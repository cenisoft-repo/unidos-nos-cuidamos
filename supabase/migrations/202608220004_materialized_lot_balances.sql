-- B6 / G-068 · El saldo por lote se mantiene al escribir, no se recalcula al leer.
--
-- QUÉ CUESTA HOY, MEDIDO EN F0 SOBRE 980.007 MOVIMIENTOS
-- -----------------------------------------------------
-- `inventory_lot_positions` es una vista cuyo primer CTE agrega **toda** la tabla
-- `stock_movements` con `group by lot_id`, sin filtro de evento que empujar. Leerla cuesta
-- 213 ms. Pero el problema no es leerla una vez:
--
--   `logistics_requests` recorre las solicitudes del evento —10.000—
--     y por cada una llama a `transfer_request_lines`
--       que por cada línea —unas 20.000— suma sobre `inventory_lot_positions`
--
-- Son veinte mil agregaciones completas de un millón de filas. Medido: **no termina en 20 s**.
-- No es una consulta lenta, es una consulta que a escala no existe.
--
-- LA REGLA QUE ESTO NO PUEDE ROMPER
-- ---------------------------------
-- «El Kardex es la fuente de verdad. Nunca escritura directa de existencias.» Sigue siéndolo.
-- Lo que se añade **no es un segundo origen**: es una caché derivada, mantenida por
-- disparador desde las dos únicas fuentes que existen, y que nadie puede escribir a mano. Si
-- alguna vez difiere del Kardex, difiere la caché, y por eso se comprueba con una función que
-- recalcula desde el origen y compara. Una caché de existencias que puede mentir sin que nadie
-- se entere sería exactamente el defecto que este proyecto existe para no cometer.
--
-- LA TRAMPA QUE EL LOOP AVISA, Y ES REAL
-- --------------------------------------
-- `register_delivery` escribe el `transfer_in` sobre el lote **nuevo** del destino y ninguna
-- fila contra el lote de origen. Así que un disparador sobre `stock_movements` **no basta**:
-- lo entregado y lo perdido viven en `delivery_items`, enlazados al lote por
-- `shipment_items → allocations`. Hay dos fuentes y las dos alimentan la caché.

-- ---------------------------------------------------------------- la caché

create table if not exists public.inventory_lot_balances (
  lot_id uuid primary key references public.inventory_lots(id) on delete cascade,
  -- El tenant se denormaliza desde el lote a proposito. La vista es `security_invoker`, asi
  -- que la RLS de esta tabla tiene que decir lo mismo que la de `inventory_lots`; con estas
  -- dos columnas la politica es identica y cuesta lo mismo, en vez de una subconsulta por
  -- fila que devolveria por la ventana el coste que esta migracion vino a quitar.
  event_id uuid not null references public.emergency_events(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Del Kardex: exactamente las tres sumas que la vista calculaba.
  available numeric not null default 0,
  reserved numeric not null default 0,
  dispatched numeric not null default 0,
  -- De las líneas de entrega, que el Kardex no refleja contra el lote de origen.
  delivered numeric not null default 0,
  lost numeric not null default 0,
  updated_at timestamptz not null default now()
);

comment on table public.inventory_lot_balances is
  'Cache derivada del saldo por lote. NO es fuente de verdad: la fuente sigue siendo stock_movements y delivery_items. La mantienen disparadores y se comprueba con assert_lot_balances_match_kardex() (B6).';

alter table public.inventory_lot_balances enable row level security;

-- `inventory_lot_positions` es una vista **del invocador** (`security_invoker = true`), y eso
-- es lo que hace que la RLS de las tablas de debajo se aplique de verdad. Asi que esta tabla
-- necesita su propia politica, con exactamente la misma regla que la del lote: quien no es de
-- la organizacion no ve la fila. Sin ella, materializar habria convertido una vista que
-- respetaba el tenant en una que lo ignora.
create policy "org members read lot balances" on public.inventory_lot_balances
  for select using (public.is_org_member(organization_id, event_id));

-- Solo lectura, y solo por la politica. Escribir existencias sigue siendo cosa de los
-- disparadores desde el Kardex.
--
-- El REVOKE es TOTAL y despues se concede lo justo. Enumerar `insert, update, delete` dejaba
-- fuera **TRUNCATE**, que estas tablas heredan por omision y que no dispara ningun disparador
-- de fila: un solo `truncate` habria dejado los 20.004 lotes en cero fisico, cero disponible y
-- cero reservado, con el Kardex intacto y sin un error en los registros. Es exactamente el
-- defecto que la cabecera de esta migracion dice que el proyecto existe para no cometer, y lo
-- destapo una revision adversaria, no la lista de privilegios que yo enumere.
revoke all on table public.inventory_lot_balances from public, anon, authenticated, service_role;
grant select on table public.inventory_lot_balances to authenticated;

-- ---------------------------------------------------------------- el mantenimiento

-- Un movimiento del Kardex es inmutable y solo se inserta (`stock_movements_immutable`), asi
-- que basta con aplicar su delta. No hace falta contemplar UPDATE ni DELETE: si algun dia se
-- pudieran, este disparador se quedaria corto, y por eso la comprobacion de coherencia existe.
create or replace function public.apply_lot_balance_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.inventory_lot_balances as saldo (lot_id, event_id, organization_id, available, reserved, dispatched, updated_at)
  values (
    new.lot_id,
    new.event_id,
    new.organization_id,
    new.quantity_delta,
    case when new.movement_type in ('reserve','release') then -new.quantity_delta else 0 end,
    case when new.movement_type in ('dispatch','transfer_out') then -new.quantity_delta else 0 end,
    now()
  )
  on conflict (lot_id) do update set
    available = saldo.available + excluded.available,
    reserved = saldo.reserved + excluded.reserved,
    dispatched = saldo.dispatched + excluded.dispatched,
    updated_at = now();
  return null;
end;
$$;

drop trigger if exists stock_movements_lot_balance on public.stock_movements;
create trigger stock_movements_lot_balance
  after insert on public.stock_movements
  for each row execute function public.apply_lot_balance_movement();

-- Lo entregado y lo perdido llegan por `delivery_items`, que no tiene disparador de
-- inmutabilidad, asi que aqui si hay que contemplar las tres operaciones y aplicar la
-- diferencia en vez de la cantidad.
create or replace function public.apply_lot_balance_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  lote uuid;
  lote_evento uuid;
  lote_organizacion uuid;
  delta_entregado numeric := 0;
  delta_perdido numeric := 0;
  linea record;
begin
  linea := case when tg_op = 'DELETE' then old else new end;

  select allocation.lot_id, lot.event_id, lot.organization_id
  into lote, lote_evento, lote_organizacion
  from public.shipment_items as shipment_item
  join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  join public.inventory_lots as lot on lot.id = allocation.lot_id
  where shipment_item.id = linea.shipment_item_id;

  if lote is null then return null; end if;

  if tg_op <> 'DELETE' then
    delta_entregado := delta_entregado + coalesce(new.quantity_delivered, 0);
    delta_perdido := delta_perdido + coalesce(new.quantity_damaged, 0) + coalesce(new.quantity_missing, 0);
  end if;
  if tg_op <> 'INSERT' then
    delta_entregado := delta_entregado - coalesce(old.quantity_delivered, 0);
    delta_perdido := delta_perdido - coalesce(old.quantity_damaged, 0) - coalesce(old.quantity_missing, 0);
  end if;

  insert into public.inventory_lot_balances as saldo (lot_id, event_id, organization_id, delivered, lost, updated_at)
  values (lote, lote_evento, lote_organizacion, delta_entregado, delta_perdido, now())
  on conflict (lot_id) do update set
    delivered = saldo.delivered + excluded.delivered,
    lost = saldo.lost + excluded.lost,
    updated_at = now();
  return null;
end;
$$;

drop trigger if exists delivery_items_lot_balance on public.delivery_items;
create trigger delivery_items_lot_balance
  after insert or update or delete on public.delivery_items
  for each row execute function public.apply_lot_balance_delivery();

-- Un lote nuevo nace con su fila en cero, para que la vista no dependa de un `left join` que
-- haga distinta a la primera lectura.
create or replace function public.seed_lot_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.inventory_lot_balances(lot_id, event_id, organization_id)
  values (new.id, new.event_id, new.organization_id)
  on conflict (lot_id) do nothing;
  return null;
end;
$$;

drop trigger if exists inventory_lots_balance_seed on public.inventory_lots;
create trigger inventory_lots_balance_seed
  after insert on public.inventory_lots
  for each row execute function public.seed_lot_balance();

-- ---------------------------------------------------------------- el relleno inicial

-- Se calcula desde el origen exactamente igual que lo hacia la vista, para que el corte entre
-- «antes» y «despues» sea invisible en las cifras.
insert into public.inventory_lot_balances(lot_id, event_id, organization_id, available, reserved, dispatched, delivered, lost)
select
  lot.id,
  lot.event_id,
  lot.organization_id,
  coalesce(movimiento.available, 0),
  coalesce(movimiento.reserved, 0),
  coalesce(movimiento.dispatched, 0),
  coalesce(entrega.delivered, 0),
  coalesce(entrega.lost, 0)
from public.inventory_lots as lot
left join (
  select
    movement.lot_id,
    sum(movement.quantity_delta) as available,
    sum(case when movement.movement_type in ('reserve','release') then -movement.quantity_delta else 0 end) as reserved,
    sum(case when movement.movement_type in ('dispatch','transfer_out') then -movement.quantity_delta else 0 end) as dispatched
  from public.stock_movements as movement
  group by movement.lot_id
) as movimiento on movimiento.lot_id = lot.id
left join (
  select
    allocation.lot_id,
    sum(delivery_item.quantity_delivered) as delivered,
    sum(delivery_item.quantity_damaged + delivery_item.quantity_missing) as lost
  from public.delivery_items as delivery_item
  join public.shipment_items as shipment_item on shipment_item.id = delivery_item.shipment_item_id
  join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  group by allocation.lot_id
) as entrega on entrega.lot_id = lot.id
on conflict (lot_id) do update set
  available = excluded.available,
  reserved = excluded.reserved,
  dispatched = excluded.dispatched,
  delivered = excluded.delivered,
  lost = excluded.lost,
  updated_at = now();

-- ---------------------------------------------------------------- la vista, ya barata

-- Mismo contrato, mismas columnas, mismos valores. Lo unico que cambia es de donde salen: de
-- una fila por lote en vez de una agregacion de la tabla entera.
--
-- `security_invoker = true` NO es decorativo y no puede omitirse: es lo que hace que la RLS de
-- `inventory_lots` y de la cache se aplique al lector. `create or replace view` **no conserva**
-- esta opcion si no se repite, y omitirla convierte la vista en una del dueno, que ignora la
-- RLS de todo lo que hay debajo. Al escribir esta migracion se omitio, y el resultado fue que
-- una cuenta de una sola organizacion leia los lotes de las veintitres por la API. Se descubrio
-- comprobandolo; no lo cazo ninguna prueba, porque `verify-rls.mjs` no miraba esta vista.
create or replace view public.inventory_lot_positions
with (security_invoker = true) as
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
  coalesce(saldo.available, 0) + coalesce(saldo.reserved, 0) as quantity_physical,
  coalesce(saldo.available, 0) as quantity_available,
  coalesce(saldo.reserved, 0) as quantity_reserved,
  greatest(
    coalesce(saldo.dispatched, 0) - coalesce(saldo.delivered, 0) - coalesce(saldo.lost, 0),
    0::numeric
  ) as quantity_in_transit,
  coalesce(saldo.delivered, 0) as quantity_delivered
from public.inventory_lots as lot
left join public.inventory_lot_balances as saldo on saldo.lot_id = lot.id;

-- ---------------------------------------------------------------- la comprobacion

-- La caché tiene que poder demostrarse. Esta funcion recalcula desde el Kardex y las lineas de
-- entrega, y devuelve **una fila por cada lote que no cuadre**. Que devuelva vacio es la unica
-- razon para confiar en lo anterior; si algun dia devuelve algo, la respuesta correcta es
-- rellenar de nuevo desde el origen, nunca corregir la caché a mano.
create or replace function public.assert_lot_balances_match_kardex()
returns table(
  lot_id uuid,
  lot_code text,
  campo text,
  en_cache numeric,
  en_kardex numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with esperado as (
    select
      lot.id,
      lot.lot_code,
      coalesce(movimiento.available, 0) as available,
      coalesce(movimiento.reserved, 0) as reserved,
      coalesce(movimiento.dispatched, 0) as dispatched,
      coalesce(entrega.delivered, 0) as delivered,
      coalesce(entrega.lost, 0) as lost
    from public.inventory_lots as lot
    left join (
      select
        movement.lot_id,
        sum(movement.quantity_delta) as available,
        sum(case when movement.movement_type in ('reserve','release') then -movement.quantity_delta else 0 end) as reserved,
        sum(case when movement.movement_type in ('dispatch','transfer_out') then -movement.quantity_delta else 0 end) as dispatched
      from public.stock_movements as movement
      group by movement.lot_id
    ) as movimiento on movimiento.lot_id = lot.id
    left join (
      select
        allocation.lot_id,
        sum(delivery_item.quantity_delivered) as delivered,
        sum(delivery_item.quantity_damaged + delivery_item.quantity_missing) as lost
      from public.delivery_items as delivery_item
      join public.shipment_items as shipment_item on shipment_item.id = delivery_item.shipment_item_id
      join public.allocations as allocation on allocation.id = shipment_item.allocation_id
      group by allocation.lot_id
    ) as entrega on entrega.lot_id = lot.id
  )
  select esperado.id, esperado.lot_code, diferencia.campo, diferencia.en_cache, diferencia.en_kardex
  from esperado
  left join public.inventory_lot_balances as saldo on saldo.lot_id = esperado.id
  cross join lateral (
    values
      ('available', coalesce(saldo.available, 0), esperado.available),
      ('reserved', coalesce(saldo.reserved, 0), esperado.reserved),
      ('dispatched', coalesce(saldo.dispatched, 0), esperado.dispatched),
      ('delivered', coalesce(saldo.delivered, 0), esperado.delivered),
      ('lost', coalesce(saldo.lost, 0), esperado.lost)
  ) as diferencia(campo, en_cache, en_kardex)
  where diferencia.en_cache is distinct from diferencia.en_kardex;
$$;

revoke all on function public.assert_lot_balances_match_kardex() from public, anon, authenticated;

comment on function public.assert_lot_balances_match_kardex() is
  'Devuelve una fila por cada lote cuyo saldo en cache no coincide con el recalculado desde el Kardex y las lineas de entrega. Vacio es lo unico que autoriza a confiar en inventory_lot_positions (B6).';

-- ---------------------------------------------------------------- indices del camino caliente

-- La agregacion desaparecio, pero las lecturas por lote y por ubicacion siguen: con un millon
-- de movimientos y veinte mil lotes, buscar el saldo de una bodega no puede recorrer la tabla.
create index if not exists inventory_lots_location_event_idx
  on public.inventory_lots (location_id, event_id);

-- `database_test.sql` exige desde hace tiempo que toda clave foranea publica tenga indice de
-- soporte, y las dos que esta tabla estrena no lo tenian. Lo caz� esa prueba, no yo.
create index if not exists inventory_lot_balances_event_id_idx
  on public.inventory_lot_balances (event_id);
create index if not exists inventory_lot_balances_organization_id_idx
  on public.inventory_lot_balances (organization_id);
-- Y el que de verdad usa la lectura: el saldo de una organizacion dentro de un evento.
create index if not exists inventory_lot_balances_tenant_idx
  on public.inventory_lot_balances (organization_id, event_id);
create index if not exists stock_movements_lot_idx
  on public.stock_movements (lot_id);
