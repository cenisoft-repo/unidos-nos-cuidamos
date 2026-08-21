-- Recaudo por pasarela para aportes en dinero, de extremo a extremo.
--
-- Lo que se comprueba es la regla que sostiene todo lo demás: **cobrar no es conciliar**.
-- El proveedor confirma y no pasa nada en el libro; el saldo se mueve cuando una persona de
-- tesorería casa ese cobro con el extracto. Entre medias, ni un importe distinto ni un
-- secreto equivocado ni un aporte sin aprobar pueden colar un peso.

begin;
select plan(28);

-- ---------------------------------------------------------------- el canal sembrado

select is(
  (select count(*)::integer from public.payment_providers
   where provider_key = 'practica' and active and sandbox),
  1, '01 el sandbox trae un canal de práctica activo, registrado por la RPC auditada');
select is(
  (select activation_reason is not null and activated_by is not null from public.payment_providers where provider_key = 'practica'),
  true, '01 la activación deja escrito quién y por qué');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select throws_ok(
  $$select public.set_payment_provider(
      (select id from public.payment_providers where provider_key = 'practica'),
      '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',
      '80000000-0000-0000-0000-000000000001','practica','Pasarela de práctica', true, true,
      '{"api_key":"sk_live_no_deberia_entrar"}'::jsonb,
      'secreto-de-practica-solo-para-el-sandbox-local','Intento con un secreto en la configuración')$$,
  '22023',
  'La configuración publicable no puede contener «api_key»: los secretos viven fuera de la base',
  '02 un secreto en la configuración publicable se rechaza por su nombre'
);
select throws_ok(
  $$select public.set_payment_provider(
      null, '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',
      '80000000-0000-0000-0000-000000000001','real_de_verdad','Pasarela real', false, true,
      '{}'::jsonb, 'secreto-suficientemente-largo-para-pasar-0001','Intento de abrir recaudo real')$$,
  '42501',
  'Activar un canal de recaudo real exige autoridad global y queda registrado',
  '02 abrir un canal que mueve dinero real exige autoridad global'
);

-- ---------------------------------------------------------------- el aliado declara y paga

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table pago_aporte as
select * from public.submit_donation_intake_v2(
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'money', 'pago-test-001', 'Donante Sintético',
  '{"email":"donante.pago@example.invalid"}'::jsonb,
  'anonymous', '', false, 'comprometida',
  '[]'::jsonb, 250000, null, '{}'::jsonb,
  public.current_donation_catalog_versions(), 'apoyo_economico_recursos', null
);

create temporary table pago_canal as
select * from public.payment_options_for_intake((select intake_id from pago_aporte));
select is((select count(*)::integer from pago_canal), 1, '03 el aporte ve el canal activo del evento');
select is((select amount from pago_canal), 250000::numeric, '03 el cobro es por lo declarado, no por lo que escriba el navegador');
select is((select already_paid from pago_canal), false, '03 y todavía no está pagado');

create temporary table pago_intencion as
select * from public.start_payment_intent(
  (select intake_id from pago_aporte), (select provider_id from pago_canal), 'pago-test-intent-001');
select is((select was_duplicate from pago_intencion), false, '04 se abre la intención de cobro');
select is(
  (select was_duplicate from public.start_payment_intent(
    (select intake_id from pago_aporte), (select provider_id from pago_canal), 'pago-test-intent-001')),
  true, '04 repetir con la misma clave no abre un segundo cobro');

-- Carlos Aprobaciones solo pertenece a la organización que recauda, no a la que aportó.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
select throws_ok(
  format($$select * from public.start_payment_intent(%L, %L, 'pago-test-ajeno')$$,
    (select intake_id from pago_aporte), (select provider_id from pago_canal)),
  '42501',
  'No puedes pagar un aporte de otra organización',
  '04 nadie abre el cobro de un aporte que no es de su organización'
);

-- ---------------------------------------------------------------- la vuelta del proveedor

select set_config('request.jwt.claims','{"role":"anon"}',true);
select throws_ok(
  format($$select * from public.confirm_payment_intent(%L,'practica','secreto-equivocado-pero-bien-largo','confirmed','PROV-X',250000,null)$$,
    (select reference from pago_intencion)),
  '42501',
  'Pago no reconocido',
  '05 con el secreto equivocado no se confirma nada, y la respuesta no dice por qué'
);

select is(
  (select intent_status from public.confirm_payment_intent(
    (select reference from pago_intencion), 'practica', 'secreto-de-practica-solo-para-el-sandbox-local',
    'confirmed', 'PROV-DISTINTO', 100000, null)),
  'failed', '05 un importe distinto al pedido deja el cobro fallido');
select is(
  (select count(*)::integer from public.financial_transactions where public_reference like 'PAG-%'),
  0, '05 y no escribe ni un asiento en el libro');

-- La intención quedó fallida; el proveedor reintenta con el importe correcto.
update public.payment_intents set status = 'pending', failure_reason = null
where reference = (select reference from pago_intencion);

create temporary table pago_confirmado as
select * from public.confirm_payment_intent(
  (select reference from pago_intencion), 'practica', 'secreto-de-practica-solo-para-el-sandbox-local',
  'confirmed', 'PRACTICA-0001', 250000, null);
select is((select intent_status from pago_confirmado), 'confirmed', '06 con el secreto y el importe correctos, el cobro queda confirmado');
select is((select was_duplicate from pago_confirmado), false, '06 y es la primera vez');
select is(
  (select was_duplicate from public.confirm_payment_intent(
    (select reference from pago_intencion), 'practica', 'secreto-de-practica-solo-para-el-sandbox-local',
    'confirmed', 'PRACTICA-0001', 250000, null)),
  true, '06 el reintento del proveedor es idempotente');
select is(
  (select count(*)::integer from public.financial_transactions as movement
   join public.donations as donation on donation.id = movement.donation_id
   where donation.intake_id = (select intake_id from pago_aporte)),
  0, '06 confirmar NO escribe en el libro: cobrar no es conciliar');

-- ---------------------------------------------------------------- tesorería

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
select is(
  (select balance from public.treasury_balance('10000000-0000-0000-0000-000000000001')),
  0::numeric, '07 el saldo no se mueve con un cobro confirmado');
select is(
  (select donation_ready from public.treasury_provider_payments('10000000-0000-0000-0000-000000000001')
   where payment_reference = (select reference from pago_intencion)),
  false, '07 la cola lo muestra, y avisa de que verificación aún no aprobó el aporte');
select throws_ok(
  format($$select * from public.reconcile_provider_payment(%L,'EXTRACTO-0001','pago-test-conc-001')$$,
    (select reference from pago_intencion)),
  '22023',
  'El aporte todavía no fue aprobado por verificación: no hay nada que conciliar aún',
  '07 conciliar antes de que verificación apruebe se rechaza'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(
  public.review_donation_intake((select intake_id from pago_aporte), 'approve', 'Aprobación del ejercicio de pagos') is not null,
  '08 verificación aprueba el aporte y nace la donación');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  format($$select * from public.reconcile_provider_payment(%L,'EXTRACTO-0001','pago-test-conc-aliado')$$,
    (select reference from pago_intencion)),
  '42501',
  'No puedes conciliar este ingreso',
  '08 quien aporta no concilia su propio cobro'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
create temporary table pago_conciliado as
select * from public.reconcile_provider_payment(
  (select reference from pago_intencion), 'EXTRACTO-0001', 'pago-test-conc-001');
select is((select was_duplicate from pago_conciliado), false, '09 tesorería concilia el cobro contra el extracto');
select is(
  (select was_duplicate from public.reconcile_provider_payment(
    (select reference from pago_intencion), 'EXTRACTO-0001', 'pago-test-conc-001')),
  true, '09 y repetirlo no duplica el ingreso');
select is(
  (select provider from public.financial_transactions where id = (select transaction_id from pago_conciliado)),
  'practica', '09 el asiento conserva por qué canal entró el dinero');
select is(
  (select status from public.financial_transactions where id = (select transaction_id from pago_conciliado)),
  'reconciled', '09 el asiento nace conciliado: el libro no admite estados intermedios');
select is(
  (select balance from public.treasury_balance('10000000-0000-0000-0000-000000000001')),
  250000::numeric, '10 ahora sí el saldo refleja el ingreso');
select is(
  (select projection.reconciled_amount
   from public.public_donation_projections as projection
   join public.donations as donation on donation.id = projection.donation_id
   where donation.intake_id = (select intake_id from pago_aporte)),
  250000::numeric, '10 el aporte queda publicado con el importe conciliado');

select * from finish();
rollback;
