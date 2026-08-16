begin;
select plan(60);

select is((
  select count(*)::integer
  from pg_catalog.pg_constraint as foreign_key
  join pg_catalog.pg_class as target_table on target_table.oid = foreign_key.conrelid
  join pg_catalog.pg_namespace as table_schema on table_schema.oid = target_table.relnamespace
  join lateral unnest(foreign_key.conkey) as key_column(attnum) on true
  where foreign_key.contype = 'f'
    and table_schema.nspname = 'public'
    and not exists (
      select 1
      from pg_catalog.pg_index as existing_index
      where existing_index.indrelid = foreign_key.conrelid
        and key_column.attnum = any(existing_index.indkey)
    )
), 0, 'Toda clave foránea pública tiene un índice de soporte');

select has_table('public', 'need_cases', 'Existe el modelo operacional de necesidades');
select has_table('public', 'audit_events', 'Existe auditoría append-only');
select has_function('public', 'submit_need_report', array['uuid','text','text','text','numeric','text','text','jsonb'], 'Existe RPC segura de reporte');
select has_function('public', 'submit_donation_intake', array['uuid','uuid','donation_kind','text','text','jsonb','text','text','boolean','text','jsonb','numeric'], 'Existe RPC idempotente de intake');
select has_extension('postgis', 'PostGIS está habilitado para consultas territoriales');
select has_column('public', 'public_need_projections', 'approximate_location', 'La proyección pública conserva un punto geoespacial aproximado');
select has_function('public', 'public_need_map', array['uuid','double precision','double precision','double precision','double precision'], 'Existe RPC pública con filtro espacial');
select ok(exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='public_need_projections'),'La proyección pública está habilitada para Realtime');
select has_column('public', 'donation_intakes', 'preferred_location_id', 'El aporte puede declarar un centro preferido');
select has_function('public', 'public_collection_centers', array['uuid'], 'Existe proyección segura de centros de acopio');
select has_function('public', 'submit_donation_intake', array['uuid','uuid','donation_kind','text','text','jsonb','text','text','boolean','text','jsonb','numeric','uuid'], 'Existe intake guiado con centro preferido');
select has_column('public', 'donation_intakes', 'donor_type', 'El intake conserva el tipo de donante de forma operacional');
select has_column('public', 'donation_intakes', 'economic_sector', 'El intake conserva el sector económico declarado');
select has_column('public', 'donation_intakes', 'specific_destination', 'El intake distingue una destinación específica');
select has_column('public', 'donation_intakes', 'estimated_beneficiaries', 'La estimación de beneficiarios queda separada del impacto público');
select has_column('public', 'donation_intakes', 'internal_contact_private', 'El contacto interno permanece en un campo privado');
select has_column('public', 'donation_intakes', 'observations_private', 'Las observaciones operativas permanecen privadas');
select has_column('public', 'donation_intake_items', 'declared_estimated_value_cop', 'Cada artículo puede conservar un valor declarado no conciliado');
select has_function('public', 'submit_donation_intake', array['uuid','uuid','donation_kind','text','text','jsonb','text','text','boolean','text','jsonb','numeric','uuid','jsonb'], 'Existe intake guiado con contexto de reporte privado');
select has_column('public', 'donation_intakes', 'request_fingerprint', 'El intake conserva una huella canónica para idempotencia segura');
select has_column('public', 'public_donation_projections', 'donation_item_id', 'La proyección pública distingue cada artículo verificado');
select has_column('public', 'financial_transactions', 'donation_id', 'La conciliación financiera conserva el aporte monetario fuente');
select has_function('public', 'treasury_pending_money_donations', array['uuid'], 'Tesorería consulta una cola monetaria sin PII');
select has_function('public', 'reconcile_money_donation', array['uuid','uuid','text','text'], 'Existe conciliación monetaria específica e idempotente');
select has_function('public', 'submit_need_report', array['uuid','text','text','text','numeric','text','text','jsonb','text'], 'El reporte ciudadano incluye trampa anti-bot validada en servidor');
select ok(not has_function_privilege('anon','public.submit_need_report(uuid,text,text,text,numeric,text,text,jsonb)','EXECUTE'), 'El visitante no ejecuta la firma de reporte sin anti-bot');
select ok(has_function_privilege('anon','public.submit_need_report(uuid,text,text,text,numeric,text,text,jsonb,text)','EXECUTE'), 'El visitante solo ejecuta la firma protegida del reporte');
select has_table('public', 'anonymous_rate_limits', 'Existe contador antiabuso sin IP en claro');
select ok(not has_table_privilege('anon','public.anonymous_rate_limits','SELECT'), 'El visitante no puede leer contadores antiabuso');
select ok(not has_table_privilege('anon','public.anonymous_rate_limits','INSERT'), 'El visitante no puede alterar contadores antiabuso');
select set_config('request.headers','{"x-forwarded-for":"198.51.100.42"}',true);
select lives_ok(
  $statement$do $rate_test$
  begin
    for attempt in 1..5 loop
      perform * from public.submit_need_report(
        '10000000-0000-0000-0000-000000000001',
        'Agua',
        format('Reporte sintético de control antiabuso número %s.', attempt),
        'Zona amplia de prueba',
        1,
        'unidad',
        null,
        '{}'::jsonb,
        ''
      );
    end loop;
  end
  $rate_test$;$statement$,
  'Los primeros cinco reportes válidos de la ventana son aceptados'
);
select is(
  (
    select request_count
    from public.anonymous_rate_limits
    where action='submit_need_report'
      and bucket_hash=encode(
        extensions.digest(
          '198.51.100.42|10000000-0000-0000-0000-000000000001',
          'sha256'
        ),
        'hex'
      )
      and window_started_at=date_bin(
        interval '10 minutes',
        clock_timestamp(),
        timestamptz '2000-01-01 00:00:00+00'
      )
  ),
  5,
  'El contador registra la cuota exacta de la ventana'
);
select ok(
  not exists(select 1 from public.anonymous_rate_limits where bucket_hash like '%198.51.100.42%'),
  'La fuente de red no se conserva en claro'
);
select throws_ok(
  $$select * from public.submit_need_report(
    '10000000-0000-0000-0000-000000000001',
    'Agua',
    'Reporte sintético que debe superar la cuota temporal.',
    'Zona amplia de prueba',
    1,
    'unidad',
    null,
    '{}'::jsonb,
    ''
  )$$,
  'P0001',
  'Se alcanzó el límite temporal de reportes. Intenta de nuevo en unos minutos',
  'El sexto reporte de la misma ventana queda bloqueado'
);
select throws_ok(
  $$select * from public.submit_need_report(
    '10000000-0000-0000-0000-000000000001',
    'Agua',
    'Reporte sintético atrapado por el campo invisible.',
    'Zona amplia de prueba',
    1,
    'unidad',
    null,
    '{}'::jsonb,
    'https://bot.invalid'
  )$$,
  '22023',
  'No fue posible procesar el reporte',
  'La trampa invisible continúa bloqueando automatizaciones simples'
);
select has_table('public', 'public_logistics_projections', 'Existe la proyección cartográfica segura de logística');
select has_function('public', 'public_logistics_map', array['uuid'], 'Existe RPC pública para centros y despachos aproximados');
select is((select count(*)::integer from public.public_logistics_map('10000000-0000-0000-0000-000000000001') where source_type='collection_center'), 2, 'El mapa logístico publica dos centros sintéticos activos');
select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='public_logistics_projections' and column_name='exact_address_private'), 'La proyección logística no contiene dirección exacta');
select ok(exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='public_logistics_projections'), 'La logística pública está habilitada para Realtime');
select ok(not has_table_privilege('anon','public.public_logistics_projections','INSERT'), 'El visitante no puede escribir la proyección logística');
select ok(not has_function_privilege('anon','public.allocate_stock(uuid,uuid,numeric,text)','EXECUTE'), 'El visitante no puede ejecutar mutaciones operativas SECURITY DEFINER');
select ok(not has_function_privilege('anon','public.submit_donation_intake(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb)','EXECUTE'), 'El visitante no puede registrar datos privados de un aporte sin membresía');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
create temporary table test_contextual_intake as
select * from public.submit_donation_intake(
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'in_kind',
  'test-contextual-intake-001',
  'Persona sintética',
  '{"email":"context@example.invalid"}'::jsonb,
  'anonymous',
  '',
  false,
  'comprometida',
  '[{"category":"Agua","description":"Botellas selladas sintéticas","quantity":12,"unit":"litro","condition":"sellado","storage_requirement":"ambiente","declared_estimated_value_cop":84000}]'::jsonb,
  null,
  '70000000-0000-0000-0000-000000000002',
  '{"donor_type":"empresa","economic_sector":"Tecnología","specific_destination":true,"destination_note":"Zona simulada","destination_department":"Caldas","destination_municipality":"Manizales","estimated_beneficiaries":"24","delivery_channel":"Operador sintético","internal_responsible":"Persona interna sintética","internal_contact":{"value":"interno@example.invalid"},"observations":"Observación sintética"}'::jsonb
);
select ok((select intake_id from test_contextual_intake) is not null, 'El intake contextual ejecuta el recorrido transaccional completo');
select is((select donor_type from public.donation_intakes where id=(select intake_id from test_contextual_intake)), 'empresa', 'Conserva el perfil declarado del donante');
select is((select estimated_beneficiaries from public.donation_intakes where id=(select intake_id from test_contextual_intake)), 24, 'Beneficiarios estimados quedan separados y privados');
select is((select declared_estimated_value_cop from public.donation_intake_items where intake_id=(select intake_id from test_contextual_intake)), 84000::numeric, 'El valor estimado queda marcado a nivel de artículo');
select is((select char_length(request_fingerprint) from public.donation_intakes where id=(select intake_id from test_contextual_intake)), 64, 'La solicitud guarda una huella SHA-256');

select throws_ok(
  $$select * from public.submit_donation_intake(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind',
    'test-invalid-server-contract-001',
    '',
    '{"email":"context@example.invalid"}'::jsonb,
    'anonymous',
    '',
    false,
    'comprometida',
    '[{"category":"Agua","description":"Botellas selladas sintéticas","quantity":12,"unit":"litro","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
    null,
    '70000000-0000-0000-0000-000000000002',
    '{}'::jsonb
  )$$,
  '22023',
  'Escribe el nombre del donante',
  'El servidor rechaza un campo obligatorio aunque el cliente sea omitido'
);

select throws_ok(
  $$select * from public.submit_donation_intake(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind',
    'test-contextual-intake-001',
    'Persona sintética',
    '{"email":"context@example.invalid"}'::jsonb,
    'anonymous',
    '',
    false,
    'comprometida',
    '[{"category":"Agua","description":"Botellas selladas sintéticas","quantity":13,"unit":"litro","condition":"sellado","storage_requirement":"ambiente","declared_estimated_value_cop":84000}]'::jsonb,
    null,
    '70000000-0000-0000-0000-000000000002',
    '{"donor_type":"empresa","economic_sector":"Tecnología","specific_destination":true,"destination_note":"Zona simulada","destination_department":"Caldas","destination_municipality":"Manizales","estimated_beneficiaries":"24","delivery_channel":"Operador sintético","internal_responsible":"Persona interna sintética","internal_contact":{"value":"interno@example.invalid"},"observations":"Observación sintética"}'::jsonb
  )$$,
  '22023',
  'La clave idempotente ya fue usada con datos diferentes',
  'La idempotencia rechaza reutilizar una clave con otro contenido'
);

select is((select count(*)::integer from public.public_need_projections where published and source_need_id in ('60000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000002')), 2, 'Las dos necesidades base están publicadas');
select is((select count(*)::integer from public.public_need_map('10000000-0000-0000-0000-000000000001',-75.7,6.1,-75.4,6.4)),1,'El filtro PostGIS devuelve solo el punto público dentro del encuadre');
select is((select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001')),2,'La proyección pública devuelve dos centros sintéticos sin dirección exacta');
select is((select count(*)::integer from public.public_donation_projections p join public.donations d on d.id=p.donation_id join public.donation_intakes i on i.id=d.intake_id where i.status <> 'approved'), 0, 'Ningún intake sin aprobar aparece públicamente');
select ok(public.contains_sensitive_content('Consignar a cuenta de ahorros'), 'Detecta contenido monetario ciudadano');
select ok(public.contains_sensitive_content('Llámame al 3001234567'), 'Detecta teléfono personal');
select ok(not public.contains_sensitive_content('Se requieren 20 kits de higiene'), 'Acepta descripción humanitaria segura');
select ok(not public.contains_sensitive_content('Se requieren cincuenta unidades'), 'No confunde cincuenta con una cuenta bancaria');

select throws_ok(
  $$ update public.audit_events set action = 'tampered' $$,
  '42501',
  'El historial append-only no puede modificarse ni eliminarse',
  'La auditoría no puede alterarse'
);

select * from finish();
rollback;
