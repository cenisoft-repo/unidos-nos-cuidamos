-- Contexto declarativo para reportes y exportaciones analíticas.
-- Todos estos campos permanecen en la tabla operacional protegida por RLS.

alter table public.donation_intakes
  add column if not exists donor_type text,
  add column if not exists economic_sector text,
  add column if not exists specific_destination boolean not null default false,
  add column if not exists destination_department text,
  add column if not exists destination_municipality text,
  add column if not exists estimated_beneficiaries integer,
  add column if not exists delivery_channel text,
  add column if not exists internal_responsible_private text,
  add column if not exists internal_contact_private jsonb not null default '{}'::jsonb,
  add column if not exists observations_private text;

alter table public.donation_intakes
  add constraint donation_intakes_donor_type_check
    check (donor_type is null or donor_type in ('persona','empresa','gremio','fundacion','otro')),
  add constraint donation_intakes_economic_sector_length
    check (economic_sector is null or char_length(economic_sector) between 2 and 120),
  add constraint donation_intakes_destination_department_length
    check (destination_department is null or char_length(destination_department) between 2 and 100),
  add constraint donation_intakes_destination_municipality_length
    check (destination_municipality is null or char_length(destination_municipality) between 2 and 140),
  add constraint donation_intakes_estimated_beneficiaries_positive
    check (estimated_beneficiaries is null or estimated_beneficiaries > 0),
  add constraint donation_intakes_delivery_channel_length
    check (delivery_channel is null or char_length(delivery_channel) between 2 and 160),
  add constraint donation_intakes_internal_responsible_length
    check (internal_responsible_private is null or char_length(internal_responsible_private) between 2 and 160),
  add constraint donation_intakes_internal_contact_object
    check (jsonb_typeof(internal_contact_private) = 'object'),
  add constraint donation_intakes_observations_length
    check (observations_private is null or char_length(observations_private) <= 2000),
  add constraint donation_intakes_specific_destination_fields
    check (
      not specific_destination
      or (destination_department is not null and destination_municipality is not null)
    );

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
returns table(intake_id uuid, tracking_code text, status public.intake_status, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare submitted record;
declare context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
declare wants_destination boolean := coalesce((context->>'specific_destination')::boolean, false);
declare beneficiary_count integer := nullif(context->>'estimated_beneficiaries', '')::integer;
begin
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;
  if nullif(context->>'donor_type', '') is not null
    and context->>'donor_type' not in ('persona','empresa','gremio','fundacion','otro') then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante válido';
  end if;
  if wants_destination and (
    length(trim(coalesce(context->>'destination_department', ''))) < 2
    or length(trim(coalesce(context->>'destination_municipality', ''))) < 2
  ) then
    raise exception using errcode = '22023', message = 'La destinación específica requiere departamento y municipio o zona';
  end if;
  if beneficiary_count is not null and beneficiary_count <= 0 then
    raise exception using errcode = '22023', message = 'Los beneficiarios estimados deben ser mayores que cero';
  end if;
  if context ? 'internal_contact' and jsonb_typeof(context->'internal_contact') <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto interno debe ser un objeto';
  end if;
  if jsonb_typeof(p_items) = 'array' and exists (
    select 1
    from jsonb_array_elements(p_items) as supplied(item)
    where nullif(item->>'declared_estimated_value_cop', '')::numeric <= 0
  ) then
    raise exception using errcode = '22023', message = 'El valor estimado de un artículo debe ser mayor que cero';
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
    p_declared_status,
    p_items,
    p_declared_amount,
    p_preferred_location_id
  );

  if not submitted.was_duplicate then
    update public.donation_intakes
    set
      donor_type = nullif(context->>'donor_type', ''),
      economic_sector = nullif(trim(context->>'economic_sector'), ''),
      specific_destination = wants_destination,
      destination_note = case when wants_destination then nullif(trim(context->>'destination_note'), '') else null end,
      destination_department = case when wants_destination then nullif(trim(context->>'destination_department'), '') else null end,
      destination_municipality = case when wants_destination then nullif(trim(context->>'destination_municipality'), '') else null end,
      estimated_beneficiaries = beneficiary_count,
      delivery_channel = nullif(trim(context->>'delivery_channel'), ''),
      internal_responsible_private = nullif(trim(context->>'internal_responsible'), ''),
      internal_contact_private = coalesce(context->'internal_contact', '{}'::jsonb),
      observations_private = nullif(trim(context->>'observations'), '')
    where id = submitted.intake_id;

    with supplied as (
      select ordinality::integer as position, nullif(item->>'declared_estimated_value_cop', '')::numeric as estimated_value
      from jsonb_array_elements(p_items) with ordinality as valueset(item, ordinality)
    ), persisted as (
      select id, row_number() over (order by created_at, id)::integer as position
      from public.donation_intake_items as persisted_item
      where persisted_item.intake_id = submitted.intake_id
    )
    update public.donation_intake_items as item
    set declared_estimated_value_cop = supplied.estimated_value
    from supplied
    join persisted using (position)
    where item.id = persisted.id
      and supplied.estimated_value is not null;
  end if;

  return query select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid, jsonb
) to authenticated;

comment on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid, jsonb
) is 'Intake guiado con organización derivada de membresía, centro, contexto privado, idempotencia y auditoría.';

comment on column public.donation_intakes.estimated_beneficiaries is
  'Estimación declarada y privada; nunca alimenta métricas públicas de impacto sin verificación y conciliación.';
comment on column public.donation_intakes.internal_contact_private is
  'Contacto operacional privado sujeto a RLS; se excluye de proyecciones públicas y exportaciones de transparencia.';
comment on column public.donation_intake_items.declared_estimated_value_cop is
  'Valor declarado no conciliado; no constituye ingreso financiero ni cifra pública.';
