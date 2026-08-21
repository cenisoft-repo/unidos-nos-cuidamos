begin;
select plan(38);

-- Escenario C: privacidad y fraude se bloquean antes de persistir.
select ok(public.contains_sensitive_content('Escríbeme al 300 123 4567'), 'C bloquea teléfono');
select ok(public.contains_sensitive_content('Consignar a cuenta corriente'), 'C bloquea instrucciones monetarias');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok($$select * from public.submit_donation_intake('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-f-restricted-001','Persona sintética','{"email":"private@example.invalid"}','anonymous','',false,'comprometida','[{"category":"Salud","description":"Medicamento sintético","quantity":1,"unit":"unidad","condition":"abierto","storage_requirement":"ambiente"}]',null,'70000000-0000-0000-0000-000000000002','{}')$$,'22023','No se aceptan artículos abiertos o vencidos','F rechaza artículo abierto antes del traslado');

-- Escenario H/A: aliado autenticado registra dos líneas e idempotencia conserva un ingreso.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table test_intake as
select * from public.submit_donation_intake(
  '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-h-intake-001',
  'Persona sintética','{"email":"private@example.invalid"}','anonymous','',false,'comprometida',
  '[{"category":"Agua","description":"Botella sellada","quantity":100,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"},{"category":"Higiene","description":"Kit familiar","quantity":10,"unit":"kit","condition":"nuevo","storage_requirement":"seco"}]'::jsonb,null,
  '70000000-0000-0000-0000-000000000002','{}'::jsonb
);
select is((select count(*)::integer from public.donation_intake_items where intake_id=(select intake_id from test_intake)),2,'H crea dos líneas bajo un ingreso');
select is((select count(*)::integer from public.public_donation_projections p join public.donations d on d.id=p.donation_id where d.intake_id=(select intake_id from test_intake)),0,'H no publica el intake');
select is((select was_duplicate from public.submit_donation_intake('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-h-intake-001','Persona sintética','{"email":"private@example.invalid"}','anonymous','',false,'comprometida','[{"category":"Agua","description":"Botella sellada","quantity":100,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"},{"category":"Higiene","description":"Kit familiar","quantity":10,"unit":"kit","condition":"nuevo","storage_requirement":"seco"}]'::jsonb,null,'70000000-0000-0000-0000-000000000002','{}'::jsonb)),true,'H reintento idempotente');

-- Verificador aprueba; bodega recibe 95 y rechaza 5.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(public.review_donation_intake((select intake_id from test_intake),'approve','Soporte sintético válido') is not null,'A verificador crea promesa operacional');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
create temporary table test_lot as select public.receive_donation(
  (select di.id from public.donation_items di join public.donations d on d.id=di.donation_id where d.intake_id=(select intake_id from test_intake) and di.category='Agua'),
  '70000000-0000-0000-0000-000000000002',95,5,'sellado','e2e-a-receipt-001'
) as id;
select ok((select id from test_lot) is not null,'A recepción crea lote');
select is(public.receive_donation((select di.id from public.donation_items di join public.donations d on d.id=di.donation_id where d.intake_id=(select intake_id from test_intake) and di.category='Agua'),'70000000-0000-0000-0000-000000000002',95,5,'sellado','e2e-a-receipt-001'),(select id from test_lot),'D sincronización repetida conserva un lote');
select is((select count(*)::integer from public.stock_movements where idempotency_key='e2e-a-receipt-001'),1,'D solo crea un movimiento de recepción');

create temporary table test_allocation as select public.allocate_stock((select id from test_lot),'61000000-0000-0000-0000-000000000001',90,'e2e-a-allocation-001') as id;
select ok((select id from test_allocation) is not null,'A reserva 90 unidades');
select throws_ok($$select public.allocate_stock((select id from test_lot),'61000000-0000-0000-0000-000000000001',50,'e2e-g-allocation-over')$$,'22023','Existencia insuficiente','G evita sobreasignación/stock negativo');

select throws_ok(
  $$select public.create_shipment((select id from test_allocation),null,'70000000-0000-0000-0000-000000000001',null,'Medellín · zona aproximada','{"mode":"transportadora","company":"Transportes Sintéticos SAS","contact_name":"Conductor Sintético","contact_document":"CC-00000001","contact_phone":"6040000000","vehicle":"Camión sencillo","plate":"ABC123","responsible":"Marta Bodega"}'::jsonb,'e2e-a-shipment-cross')$$,
  '42501',
  'El punto de origen pertenece a otra organización o evento',
  'A no puede despachar desde un punto de otra organización'
);
create temporary table test_shipment as select public.create_shipment((select id from test_allocation),null,'70000000-0000-0000-0000-000000000003',null,'Medellín · zona aproximada','{"mode":"transportadora","company":"Transportes Sintéticos SAS","contact_name":"Conductor Sintético","contact_document":"CC-00000001","contact_phone":"6040000000","vehicle":"Camión sencillo","plate":"ABC123","responsible":"Marta Bodega"}'::jsonb,'e2e-a-shipment-001') as id;
select ok((select id from test_shipment) is not null,'A crea despacho auditable desde una base que solo despacha');
select is((select origin_location_id from public.shipments where id=(select id from test_shipment)),'70000000-0000-0000-0000-000000000003'::uuid,'A conserva desde qué punto salió el despacho');
select is(public.dispatch_shipment((select id from test_shipment))::text,'dispatched','A el despacho sale solo cuando el transporte está completo');
select is((select count(*)::integer from public.public_logistics_projections where source_type='dispatch' and source_id=(select id from test_shipment) and published),1,'A proyecta el despacho en el mapa solo después de la salida');
create temporary table test_delivery as select public.register_delivery(
  (select id from test_shipment),
  (select jsonb_agg(jsonb_build_object('shipment_item_id', item.id, 'delivered', 89, 'damaged', 1, 'missing', 0))
   from public.shipment_items as item where item.shipment_id = (select id from test_shipment)),
  'e2e-a-delivery-001') as id;
select ok((select id from test_delivery) is not null,'A registra 89 entregadas y 1 dañada');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(public.validate_delivery((select id from test_delivery),'Confirmación sintética') is not null,'A valida la entrega por rol separado');
select is((select quantity_covered from public.need_items where id='61000000-0000-0000-0000-000000000001'),178::numeric,'A cobertura aumenta exactamente en 89');
select is((select count(*)::integer from public.public_donation_projections p join public.donations d on d.id=p.donation_id where d.intake_id=(select intake_id from test_intake) and p.published),1,'H solo publica después de entrega validada');
-- G-023: el mismo QR APO-* no se congela en «aporte reportado»; muestra el recorrido
-- operacional (recepción/despacho/entrega) de la donación DON-* vinculada.
select ok(
  (select count(*) from public.track_public_journey((select tracking_code from test_intake))
   where stage_key in ('stock_received','shipment_dispatched','delivery_registered','delivery_validated')) >= 1,
  'El mismo QR del APO muestra el recorrido operacional de su donación vinculada'
);

-- Escenario F: un hold impide asignar o despachar.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
select is(public.place_lot_control((select id from test_lot),'hold','Ruptura de temperatura simulada'),'hold'::public.lot_status,'F pone lote en hold');
select throws_ok($$select public.allocate_stock((select id from test_lot),'61000000-0000-0000-0000-000000000001',1,'e2e-f-blocked')$$,'22023','El lote está bloqueado o no disponible','F bloquea asignación de lote retenido');

-- Escenario B: pago idempotente, gasto segregado y saldo exacto.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
create temporary table test_credit as select public.reconcile_sandbox_payment('80000000-0000-0000-0000-000000000001',1000000,'provider-e2e-b-001','e2e-b-credit-001') as id;
select is(public.reconcile_sandbox_payment('80000000-0000-0000-0000-000000000001',1000000,'provider-e2e-b-001','e2e-b-credit-001'),(select id from test_credit),'B webhook repetido no duplica ingreso');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}',true);
create temporary table test_expense as select public.request_expense('80000000-0000-0000-0000-000000000001',300000,'Compra sintética de agua') as id;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
select is(public.approve_expense((select id from test_expense),'approved','Soporte revisado'),'approved'::public.expense_status,'B actor diferente aprueba gasto');
select ok(public.pay_expense((select id from test_expense),'e2e-b-payment-001') is not null,'B paga gasto aprobado');
select is((select sum(case when transaction_type='credit' then amount when transaction_type='debit' then -amount else 0 end) from public.financial_transactions where idempotency_key in ('e2e-b-credit-001','e2e-b-payment-001')),700000::numeric,'B saldo concilia en COP 700.000');

-- Escenario B2: un aporte económico aprobado entra a tesorería y solo entonces se publica.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table test_money_intake as
select * from public.submit_donation_intake(
  '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','money','e2e-b-money-intake-001',
  'Empresa donante sintética','{"email":"finance@example.invalid"}','organization','',false,'comprometida','[]'::jsonb,250000,null,
  '{"donor_type":"empresa","economic_sector":"Tecnología","specific_destination":false,"internal_contact":{}}'::jsonb
);
select ok((select intake_id from test_money_intake) is not null,'B2 registra una declaración monetaria privada');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table test_money_donation as
select public.review_donation_intake((select intake_id from test_money_intake),'approve','Soporte declarado listo para tesorería') as id;
select ok((select id from test_money_donation) is not null,'B2 aprobación crea la promesa monetaria operacional');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
select is((select count(*)::integer from public.treasury_pending_money_donations('10000000-0000-0000-0000-000000000001') where donation_id=(select id from test_money_donation)),1,'B2 tesorería ve la promesa sin datos privados del donante');
create temporary table test_money_transaction as
select * from public.reconcile_money_donation((select id from test_money_donation),'80000000-0000-0000-0000-000000000001','provider-money-e2e-001','e2e-b-money-reconcile-001');
select ok((select transaction_id from test_money_transaction) is not null,'B2 conciliación crea el movimiento financiero vinculado');
select is((select amount from public.financial_transactions where donation_id=(select id from test_money_donation)),250000::numeric,'B2 usa el monto aprobado y no un monto digitado por tesorería');
select is((select reconciled_amount from public.public_donation_projections where donation_id=(select id from test_money_donation) and published),250000::numeric,'B2 publica el monto únicamente después de conciliarlo');
select is((select was_duplicate from public.reconcile_money_donation((select id from test_money_donation),'80000000-0000-0000-0000-000000000001','provider-money-e2e-001','e2e-b-money-reconcile-001')),true,'B2 reintento de conciliación devuelve el mismo resultado sin duplicar');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table test_self_expense as select public.request_expense('80000000-0000-0000-0000-000000000001',1000,'Gasto de autoverificación sintético') as id;
select throws_ok($$select public.approve_expense((select id from test_self_expense),'approved','Intento propio')$$,'42501','No puedes aprobar tu propia solicitud','B bloquea autoaprobación aun para administración');

-- Escenario E: migración conserva conteos, cuarentena y rollback.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table test_batch as select public.import_legacy_fixture('10000000-0000-0000-0000-000000000001','fixture-e2e','sha256-synthetic','[{"external_id":"1","text":"registro válido","location":"Pereira"},{"external_id":"2","text":"llamar al 3001234567","location":"Pereira"},{"external_id":"3","text":"duplicado","location":"Pereira","is_duplicate":true},{"external_id":"4","text":"vencido","location":"","is_expired":true},{"external_id":"5","text":"desmentido","location":"Pereira","is_disproved":true}]'::jsonb) as id;
select is((select concat_ws(',',approved_count,rejected_count,duplicate_count,quarantine_count) from public.migration_batches where id=(select id from test_batch)),'1,1,1,2','E concilia conteos de migración');
select is(public.rollback_migration_batch((select id from test_batch)),'rolled_back','E rollback queda registrado');

select * from finish();
rollback;
