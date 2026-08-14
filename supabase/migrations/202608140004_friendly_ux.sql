-- Proyección segura de centros y preferencia de entrega para el flujo amigable.

alter table public.inventory_locations
  add column if not exists public_latitude numeric(9,6),
  add column if not exists public_longitude numeric(9,6);

alter table public.inventory_locations
  add constraint inventory_locations_public_coordinates_pair
  check ((public_latitude is null) = (public_longitude is null));

alter table public.donation_intakes
  add column if not exists preferred_location_id uuid references public.inventory_locations(id);

create or replace function public.public_collection_centers(p_event_id uuid)
returns table(
  id uuid,
  name text,
  location_label text,
  accepts text[],
  restricted_items text[],
  cold_chain_capable boolean,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    location.id,
    location.name,
    location.public_location_text,
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join public.item_acceptance_rules as rule
    on rule.organization_id = location.organization_id
    and rule.event_id = location.event_id
    and rule.effective_from <= now()
  where location.event_id = p_event_id
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

revoke all on function public.public_collection_centers(uuid) from public;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

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
  p_preferred_location_id uuid
)
returns table(intake_id uuid, tracking_code text, status public.intake_status, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare submitted record;
begin
  if p_kind = 'in_kind' then
    if p_preferred_location_id is null or not exists (
      select 1 from public.inventory_locations
      where id = p_preferred_location_id and event_id = p_event_id
    ) then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega válido';
    end if;
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
    p_declared_amount
  );

  if not submitted.was_duplicate then
    update public.donation_intakes
    set preferred_location_id = case when p_kind = 'in_kind' then p_preferred_location_id else null end
    where id = submitted.intake_id;
  end if;

  return query select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid
) to authenticated;

comment on function public.public_collection_centers(uuid) is
  'Proyección pública explícita de centros sintéticos, ubicación aproximada y reglas vigentes; excluye direcciones exactas.';

comment on column public.donation_intakes.preferred_location_id is
  'Preferencia operativa declarada; no acredita recepción y puede cambiar durante la coordinación autorizada.';
