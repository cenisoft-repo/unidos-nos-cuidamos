-- G-074 · Un rechazo total tiene que dejar huella, o la cola lo repite.
--
-- `receive_donation` resuelve su idempotencia buscando el movimiento de Kardex que la clave
-- produjo. La rama de rechazo total no crea ninguno —nada entra, asi que no hay lote— y salia
-- sin dejar nada. El reintento no encontraba huella y volvia a sumar al contador de rechazado:
-- 10, 20, 30, hasta que el propio guardian de la funcion bloqueaba el aporte para siempre.
--
-- Lo alcanza cualquiera que rechace estando sin conexion: la cola reintenta sola.
--
-- Lo que se fija aqui no es «existe la tabla», sino **que repetir la llamada no repita el
-- efecto**, que es lo unico que significa idempotente.

begin;
select plan(12);

-- --------------------------------------------------------------------- el registro nuevo --
select has_table('public', 'intake_rejections', 'El rechazo total tiene su propio registro');
select ok(
  exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.intake_rejections'::regclass
      and tgname = 'intake_rejections_immutable' and not tgisinternal
  ),
  'Y es append-only: un rechazo es un hecho, no una fila editable'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.intake_rejections'::regclass and contype = 'u'
      and pg_get_constraintdef(oid) like '%organization_id%idempotency_key%'
  ),
  'La clave pertenece a una organizacion, igual que en el resto del sistema (ADR-023)'
);
select ok(
  not has_table_privilege('authenticated', 'public.intake_rejections', 'INSERT')
  and not has_table_privilege('authenticated', 'public.intake_rejections', 'UPDATE')
  and not has_table_privilege('anon', 'public.intake_rejections', 'SELECT'),
  'Solo la escribe receive_donation; desde la API es de lectura y solo para quien es de la organizacion'
);

-- ------------------------------------------------------------------- y el comportamiento --
insert into public.donations(id, event_id, organization_id, kind, status, donor_tracking_code)
values ('ed000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001','in_kind','promised','RECHAZO-PRUEBA');
insert into public.donation_items(id, donation_id, category, description, quantity_promised, unit)
values ('ed100000-0000-0000-0000-0000000000c1','ed000000-0000-0000-0000-0000000000c1',
        'Agua','Agua sintetica para la prueba de rechazo', 30, 'unidad');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);

-- Primer rechazo total de 10 de los 30 prometidos.
select is(
  public.receive_donation(
    'ed100000-0000-0000-0000-0000000000c1','70000000-0000-0000-0000-000000000001',
    0, 10, 'dañado', 'clave-de-rechazo-total'),
  null::uuid,
  'Un rechazo total no crea lote: nada entro al inventario'
);
select is(
  (select quantity_rejected from public.donation_items where id = 'ed100000-0000-0000-0000-0000000000c1'),
  10::numeric,
  'Y el contador registra los 10 rechazados'
);
select is(
  (select count(*)::integer from public.intake_rejections
   where idempotency_key = 'clave-de-rechazo-total'),
  1,
  'Queda su registro, con quien y cuando: antes solo quedaba un contador incrementado'
);

-- LA PRUEBA: la cola sin conexion reintenta con la misma clave.
select is(
  public.receive_donation(
    'ed100000-0000-0000-0000-0000000000c1','70000000-0000-0000-0000-000000000001',
    0, 10, 'dañado', 'clave-de-rechazo-total'),
  null::uuid,
  'El reintento con la misma clave devuelve lo mismo'
);
select is(
  (select quantity_rejected from public.donation_items where id = 'ed100000-0000-0000-0000-0000000000c1'),
  10::numeric,
  'Y NO vuelve a sumar: antes pasaba de 10 a 20'
);
select is(
  (select count(*)::integer from public.intake_rejections
   where idempotency_key = 'clave-de-rechazo-total'),
  1,
  'Ni duplica el registro'
);

-- Y lo que de verdad se perdia: que el aporte siguiera pudiendo recibirse. Con el contador
-- inflado, el guardian de cantidades bloqueaba cualquier recepcion real para siempre.
select ok(
  public.receive_donation(
    'ed100000-0000-0000-0000-0000000000c1','70000000-0000-0000-0000-000000000001',
    5, 0, 'sellado', 'clave-de-recepcion-real') is not null,
  'Despues de los reintentos, el aporte todavia puede recibir de verdad'
);
select is(
  (select quantity_received from public.donation_items where id = 'ed100000-0000-0000-0000-0000000000c1'),
  5::numeric,
  'Y los 5 aceptados entran al inventario'
);

select * from finish();
rollback;
