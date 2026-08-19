-- G-028 · corrección de un ingreso observado.
-- Cubre el nodo «Observación → corregir sin borrar historia → volver a
-- verificación» del diagrama de recorrido, que no tenía implementación ni
-- cobertura antes de esta migración.
begin;
select plan(22);

-- ---------------------------------------------------------------- contrato --
select has_table('public', 'intake_amendments', 'Existe el historial de correcciones del aliado');
select has_function(
  'public', 'amend_donation_intake', array['uuid','text','integer','jsonb','numeric'],
  'Existe RPC de corrección con versión esperada'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.intake_amendments'::regclass),
  'El historial de correcciones tiene RLS habilitada'
);
-- Append-only: ninguna política de escritura para el rol autenticado.
select is(
  (select count(*)::integer from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'intake_amendments'
     and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  'El historial de correcciones no admite escritura directa'
);

-- ------------------------------------------------- montaje de un escenario --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table amend_intake as
select * from public.submit_donation_intake(
  '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','g028-amend-001',
  'Persona sintética','{"email":"private@example.invalid"}','anonymous','',false,'comprometida',
  '[{"category":"Agua","description":"Botella sellada","quantity":100,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
  null,'70000000-0000-0000-0000-000000000002','{}'::jsonb
);

-- Un ingreso recién creado todavía no admite corrección.
select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Intento antes de la observación',1,'[]'::jsonb)$$,
  '22023', 'Solo un ingreso con observaciones admite corrección',
  'Sin observación previa la corrección se rechaza'
);

-- El verificador observa: aquí empezaba el callejón sin salida.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(
  public.review_donation_intake((select intake_id from amend_intake),'observe','La cantidad no coincide con la remisión') is null,
  'El verificador deja el ingreso con observaciones'
);
select is(
  (select status::text from public.donation_intakes where id = (select intake_id from amend_intake)),
  'observed', 'El ingreso queda en observed'
);

-- ------------------------------------------------------------ aislamiento --
-- Mismo evento y misma organización, pero rol equivocado: verificar no es corregir.
select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'El verificador intenta corregir',1,'[]'::jsonb)$$,
  '42501', 'No puedes corregir este ingreso',
  'Quien verifica no puede corregir en nombre del aliado'
);

-- Rol correcto pero en otra organización: no debe alcanzar el ingreso ajeno.
insert into public.memberships(user_id,organization_id,event_id,role)
values ('00000000-0000-0000-0000-000000000104','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','partner_reporter');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}',true);
select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Aliado de otra organización',1,'[]'::jsonb)$$,
  '42501', 'No puedes corregir este ingreso',
  'Un aliado de otra organización no puede corregir el ingreso'
);

-- --------------------------------------------------------- validación de datos --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);

select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Escríbeme al 300 123 4567 para coordinar',1,'[]'::jsonb)$$,
  '22023', 'La respuesta no puede incluir contactos, cuentas ni datos sensibles',
  'La respuesta del aliado pasa por el mismo filtro de contenido sensible'
);

select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Corto',1,'[]'::jsonb)$$,
  '22023', 'Explica la corrección en al menos 10 caracteres',
  'La corrección exige una explicación con sustancia'
);

select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Versión desactualizada a propósito',99,'[]'::jsonb)$$,
  '40001', 'El ingreso cambió desde que lo abriste; vuelve a cargarlo',
  'La versión esperada evita pisar una corrección concurrente'
);

select throws_ok(
  $$select public.amend_donation_intake(
      (select intake_id from amend_intake),'Cantidad en cero no es una corrección',1,
      jsonb_build_array(jsonb_build_object(
        'item_id',(select id from public.donation_intake_items where intake_id=(select intake_id from amend_intake) limit 1),
        'quantity',0))
    )$$,
  '22023', 'La cantidad corregida debe ser mayor que cero',
  'Una cantidad no positiva se rechaza'
);

select throws_ok(
  $$select public.amend_donation_intake(
      (select intake_id from amend_intake),'Línea que no pertenece a este ingreso',1,
      jsonb_build_array(jsonb_build_object('item_id','99999999-9999-9999-9999-999999999999','quantity',5))
    )$$,
  '22023', 'Una de las líneas corregidas no pertenece a este ingreso',
  'No se puede corregir la línea de otro ingreso'
);

select throws_ok(
  $$select public.amend_donation_intake((select intake_id from amend_intake),'Monto en un aporte en especie',1,'[]'::jsonb,500000)$$,
  '22023', 'Solo un aporte económico tiene monto declarado',
  'El monto declarado no aplica a un aporte en especie'
);

-- ------------------------------------------------------- corrección válida --
select is(
  public.amend_donation_intake(
    (select intake_id from amend_intake),
    'Cantidad ajustada contra la remisión física 0012',
    1,
    jsonb_build_array(jsonb_build_object(
      'item_id',(select id from public.donation_intake_items where intake_id=(select intake_id from amend_intake) limit 1),
      'quantity',80))
  ),
  2,
  'La corrección devuelve la versión nueva'
);

select is(
  (select quantity from public.donation_intake_items where intake_id=(select intake_id from amend_intake) limit 1),
  80::numeric(14,3),
  'La cantidad queda corregida'
);

select is(
  (select status::text from public.donation_intakes where id=(select intake_id from amend_intake)),
  'pending_verification',
  'El ingreso vuelve a la cola de verificación'
);

-- La historia no se sobrescribe: la enmienda guarda el antes y el después.
select is(
  (select changes->0->>'before' from public.intake_amendments
   where intake_id=(select intake_id from amend_intake)),
  '100.000',
  'La enmienda conserva la cantidad anterior'
);
select is(
  (select changes->0->>'after' from public.intake_amendments
   where intake_id=(select intake_id from amend_intake)),
  '80.000',
  'La enmienda conserva la cantidad corregida'
);

-- El ciclo se cierra: quien verifica decide sobre la versión nueva.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select ok(
  public.review_donation_intake((select intake_id from amend_intake),'approve','Corrección conforme a la remisión') is not null,
  'El verificador aprueba la versión corregida y crea la promesa operacional'
);

-- La creación del ingreso y su corrección conviven en el historial: la
-- auditoría suma eventos, no los reemplaza.
select cmp_ok(
  (select count(*)::integer from public.audit_events
   where entity_table = 'donation_intakes'
     and entity_id = (select intake_id from amend_intake)),
  '>=', 2,
  'La corrección suma auditoría en vez de reemplazar la anterior'
);

select * from finish();
rollback;
