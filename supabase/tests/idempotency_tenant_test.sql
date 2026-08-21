-- B5 · La clave de idempotencia pertenece a una organizacion, y la busqueda tiene que decirlo.
--
-- Lo que se comprueba aqui no es que la idempotencia funcione —eso ya lo cubren las pruebas
-- de concurrencia— sino que NO ATRAVIESE organizaciones. La unicidad de la clave es
-- `(organization_id, idempotency_key)`, asi que dos organizaciones pueden usar la misma
-- legitimamente; buscar solo por la clave encontraba la ajena.

begin;
select plan(11);

-- --------------------------------------------- la busqueda declara de quien es la clave --
-- Guarda estructural: si alguien reescribe una de estas funciones y vuelve a buscar por la
-- clave a secas, esto falla antes de que nadie pierda un movimiento de Kardex.
select ok(
  substring((select prosrc from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'receive_donation')
  -- Se mira SOLO dentro de la sentencia de busqueda, hasta el punto y coma. Mirar el
  -- cuerpo entero no probaba nada: `organization_id` aparece mas abajo en los INSERT,
  -- asi que la comprobacion pasaba tambien con el defecto puesto. Lo destapo romperla.
  from 'idempotency_key = p_idempotency_key[^;]*') like '%organization_id%',
  'receive_donation acota la busqueda de idempotencia por organizacion'
);
select ok(
  substring((select prosrc from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reserve_lot_quantity')
  -- Se mira SOLO dentro de la sentencia de busqueda, hasta el punto y coma. Mirar el
  -- cuerpo entero no probaba nada: `organization_id` aparece mas abajo en los INSERT,
  -- asi que la comprobacion pasaba tambien con el defecto puesto. Lo destapo romperla.
  from 'idempotency_key = p_idempotency_key[^;]*') like '%organization_id%',
  'reserve_lot_quantity acota la busqueda de idempotencia por organizacion'
);
select ok(
  substring((select prosrc from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_shipment')
  -- Se mira SOLO dentro de la sentencia de busqueda, hasta el punto y coma. Mirar el
  -- cuerpo entero no probaba nada: `organization_id` aparece mas abajo en los INSERT,
  -- asi que la comprobacion pasaba tambien con el defecto puesto. Lo destapo romperla.
  from 'idempotency_key = p_idempotency_key[^;]*') like '%organization_id%',
  'create_shipment acota la busqueda de idempotencia por organizacion'
);
select ok(
  substring((select prosrc from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reconcile_sandbox_payment')
  -- Se mira SOLO dentro de la sentencia de busqueda, hasta el punto y coma. Mirar el
  -- cuerpo entero no probaba nada: `organization_id` aparece mas abajo en los INSERT,
  -- asi que la comprobacion pasaba tambien con el defecto puesto. Lo destapo romperla.
  from 'idempotency_key = p_idempotency_key[^;]*') like '%organization_id%',
  'reconcile_sandbox_payment acota la busqueda sobre el libro financiero por organizacion'
);

-- ------------------------------------------------- y el comportamiento, de punta a punta --
-- Dos organizaciones distintas usando la MISMA clave. Antes, la segunda recibia el lote de
-- la primera, su recepcion no se registraba y su inventario quedaba en cero creyendo lo
-- contrario.
insert into public.donations(id, event_id, organization_id, kind, status, donor_tracking_code)
values ('e0000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001','in_kind','promised','COL-ORG1'),
       ('e0000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000002','in_kind','promised','COL-ORG2');
insert into public.donation_items(id, donation_id, category, description, quantity_promised, unit)
values ('e1000000-0000-0000-0000-0000000000a1','e0000000-0000-0000-0000-0000000000a1',
        'Agua','Agua sintetica de la organizacion uno', 5, 'litro'),
       ('e1000000-0000-0000-0000-0000000000a2','e0000000-0000-0000-0000-0000000000a2',
        'Agua','Agua sintetica de la organizacion dos', 7, 'litro');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);

create temporary table recepcion_org1 as
select public.receive_donation(
  'e1000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-000000000001',
  5, 0, 'sellado', 'clave-que-las-dos-organizaciones-usan') as lote;
create temporary table recepcion_org2 as
select public.receive_donation(
  'e1000000-0000-0000-0000-0000000000a2', '70000000-0000-0000-0000-000000000002',
  7, 0, 'sellado', 'clave-que-las-dos-organizaciones-usan') as lote;

select isnt(
  (select lote from recepcion_org2), (select lote from recepcion_org1),
  'Cada organizacion recibe SU lote, no el de la otra, aunque compartan clave'
);
select is(
  (select lot.organization_id from public.inventory_lots as lot where lot.id = (select lote from recepcion_org2)),
  '20000000-0000-0000-0000-000000000002'::uuid,
  'El lote devuelto pertenece a quien pidio la recepcion'
);
select is(
  (select count(*)::integer from public.stock_movements
   where idempotency_key = 'clave-que-las-dos-organizaciones-usan'),
  2,
  'El Kardex conserva las dos recepciones: la clave compartida no borra una'
);
select is(
  (select lot.quantity_initial from public.inventory_lots as lot where lot.id = (select lote from recepcion_org2)),
  7::numeric,
  'La organizacion dos tiene de verdad los 7 litros que creyo recibir'
);

-- Y la idempotencia real, la de la misma organizacion, sigue funcionando: repetir la misma
-- llamada no crea un segundo lote. Arreglar la colision no puede romper lo que protegia.
select is(
  public.receive_donation(
    'e1000000-0000-0000-0000-0000000000a2', '70000000-0000-0000-0000-000000000002',
    7, 0, 'sellado', 'clave-que-las-dos-organizaciones-usan'),
  (select lote from recepcion_org2),
  'Repetir la misma llamada de la misma organizacion devuelve el mismo lote'
);
select is(
  (select count(*)::integer from public.stock_movements
   where idempotency_key = 'clave-que-las-dos-organizaciones-usan'),
  2,
  'Y no descuenta ni recibe dos veces'
);

-- ------------------------------------------------------------------ el indice que sirve --
select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public' and tablename = 'stock_movements'
      and indexdef like '%organization_id%idempotency_key%'
  ),
  'El indice compuesto que ya existia es el que estas busquedas pueden usar ahora'
);

select * from finish();
rollback;
