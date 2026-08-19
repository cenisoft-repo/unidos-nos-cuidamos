-- Fase 16 del loop de consolidación: los reportes se construyen al final y siempre sobre el
-- Kardex, nunca sobre contadores paralelos. Todos son `security invoker`, así que devuelven
-- exactamente lo que la membresía de quien consulta ya podía leer.

-- Reservas vigentes: qué está comprometido, para qué y desde cuándo.
create or replace function public.stock_reservations(p_event_id uuid)
returns table(
  allocation_id uuid,
  reserved_at timestamptz,
  location_name text,
  lot_code text,
  category text,
  unit text,
  quantity numeric,
  destination_kind text,
  destination_label text,
  status text
)
language sql stable security invoker set search_path = '' as $$
  select
    allocation.id,
    allocation.created_at,
    location.name,
    lot.lot_code,
    lot.category,
    lot.unit,
    allocation.quantity,
    case when allocation.transfer_request_id is null then 'necesidad' else 'traslado' end,
    coalesce(destination.name, need_case.public_location_text, 'Sin destino declarado'),
    allocation.status
  from public.allocations as allocation
  join public.inventory_lots as lot on lot.id = allocation.lot_id
  join public.inventory_locations as location on location.id = lot.location_id
  left join public.transfer_requests as request on request.id = allocation.transfer_request_id
  left join public.inventory_locations as destination on destination.id = request.destination_location_id
  left join public.need_items as need_item on need_item.id = allocation.need_item_id
  left join public.need_cases as need_case on need_case.id = need_item.need_case_id
  where allocation.event_id = p_event_id
    and allocation.status = 'reserved'
  order by allocation.created_at desc;
$$;

-- Productos que ya salieron y todavía no fueron confirmados en destino.
create or replace function public.shipments_in_movement(p_event_id uuid)
returns table(
  shipment_id uuid,
  shipment_code text,
  status text,
  origin_name text,
  destination_label text,
  is_transfer boolean,
  quantity numeric,
  unit text,
  category text,
  transport_mode text,
  transport_plate text,
  dispatched_at timestamptz
)
language sql stable security invoker set search_path = '' as $$
  select
    shipment.id,
    shipment.shipment_code,
    shipment.status::text,
    origin.name,
    coalesce(destination.name, shipment.public_destination),
    shipment.transfer_request_id is not null,
    coalesce(sum(shipment_item.quantity), 0),
    min(lot.unit),
    min(lot.category),
    shipment.transport_mode,
    shipment.transport_plate,
    shipment.dispatched_at
  from public.shipments as shipment
  left join public.inventory_locations as origin on origin.id = shipment.origin_location_id
  left join public.inventory_locations as destination on destination.id = shipment.destination_location_id
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  where shipment.event_id = p_event_id
    and shipment.status in ('dispatched','in_transit','arrived')
  group by shipment.id, origin.name, destination.name
  order by shipment.dispatched_at desc nulls last;
$$;

-- Lo que espera acción: traslados autorizados sin despacho y despachos en preparación.
create or replace function public.pending_dispatches(p_event_id uuid)
returns table(
  reference text,
  kind text,
  origin_name text,
  destination_label text,
  category text,
  unit text,
  quantity numeric,
  status text,
  since timestamptz
)
language sql stable security invoker set search_path = '' as $$
  select
    request.request_code,
    'traslado autorizado',
    origin.name,
    destination.name,
    request.category,
    request.unit,
    request.quantity_authorized,
    request.status::text,
    request.decided_at
  from public.transfer_requests as request
  join public.inventory_locations as origin on origin.id = request.origin_location_id
  join public.inventory_locations as destination on destination.id = request.destination_location_id
  where request.event_id = p_event_id
    and request.status = 'authorized'
  union all
  select
    shipment.shipment_code,
    'despacho en preparación',
    origin.name,
    coalesce(destination.name, shipment.public_destination),
    min(lot.category),
    min(lot.unit),
    coalesce(sum(shipment_item.quantity), 0),
    shipment.status::text,
    shipment.created_at
  from public.shipments as shipment
  left join public.inventory_locations as origin on origin.id = shipment.origin_location_id
  left join public.inventory_locations as destination on destination.id = shipment.destination_location_id
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  where shipment.event_id = p_event_id
    and shipment.status = 'preparing'
  group by shipment.id, origin.name, destination.name
  order by since desc nulls last;
$$;

-- Donaciones por aliado: lo prometido, lo recibido y lo que ya se entregó.
create or replace function public.donations_by_ally(p_event_id uuid)
returns table(
  organization_id uuid,
  organization_name text,
  donations integer,
  quantity_promised numeric,
  quantity_received numeric,
  category text,
  unit text
)
language sql stable security invoker set search_path = '' as $$
  select
    donation.organization_id,
    organization.name,
    count(distinct donation.id)::integer,
    coalesce(sum(donation_item.quantity_promised), 0),
    coalesce(sum(donation_item.quantity_received), 0),
    donation_item.category,
    donation_item.unit
  from public.donations as donation
  join public.organizations as organization on organization.id = donation.organization_id
  join public.donation_items as donation_item on donation_item.donation_id = donation.id
  where donation.event_id = p_event_id
  group by donation.organization_id, organization.name, donation_item.category, donation_item.unit
  order by organization.name, donation_item.category;
$$;

-- Donaciones asociadas a necesidades: la cadena NECESIDAD → ALIADO → DONACIÓN en una tabla.
create or replace function public.donations_by_need(p_event_id uuid)
returns table(
  need_tracking_code text,
  need_location text,
  category text,
  unit text,
  quantity_requested numeric,
  quantity_committed numeric,
  quantity_received numeric,
  quantity_delivered numeric,
  quantity_pending numeric,
  contributing_allies integer
)
language sql stable security invoker set search_path = '' as $$
  select
    need_case.tracking_code,
    need_case.public_location_text,
    item_position.category,
    item_position.unit,
    item_position.quantity_requested,
    item_position.quantity_committed,
    item_position.quantity_received,
    item_position.quantity_delivered,
    item_position.quantity_pending,
    count(distinct donation.organization_id)::integer
  from public.need_item_positions as item_position
  join public.need_cases as need_case on need_case.id = item_position.need_case_id
  left join public.donation_items as donation_item on donation_item.need_item_id = item_position.need_item_id
  left join public.donations as donation on donation.id = donation_item.donation_id
  where item_position.event_id = p_event_id
  group by
    need_case.tracking_code, need_case.public_location_text,
    item_position.category, item_position.unit, item_position.quantity_requested,
    item_position.quantity_committed, item_position.quantity_received,
    item_position.quantity_delivered, item_position.quantity_pending
  order by item_position.quantity_pending desc, need_case.tracking_code;
$$;

-- Historial de movimientos: el Kardex tal cual, que es la fuente de todo lo anterior.
create or replace function public.stock_movement_history(
  p_event_id uuid,
  p_location_id uuid default null,
  p_limit integer default 200
)
returns table(
  moved_at timestamptz,
  location_name text,
  lot_code text,
  category text,
  unit text,
  movement_type text,
  quantity_delta numeric,
  reason text,
  actor_id uuid
)
language sql stable security invoker set search_path = '' as $$
  select
    movement.created_at,
    location.name,
    lot.lot_code,
    lot.category,
    lot.unit,
    movement.movement_type::text,
    movement.quantity_delta,
    movement.reason,
    movement.actor_id
  from public.stock_movements as movement
  join public.inventory_lots as lot on lot.id = movement.lot_id
  join public.inventory_locations as location on location.id = lot.location_id
  where movement.event_id = p_event_id
    and (p_location_id is null or lot.location_id = p_location_id)
  order by movement.created_at desc
  limit least(greatest(coalesce(p_limit, 200), 1), 1000);
$$;

do $$
declare report_signature text;
begin
  foreach report_signature in array array[
    'public.stock_reservations(uuid)',
    'public.shipments_in_movement(uuid)',
    'public.pending_dispatches(uuid)',
    'public.donations_by_ally(uuid)',
    'public.donations_by_need(uuid)',
    'public.stock_movement_history(uuid, uuid, integer)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', report_signature);
    execute format('grant execute on function %s to authenticated', report_signature);
  end loop;
end $$;

comment on function public.stock_reservations(uuid) is 'Reservas vigentes con su destino: necesidad o traslado.';
comment on function public.shipments_in_movement(uuid) is 'Productos que salieron y aún no fueron confirmados en destino.';
comment on function public.pending_dispatches(uuid) is 'Traslados autorizados sin despachar y despachos todavía en preparación.';
comment on function public.donations_by_ally(uuid) is 'Donaciones por aliado, categoría y unidad, sin convertir unidades.';
comment on function public.donations_by_need(uuid) is 'Solicitado, comprometido, recibido, entregado y pendiente por necesidad, con cuántos aliados aportaron.';
comment on function public.stock_movement_history(uuid, uuid, integer) is 'Historial del Kardex, fuente única de todas las cifras de inventario.';
