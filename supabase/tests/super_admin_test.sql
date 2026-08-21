-- SUPER_ADMIN y PARAMETRIZACION.
--
-- Lo que se comprueba aqui es lo que las fases 7, 8, 10, 11 y 12 del loop exigen:
-- que el alcance global exista, que NO sea un bypass, que nadie pueda escalar su
-- propio rol y que cada cambio administrativo quede con su antes y su despues.
begin;
select plan(67);

-- ------------------------------------------------------------- el rol existe --
select ok(
  'super_admin' = any(enum_range(null::public.app_role)::text[]),
  'SUPER_ADMIN es un valor del enum de roles, no un sistema aparte'
);
select has_function('public', 'is_super_admin', '{}'::text[], 'Existe la comprobacion de autoridad global');

-- ------------------------------------------------------------- alcance real --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select ok(public.is_super_admin(), 'La cuenta con rol global es reconocida');
-- 106 solo tiene una fila de membresia, sobre la organizacion 1. El alcance global
-- tiene que alcanzar la organizacion 2 sin ninguna fila que lo diga.
select ok(
  public.is_org_member('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001'),
  'SUPER_ADMIN alcanza una organizacion en la que no tiene membresia'
);
select ok(
  public.has_any_role('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001', array['event_admin']::public.app_role[]),
  'SUPER_ADMIN pasa la compuerta de administrador en cualquier organizacion'
);
select ok(
  public.has_event_role('10000000-0000-0000-0000-000000000001', array['verifier']::public.app_role[]),
  'SUPER_ADMIN pasa la compuerta de verificacion'
);
select ok(
  public.has_location_scope('70000000-0000-0000-0000-000000000001', array['warehouse_operator']::public.app_role[]),
  'SUPER_ADMIN alcanza cualquier bodega sin alcance declarado'
);

-- El aliado sigue acotado: el alcance global no se contagia.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select ok(not public.is_super_admin(), 'El aliado no es autoridad global');
select ok(
  not public.has_any_role('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001', array['event_admin']::public.app_role[]),
  'El aliado no pasa la compuerta de administrador de otra organizacion'
);

-- ------------------------------------------------- SUPER_ADMIN no es bypass --
-- Fase 8: mayor alcance sobre las mismas reglas. El inventario no tiene ninguna
-- politica de escritura directa, asi que nadie —tampoco la autoridad global— puede
-- hacer `update stock = ...` saltandose el Kardex.
select is(
  (select count(*)::integer from pg_catalog.pg_policies
   where schemaname='public' and tablename in ('inventory_lots','stock_movements','allocations')
     and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  'El inventario no admite escritura directa por ningun rol'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.inventory_lots'::regclass),
  'RLS sigue habilitada sobre el inventario'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.memberships'::regclass),
  'RLS sigue habilitada sobre las membresias'
);

-- ------------------------------------------- no se puede escalar el propio rol --
select ok(
  not has_function_privilege('authenticated','public.grant_super_admin(text,uuid,uuid,text)','EXECUTE'),
  'La concesion de SUPER_ADMIN no es alcanzable desde una sesion autenticada'
);
select ok(
  not has_function_privilege('anon','public.grant_super_admin(text,uuid,uuid,text)','EXECUTE'),
  'La concesion de SUPER_ADMIN no es alcanzable de forma anonima'
);
select ok(
  not has_function_privilege('authenticated','public.revoke_super_admin(uuid,text)','EXECUTE'),
  'La revocacion de SUPER_ADMIN tampoco se expone al cliente'
);
select ok(
  has_function_privilege('service_role','public.grant_super_admin(text,uuid,uuid,text)','EXECUTE'),
  'La operacion privilegiada si es alcanzable por quien administra el entorno'
);
select ok(
  has_function_privilege('service_role','public.revoke_super_admin(uuid,text)','EXECUTE'),
  'La revocacion privilegiada tambien lo es'
);
-- Y la via silenciosa queda cerrada: `service_role` tiene INSERT y UPDATE sobre
-- `memberships` por el arranque en frio, asi que sin este disparador podia escribirse
-- la autoridad global a mano, sin motivo, sin actor y sin auditoria.
select throws_ok(
  $$insert into public.memberships(user_id, organization_id, event_id, role, active)
    values ('00000000-0000-0000-0000-000000000103','20000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000001','super_admin', true)$$,
  '42501',
  'SUPER_ADMIN solo se concede o revoca con grant_super_admin() / revoke_super_admin()',
  'La autoridad global no se escribe directamente sobre la tabla'
);
select throws_ok(
  $$update public.memberships set active = false
    where user_id = '00000000-0000-0000-0000-000000000106' and role = 'super_admin'$$,
  '42501',
  'La membresia SUPER_ADMIN no se modifica por escritura directa',
  'Tampoco se altera la que ya existe'
);
select lives_ok(
  $$insert into public.memberships(user_id, organization_id, event_id, role, active)
    values ('00000000-0000-0000-0000-000000000105','20000000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000001','auditor', true)$$,
  'El disparador no estorba a los demas roles'
);
select is(
  (select count(*)::integer from public.audit_events
   where action = 'grant_super_admin' and metadata ->> 'via' = 'operacion_privilegiada'),
  1,
  'La unica autoridad global del entorno se concedio por la via auditada'
);
select is(
  (select count(*)::integer from pg_catalog.pg_policies
   where schemaname='public' and tablename='memberships' and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  'Ningun cliente escribe roles directamente sobre la tabla'
);
-- El aliado intenta darse un rol.
select throws_ok(
  $$select public.assign_membership_role(
      '00000000-0000-0000-0000-000000000102',
      '20000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000001',
      'event_admin'::public.app_role, true)$$,
  '42501',
  'Solo SUPER_ADMIN administra roles',
  'El aliado no puede asignarse un rol administrativo'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select throws_ok(
  $$select public.assign_membership_role(
      '00000000-0000-0000-0000-000000000103',
      '20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'super_admin'::public.app_role, true)$$,
  '42501',
  'SUPER_ADMIN solo se concede mediante la operacion privilegiada',
  'La consola no puede repartir autoridad global'
);
select throws_ok(
  $$select public.assign_membership_role(
      '00000000-0000-0000-0000-000000000106',
      '20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'auditor'::public.app_role, true)$$,
  '42501',
  'No puedes modificar tus propios roles',
  'Nadie edita su propia membresia desde la consola'
);
select throws_ok(
  $$select public.set_user_platform_access('00000000-0000-0000-0000-000000000106', false)$$,
  '42501',
  'No puedes desactivar tu propia cuenta',
  'Nadie se desactiva a si mismo'
);

-- ------------------------------------------------ administracion que si aplica --
select lives_ok(
  $$select public.assign_membership_role(
      '00000000-0000-0000-0000-000000000104',
      '20000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000001',
      'warehouse_operator'::public.app_role, true)$$,
  'SUPER_ADMIN asigna un rol operativo en otra organizacion'
);
select is(
  (select count(*)::integer from public.memberships
   where user_id='00000000-0000-0000-0000-000000000104'
     and organization_id='20000000-0000-0000-0000-000000000002'
     and role='warehouse_operator' and active),
  1,
  'La asignacion queda escrita como membresia activa'
);
select is(
  public.set_user_platform_access('00000000-0000-0000-0000-000000000104', false),
  2,
  'Desactivar una cuenta retira sus dos membresias vigentes'
);
select is(
  (select count(*)::integer from public.memberships where user_id='00000000-0000-0000-0000-000000000104'),
  2,
  'Desactivar no borra: las membresias siguen ahi para la trazabilidad'
);

-- --------------------------------------------------------- parametrizacion --
select ok(
  (select count(*) from public.parameterizable_catalogs()) >= 5,
  'La parametrizacion ofrece los catalogos que son datos'
);
select ok(
  not exists (select 1 from public.parameterizable_catalogs() where key in ('declared_donation_statuses','departments')),
  'Los catalogos que son contrato quedan fuera de la parametrizacion'
);
select throws_ok(
  $$select public.manage_catalog_values('departments', '["Antioquia"]'::jsonb, 'intento')$$,
  '42501',
  'Ese catalogo no es parametrizable',
  'No se puede parametrizar un catalogo que sostiene una invariante'
);
select throws_ok(
  $$select public.manage_catalog_values('units', '[{"value":"litro"}]'::jsonb, 'intento')$$,
  '22023',
  'El nuevo catalogo debe conservar la forma del vigente',
  'La forma del catalogo no se cambia desde una pantalla'
);
select throws_ok(
  $$select public.manage_catalog_values('units', '["litro","litro"]'::jsonb, 'intento')$$,
  '22023',
  'El catalogo no admite valores repetidos',
  'El catalogo no admite valores repetidos'
);
select is(
  public.manage_catalog_values('units', '["litro","kilogramo","unidad","kit","paquete","caja"]'::jsonb, 'Se agrega caja para el piloto'),
  3,
  'Parametrizar publica una version nueva'
);
select is(
  (select count(*)::integer from public.catalog_versions as version
   join public.catalogs as catalog on catalog.id = version.catalog_id
   where catalog.key='units' and version.effective_to is null),
  1,
  'Solo una version del catalogo queda vigente'
);
select is(
  (select jsonb_array_length(version.values_json) from public.catalog_versions as version
   join public.catalogs as catalog on catalog.id = version.catalog_id
   where catalog.key='units' and version.effective_to is null),
  6,
  'La version vigente es la recien publicada'
);
select ok(
  (select count(*) from public.catalog_versions as version
   join public.catalogs as catalog on catalog.id = version.catalog_id
   where catalog.key='units' and version.effective_to is not null) >= 1,
  'La version anterior se conserva cerrada, no se sobrescribe'
);

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  $$select public.manage_catalog_values('units', '["litro"]'::jsonb, 'intento')$$,
  '42501',
  'Solo SUPER_ADMIN parametriza catalogos',
  'El aliado no puede modificar configuracion'
);
select throws_ok(
  $$select public.manage_organization(null,'Organizacion pirata','pirata','active',true)$$,
  '42501',
  'Solo SUPER_ADMIN administra organizaciones',
  'El aliado no puede crear organizaciones'
);
select is(
  (select count(*)::integer from public.platform_users_admin('10000000-0000-0000-0000-000000000001')),
  0,
  'El padron de cuentas no devuelve nada a quien no es autoridad global'
);

-- ------------------------------------------------ auditoria del parametrizador --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select ok(
  exists (
    select 1 from public.audit_events
    where entity_table='memberships' and action='insert'
      and actor_id='00000000-0000-0000-0000-000000000106'
      and metadata ? 'valor_nuevo'
  ),
  'La asignacion de rol deja actor, entidad y valor nuevo'
);
select ok(
  exists (
    select 1 from public.audit_events
    where entity_table='memberships' and action='update'
      and metadata -> 'valor_anterior' ? 'active'
      and metadata -> 'valor_nuevo' ? 'active'
  ),
  'La desactivacion deja el antes y el despues del campo que cambio'
);
select ok(
  exists (
    select 1 from public.audit_events
    where action='parameterize_catalog'
      and metadata ->> 'catalogo' = 'units'
      and metadata ? 'valor_anterior' and metadata ? 'valor_nuevo'
  ),
  'La parametrizacion de un catalogo deja el antes y el despues'
);
select is(
  (select count(*)::integer from public.audit_events
   where entity_table in ('catalogs','catalog_versions')),
  1,
  'Un cambio de catalogo deja un registro, no el mismo JSON repetido en tres'
);
select ok(
  (select count(*) from public.platform_audit_admin('10000000-0000-0000-0000-000000000001', 100)) >= 3,
  'La consola de auditoria muestra los cambios administrativos'
);

-- ------------------------------------------- alcance del ADMINISTRADOR por bodega --
-- Fase 12: el alcance del administrador se define por asignacion, no creando un rol
-- por bodega. Sin filas declaradas el comportamiento anterior se conserva; en cuanto
-- se declara una bodega, la membresia deja de alcanzar las demas de su organizacion.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select is(
  public.set_membership_locations(
    (select id from public.memberships
     where user_id='00000000-0000-0000-0000-000000000103'
       and organization_id='20000000-0000-0000-0000-000000000002'
       and role='warehouse_operator'),
    array['70000000-0000-0000-0000-000000000002']::uuid[]
  ),
  1,
  'La administracion declara una bodega para esa membresia'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',true);
select ok(
  public.has_location_scope('70000000-0000-0000-0000-000000000002', array['warehouse_operator']::public.app_role[]),
  'El operador alcanza la bodega que tiene asignada'
);
select ok(
  not public.has_location_scope('70000000-0000-0000-0000-000000000003', array['warehouse_operator']::public.app_role[]),
  'El operador no alcanza una bodega de su organizacion que no tiene asignada'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select ok(
  public.has_location_scope('70000000-0000-0000-0000-000000000003', array['warehouse_operator']::public.app_role[]),
  'SUPER_ADMIN alcanza la bodega que el operador tiene vedada'
);

-- ------------------------------- G-039 · correo confirmado no es organizacion verificada --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.organization_verifications'::regclass
      and conname = 'organization_verifications_state_check'
      and pg_get_constraintdef(oid) like '%email_verified%'
      and pg_get_constraintdef(oid) like '%document_pending%'
  ),
  'El modelo distingue correo comprobado de organizacion verificada'
);
select is(
  (select verification_state from public.organization_verification_status('10000000-0000-0000-0000-000000000001')
   where organization_id = '20000000-0000-0000-0000-000000000002'),
  'pending',
  'Una organizacion sin decision de verificacion no figura como verificada'
);
select throws_ok(
  $$select public.decide_organization_verification(
      '20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','verify','ok')$$,
  '22023',
  'Registra el sustento de la decision',
  'Verificar una organizacion exige dejar por escrito en que se sustenta'
);
select is(
  public.decide_organization_verification(
    '20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
    'request_documents','Se solicita camara de comercio y RUT del ejercicio'),
  'document_pending',
  'La autoridad global puede pedir documentos antes de verificar'
);
select is(
  public.decide_organization_verification(
    '20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
    'verify','Documentos revisados en el ejercicio sintetico'),
  'verified',
  'Con documentos revisados la organizacion queda verificada'
);
select is(
  (select verification_method from public.organization_verification_status('10000000-0000-0000-0000-000000000001')
   where organization_id = '20000000-0000-0000-0000-000000000002'),
  'document_reviewed',
  'El metodo distingue la revision documental del correo confirmado'
);
select is(
  (select count(*)::integer from public.organization_verifications
   where organization_id = '20000000-0000-0000-0000-000000000002'),
  2,
  'Cada decision se anade al historial en vez de sobrescribir la anterior'
);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',true);
select throws_ok(
  $$select public.decide_organization_verification(
      '20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','verify','Intento del aliado')$$,
  '42501',
  'No puedes decidir la verificacion de esta organizacion',
  'El aliado no verifica organizaciones ajenas'
);

-- --------------------------------------- identificador publico de una organizacion --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select throws_ok(
  $$select public.manage_organization(null,'Organizacion de prueba','Con Mayusculas Y Espacios','active',false)$$,
  '22023',
  'El identificador debe ser minusculas, numeros y guiones simples',
  'El identificador publico se valida antes de llegar a la restriccion de la tabla'
);
select throws_ok(
  $$select public.manage_organization(null,'Organizacion de prueba','aliados-unidos-demo','active',false)$$,
  '22023',
  'Ese identificador ya esta en uso',
  'Dos organizaciones no pueden compartir identificador publico'
);
select ok(
  public.manage_organization(null,'Organizacion de prueba','organizacion-de-prueba','active',false) is not null,
  'La autoridad global da de alta una organizacion nueva'
);
select throws_ok(
  $$select public.manage_organization(
      '20000000-0000-0000-0000-000000000002','Aliados Unidos Demo','otro-identificador','active',true)$$,
  '22023',
  'El identificador publico de una organizacion existente no se cambia',
  'Renombrar el identificador romperia enlaces ya emitidos, asi que no se permite'
);
create temporary table suspended_organization as
select public.manage_organization(
  '20000000-0000-0000-0000-000000000002', null, null, 'suspended', null) as id;
select is(
  (select organization.status from public.organizations as organization
   where organization.id = (select id from suspended_organization)),
  'suspended',
  'La baja de una organizacion con historial es una suspension, no un borrado'
);
select is(
  (select count(*)::integer from public.organizations
   where id = '20000000-0000-0000-0000-000000000002'),
  1,
  'La organizacion suspendida sigue existiendo con su historial'
);

-- ------------------------------------- G-071 · la marca sola no abre la puerta --
--
-- `202608200002` cerro la escritura directa de una membresia SUPER_ADMIN con un disparador que
-- deja pasar cuando ve la marca de transaccion. Pero el disparador era `security definer`, asi
-- que `current_user` dentro de el era siempre el dueno y la unica condicion efectiva quedaba
-- siendo la marca, que `set_config` deja poner a cualquiera. `service_role` tiene ademas INSERT
-- sobre `memberships` desde el arranque en frio: se concedia autoridad global a quien quisiera,
-- sin actor en la auditoria. Estuvo desplegado desde el 20 de agosto.
--
-- Lo que se fija aqui no es «existe un disparador», que ya se comprobaba, sino que la marca
-- **por si sola** no basta.
reset role;
set local role service_role;
select set_config('app.super_admin_grant','on', true);
select throws_ok(
  $$insert into public.memberships(user_id, organization_id, event_id, role, active)
    values ('00000000-0000-0000-0000-000000000102','20000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000001','super_admin', true)$$,
  '42501',
  'SUPER_ADMIN solo se concede o revoca con grant_super_admin() / revoke_super_admin()',
  'Poner la marca a mano desde service_role NO concede SUPER_ADMIN'
);
select set_config('app.super_admin_grant','', true);

-- Y la via sancionada sigue abierta: cerrar el atajo no puede cerrar el arranque en frio, que
-- es como la propia semilla concede la primera autoridad global.
select lives_ok(
  $$select public.grant_super_admin(
      'aliado@rutasolidaria.local','20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001','Comprobacion de que la via legitima sigue abierta')$$,
  'grant_super_admin desde service_role sigue funcionando'
);
reset role;

select * from finish();
rollback;
