-- Eje P0 del loop maestro: la solicitud logística generalizada, de extremo a extremo.
--
-- El escenario es el de la demostración: Red Humanitaria Demo tiene agua, mercados y
-- cobijas en su Centro de acopio Norte; Aliados Unidos Demo —otra organización del mismo
-- evento— los pide desde su Centro aliado temporal. Se comprueba lo que el documento exige:
-- multiproducto, cross-organization, los tres modos, necesidad opcional, autorización
-- parcial, reserva sin sobreventa y recepción producto a producto.
--
-- Quien pide (Rosa Manizales) pertenece SOLO a la organización solicitante. Si algo de esto
-- funcionara por tener membresía en las dos, no probaría nada.

begin;
select plan(49);

-- ---------------------------------------------------------------- fixtures

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000301','authenticated','authenticated',
  'rosa.manizales@example.invalid', extensions.crypt('RutaSolidaria2026!', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}','{"full_name":"Rosa Manizales"}', now(), now(), '','','',''
);
insert into public.memberships(user_id, organization_id, event_id, role) values
('00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','warehouse_operator'),
('00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','logistics_operator');

-- Bodega propia del ejercicio: atarse a las existencias del seed haría que cualquier
-- cambio en los datos de demostración rompiera estas cifras sin que nada esté mal.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table gen_origin as
select location_id as id from public.manage_delivery_point(
  null, '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
  'Bodega proveedora del ejercicio', 'Medellín · zona occidental', 'Dirección sintética no operativa',
  'Salida coordinada del ejercicio', 6.2600, -75.5900, false, true, false, true,
  array[]::text[], 'gen-origin-001'
);

insert into public.donations(id,event_id,organization_id,kind,status,donor_tracking_code) values
('a1000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','in_kind','received','DON-A1A1A1A1A1A1A1A1A1A1A1A1');
insert into public.donation_items(id,donation_id,category,description,quantity_promised,unit,quantity_received) values
('a1100000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','Agua','Agua embotellada',1000,'litro',1000),
('a1100000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','Alimentos','Mercados familiares',300,'kit',300),
('a1100000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000001','Refugio','Cobijas',150,'unidad',150);

-- Dos lotes de agua con vencimientos distintos: la reserva tiene que consumir primero el
-- que vence antes, y atravesar lotes cuando uno no alcanza.
insert into public.inventory_lots(id,event_id,organization_id,donation_item_id,location_id,lot_code,status,category,quantity_initial,unit,condition,expires_on,received_by) values
('a1200000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',(select id from gen_origin),'LOT-GEN-AGUA-1','available','Agua',300,'litro','sellado','2026-09-30','00000000-0000-0000-0000-000000000103'),
('a1200000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',(select id from gen_origin),'LOT-GEN-AGUA-2','available','Agua',700,'litro','sellado','2026-12-31','00000000-0000-0000-0000-000000000103'),
('a1200000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002',(select id from gen_origin),'LOT-GEN-MERC','available','Alimentos',300,'kit','sellado',null,'00000000-0000-0000-0000-000000000103'),
('a1200000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003',(select id from gen_origin),'LOT-GEN-COBI','available','Refugio',120,'unidad','usado',null,'00000000-0000-0000-0000-000000000103');

insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id) values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','receipt',300,'gen-r1','Recepción sintética','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000002','receipt',700,'gen-r2','Recepción sintética','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000003','receipt',300,'gen-r3','Recepción sintética','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000004','receipt',120,'gen-r4','Recepción sintética','00000000-0000-0000-0000-000000000103');

-- ---------------------------------------------------------------- 1. disponibilidad segura

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',true);

create temporary table gen_availability as
select * from public.shared_stock_availability('10000000-0000-0000-0000-000000000001')
where location_id = (select id from gen_origin);

select is((select count(*)::integer from gen_availability), 3,
  '01 la organización solicitante ve las tres categorías disponibles de la otra organización');
select is((select quantity_available from gen_availability where category = 'Agua'), 1000::numeric,
  '01 el agua se agrega de los dos lotes sin exponerlos');
select is((select bool_or(is_own_organization) from gen_availability), false,
  '01 la proyección declara que ese inventario no es suyo');
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as space on space.oid = routine.pronamespace,
    lateral unnest(coalesce(routine.proargnames, '{}'::text[])) as argument(name)
    where space.nspname = 'public'
      and routine.proname = 'shared_stock_availability'
      and (argument.name like '%\_private' or argument.name in ('lot_id','lot_code','exact_address_private','donor_name_private','contact_private'))
  ),
  '01 la proyección no devuelve lotes, direcciones privadas ni datos de contacto');

-- ---------------------------------------------------------------- 2. la política de compartir manda

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(public.set_location_availability_sharing((select id from gen_origin), false), false,
  '02 la bodega proveedora puede dejar de compartir su disponibilidad');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',true);
select is((select count(*)::integer from public.shared_stock_availability('10000000-0000-0000-0000-000000000001')
           where location_id = (select id from gen_origin)), 0,
  '02 sin compartir, la bodega desaparece de la disponibilidad de la red');
select throws_ok(
  $$select * from public.request_stock_transfer(
      (select id from gen_origin),'70000000-0000-0000-0000-000000000002',
      jsonb_build_array(jsonb_build_object('category','Agua','unit','litro','mode','exact_quantity','quantity',10)),
      'Intento de pedir a una bodega que no comparte su disponibilidad.',
      null, null, 'gen-request-cerrada')$$,
  '42501',
  'Esa bodega no comparte su disponibilidad con otras organizaciones del evento',
  '02 sin compartir, otra organización tampoco puede pedirle'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(public.set_location_availability_sharing((select id from gen_origin), true), true,
  '02 la bodega vuelve a compartir su disponibilidad');

-- ---------------------------------------------------------------- 3. solicitud multiproducto

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',true);
create temporary table gen_request as
select * from public.request_stock_transfer(
  (select id from gen_origin),'70000000-0000-0000-0000-000000000002',
  jsonb_build_array(
    jsonb_build_object('category','Agua','unit','litro','mode','exact_quantity','quantity',500),
    jsonb_build_object('category','Alimentos','unit','kit','mode','exact_quantity','quantity',100),
    jsonb_build_object('category','Refugio','unit','unidad','mode','all_available')
  ),
  'Manizales necesita agua, mercados y cobijas para el albergue del ejercicio.',
  null, null, 'gen-request-001'
);

select is((select line_count from gen_request), 3, '03 una sola solicitud lleva tres productos');
select is((select status::text from gen_request), 'requested', '03 la solicitud nace pendiente de autorización');
select is(
  (select requesting_organization_id from public.transfer_requests where id = (select request_id from gen_request)),
  '20000000-0000-0000-0000-000000000002'::uuid,
  '03 la solicitud distingue a quién pide de quién provee');
select is(
  (select organization_id from public.transfer_requests where id = (select request_id from gen_request)),
  '20000000-0000-0000-0000-000000000001'::uuid,
  '03 la organización proveedora es la dueña de la bodega de origen');
select ok(
  (select need_case_id is null and need_item_id is null from public.transfer_requests
   where id = (select request_id from gen_request)),
  '03 una solicitud puramente logística no necesita ninguna necesidad');
select is(
  (select quantity_requested from public.transfer_request_lines((select request_id from gen_request)) where line_no = 3),
  null::numeric,
  '03 la línea ALL_AVAILABLE no lleva cantidad: la pone la base al autorizar');
select is((select was_duplicate from public.request_stock_transfer(
    (select id from gen_origin),'70000000-0000-0000-0000-000000000002',
    jsonb_build_array(jsonb_build_object('category','Agua','unit','litro','mode','exact_quantity','quantity',500)),
    'Manizales necesita agua, mercados y cobijas para el albergue del ejercicio.',
    null, null, 'gen-request-001')),
  true, '03 repetir la solicitud con la misma clave no crea otra');

select throws_ok(
  $$select * from public.request_stock_transfer(
      (select id from gen_origin),'70000000-0000-0000-0000-000000000002',
      jsonb_build_array(jsonb_build_object('mode','full_lot','lot_id','a1200000-0000-0000-0000-000000000001')),
      'Intento de pedir un lote concreto a otra organización.',
      null, null, 'gen-request-lote-ajeno')$$,
  '42501',
  'A otra organización se le pide por cantidad o todo lo disponible, no por lote',
  '03 pedir un lote concreto exige poder verlo: entre organizaciones no se publica'
);

select throws_ok(
  format($$select public.decide_stock_transfer(%L,'authorize',null,'Autorización propia que debe fallar')$$,
    (select request_id from gen_request)),
  '42501',
  'No administras la bodega de origen',
  '03 quien pide no administra el origen y por tanto no autoriza'
);

-- ---------------------------------------------------------------- 4. lo disponible cambia

-- Entre que se leyó la disponibilidad y se autoriza entran 30 cobijas más. Lo que se
-- autoriza en ALL_AVAILABLE tiene que ser lo que hay al ejecutar, no lo que vio la pantalla.
insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id) values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000004','adjustment',30,'gen-r5','Ajuste sintético posterior a la lectura','00000000-0000-0000-0000-000000000103');

-- ---------------------------------------------------------------- 5. autorización parcial

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(
  public.decide_stock_transfer(
    (select request_id from gen_request), 'authorize',
    jsonb_build_array(jsonb_build_object(
      'item_id', (select item_id from public.transfer_request_lines((select request_id from gen_request)) where line_no = 1),
      'quantity', 450
    )),
    'Se autorizan 450 litros por reserva operativa propia'
  )::text,
  'authorized', '05 la autorización parcial deja la solicitud autorizada');

select is(
  (select quantity_authorized from public.transfer_request_lines((select request_id from gen_request)) where line_no = 1),
  450::numeric, '05 del agua se autorizan 450 de los 500 pedidos');
select is(
  (select quantity_authorized from public.transfer_request_lines((select request_id from gen_request)) where line_no = 2),
  100::numeric, '05 los mercados se autorizan completos');
select is(
  (select quantity_authorized from public.transfer_request_lines((select request_id from gen_request)) where line_no = 3),
  150::numeric, '05 ALL_AVAILABLE autoriza las 150 que hay al ejecutar, no las 120 que se leyeron');

select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = 'a1200000-0000-0000-0000-000000000001'),
  0::numeric, '05 la reserva agota primero el lote que vence antes');
select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = 'a1200000-0000-0000-0000-000000000002'),
  550::numeric, '05 y toma del siguiente solo lo que faltaba');
select is(
  (select count(*)::integer from public.allocations
   where transfer_request_id = (select request_id from gen_request)),
  4, '05 quedan cuatro reservas: dos lotes de agua, mercados y cobijas');
select is(
  (select count(*)::integer from public.allocations
   where transfer_request_id = (select request_id from gen_request)
     and transfer_request_item_id is null),
  0, '05 ninguna reserva pierde a qué línea de la solicitud responde');
select is(
  (select count(*)::integer from public.transfer_request_decisions
   where transfer_request_id = (select request_id from gen_request)
     and decided_by = '00000000-0000-0000-0000-000000000101'),
  3, '05 la decisión queda registrada línea por línea con su actor');

-- ---------------------------------------------------------------- 6. despachar

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table gen_shipment as
select public.create_shipment(
  null, (select request_id from gen_request),
  (select id from gen_origin),'70000000-0000-0000-0000-000000000002', null,
  '{"mode":"institucional","contact_name":"Conductor Sintetico","contact_document":"CC-00000009","contact_phone":"6040000009","vehicle":"Camion","plate":"gen123","responsible":"Marta Bodega"}'::jsonb,
  'gen-shipment-001'
) as id;
select is(
  (select count(*)::integer from public.shipment_items where shipment_id = (select id from gen_shipment)),
  4, '06 el despacho lleva las cuatro reservas de la solicitud');
select is(public.dispatch_shipment((select id from gen_shipment))::text, 'dispatched', '06 sale el despacho');
select is(public.advance_shipment((select id from gen_shipment), 'arrived')::text, 'arrived', '06 el despacho llega');

-- ---------------------------------------------------------------- 7. recibir producto a producto

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',true);

select throws_ok(
  format($$select public.register_delivery(%L,
    (select jsonb_agg(una.linea) from (
       select jsonb_build_object('shipment_item_id', item.id, 'delivered', item.quantity, 'damaged', 0, 'missing', 0) as linea
       from public.shipment_items as item
       where item.shipment_id = %L
       order by item.id limit 1
     ) as una),
    'gen-delivery-incompleta')$$,
    (select id from gen_shipment), (select id from gen_shipment)),
  '22023',
  'El despacho lleva 4 productos y hay que conciliarlos todos, una sola vez cada uno',
  '07 no se puede conciliar solo una parte del despacho'
);

create temporary table gen_delivery as
select public.register_delivery(
  (select id from gen_shipment),
  (select jsonb_agg(jsonb_build_object(
     'shipment_item_id', item.id,
     'delivered', case when lot.category = 'Refugio' then item.quantity - 2 else item.quantity end,
     'damaged', 0,
     'missing', case when lot.category = 'Refugio' then 2 else 0 end))
   from public.shipment_items as item
   join public.allocations as allocation on allocation.id = item.allocation_id
   join public.inventory_lots as lot on lot.id = allocation.lot_id
   where item.shipment_id = (select id from gen_shipment)),
  'gen-delivery-001'
) as id;
select ok((select id from gen_delivery) is not null, '07 el destino confirma lo que recibió de cada producto');

select is(
  (select outcome from public.shipment_reconciliation_lines((select id from gen_shipment))
   where category = 'Alimentos'),
  'CONFORME', '07 el producto que llegó completo concilia CONFORME');
select is(
  (select outcome from public.shipment_reconciliation_lines((select id from gen_shipment))
   where category = 'Refugio'),
  'NOVEDAD', '07 el producto con faltante concilia NOVEDAD, sin contagiar a los demás');
select is(
  (select quantity_missing from public.shipment_reconciliation_lines((select id from gen_shipment))
   where category = 'Refugio'),
  2::numeric, '07 el faltante queda cuantificado en su propia unidad');

select is(
  (select sum(position.quantity_available) from public.inventory_lot_positions as position
   where position.location_id = '70000000-0000-0000-0000-000000000002' and position.category = 'Agua'),
  450::numeric, '08 el inventario del destino crece exactamente con el agua confirmada');
select is(
  (select sum(position.quantity_available) from public.inventory_lot_positions as position
   where position.location_id = '70000000-0000-0000-0000-000000000002' and position.category = 'Refugio'),
  148::numeric, '08 y con las cobijas confirmadas, no con las despachadas');
select is(
  (select count(distinct position.organization_id)::integer from public.inventory_lot_positions as position
   where position.location_id = '70000000-0000-0000-0000-000000000002'
     and position.category in ('Agua','Alimentos','Refugio')),
  1, '08 el inventario recibido tiene un solo dueño');
select is(
  (select distinct position.organization_id from public.inventory_lot_positions as position
   where position.location_id = '70000000-0000-0000-0000-000000000002'
     and position.category in ('Agua','Alimentos','Refugio')),
  '20000000-0000-0000-0000-000000000002'::uuid,
  '08 y ese dueño es la organización que recibió, no la que despachó');
select is(
  (select sum(position.quantity_in_transit) from public.inventory_lot_positions as position
   where position.location_id = (select id from gen_origin)),
  0::numeric, '08 el origen no deja nada colgado en movimiento');
select is(
  (select status::text from public.transfer_requests where id = (select request_id from gen_request)),
  'closed', '08 la solicitud queda cerrada tras la confirmación del destino');

-- ---------------------------------------------------------------- 9. lote completo y necesidad

-- Dentro de la misma organización sí se puede pedir un lote concreto, porque quien pide
-- puede verlo. La cantidad la calcula la base: la línea no lleva ninguna.
insert into public.inventory_lots(id,event_id,organization_id,donation_item_id,location_id,lot_code,status,category,quantity_initial,unit,condition,received_by) values
('a1200000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000003','LOT-GEN-PROPIO','available','Alimentos',80,'kit','sellado','00000000-0000-0000-0000-000000000103');
insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id) values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000005','receipt',80,'gen-r6','Recepción sintética propia','00000000-0000-0000-0000-000000000103');

create temporary table gen_full_lot as
select * from public.request_stock_transfer(
  '70000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000002',
  jsonb_build_array(jsonb_build_object('mode','full_lot','lot_id','a1200000-0000-0000-0000-000000000005')),
  'Se traslada el lote completo de mercados desde la base logística propia.',
  '60000000-0000-0000-0000-000000000001', null,
  'gen-request-lote'
);
select is(
  (select need_case_id from public.transfer_requests where id = (select request_id from gen_full_lot)),
  '60000000-0000-0000-0000-000000000001'::uuid,
  '09 cuando existe una necesidad, la solicitud la conserva como vínculo');
select throws_ok(
  $$select * from public.request_stock_transfer(
      '70000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000002',
      jsonb_build_array(jsonb_build_object('category','Alimentos','unit','kit','mode','exact_quantity','quantity',5)),
      'Solicitud del ejercicio vinculada a un artículo que no corresponde.',
      '60000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001',
      'gen-request-necesidad-incoherente')$$,
  '22023',
  'Ninguno de los productos pedidos corresponde al artículo de la necesidad',
  '09 vincular un artículo de la necesidad y pedir otra cosa se rechaza'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(
  public.decide_stock_transfer((select request_id from gen_full_lot),'authorize',null,'Autorización del lote completo')::text,
  'authorized', '09 el lote completo se autoriza sin que nadie escriba una cantidad');
select is(
  (select quantity_authorized from public.transfer_request_lines((select request_id from gen_full_lot)) where line_no = 1),
  80::numeric, '09 la cantidad del lote la calculó la base, no el navegador');

-- ---------------------------------------------------------------- 10. rechazo y vacío

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',true);
create temporary table gen_rejected as
select * from public.request_stock_transfer(
  (select id from gen_origin),'70000000-0000-0000-0000-000000000002',
  jsonb_build_array(jsonb_build_object('category','Salud','unit','kit','mode','all_available')),
  'Solicitud del ejercicio que la bodega de origen no puede atender.',
  null, null, 'gen-request-rechazo'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select throws_ok(
  format($$select public.decide_stock_transfer(%L,'authorize',
    jsonb_build_array(jsonb_build_object('item_id','00000000-0000-0000-0000-0000000000ff','quantity',1)),
    'Decisión sobre una línea que no es de esta solicitud')$$,
    (select request_id from gen_rejected)),
  '22023',
  'Alguna línea de la decisión no pertenece a esta solicitud',
  '10 una línea ajena en la decisión no se ignora en silencio'
);
select throws_ok(
  format($$select public.decide_stock_transfer(%L,'authorize',null,'Intento de autorizar sin existencia')$$,
    (select request_id from gen_rejected)),
  '22023',
  'No hay existencia disponible para autorizar ninguna línea de esta solicitud',
  '10 autorizar sin existencia no deja una solicitud autorizada y vacía'
);
select is(
  public.decide_stock_transfer((select request_id from gen_rejected),'reject',null,'No hay existencia de esa categoría')::text,
  'rejected', '10 rechazar es una decisión válida y explicada');
select is(
  (select count(*)::integer from public.allocations where transfer_request_id = (select request_id from gen_rejected)),
  0, '10 rechazar no toca el inventario');
select is(
  (select decision from public.transfer_request_decisions
   where transfer_request_id = (select request_id from gen_rejected) order by decided_at desc limit 1),
  'reject', '10 el rechazo queda en la misma historia que la autorización');

select * from finish();
rollback;
