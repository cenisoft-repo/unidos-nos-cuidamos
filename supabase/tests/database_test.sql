begin;
select plan(155);

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
select has_function('public', 'submit_donation_intake_v2', array['uuid','uuid','donation_kind','text','text','jsonb','text','text','boolean','text','jsonb','numeric','uuid','jsonb','jsonb','text'], 'Existe intake validado contra catálogos y centro');
select has_column('public', 'donation_intakes', 'reporting_ally_code', 'El intake conserva el aliado declarado solo como referencia');
select has_table('public', 'donation_intake_evidence', 'Existe el vínculo privado de fotografías del intake');
select has_function('public', 'prepare_intake_photo_evidence', array['uuid','text','text','bigint','text'], 'Existe RPC segura para reservar evidencia fotográfica');
select has_function('public', 'confirm_intake_photo_evidence', array['uuid'], 'Existe RPC que confirma la carga privada');
select has_column('public', 'donation_intakes', 'declared_category_code', 'El intake conserva la categoría económica detallada');
select has_column('public', 'donation_intake_items', 'category_code', 'Cada artículo conserva la categoría detallada');
select has_column('public', 'item_acceptance_rules', 'location_id', 'Las reglas de recepción pueden pertenecer a un centro específico');
select has_column('public', 'inventory_locations', 'public_instructions', 'El punto conserva instrucciones públicas separadas de la dirección privada');
select has_column('public', 'inventory_locations', 'updated_at', 'El punto registra la fecha de su última parametrización');
select has_table('public', 'delivery_point_changes', 'Existe un registro append-only de cambios en puntos de entrega');
select has_function('public', 'manage_delivery_point', array['uuid','uuid','uuid','text','text','text','text','numeric','numeric','boolean','boolean','boolean','boolean','text[]','text'], 'Existe RPC transaccional para parametrizar puntos');
select has_function('public', 'delivery_points_admin', array['uuid'], 'Existe consulta administrativa privada de puntos');
select has_function('public', 'organization_delivery_points', array['uuid','uuid'], 'Existe consulta de puntos limitada a la organización reportante');
select ok(has_function_privilege('authenticated','public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,boolean,boolean,text[],text)','EXECUTE'), 'El usuario autenticado solo intenta parametrizar mediante la RPC');
select ok(not has_function_privilege('anon','public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,boolean,boolean,text[],text)','EXECUTE'), 'El visitante no puede parametrizar puntos');
select ok(not has_function_privilege('anon','public.organization_delivery_points(uuid,uuid)','EXECUTE'), 'El visitante no consulta la selección privada por organización');
select ok(not has_function_privilege('authenticated','public.submit_donation_intake(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb)','EXECUTE'), 'La aplicación autenticada no puede saltarse el contrato catalogado anterior');
select ok(has_function_privilege('authenticated','public.submit_donation_intake_v2(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb,jsonb,text)','EXECUTE'), 'La aplicación autenticada ejecuta únicamente el intake catalogado');
select ok(has_function_privilege('authenticated','public.prepare_intake_photo_evidence(uuid,text,text,bigint,text)','EXECUTE'), 'El usuario autenticado puede reservar una fotografía mediante la RPC');
select ok(has_function_privilege('authenticated','public.confirm_intake_photo_evidence(uuid)','EXECUTE'), 'El usuario autenticado puede confirmar una fotografía mediante la RPC');
select ok(not has_table_privilege('anon','public.donation_intake_evidence','SELECT'), 'El visitante no puede leer vínculos fotográficos privados');
select ok(not has_function_privilege('authenticated','public.submit_donation_intake_v2_catalogs_v1(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb,jsonb,text)','EXECUTE'), 'El cliente no puede saltarse la validación actual mediante la implementación interna');
select is((select count(*)::integer from public.donation_flow_catalogs()), 8, 'El flujo expone sus ocho catálogos autoritativos');
select is((select jsonb_array_length(values_json) from public.donation_flow_catalogs() where key='donation_categories'), 13, 'Las trece categorías de la matriz están versionadas');
select is((select jsonb_array_length(values_json) from public.donation_flow_catalogs() where key='coverage_departments'), 5, 'La cobertura inicial conserva los cinco departamentos definidos');
select is((select jsonb_array_length(values_json) from public.donation_flow_catalogs() where key='reporting_allies'), 22, 'Los veintidós aliados suministrados están versionados sin conceder permisos');
select is((select cardinality(accepts) from public.public_collection_centers('10000000-0000-0000-0000-000000000001') where id='70000000-0000-0000-0000-000000000002'), 8, 'El centro aliado publica solo sus agrupaciones aceptadas vigentes');
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
select ok((select count(*)::integer from public.public_logistics_map('10000000-0000-0000-0000-000000000001') where source_type='collection_center') >= 2, 'El mapa logístico publica los centros de acopio activos');
select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='public_logistics_projections' and column_name='exact_address_private'), 'La proyección logística no contiene dirección exacta');
select ok(exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='public_logistics_projections'), 'La logística pública está habilitada para Realtime');
select ok(not has_table_privilege('anon','public.public_logistics_projections','INSERT'), 'El visitante no puede escribir la proyección logística');
select ok(not has_function_privilege('anon','public.allocate_stock(uuid,uuid,numeric,text)','EXECUTE'), 'El visitante no puede ejecutar mutaciones operativas SECURITY DEFINER');
select ok(not has_function_privilege('anon','public.submit_donation_intake(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb)','EXECUTE'), 'El visitante no puede registrar datos privados de un aporte sin membresía');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select is((select count(*)::integer from public.organization_delivery_points('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002')), 1, 'El aliado solo recibe puntos activos de su propia organización');
select is((select cardinality(accepts) from public.organization_delivery_points('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002') where id='70000000-0000-0000-0000-000000000002'), 8, 'La selección organizacional hereda las reglas globales cuando el punto no tiene excepciones');
select throws_ok(
  $$select * from public.submit_donation_intake_v2(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind', 'test-cross-tenant-point-001', 'Donante sintético',
    '{"email":"cross-tenant@example.invalid"}'::jsonb,
    'anonymous','',false,'comprometida',
    '[{"category":"Agua","category_code":"agua_potable","description":"Agua sintética sellada","quantity":1,"unit":"litro","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
    null, '70000000-0000-0000-0000-000000000001',
    '{"specific_destination":false}'::jsonb,
    public.current_donation_catalog_versions(), null
  )$$,
  '22023',
  'Selecciona un punto de entrega activo de tu organización',
  'El contrato rechaza un punto activo perteneciente a otra organización'
);
create temporary table test_catalogued_intake as
select * from public.submit_donation_intake_v2(
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'in_kind',
  'test-catalogued-intake-001',
  'Donante catalogado sintético',
  '{"email":"catalog@example.invalid"}'::jsonb,
  'anonymous',
  '',
  false,
  'entregada',
  '[{"category":"Logística","category_code":"combustible","description":"Combustible sintético sellado","quantity":3,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
  null,
  '70000000-0000-0000-0000-000000000002',
  '{"donor_type":"cooperativa","economic_sector":"logistica_transporte","reporting_ally":"propacifico","specific_destination":false,"internal_contact":{}}'::jsonb,
  public.current_donation_catalog_versions(),
  null
);
select ok((select intake_id from test_catalogued_intake) is not null, 'El intake catalogado registra el aporte compatible');
select is((select declared_status from public.donation_intakes where id=(select intake_id from test_catalogued_intake)), 'entregada', 'Entregada se conserva como declaración');
select is((select status::text from public.donation_intakes where id=(select intake_id from test_catalogued_intake)), 'pending_verification', 'Entregada no cambia el estado operativo sin revisión');
select is((select category || ':' || category_code from public.donation_intake_items where intake_id=(select intake_id from test_catalogued_intake)), 'Logística:combustible', 'La categoría detallada conserva su agrupación logística');
select is((select catalog_versions from public.donation_intakes where id=(select intake_id from test_catalogued_intake)), public.current_donation_catalog_versions(), 'El intake fija las versiones usadas al validar');
select is((select reporting_ally_code from public.donation_intakes where id=(select intake_id from test_catalogued_intake)), 'propacifico', 'El aliado elegido queda en el resumen interno sin sustituir a la organización');
select is((select count(*)::integer from public.donations where intake_id=(select intake_id from test_catalogued_intake)), 0, 'La declaración no crea una donación operativa antes de aprobación');
select throws_ok(
  $$select * from public.submit_donation_intake_v2(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind',
    'test-invalid-category-001',
    'Donante sintético',
    '{"email":"invalid@example.invalid"}'::jsonb,
    'anonymous','',false,'comprometida',
    '[{"category":"Logística","category_code":"codigo_inventado","description":"Artículo sintético","quantity":1,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
    null,
    '70000000-0000-0000-0000-000000000002',
    '{"specific_destination":false}'::jsonb,
    public.current_donation_catalog_versions(),
    null
  )$$,
  '22023',
  'Cada artículo requiere una categoría detallada vigente',
  'El servidor rechaza categorías inventadas aunque el cliente sea alterado'
);
select throws_ok(
  $$select * from public.submit_donation_intake_v2(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind', 'test-invalid-ally-001', 'Donante sintético',
    '{"email":"invalid-ally@example.invalid"}'::jsonb,
    'anonymous','',false,'comprometida',
    '[{"category":"Logística","category_code":"combustible","description":"Artículo sintético","quantity":1,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
    null, '70000000-0000-0000-0000-000000000002',
    '{"reporting_ally":"aliado_inventado","specific_destination":false}'::jsonb,
    public.current_donation_catalog_versions(), null
  )$$,
  '22023',
  'Selecciona un aliado de referencia vigente',
  'El servidor rechaza un aliado inventado'
);
select throws_ok(
  $$select * from public.submit_donation_intake_v2(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'in_kind', 'test-other-ally-001', 'Donante sintético',
    '{"email":"other-ally@example.invalid"}'::jsonb,
    'anonymous','',false,'comprometida',
    '[{"category":"Logística","category_code":"combustible","description":"Artículo sintético","quantity":1,"unit":"unidad","condition":"sellado","storage_requirement":"ambiente"}]'::jsonb,
    null, '70000000-0000-0000-0000-000000000002',
    '{"reporting_ally":"otro","observations":"","specific_destination":false}'::jsonb,
    public.current_donation_catalog_versions(), null
  )$$,
  '22023',
  'Especifica el otro aliado en Observaciones',
  'La opción Otro exige identificar el aliado en observaciones privadas'
);

create temporary table test_prepared_photo_evidence as
select * from public.prepare_intake_photo_evidence(
  (select intake_id from test_catalogued_intake),
  'recepcion-sintetica.png',
  'image/png',
  1024,
  repeat('a', 64)
);
select ok((select evidence_id from test_prepared_photo_evidence) is not null, 'La RPC reserva una evidencia para el intake propio');
select is((
  select concat(mime_type, ':', scan_status, ':', sensitivity::text)
  from public.evidence where id=(select evidence_id from test_prepared_photo_evidence)
), 'image/png:pending:private', 'La fotografía nace privada y pendiente de revisión segura');
select is((
  select concat(position::text, ':', coalesce(uploaded_at::text, 'pending'))
  from public.donation_intake_evidence where evidence_id=(select evidence_id from test_prepared_photo_evidence)
), '1:pending', 'El vínculo conserva orden y no declara carga antes de confirmarla');
select throws_ok(
  $$select * from public.confirm_intake_photo_evidence((select evidence_id from test_prepared_photo_evidence))$$,
  '22023',
  'La fotografía todavía no fue cargada',
  'No se puede confirmar una ruta sin objeto privado almacenado'
);
insert into storage.objects(bucket_id, name, owner, metadata)
select 'evidence-private', storage_path, (select auth.uid()), '{"mimetype":"image/png","size":1024}'::jsonb
from public.evidence where id=(select evidence_id from test_prepared_photo_evidence);
select lives_ok(
  $$select * from public.confirm_intake_photo_evidence((select evidence_id from test_prepared_photo_evidence))$$,
  'La confirmación termina cuando el objeto privado realmente existe'
);
select ok((
  select uploaded_at is not null
  from public.donation_intake_evidence where evidence_id=(select evidence_id from test_prepared_photo_evidence)
), 'El vínculo registra la carga sin cambiar el estado de validación de la evidencia');
select throws_ok(
  $$select * from public.prepare_intake_photo_evidence(
    (select intake_id from test_catalogued_intake),
    'soporte-sintetico.pdf',
    'application/pdf',
    1024,
    repeat('b', 64)
  )$$,
  '22023',
  'La evidencia fotográfica debe ser JPG o PNG',
  'La evidencia del intake no acepta PDF ni tipos distintos de fotografía'
);
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

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
create temporary table test_delivery_point as
select * from public.manage_delivery_point(
  null,
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'Punto parametrizado sintético',
  'Cali · zona occidental aproximada',
  'Dirección privada sintética 123',
  'Coordina el horario después de recibir el código APO.',
  3.4516,
  -76.5320,
  true,
  true,
  true,
  false,
  array['Agua','Higiene']::text[],
  'test-delivery-point-001'
);
select ok((select location_id from test_delivery_point) is not null and not (select was_duplicate from test_delivery_point), 'Administración crea un punto mediante una escritura transaccional');
select is((
  select concat(name, ':', active::text, ':', cold_chain_capable::text)
  from public.inventory_locations where id=(select location_id from test_delivery_point)
), 'Punto parametrizado sintético:true:true', 'El punto conserva disponibilidad y capacidad operativa');
select is((
  select array_agg(category order by category)
  from public.item_acceptance_rules
  where location_id=(select location_id from test_delivery_point)
    and decision='accepted' and effective_to is null
), array['Agua','Higiene']::text[], 'Las categorías aceptadas se materializan como reglas vigentes');
select is((
  select exact_address_private
  from public.delivery_points_admin('10000000-0000-0000-0000-000000000001')
  where id=(select location_id from test_delivery_point)
), 'Dirección privada sintética 123', 'La dirección exacta aparece únicamente en la consulta administrativa');
select is((
  select public_instructions
  from public.organization_delivery_points('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002')
  where id=(select location_id from test_delivery_point)
), 'Coordina el horario después de recibir el código APO.', 'La selección del aliado recibe las instrucciones públicas parametrizadas');
select ok((select was_duplicate from public.manage_delivery_point(
  null,
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'Punto parametrizado sintético',
  'Cali · zona occidental aproximada',
  'Dirección privada sintética 123',
  'Coordina el horario después de recibir el código APO.',
  3.4516, -76.5320, true, true, true, false,
  array['Agua','Higiene']::text[],
  'test-delivery-point-001'
)), 'Repetir la misma solicitud devuelve el resultado idempotente');
select throws_ok(
  $$select * from public.manage_delivery_point(
    null,
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'Punto alterado sintético',
    'Cali · zona occidental aproximada',
    'Dirección privada sintética 123',
    'Coordina el horario después de recibir el código APO.',
    3.4516, -76.5320, true, true, true, false,
    array['Agua','Higiene']::text[],
    'test-delivery-point-001'
  )$$,
  '22023',
  'La clave idempotente ya fue usada con otros parámetros',
  'La idempotencia impide reutilizar una clave con otra parametrización'
);
select is((select actor_id from public.delivery_point_changes where location_id=(select location_id from test_delivery_point)), '00000000-0000-0000-0000-000000000101'::uuid, 'El cambio conserva el actor administrativo');
select ok(exists(
  select 1 from public.audit_events
  where entity_table='delivery_point_changes' and entity_id=(select id from public.delivery_point_changes where location_id=(select location_id from test_delivery_point))
), 'La parametrización produce auditoría append-only correlacionada');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  $$select * from public.manage_delivery_point(
    null,
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'Punto no autorizado', 'Cali · zona simulada', 'Dirección privada sintética', null,
    3.4516, -76.5320, false, true, true, false, array['Agua']::text[], 'test-denied-point-001'
  )$$,
  '42501',
  'Solo administración del evento puede parametrizar puntos de entrega',
  'El aliado reportante no puede administrar puntos'
);

select is((select count(*)::integer from public.public_need_projections where published and source_need_id in ('60000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000002')), 2, 'Las dos necesidades base están publicadas');
select is((select count(*)::integer from public.public_need_map('10000000-0000-0000-0000-000000000001',-75.7,6.1,-75.4,6.4)),1,'El filtro PostGIS devuelve solo el punto público dentro del encuadre');
select ok((select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001')) >= 3, 'La proyección pública incorpora los puntos de acopio parametrizados');
select is((select location_label from public.public_collection_centers('10000000-0000-0000-0000-000000000001') where id='70000000-0000-0000-0000-000000000002'), 'Dirección sintética no operativa', 'El centro de acopio publica su dirección exacta como ubicación pública real');
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

-- Arranque en frío: `service_role` solo alcanza las tablas que ninguna sesión con rol
-- puede crear todavía, y nada del recorrido operacional.
select ok(has_table_privilege('service_role','public.organizations','INSERT'), 'La provisión puede crear organizaciones');
select ok(has_table_privilege('service_role','public.emergency_events','INSERT'), 'La provisión puede crear el evento');
select ok(has_table_privilege('service_role','public.memberships','INSERT'), 'La provisión puede asignar membresías');
select ok(has_table_privilege('service_role','public.profiles','INSERT'), 'La provisión puede crear perfiles');
select ok(has_table_privilege('service_role','public.funds','INSERT'), 'La provisión puede crear fondos');
select ok(not has_table_privilege('service_role','public.inventory_locations','SELECT'), 'La provisión no lee centros por fuera de delivery_points_admin');
select ok(not has_table_privilege('service_role','public.item_acceptance_rules','INSERT'), 'La provisión no fija reglas por fuera de manage_delivery_point');
select ok(not has_table_privilege('service_role','public.donation_intakes','INSERT'), 'La clave administrativa no puede fabricar aportes');
select ok(not has_table_privilege('service_role','public.inventory_lots','INSERT'), 'La clave administrativa no puede fabricar inventario');
select ok(not has_table_privilege('service_role','public.financial_transactions','INSERT'), 'La clave administrativa no puede fabricar movimientos financieros');
select ok(not has_table_privilege('service_role','public.audit_events','INSERT'), 'La clave administrativa no puede escribir auditoría directa');

-- Propósito del punto: acopio, despacho o ambos, nunca ninguno.
select ok(
  (select accepts_donations and dispatches_shipments from public.inventory_locations where id = '70000000-0000-0000-0000-000000000002'),
  'El punto aliado recibe y despacha'
);
select ok(
  (select not accepts_donations and dispatches_shipments from public.inventory_locations where id = '70000000-0000-0000-0000-000000000003'),
  'La base logística solo despacha'
);
select throws_ok(
  $$ update public.inventory_locations set accepts_donations = false, dispatches_shipments = false where id = '70000000-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'Un punto sin ningún propósito es rechazado'
);
select is(
  (select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001') where id = '70000000-0000-0000-0000-000000000003'),
  0,
  'Un punto que solo despacha no aparece como centro de acopio público'
);

-- Trazabilidad: el código del reporte atraviesa su donación operacional.
select is(
  (select count(*)::integer from public.track_public_journey('APO-INVALIDO')),
  0,
  'La cadena ignora un código con formato inválido'
);
select ok(
  (select count(*) from public.track_public_journey(
    (select tracking_code from public.need_cases where id = '60000000-0000-0000-0000-000000000001')
  ) where stage_key = 'need_published') = 1,
  'La necesidad publicada aparece como hito con su fecha'
);
select ok(
  (select bool_and(occurred_at is not null) from public.track_public_journey(
    (select tracking_code from public.need_cases where id = '60000000-0000-0000-0000-000000000001')
  )),
  'Ningún hito se devuelve sin fecha'
);
select ok(
  (select count(*) from public.track_public_journey(
    (select donor_tracking_code from public.donations where id = '71000000-0000-0000-0000-000000000001')
  ) where stage_key in ('stock_received','stock_allocated','shipment_dispatched')) = 3,
  'La donación en tránsito muestra recepción, reserva y despacho'
);
select is(
  (select count(*)::integer from public.track_public_journey(
    (select donor_tracking_code from public.donations where id = '71000000-0000-0000-0000-000000000001')
  ) where detail ilike '%Transportador sintético%'),
  0,
  'La cadena no expone el transportador'
);

-- Tesorería: el saldo sale del libro completo y la justificación puede leerse.
select has_function('public', 'treasury_balance', array['uuid'], 'Existe el saldo calculado en la base');
select has_function('public', 'expense_decisions', array['uuid'], 'Existe el historial legible de decisiones de gasto');
select ok(not has_function_privilege('anon','public.treasury_balance(uuid)','EXECUTE'), 'El visitante no consulta el saldo');
select ok(not has_function_privilege('anon','public.expense_decisions(uuid)','EXECUTE'), 'El visitante no consulta las decisiones de gasto');
-- La tabla tiene RLS sin ninguna política de lectura: en la práctica no se puede consultar
-- directamente, y `expense_decisions` es la única vía. Antes eso dejaba la justificación
-- escrita y sin forma de leerla.
select is(
  (select count(*)::integer from pg_catalog.pg_policies
   where schemaname='public' and tablename='expense_approvals' and cmd in ('SELECT','ALL')),
  0,
  'La justificación no se lee por tabla, solo por la función acotada'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  $$select * from public.treasury_balance('10000000-0000-0000-0000-000000000001')$$,
  '42501',
  'No puedes consultar el saldo de este evento',
  'El aliado reportante no alcanza el saldo del evento'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',true);
select is(
  (select movement_count from public.treasury_balance('10000000-0000-0000-0000-000000000001')),
  (select count(*)::integer from public.financial_transactions where event_id='10000000-0000-0000-0000-000000000001' and status='reconciled'),
  'El saldo cuenta todo el libro conciliado del evento y no una página'
);
select is(
  (select balance from public.treasury_balance('10000000-0000-0000-0000-000000000001')),
  (select coalesce(sum(case when transaction_type='credit' then amount else -amount end),0)
   from public.financial_transactions where event_id='10000000-0000-0000-0000-000000000001' and status='reconciled'),
  'El saldo es créditos menos egresos sobre el libro completo'
);

-- G-021: la superficie privada de las necesidades no es legible por columna directa y solo
-- verificación/administración obtiene el detalle privado mediante la RPC mínima.
select ok(not has_column_privilege('authenticated','public.need_cases','exact_address_private','SELECT'), 'La dirección exacta de la necesidad no es legible por columna directa');
select ok(not has_column_privilege('authenticated','public.need_cases','contact_private','SELECT'), 'El contacto privado de la necesidad no es legible por columna directa');
select ok(not has_column_privilege('authenticated','public.need_cases','operational_location','SELECT'), 'La ubicación operativa exacta no es legible por columna directa');
select ok(has_column_privilege('authenticated','public.need_cases','public_location_text','SELECT'), 'La zona pública de la necesidad sigue siendo legible');
select ok(not has_function_privilege('anon','public.need_case_private_detail(uuid)','EXECUTE'), 'El visitante no consulta el detalle privado de la necesidad');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  $$ select * from public.need_case_private_detail('60000000-0000-0000-0000-000000000001') $$,
  '42501',
  'Solo verificación o administración del evento puede ver los datos privados de la necesidad',
  'El aliado reportante no accede a los datos privados de la necesidad'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is((select count(*)::integer from public.need_case_private_detail('60000000-0000-0000-0000-000000000001')), 1, 'La verificación autorizada obtiene el detalle privado de la necesidad');

-- G-025: la auditoría de tablas hijas hereda el evento del padre y no deja registros huérfanos.
select is(
  (select count(*)::integer from public.audit_events
   where entity_table in ('need_verifications','intake_verification_decisions','receipts','deliveries','expense_approvals','expense_payments')
     and event_id is null),
  0,
  'La auditoría de tablas hijas conserva el evento derivado del padre'
);

select * from finish();
rollback;
