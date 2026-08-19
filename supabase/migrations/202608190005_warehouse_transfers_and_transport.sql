-- Fases 7 y 9 a 14 del loop de consolidación.
--
-- Lo que faltaba y aquí se construye:
--
--   Fase 7  · el alcance del administrador llega hasta la bodega, no solo hasta la organización.
--   Fase 9  · Centro A → Centro B con cantidades parciales y la unidad conservada.
--   Fase 10 · la autorización reserva antes de que nada salga físicamente.
--   Fase 11 · Solicitar → Revisar → Autorizar → Preparar → Despachar, cada paso con actor y fecha.
--   Fase 12 · sin datos de transporte no hay salida.
--   Fase 13 · Preparando → Despachado → En movimiento → Llegó → Recibido.
--   Fase 14 · el destino confirma; faltante y daño se registran por separado.
--
-- Nada de esto crea una segunda forma de mover inventario: la reserva sigue siendo una fila de
-- `allocations` con su movimiento `reserve`, y la salida sigue siendo `release` + `dispatch`.
-- El traslado entre bodegas reutiliza esas mismas piezas y estrena `transfer_in`, que estaba
-- declarado en el enum desde el principio y nunca se había usado.

-- ============================================================ 1. alcance por bodega (Fase 7)

create table public.membership_locations (
  membership_id uuid not null references public.memberships(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (membership_id, location_id)
);

alter table public.membership_locations enable row level security;
revoke all on table public.membership_locations from public, anon, authenticated;
grant select on table public.membership_locations to authenticated;

create policy "members read own location scope"
  on public.membership_locations for select to authenticated
  using (exists (
    select 1 from public.memberships as membership
    where membership.id = membership_id
      and membership.user_id = (select auth.uid())
  ));

comment on table public.membership_locations is
  'Bodegas concretas que una membresía puede administrar. Sin filas, la membresía alcanza todos los puntos de su organización.';

-- Alcance efectivo sobre un punto: rol vigente en la organización del punto y, si la membresía
-- declara bodegas, que el punto esté entre ellas.
create or replace function public.has_location_scope(p_location_id uuid, allowed_roles public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.inventory_locations as location
    join public.memberships as membership
      on membership.organization_id = location.organization_id
     and membership.event_id = location.event_id
    where location.id = p_location_id
      and membership.user_id = (select auth.uid())
      and membership.active
      and membership.role = any(allowed_roles)
      and (
        not exists (
          select 1 from public.membership_locations as scope
          where scope.membership_id = membership.id
        )
        or exists (
          select 1 from public.membership_locations as scope
          where scope.membership_id = membership.id
            and scope.location_id = location.id
        )
      )
  );
$$;

revoke all on function public.has_location_scope(uuid, public.app_role[]) from public, anon, authenticated;
grant execute on function public.has_location_scope(uuid, public.app_role[]) to authenticated;
comment on function public.has_location_scope(uuid, public.app_role[]) is
  'Alcance del actor sobre una bodega concreta; conserva el comportamiento anterior cuando la membresía no declara bodegas.';

-- Administración del alcance. Reemplaza el conjunto completo para que quede declarativo.
create or replace function public.set_membership_locations(p_membership_id uuid, p_location_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare
  membership public.memberships;
  invalid integer;
begin
  select * into membership from public.memberships where id = p_membership_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Membresía no encontrada';
  end if;
  if not public.has_any_role(
    membership.organization_id,
    membership.event_id,
    array['event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Solo la administración del evento define el alcance por bodega';
  end if;

  select count(*)::integer into invalid
  from unnest(coalesce(p_location_ids, '{}'::uuid[])) as requested(location_id)
  where not exists (
    select 1 from public.inventory_locations as location
    where location.id = requested.location_id
      and location.organization_id = membership.organization_id
      and location.event_id = membership.event_id
  );
  if invalid > 0 then
    raise exception using errcode = '42501', message = 'Alguna bodega no pertenece a la organización de esa membresía';
  end if;

  delete from public.membership_locations where membership_id = p_membership_id;
  insert into public.membership_locations(membership_id, location_id)
  select p_membership_id, location_id
  from unnest(coalesce(p_location_ids, '{}'::uuid[])) as granted(location_id)
  on conflict do nothing;

  return coalesce(array_length(p_location_ids, 1), 0);
end;
$$;

revoke all on function public.set_membership_locations(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.set_membership_locations(uuid, uuid[]) to authenticated;
comment on function public.set_membership_locations(uuid, uuid[]) is
  'Define qué bodegas administra una membresía; un arreglo vacío devuelve el alcance a toda la organización.';

-- ============================================================ 2. solicitud de traslado

create type public.transfer_status as enum (
  'requested', 'authorized', 'rejected', 'dispatched', 'closed', 'cancelled'
);

create table public.transfer_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  request_code text not null unique default public.generate_tracking_code('SOL'),
  origin_location_id uuid not null references public.inventory_locations(id),
  destination_location_id uuid not null references public.inventory_locations(id),
  category text not null,
  unit text not null,
  quantity_requested numeric(14,3) not null check (quantity_requested > 0),
  quantity_authorized numeric(14,3) not null default 0 check (quantity_authorized >= 0),
  status public.transfer_status not null default 'requested',
  justification text not null check (char_length(btrim(justification)) between 10 and 500),
  decision_note text,
  idempotency_key text not null,
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  check (origin_location_id <> destination_location_id),
  check (quantity_authorized <= quantity_requested)
);

create index transfer_requests_queue_idx
  on public.transfer_requests (event_id, status, requested_at);
create index transfer_requests_origin_idx on public.transfer_requests (origin_location_id);
create index transfer_requests_destination_idx on public.transfer_requests (destination_location_id);
create index transfer_requests_requested_by_idx on public.transfer_requests (requested_by);
create index transfer_requests_decided_by_idx on public.transfer_requests (decided_by);

create trigger transfer_requests_updated_at
  before update on public.transfer_requests
  for each row execute function public.set_updated_at();
create trigger transfer_requests_audit
  after insert or update or delete on public.transfer_requests
  for each row execute function public.audit_row_change();

alter table public.transfer_requests enable row level security;
revoke all on table public.transfer_requests from public, anon, authenticated;
grant select on table public.transfer_requests to authenticated;

create policy "org members read transfer requests"
  on public.transfer_requests for select to authenticated
  using (public.is_org_member(organization_id, event_id));

comment on table public.transfer_requests is
  'Solicitud de traslado entre bodegas de la misma organización: Solicitar → Revisar → Autorizar → Preparar → Despachar.';
comment on column public.transfer_requests.quantity_authorized is
  'Cantidad realmente autorizada; puede ser menor que la solicitada y nunca mayor.';

-- Una reserva puede responder a una necesidad ciudadana o a un traslado entre bodegas, nunca a
-- las dos cosas ni a ninguna.
alter table public.allocations
  alter column need_item_id drop not null,
  add column transfer_request_id uuid references public.transfer_requests(id);

alter table public.allocations
  add constraint allocations_single_destination
  check ((need_item_id is not null) <> (transfer_request_id is not null));

create index allocations_transfer_request_idx
  on public.allocations (transfer_request_id) where transfer_request_id is not null;

comment on column public.allocations.transfer_request_id is
  'Traslado que originó la reserva; excluyente con need_item_id.';

-- ============================================================ 3. transporte y destino

alter table public.shipments
  add column transfer_request_id uuid references public.transfer_requests(id),
  add column destination_location_id uuid references public.inventory_locations(id),
  add column transport_mode text check (transport_mode in ('transportadora','particular','institucional')),
  add column transport_company text,
  add column transport_contact_name text,
  add column transport_contact_document text,
  add column transport_contact_phone text,
  add column transport_vehicle text,
  add column transport_plate text,
  add column transport_responsible text;

create index shipments_transfer_request_idx
  on public.shipments (transfer_request_id) where transfer_request_id is not null;
create index shipments_destination_location_idx
  on public.shipments (destination_location_id) where destination_location_id is not null;

comment on column public.shipments.destination_location_id is
  'Bodega de destino cuando el despacho es un traslado; nulo cuando el destino es una necesidad publicada.';
comment on column public.shipments.transport_mode is
  'Transportadora, particular o vehículo institucional. Sin este dato el despacho no puede salir.';

-- Datos mínimos de transporte exigidos por la regla de negocio antes de EN MOVIMIENTO.
create or replace function public.assert_transport_ready(p_shipment_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
declare shipment public.shipments;
begin
  select * into shipment from public.shipments where id = p_shipment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Despacho no encontrado';
  end if;
  if shipment.transport_mode is null then
    raise exception using errcode = '22023', message = 'Indica si el transporte es transportadora, particular o institucional';
  end if;
  if coalesce(btrim(shipment.transport_contact_name), '') = ''
     or coalesce(btrim(shipment.transport_contact_document), '') = ''
     or coalesce(btrim(shipment.transport_contact_phone), '') = '' then
    raise exception using errcode = '22023', message = 'Registra nombre, identificación y teléfono de quien transporta';
  end if;
  if coalesce(btrim(shipment.transport_plate), '') = ''
     or coalesce(btrim(shipment.transport_vehicle), '') = '' then
    raise exception using errcode = '22023', message = 'Registra el vehículo y la placa que llevan la carga';
  end if;
  if coalesce(btrim(shipment.transport_responsible), '') = '' then
    raise exception using errcode = '22023', message = 'Registra quién responde por la carga durante el traslado';
  end if;
  if shipment.transport_mode = 'transportadora'
     and coalesce(btrim(shipment.transport_company), '') = '' then
    raise exception using errcode = '22023', message = 'Registra la empresa transportadora';
  end if;
end;
$$;

revoke all on function public.assert_transport_ready(uuid) from public, anon, authenticated;
comment on function public.assert_transport_ready(uuid) is
  'Regla de negocio de la Fase 12: sin transporte completo un despacho no puede pasar a EN MOVIMIENTO.';

-- ============================================================ 4. reserva única (Fase 10)

-- Primitiva única de reserva. Reservar contra una necesidad y reservar contra un traslado
-- comparten exactamente la misma escritura: una fila en `allocations` y un movimiento `reserve`.
create or replace function public.reserve_lot_quantity(
  p_lot_id uuid,
  p_quantity numeric,
  p_need_item_id uuid,
  p_transfer_request_id uuid,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  lot public.inventory_lots;
  available numeric;
  allocation_id uuid;
begin
  select existing.id into allocation_id
  from public.allocations as existing
  where existing.idempotency_key = p_idempotency_key;
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
    event_id, organization_id, lot_id, need_item_id, transfer_request_id,
    quantity, idempotency_key, allocated_by
  ) values (
    lot.event_id, lot.organization_id, lot.id, p_need_item_id, p_transfer_request_id,
    p_quantity, p_idempotency_key, (select auth.uid())
  )
  returning id into allocation_id;

  insert into public.stock_movements(
    event_id, organization_id, lot_id, movement_type, quantity_delta,
    idempotency_key, reason, actor_id
  ) values (
    lot.event_id, lot.organization_id, lot.id, 'reserve', -p_quantity,
    p_idempotency_key || ':stock',
    case when p_transfer_request_id is null then 'Reserva para necesidad' else 'Reserva para traslado entre bodegas' end,
    (select auth.uid())
  );

  update public.inventory_lots
  set status = case when available = p_quantity then 'reserved'::public.lot_status else status end
  where id = lot.id;

  return allocation_id;
end;
$$;

revoke all on function public.reserve_lot_quantity(uuid, numeric, uuid, uuid, text) from public, anon, authenticated;
comment on function public.reserve_lot_quantity(uuid, numeric, uuid, uuid, text) is
  'Única escritura de reserva del sistema; la usan la asignación a una necesidad y la autorización de un traslado.';

-- La asignación contra una necesidad conserva su contrato y deja de tener escritura propia.
create or replace function public.allocate_stock(
  p_lot_id uuid,
  p_need_item_id uuid,
  p_quantity numeric,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  lot public.inventory_lots;
  need_item public.need_items;
begin
  select * into lot from public.inventory_lots where id = p_lot_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lote no encontrado';
  end if;
  if not public.has_any_role(
    lot.organization_id,
    lot.event_id,
    array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes asignar este lote';
  end if;
  if not public.has_location_scope(
    lot.location_id,
    array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Esa bodega no está dentro de tu alcance';
  end if;

  select * into need_item from public.need_items where id = p_need_item_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Necesidad no encontrada';
  end if;
  if need_item.unit <> lot.unit or need_item.category <> lot.category then
    raise exception using errcode = '22023', message = 'Categoría o unidad incompatible';
  end if;

  return public.reserve_lot_quantity(p_lot_id, p_quantity, p_need_item_id, null, p_idempotency_key);
end;
$$;

revoke all on function public.allocate_stock(uuid, uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.allocate_stock(uuid, uuid, numeric, text) to authenticated;
comment on function public.allocate_stock(uuid, uuid, numeric, text) is
  'Reserva existencia contra una necesidad compatible; delega la escritura en reserve_lot_quantity.';

-- ============================================================ 5. solicitar y autorizar (Fases 9 y 11)

create or replace function public.request_stock_transfer(
  p_origin_location_id uuid,
  p_destination_location_id uuid,
  p_category text,
  p_unit text,
  p_quantity numeric,
  p_justification text,
  p_idempotency_key text
)
returns table(request_id uuid, request_code text, status public.transfer_status, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  origin public.inventory_locations;
  destination public.inventory_locations;
  existing public.transfer_requests;
  created public.transfer_requests;
begin
  select * into origin from public.inventory_locations where id = p_origin_location_id;
  select * into destination from public.inventory_locations where id = p_destination_location_id;
  if origin.id is null or destination.id is null then
    raise exception using errcode = 'P0002', message = 'Bodega de origen o destino no encontrada';
  end if;
  if origin.id = destination.id then
    raise exception using errcode = '22023', message = 'El origen y el destino deben ser bodegas distintas';
  end if;
  if origin.organization_id <> destination.organization_id or origin.event_id <> destination.event_id then
    raise exception using errcode = '42501', message = 'Ambas bodegas deben pertenecer a la misma organización y evento';
  end if;
  if not origin.active or not origin.dispatches_shipments then
    raise exception using errcode = '22023', message = 'La bodega de origen no está habilitada para despachar';
  end if;
  if not destination.active or not destination.accepts_donations then
    raise exception using errcode = '22023', message = 'La bodega de destino no está habilitada para recibir';
  end if;

  -- Solicita quien administra la bodega que necesita el producto.
  if not public.has_location_scope(
    destination.id,
    array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No administras la bodega que solicita';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception using errcode = '22023', message = 'La cantidad solicitada debe ser mayor que cero';
  end if;
  if char_length(btrim(coalesce(p_justification, ''))) not between 10 and 500 then
    raise exception using errcode = '22023', message = 'Explica en 10 a 500 caracteres por qué se necesita el traslado';
  end if;
  if public.contains_sensitive_content(p_justification) then
    raise exception using errcode = '22023', message = 'La justificación no puede incluir teléfonos, cuentas ni enlaces';
  end if;

  select * into existing
  from public.transfer_requests as candidate
  where candidate.organization_id = origin.organization_id
    and candidate.idempotency_key = p_idempotency_key;
  if existing.id is not null then
    return query select existing.id, existing.request_code, existing.status, true;
    return;
  end if;

  insert into public.transfer_requests(
    event_id, organization_id, origin_location_id, destination_location_id,
    category, unit, quantity_requested, justification, idempotency_key, requested_by
  ) values (
    origin.event_id, origin.organization_id, origin.id, destination.id,
    btrim(p_category), btrim(p_unit), p_quantity, btrim(p_justification), p_idempotency_key, (select auth.uid())
  )
  returning * into created;

  return query select created.id, created.request_code, created.status, false;
end;
$$;

revoke all on function public.request_stock_transfer(uuid, uuid, text, text, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.request_stock_transfer(uuid, uuid, text, text, numeric, text, text)
  to authenticated;
comment on function public.request_stock_transfer(uuid, uuid, text, text, numeric, text, text) is
  'Una bodega pide producto a otra de su misma organización. No mueve inventario: solo abre la solicitud.';

-- Autorizar reserva de inmediato (Fase 10): el producto queda comprometido antes de salir para
-- que ningún otro administrador despache la misma cantidad.
create or replace function public.decide_stock_transfer(
  p_request_id uuid,
  p_decision text,
  p_quantity_authorized numeric,
  p_note text
)
returns public.transfer_status
language plpgsql security definer set search_path = '' as $$
declare
  request public.transfer_requests;
  actor uuid := (select auth.uid());
  remaining numeric;
  taken numeric;
  candidate record;
begin
  select * into request from public.transfer_requests where id = p_request_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitud de traslado no encontrada';
  end if;
  if request.status <> 'requested' then
    return request.status;
  end if;
  if p_decision not in ('authorize','reject') then
    raise exception using errcode = '22023', message = 'Decisión inválida';
  end if;
  -- Autoriza quien administra la bodega de la que sale el producto.
  if not public.has_location_scope(
    request.origin_location_id,
    array['logistics_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No administras la bodega de origen';
  end if;
  if request.requested_by = actor then
    raise exception using errcode = '42501', message = 'Quien solicita no puede autorizar su propia solicitud';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Escribe la razón de la decisión';
  end if;

  if p_decision = 'reject' then
    update public.transfer_requests
    set status = 'rejected', decided_by = actor, decided_at = now(), decision_note = btrim(p_note)
    where id = request.id;
    return 'rejected'::public.transfer_status;
  end if;

  if p_quantity_authorized is null or p_quantity_authorized <= 0 then
    raise exception using errcode = '22023', message = 'La cantidad autorizada debe ser mayor que cero';
  end if;
  if p_quantity_authorized > request.quantity_requested then
    raise exception using errcode = '22023', message = 'No puedes autorizar más de lo solicitado';
  end if;

  -- Reserva por vencimiento más próximo primero, conservando la unidad de la solicitud.
  remaining := p_quantity_authorized;
  for candidate in
    select lot_position.lot_id, lot_position.quantity_available, lot.expires_on, lot.received_at
    from public.inventory_lot_positions as lot_position
    join public.inventory_lots as lot on lot.id = lot_position.lot_id
    where lot_position.location_id = request.origin_location_id
      and lot_position.category = request.category
      and lot_position.unit = request.unit
      and lot.status in ('available','reserved')
      and lot_position.quantity_available > 0
    order by lot.expires_on nulls last, lot.received_at
  loop
    exit when remaining <= 0;
    taken := least(remaining, candidate.quantity_available);
    perform public.reserve_lot_quantity(
      candidate.lot_id, taken, null, request.id,
      request.request_code || ':' || candidate.lot_id::text
    );
    remaining := remaining - taken;
  end loop;

  if remaining > 0 then
    raise exception using
      errcode = '22023',
      message = format('La bodega de origen no tiene %s %s disponibles de %s',
        public.format_quantity(p_quantity_authorized), request.unit, request.category);
  end if;

  update public.transfer_requests
  set status = 'authorized',
      quantity_authorized = p_quantity_authorized,
      decided_by = actor,
      decided_at = now(),
      decision_note = btrim(p_note)
  where id = request.id;

  return 'authorized'::public.transfer_status;
end;
$$;

revoke all on function public.decide_stock_transfer(uuid, text, numeric, text) from public, anon, authenticated;
grant execute on function public.decide_stock_transfer(uuid, text, numeric, text) to authenticated;
comment on function public.decide_stock_transfer(uuid, text, numeric, text) is
  'Autoriza total o parcialmente un traslado y deja la cantidad reservada; rechazar no toca el inventario.';

-- ============================================================ 6. preparar y despachar (Fases 11 a 13)

-- Un solo constructor de despachos para los dos destinos posibles: una necesidad publicada o
-- una bodega de la misma organización. Nace en «Preparando» y todavía no mueve inventario.
drop function if exists public.create_shipment(uuid, uuid, text, text, text);

create or replace function public.create_shipment(
  p_allocation_id uuid,
  p_transfer_request_id uuid,
  p_origin_location_id uuid,
  p_destination_location_id uuid,
  p_public_destination text,
  p_transport jsonb,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shipment_id uuid;
  origin public.inventory_locations;
  destination public.inventory_locations;
  request public.transfer_requests;
  target public.allocations;
  event_id uuid;
  organization_id uuid;
  destination_label text;
  transport jsonb := coalesce(p_transport, '{}'::jsonb);
  allocation_count integer;
begin
  select existing.id into shipment_id from public.shipments as existing
  where existing.idempotency_key = p_idempotency_key;
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
    event_id := request.event_id;
    organization_id := request.organization_id;
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
    event_id := target.event_id;
    organization_id := target.organization_id;
    destination_label := btrim(p_public_destination);
  end if;

  if origin.organization_id <> organization_id or origin.event_id <> event_id then
    raise exception using errcode = '42501', message = 'El punto de origen pertenece a otra organización o evento';
  end if;
  if not public.has_any_role(
    organization_id, event_id,
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
    event_id, organization_id, 'preparing', destination_label, origin.id,
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
$$;

revoke all on function public.create_shipment(uuid, uuid, uuid, uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.create_shipment(uuid, uuid, uuid, uuid, text, jsonb, text) to authenticated;
comment on function public.create_shipment(uuid, uuid, uuid, uuid, text, jsonb, text) is
  'Arma un despacho en «Preparando» hacia una necesidad o hacia otra bodega. No mueve existencias: la carga sigue reservada.';

-- La salida física. Aquí se exige el transporte y aquí, y solo aquí, el inventario sale.
create or replace function public.dispatch_shipment(p_shipment_id uuid)
returns public.shipment_status
language plpgsql security definer set search_path = '' as $$
declare
  shipment public.shipments;
  line record;
  donation_id uuid;
begin
  select * into shipment from public.shipments where id = p_shipment_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Despacho no encontrado';
  end if;
  if shipment.status <> 'preparing' then
    return shipment.status;
  end if;
  if not public.has_location_scope(
    shipment.origin_location_id,
    array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No administras la bodega de origen de este despacho';
  end if;

  perform public.assert_transport_ready(shipment.id);

  for line in
    select shipment_item.allocation_id, shipment_item.quantity, allocation.lot_id, lot.status as lot_status
    from public.shipment_items as shipment_item
    join public.allocations as allocation on allocation.id = shipment_item.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    where shipment_item.shipment_id = shipment.id
  loop
    if line.lot_status in ('quarantined','hold','recalled','disposed') then
      raise exception using errcode = '22023', message = 'El lote está bloqueado y no puede salir';
    end if;
    insert into public.stock_movements(
      event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id
    ) values (
      shipment.event_id, shipment.organization_id, line.lot_id, 'release', line.quantity,
      shipment.shipment_code || ':' || line.allocation_id::text || ':release',
      'Conversión de reserva a salida', (select auth.uid())
    );
    insert into public.stock_movements(
      event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id
    ) values (
      shipment.event_id, shipment.organization_id, line.lot_id,
      case when shipment.transfer_request_id is null then 'dispatch'::public.stock_movement_type
           else 'transfer_out'::public.stock_movement_type end,
      -line.quantity,
      shipment.shipment_code || ':' || line.allocation_id::text || ':out',
      case when shipment.transfer_request_id is null then 'Salida física despachada' else 'Salida hacia otra bodega' end,
      (select auth.uid())
    );
    update public.allocations set status = 'dispatched' where id = line.allocation_id;

    if shipment.transfer_request_id is null then
      select donation_item.donation_id into donation_id
      from public.inventory_lots as lot
      join public.donation_items as donation_item on donation_item.id = lot.donation_item_id
      where lot.id = line.lot_id;
      update public.donations set status = 'dispatched' where id = donation_id;
    end if;
  end loop;

  update public.shipments
  set status = 'dispatched', dispatched_at = now()
  where id = shipment.id;

  if shipment.transfer_request_id is not null then
    update public.transfer_requests set status = 'dispatched' where id = shipment.transfer_request_id;
  end if;

  return 'dispatched'::public.shipment_status;
end;
$$;

revoke all on function public.dispatch_shipment(uuid) from public, anon, authenticated;
grant execute on function public.dispatch_shipment(uuid) to authenticated;
comment on function public.dispatch_shipment(uuid) is
  'Saca físicamente la carga tras comprobar los datos mínimos de transporte; es el único punto donde la reserva se convierte en salida.';

-- Seguimiento del movimiento sin GPS: Despachado → En movimiento → Llegó.
create or replace function public.advance_shipment(p_shipment_id uuid, p_next_state text)
returns public.shipment_status
language plpgsql security definer set search_path = '' as $$
declare shipment public.shipments;
begin
  select * into shipment from public.shipments where id = p_shipment_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Despacho no encontrado';
  end if;
  if not public.has_any_role(
    shipment.organization_id, shipment.event_id,
    array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes actualizar este despacho';
  end if;
  if p_next_state not in ('in_transit','arrived') then
    raise exception using errcode = '22023', message = 'Estado de movimiento inválido';
  end if;
  if shipment.status::text = p_next_state then
    return shipment.status;
  end if;
  if p_next_state = 'in_transit' and shipment.status <> 'dispatched' then
    raise exception using errcode = '22023', message = 'Solo un despacho ya salido puede marcarse en movimiento';
  end if;
  if p_next_state = 'arrived' and shipment.status not in ('dispatched','in_transit') then
    raise exception using errcode = '22023', message = 'Solo un despacho en movimiento puede marcarse como llegado';
  end if;

  update public.shipments
  set status = p_next_state::public.shipment_status
  where id = shipment.id;

  return p_next_state::public.shipment_status;
end;
$$;

revoke all on function public.advance_shipment(uuid, text) from public, anon, authenticated;
grant execute on function public.advance_shipment(uuid, text) to authenticated;
comment on function public.advance_shipment(uuid, text) is
  'Avanza el seguimiento del movimiento entre Despachado, En movimiento y Llegó, sin depender de GPS.';

-- ============================================================ 7. recepción y conciliación (Fase 14)

-- Una sola implementación de «registrar entrega» para los dos destinos. El faltante deja de
-- disfrazarse de daño y, cuando el destino es una bodega, la confirmación —y solo ella— crea
-- el inventario de destino.
drop function if exists public.register_delivery(uuid, numeric, numeric, text);

create or replace function public.register_delivery(
  p_shipment_id uuid,
  p_quantity_delivered numeric,
  p_quantity_damaged numeric,
  p_quantity_missing numeric,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shipment public.shipments;
  shipped numeric;
  delivery_id uuid;
  line record;
  received numeric;
  new_lot uuid;
begin
  select delivery.id into delivery_id
  from public.deliveries as delivery
  where delivery.shipment_id = p_shipment_id
    and delivery.idempotency_key = p_idempotency_key;
  if delivery_id is not null then
    return delivery_id;
  end if;

  select * into shipment from public.shipments where id = p_shipment_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Despacho no encontrado';
  end if;
  if shipment.status not in ('dispatched','in_transit','arrived','incident') then
    raise exception using errcode = '22023', message = 'El despacho no admite entrega';
  end if;

  if shipment.transfer_request_id is null then
    if not public.has_any_role(
      shipment.organization_id, shipment.event_id,
      array['logistics_operator','event_admin']::public.app_role[]
    ) then
      raise exception using errcode = '42501', message = 'No puedes registrar esta entrega';
    end if;
  else
    -- Confirma quien administra la bodega de destino, no quien despachó.
    if not public.has_location_scope(
      shipment.destination_location_id,
      array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
    ) then
      raise exception using errcode = '42501', message = 'Solo la bodega de destino confirma lo que recibió';
    end if;
  end if;

  select coalesce(sum(shipment_item.quantity), 0) into shipped
  from public.shipment_items as shipment_item
  where shipment_item.shipment_id = shipment.id;

  if p_quantity_delivered < 0 or p_quantity_damaged < 0 or coalesce(p_quantity_missing, 0) < 0
     or p_quantity_delivered + p_quantity_damaged + coalesce(p_quantity_missing, 0) <> shipped then
    raise exception using
      errcode = '22023',
      message = format('Lo recibido, lo dañado y el faltante deben sumar %s', public.format_quantity(shipped));
  end if;

  insert into public.deliveries(
    shipment_id, status, quantity_delivered, quantity_damaged, quantity_missing,
    delivered_at, idempotency_key
  ) values (
    shipment.id,
    case when p_quantity_damaged > 0 or coalesce(p_quantity_missing, 0) > 0 then 'incident' else 'delivered' end,
    p_quantity_delivered, p_quantity_damaged, coalesce(p_quantity_missing, 0),
    now(), p_idempotency_key
  )
  returning id into delivery_id;

  update public.shipments
  set status = case
    when p_quantity_damaged > 0 or coalesce(p_quantity_missing, 0) > 0 then 'incident'::public.shipment_status
    else 'delivered'::public.shipment_status end
  where id = shipment.id;

  -- El inventario del destino nace aquí, con lo que el destino dice haber recibido, y conserva
  -- el vínculo con la donación que originó la carga.
  if shipment.transfer_request_id is not null and p_quantity_delivered > 0 then
    for line in
      select shipment_item.quantity, lot.donation_item_id, lot.category, lot.unit,
             lot.condition, lot.expires_on, lot.storage_requirement, allocation.id as allocation_id
      from public.shipment_items as shipment_item
      join public.allocations as allocation on allocation.id = shipment_item.allocation_id
      join public.inventory_lots as lot on lot.id = allocation.lot_id
      where shipment_item.shipment_id = shipment.id
    loop
      received := round(p_quantity_delivered * line.quantity / nullif(shipped, 0), 3);
      continue when received is null or received <= 0;
      insert into public.inventory_lots(
        event_id, organization_id, donation_item_id, location_id, category,
        quantity_initial, unit, condition, expires_on, storage_requirement, received_by
      ) values (
        shipment.event_id, shipment.organization_id, line.donation_item_id,
        shipment.destination_location_id, line.category,
        received, line.unit, line.condition, line.expires_on, line.storage_requirement,
        (select auth.uid())
      )
      returning id into new_lot;

      insert into public.stock_movements(
        event_id, organization_id, lot_id, movement_type, quantity_delta,
        idempotency_key, reason, actor_id
      ) values (
        shipment.event_id, shipment.organization_id, new_lot, 'transfer_in', received,
        p_idempotency_key || ':' || line.allocation_id::text || ':in',
        'Entrada por traslado confirmado en destino', (select auth.uid())
      );

      update public.allocations set status = 'delivered' where id = line.allocation_id;
    end loop;

    update public.transfer_requests set status = 'closed' where id = shipment.transfer_request_id;
  end if;

  return delivery_id;
end;
$$;

revoke all on function public.register_delivery(uuid, numeric, numeric, numeric, text) from public, anon, authenticated;
grant execute on function public.register_delivery(uuid, numeric, numeric, numeric, text) to authenticated;
comment on function public.register_delivery(uuid, numeric, numeric, numeric, text) is
  'El destino confirma lo recibido: CONFORME si concilia, NOVEDAD si hay daño o faltante. En un traslado, crea el inventario de destino.';

-- Estado de conciliación de un despacho, en el lenguaje de la Fase 14.
create or replace function public.shipment_reconciliation(p_shipment_id uuid)
returns table(
  shipment_code text,
  quantity_dispatched numeric,
  quantity_received numeric,
  quantity_damaged numeric,
  quantity_missing numeric,
  outcome text
)
language sql stable security invoker set search_path = '' as $$
  select
    shipment.shipment_code,
    coalesce(shipped.total, 0),
    coalesce(delivery.quantity_delivered, 0),
    coalesce(delivery.quantity_damaged, 0),
    coalesce(delivery.quantity_missing, 0),
    case
      when delivery.id is null then 'PENDIENTE'
      when coalesce(delivery.quantity_damaged, 0) = 0 and coalesce(delivery.quantity_missing, 0) = 0 then 'CONFORME'
      else 'NOVEDAD'
    end
  from public.shipments as shipment
  left join lateral (
    select sum(shipment_item.quantity) as total
    from public.shipment_items as shipment_item
    where shipment_item.shipment_id = shipment.id
  ) as shipped on true
  left join public.deliveries as delivery on delivery.shipment_id = shipment.id
  where shipment.id = p_shipment_id
  order by delivery.created_at desc nulls last
  limit 1;
$$;

revoke all on function public.shipment_reconciliation(uuid) from public, anon, authenticated;
grant execute on function public.shipment_reconciliation(uuid) to authenticated;
comment on function public.shipment_reconciliation(uuid) is
  'Despachado contra recibido de un despacho, con su resultado CONFORME o NOVEDAD.';

-- La validación independiente sigue siendo solo para entregas a una necesidad publicada.
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
  -- Un traslado entre bodegas no es una entrega final: se cierra cuando el destino confirma
  -- lo recibido, no con la validación independiente que publica impacto.
  if shipment.transfer_request_id is not null then
    raise exception using
      errcode = '22023',
      message = 'Un traslado entre bodegas se cierra con la confirmación del destino, no con validación de entrega';
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
comment on function public.validate_delivery(uuid, text) is
  'Validación independiente de una entrega a una necesidad publicada; rechaza los traslados entre bodegas.';

-- ============================================================ 8. ajustes de superficie

-- «Llegó» también es un estado visible del movimiento en la capa pública. Un traslado entre
-- bodegas sigue sin publicarse: la condición exige una necesidad publicada como destino.
create or replace function public.sync_public_shipment_projection(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
    coalesce(need_projection.location_label, shipment.public_destination) as destination_label,
    need_projection.latitude as destination_latitude,
    need_projection.longitude as destination_longitude,
    need_projection.published as destination_published
  into projection
  from public.shipments as shipment
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  left join public.inventory_locations as location on location.id = lot.location_id
  left join public.need_items as need_item on need_item.id = allocation.need_item_id
  left join public.need_cases as need_case on need_case.id = need_item.need_case_id
  left join public.public_need_projections as need_projection on need_projection.source_need_id = need_case.id
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
$$;

-- La recepción respeta el alcance por bodega de la Fase 7.
create or replace function public.receive_donation(
  p_donation_item_id uuid,
  p_location_id uuid,
  p_accepted numeric,
  p_rejected numeric,
  p_condition text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare item public.donation_items;
declare donation public.donations;
declare location public.inventory_locations;
declare existing uuid;
declare lot_id uuid;
begin
  select l.id into existing from public.inventory_lots l
    join public.stock_movements s on s.lot_id = l.id
    where s.idempotency_key = p_idempotency_key;
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
$$;

revoke all on function public.receive_donation(uuid, uuid, numeric, numeric, text, text) from public, anon, authenticated;
grant execute on function public.receive_donation(uuid, uuid, numeric, numeric, text, text) to authenticated;
comment on function public.receive_donation(uuid, uuid, numeric, numeric, text, text) is
  'Única creación de lote por recepción de una donación; exige rol y alcance sobre la bodega receptora.';

-- `carrier_name` quedó sustituido por los campos estructurados de transporte y ya no lo escribe
-- nadie. Se retira para no dejar dos lugares donde vive el mismo dato.
alter table public.shipments drop column carrier_name;

-- Un despacho puede armarse antes de saber quién lo lleva; lo que no puede es salir sin saberlo.
-- Esta es la única escritura de los datos de transporte y solo funciona mientras se prepara.
create or replace function public.set_shipment_transport(p_shipment_id uuid, p_transport jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shipment public.shipments;
  transport jsonb := coalesce(p_transport, '{}'::jsonb);
begin
  select * into shipment from public.shipments where id = p_shipment_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Despacho no encontrado';
  end if;
  if shipment.status <> 'preparing' then
    raise exception using errcode = '22023', message = 'El transporte solo puede cambiarse mientras el despacho se prepara';
  end if;
  if not public.has_location_scope(
    shipment.origin_location_id,
    array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No administras la bodega de origen de este despacho';
  end if;
  if transport ->> 'mode' is not null
     and transport ->> 'mode' not in ('transportadora','particular','institucional') then
    raise exception using errcode = '22023', message = 'Tipo de transporte inválido';
  end if;

  update public.shipments
  set transport_mode = nullif(btrim(transport ->> 'mode'), ''),
      transport_company = nullif(btrim(transport ->> 'company'), ''),
      transport_contact_name = nullif(btrim(transport ->> 'contact_name'), ''),
      transport_contact_document = nullif(btrim(transport ->> 'contact_document'), ''),
      transport_contact_phone = nullif(btrim(transport ->> 'contact_phone'), ''),
      transport_vehicle = nullif(btrim(transport ->> 'vehicle'), ''),
      transport_plate = upper(nullif(btrim(transport ->> 'plate'), '')),
      transport_responsible = nullif(btrim(transport ->> 'responsible'), '')
  where id = shipment.id;

  return shipment.id;
end;
$$;

revoke all on function public.set_shipment_transport(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.set_shipment_transport(uuid, jsonb) to authenticated;
comment on function public.set_shipment_transport(uuid, jsonb) is
  'Registra o corrige los datos de transporte de un despacho mientras se prepara; después de salir queda fijo.';
