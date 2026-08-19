-- Fases 3 y 4 del loop de consolidación: una sola entidad NECESIDAD que puede recibir aportes
-- parciales de varios aliados, y un único flujo de donación con dos caminos de entrada.
--
--   Donación libre       ALIADO → Nueva donación → Productos → Cantidades → Evidencias → Punto
--   Donación desde una   NECESIDAD → AYUDAR → Registrar aporte → Confirmar → Otros productos
--
-- No se crea una segunda RPC de aporte: `submit_donation_intake_v2` recibe la necesidad como un
-- parámetro más y sigue siendo el único camino expuesto para registrar una donación.
--
-- Solicitado / comprometido / pendiente **no** se guardan como contadores independientes: se
-- derivan de `donation_items`, que es donde vive el compromiso real. La proyección pública sí
-- conserva una copia, porque es una superficie de lectura y ya funcionaba así.

-- Cantidades legibles para los mensajes de la operación: 25.000 se lee «25» y 25.500 se lee
-- «25.5». Vive en un solo lugar porque lo usan el aporte, el traslado y la conciliación.
create or replace function public.format_quantity(p_quantity numeric)
returns text language sql immutable set search_path = '' as $$
  select rtrim(rtrim(to_char(coalesce(p_quantity, 0), 'FM999999990.999'), '0'), '.');
$$;

revoke all on function public.format_quantity(numeric) from public, anon, authenticated;
comment on function public.format_quantity(numeric) is
  'Cantidad sin ceros ni separador decimal sobrantes, para mensajes dirigidos a personas.';

alter table public.donation_intakes
  add column need_case_id uuid references public.need_cases(id);
alter table public.donation_intake_items
  add column need_item_id uuid references public.need_items(id);
alter table public.donation_items
  add column need_item_id uuid references public.need_items(id);
alter table public.public_need_projections
  add column committed_quantity numeric(14,3) not null default 0;

create index donation_intakes_need_case_idx
  on public.donation_intakes (need_case_id) where need_case_id is not null;
create index donation_intake_items_need_item_idx
  on public.donation_intake_items (need_item_id) where need_item_id is not null;
create index donation_items_need_item_idx
  on public.donation_items (need_item_id) where need_item_id is not null;

comment on column public.donation_intakes.need_case_id is
  'Necesidad desde la que nació el aporte cuando el aliado usó AYUDAR; nulo en la donación libre.';
comment on column public.donation_items.need_item_id is
  'Artículo de la necesidad al que se compromete esta línea; sostiene la cifra comprometida sin contador propio.';
comment on column public.public_need_projections.committed_quantity is
  'Cantidad ya comprometida por aliados. Copia de lectura derivada de donation_items.';

-- Posición de cada artículo de una necesidad, derivada y no almacenada.
create or replace view public.need_item_positions
with (security_invoker = true) as
select
  need_item.id as need_item_id,
  need_case.id as need_case_id,
  need_case.event_id,
  need_case.tracking_code,
  need_item.category,
  need_item.description,
  need_item.unit,
  need_item.quantity_required as quantity_requested,
  coalesce(commitment.promised, 0) as quantity_committed,
  coalesce(reception.received, 0) as quantity_received,
  need_item.quantity_covered as quantity_delivered,
  greatest(need_item.quantity_required - coalesce(commitment.promised, 0), 0) as quantity_pending
from public.need_items as need_item
join public.need_cases as need_case on need_case.id = need_item.need_case_id
-- El compromiso nace cuando el aliado confirma el aporte, no cuando alguien lo aprueba: si
-- se contara solo lo aprobado, dos aliados podrían comprometer la misma cantidad mientras la
-- verificación decide. Lo recibido, en cambio, solo existe tras la recepción física.
left join lateral (
  select sum(intake_item.quantity) as promised
  from public.donation_intake_items as intake_item
  join public.donation_intakes as intake on intake.id = intake_item.intake_id
  where intake_item.need_item_id = need_item.id
    and intake.status in ('reported','pending_verification','observed','approved')
) as commitment on true
left join lateral (
  select sum(donation_item.quantity_received) as received
  from public.donation_items as donation_item
  join public.donations as donation on donation.id = donation_item.donation_id
  where donation_item.need_item_id = need_item.id
    and donation.status not in ('rejected','cancelled')
) as reception on true;

grant select on public.need_item_positions to authenticated;
comment on view public.need_item_positions is
  'Solicitado, comprometido, recibido, entregado y pendiente por artículo de necesidad; todo derivado de donation_items.';

-- Contrato del camino AYUDAR: qué le falta a una necesidad publicada, sin exponer un solo
-- campo privado del caso ciudadano.
create or replace function public.need_help_options(p_projection_id uuid)
returns table(
  need_case_id uuid,
  tracking_code text,
  summary text,
  location_label text,
  need_item_id uuid,
  category text,
  description text,
  unit text,
  quantity_requested numeric,
  quantity_committed numeric,
  quantity_pending numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    need_case.id,
    need_case.tracking_code,
    projection.summary,
    projection.location_label,
    item_position.need_item_id,
    item_position.category,
    item_position.description,
    item_position.unit,
    item_position.quantity_requested,
    item_position.quantity_committed,
    item_position.quantity_pending
  from public.need_cases as need_case
  join public.public_need_projections as projection on projection.source_need_id = need_case.id
  join public.need_item_positions as item_position on item_position.need_case_id = need_case.id
  where projection.id = p_projection_id
    and projection.published
    and projection.expires_at > now()
    and (select auth.uid()) is not null
  order by item_position.category, item_position.need_item_id;
$$;

revoke all on function public.need_help_options(uuid) from public, anon, authenticated;
grant execute on function public.need_help_options(uuid) to authenticated;
comment on function public.need_help_options(uuid) is
  'Recibe el identificador de la proyección pública y devuelve los artículos pendientes de esa necesidad para el camino AYUDAR; no expone dirección, contacto ni reportante.';

-- La proyección pública conserva la cifra comprometida del artículo principal, igual que ya
-- conservaba la solicitada y la cubierta.
create or replace function public.sync_need_commitment_projection(p_need_case_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  need_position record;
begin
  select * into need_position
  from public.need_item_positions as candidate
  where candidate.need_case_id = p_need_case_id
  order by candidate.need_item_id
  limit 1;
  if need_position.need_item_id is null then
    return;
  end if;
  update public.public_need_projections
  set committed_quantity = need_position.quantity_committed,
      covered_quantity = need_position.quantity_delivered,
      updated_at = now()
  where source_need_id = p_need_case_id;
end;
$$;

create or replace function public.sync_need_commitment_trigger()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  touched uuid;
  affected uuid;
begin
  -- En un disparador AFTER DELETE la fila NEW no existe, así que el artículo se toma del
  -- registro que corresponda a la operación y el disparador no devuelve fila.
  if tg_op = 'DELETE' then
    touched := old.need_item_id;
  else
    touched := new.need_item_id;
  end if;
  if touched is null then
    return null;
  end if;
  select need_item.need_case_id into affected
  from public.need_items as need_item
  where need_item.id = touched;
  if affected is not null then
    perform public.sync_need_commitment_projection(affected);
  end if;
  return null;
end;
$$;

-- El compromiso cambia al registrar el aporte y lo recibido cambia al conciliar la recepción:
-- las dos tablas alimentan la misma proyección con el mismo disparador.
create trigger donation_intake_items_need_commitment
after insert or update or delete on public.donation_intake_items
for each row execute function public.sync_need_commitment_trigger();

create trigger donation_items_need_commitment
after insert or update or delete on public.donation_items
for each row execute function public.sync_need_commitment_trigger();

create or replace function public.submit_donation_intake_v2(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric,
  p_preferred_location_id uuid,
  p_reporting_context jsonb,
  p_catalog_versions jsonb,
  p_declared_category_code text,
  p_need_case_id uuid
)
returns table(
  intake_id uuid,
  tracking_code text,
  status public.intake_status,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  submitted record;
  existing public.donation_intakes;
  center public.inventory_locations;
  item jsonb;
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  expected_versions jsonb := public.current_donation_catalog_versions();
  canonical_fingerprint text;
  legacy_status text;
  legacy_donor_type text;
  legacy_context jsonb;
  legacy_items jsonb := '[]'::jsonb;
  acceptance_decision text;
  need_case public.need_cases;
  need_item public.need_items;
  linked_need_item uuid;
  pending_quantity numeric;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión como aliado';
  end if;
  if not public.has_any_role(
    p_organization_id,
    p_event_id,
    array['partner_reporter','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No perteneces al aliado indicado';
  end if;
  if not exists (
    select 1 from public.organizations as organization
    where organization.id = p_organization_id
      and organization.verified
      and organization.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'La organización debe estar activa y verificada';
  end if;
  if jsonb_typeof(coalesce(p_catalog_versions, 'null'::jsonb)) <> 'object'
     or p_catalog_versions is distinct from expected_versions then
    raise exception using errcode = '22023', message = 'Los catálogos cambiaron; actualiza la página antes de continuar';
  end if;
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;
  if not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'declared_donation_statuses'
      and option.value ->> 'value' = p_declared_status
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un estado declarado vigente';
  end if;
  if nullif(context ->> 'donor_type', '') is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'donor_types'
      and option.value ->> 'value' = context ->> 'donor_type'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante vigente';
  end if;
  if nullif(context ->> 'economic_sector', '') is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'economic_sectors'
      and option.value ->> 'value' = context ->> 'economic_sector'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un sector económico vigente';
  end if;
  if coalesce((context ->> 'specific_destination')::boolean, false) and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements_text(catalog.values_json) as department(value)
    where catalog.key = 'departments'
      and department.value = context ->> 'destination_department'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un departamento vigente';
  end if;

  if p_kind = 'money' then
    if p_declared_category_code <> 'apoyo_economico_recursos' or not exists (
      select 1
      from public.donation_flow_catalogs() as catalog,
        jsonb_array_elements(catalog.values_json) as option(value)
      where catalog.key = 'donation_categories'
        and option.value ->> 'value' = p_declared_category_code
        and option.value ->> 'kind' = 'money'
    ) then
      raise exception using errcode = '22023', message = 'Selecciona una categoría económica vigente';
    end if;
  else
    select * into center
    from public.inventory_locations as location
    where location.id = p_preferred_location_id
      and location.event_id = p_event_id
      and location.active;
    if center.id is null then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega activo';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) not between 1 and 20 then
      raise exception using errcode = '22023', message = 'Agrega entre 1 y 20 artículos';
    end if;

    for item in select value from jsonb_array_elements(p_items)
    loop
      if not exists (
        select 1
        from public.donation_flow_catalogs() as catalog,
          jsonb_array_elements(catalog.values_json) as option(value)
        where catalog.key = 'donation_categories'
          and option.value ->> 'value' = item ->> 'category_code'
          and option.value ->> 'kind' = 'in_kind'
          and option.value ->> 'parent_category' = item ->> 'category'
      ) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una categoría detallada vigente';
      end if;
      if not exists (
        select 1
        from public.donation_flow_catalogs() as catalog,
          jsonb_array_elements_text(catalog.values_json) as unit(value)
        where catalog.key = 'units' and unit.value = item ->> 'unit'
      ) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una unidad vigente';
      end if;
      if item ->> 'storage_requirement' = 'frio' and not center.cold_chain_capable then
        raise exception using errcode = '22023', message = 'El centro seleccionado no tiene cadena de frío';
      end if;

      select rule.decision into acceptance_decision
      from public.item_acceptance_rules as rule
      where rule.organization_id = center.organization_id
        and rule.event_id = center.event_id
        and rule.category = item ->> 'category'
        and (rule.location_id = center.id or rule.location_id is null)
        and rule.effective_from <= now()
        and (rule.effective_to is null or rule.effective_to > now())
      order by (rule.location_id = center.id) desc, rule.version desc
      limit 1;
      if acceptance_decision is distinct from 'accepted' then
        raise exception using errcode = '22023', message = 'El centro seleccionado no recibe una de las categorías indicadas';
      end if;
      acceptance_decision := null;
    end loop;
  end if;

  -- Fase 4: la donación puede nacer libre o desde una necesidad. Cuando nace desde una
  -- necesidad, cada artículo vinculado tiene que caber en lo que todavía falta: se aceptan
  -- aportes parciales de varios aliados, no sobreasignación.
  if p_need_case_id is not null then
    if p_kind <> 'in_kind' then
      raise exception using errcode = '22023', message = 'Un aporte económico no se registra contra una necesidad puntual';
    end if;
    select * into need_case from public.need_cases as candidate where candidate.id = p_need_case_id;
    if need_case.id is null or need_case.event_id <> p_event_id then
      raise exception using errcode = '22023', message = 'La necesidad indicada no pertenece a este evento';
    end if;
    if need_case.status not in ('published','partially_covered') then
      raise exception using errcode = '22023', message = 'Solo puedes aportar a una necesidad publicada';
    end if;

    for item in select value from jsonb_array_elements(p_items)
    loop
      linked_need_item := nullif(item ->> 'need_item_id', '')::uuid;
      if linked_need_item is null then
        continue;
      end if;
      -- El bloqueo del artículo serializa dos aportes simultáneos contra lo mismo pendiente.
      select * into need_item
      from public.need_items as candidate
      where candidate.id = linked_need_item and candidate.need_case_id = need_case.id
      for update;
      if need_item.id is null then
        raise exception using errcode = '22023', message = 'Uno de los artículos no corresponde a esta necesidad';
      end if;
      if need_item.category is distinct from (item ->> 'category')
         or need_item.unit is distinct from (item ->> 'unit') then
        raise exception using errcode = '22023',
          message = 'La categoría y la unidad del aporte deben coincidir con las de la necesidad';
      end if;
      select greatest(need_item.quantity_required - coalesce(sum(intake_item.quantity), 0), 0)
      into pending_quantity
      from public.donation_intake_items as intake_item
      join public.donation_intakes as intake on intake.id = intake_item.intake_id
      where intake_item.need_item_id = need_item.id
        and intake.status in ('reported','pending_verification','observed','approved');
      if (item ->> 'quantity')::numeric > pending_quantity then
        raise exception using errcode = '22023',
          message = format('A esa necesidad solo le faltan %s %s', public.format_quantity(pending_quantity), need_item.unit);
      end if;
    end loop;
  end if;

  canonical_fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'event_id', p_event_id,
        'need_case_id', p_need_case_id,
        'organization_id', p_organization_id,
        'kind', p_kind,
        'donor_name_private', btrim(p_donor_name_private),
        'contact_private', p_contact_private,
        'attribution_kind', p_attribution_kind,
        'public_attribution', p_public_attribution,
        'attribution_authorized', coalesce(p_attribution_authorized, false),
        'declared_status', p_declared_status,
        'declared_category_code', p_declared_category_code,
        'items', coalesce(p_items, '[]'::jsonb),
        'declared_amount', p_declared_amount,
        'preferred_location_id', p_preferred_location_id,
        'reporting_context', context,
        'catalog_versions', p_catalog_versions
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  select * into existing
  from public.donation_intakes as intake
  where intake.organization_id = p_organization_id
    and intake.idempotency_key = p_idempotency_key;
  if existing.id is not null then
    if existing.catalog_fingerprint is distinct from canonical_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select existing.id, existing.tracking_code, existing.status, true;
    return;
  end if;

  legacy_status := case p_declared_status
    when 'en_gestion' then 'comprometida'
    when 'entregada' then 'entregada_por_validar'
    else p_declared_status
  end;
  legacy_donor_type := case context ->> 'donor_type'
    when 'persona_natural' then 'persona'
    when 'gremio_asociacion' then 'gremio'
    when 'fundacion_empresarial' then 'fundacion'
    when 'cooperativa' then 'otro'
    when 'entidad_publica' then 'otro'
    else nullif(context ->> 'donor_type', '')
  end;
  legacy_context := jsonb_set(context, '{donor_type}', to_jsonb(coalesce(legacy_donor_type, '')));

  if p_kind = 'in_kind' then
    select coalesce(jsonb_agg(
      case
        when value ->> 'category' in ('Logística','Otro')
          then jsonb_set(value, '{category}', to_jsonb('Refugio'::text))
        else value
      end order by ordinality
    ), '[]'::jsonb)
    into legacy_items
    from jsonb_array_elements(p_items) with ordinality as supplied(value, ordinality);
  end if;

  select * into submitted
  from public.submit_donation_intake(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    legacy_status,
    legacy_items,
    p_declared_amount,
    p_preferred_location_id,
    legacy_context
  );

  if submitted.was_duplicate then
    select * into existing
    from public.donation_intakes as intake
    where intake.id = submitted.intake_id
    for update;
    if existing.catalog_fingerprint is distinct from canonical_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select existing.id, existing.tracking_code, existing.status, true;
    return;
  end if;

  update public.donation_intakes
  set declared_status = p_declared_status,
      donor_type = nullif(context ->> 'donor_type', ''),
      economic_sector = nullif(context ->> 'economic_sector', ''),
      declared_category_code = p_declared_category_code,
      catalog_versions = p_catalog_versions,
      catalog_fingerprint = canonical_fingerprint,
      need_case_id = p_need_case_id
  where id = submitted.intake_id;

  if p_kind = 'in_kind' then
    with supplied as (
      select ordinality::integer as position,
        value ->> 'category' as category,
        value ->> 'category_code' as category_code,
        nullif(value ->> 'need_item_id', '')::uuid as need_item_id
      from jsonb_array_elements(p_items) with ordinality as valueset(value, ordinality)
    ), persisted as (
      select stored.id, row_number() over (order by stored.created_at, stored.id)::integer as position
      from public.donation_intake_items as stored
      where stored.intake_id = submitted.intake_id
    )
    update public.donation_intake_items as intake_item
    set category = supplied.category,
        category_code = supplied.category_code,
        need_item_id = supplied.need_item_id
    from supplied
    join persisted using (position)
    where intake_item.id = persisted.id;
  end if;

  return query
  select submitted.intake_id, submitted.tracking_code, submitted.status, false;
end;
$$;
-- `submit_donation_intake_v2` deja de tener dos firmas posibles: la de dieciséis parámetros se
-- retira y la nueva exige el vínculo con la necesidad (nulo cuando la donación es libre).
drop function if exists public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text
);

create or replace function public.review_donation_intake(p_intake_id uuid, p_decision text, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake public.donation_intakes;
  donation_id uuid;
begin
  select * into intake from public.donation_intakes where id = p_intake_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Ingreso no encontrado'; end if;
  if not public.has_event_role(intake.event_id, array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes verificar este ingreso';
  end if;
  if intake.status not in ('reported','pending_verification','observed') then
    raise exception using errcode = '22023', message = 'El ingreso no admite esta transición';
  end if;
  if p_decision not in ('approve','observe','reject','duplicate','quarantine','cancel') then
    raise exception using errcode = '22023', message = 'Decisión inválida';
  end if;

  insert into public.intake_verification_decisions(intake_id, decision, note, decided_by)
  values (p_intake_id, p_decision, trim(p_note), (select auth.uid()));
  update public.donation_intakes set status = case p_decision
    when 'approve' then 'approved'::public.intake_status
    when 'observe' then 'observed'::public.intake_status
    when 'reject' then 'rejected'::public.intake_status
    when 'duplicate' then 'duplicate'::public.intake_status
    when 'quarantine' then 'quarantined'::public.intake_status
    else 'cancelled'::public.intake_status end
  where id = p_intake_id;

  if p_decision = 'approve' then
    insert into public.donations(intake_id, event_id, organization_id, kind, status)
    values (intake.id, intake.event_id, intake.organization_id, intake.kind, 'promised')
    on conflict (intake_id) do update set updated_at = public.donations.updated_at
    returning id into donation_id;
    insert into public.donation_items(
      donation_id, source_intake_item_id, need_item_id, category, category_code,
      description, quantity_promised, unit
    )
    select donation_id, item.id, item.need_item_id, item.category, item.category_code,
      item.description, item.quantity, item.unit
    from public.donation_intake_items as item
    where item.intake_id = intake.id
      and not exists (
        select 1 from public.donation_items as donation_item
        where donation_item.source_intake_item_id = item.id
      );
  end if;
  return donation_id;
end;
$$;

revoke all on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text, uuid
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text, uuid
) to authenticated;
comment on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text, uuid
) is
  'Único registro de aporte: valida membresía, aliado verificado, catálogos, centro y, cuando viene de AYUDAR, que el aporte quepa en lo pendiente de la necesidad.';

comment on function public.review_donation_intake(uuid, text, text) is
  'Aprueba o rechaza un aporte; al aprobar traslada el vínculo con la necesidad a la donación operacional.';

-- El mapa público entrega también lo comprometido. El identificador que viaja hacia AYUDAR es
-- el de la proyección, no el de la necesidad operacional: la capa geoespacial pública sigue sin
-- exponer identificadores internos.
drop function if exists public.public_need_map(uuid, double precision, double precision, double precision, double precision);

create or replace function public.public_need_map(
  p_event_id uuid,
  p_min_longitude double precision default null,
  p_min_latitude double precision default null,
  p_max_longitude double precision default null,
  p_max_latitude double precision default null
)
returns table(
  id uuid,
  category text,
  summary text,
  location_label text,
  status text,
  needed_quantity numeric,
  committed_quantity numeric,
  covered_quantity numeric,
  unit text,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    projection.id,
    projection.category,
    projection.summary,
    projection.location_label,
    projection.status,
    projection.needed_quantity,
    projection.committed_quantity,
    projection.covered_quantity,
    projection.unit,
    extensions.st_y(projection.approximate_location),
    extensions.st_x(projection.approximate_location),
    projection.updated_at
  from public.public_need_projections as projection
  where projection.event_id = p_event_id
    and projection.published
    and projection.expires_at > now()
    and projection.approximate_location is not null
    and (
      p_min_longitude is null
      or p_min_latitude is null
      or p_max_longitude is null
      or p_max_latitude is null
      or extensions.st_intersects(
        projection.approximate_location,
        extensions.st_makeenvelope(
          p_min_longitude,
          p_min_latitude,
          p_max_longitude,
          p_max_latitude,
          4326
        )
      )
    )
  order by projection.updated_at desc;
$$;

grant execute on function public.public_need_map(uuid, double precision, double precision, double precision, double precision)
  to anon, authenticated;
comment on function public.public_need_map(uuid, double precision, double precision, double precision, double precision) is
  'Necesidades públicas vigentes con coordenada aproximada y cantidad comprometida; no expone identificadores operacionales.';
