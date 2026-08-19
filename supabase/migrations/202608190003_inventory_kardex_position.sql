-- Fases 8 y 15 del loop de consolidación: una única fuente de verdad para el inventario.
--
-- El Kardex (`stock_movements`) ya existía y es append-only e inmutable, pero nadie lo leía
-- para presentar la posición: la consola de bodega mostraba `inventory_lots.quantity_initial`,
-- que es el saldo del día de la recepción y no cambia nunca. Ese era el contador independiente
-- que la Fase 8 prohíbe.
--
-- A partir de aquí físico, disponible, reservado, en movimiento y entregado se derivan. No se
-- agrega ninguna columna de saldo y `quantity_initial` queda como lo que siempre fue: la
-- cantidad con la que nació el lote.
--
-- Cómo se deriva cada cifra:
--
--   disponible   = suma de todos los movimientos del lote
--   reservado    = lo retenido por reservas todavía no liberadas
--   físico       = disponible + reservado (lo que sigue en la bodega)
--   en movimiento= lo despachado que el destino aún no confirmó
--   entregado    = lo que el destino confirmó recibir
--
-- Ejemplo de la Fase 8: 100 kg recibidos y 25 kg solicitados dejan físico 100, disponible 75 y
-- reservado 25. Al salir el transporte, disponible 75 y en movimiento 25. Al llegar, en
-- movimiento 0 y entregado 25.

-- Un faltante no es un daño: la Fase 14 los pide separados y la posición los descuenta igual.
alter table public.deliveries
  add column quantity_missing numeric(14,3) not null default 0 check (quantity_missing >= 0);

comment on column public.deliveries.quantity_missing is
  'Cantidad despachada que el destino no recibió y tampoco reportó como dañada.';

create or replace view public.inventory_lot_positions
with (security_invoker = true) as
with movement as (
  select
    stock_movement.lot_id,
    sum(stock_movement.quantity_delta) as available,
    sum(case when stock_movement.movement_type in ('reserve','release') then -stock_movement.quantity_delta else 0 end) as reserved,
    sum(case when stock_movement.movement_type in ('dispatch','transfer_out') then -stock_movement.quantity_delta else 0 end) as dispatched
  from public.stock_movements as stock_movement
  group by stock_movement.lot_id
), settled as (
  -- Un despacho puede llevar varias líneas; lo conciliado se reparte según lo que aportó cada
  -- una para que dos lotes en el mismo despacho no se cuenten dos veces.
  select
    allocation.lot_id,
    sum(delivery.quantity_delivered * shipment_item.quantity / nullif(shipped.total, 0)) as delivered,
    sum((delivery.quantity_damaged + delivery.quantity_missing) * shipment_item.quantity / nullif(shipped.total, 0)) as lost
  from public.deliveries as delivery
  join public.shipment_items as shipment_item on shipment_item.shipment_id = delivery.shipment_id
  join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  join lateral (
    select sum(sibling.quantity) as total
    from public.shipment_items as sibling
    where sibling.shipment_id = delivery.shipment_id
  ) as shipped on true
  group by allocation.lot_id
)
select
  lot.id as lot_id,
  lot.event_id,
  lot.organization_id,
  lot.location_id,
  lot.lot_code,
  lot.category,
  lot.unit,
  lot.status,
  lot.expires_on,
  lot.quantity_initial,
  coalesce(movement.available, 0) + coalesce(movement.reserved, 0) as quantity_physical,
  coalesce(movement.available, 0) as quantity_available,
  coalesce(movement.reserved, 0) as quantity_reserved,
  greatest(coalesce(movement.dispatched, 0) - coalesce(settled.delivered, 0) - coalesce(settled.lost, 0), 0) as quantity_in_transit,
  coalesce(settled.delivered, 0) as quantity_delivered
from public.inventory_lots as lot
left join movement on movement.lot_id = lot.id
left join settled on settled.lot_id = lot.id;

grant select on public.inventory_lot_positions to authenticated;
comment on view public.inventory_lot_positions is
  'Posición real de cada lote derivada del Kardex y de las entregas conciliadas; ningún saldo se almacena.';

-- Estado global del inventario por punto, categoría y unidad. La unidad nunca se convierte:
-- kilogramos siguen siendo kilogramos y litros siguen siendo litros.
create or replace function public.inventory_position(p_event_id uuid)
returns table(
  location_id uuid,
  location_name text,
  organization_id uuid,
  category text,
  unit text,
  quantity_physical numeric,
  quantity_available numeric,
  quantity_reserved numeric,
  quantity_in_transit numeric,
  quantity_delivered numeric,
  lots integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    location.id,
    location.name,
    location.organization_id,
    lot_position.category,
    lot_position.unit,
    sum(lot_position.quantity_physical),
    sum(lot_position.quantity_available),
    sum(lot_position.quantity_reserved),
    sum(lot_position.quantity_in_transit),
    sum(lot_position.quantity_delivered),
    count(*)::integer
  from public.inventory_lot_positions as lot_position
  join public.inventory_locations as location on location.id = lot_position.location_id
  where lot_position.event_id = p_event_id
  group by location.id, location.name, location.organization_id, lot_position.category, lot_position.unit
  order by location.name, lot_position.category, lot_position.unit;
$$;

revoke all on function public.inventory_position(uuid) from public, anon, authenticated;
grant execute on function public.inventory_position(uuid) to authenticated;
comment on function public.inventory_position(uuid) is
  'Estado global del inventario por punto, categoría y unidad, derivado del Kardex. Conserva la unidad de origen.';

-- ============================================================ Fase 6: punto más próximo

-- Un solo listado de puntos de entrega del aliado. Con coordenada devuelve la distancia y los
-- ordena de más cerca a más lejos; sin coordenada conserva el orden alfabético de siempre.
-- `organization_delivery_points` pasa a ser el caso «sin coordenada» de este mismo contrato.
create or replace function public.organization_delivery_points_near(
  p_event_id uuid,
  p_organization_id uuid,
  p_latitude double precision,
  p_longitude double precision
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
  longitude double precision,
  distance_km double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  has_reference boolean := p_latitude is not null and p_longitude is not null;
begin
  if (select auth.uid()) is null
     or not public.has_any_role(
       p_organization_id,
       p_event_id,
       array['partner_reporter','event_admin']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No puedes consultar los puntos de esta organización';
  end if;

  if has_reference and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    raise exception using errcode = '22023', message = 'La ubicación de referencia no es válida';
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
    location.public_longitude::double precision,
    case
      when not has_reference then null
      else round((extensions.st_distancesphere(
        extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326),
        extensions.st_setsrid(
          extensions.st_makepoint(location.public_longitude::double precision, location.public_latitude::double precision),
          4326
        )
      ) / 1000)::numeric, 2)::double precision
    end
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
    and location.organization_id = p_organization_id
    and location.active
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by
    case when not has_reference then null else extensions.st_distancesphere(
      extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326),
      extensions.st_setsrid(
        extensions.st_makepoint(location.public_longitude::double precision, location.public_latitude::double precision),
        4326
      )
    ) end nulls last,
    location.name;
end;
$$;

revoke all on function public.organization_delivery_points_near(uuid, uuid, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.organization_delivery_points_near(uuid, uuid, double precision, double precision)
  to authenticated;
comment on function public.organization_delivery_points_near(uuid, uuid, double precision, double precision) is
  'Puntos de acopio activos del aliado ordenados por proximidad geográfica cuando se declara una ubicación de referencia.';

-- El contrato anterior se conserva y deja de tener implementación propia.
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
language sql
stable
security invoker
set search_path = ''
as $$
  select
    point.id,
    point.name,
    point.location_label,
    point.public_instructions,
    point.accepts,
    point.restricted_items,
    point.cold_chain_capable,
    point.latitude,
    point.longitude
  from public.organization_delivery_points_near(p_event_id, p_organization_id, null, null) as point;
$$;

revoke all on function public.organization_delivery_points(uuid, uuid) from public, anon, authenticated;
grant execute on function public.organization_delivery_points(uuid, uuid) to authenticated;
comment on function public.organization_delivery_points(uuid, uuid) is
  'Puntos de acopio activos del aliado sin ordenar por distancia; delega en organization_delivery_points_near.';
