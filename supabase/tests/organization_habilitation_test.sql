-- G-055 · La habilitacion operativa de una organizacion tiene exactamente una puerta.
--
-- Lo que se comprueba aqui no es que la puerta exista, sino que **no haya otras**. Por eso
-- la mayor parte del archivo son intentos de entrar por donde no se debe: escritura directa
-- con los privilegios de tabla que `service_role` conserva del arranque en frio, la RPC de
-- administracion, y la propia marca de transaccion puesta a mano.
--
-- El recorrido se ejecuta entero: registro, activacion y proyeccion publica, porque el
-- defecto original tenia dos mitades y solo una pasaba por `organizations.verified`. La
-- otra era `public_collection_centers`, que no consultaba la organizacion en absoluto.
begin;
select plan(30);

-- --------------------------------------------------------------- la puerta existe --
select has_function(
  'public', 'assert_organization_habilitation_path', '{}'::text[],
  'Existe el disparador que custodia la habilitacion'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.organizations'::regclass
      and tgname = 'organizations_habilitation_guard'
      and not tgisinternal
  ),
  'El disparador esta puesto sobre organizations, no solo declarado'
);
select has_function(
  'public', 'bootstrap_organization_habilitation', array['uuid','text'],
  'Existe la via de arranque en frio, separada de la decision humana'
);

-- ------------------------------------------------- el autorregistro no se habilita --
insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000009f1','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','fantasma@ejemplo-sintetico.test', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000009f1","role":"authenticated"}',true);
select public.register_ally(
  '10000000-0000-0000-0000-000000000001','empresa','Fundacion Fantasma Sintetica',
  'NIT-999888777','Persona Responsable Sintetica','3001234567',
  'fantasma@ejemplo-sintetico.test','Calle Sintetica 123', 4.60971, -74.08175, null
);

create temporary table activacion as
select organization_id, operational from public.activate_ally_registration();

select is(
  (select operational from activacion),
  false,
  'La activacion declara que la organizacion todavia no puede operar'
);
reset role;

select is(
  (select organization.verified from public.organizations as organization
   where organization.name = 'Fundacion Fantasma Sintetica'),
  false,
  'La organizacion autorregistrada nace SIN habilitacion para operar'
);
-- G-039 no se rompe al cerrar G-055: el nivel de comprobacion sigue diciendo la verdad.
select is(
  (select verification.state from public.organization_verifications as verification
   join public.organizations as organization on organization.id = verification.organization_id
   where organization.name = 'Fundacion Fantasma Sintetica'),
  'email_verified',
  'El nivel de comprobacion sigue siendo el del buzon, ni mas ni menos'
);

-- ------------------------------------------- lo que ve un visitante sin sesion --
set local role anon;
select is(
  (select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001') as center
   where center.name like '%Fantasma%'),
  0,
  'El acopio de una organizacion sin habilitar no se publica a los donantes'
);
-- El mapa es una superficie distinta: `public_logistics_projections` es una TABLA que `anon`
-- lee directa, y la regla de publicacion vive alli por segunda vez, en
-- `sync_public_collection_projection`. Arreglar solo la proyeccion de centros dejaba al
-- impostor en el mapa con su etiqueta, su direccion y sus coordenadas. Lo encontro el
-- barrido de las diez superficies anonimas, no la revision del codigo.
select is(
  (select count(*)::integer from public.public_logistics_projections as projection
   where projection.label like '%Fantasma%' and projection.published),
  0,
  'El acopio de una organizacion sin habilitar tampoco sale en el mapa publico'
);
-- Y el filtro nuevo no vacia la proyeccion: los puntos legitimos siguen ahi.
select ok(
  (select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001')) >= 3,
  'Los acopios de organizaciones habilitadas siguen publicandose'
);
select ok(
  (select count(*)::integer from public.public_logistics_projections as projection
   where projection.source_type = 'collection_center' and projection.published) >= 3,
  'Y el mapa conserva los acopios legitimos'
);
reset role;

-- ------------------------------------------------------- las vias que se cierran --
-- `service_role` conserva INSERT y UPDATE sobre organizations desde `202608160004`, y
-- ademas ignora RLS. Sin el disparador, esta sentencia habilitaria la organizacion sin
-- actor, sin motivo y sin auditoria: era la via facil y silenciosa.
set local role service_role;
select throws_ok(
  format(
    $$update public.organizations set verified = true where id = %L$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '42501',
  'Habilitar una organización exige decide_organization_verification() con actor y sustento',
  'La escritura directa con privilegios de tabla no habilita una organizacion'
);
select throws_ok(
  format(
    $$insert into public.organizations(name, slug, verified) values ('Atajo','atajo-%s',true)$$,
    'sintetico'
  ),
  '42501',
  'Habilitar una organización exige decide_organization_verification() con actor y sustento',
  'Tampoco se nace habilitada por insercion directa'
);
-- La marca de transaccion no es la puerta: es una de las dos condiciones. Ponerla a mano
-- desde un rol de la API no abre nada, porque `current_user` sigue sin ser el dueno.
select set_config('app.organization_habilitation','on',true);
select throws_ok(
  format(
    $$update public.organizations set verified = true where id = %L$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '42501',
  'Habilitar una organización exige decide_organization_verification() con actor y sustento',
  'Poner la marca a mano desde la API no abre la puerta'
);
select set_config('app.organization_habilitation','',true);
reset role;

-- La RPC de administracion global tampoco sustituye a la decision: no deja motivo escrito.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select throws_ok(
  $$select public.manage_organization(null,'Organizacion por la puerta de atras','puerta-atras','active',true)$$,
  '42501',
  'Habilitar una organizacion exige decide_organization_verification() con actor y sustento',
  'La autoridad global no habilita una organizacion nueva desde la administracion'
);
select throws_ok(
  format(
    $$select public.manage_organization(%L,null,null,null,true)$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '42501',
  'Habilitar una organizacion exige decide_organization_verification() con actor y sustento',
  'Tampoco habilita una existente que no lo estaba'
);
-- Y el aliado sigue sin poder decidir sobre su propia organizacion.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000009f1","role":"authenticated"}',true);
select throws_ok(
  format(
    $$select public.decide_organization_verification(%L,'10000000-0000-0000-0000-000000000001','verify','Me verifico a mi mismo')$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '42501',
  'No puedes decidir la verificacion de esta organizacion',
  'El aliado no se verifica a si mismo'
);
-- La via de arranque en frio no esta al alcance de una sesion de la API.
select throws_ok(
  format(
    $$select public.bootstrap_organization_habilitation(%L,'Intento desde la aplicacion')$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '42501',
  'permission denied for function bootstrap_organization_habilitation',
  'La via de arranque en frio no es alcanzable desde una sesion autenticada'
);

-- ------------------------------------------------------------- la via sancionada --
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
-- El sustento no se relaja al ganar la funcion un efecto nuevo.
select throws_ok(
  format(
    $$select public.decide_organization_verification(%L,'10000000-0000-0000-0000-000000000001','verify','ok')$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  '22023',
  'Registra el sustento de la decision',
  'Verificar sigue exigiendo dejar por escrito en que se sustenta'
);
-- Pedir documentos no concede ni retira: es un paso intermedio, no una decision.
select is(
  public.decide_organization_verification(
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica'),'10000000-0000-0000-0000-000000000001',
    'request_documents','Se solicita camara de comercio y RUT del ejercicio sintetico'),
  'document_pending',
  'Se pueden pedir documentos antes de decidir'
);
reset role;
select is(
  (select organization.verified from public.organizations as organization
   where organization.id = (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')),
  false,
  'Pedir documentos no habilita a nadie'
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select is(
  public.decide_organization_verification(
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica'),'10000000-0000-0000-0000-000000000001',
    'verify','Documentos revisados en el ejercicio sintetico'),
  'verified',
  'La decision humana con sustento verifica la organizacion'
);
reset role;
select is(
  (select organization.verified from public.organizations as organization
   where organization.id = (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')),
  true,
  'Y esa decision, y solo esa, la habilita para operar'
);
select is(
  (select (audit.metadata ->> 'habilitacion_antes') || '->' || (audit.metadata ->> 'habilitacion_despues')
   from public.audit_events as audit
   where audit.action = 'decide_organization_verification'
     and audit.entity_id = (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
     -- No se ordena por `occurred_at`: es la hora de la transaccion y todas las decisiones
     -- de esta prueba la comparten, asi que el orden quedaria al azar. Es la misma trampa
     -- que `202608200003` documento para `created_at`. Se busca la fila por lo que dice.
     and audit.metadata ->> 'valor_nuevo' = 'verified'),
  'false->true',
  'La auditoria deja el antes y el despues de la habilitacion, no solo el estado'
);

-- Habilitada, su acopio ya es publicable: es la misma puerta la que decide las dos cosas.
set local role anon;
select is(
  (select count(*)::integer from public.public_collection_centers('10000000-0000-0000-0000-000000000001') as center
   where center.name like '%Fantasma%'),
  1,
  'Habilitada por decision humana, su acopio si aparece en la proyeccion publica'
);
-- Y en el mapa. Esto solo puede pasar si la decision repropaga la proyeccion: la tabla
-- guarda el valor calculado la ultima vez que se escribio, no lo recalcula al leer.
select is(
  (select count(*)::integer from public.public_logistics_projections as projection
   where projection.label like '%Fantasma%' and projection.published),
  1,
  'La decision repropaga el punto al mapa: la proyeccion no se queda con el valor viejo'
);
reset role;

-- ------------------------------------------------------------------ retirar si --
-- Bajar la habilitacion nunca necesita permiso: suspender tiene que poder hacerse por
-- cualquier via administrativa ya existente, o el control se volveria un riesgo.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',true);
select is(
  public.decide_organization_verification(
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica'),'10000000-0000-0000-0000-000000000001',
    'reject','Los documentos no corresponden a la razon social declarada'),
  'rejected',
  'La misma via puede rechazar'
);
reset role;
select is(
  (select organization.verified from public.organizations as organization
   where organization.id = (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')),
  false,
  'Rechazar retira la habilitacion para operar'
);
-- Y lo retira tambien del mapa. La mentira en esta direccion es la peor de las dos: seguiria
-- mandando gente a entregar a un sitio que la plataforma ya decidio no respaldar.
select is(
  (select count(*)::integer from public.public_logistics_projections as projection
   where projection.label like '%Fantasma%' and projection.published),
  0,
  'Rechazar retira el punto del mapa publico, no solo el permiso de operar'
);
set local role service_role;
select lives_ok(
  format(
    $$update public.organizations set verified = false where id = %L$$,
    (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')
  ),
  'Retirar la habilitacion por escritura directa sigue siendo posible'
);
reset role;

-- --------------------------------------------------------- el historial no se pierde --
select is(
  (select count(*)::integer from public.organization_verifications as verification
   where verification.organization_id = (select organization.id from public.organizations as organization where organization.name = 'Fundacion Fantasma Sintetica')),
  4,
  'Cada decision se anade al historial: buzon, documentos pedidos, verificada y rechazada'
);

select * from finish();
rollback;
