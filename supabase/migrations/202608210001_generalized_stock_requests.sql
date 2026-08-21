-- Eje P0 del loop maestro: la solicitud logística generalizada.
--
-- Lo que existía: `transfer_requests`, una fila con una categoría, una unidad y una
-- cantidad, entre dos bodegas de la MISMA organización. Servía para el traslado interno
-- y no para la red: un centro no podía pedirle producto a otro de otra organización
-- aunque los dos atendieran la misma emergencia, y una solicitud real casi nunca es de
-- un solo producto.
--
-- Lo que se hace aquí, extendiendo el motor y sin crear un segundo:
--
--   1. Cabecera + N líneas. `transfer_request_items` guarda cada producto pedido; la
--      cabecera deja de llevar categoría, unidad y cantidad, que pasan a ser de la línea.
--   2. Cross-organization. La cabecera distingue quién pide (`requesting_organization_id`)
--      de quién provee (`organization_id`, la organización de la bodega de origen). Pedir
--      no da acceso a la información privada del proveedor: la organización solicitante ve
--      una proyección de disponibilidad y su propia solicitud, nada más.
--   3. Modos de solicitud. EXACT_QUANTITY, FULL_LOT y ALL_AVAILABLE. En los dos últimos la
--      cantidad NO viaja desde el navegador: se resuelve dentro de la transacción, con los
--      lotes bloqueados, porque lo que vio React ya puede no ser cierto.
--   4. Necesidad opcional. Una solicitud puede responder a una necesidad ciudadana o ser
--      puramente logística; la necesidad no controla la disponibilidad del inventario.
--   5. Autorización parcial por línea, con su registro append-only de quién decidió qué.
--
-- La reserva sigue siendo la misma primitiva (`reserve_lot_quantity` → una fila en
-- `allocations` más un movimiento `reserve`) y el Kardex sigue siendo la fuente de verdad.

-- ============================================================ 1. modos de solicitud

create type public.transfer_request_mode as enum (
  'exact_quantity',
  'full_lot',
  'all_available'
);

comment on type public.transfer_request_mode is
  'Cómo se expresa lo pedido en una línea. En full_lot y all_available la cantidad la resuelve PostgreSQL dentro de la transacción, no el navegador.';

-- ============================================================ 2. líneas de la solicitud

create table public.transfer_request_items (
  id uuid primary key default gen_random_uuid(),
  transfer_request_id uuid not null references public.transfer_requests(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  category text not null check (char_length(btrim(category)) between 2 and 80),
  unit text not null check (char_length(btrim(unit)) between 1 and 40),
  request_mode public.transfer_request_mode not null,
  lot_id uuid references public.inventory_lots(id),
  quantity_requested numeric(14,3) check (quantity_requested > 0),
  quantity_authorized numeric(14,3) not null default 0 check (quantity_authorized >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (transfer_request_id, line_no),
  -- La forma de la línea depende del modo: una cantidad exacta no lleva lote, y un lote
  -- completo o «todo lo disponible» no llevan cantidad, porque la pone la base.
  constraint transfer_request_items_mode_shape check (
    case request_mode
      when 'exact_quantity' then quantity_requested is not null and lot_id is null
      when 'full_lot' then lot_id is not null and quantity_requested is null
      when 'all_available' then lot_id is null and quantity_requested is null
    end
  )
);

create index transfer_request_items_request_idx
  on public.transfer_request_items (transfer_request_id, line_no);
create index transfer_request_items_lot_idx
  on public.transfer_request_items (lot_id) where lot_id is not null;

create trigger transfer_request_items_updated_at
  before update on public.transfer_request_items
  for each row execute function public.set_updated_at();

alter table public.transfer_request_items enable row level security;
revoke all on table public.transfer_request_items from public, anon, authenticated;
grant select on table public.transfer_request_items to authenticated;

comment on table public.transfer_request_items is
  'Líneas de una solicitud logística: qué producto, en qué unidad, en qué modo y cuánto quedó autorizado.';
comment on column public.transfer_request_items.quantity_requested is
  'Solo en modo exact_quantity. En full_lot y all_available es nula a propósito: la cantidad se resuelve al autorizar.';

-- ============================================================ 3. la reserva conoce la línea

alter table public.allocations
  add column transfer_request_item_id uuid references public.transfer_request_items(id);

create index allocations_transfer_item_idx
  on public.allocations (transfer_request_item_id) where transfer_request_item_id is not null;

comment on column public.allocations.transfer_request_item_id is
  'Línea de la solicitud que originó la reserva; conserva la trazabilidad lote → línea → solicitud → despacho.';

-- ============================================================ 4. cabecera generalizada

alter table public.transfer_requests
  add column requesting_organization_id uuid references public.organizations(id),
  add column need_case_id uuid references public.need_cases(id),
  add column need_item_id uuid references public.need_items(id);

-- Lo vigente es intraorganizacional: quien pide y quien provee son la misma organización.
update public.transfer_requests
set requesting_organization_id = organization_id
where requesting_organization_id is null;

alter table public.transfer_requests
  alter column requesting_organization_id set not null;

-- La clave de idempotencia la genera quien pide, así que el espacio de claves es suyo.
-- Acotada a la organización proveedora —como estaba— dos solicitantes distintos habrían
-- compartido espacio: una colisión le habría devuelto a uno el código de la solicitud del
-- otro. Mientras quien pide y quien provee eran la misma organización daba igual; con la
-- solicitud entre organizaciones deja de darlo.
alter table public.transfer_requests
  drop constraint transfer_requests_organization_id_idempotency_key_key,
  add constraint transfer_requests_requester_idempotency_key
    unique (requesting_organization_id, idempotency_key);

-- Cada solicitud existente se convierte en una solicitud de una sola línea. Ninguna
-- cantidad cambia y ninguna reserva se rehace: solo se mueve dónde vive el dato.
insert into public.transfer_request_items(
  transfer_request_id, line_no, category, unit, request_mode, quantity_requested, quantity_authorized
)
select id, 1, category, unit, 'exact_quantity', quantity_requested, quantity_authorized
from public.transfer_requests;

update public.allocations as allocation
set transfer_request_item_id = item.id
from public.transfer_request_items as item
where item.transfer_request_id = allocation.transfer_request_id
  and allocation.transfer_request_id is not null;

alter table public.allocations
  add constraint allocations_transfer_line
  check ((transfer_request_id is null) = (transfer_request_item_id is null));

-- Ya no viven en la cabecera: son de la línea. Se retiran para que no queden dos lugares
-- donde vive el mismo dato ni una cantidad de cabecera que contradiga a sus líneas.
alter table public.transfer_requests
  drop column category,
  drop column unit,
  drop column quantity_requested,
  drop column quantity_authorized;

-- La cola de cada lado. La de quien provee además sostiene su clave foránea, que antes se
-- apoyaba en el índice de la unicidad de idempotencia que acaba de cambiar de columnas.
create index transfer_requests_provider_idx
  on public.transfer_requests (organization_id, event_id, status);
create index transfer_requests_requesting_org_idx
  on public.transfer_requests (requesting_organization_id, event_id, status);
create index transfer_requests_need_case_idx
  on public.transfer_requests (need_case_id) where need_case_id is not null;
create index transfer_requests_need_item_idx
  on public.transfer_requests (need_item_id) where need_item_id is not null;

comment on table public.transfer_requests is
  'Solicitud logística: un centro pide producto a otro, de su organización o de otra del mismo evento. Cabecera; los productos van en transfer_request_items.';
comment on column public.transfer_requests.organization_id is
  'Organización PROVEEDORA: la dueña de la bodega de origen. Es quien autoriza y de cuyo inventario sale el producto.';
comment on column public.transfer_requests.requesting_organization_id is
  'Organización SOLICITANTE: la dueña de la bodega de destino. Puede ser distinta de la proveedora.';
comment on column public.transfer_requests.need_case_id is
  'Necesidad ciudadana que motiva la solicitud, cuando existe. Es opcional: una solicitud puramente logística no depende de ninguna necesidad.';

-- ============================================================ 5. decisiones por línea

-- La autorización parcial necesita su propio registro: quién autorizó cuánto de qué y por
-- qué. No se delega en `audit_events` porque quien solicita —que puede ser de otra
-- organización— tiene que poder leer la razón por la que recibió 350 de los 500 que pidió,
-- y la auditoría es privada de cada organización. Es append-only: no tiene política de
-- escritura y la única inserción ocurre dentro de la RPC que decide.
create table public.transfer_request_decisions (
  id uuid primary key default gen_random_uuid(),
  transfer_request_id uuid not null references public.transfer_requests(id) on delete cascade,
  transfer_request_item_id uuid references public.transfer_request_items(id) on delete cascade,
  decision text not null check (decision in ('authorize','reject')),
  quantity_authorized numeric(14,3) check (quantity_authorized >= 0),
  note text not null check (char_length(btrim(note)) between 5 and 500),
  decided_by uuid not null references auth.users(id),
  decided_at timestamptz not null default now()
);

create index transfer_request_decisions_request_idx
  on public.transfer_request_decisions (transfer_request_id, decided_at);
create index transfer_request_decisions_decided_by_idx
  on public.transfer_request_decisions (decided_by);
create index transfer_request_decisions_item_idx
  on public.transfer_request_decisions (transfer_request_item_id) where transfer_request_item_id is not null;

alter table public.transfer_request_decisions enable row level security;
revoke all on table public.transfer_request_decisions from public, anon, authenticated;
grant select on table public.transfer_request_decisions to authenticated;

comment on table public.transfer_request_decisions is
  'Historia append-only de la autorización: actor, fecha, línea, cantidad autorizada y razón. Sin política de escritura.';

-- ============================================================ 6. lectura de las dos partes

-- Quien pide tiene que poder seguir su solicitud aunque el inventario sea de otra
-- organización. Lo que ve es la solicitud, sus líneas y las decisiones sobre ella; no las
-- reservas, ni los lotes, ni la auditoría, ni el contacto de nadie.
create policy "requesting org reads transfer requests"
  on public.transfer_requests for select to authenticated
  using (public.is_org_member(requesting_organization_id, event_id));

create policy "both parties read transfer request lines"
  on public.transfer_request_items for select to authenticated
  using (exists (
    select 1 from public.transfer_requests as request
    where request.id = transfer_request_id
      and (
        public.is_org_member(request.organization_id, request.event_id)
        or public.is_org_member(request.requesting_organization_id, request.event_id)
      )
  ));

create policy "both parties read transfer decisions"
  on public.transfer_request_decisions for select to authenticated
  using (exists (
    select 1 from public.transfer_requests as request
    where request.id = transfer_request_id
      and (
        public.is_org_member(request.organization_id, request.event_id)
        or public.is_org_member(request.requesting_organization_id, request.event_id)
      )
  ));

-- La bodega que espera la carga tiene que verla llegar. El despacho pertenece a la
-- organización que despacha; sin esta política, en una solicitud entre organizaciones el
-- destino no podría ni ver lo que va a recibir ni cuánto se esperaba.
create policy "destination org reads incoming shipments"
  on public.shipments for select to authenticated
  using (
    destination_location_id is not null
    and exists (
      select 1 from public.inventory_locations as destination
      where destination.id = destination_location_id
        and public.is_org_member(destination.organization_id, destination.event_id)
    )
  );

create policy "destination org reads incoming shipment items"
  on public.shipment_items for select to authenticated
  using (exists (
    select 1
    from public.shipments as shipment
    join public.inventory_locations as destination on destination.id = shipment.destination_location_id
    where shipment.id = shipment_id
      and public.is_org_member(destination.organization_id, destination.event_id)
  ));

-- ============================================================ 7. política de compartir

-- «Si ambos pertenecen al mismo evento y la política operacional lo permite». La política
-- vive en el punto: una bodega declara si publica su disponibilidad a la red del evento.
-- Lo que se comparte es agregado y operacional —categoría, unidad y cuánto hay—, nunca
-- lotes, donantes, contactos ni direcciones privadas.
alter table public.inventory_locations
  add column shares_availability boolean not null default true;

comment on column public.inventory_locations.shares_availability is
  'Si esta bodega publica su disponibilidad agregada a las demás organizaciones del evento. No expone lotes, donantes ni PII.';

create or replace function public.set_location_availability_sharing(p_location_id uuid, p_shares boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare location public.inventory_locations;
begin
  select * into location from public.inventory_locations where id = p_location_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Bodega no encontrada';
  end if;
  if not public.has_any_role(
    location.organization_id, location.event_id,
    array['event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Solo la administración del evento decide qué se comparte con la red';
  end if;
  if not public.has_location_scope(location.id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Esa bodega no está dentro de tu alcance';
  end if;

  update public.inventory_locations
  set shares_availability = coalesce(p_shares, false)
  where id = location.id;

  return coalesce(p_shares, false);
end;
$$;

revoke all on function public.set_location_availability_sharing(uuid, boolean) from public, anon, authenticated;
grant execute on function public.set_location_availability_sharing(uuid, boolean) to authenticated;
comment on function public.set_location_availability_sharing(uuid, boolean) is
  'Activa o desactiva la publicación de disponibilidad de una bodega hacia el resto del evento.';

-- ============================================================ 8. disponibilidad segura

-- La proyección que ve quien va a pedir. Es `security definer` a propósito: atraviesa el
-- tenant, y por eso todo lo que devuelve está elegido a mano. Lo que NO devuelve importa
-- tanto como lo que devuelve: ni lote, ni donante, ni contacto, ni dirección privada, ni
-- evidencia, ni auditoría, ni usuario alguno.
create or replace function public.shared_stock_availability(
  p_event_id uuid,
  p_category text default null
)
returns table(
  location_id uuid,
  location_name text,
  location_label text,
  organization_id uuid,
  organization_name text,
  category text,
  unit text,
  quantity_available numeric,
  cold_chain_capable boolean,
  is_own_organization boolean,
  last_movement_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select
    location.id,
    location.name,
    location.public_location_text,
    organization.id,
    organization.name,
    lot_position.category,
    lot_position.unit,
    sum(lot_position.quantity_available),
    bool_or(location.cold_chain_capable),
    bool_or(public.is_org_member(location.organization_id, location.event_id)),
    max(movement.last_at)
  from public.inventory_lot_positions as lot_position
  join public.inventory_locations as location on location.id = lot_position.location_id
  join public.organizations as organization on organization.id = location.organization_id
  left join lateral (
    select max(stock_movement.created_at) as last_at
    from public.stock_movements as stock_movement
    where stock_movement.lot_id = lot_position.lot_id
  ) as movement on true
  where lot_position.event_id = p_event_id
    and location.active
    and location.dispatches_shipments
    and location.shares_availability
    and organization.status = 'active'
    and lot_position.quantity_available > 0
    and lot_position.status in ('available','reserved')
    and (p_category is null or lot_position.category = p_category)
    -- Solo quien participa en el evento ve la disponibilidad del evento.
    and (
      public.is_super_admin()
      or exists (
        select 1 from public.memberships as membership
        where membership.user_id = (select auth.uid())
          and membership.event_id = p_event_id
          and membership.active
      )
    )
  group by location.id, location.name, location.public_location_text,
           organization.id, organization.name, lot_position.category, lot_position.unit
  order by organization.name, location.name, lot_position.category, lot_position.unit;
$$;

revoke all on function public.shared_stock_availability(uuid, text) from public, anon, authenticated;
grant execute on function public.shared_stock_availability(uuid, text) to authenticated;
comment on function public.shared_stock_availability(uuid, text) is
  'Disponibilidad agregada que una bodega publica a la red del evento. Atraviesa el tenant y por eso no expone lote, donante, contacto ni dirección privada.';

-- ============================================================ 9. la primitiva de reserva

-- Sigue siendo la única escritura de reserva del sistema. Lo único que cambia es que ahora
-- también sabe a qué línea de la solicitud responde.
drop function if exists public.reserve_lot_quantity(uuid, numeric, uuid, uuid, text);

create or replace function public.reserve_lot_quantity(
  p_lot_id uuid,
  p_quantity numeric,
  p_need_item_id uuid,
  p_transfer_request_id uuid,
  p_transfer_request_item_id uuid,
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
$$;

revoke all on function public.reserve_lot_quantity(uuid, numeric, uuid, uuid, uuid, text) from public, anon, authenticated;
comment on function public.reserve_lot_quantity(uuid, numeric, uuid, uuid, uuid, text) is
  'Única escritura de reserva del sistema; la usan la asignación a una necesidad y la autorización de una solicitud logística.';

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

  return public.reserve_lot_quantity(p_lot_id, p_quantity, p_need_item_id, null, null, p_idempotency_key);
end;
$$;

revoke all on function public.allocate_stock(uuid, uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.allocate_stock(uuid, uuid, numeric, text) to authenticated;

-- Reserva lo que pide una línea, tomando de los lotes del origen por vencimiento más
-- próximo. Con `p_quantity` nula toma todo lo disponible: así se resuelven FULL_LOT y
-- ALL_AVAILABLE dentro de la transacción y con los lotes ya bloqueados, que es la única
-- forma de que la cantidad sea cierta. Devuelve lo realmente reservado, que puede ser
-- menos de lo pedido; decidir qué hacer con esa diferencia es de quien llama.
create or replace function public.reserve_transfer_item(p_item_id uuid, p_quantity numeric)
returns numeric language plpgsql security definer set search_path = '' as $$
declare
  item public.transfer_request_items;
  request public.transfer_requests;
  remaining numeric := p_quantity;
  obtained numeric := 0;
  available numeric;
  taken numeric;
  candidate record;
begin
  select * into item from public.transfer_request_items where id = p_item_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Línea de solicitud no encontrada';
  end if;
  select * into request from public.transfer_requests where id = item.transfer_request_id;

  -- El orden del bloqueo es el mismo en todas las transacciones —vencimiento, recepción,
  -- identificador—, así que dos autorizaciones simultáneas se serializan en vez de trabarse.
  for candidate in
    select lot.id as lot_id
    from public.inventory_lots as lot
    where lot.location_id = request.origin_location_id
      and lot.category = item.category
      and lot.unit = item.unit
      and lot.status in ('available','reserved')
      and (item.lot_id is null or lot.id = item.lot_id)
    order by lot.expires_on nulls last, lot.received_at, lot.id
    for update
  loop
    exit when remaining is not null and remaining <= 0;

    select coalesce(sum(movement.quantity_delta), 0) into available
    from public.stock_movements as movement
    where movement.lot_id = candidate.lot_id;
    continue when available <= 0;

    taken := case when remaining is null then available else least(remaining, available) end;
    perform public.reserve_lot_quantity(
      candidate.lot_id, taken, null, request.id, item.id,
      request.request_code || ':' || item.id::text || ':' || candidate.lot_id::text
    );
    obtained := obtained + taken;
    if remaining is not null then
      remaining := remaining - taken;
    end if;
  end loop;

  return obtained;
end;
$$;

revoke all on function public.reserve_transfer_item(uuid, numeric) from public, anon, authenticated;
comment on function public.reserve_transfer_item(uuid, numeric) is
  'Reserva una línea de solicitud contra los lotes del origen (vencimiento más próximo primero). Con cantidad nula reserva todo lo disponible bajo bloqueo.';

-- ============================================================ 10. solicitar

drop function if exists public.request_stock_transfer(uuid, uuid, text, text, numeric, text, text);

create or replace function public.request_stock_transfer(
  p_origin_location_id uuid,
  p_destination_location_id uuid,
  p_items jsonb,
  p_justification text,
  p_need_case_id uuid,
  p_need_item_id uuid,
  p_idempotency_key text
)
returns table(request_id uuid, request_code text, status public.transfer_status, line_count integer, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  origin public.inventory_locations;
  destination public.inventory_locations;
  existing public.transfer_requests;
  created public.transfer_requests;
  entry record;
  line_mode public.transfer_request_mode;
  line_category text;
  line_unit text;
  line_quantity numeric;
  line_lot_id uuid;
  line_lot public.inventory_lots;
  need_item public.need_items;
  need_case public.need_cases;
  resolved_need_case_id uuid;
  lines integer := 0;
begin
  select * into origin from public.inventory_locations where id = p_origin_location_id;
  select * into destination from public.inventory_locations where id = p_destination_location_id;
  if origin.id is null or destination.id is null then
    raise exception using errcode = 'P0002', message = 'Bodega de origen o destino no encontrada';
  end if;
  if origin.id = destination.id then
    raise exception using errcode = '22023', message = 'El origen y el destino deben ser bodegas distintas';
  end if;
  if origin.event_id <> destination.event_id then
    raise exception using errcode = '42501', message = 'Ambas bodegas deben atender el mismo evento';
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

  -- Pedirle a otra organización solo es posible si esa bodega publica su disponibilidad a
  -- la red del evento. La política es de quien provee, no de quien pide.
  if origin.organization_id <> destination.organization_id then
    if not origin.shares_availability then
      raise exception using errcode = '42501',
        message = 'Esa bodega no comparte su disponibilidad con otras organizaciones del evento';
    end if;
    if exists (
      select 1 from public.organizations as organization
      where organization.id in (origin.organization_id, destination.organization_id)
        and organization.status <> 'active'
    ) then
      raise exception using errcode = '42501', message = 'Alguna de las dos organizaciones no está activa';
    end if;
  end if;

  if char_length(btrim(coalesce(p_justification, ''))) not between 10 and 500 then
    raise exception using errcode = '22023', message = 'Explica en 10 a 500 caracteres por qué se necesita el traslado';
  end if;
  if public.contains_sensitive_content(p_justification) then
    raise exception using errcode = '22023', message = 'La justificación no puede incluir teléfonos, cuentas ni enlaces';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'Una solicitud necesita al menos un producto';
  end if;
  if jsonb_array_length(p_items) > 20 then
    raise exception using errcode = '22023', message = 'Una solicitud admite como máximo veinte productos';
  end if;

  -- La necesidad es opcional (una solicitud puede ser puramente logística) pero si viene,
  -- tiene que ser coherente y del mismo evento.
  if p_need_item_id is not null then
    select * into need_item from public.need_items where id = p_need_item_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Necesidad no encontrada';
    end if;
    if p_need_case_id is not null and need_item.need_case_id <> p_need_case_id then
      raise exception using errcode = '22023', message = 'El artículo no pertenece a esa necesidad';
    end if;
    resolved_need_case_id := need_item.need_case_id;
  end if;
  resolved_need_case_id := coalesce(p_need_case_id, resolved_need_case_id);
  if resolved_need_case_id is not null then
    select * into need_case from public.need_cases where id = resolved_need_case_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Necesidad no encontrada';
    end if;
    if need_case.event_id <> origin.event_id then
      raise exception using errcode = '22023', message = 'Esa necesidad pertenece a otro evento';
    end if;
  end if;

  select * into existing
  from public.transfer_requests as candidate
  where candidate.requesting_organization_id = destination.organization_id
    and candidate.idempotency_key = p_idempotency_key;
  if existing.id is not null then
    return query
      select existing.id, existing.request_code, existing.status,
        (select count(*)::integer from public.transfer_request_items as item
         where item.transfer_request_id = existing.id),
        true;
    return;
  end if;

  insert into public.transfer_requests(
    event_id, organization_id, requesting_organization_id, origin_location_id, destination_location_id,
    need_case_id, need_item_id, justification, idempotency_key, requested_by
  ) values (
    origin.event_id, origin.organization_id, destination.organization_id, origin.id, destination.id,
    resolved_need_case_id, p_need_item_id,
    btrim(p_justification), p_idempotency_key, (select auth.uid())
  )
  returning * into created;

  for entry in
    select value, ordinality from jsonb_array_elements(p_items) with ordinality as elements(value, ordinality)
  loop
    line_mode := coalesce(nullif(btrim(entry.value ->> 'mode'), ''), 'exact_quantity')::public.transfer_request_mode;
    line_lot_id := null;
    line_quantity := null;

    if line_mode = 'full_lot' then
      if entry.value ->> 'lot_id' is null then
        raise exception using errcode = '22023', message = 'Para pedir un lote completo hay que indicar cuál';
      end if;
      select * into line_lot from public.inventory_lots where id = (entry.value ->> 'lot_id')::uuid;
      if not found then
        raise exception using errcode = 'P0002', message = 'Lote no encontrado';
      end if;
      if line_lot.location_id <> origin.id then
        raise exception using errcode = '22023', message = 'Ese lote no está en la bodega de origen';
      end if;
      if line_lot.status not in ('available','reserved') then
        raise exception using errcode = '22023', message = 'Ese lote está bloqueado y no puede pedirse';
      end if;
      -- Pedir un lote concreto exige poder verlo, y los lotes de otra organización no se
      -- publican. Entre organizaciones se pide por cantidad o por todo lo disponible.
      if origin.organization_id <> destination.organization_id then
        raise exception using errcode = '42501',
          message = 'A otra organización se le pide por cantidad o todo lo disponible, no por lote';
      end if;
      -- La categoría y la unidad las pone el lote, no el navegador.
      line_lot_id := line_lot.id;
      line_category := line_lot.category;
      line_unit := line_lot.unit;
    else
      line_category := btrim(coalesce(entry.value ->> 'category', ''));
      line_unit := btrim(coalesce(entry.value ->> 'unit', ''));
      if char_length(line_category) < 2 or char_length(line_unit) < 1 then
        raise exception using errcode = '22023', message = 'Cada producto necesita categoría y unidad';
      end if;
      if line_mode = 'exact_quantity' then
        line_quantity := (entry.value ->> 'quantity')::numeric;
        if line_quantity is null or line_quantity <= 0 then
          raise exception using errcode = '22023', message = 'La cantidad solicitada debe ser mayor que cero';
        end if;
      end if;
    end if;

    insert into public.transfer_request_items(
      transfer_request_id, line_no, category, unit, request_mode, lot_id, quantity_requested
    ) values (
      created.id, entry.ordinality::integer, line_category, line_unit, line_mode,
      line_lot_id, line_quantity
    );
    lines := lines + 1;
  end loop;

  -- Vincular un artículo de una necesidad y pedir otra cosa dejaría una trazabilidad que
  -- miente. La necesidad sigue siendo opcional; lo que no puede es ser incoherente.
  if p_need_item_id is not null and not exists (
    select 1 from public.transfer_request_items as item
    where item.transfer_request_id = created.id
      and item.category = need_item.category
      and item.unit = need_item.unit
  ) then
    raise exception using errcode = '22023',
      message = 'Ninguno de los productos pedidos corresponde al artículo de la necesidad';
  end if;

  return query select created.id, created.request_code, created.status, lines, false;
end;
$$;

revoke all on function public.request_stock_transfer(uuid, uuid, jsonb, text, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.request_stock_transfer(uuid, uuid, jsonb, text, uuid, uuid, text)
  to authenticated;
comment on function public.request_stock_transfer(uuid, uuid, jsonb, text, uuid, uuid, text) is
  'Un centro pide uno o varios productos a otro centro del mismo evento, sea o no de su organización. No mueve inventario: solo abre la solicitud.';

-- ============================================================ 11. autorizar

drop function if exists public.decide_stock_transfer(uuid, text, numeric, text);

create or replace function public.decide_stock_transfer(
  p_request_id uuid,
  p_decision text,
  p_lines jsonb,
  p_note text
)
returns public.transfer_status
language plpgsql security definer set search_path = '' as $$
declare
  request public.transfer_requests;
  actor uuid := (select auth.uid());
  item public.transfer_request_items;
  override jsonb;
  cap numeric;
  reserved numeric;
  authorized_lines integer := 0;
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
    insert into public.transfer_request_decisions(
      transfer_request_id, transfer_request_item_id, decision, quantity_authorized, note, decided_by
    ) values (request.id, null, 'reject', null, btrim(p_note), actor);
    return 'rejected'::public.transfer_status;
  end if;

  -- Una línea que no es de esta solicitud no se ignora en silencio: quien la envió cree
  -- haber autorizado algo, y no habría autorizado nada.
  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and exists (
    select 1
    from jsonb_array_elements(p_lines) as element(value)
    where not exists (
      -- El alias no puede llamarse `item`: la variable de recorrido de este mismo
      -- procedimiento ya se llama así y PostgreSQL no sabría a cuál se refiere.
      select 1 from public.transfer_request_items as declared_line
      where declared_line.transfer_request_id = request.id
        and declared_line.id::text = element.value ->> 'item_id'
    )
  ) then
    raise exception using errcode = '22023', message = 'Alguna línea de la decisión no pertenece a esta solicitud';
  end if;

  for item in
    select * from public.transfer_request_items
    where transfer_request_id = request.id
    order by line_no
  loop
    override := null;
    if p_lines is not null and jsonb_typeof(p_lines) = 'array' then
      select element.value into override
      from jsonb_array_elements(p_lines) as element(value)
      where element.value ->> 'item_id' = item.id::text
      limit 1;
    end if;

    if item.request_mode = 'exact_quantity' then
      cap := item.quantity_requested;
      if override is not null and override ? 'quantity' then
        cap := (override ->> 'quantity')::numeric;
        if cap is null or cap < 0 then
          raise exception using errcode = '22023', message = 'La cantidad autorizada no puede ser negativa';
        end if;
        if cap > item.quantity_requested then
          raise exception using errcode = '22023', message = 'No puedes autorizar más de lo solicitado';
        end if;
      end if;
      if cap > 0 then
        reserved := public.reserve_transfer_item(item.id, cap);
        -- Una cantidad exacta que no alcanza no se recorta en silencio: quien autoriza
        -- decide cuánto autoriza, y para autorizar menos escribe menos.
        if reserved < cap then
          raise exception using errcode = '22023',
            message = format('La bodega de origen no tiene %s %s disponibles de %s',
              public.format_quantity(cap), item.unit, item.category);
        end if;
      else
        reserved := 0;
      end if;
    else
      -- FULL_LOT y ALL_AVAILABLE: la cantidad la pone la base con los lotes bloqueados.
      cap := null;
      if override is not null and override ? 'quantity' then
        cap := (override ->> 'quantity')::numeric;
        if cap is null or cap < 0 then
          raise exception using errcode = '22023', message = 'La cantidad autorizada no puede ser negativa';
        end if;
      end if;
      if cap is not null and cap = 0 then
        reserved := 0;
      else
        reserved := public.reserve_transfer_item(item.id, cap);
      end if;
    end if;

    update public.transfer_request_items
    set quantity_authorized = reserved
    where id = item.id;

    insert into public.transfer_request_decisions(
      transfer_request_id, transfer_request_item_id, decision, quantity_authorized, note, decided_by
    ) values (request.id, item.id, 'authorize', reserved, btrim(p_note), actor);

    if reserved > 0 then
      authorized_lines := authorized_lines + 1;
    end if;
  end loop;

  if authorized_lines = 0 then
    raise exception using errcode = '22023',
      message = 'No hay existencia disponible para autorizar ninguna línea de esta solicitud';
  end if;

  update public.transfer_requests
  set status = 'authorized',
      decided_by = actor,
      decided_at = now(),
      decision_note = btrim(p_note)
  where id = request.id;

  return 'authorized'::public.transfer_status;
end;
$$;

revoke all on function public.decide_stock_transfer(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.decide_stock_transfer(uuid, text, jsonb, text) to authenticated;
comment on function public.decide_stock_transfer(uuid, text, jsonb, text) is
  'Autoriza línea por línea —total o parcialmente— y deja reservado lo autorizado; rechazar no toca el inventario.';

-- Lo que ve quien decide antes de decidir: qué se pidió y cuánto hay realmente ahora.
create or replace function public.transfer_request_lines(p_request_id uuid)
returns table(
  item_id uuid,
  line_no integer,
  category text,
  unit text,
  request_mode public.transfer_request_mode,
  lot_id uuid,
  lot_code text,
  quantity_requested numeric,
  quantity_authorized numeric,
  quantity_available_now numeric
)
language sql stable security definer set search_path = '' as $$
  select
    item.id,
    item.line_no,
    item.category,
    item.unit,
    item.request_mode,
    item.lot_id,
    lot.lot_code,
    item.quantity_requested,
    item.quantity_authorized,
    coalesce((
      select sum(lot_position.quantity_available)
      from public.inventory_lot_positions as lot_position
      where lot_position.location_id = request.origin_location_id
        and lot_position.category = item.category
        and lot_position.unit = item.unit
        and lot_position.status in ('available','reserved')
        and (item.lot_id is null or lot_position.lot_id = item.lot_id)
    ), 0)
  from public.transfer_request_items as item
  join public.transfer_requests as request on request.id = item.transfer_request_id
  left join public.inventory_lots as lot on lot.id = item.lot_id
  where item.transfer_request_id = p_request_id
    and (
      public.is_org_member(request.organization_id, request.event_id)
      or public.is_org_member(request.requesting_organization_id, request.event_id)
    )
  order by item.line_no;
$$;

revoke all on function public.transfer_request_lines(uuid) from public, anon, authenticated;
grant execute on function public.transfer_request_lines(uuid) to authenticated;
comment on function public.transfer_request_lines(uuid) is
  'Líneas de una solicitud con la disponibilidad real del origen en este momento; visible para quien pide y para quien provee.';

-- La lista que abre la consola. Es `security definer` por la misma razón que la anterior:
-- quien pide no puede leer la tabla de puntos de la organización proveedora, y sin el
-- nombre de la bodega de origen su propia solicitud sería un identificador sin sentido.
-- Las líneas se piden a `transfer_request_lines`, que ya sabe resolverlas, en vez de
-- repetir aquí la misma consulta.
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
language sql stable security definer set search_path = '' as $$
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
    public.is_org_member(request.organization_id, request.event_id),
    public.is_org_member(request.requesting_organization_id, request.event_id),
    coalesce((
      select jsonb_agg(to_jsonb(line) order by line.line_no)
      from public.transfer_request_lines(request.id) as line
    ), '[]'::jsonb)
  from public.transfer_requests as request
  join public.inventory_locations as origin on origin.id = request.origin_location_id
  join public.inventory_locations as destination on destination.id = request.destination_location_id
  join public.organizations as provider on provider.id = request.organization_id
  join public.organizations as requester on requester.id = request.requesting_organization_id
  where request.event_id = p_event_id
    and (
      public.is_org_member(request.organization_id, request.event_id)
      or public.is_org_member(request.requesting_organization_id, request.event_id)
    )
  order by request.requested_at desc;
$$;

revoke all on function public.logistics_requests(uuid) from public, anon, authenticated;
grant execute on function public.logistics_requests(uuid) to authenticated;
comment on function public.logistics_requests(uuid) is
  'Solicitudes logísticas visibles para el actor, con sus líneas y con el nombre de las dos bodegas; no expone nada más de la otra organización.';

-- ============================================================ 12. recibir producto a producto

-- Una solicitud multiproducto rompe la recepción con una sola cifra: 500 litros de agua y
-- 100 mercados no se suman, y repartir «lo recibido» en proporción a lo despachado —que es
-- lo que hacía el cálculo anterior— inventa números en cuanto las líneas no son del mismo
-- producto. Lo recibido se declara por línea.
create table public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  shipment_item_id uuid not null references public.shipment_items(id),
  quantity_delivered numeric(14,3) not null check (quantity_delivered >= 0),
  quantity_damaged numeric(14,3) not null default 0 check (quantity_damaged >= 0),
  quantity_missing numeric(14,3) not null default 0 check (quantity_missing >= 0),
  created_at timestamptz not null default now(),
  unique (delivery_id, shipment_item_id)
);

create index delivery_items_delivery_idx on public.delivery_items (delivery_id);
create index delivery_items_shipment_item_idx on public.delivery_items (shipment_item_id);

alter table public.delivery_items enable row level security;
revoke all on table public.delivery_items from public, anon, authenticated;
grant select on table public.delivery_items to authenticated;

create policy "both parties read delivery lines"
  on public.delivery_items for select to authenticated
  using (exists (
    select 1
    from public.deliveries as delivery
    join public.shipments as shipment on shipment.id = delivery.shipment_id
    left join public.inventory_locations as destination on destination.id = shipment.destination_location_id
    where delivery.id = delivery_id
      and (
        public.is_org_member(shipment.organization_id, shipment.event_id)
        or (destination.id is not null and public.is_org_member(destination.organization_id, destination.event_id))
      )
  ));

comment on table public.delivery_items is
  'Lo recibido, dañado y faltante de cada producto de un despacho. La cifra de la entrega es la suma de estas líneas, no al revés.';

-- Las entregas ya registradas se convierten en líneas con el mismo reparto proporcional que
-- la posición del Kardex venía aplicando, para que ningún número histórico cambie.
insert into public.delivery_items(
  delivery_id, shipment_item_id, quantity_delivered, quantity_damaged, quantity_missing
)
select
  delivery.id,
  shipment_item.id,
  round(delivery.quantity_delivered * shipment_item.quantity / nullif(shipped.total, 0), 3),
  round(delivery.quantity_damaged * shipment_item.quantity / nullif(shipped.total, 0), 3),
  round(delivery.quantity_missing * shipment_item.quantity / nullif(shipped.total, 0), 3)
from public.deliveries as delivery
join public.shipment_items as shipment_item on shipment_item.shipment_id = delivery.shipment_id
join lateral (
  select sum(sibling.quantity) as total
  from public.shipment_items as sibling
  where sibling.shipment_id = delivery.shipment_id
) as shipped on true
where shipped.total > 0;

-- La posición del lote deja de repartir en proporción: lee lo que declaró cada línea.
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
  select
    allocation.lot_id,
    sum(delivery_item.quantity_delivered) as delivered,
    sum(delivery_item.quantity_damaged + delivery_item.quantity_missing) as lost
  from public.delivery_items as delivery_item
  join public.shipment_items as shipment_item on shipment_item.id = delivery_item.shipment_item_id
  join public.allocations as allocation on allocation.id = shipment_item.allocation_id
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

comment on view public.inventory_lot_positions is
  'Posición real de cada lote derivada del Kardex y de lo que el destino declaró producto a producto; ningún saldo se almacena.';

drop function if exists public.register_delivery(uuid, numeric, numeric, numeric, text);

create or replace function public.register_delivery(
  p_shipment_id uuid,
  p_lines jsonb,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shipment public.shipments;
  destination public.inventory_locations;
  shipment_item public.shipment_items;
  delivery_id uuid;
  entry record;
  source record;
  shipment_lines integer;
  declared_lines integer;
  total_delivered numeric := 0;
  total_damaged numeric := 0;
  total_missing numeric := 0;
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
    -- Confirma quien administra la bodega de destino, no quien despachó. En una solicitud
    -- entre organizaciones esa bodega es de la organización solicitante.
    if not public.has_location_scope(
      shipment.destination_location_id,
      array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
    ) then
      raise exception using errcode = '42501', message = 'Solo la bodega de destino confirma lo que recibió';
    end if;
    select * into destination from public.inventory_locations where id = shipment.destination_location_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Bodega de destino no encontrada';
    end if;
  end if;

  select count(*)::integer into shipment_lines
  from public.shipment_items where shipment_id = shipment.id;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = '22023', message = 'Declara cuánto llegó de cada producto del despacho';
  end if;

  select count(distinct element.value ->> 'shipment_item_id')::integer into declared_lines
  from jsonb_array_elements(p_lines) as element(value);
  if declared_lines <> shipment_lines or jsonb_array_length(p_lines) <> shipment_lines then
    raise exception using errcode = '22023',
      message = format('El despacho lleva %s productos y hay que conciliarlos todos, una sola vez cada uno', shipment_lines);
  end if;

  for entry in
    select
      (element.value ->> 'shipment_item_id')::uuid as shipment_item_id,
      coalesce((element.value ->> 'delivered')::numeric, 0) as delivered,
      coalesce((element.value ->> 'damaged')::numeric, 0) as damaged,
      coalesce((element.value ->> 'missing')::numeric, 0) as missing
    from jsonb_array_elements(p_lines) as element(value)
  loop
    select * into shipment_item
    from public.shipment_items
    where id = entry.shipment_item_id and shipment_id = shipment.id;
    if not found then
      raise exception using errcode = '22023', message = 'Ese producto no pertenece a este despacho';
    end if;
    if entry.delivered < 0 or entry.damaged < 0 or entry.missing < 0
       or entry.delivered + entry.damaged + entry.missing <> shipment_item.quantity then
      raise exception using errcode = '22023',
        message = format('Lo recibido, lo dañado y el faltante de cada producto deben sumar %s',
          public.format_quantity(shipment_item.quantity));
    end if;
    total_delivered := total_delivered + entry.delivered;
    total_damaged := total_damaged + entry.damaged;
    total_missing := total_missing + entry.missing;
  end loop;

  insert into public.deliveries(
    shipment_id, status, quantity_delivered, quantity_damaged, quantity_missing,
    delivered_at, idempotency_key
  ) values (
    shipment.id,
    case when total_damaged > 0 or total_missing > 0 then 'incident' else 'delivered' end,
    total_delivered, total_damaged, total_missing,
    now(), p_idempotency_key
  )
  returning id into delivery_id;

  update public.shipments
  set status = case
    when total_damaged > 0 or total_missing > 0 then 'incident'::public.shipment_status
    else 'delivered'::public.shipment_status end
  where id = shipment.id;

  for entry in
    select
      (element.value ->> 'shipment_item_id')::uuid as shipment_item_id,
      coalesce((element.value ->> 'delivered')::numeric, 0) as delivered,
      coalesce((element.value ->> 'damaged')::numeric, 0) as damaged,
      coalesce((element.value ->> 'missing')::numeric, 0) as missing
    from jsonb_array_elements(p_lines) as element(value)
  loop
    insert into public.delivery_items(
      delivery_id, shipment_item_id, quantity_delivered, quantity_damaged, quantity_missing
    ) values (
      delivery_id, entry.shipment_item_id, entry.delivered, entry.damaged, entry.missing
    );

    if shipment.transfer_request_id is not null then
      select
        allocation.id as allocation_id, lot.donation_item_id, lot.category, lot.unit,
        lot.condition, lot.expires_on, lot.storage_requirement
      into source
      from public.shipment_items as item
      join public.allocations as allocation on allocation.id = item.allocation_id
      join public.inventory_lots as lot on lot.id = allocation.lot_id
      where item.id = entry.shipment_item_id;

      -- El inventario del destino nace aquí, con lo que el destino dice haber recibido, y
      -- pertenece a la organización del destino: en una solicitud entre organizaciones el
      -- producto cambia de dueño al ser confirmado.
      if entry.delivered > 0 then
        insert into public.inventory_lots(
          event_id, organization_id, donation_item_id, location_id, category,
          quantity_initial, unit, condition, expires_on, storage_requirement, received_by
        ) values (
          destination.event_id, destination.organization_id, source.donation_item_id,
          destination.id, source.category,
          entry.delivered, source.unit, source.condition, source.expires_on,
          source.storage_requirement, (select auth.uid())
        )
        returning id into new_lot;

        insert into public.stock_movements(
          event_id, organization_id, lot_id, movement_type, quantity_delta,
          idempotency_key, reason, actor_id
        ) values (
          destination.event_id, destination.organization_id, new_lot, 'transfer_in', entry.delivered,
          p_idempotency_key || ':' || entry.shipment_item_id::text || ':in',
          'Entrada por traslado confirmado en destino', (select auth.uid())
        );

        update public.allocations set status = 'delivered' where id = source.allocation_id;
      end if;
    end if;
  end loop;

  -- La solicitud se cierra cuando el destino confirma, haya o no novedad: lo que quedó
  -- pendiente es un faltante registrado, no un traslado abierto.
  if shipment.transfer_request_id is not null then
    update public.transfer_requests set status = 'closed' where id = shipment.transfer_request_id;
  end if;

  return delivery_id;
end;
$$;

revoke all on function public.register_delivery(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.register_delivery(uuid, jsonb, text) to authenticated;
comment on function public.register_delivery(uuid, jsonb, text) is
  'El destino confirma producto a producto: CONFORME si todo concilia, NOVEDAD si hay daño o faltante. En una solicitud logística crea el inventario del destino, a nombre de la organización que recibe.';

-- Conciliación producto a producto, en el lenguaje de la Fase 14: esperado, recibido,
-- faltante y daño de cada línea.
--
-- Es `security definer` porque quien tiene que verla es, sobre todo, la bodega de destino,
-- y en una solicitud entre organizaciones esa bodega no puede leer los lotes ni las
-- reservas de quien despacha. La compuerta es explícita: miembro de la organización que
-- despacha o de la que recibe, nadie más. Con un despacho devuelve sus líneas; con un
-- evento, las de todos los despachos que ese actor ya podía ver.
create or replace function public.shipment_reconciliation_lines(
  p_shipment_id uuid default null,
  p_event_id uuid default null
)
returns table(
  shipment_id uuid,
  shipment_code text,
  shipment_status text,
  origin_name text,
  destination_label text,
  shipment_item_id uuid,
  category text,
  unit text,
  quantity_dispatched numeric,
  quantity_received numeric,
  quantity_damaged numeric,
  quantity_missing numeric,
  outcome text
)
language sql stable security definer set search_path = '' as $$
  select
    shipment.id,
    shipment.shipment_code,
    shipment.status::text,
    origin.name,
    coalesce(destination.name, shipment.public_destination),
    shipment_item.id,
    lot.category,
    lot.unit,
    shipment_item.quantity,
    coalesce(sum(delivery_item.quantity_delivered), 0),
    coalesce(sum(delivery_item.quantity_damaged), 0),
    coalesce(sum(delivery_item.quantity_missing), 0),
    case
      when count(delivery_item.id) = 0 then 'PENDIENTE'
      when coalesce(sum(delivery_item.quantity_damaged), 0) = 0
       and coalesce(sum(delivery_item.quantity_missing), 0) = 0 then 'CONFORME'
      else 'NOVEDAD'
    end
  from public.shipments as shipment
  join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  join public.inventory_lots as lot on lot.id = allocation.lot_id
  left join public.inventory_locations as origin on origin.id = shipment.origin_location_id
  left join public.inventory_locations as destination on destination.id = shipment.destination_location_id
  left join public.delivery_items as delivery_item on delivery_item.shipment_item_id = shipment_item.id
  where (p_shipment_id is not null or p_event_id is not null)
    and (p_shipment_id is null or shipment.id = p_shipment_id)
    and (p_event_id is null or shipment.event_id = p_event_id)
    and (
      public.is_org_member(shipment.organization_id, shipment.event_id)
      or (destination.id is not null and public.is_org_member(destination.organization_id, destination.event_id))
    )
  group by shipment.id, shipment.shipment_code, shipment.status, origin.name,
           destination.name, shipment.public_destination, shipment_item.id,
           shipment_item.quantity, lot.category, lot.unit
  order by shipment.shipment_code, lot.category, lot.unit;
$$;

revoke all on function public.shipment_reconciliation_lines(uuid, uuid) from public, anon, authenticated;
grant execute on function public.shipment_reconciliation_lines(uuid, uuid) to authenticated;
comment on function public.shipment_reconciliation_lines(uuid, uuid) is
  'Despachado contra recibido de cada producto, sin sumar unidades distintas. Visible para quien despacha y para quien recibe.';

-- ============================================================ 13. reportes

-- `pending_dispatches` leía categoría, unidad y cantidad de la cabecera, que ya no las
-- tiene. Ahora devuelve una fila por producto pedido: sumar litros con kits para caber en
-- una sola fila habría sido inventar una cifra.
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
    item.category,
    item.unit,
    item.quantity_authorized,
    request.status::text,
    request.decided_at
  from public.transfer_requests as request
  join public.transfer_request_items as item on item.transfer_request_id = request.id
  join public.inventory_locations as origin on origin.id = request.origin_location_id
  join public.inventory_locations as destination on destination.id = request.destination_location_id
  where request.event_id = p_event_id
    and request.status = 'authorized'
    and item.quantity_authorized > 0
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
  order by 9 desc nulls last;
$$;
