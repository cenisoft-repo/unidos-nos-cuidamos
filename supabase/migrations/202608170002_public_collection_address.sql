-- Los puntos de acopio muestran su dirección real en la superficie pública.
-- Decisión de producto: un centro de acopio es un lugar público de entrega, así que su
-- dirección exacta debe verse «donde realmente es». Ambas funciones ya devuelven solo
-- puntos que reciben aportes (and location.accepts_donations), de modo que la etiqueta
-- pública pasa a ser la dirección exacta (con la zona aproximada como respaldo).
--
-- Se recrean sobre su definición vigente (202608160005), conservando el filtro de acopio
-- y cambiando únicamente la etiqueta. Alimentan tarjetas, mapa y flujo de donación, así
-- que el cambio se refleja en todas las superficies.

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
  with current_rules as (
    select distinct on (
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category
    )
      rule.organization_id,
      rule.event_id,
      rule.location_id,
      rule.category,
      rule.decision
    from public.item_acceptance_rules as rule
    where rule.effective_from <= now()
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
    -- Punto de acopio: su dirección exacta es la ubicación pública real.
    coalesce(nullif(btrim(location.exact_address_private), ''), location.public_location_text),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
    and location.active
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

revoke all on function public.public_collection_centers(uuid) from public;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

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
    -- Punto de acopio: su dirección exacta es la ubicación real que ve quien va a donar.
    coalesce(nullif(btrim(location.exact_address_private), ''), location.public_location_text),
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
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
end;
$$;

revoke all on function public.organization_delivery_points(uuid,uuid) from public, anon, authenticated;
grant execute on function public.organization_delivery_points(uuid,uuid) to authenticated;

comment on function public.public_collection_centers(uuid) is
  'Centros públicos de acopio: exponen su dirección exacta como ubicación pública real; solo puntos que reciben aportes.';