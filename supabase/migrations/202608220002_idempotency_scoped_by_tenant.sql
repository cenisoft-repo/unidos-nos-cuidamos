-- B5 · La clave de idempotencia se buscaba sin decir de quien era.
--
-- El loop de escala anotaba esto como un problema de rendimiento —«son cuatro indices», el
-- mejor coste/beneficio de la lista— porque las cuatro funciones buscan `idempotency_key`
-- sin aportar `organization_id`, y el unico indice es `unique (organization_id,
-- idempotency_key)`, sin prefijo aprovechable. Medido en F0 sobre 980.007 movimientos, esa
-- busqueda tarda 43 ms y recorre la tabla entera.
--
-- Al ir a ponerlos aparecio que el defecto no es de rendimiento. La unicidad es POR
-- ORGANIZACION, asi que dos organizaciones pueden usar la misma clave legitimamente, y las
-- cuatro busquedas son la PRIMERA sentencia de su funcion, antes de resolver ninguna
-- organizacion. Buscan en todas.
--
-- Comprobado contra la base, no razonado:
--
--   La organizacion 2 pide recibir 7 litros con una clave que la organizacion 1 ya uso.
--   -> se le devuelve el lote de la organizacion 1
--   -> queda 1 movimiento de Kardex donde deberia haber 2
--   -> su inventario real es 0 litros mientras cree haber recibido 7
--
-- Es decir: el Kardex —la fuente de verdad, regla innegociable numero 1— pierde una
-- recepcion en silencio, y una organizacion recibe el identificador de inventario de otra.
-- `reconcile_sandbox_payment` hace lo mismo sobre el LIBRO FINANCIERO.
--
-- Por eso esto NO añade cuatro indices. Acota las cuatro busquedas por la organizacion que
-- la propia funcion ya conoce por sus parametros, lo que:
--
--   a) cierra la colision entre organizaciones, que es un defecto de correccion;
--   b) hace utilizable el indice unico que YA existe, con lo que el problema de rendimiento
--      desaparece sin añadir un solo indice nuevo que mantener en tablas que crecen a 10^8.
--
-- Se cambia unicamente la sentencia de busqueda de cada funcion: el resto del cuerpo es
-- exactamente el que estaba desplegado, tomado de la definicion viva.


-- ---------------------------------------------------------------- receive_donation

CREATE OR REPLACE FUNCTION public.receive_donation(p_donation_item_id uuid, p_location_id uuid, p_accepted numeric, p_rejected numeric, p_condition text, p_idempotency_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item public.donation_items;
declare donation public.donations;
declare location public.inventory_locations;
declare existing uuid;
declare lot_id uuid;
begin
  -- B5 · La clave de idempotencia es unica POR ORGANIZACION, asi que buscarla sola
  -- encuentra la de otra. Se acota por la organizacion del aporte que se esta recibiendo.
  select l.id into existing from public.inventory_lots l
    join public.stock_movements s on s.lot_id = l.id
    where s.idempotency_key = p_idempotency_key
      and s.organization_id = (
        select propietaria.organization_id
        from public.donation_items as articulo
        join public.donations as propietaria on propietaria.id = articulo.donation_id
        where articulo.id = p_donation_item_id
      );
  if found then return existing; end if;

  select * into item from public.donation_items where id = p_donation_item_id for update;
  select * into donation from public.donations where id = item.donation_id for update;
  select * into location from public.inventory_locations where id = p_location_id;
  if not found or item.id is null or donation.id is null then raise exception using errcode = 'P0002', message = 'Donación o centro no encontrado'; end if;
  if not public.has_any_role(donation.organization_id, donation.event_id, array['warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes recibir en este centro';
  end if;
  if location.organization_id <> donation.organization_id or location.event_id <> donation.event_id then
    raise exception using errcode = '42501', message = 'Centro fuera del tenant';
  end if;
  if not public.has_location_scope(
    location.id,
    array['warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Esa bodega no está dentro de tu alcance';
  end if;
  if p_accepted < 0 or p_rejected < 0 or item.quantity_received + item.quantity_rejected + p_accepted + p_rejected > item.quantity_promised then
    raise exception using errcode = '22023', message = 'Las cantidades no concilian con la promesa';
  end if;
  if p_accepted = 0 then
    update public.donation_items set quantity_rejected = quantity_rejected + p_rejected where id = item.id;
    update public.donations set status = 'rejected' where id = donation.id;
    return null;
  end if;

  insert into public.inventory_lots(event_id, organization_id, donation_item_id, location_id, category, quantity_initial, unit, condition, received_by)
  values (donation.event_id, donation.organization_id, item.id, location.id, item.category, p_accepted, item.unit, p_condition, (select auth.uid()))
  returning id into lot_id;
  insert into public.stock_movements(event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id)
  values (donation.event_id, donation.organization_id, lot_id, 'receipt', p_accepted, p_idempotency_key, 'Recepción aceptada', (select auth.uid()));
  update public.donation_items set quantity_received = quantity_received + p_accepted, quantity_rejected = quantity_rejected + p_rejected where id = item.id;
  update public.donations set status = case when p_accepted + p_rejected < item.quantity_promised then 'partial'::public.donation_status else 'received'::public.donation_status end where id = donation.id;
  return lot_id;
end;
$function$;

-- ---------------------------------------------------------------- reserve_lot_quantity

CREATE OR REPLACE FUNCTION public.reserve_lot_quantity(p_lot_id uuid, p_quantity numeric, p_need_item_id uuid, p_transfer_request_id uuid, p_transfer_request_item_id uuid, p_idempotency_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  lot public.inventory_lots;
  available numeric;
  allocation_id uuid;
begin
  -- B5 · acotada por la organizacion dueña del lote que se reserva.
  select existing.id into allocation_id
  from public.allocations as existing
  where existing.idempotency_key = p_idempotency_key
    and existing.organization_id = (
      select alcance.organization_id from public.inventory_lots as alcance
      where alcance.id = p_lot_id
    );
  if allocation_id is not null then
    return allocation_id;
  end if;

  select * into lot from public.inventory_lots where id = p_lot_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lote no encontrado';
  end if;
  if lot.status not in ('available','reserved') then
    raise exception using errcode = '22023', message = 'El lote está bloqueado o no disponible';
  end if;

  select coalesce(sum(movement.quantity_delta), 0) into available
  from public.stock_movements as movement
  where movement.lot_id = p_lot_id;

  if p_quantity <= 0 or available < p_quantity then
    raise exception using errcode = '22023', message = 'Existencia insuficiente';
  end if;

  insert into public.allocations(
    event_id, organization_id, lot_id, need_item_id, transfer_request_id, transfer_request_item_id,
    quantity, idempotency_key, allocated_by
  ) values (
    lot.event_id, lot.organization_id, lot.id, p_need_item_id, p_transfer_request_id, p_transfer_request_item_id,
    p_quantity, p_idempotency_key, (select auth.uid())
  )
  returning id into allocation_id;

  insert into public.stock_movements(
    event_id, organization_id, lot_id, movement_type, quantity_delta,
    idempotency_key, reason, actor_id
  ) values (
    lot.event_id, lot.organization_id, lot.id, 'reserve', -p_quantity,
    p_idempotency_key || ':stock',
    case when p_transfer_request_id is null then 'Reserva para necesidad' else 'Reserva para solicitud logística' end,
    (select auth.uid())
  );

  update public.inventory_lots
  set status = case when available = p_quantity then 'reserved'::public.lot_status else status end
  where id = lot.id;

  return allocation_id;
end;
$function$;

-- ---------------------------------------------------------------- create_shipment

CREATE OR REPLACE FUNCTION public.create_shipment(p_allocation_id uuid, p_transfer_request_id uuid, p_origin_location_id uuid, p_destination_location_id uuid, p_public_destination text, p_transport jsonb, p_idempotency_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  shipment_id uuid;
  origin public.inventory_locations;
  destination public.inventory_locations;
  request public.transfer_requests;
  target public.allocations;
  shipment_event uuid;
  shipment_organization uuid;
  destination_label text;
  transport jsonb := coalesce(p_transport, '{}'::jsonb);
  allocation_count integer;
begin
  -- B5 · acotada por la organizacion de la bodega de origen, que mas abajo esta funcion
  -- ya obliga a coincidir con la del despacho.
  select existing.id into shipment_id from public.shipments as existing
  where existing.idempotency_key = p_idempotency_key
    and existing.organization_id = (
      select alcance.organization_id from public.inventory_locations as alcance
      where alcance.id = p_origin_location_id
    );
  if shipment_id is not null then
    return shipment_id;
  end if;

  if (p_allocation_id is null) = (p_transfer_request_id is null) then
    raise exception using errcode = '22023', message = 'Un despacho atiende una necesidad o un traslado, no ambos';
  end if;

  select * into origin from public.inventory_locations where id = p_origin_location_id;
  if origin.id is null then
    raise exception using errcode = '22023', message = 'Selecciona el punto desde el que sale el despacho';
  end if;
  if not origin.active or not origin.dispatches_shipments then
    raise exception using errcode = '22023', message = 'Ese punto no está habilitado para despachar salidas';
  end if;

  if p_transfer_request_id is not null then
    select * into request from public.transfer_requests where id = p_transfer_request_id for update;
    if request.id is null then
      raise exception using errcode = 'P0002', message = 'Solicitud de traslado no encontrada';
    end if;
    if request.status <> 'authorized' then
      raise exception using errcode = '22023', message = 'Solo un traslado autorizado puede prepararse';
    end if;
    if request.origin_location_id <> origin.id then
      raise exception using errcode = '22023', message = 'El origen no coincide con el autorizado en la solicitud';
    end if;
    select * into destination from public.inventory_locations
    where id = coalesce(p_destination_location_id, request.destination_location_id);
    if destination.id is null or destination.id <> request.destination_location_id then
      raise exception using errcode = '22023', message = 'El destino no coincide con el autorizado en la solicitud';
    end if;
    shipment_event := request.event_id;
    shipment_organization := request.organization_id;
    destination_label := destination.public_location_text;
  else
    select * into target from public.allocations where id = p_allocation_id for update;
    if target.id is null or target.status <> 'reserved' then
      raise exception using errcode = '22023', message = 'La asignación no está disponible para despacho';
    end if;
    if target.transfer_request_id is not null then
      raise exception using errcode = '22023', message = 'Esa reserva pertenece a un traslado; prepáralo desde la solicitud';
    end if;
    if p_destination_location_id is not null then
      raise exception using errcode = '22023', message = 'Un despacho hacia una necesidad no lleva bodega de destino';
    end if;
    if char_length(btrim(coalesce(p_public_destination, ''))) not between 3 and 180 then
      raise exception using errcode = '22023', message = 'Describe públicamente la zona de destino';
    end if;
    if public.contains_sensitive_content(p_public_destination) then
      raise exception using errcode = '22023', message = 'El destino público no puede incluir teléfonos, cuentas ni enlaces';
    end if;
    shipment_event := target.event_id;
    shipment_organization := target.organization_id;
    destination_label := btrim(p_public_destination);
  end if;

  if origin.organization_id <> shipment_organization or origin.event_id <> shipment_event then
    raise exception using errcode = '42501', message = 'El punto de origen pertenece a otra organización o evento';
  end if;
  if not public.has_any_role(
    shipment_organization, shipment_event,
    array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes crear este despacho';
  end if;
  if not public.has_location_scope(
    origin.id,
    array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Esa bodega de origen no está dentro de tu alcance';
  end if;

  insert into public.shipments(
    event_id, organization_id, status, public_destination, origin_location_id,
    destination_location_id, transfer_request_id,
    transport_mode, transport_company, transport_contact_name, transport_contact_document,
    transport_contact_phone, transport_vehicle, transport_plate, transport_responsible,
    created_by, idempotency_key
  ) values (
    shipment_event, shipment_organization, 'preparing', destination_label, origin.id,
    destination.id, request.id,
    nullif(btrim(transport ->> 'mode'), ''),
    nullif(btrim(transport ->> 'company'), ''),
    nullif(btrim(transport ->> 'contact_name'), ''),
    nullif(btrim(transport ->> 'contact_document'), ''),
    nullif(btrim(transport ->> 'contact_phone'), ''),
    nullif(btrim(transport ->> 'vehicle'), ''),
    upper(nullif(btrim(transport ->> 'plate'), '')),
    nullif(btrim(transport ->> 'responsible'), ''),
    (select auth.uid()), p_idempotency_key
  )
  returning id into shipment_id;

  if p_transfer_request_id is not null then
    insert into public.shipment_items(shipment_id, allocation_id, quantity)
    select shipment_id, allocation.id, allocation.quantity
    from public.allocations as allocation
    where allocation.transfer_request_id = request.id
      and allocation.status = 'reserved';
    get diagnostics allocation_count = row_count;
    if allocation_count = 0 then
      raise exception using errcode = '22023', message = 'El traslado no tiene existencias reservadas para despachar';
    end if;
  else
    insert into public.shipment_items(shipment_id, allocation_id, quantity)
    values (shipment_id, target.id, target.quantity);
  end if;

  return shipment_id;
end;
$function$;

-- ---------------------------------------------------------------- reconcile_sandbox_payment

CREATE OR REPLACE FUNCTION public.reconcile_sandbox_payment(p_fund_id uuid, p_amount numeric, p_provider_reference text, p_idempotency_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target_fund public.funds;
declare tx_id uuid;
begin
  -- B5 · acotada por la organizacion del fondo. Sin esto, esta funcion podia devolver el
  -- identificador de un asiento del LIBRO FINANCIERO de otra organizacion.
  select id into tx_id from public.financial_transactions
  where idempotency_key = p_idempotency_key
    and organization_id = (
      select alcance.organization_id from public.funds as alcance where alcance.id = p_fund_id
    );
  if found then return tx_id; end if;
  select * into target_fund from public.funds where id = p_fund_id for update;
  if not found or not target_fund.verified then raise exception using errcode = '22023', message = 'El fondo no está verificado'; end if;
  if not public.has_any_role(target_fund.organization_id, target_fund.event_id, array['treasury_approver','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes conciliar este fondo';
  end if;
  if p_amount <= 0 then raise exception using errcode = '22023', message = 'Monto inválido'; end if;
  insert into public.financial_transactions(event_id, organization_id, fund_id, transaction_type, amount, status, provider, provider_reference_private, public_reference, idempotency_key, actor_id, reconciled_at)
  values (target_fund.event_id, target_fund.organization_id, target_fund.id, 'credit', p_amount, 'reconciled', 'sandbox', p_provider_reference, 'SANDBOX-' || right(encode(extensions.digest(p_provider_reference, 'sha256'), 'hex'), 8), p_idempotency_key, (select auth.uid()), now())
  returning id into tx_id;
  return tx_id;
end;
$function$;
