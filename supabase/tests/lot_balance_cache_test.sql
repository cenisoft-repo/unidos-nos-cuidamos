-- B6 / G-068 · El saldo por lote se mantiene al escribir. Y tiene que poder demostrarse.
--
-- `inventory_lot_positions` dejo de agregar `stock_movements` entera en cada lectura y pasa a
-- leer una fila por lote que mantienen disparadores. Eso es una **cache derivada**, no una
-- segunda fuente de verdad, y la unica forma de que siga mereciendo confianza es comprobar,
-- despues de cada clase de escritura, que sigue coincidiendo con el Kardex.
--
-- La comprobacion no mira numeros concretos: recalcula desde el origen y compara. Asi sigue
-- valiendo aunque manana cambien las cantidades del ejercicio sintetico.

begin;
select plan(15);

-- ------------------------------------------------------------------ existe y esta cerrada --
select has_table('public', 'inventory_lot_balances', 'Existe la cache de saldo por lote');
select has_function(
  'public', 'assert_lot_balances_match_kardex', '{}'::text[],
  'Existe la comprobacion que recalcula desde el Kardex y compara'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.inventory_lot_balances'::regclass),
  'La cache tiene RLS activada'
);
-- La vista es `security_invoker`, asi que quien la lee TIENE que poder leer la cache: sin ese
-- SELECT la consola se queda vacia. Lo que no puede es escribirla. Esta asercion se escribio
-- primero al reves —negando tambien el SELECT— y fallo en cuanto la vista volvio a ser del
-- invocador: la asercion estaba describiendo un diseno que ya no era el correcto.
select ok(
  has_table_privilege('authenticated', 'public.inventory_lot_balances', 'SELECT'),
  'Quien lee la vista puede leer la cache: sin eso, la consola se queda sin inventario'
);
-- Escribir existencias a mano seria escritura directa de inventario, que es la regla numero
-- uno del proyecto. Ni authenticated ni service_role tienen por donde.
select ok(
  not has_table_privilege('authenticated', 'public.inventory_lot_balances', 'INSERT')
  and not has_table_privilege('authenticated', 'public.inventory_lot_balances', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.inventory_lot_balances', 'DELETE')
  and not has_table_privilege('service_role', 'public.inventory_lot_balances', 'INSERT')
  and not has_table_privilege('service_role', 'public.inventory_lot_balances', 'UPDATE')
  -- TRUNCATE aparte, y no es un detalle: se hereda por omision, NO dispara ningun disparador
  -- de fila y vaciaria la cache dejando el inventario entero en cero con el Kardex intacto.
  -- La primera version de esta asercion enumeraba INSERT/UPDATE/DELETE y lo dejaba fuera.
  and not has_table_privilege('anon', 'public.inventory_lot_balances', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.inventory_lot_balances', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.inventory_lot_balances', 'TRUNCATE'),
  'Nadie de la API escribe ni vacia la cache: solo los disparadores, desde el Kardex'
);
select ok(
  not has_table_privilege('anon', 'public.inventory_lot_balances', 'SELECT'),
  'Ni un visitante'
);

-- ------------------------------------------------------- coincide con el Kardex de partida --
select is(
  (select count(*)::integer from public.assert_lot_balances_match_kardex()),
  0,
  'Tras el relleno inicial, la cache coincide con el Kardex en todos los lotes'
);

-- ------------------------------------------------------------- y despues de cada escritura --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);

insert into public.donations(id, event_id, organization_id, kind, status, donor_tracking_code)
values ('e0000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001','in_kind','promised','SALDO-1');
insert into public.donation_items(id, donation_id, category, description, quantity_promised, unit)
values ('e1000000-0000-0000-0000-0000000000b1','e0000000-0000-0000-0000-0000000000b1',
        'Agua','Agua sintetica para el saldo', 40, 'unidad');

create temporary table lote_saldo as
select public.receive_donation(
  'e1000000-0000-0000-0000-0000000000b1', '70000000-0000-0000-0000-000000000001',
  40, 0, 'sellado', 'saldo-recepcion-001') as id;

select is(
  (select count(*)::integer from public.assert_lot_balances_match_kardex()),
  0,
  'Despues de una recepcion, la cache sigue cuadrando'
);
select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = (select id from lote_saldo)),
  40::numeric,
  'Y la posicion refleja los 40 litros recibidos'
);
select is(
  (select quantity_physical from public.inventory_lot_positions where lot_id = (select id from lote_saldo)),
  40::numeric,
  'El fisico tambien'
);

-- Una reserva mueve disponible y reservado en direcciones opuestas: es el caso donde una
-- cache mal mantenida se nota antes.
-- Una reserva exige destino: `allocations_single_destination` obliga a que sea una necesidad
-- o un traslado, nunca ninguno. Se usa la necesidad de agua publicada del ejercicio.
select ok(
  public.reserve_lot_quantity(
    (select id from lote_saldo), 15,
    '61000000-0000-0000-0000-000000000001', null, null, 'saldo-reserva-001') is not null,
  'Se reservan 15 de los 40 contra una necesidad publicada'
);
select is(
  (select count(*)::integer from public.assert_lot_balances_match_kardex()),
  0,
  'Despues de una reserva, la cache sigue cuadrando'
);
select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = (select id from lote_saldo)),
  25::numeric,
  'Disponible baja a 25'
);
select is(
  (select quantity_reserved from public.inventory_lot_positions where lot_id = (select id from lote_saldo)),
  15::numeric,
  'Y reservado sube a 15'
);
select is(
  (select quantity_physical from public.inventory_lot_positions where lot_id = (select id from lote_saldo)),
  40::numeric,
  'El fisico no se mueve: reservar no saca nada de la bodega'
);

select * from finish();
rollback;
