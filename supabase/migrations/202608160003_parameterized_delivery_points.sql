-- Administración parametrizada de puntos de entrega.
-- Las direcciones exactas permanecen privadas; la superficie pública usa zona y coordenadas aproximadas.

alter table public.inventory_locations
  add column if not exists public_instructions text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.inventory_locations
  add constraint inventory_locations_name_length check (char_length(btrim(name)) between 3 and 120),
  add constraint inventory_locations_public_location_length check (char_length(btrim(public_location_text)) between 3 and 180),
  add constraint inventory_locations_exact_address_length check (exact_address_private is null or char_length(btrim(exact_address_private)) between 5 and 300),
  add constraint inventory_locations_public_instructions_length check (public_instructions is null or char_length(btrim(public_instructions)) between 3 and 500),
  add constraint inventory_locations_public_latitude_range check (public_latitude is null or public_latitude between -4.5 and 13.5),
  add constraint inventory_locations_public_longitude_range check (public_longitude is null or public_longitude between -82 and -66.5);

create trigger inventory_locations_updated_at
before update on public.inventory_locations
for each row execute function public.set_updated_at();

create table public.delivery_point_changes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  location_id uuid not null references public.inventory_locations(id),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create index delivery_point_changes_event_idx on public.delivery_point_changes(event_id);
create index delivery_point_changes_location_idx on public.delivery_point_changes(location_id);
create index delivery_point_changes_actor_idx on public.delivery_point_changes(actor_id);
alter table public.delivery_point_changes enable row level security;

create trigger delivery_point_changes_immutable
before update or delete on public.delivery_point_changes
for each row execute function public.prevent_mutation();
create trigger delivery_point_changes_audit
after insert on public.delivery_point_changes
for each row execute function public.audit_row_change();

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'item_acceptance_rules_audit'
      and tgrelid = 'public.item_acceptance_rules'::regclass
  ) then
    create trigger item_acceptance_rules_audit
    after insert or update or delete on public.item_acceptance_rules
    for each row execute function public.audit_row_change();
  end if;
end $$;

create or replace function public.manage_delivery_point(
  p_location_id uuid,
  p_event_id uuid,
  p_organization_id uuid,
  p_name text,
  p_public_location_text text,
  p_exact_address_private text,
  p_public_instructions text,
  p_public_latitude numeric,
  p_public_longitude numeric,
  p_cold_chain_capable boolean,
  p_active boolean,
  p_accepted_categories text[],
  p_idempotency_key text
)
returns table(location_id uuid, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target public.inventory_locations;
  existing_change public.delivery_point_changes;
  request_fingerprint text;
  category_name text;
  next_version integer;
begin
  if actor_id is null or not public.has_event_role(p_event_id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo administración del evento puede parametrizar puntos de entrega';
  end if;
  if not exists (
    select 1 from public.organizations as organization
    where organization.id = p_organization_id
      and organization.verified
      and organization.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona una organización activa y verificada';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 3 and 120 then
    raise exception using errcode = '22023', message = 'Escribe un nombre del punto entre 3 y 120 caracteres';
  end if;
  if char_length(btrim(coalesce(p_public_location_text, ''))) not between 3 and 180 then
    raise exception using errcode = '22023', message = 'Describe públicamente la ciudad y zona aproximada';
  end if;
  if char_length(btrim(coalesce(p_exact_address_private, ''))) not between 5 and 300 then
    raise exception using errcode = '22023', message = 'Registra la dirección exacta privada del punto';
  end if;
  if nullif(btrim(coalesce(p_public_instructions, '')), '') is not null
     and char_length(btrim(p_public_instructions)) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'Las instrucciones públicas deben tener entre 3 y 500 caracteres';
  end if;
  if p_public_latitude is null or p_public_latitude not between -4.5 and 13.5
     or p_public_longitude is null or p_public_longitude not between -82 and -66.5 then
    raise exception using errcode = '22023', message = 'Registra coordenadas aproximadas válidas dentro de Colombia';
  end if;
  if char_length(coalesce(p_idempotency_key, '')) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'La clave idempotente no es válida';
  end if;
  if cardinality(coalesce(p_accepted_categories, '{}'::text[])) not between 1 and 8 then
    raise exception using errcode = '22023', message = 'Selecciona entre 1 y 8 categorías aceptadas';
  end if;
  if exists (
    select 1
    from unnest(p_accepted_categories) as supplied(category)
    where not exists (
      select 1
      from public.donation_flow_catalogs() as catalog,
        jsonb_array_elements(catalog.values_json) as option(value)
      where catalog.key = 'donation_categories'
        and option.value ->> 'kind' = 'in_kind'
        and option.value ->> 'parent_category' = supplied.category
    )
  ) then
    raise exception using errcode = '22023', message = 'Una categoría aceptada no pertenece al catálogo vigente';
  end if;

  request_fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'location_id', p_location_id,
        'event_id', p_event_id,
        'organization_id', p_organization_id,
        'name', btrim(p_name),
        'public_location_text', btrim(p_public_location_text),
        'exact_address_private', btrim(p_exact_address_private),
        'public_instructions', nullif(btrim(coalesce(p_public_instructions, '')), ''),
        'public_latitude', p_public_latitude,
        'public_longitude', p_public_longitude,
        'cold_chain_capable', coalesce(p_cold_chain_capable, false),
        'active', coalesce(p_active, false),
        'accepted_categories', to_jsonb(p_accepted_categories)
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || p_idempotency_key, 0));
  select * into existing_change
  from public.delivery_point_changes
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if existing_change.id is not null then
    if existing_change.request_fingerprint is distinct from request_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con otros parámetros';
    end if;
    return query select existing_change.location_id, true;
    return;
  end if;

  if p_location_id is null then
    insert into public.inventory_locations(
      event_id, organization_id, name, public_location_text, exact_address_private,
      public_instructions, public_latitude, public_longitude, cold_chain_capable, active
    ) values (
      p_event_id, p_organization_id, btrim(p_name), btrim(p_public_location_text),
      btrim(p_exact_address_private), nullif(btrim(coalesce(p_public_instructions, '')), ''),
      p_public_latitude, p_public_longitude, coalesce(p_cold_chain_capable, false), coalesce(p_active, false)
    ) returning * into target;
  else
    select * into target
    from public.inventory_locations
    where id = p_location_id
      and event_id = p_event_id
      and organization_id = p_organization_id
    for update;
    if target.id is null then
      raise exception using errcode = '22023', message = 'El punto no pertenece al evento y organización indicados';
    end if;
    update public.inventory_locations
    set name = btrim(p_name),
        public_location_text = btrim(p_public_location_text),
        exact_address_private = btrim(p_exact_address_private),
        public_instructions = nullif(btrim(coalesce(p_public_instructions, '')), ''),
        public_latitude = p_public_latitude,
        public_longitude = p_public_longitude,
        cold_chain_capable = coalesce(p_cold_chain_capable, false),
        active = coalesce(p_active, false)
    where id = target.id
    returning * into target;
  end if;

  for category_name in
    select distinct option.value ->> 'parent_category'
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'donation_categories'
      and option.value ->> 'kind' = 'in_kind'
      and option.value ->> 'parent_category' is not null
    order by 1
  loop
    update public.item_acceptance_rules as rule
    set effective_to = now()
    where rule.organization_id = target.organization_id
      and rule.event_id = target.event_id
      and rule.location_id = target.id
      and rule.category = category_name
      and rule.effective_to is null;

    select coalesce(max(version), 0) + 1 into next_version
    from public.item_acceptance_rules as rule
    where rule.organization_id = target.organization_id
      and rule.event_id = target.event_id
      and rule.category = category_name;

    insert into public.item_acceptance_rules(
      organization_id, event_id, location_id, category, decision, rule_text,
      requires_cold_chain, version, effective_from
    ) values (
      target.organization_id, target.event_id, target.id, category_name,
      case when category_name = any(p_accepted_categories) then 'accepted' else 'prohibited' end,
      case when category_name = any(p_accepted_categories)
        then 'Categoría habilitada en la parametrización vigente del punto.'
        else 'Categoría no habilitada en la parametrización vigente del punto.'
      end,
      false, next_version, now()
    );
  end loop;

  insert into public.delivery_point_changes(
    event_id, organization_id, location_id, idempotency_key, request_fingerprint, actor_id
  ) values (
    target.event_id, target.organization_id, target.id, p_idempotency_key, request_fingerprint, actor_id
  );

  return query select target.id, false;
end;
$$;

create or replace function public.delivery_points_admin(p_event_id uuid)
returns table(
  id uuid,
  organization_id uuid,
  organization_name text,
  name text,
  public_location_text text,
  exact_address_private text,
  public_instructions text,
  public_latitude numeric,
  public_longitude numeric,
  cold_chain_capable boolean,
  active boolean,
  accepted_categories text[],
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not public.has_event_role(p_event_id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo administración del evento puede consultar la parametrización';
  end if;

  return query
  with current_rules as (
    select distinct on (rule.location_id, rule.category)
      rule.location_id, rule.category, rule.decision
    from public.item_acceptance_rules as rule
    where rule.event_id = p_event_id
      and rule.location_id is not null
      and rule.effective_from <= now()
      and (rule.effective_to is null or rule.effective_to > now())
    order by rule.location_id, rule.category, rule.version desc
  )
  select
    location.id,
    location.organization_id,
    organization.name,
    location.name,
    location.public_location_text,
    location.exact_address_private,
    location.public_instructions,
    location.public_latitude,
    location.public_longitude,
    location.cold_chain_capable,
    location.active,
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    location.updated_at
  from public.inventory_locations as location
  join public.organizations as organization on organization.id = location.organization_id
  left join current_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
  group by location.id, organization.name
  order by location.active desc, organization.name, location.name;
end;
$$;

revoke all on function public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,text[],text) from public, anon, authenticated;
revoke all on function public.delivery_points_admin(uuid) from public, anon, authenticated;
grant execute on function public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,text[],text) to authenticated;
grant execute on function public.delivery_points_admin(uuid) to authenticated;

-- Un punto de otra organización no puede dejar el aporte en un callejón sin salida.
-- La función interna v1 conserva toda la validación de catálogo; esta restricción se
-- aplica antes de invocarla desde el contrato público vigente.
create or replace function public.assert_delivery_point_tenant(
  p_location_id uuid,
  p_event_id uuid,
  p_organization_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_location_id is not null and not exists (
    select 1 from public.inventory_locations as location
    where location.id = p_location_id
      and location.event_id = p_event_id
      and location.organization_id = p_organization_id
      and location.active
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un punto de entrega activo de tu organización';
  end if;
end;
$$;

revoke all on function public.assert_delivery_point_tenant(uuid,uuid,uuid) from public, anon, authenticated;

create or replace function public.organization_delivery_points(
  p_event_id uuid,
  p_organization_id uuid
)
returns table(
  id uuid,
  name text,
  location_label text,
  public_instructions text,
  accepts text[],
  restricted_items text[],
  cold_chain_capable boolean,
  latitude double precision,
  longitude double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_any_role(
       p_organization_id,
       p_event_id,
       array['partner_reporter','event_admin']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No puedes consultar los puntos de esta organización';
  end if;

  return query
  with current_rules as (
    select distinct on (
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category
    )
      rule.organization_id, rule.event_id, rule.location_id, rule.category, rule.decision
    from public.item_acceptance_rules as rule
    where rule.organization_id = p_organization_id
      and rule.event_id = p_event_id
      and rule.effective_from <= now()
      and (rule.effective_to is null or rule.effective_to > now())
    order by
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category,
      rule.version desc
  ), applicable_rules as (
    select location.id as location_id, rule.category, rule.decision
    from public.inventory_locations as location
    join current_rules as rule
      on rule.organization_id = location.organization_id
      and rule.event_id = location.event_id
      and (
        rule.location_id = location.id
        or (
          rule.location_id is null
          and not exists (
            select 1 from current_rules as override
            where override.organization_id = location.organization_id
              and override.event_id = location.event_id
              and override.location_id = location.id
              and override.category = rule.category
          )
        )
      )
  )
  select
    location.id,
    location.name,
    location.public_location_text,
    location.public_instructions,
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
    and location.organization_id = p_organization_id
    and location.active
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
end;
$$;

revoke all on function public.organization_delivery_points(uuid,uuid) from public, anon, authenticated;
grant execute on function public.organization_delivery_points(uuid,uuid) to authenticated;

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
  p_declared_category_code text
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
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  reporting_ally text;
  submitted record;
begin
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;

  reporting_ally := nullif(btrim(context ->> 'reporting_ally'), '');
  if reporting_ally is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'reporting_allies'
      and option.value ->> 'value' = reporting_ally
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un aliado de referencia vigente';
  end if;
  if reporting_ally = 'otro' and char_length(btrim(coalesce(context ->> 'observations', ''))) < 3 then
    raise exception using errcode = '22023', message = 'Especifica el otro aliado en Observaciones';
  end if;

  if p_kind = 'in_kind' then
    perform public.assert_delivery_point_tenant(
      p_preferred_location_id,
      p_event_id,
      p_organization_id
    );
  end if;

  select * into submitted
  from public.submit_donation_intake_v2_catalogs_v1(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    p_declared_status,
    p_items,
    p_declared_amount,
    p_preferred_location_id,
    context,
    p_catalog_versions,
    p_declared_category_code
  );

  update public.donation_intakes
  set reporting_ally_code = reporting_ally
  where id = submitted.intake_id
    and reporting_ally_code is distinct from reporting_ally;

  return query
  select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

revoke all on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) to authenticated;

comment on function public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,text[],text) is
  'Crea o actualiza un punto de entrega con categorías versionadas, idempotencia y auditoría; solo event_admin.';
comment on function public.delivery_points_admin(uuid) is
  'Vista administrativa privada de puntos activos/inactivos, dirección exacta y categorías vigentes.';
comment on function public.organization_delivery_points(uuid,uuid) is
  'Puntos activos y reglas vigentes limitados a la organización autenticada que registra el aporte.';
comment on column public.inventory_locations.public_instructions is
  'Instrucciones públicas seguras; nunca debe contener dirección exacta, teléfonos personales ni PII.';
