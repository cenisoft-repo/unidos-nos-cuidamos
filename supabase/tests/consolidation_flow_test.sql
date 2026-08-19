-- Fase 17 del loop de consolidación: el escenario completo, de la necesidad a la entrega
-- auditable, en los veinte pasos que define el documento. Si esto pasa, la arquitectura
-- principal está funcionando.
--
--  1 necesidad de 50 kg · 2 aliado se registra · 3 confirma correo · 4 obtiene cuenta ALIADO
--  5 entra a la necesidad · 6 AYUDAR · 7 dona 25 kg · 8 evidencia · 9 punto de acopio
-- 10 la bodega recibe 25 · 11 entran al inventario · 12 otra bodega solicita 15
-- 13 el administrador autoriza 15 · 14 pasan a RESERVADO · 15 transportador y vehículo
-- 16 sale el despacho · 17 pasan a EN MOVIMIENTO · 18 el destino confirma 15
-- 19 se actualiza el inventario destino · 20 el movimiento queda cerrado y auditable

begin;
select plan(54);

-- ---------------------------------------------------------------- 1. necesidad de 50 kg

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table flow_need as
select * from public.submit_need_report(
  '10000000-0000-0000-0000-000000000001',
  'Alimentos',
  'Se requieren cincuenta kilogramos de arroz para el comedor comunitario del ejercicio sintético.',
  'Medellín · zona centro',
  50, 'kilogramo', null, '{}'::jsonb, null
);
select ok((select need_id from flow_need) is not null, '01 la necesidad queda registrada');
select is(
  public.review_need_case((select need_id from flow_need),'verify','Verificación del ejercicio',90,null,6.2500,-75.5700)::text,
  'verified', '01 la necesidad se verifica');
select is(
  public.review_need_case((select need_id from flow_need),'publish','Publicación del ejercicio',90,null,6.2500,-75.5700)::text,
  'published', '01 la necesidad se publica con 50 kg solicitados');

-- ---------------------------------------------------------------- 2 a 4. aliado ALIADO

select set_config('request.jwt.claims','{"role":"anon"}',true);
create temporary table flow_registration as
select * from public.register_ally(
  '10000000-0000-0000-0000-000000000001', 'empresa', 'Alimentos del Valle SAS', 'NIT-900123456',
  'Responsable Sintético', '6041112233', 'aliado.nuevo@example.invalid',
  'Cali · zona sur', 3.4200, -76.5300, null
);
select is((select platform_identifier from flow_registration), 'alimentos-del-valle-sas@rutasolidaria.co',
  '02 el registro reserva el identificador de plataforma del aliado');
select is((select status::text from flow_registration), 'pending_email',
  '02 el registro nace pendiente de confirmación de correo');

-- La identidad la crea Auth. Aquí se simulan las dos situaciones: sin confirmar y confirmada.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000201','authenticated','authenticated',
  'aliado.nuevo@example.invalid', extensions.crypt('RutaSolidaria2026!', extensions.gen_salt('bf')), null,
  '{"provider":"email","providers":["email"]}','{"full_name":"Aliado Nuevo"}', now(), now(), '','','','' 
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',true);
select throws_ok(
  $$select * from public.activate_ally_registration()$$,
  '42501',
  'Confirma el correo desde el mensaje que te enviamos antes de activar la cuenta ALIADO',
  '03 sin correo confirmado la cuenta no puede operar'
);

update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000201';
create temporary table flow_activation as select * from public.activate_ally_registration();
select ok((select organization_id from flow_activation) is not null, '04 la activación crea la organización del aliado');
select is(
  (select count(*)::integer from public.memberships
   where user_id = '00000000-0000-0000-0000-000000000201'
     and organization_id = (select organization_id from flow_activation)
     and role = 'partner_reporter' and active),
  1, '04 la activación entrega exactamente el rol ALIADO');
select is(
  (select organization_id from public.activate_ally_registration()),
  (select organization_id from flow_activation),
  '04 repetir la activación devuelve la misma organización');

create temporary table flow_point as
select id from public.inventory_locations
where organization_id = (select organization_id from flow_activation)
  and event_id = '10000000-0000-0000-0000-000000000001';
select is((select count(*)::integer from flow_point), 1, '09 el aliado nace con su punto de acopio');

-- ---------------------------------------------------------------- 5 a 7. AYUDAR con 25 kg

create temporary table flow_help as
select * from public.need_help_options(
  (select id from public.public_need_projections where source_need_id = (select need_id from flow_need))
);
select is((select quantity_requested from flow_help), 50::numeric, '05 la necesidad publica 50 kg solicitados');
select is((select quantity_pending from flow_help), 50::numeric, '05 la necesidad publica 50 kg pendientes');

create temporary table flow_intake as
select * from public.submit_donation_intake_v2(
  '10000000-0000-0000-0000-000000000001',
  (select organization_id from flow_activation),
  'in_kind', 'flow-intake-001', 'Alimentos del Valle SAS',
  '{"email":"aliado.nuevo@example.invalid"}'::jsonb,
  'anonymous', '', false, 'comprometida',
  jsonb_build_array(jsonb_build_object(
    'category','Alimentos','category_code','alimentos','description','Arroz en sacos sellados',
    'quantity',25,'unit','kilogramo','condition','sellado','storage_requirement','ambiente',
    'need_item_id',(select need_item_id from flow_help)
  )),
  null,
  (select id from flow_point),
  '{"specific_destination":false}'::jsonb,
  public.current_donation_catalog_versions(),
  null,
  (select need_case_id from flow_help)
);
select ok((select intake_id from flow_intake) is not null, '07 el aliado aporta 25 de los 50 kg');
select is(
  (select quantity_committed from public.need_item_positions where need_item_id = (select need_item_id from flow_help)),
  25::numeric, '07 la necesidad registra 25 kg comprometidos');
select is(
  (select quantity_pending from public.need_item_positions where need_item_id = (select need_item_id from flow_help)),
  25::numeric, '07 la necesidad conserva 25 kg pendientes para otros aliados');
select throws_ok(
  format($$select * from public.submit_donation_intake_v2(
    '10000000-0000-0000-0000-000000000001', %L, 'in_kind', 'flow-intake-over', 'Alimentos del Valle SAS',
    '{"email":"aliado.nuevo@example.invalid"}'::jsonb, 'anonymous', '', false, 'comprometida',
    jsonb_build_array(jsonb_build_object(
      'category','Alimentos','category_code','alimentos','description','Arroz adicional',
      'quantity',30,'unit','kilogramo','condition','sellado','storage_requirement','ambiente',
      'need_item_id',%L)),
    null, %L, '{"specific_destination":false}'::jsonb,
    public.current_donation_catalog_versions(), null, %L)$$,
    (select organization_id from flow_activation),
    (select need_item_id from flow_help),
    (select id from flow_point),
    (select need_case_id from flow_help)),
  '22023',
  'A esa necesidad solo le faltan 25 kilogramo',
  '07 no se puede comprometer más de lo que falta'
);

-- ---------------------------------------------------------------- 10 y 11. recepción

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table flow_donation as
select public.review_donation_intake((select intake_id from flow_intake),'approve','Aprobación del ejercicio') as id;
select ok((select id from flow_donation) is not null, '10 la verificación crea la donación operacional');
select is(
  (select need_item_id from public.donation_items where donation_id = (select id from flow_donation)),
  (select need_item_id from flow_help),
  '10 la donación conserva a qué necesidad responde');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table flow_lot as
select public.receive_donation(
  (select id from public.donation_items where donation_id = (select id from flow_donation)),
  (select id from flow_point), 25, 0, 'sellado', 'flow-receipt-001'
) as id;
select ok((select id from flow_lot) is not null, '11 la recepción crea el lote en la bodega');
select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  25::numeric, '11 el Kardex reporta 25 kg disponibles');
select is(
  (select quantity_physical from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  25::numeric, '11 el físico coincide con lo recibido');

-- ---------------------------------------------------------------- 12 a 14. traslado de 15 kg

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table flow_destination as
select location_id as id from public.manage_delivery_point(
  null, '10000000-0000-0000-0000-000000000001', (select organization_id from flow_activation),
  'Bodega destino del ejercicio', 'Cali · zona norte', 'Dirección sintética no operativa',
  'Recepción coordinada del ejercicio', 3.4800, -76.5200, false, true, true, false,
  array['Alimentos']::text[], 'flow-destination-001'
);
select ok((select id from flow_destination) is not null, '12 existe una segunda bodega que puede recibir');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table flow_transfer as
select * from public.request_stock_transfer(
  (select id from flow_point), (select id from flow_destination),
  'Alimentos', 'kilogramo', 15,
  'La bodega destino necesita arroz para el comedor del ejercicio.',
  'flow-transfer-001'
);
select is((select status::text from flow_transfer), 'requested', '12 la otra bodega solicita 15 kg');
select throws_ok(
  format($$select public.decide_stock_transfer(%L,'authorize',15,'Autorización propia que debe fallar')$$,
    (select request_id from flow_transfer)),
  '42501',
  'Quien solicita no puede autorizar su propia solicitud',
  '13 quien solicita no puede autorizarse a sí mismo'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(
  public.decide_stock_transfer((select request_id from flow_transfer),'authorize',15,'Autorización del ejercicio')::text,
  'authorized', '13 el administrador autoriza 15 kg de los 15 solicitados');
select is(
  (select quantity_reserved from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  15::numeric, '14 los 15 kg pasan a RESERVADO');
select is(
  (select quantity_available from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  10::numeric, '14 quedan 10 kg disponibles en el origen');
select is(
  (select quantity_physical from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  25::numeric, '14 el físico no cambia porque nada ha salido');

-- ---------------------------------------------------------------- 15 a 17. transporte y salida

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table flow_shipment as
select public.create_shipment(
  null, (select request_id from flow_transfer), (select id from flow_point), (select id from flow_destination),
  null, '{}'::jsonb, 'flow-shipment-001'
) as id;
select is(
  (select status::text from public.shipments where id = (select id from flow_shipment)),
  'preparing', '15 el traslado se arma en Preparando');
select throws_ok(
  format($$select public.dispatch_shipment(%L)$$, (select id from flow_shipment)),
  '22023',
  'Indica si el transporte es transportadora, particular o institucional',
  '15 sin datos de transporte el despacho no puede salir'
);
select ok(
  public.set_shipment_transport(
    (select id from flow_shipment),
    '{"mode":"transportadora","company":"Transportes Sintéticos SAS","contact_name":"Conductor Sintético","contact_document":"CC-00000001","contact_phone":"6040000000","vehicle":"Camión sencillo","plate":"abc123","responsible":"Marta Bodega"}'::jsonb
  ) is not null, '15 se registran transportador, vehículo y placa');
select is(
  (select transport_plate from public.shipments where id = (select id from flow_shipment)),
  'ABC123', '15 la placa queda normalizada');
select is(
  public.dispatch_shipment((select id from flow_shipment))::text,
  'dispatched', '16 sale el despacho');
select is(
  public.advance_shipment((select id from flow_shipment), 'in_transit')::text,
  'in_transit', '17 el despacho pasa a EN MOVIMIENTO');
select is(
  (select quantity_in_transit from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  15::numeric, '17 los 15 kg figuran en movimiento');
select is(
  (select quantity_physical from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  10::numeric, '17 el origen conserva 10 kg físicos');

-- ---------------------------------------------------------------- 18 a 20. destino y cierre

select is(
  public.advance_shipment((select id from flow_shipment), 'arrived')::text,
  'arrived', '18 el despacho reporta llegada');
select throws_ok(
  format($$select public.register_delivery(%L, 10, 0, 0, 'flow-delivery-bad')$$, (select id from flow_shipment)),
  '22023',
  'Lo recibido, lo dañado y el faltante deben sumar 15',
  '18 la recepción tiene que conciliar con lo despachado'
);
create temporary table flow_delivery as
select public.register_delivery((select id from flow_shipment), 15, 0, 0, 'flow-delivery-001') as id;
select is(
  (select outcome from public.shipment_reconciliation((select id from flow_shipment))),
  'CONFORME', '18 el destino confirma 15 kg y la conciliación es CONFORME');
select is(
  (select sum(lot_position.quantity_available)
   from public.inventory_lot_positions as lot_position
   where lot_position.location_id = (select id from flow_destination)),
  15::numeric, '19 el inventario del destino crece exactamente en lo confirmado');
select is(
  (select quantity_in_transit from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  0::numeric, '19 el origen deja de reportar producto en movimiento');
select is(
  (select status::text from public.transfer_requests where id = (select request_id from flow_transfer)),
  'closed', '20 el traslado queda cerrado');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select throws_ok(
  format($$select public.validate_delivery(%L, 'Intento sobre un traslado')$$, (select id from flow_delivery)),
  '22023',
  'Un traslado entre bodegas se cierra con la confirmación del destino, no con validación de entrega',
  '20 un traslado no se valida como entrega final'
);
select ok(
  (select count(*) from public.audit_events
   where entity_table = 'transfer_requests'
     and entity_id = (select request_id from flow_transfer)) >= 3,
  '20 la solicitud, la autorización y el cierre quedan auditados');

-- ------------------------------------------- 21 a 24. el destino recibe de menos
-- Fase 15 del loop: si el destino recibe 3 de los 5 que salieron, su inventario crece
-- solo en 3, la diferencia queda registrada como faltante y el historial no pierde los
-- 2 kg. Un traslado que cuadra por decreto no serviria de nada.

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table flow_transfer_short as
select * from public.request_stock_transfer(
  (select id from flow_point), (select id from flow_destination),
  'Alimentos', 'kilogramo', 5,
  'Segundo envio del ejercicio para probar la conciliacion con faltante.',
  'flow-transfer-002'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(
  public.decide_stock_transfer((select request_id from flow_transfer_short),'authorize',5,'Autorizacion del segundo envio')::text,
  'authorized', '21 el administrador autoriza los 5 kg restantes');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table flow_shipment_short as
select public.create_shipment(
  null, (select request_id from flow_transfer_short), (select id from flow_point), (select id from flow_destination),
  null, '{"mode":"institucional","contact_name":"Conductor Sintetico","contact_document":"CC-00000002","contact_phone":"6040000001","vehicle":"Camioneta","plate":"xyz789","responsible":"Marta Bodega"}'::jsonb,
  'flow-shipment-002'
) as id;
select is(
  public.dispatch_shipment((select id from flow_shipment_short))::text,
  'dispatched', '22 sale el segundo despacho');
select is(
  public.advance_shipment((select id from flow_shipment_short), 'arrived')::text,
  'arrived', '22 el segundo despacho llega al destino');

create temporary table flow_delivery_short as
select public.register_delivery((select id from flow_shipment_short), 3, 0, 2, 'flow-delivery-002') as id;
select is(
  (select outcome from public.shipment_reconciliation((select id from flow_shipment_short))),
  'NOVEDAD', '23 recibir de menos se concilia como NOVEDAD, no como conforme');
select is(
  (select quantity_missing from public.shipment_reconciliation((select id from flow_shipment_short))),
  2::numeric, '23 el faltante queda cuantificado en 2 kg');
select is(
  (select quantity_dispatched from public.shipment_reconciliation((select id from flow_shipment_short))),
  5::numeric, '23 lo despachado sigue siendo 5: el historial no pierde los 2 kg');
select is(
  (select status::text from public.shipments where id = (select id from flow_shipment_short)),
  'incident', '23 el despacho queda marcado como novedad');
select is(
  (select sum(lot_position.quantity_available)
   from public.inventory_lot_positions as lot_position
   where lot_position.location_id = (select id from flow_destination)),
  18::numeric, '24 el destino crece solo con lo confirmado: 15 + 3, nunca 15 + 5');
select is(
  (select quantity_in_transit from public.inventory_lot_positions where lot_id = (select id from flow_lot)),
  0::numeric, '24 nada queda colgado en movimiento tras conciliar la novedad');
select is(
  (select quantity_delivered + quantity_damaged + quantity_missing
   from public.deliveries where id = (select id from flow_delivery_short)),
  5::numeric, '24 lo recibido, lo danado y el faltante siguen sumando lo que salio');

select * from finish();
rollback;
