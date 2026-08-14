begin;
select plan(27);

-- Escenario C: privacidad y fraude se bloquean antes de persistir.
select ok(public.contains_sensitive_content('Escríbeme al 300 123 4567'), 'C bloquea teléfono');
select ok(public.contains_sensitive_content('Consignar a cuenta corriente'), 'C bloquea instrucciones monetarias');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok($$select * from public.submit_donation_intake('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-f-restricted-001','Persona sintética','{}','anonymous','',false,'comprometida','[{"category":"Salud","description":"Medicamento","quantity":1,"unit":"unidad","condition":"abierto"}]',null)$$,'22023','No se aceptan artículos abiertos o vencidos','F rechaza artículo abierto antes del traslado');

-- Escenario H/A: aliado autenticado registra dos líneas e idempotencia conserva un ingreso.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table test_intake as
select * from public.submit_donation_intake(
  '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-h-intake-001',
  'Persona sintética','{"email":"private@example.invalid"}','anonymous','',false,'comprometida',
  '[{"category":"Agua","description":"Botella sellada","quantity":100,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"},{"category":"Higiene","description":"Kit familiar","quantity":10,"unit":"kit","condition":"nuevo","storage_requirement":"seco"}]'::jsonb,null
);
select is((select count(*)::integer from public.donation_intake_items where intake_id=(select intake_id from test_intake)),2,'H crea dos líneas bajo un ingreso');
select is((select count(*)::integer from public.public_donation_projections p join public.donations d on d.id=p.donation_id where d.intake_id=(select intake_id from test_intake)),0,'H no publica el intake');
select is((select was_duplicate from public.submit_donation_intake('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','e2e-h-intake-001','Persona sintética','{}','anonymous','',false,'comprometida','[]',null)),true,'H reintento idempotente');

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

create temporary table test_shipment as select public.create_shipment((select id from test_allocation),'Medellín · zona aproximada','Transportador sintético','e2e-a-shipment-001') as id;
select ok((select id from test_shipment) is not null,'A crea despacho auditable');
select is((select count(*)::integer from public.public_logistics_projections where source_type='dispatch' and source_id=(select id from test_shipment) and published),1,'A proyecta el despacho en el mapa con origen y destino aproximados');
create temporary table test_delivery as select public.register_delivery((select id from test_shipment),89,1,'e2e-a-delivery-001') as id;
select ok((select id from test_delivery) is not null,'A registra 89 entregadas y 1 dañada');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(public.validate_delivery((select id from test_delivery),'Confirmación sintética') is not null,'A valida la entrega por rol separado');
select is((select quantity_covered from public.need_items where id='61000000-0000-0000-0000-000000000001'),178::numeric,'A cobertura aumenta exactamente en 89');
select is((select count(*)::integer from public.public_donation_projections p join public.donations d on d.id=p.donation_id where d.intake_id=(select intake_id from test_intake) and p.published),1,'H solo publica después de entrega validada');

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
