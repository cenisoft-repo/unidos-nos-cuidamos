-- Alineación del registro de aportes con el recorrido funcional auditado.
-- Los datos declarados siguen siendo privados hasta que exista evidencia validada.

alter table public.donation_intakes
  add column request_fingerprint text;

update public.donation_intakes
set request_fingerprint = encode(
  extensions.digest(('legacy:' || id::text)::bytea, 'sha256'),
  'hex'
)
where request_fingerprint is null;

update public.donation_intakes
set declared_status = 'comprometida'
where declared_status is null
   or declared_status not in ('comprometida', 'en_transito', 'entregada_por_validar');

alter table public.donation_intakes
  alter column request_fingerprint set not null,
  alter column declared_status set not null,
  add constraint donation_intakes_request_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint donation_intakes_donor_name_check
    check (char_length(btrim(donor_name_private)) between 2 and 160),
  add constraint donation_intakes_contact_object_check
    check (jsonb_typeof(contact_private) = 'object'),
  add constraint donation_intakes_declared_status_check
    check (declared_status in ('comprometida', 'en_transito', 'entregada_por_validar'));

alter table public.donation_intake_items
  add constraint donation_intake_items_category_check
    check (category = any (array['Agua', 'Alimentos', 'Higiene', 'Refugio', 'Salud', 'Protección']::text[])),
  add constraint donation_intake_items_description_check
    check (char_length(btrim(description)) between 3 and 500),
  add constraint donation_intake_items_unit_check
    check (unit = any (array['unidad', 'litro', 'kilogramo', 'kit', 'caja']::text[])),
  add constraint donation_intake_items_declared_value_check
    check (declared_estimated_value_cop is null or declared_estimated_value_cop > 0);

alter table public.public_donation_projections
  add column donation_item_id uuid references public.donation_items(id);

update public.public_donation_projections as projection
set donation_item_id = (
  select item.id
  from public.donation_items as item
  where item.donation_id = projection.donation_id
  order by item.created_at, item.id
  limit 1
)
where projection.verified_quantity is not null;

alter table public.public_donation_projections
  drop constraint if exists public_donation_projections_donation_id_key,
  add constraint public_donation_projections_donation_item_key unique (donation_item_id);

create index public_donation_projections_donation_id_idx
  on public.public_donation_projections (donation_id);

create unique index public_donation_projections_money_donation_key
  on public.public_donation_projections (donation_id)
  where donation_item_id is null;

alter table public.financial_transactions
  add column donation_id uuid references public.donations(id);

create unique index financial_transactions_donation_id_key
  on public.financial_transactions (donation_id)
  where donation_id is not null;

create or replace function public.submit_donation_intake(
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
  p_reporting_context jsonb
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
  created public.donation_intakes;
  item jsonb;
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  wants_destination boolean;
  beneficiary_count integer;
  public_name text;
  organization_name text;
  contact_email text;
  contact_phone text;
  internal_contact jsonb;
  fingerprint text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión como aliado';
  end if;
  if not public.has_any_role(
    p_organization_id,
    p_event_id,
    array['partner_reporter', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No perteneces al aliado indicado';
  end if;
  if not exists (
    select 1
    from public.emergency_events as event
    where event.id = p_event_id and event.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'El evento no está disponible para aportes';
  end if;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = p_organization_id;

  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;
  if char_length(btrim(coalesce(p_donor_name_private, ''))) not between 2 and 160 then
    raise exception using errcode = '22023', message = 'Escribe el nombre del donante';
  end if;
  if jsonb_typeof(coalesce(p_contact_private, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto privado debe ser un objeto';
  end if;

  contact_email := lower(btrim(coalesce(p_contact_private ->> 'email', '')));
  contact_phone := btrim(coalesce(p_contact_private ->> 'phone', ''));
  if contact_email !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$' then
    raise exception using errcode = '22023', message = 'Escribe un correo de coordinación válido';
  end if;
  if contact_phone <> '' and char_length(contact_phone) not between 7 and 30 then
    raise exception using errcode = '22023', message = 'El teléfono de coordinación no es válido';
  end if;

  if p_attribution_kind not in ('organization', 'authorized_name', 'alias', 'anonymous') then
    raise exception using errcode = '22023', message = 'Selecciona una atribución pública válida';
  end if;
  if p_attribution_kind = 'anonymous' then
    public_name := null;
  elsif p_attribution_kind = 'organization' then
    public_name := organization_name;
  else
    if p_attribution_kind = 'authorized_name' and not coalesce(p_attribution_authorized, false) then
      raise exception using errcode = '22023', message = 'La atribución personal exige autorización expresa';
    end if;
    if char_length(btrim(coalesce(p_public_attribution, ''))) not between 2 and 120 then
      raise exception using errcode = '22023', message = 'Escribe una atribución pública válida';
    end if;
    public_name := btrim(p_public_attribution);
  end if;

  if p_declared_status not in ('comprometida', 'en_transito', 'entregada_por_validar') then
    raise exception using errcode = '22023', message = 'Selecciona un estado declarado válido';
  end if;
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;

  wants_destination := coalesce((context ->> 'specific_destination')::boolean, false);
  beneficiary_count := nullif(context ->> 'estimated_beneficiaries', '')::integer;
  internal_contact := coalesce(context -> 'internal_contact', '{}'::jsonb);

  if nullif(context ->> 'donor_type', '') is not null
     and context ->> 'donor_type' not in ('persona', 'empresa', 'gremio', 'fundacion', 'otro') then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante válido';
  end if;
  if nullif(btrim(coalesce(context ->> 'economic_sector', '')), '') is not null
     and char_length(btrim(context ->> 'economic_sector')) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'El sector económico no es válido';
  end if;
  if wants_destination and (
    char_length(btrim(coalesce(context ->> 'destination_department', ''))) < 2
    or char_length(btrim(coalesce(context ->> 'destination_municipality', ''))) < 2
  ) then
    raise exception using errcode = '22023', message = 'La destinación específica requiere departamento y municipio o zona';
  end if;
  if beneficiary_count is not null and beneficiary_count <= 0 then
    raise exception using errcode = '22023', message = 'Los beneficiarios estimados deben ser mayores que cero';
  end if;
  if jsonb_typeof(internal_contact) <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto interno debe ser un objeto';
  end if;
  if char_length(coalesce(context ->> 'destination_note', '')) > 240
     or char_length(coalesce(context ->> 'destination_municipality', '')) > 140
     or char_length(coalesce(context ->> 'delivery_channel', '')) > 160
     or char_length(coalesce(context ->> 'internal_responsible', '')) > 160
     or char_length(coalesce(context ->> 'observations', '')) > 2000
     or char_length(coalesce(internal_contact ->> 'value', '')) > 180 then
    raise exception using errcode = '22023', message = 'Uno de los campos privados excede el tamaño permitido';
  end if;

  if p_kind = 'money' then
    if p_declared_amount is null or p_declared_amount <= 0 then
      raise exception using errcode = '22023', message = 'El monto declarado debe ser mayor que cero';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) <> 0 then
      raise exception using errcode = '22023', message = 'El aporte monetario no debe incluir artículos';
    end if;
  else
    if p_declared_amount is not null then
      raise exception using errcode = '22023', message = 'El aporte en especie no usa un monto global';
    end if;
    if p_preferred_location_id is null or not exists (
      select 1
      from public.inventory_locations as location
      where location.id = p_preferred_location_id
        and location.event_id = p_event_id
        and location.active
    ) then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega válido';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) not between 1 and 20 then
      raise exception using errcode = '22023', message = 'Agrega entre 1 y 20 artículos';
    end if;

    for item in select value from jsonb_array_elements(p_items)
    loop
      if item ->> 'category' is null
         or item ->> 'category' <> all (array['Agua', 'Alimentos', 'Higiene', 'Refugio', 'Salud', 'Protección']::text[]) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una categoría válida';
      end if;
      if char_length(btrim(coalesce(item ->> 'description', ''))) not between 3 and 500 then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una descripción válida';
      end if;
      if coalesce((item ->> 'quantity')::numeric, 0) <= 0 then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una cantidad positiva';
      end if;
      if item ->> 'unit' is null
         or item ->> 'unit' <> all (array['unidad', 'litro', 'kilogramo', 'kit', 'caja']::text[]) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una unidad válida';
      end if;
      if coalesce(item ->> 'condition', '') not in ('sellado', 'nuevo') then
        raise exception using errcode = '22023', message = 'No se aceptan artículos abiertos o vencidos';
      end if;
      if coalesce(item ->> 'storage_requirement', '') not in ('ambiente', 'frio', 'seco') then
        raise exception using errcode = '22023', message = 'Selecciona un cuidado de almacenamiento válido';
      end if;
      if nullif(item ->> 'expires_on', '')::date is not null
         and nullif(item ->> 'expires_on', '')::date <= current_date then
        raise exception using errcode = '22023', message = 'No se aceptan artículos vencidos';
      end if;
      if nullif(item ->> 'declared_estimated_value_cop', '')::numeric is not null
         and nullif(item ->> 'declared_estimated_value_cop', '')::numeric <= 0 then
        raise exception using errcode = '22023', message = 'El valor estimado debe ser mayor que cero';
      end if;
    end loop;
  end if;

  fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'event_id', p_event_id,
        'organization_id', p_organization_id,
        'kind', p_kind,
        'donor_name_private', btrim(p_donor_name_private),
        'contact_private', jsonb_build_object('email', contact_email, 'phone', nullif(contact_phone, '')),
        'attribution_kind', p_attribution_kind,
        'public_attribution', public_name,
        'attribution_authorized', coalesce(p_attribution_authorized, false),
        'declared_status', p_declared_status,
        'items', coalesce(p_items, '[]'::jsonb),
        'declared_amount', p_declared_amount,
        'preferred_location_id', p_preferred_location_id,
        'reporting_context', context
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  insert into public.donation_intakes(
    event_id,
    organization_id,
    kind,
    status,
    tracking_code,
    idempotency_key,
    donor_name_private,
    contact_private,
    public_attribution_kind,
    public_attribution,
    attribution_authorized,
    declared_status,
    declared_amount,
    preferred_location_id,
    donor_type,
    economic_sector,
    specific_destination,
    destination_note,
    destination_department,
    destination_municipality,
    estimated_beneficiaries,
    delivery_channel,
    internal_responsible_private,
    internal_contact_private,
    observations_private,
    submitted_by,
    request_fingerprint
  ) values (
    p_event_id,
    p_organization_id,
    p_kind,
    'pending_verification',
    public.generate_tracking_code('APO'),
    p_idempotency_key,
    btrim(p_donor_name_private),
    jsonb_build_object('email', contact_email, 'phone', nullif(contact_phone, '')),
    p_attribution_kind,
    public_name,
    coalesce(p_attribution_authorized, false),
    p_declared_status,
    p_declared_amount,
    case when p_kind = 'in_kind' then p_preferred_location_id else null end,
    nullif(context ->> 'donor_type', ''),
    nullif(btrim(context ->> 'economic_sector'), ''),
    wants_destination,
    case when wants_destination then nullif(btrim(context ->> 'destination_note'), '') else null end,
    case when wants_destination then nullif(btrim(context ->> 'destination_department'), '') else null end,
    case when wants_destination then nullif(btrim(context ->> 'destination_municipality'), '') else null end,
    beneficiary_count,
    nullif(btrim(context ->> 'delivery_channel'), ''),
    nullif(btrim(context ->> 'internal_responsible'), ''),
    internal_contact,
    nullif(btrim(context ->> 'observations'), ''),
    actor_id,
    fingerprint
  )
  on conflict (organization_id, idempotency_key) do nothing
  returning * into created;

  if created.id is null then
    select * into created
    from public.donation_intakes as existing
    where existing.organization_id = p_organization_id
      and existing.idempotency_key = p_idempotency_key;

    if created.request_fingerprint is distinct from fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;

    return query select created.id, created.tracking_code, created.status, true;
    return;
  end if;

  if p_kind = 'in_kind' then
    insert into public.donation_intake_items(
      intake_id,
      category,
      description,
      quantity,
      unit,
      condition,
      expires_on,
      storage_requirement,
      declared_estimated_value_cop
    )
    select
      created.id,
      btrim(value ->> 'category'),
      btrim(value ->> 'description'),
      (value ->> 'quantity')::numeric,
      btrim(value ->> 'unit'),
      btrim(value ->> 'condition'),
      nullif(value ->> 'expires_on', '')::date,
      btrim(value ->> 'storage_requirement'),
      nullif(value ->> 'declared_estimated_value_cop', '')::numeric
    from jsonb_array_elements(p_items);
  end if;

  return query select created.id, created.tracking_code, created.status, false;
end;
$$;

revoke all on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) to authenticated;

comment on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) is 'Registro aliado validado en servidor, atómico e idempotente; conserva campos privados fuera de las proyecciones públicas.';

create or replace function public.validate_delivery(
  p_delivery_id uuid,
  p_note text default 'Validación sandbox'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.deliveries;
  shipment public.shipments;
  shipped_item public.shipment_items;
  allocation public.allocations;
  need_item public.need_items;
  donation_item public.donation_items;
  donation public.donations;
  intake public.donation_intakes;
begin
  select * into target
  from public.deliveries
  where id = p_delivery_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Entrega no encontrada';
  end if;

  select * into shipment
  from public.shipments
  where id = target.shipment_id
  for update;
  if not public.has_event_role(
    shipment.event_id,
    array['verifier', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes validar esta entrega';
  end if;

  select * into shipped_item
  from public.shipment_items
  where shipment_id = shipment.id
  order by id
  limit 1;
  select * into allocation
  from public.allocations
  where id = shipped_item.allocation_id
  for update;
  select * into need_item
  from public.need_items
  where id = allocation.need_item_id
  for update;
  select * into donation_item
  from public.donation_items
  where id = (
    select lot.donation_item_id
    from public.inventory_lots as lot
    where lot.id = allocation.lot_id
  );
  select * into donation
  from public.donations
  where id = donation_item.donation_id
  for update;
  select * into intake
  from public.donation_intakes
  where id = donation.intake_id;

  if target.status = 'validated' then
    return donation.id;
  end if;
  if target.status not in ('delivered', 'incident') then
    raise exception using errcode = '22023', message = 'Entrega no disponible para validación';
  end if;
  if need_item.quantity_covered + target.quantity_delivered > need_item.quantity_required then
    raise exception using errcode = '22023', message = 'La entrega excede la necesidad pendiente';
  end if;

  update public.deliveries
  set status = 'validated',
      validated_by = (select auth.uid()),
      validated_at = now(),
      recipient_confirmation_private = jsonb_build_object('note', left(p_note, 240))
  where id = target.id;
  update public.shipments set status = 'validated' where id = shipment.id;
  update public.allocations set status = 'delivered' where id = allocation.id;
  update public.need_items
  set quantity_covered = quantity_covered + target.quantity_delivered
  where id = need_item.id;
  update public.need_cases
  set status = case
    when need_item.quantity_covered + target.quantity_delivered >= need_item.quantity_required
      then 'covered'::public.need_status
    else 'partially_covered'::public.need_status
  end
  where id = need_item.need_case_id;
  update public.public_need_projections
  set covered_quantity = covered_quantity + target.quantity_delivered,
      status = case
        when covered_quantity + target.quantity_delivered >= needed_quantity then 'Cubierta'
        else 'Parcialmente cubierta'
      end,
      updated_at = now()
  where source_need_id = need_item.need_case_id;

  update public.donations
  set status = 'validated', updated_at = now()
  where id = donation.id;

  insert into public.public_donation_projections(
    donation_id,
    donation_item_id,
    event_id,
    public_code,
    attribution,
    kind,
    category,
    verified_quantity,
    unit,
    destination_label,
    operational_state,
    evidence_level,
    published,
    published_at
  ) values (
    donation.id,
    donation_item.id,
    donation.event_id,
    donation.donor_tracking_code || '-' || left(replace(donation_item.id::text, '-', ''), 8),
    case intake.public_attribution_kind
      when 'anonymous' then 'Anónimo'
      when 'organization' then coalesce(intake.public_attribution, 'Organización aliada')
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    donation.kind,
    donation_item.category,
    target.quantity_delivered,
    donation_item.unit,
    shipment.public_destination,
    'validated',
    'operational_events',
    true,
    now()
  )
  on conflict (donation_item_id) do update
  set verified_quantity = public.public_donation_projections.verified_quantity + excluded.verified_quantity,
      destination_label = excluded.destination_label,
      operational_state = excluded.operational_state,
      evidence_level = excluded.evidence_level,
      published = true,
      published_at = excluded.published_at,
      updated_at = now();

  return donation.id;
end;
$$;

revoke all on function public.validate_delivery(uuid, text) from public, anon, authenticated;
grant execute on function public.validate_delivery(uuid, text) to authenticated;

create or replace function public.treasury_pending_money_donations(p_event_id uuid)
returns table(
  donation_id uuid,
  tracking_code text,
  intake_tracking_code text,
  declared_amount numeric,
  currency text,
  attribution text,
  submitted_at timestamptz
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_event_role(
       p_event_id,
       array['treasury_approver', 'event_admin', 'auditor']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar aportes monetarios';
  end if;

  return query
  select
    donation.id,
    donation.donor_tracking_code,
    intake.tracking_code,
    intake.declared_amount,
    intake.currency::text,
    case
      when intake.public_attribution_kind = 'anonymous' then 'Anónimo'
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    intake.submitted_at
  from public.donations as donation
  join public.donation_intakes as intake on intake.id = donation.intake_id
  where donation.event_id = p_event_id
    and donation.kind = 'money'
    and donation.status = 'promised'
    and intake.status = 'approved'
  order by intake.submitted_at;
end;
$$;

revoke all on function public.treasury_pending_money_donations(uuid) from public, anon, authenticated;
grant execute on function public.treasury_pending_money_donations(uuid) to authenticated;

create or replace function public.reconcile_money_donation(
  p_donation_id uuid,
  p_fund_id uuid,
  p_provider_reference_private text,
  p_idempotency_key text
)
returns table(
  transaction_id uuid,
  source_donation_id uuid,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  donation public.donations;
  intake public.donation_intakes;
  fund public.funds;
  transaction_record public.financial_transactions;
  destination_label text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Autenticación requerida';
  end if;
  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;
  if char_length(btrim(coalesce(p_provider_reference_private, ''))) not between 4 and 160 then
    raise exception using errcode = '22023', message = 'Referencia privada inválida';
  end if;

  select * into donation
  from public.donations
  where id = p_donation_id
  for update;
  if not found or donation.kind <> 'money' then
    raise exception using errcode = 'P0002', message = 'Aporte monetario no encontrado';
  end if;
  select * into intake
  from public.donation_intakes
  where id = donation.intake_id
  for update;
  select * into fund
  from public.funds
  where id = p_fund_id
  for update;

  if fund.id is null or not fund.verified or fund.event_id <> donation.event_id then
    raise exception using errcode = '22023', message = 'Fondo inválido para el evento';
  end if;
  if not public.has_any_role(
    fund.organization_id,
    fund.event_id,
    array['treasury_approver', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes conciliar este aporte';
  end if;

  select * into transaction_record
  from public.financial_transactions as existing
  where existing.organization_id = fund.organization_id
    and existing.idempotency_key = p_idempotency_key;
  if transaction_record.id is not null then
    if transaction_record.donation_id is distinct from donation.id
       or transaction_record.fund_id is distinct from fund.id
       or transaction_record.amount is distinct from intake.declared_amount then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select transaction_record.id, donation.id, true;
    return;
  end if;

  select * into transaction_record
  from public.financial_transactions as existing
  where existing.donation_id = donation.id;
  if transaction_record.id is not null then
    if transaction_record.fund_id is distinct from fund.id
       or transaction_record.amount is distinct from intake.declared_amount then
      raise exception using errcode = '22023', message = 'El aporte ya fue conciliado con datos diferentes';
    end if;
    return query select transaction_record.id, donation.id, true;
    return;
  end if;

  if intake.status <> 'approved' or donation.status <> 'promised' then
    raise exception using errcode = '22023', message = 'El aporte no está listo para conciliación';
  end if;
  if intake.declared_amount is null or intake.declared_amount <= 0 then
    raise exception using errcode = '22023', message = 'El aporte no tiene un valor declarado válido';
  end if;

  insert into public.financial_transactions(
    event_id,
    organization_id,
    fund_id,
    donation_id,
    transaction_type,
    amount,
    currency,
    status,
    provider,
    provider_reference_private,
    public_reference,
    idempotency_key,
    actor_id,
    reconciled_at
  ) values (
    fund.event_id,
    fund.organization_id,
    fund.id,
    donation.id,
    'credit',
    intake.declared_amount,
    intake.currency,
    'reconciled',
    'donation_intake',
    btrim(p_provider_reference_private),
    'DON-' || donation.donor_tracking_code,
    p_idempotency_key,
    actor_id,
    now()
  )
  returning * into transaction_record;

  update public.donations
  set status = 'validated', updated_at = now()
  where id = donation.id;

  destination_label := case
    when intake.specific_destination
      then nullif(concat_ws(', ', intake.destination_municipality, intake.destination_department), '')
    else null
  end;

  insert into public.public_donation_projections(
    donation_id,
    donation_item_id,
    event_id,
    public_code,
    attribution,
    kind,
    category,
    reconciled_amount,
    currency,
    destination_label,
    operational_state,
    evidence_level,
    published,
    published_at
  ) values (
    donation.id,
    null,
    donation.event_id,
    donation.donor_tracking_code,
    case intake.public_attribution_kind
      when 'anonymous' then 'Anónimo'
      when 'organization' then coalesce(intake.public_attribution, 'Organización aliada')
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    'money',
    'Aporte económico',
    intake.declared_amount,
    intake.currency,
    destination_label,
    'reconciled',
    'financial_reconciliation',
    true,
    now()
  )
  on conflict (donation_id) where donation_item_id is null do update
  set reconciled_amount = excluded.reconciled_amount,
      currency = excluded.currency,
      destination_label = excluded.destination_label,
      operational_state = excluded.operational_state,
      evidence_level = excluded.evidence_level,
      published = true,
      published_at = excluded.published_at,
      updated_at = now();

  insert into public.receipts(
    donation_id,
    receipt_type,
    issued_by,
    disclaimer,
    payload_hash
  ) values (
    donation.id,
    'payment_receipt',
    actor_id,
    'Constancia sandbox de conciliación: no certifica beneficio, impacto ni deducibilidad tributaria.',
    encode(
      extensions.digest(
        (transaction_record.id::text || ':' || btrim(p_provider_reference_private))::bytea,
        'sha256'
      ),
      'hex'
    )
  );

  return query select transaction_record.id, donation.id, false;
end;
$$;

revoke all on function public.reconcile_money_donation(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.reconcile_money_donation(uuid, uuid, text, text) to authenticated;

create or replace function public.submit_need_report(
  p_event_id uuid,
  p_category text,
  p_description text,
  p_public_location text,
  p_quantity numeric,
  p_unit text,
  p_exact_address_private text,
  p_contact_private jsonb,
  p_bot_field text
)
returns table(need_id uuid, tracking_code text, status public.need_status)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if nullif(btrim(coalesce(p_bot_field, '')), '') is not null then
    raise exception using errcode = '22023', message = 'No fue posible procesar el reporte';
  end if;

  return query
  select *
  from public.submit_need_report(
    p_event_id,
    p_category,
    p_description,
    p_public_location,
    p_quantity,
    p_unit,
    p_exact_address_private,
    p_contact_private
  );
end;
$$;

revoke all on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb
) from public, anon, authenticated;
revoke all on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb, text
) to anon, authenticated;

-- Una sola política permisiva por operación evita evaluaciones duplicadas sin
-- ampliar el alcance: se conserva la unión de miembro de organización y verificador.
drop policy if exists "members read need item allocations" on public.allocations;

drop policy if exists "event verifiers read all intakes" on public.donation_intakes;
drop policy if exists "org members read intakes" on public.donation_intakes;
create policy "authorized members read intakes"
on public.donation_intakes
for select
to authenticated
using (
  public.is_org_member(organization_id, event_id)
  or public.has_event_role(
    event_id,
    array['verifier', 'event_admin', 'auditor']::public.app_role[]
  )
);

drop policy if exists "event verifiers read all intake items" on public.donation_intake_items;
drop policy if exists "org members read intake items" on public.donation_intake_items;
create policy "authorized members read intake items"
on public.donation_intake_items
for select
to authenticated
using (
  exists (
    select 1
    from public.donation_intakes as intake
    where intake.id = donation_intake_items.intake_id
      and (
        public.is_org_member(intake.organization_id, intake.event_id)
        or public.has_event_role(
          intake.event_id,
          array['verifier', 'event_admin', 'auditor']::public.app_role[]
        )
      )
  )
);

drop policy if exists "event verifiers read all intake decisions" on public.intake_verification_decisions;
drop policy if exists "org members read intake decisions" on public.intake_verification_decisions;
create policy "authorized members read intake decisions"
on public.intake_verification_decisions
for select
to authenticated
using (
  exists (
    select 1
    from public.donation_intakes as intake
    where intake.id = intake_verification_decisions.intake_id
      and (
        public.is_org_member(intake.organization_id, intake.event_id)
        or public.has_event_role(
          intake.event_id,
          array['verifier', 'event_admin', 'auditor']::public.app_role[]
        )
      )
  )
);

drop policy if exists "public reads active events" on public.emergency_events;
create policy "public reads active events"
on public.emergency_events
for select
to anon
using (status = 'active');

comment on column public.donation_intakes.request_fingerprint is
  'SHA-256 del contenido validado; impide reutilizar una clave idempotente con una solicitud diferente.';
comment on column public.public_donation_projections.donation_item_id is
  'Ítem fuente de una proyección en especie. Las proyecciones monetarias conservan este campo nulo.';
comment on column public.financial_transactions.donation_id is
  'Aporte monetario conciliado por este movimiento financiero append-only.';
