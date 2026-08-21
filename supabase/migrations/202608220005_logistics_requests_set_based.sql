-- B6 / G-068 · La segunda mitad: dejar de preguntar una vez por línea.
--
-- `202608220004` quitó la agregación de un millón de filas en cada lectura, y con eso
-- `logistics_requests` pasó de **no terminar en 20 s** a 3.186 ms. Sigue treinta veces por
-- encima de los 200 ms que exige la puerta de F3, y medir dijo dónde:
--
--   la consulta por línea cuesta 0,6 ms y usa índices correctamente
--   pero se ejecuta una vez por línea, y hay 20.000
--
-- Es decir: ya no es una consulta cara, es una consulta barata repetida veinte mil veces. Un
-- índice más no arregla eso; lo que hay que quitar es la repetición.
--
-- LO QUE CAMBIA Y LO QUE NO
-- ------------------------
-- Cambia **cómo** se calcula la disponibilidad de las líneas: una sola pasada que agrupa por
-- (bodega, categoría, unidad) y otra por lote, y después se une a las líneas. No cambia **qué**
-- se devuelve: mismas columnas, mismas claves en el JSON de `lines`, mismos valores. La
-- comprobación de que eso es cierto no es la lectura del código, es la prueba que compara
-- solicitud a solicitud la salida nueva contra la que da `transfer_request_lines`.
--
-- `transfer_request_lines` **no se toca**: para una sola solicitud N vale 1 y su forma está
-- bien. Lo que estaba mal era llamarla en cadena.

create or replace function public.logistics_requests(p_event_id uuid)
returns table(
  request_id uuid,
  request_code text,
  status public.transfer_status,
  origin_location_id uuid,
  origin_name text,
  providing_organization_id uuid,
  providing_organization_name text,
  destination_location_id uuid,
  destination_name text,
  requesting_organization_id uuid,
  requesting_organization_name text,
  justification text,
  decision_note text,
  requested_by uuid,
  requested_at timestamptz,
  need_case_id uuid,
  is_provider boolean,
  is_requester boolean,
  lines jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    -- Las compuertas se evalúan una vez por solicitud, como antes, pero el resultado se
    -- reutiliza en vez de recalcularse dentro de cada línea.
    select
      request.*,
      public.is_org_member(request.organization_id, request.event_id) as es_proveedora,
      public.is_org_member(request.requesting_organization_id, request.event_id) as es_solicitante
    from public.transfer_requests as request
    where request.event_id = p_event_id
  ), alcance as (
    select * from visible where es_proveedora or es_solicitante
  ), posicion as (
    -- Una sola lectura del saldo, acotada a las bodegas de origen que intervienen. Con la
    -- caché de `202608220004` esto es una pasada sobre una fila por lote, no una agregación
    -- del Kardex.
    select
      lot_position.location_id,
      lot_position.category,
      lot_position.unit,
      lot_position.lot_id,
      lot_position.quantity_available
    from public.inventory_lot_positions as lot_position
    where lot_position.status in ('available','reserved')
      and lot_position.location_id in (select distinct origin_location_id from alcance)
  ), por_grupo as (
    -- Disponible cuando la línea no fija lote: todo lo de esa categoría y unidad en la bodega.
    select location_id, category, unit, sum(quantity_available) as disponible
    from posicion
    group by location_id, category, unit
  ), por_lote as (
    -- Disponible cuando la línea sí fija lote: solo ese lote, y solo si está en esa bodega.
    select location_id, category, unit, lot_id, sum(quantity_available) as disponible
    from posicion
    group by location_id, category, unit, lot_id
  ), lineas as (
    select
      item.transfer_request_id,
      jsonb_agg(
        jsonb_build_object(
          'item_id', item.id,
          'line_no', item.line_no,
          'category', item.category,
          'unit', item.unit,
          'request_mode', item.request_mode,
          'lot_id', item.lot_id,
          'lot_code', lot.lot_code,
          'quantity_requested', item.quantity_requested,
          'quantity_authorized', item.quantity_authorized,
          'quantity_available_now', coalesce(
            case when item.lot_id is null then grupo.disponible else lote_exacto.disponible end,
            0
          )
        )
        order by item.line_no
      ) as detalle
    from public.transfer_request_items as item
    join alcance as request on request.id = item.transfer_request_id
    left join public.inventory_lots as lot on lot.id = item.lot_id
    left join por_grupo as grupo
      on item.lot_id is null
      and grupo.location_id = request.origin_location_id
      and grupo.category = item.category
      and grupo.unit = item.unit
    left join por_lote as lote_exacto
      on item.lot_id is not null
      and lote_exacto.location_id = request.origin_location_id
      and lote_exacto.category = item.category
      and lote_exacto.unit = item.unit
      and lote_exacto.lot_id = item.lot_id
    group by item.transfer_request_id
  )
  select
    request.id,
    request.request_code,
    request.status,
    request.origin_location_id,
    origin.name,
    request.organization_id,
    provider.name,
    request.destination_location_id,
    destination.name,
    request.requesting_organization_id,
    requester.name,
    request.justification,
    request.decision_note,
    request.requested_by,
    request.requested_at,
    request.need_case_id,
    request.es_proveedora,
    request.es_solicitante,
    coalesce(lineas.detalle, '[]'::jsonb)
  from alcance as request
  join public.inventory_locations as origin on origin.id = request.origin_location_id
  join public.inventory_locations as destination on destination.id = request.destination_location_id
  join public.organizations as provider on provider.id = request.organization_id
  join public.organizations as requester on requester.id = request.requesting_organization_id
  left join lineas on lineas.transfer_request_id = request.id
  order by request.requested_at desc;
$$;

comment on function public.logistics_requests(uuid) is
  'Solicitudes logisticas del evento con sus lineas y la disponibilidad vigente, calculada en una sola pasada de conjunto. Antes se preguntaba una vez por linea: 20.000 consultas de 0,6 ms (B6).';

-- El camino que la pasada nueva recorre: las lineas de las solicitudes del evento.
create index if not exists transfer_request_items_request_idx
  on public.transfer_request_items (transfer_request_id, line_no);
