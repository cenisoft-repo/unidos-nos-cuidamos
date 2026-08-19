-- G-049 - El eje bodega a bodega era invisible en el mapa.
--
-- `sync_public_shipment_projection` derivaba el destino unicamente de la necesidad a la
-- que apuntaba la asignacion. Un traslado entre bodegas no apunta a ninguna: su vinculo es
-- `transfer_request_id`. El destino quedaba sin etiqueta ni coordenada y, como publicar
-- exige ambas, la proyeccion nacia con `published = false`.
--
-- Es decir: la consolidacion abrio el eje bodega a bodega y ese eje no se podia ver. Se
-- despachaba, se movia y se recibia sin que la cartografia publica lo mostrara nunca.
--
-- El destino de un traslado es la bodega de llegada, cuyo punto ya figura en el mapa con
-- su ubicacion publica; mostrar que algo va hacia alli no revela nada que no estuviera ya
-- publicado, y la direccion exacta sigue sin salir de la base.

CREATE OR REPLACE FUNCTION public.sync_public_shipment_projection(p_shipment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare projection record;
begin
  select
    shipment.event_id,
    shipment.id,
    shipment.shipment_code,
    shipment.status::text,
    location.name as origin_name,
    location.public_location_text as origin_label,
    location.public_latitude as origin_latitude,
    location.public_longitude as origin_longitude,
    -- Un traslado entre bodegas no apunta a una necesidad: su destino es la bodega de
    -- llegada, cuyo punto ya es publico en el mapa. Sin esto el destino quedaba nulo y el
    -- despacho no podia publicarse nunca.
    coalesce(
      need_projection.location_label,
      nullif(concat_ws(' · ', destination_location.name, destination_location.public_location_text), ''),
      shipment.public_destination
    ) as destination_label,
    coalesce(need_projection.latitude, destination_location.public_latitude) as destination_latitude,
    coalesce(need_projection.longitude, destination_location.public_longitude) as destination_longitude,
    coalesce(need_projection.published, destination_location.active) as destination_published
  into projection
  from public.shipments as shipment
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  left join public.inventory_locations as location on location.id = lot.location_id
  left join public.need_items as need_item on need_item.id = allocation.need_item_id
  left join public.need_cases as need_case on need_case.id = need_item.need_case_id
  left join public.public_need_projections as need_projection on need_projection.source_need_id = need_case.id
  left join public.inventory_locations as destination_location on destination_location.id = shipment.destination_location_id
  where shipment.id = p_shipment_id
  order by shipment_item.id nulls last
  limit 1;

  if not found then
    update public.public_logistics_projections
    set published = false, updated_at = now()
    where source_type = 'dispatch' and source_id = p_shipment_id;
    return;
  end if;

  insert into public.public_logistics_projections(
    event_id, source_type, source_id, public_code, label, status,
    origin_label, origin_latitude, origin_longitude,
    destination_label, destination_latitude, destination_longitude,
    published, updated_at
  ) values (
    projection.event_id,
    'dispatch',
    projection.id,
    projection.shipment_code,
    'Despacho ' || projection.shipment_code,
    projection.status,
    nullif(concat_ws(' · ', projection.origin_name, projection.origin_label), ''),
    projection.origin_latitude,
    projection.origin_longitude,
    projection.destination_label,
    projection.destination_latitude,
    projection.destination_longitude,
    projection.status in ('dispatched', 'in_transit', 'arrived', 'delivered', 'validated')
      and projection.origin_latitude is not null
      and projection.origin_longitude is not null
      and projection.destination_latitude is not null
      and projection.destination_longitude is not null
      and coalesce(projection.destination_published, false),
    now()
  )
  on conflict (source_type, source_id) do update set
    event_id = excluded.event_id,
    public_code = excluded.public_code,
    label = excluded.label,
    status = excluded.status,
    origin_label = excluded.origin_label,
    origin_latitude = excluded.origin_latitude,
    origin_longitude = excluded.origin_longitude,
    destination_label = excluded.destination_label,
    destination_latitude = excluded.destination_latitude,
    destination_longitude = excluded.destination_longitude,
    published = excluded.published,
    updated_at = now();
end;
$function$
