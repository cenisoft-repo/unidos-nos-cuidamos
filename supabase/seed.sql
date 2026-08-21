-- Datos 100 % sintéticos para desarrollo local.

-- G-055: la habilitación operativa de una organización sólo la concede
-- `decide_organization_verification` con actor y sustento; un disparador rechaza cualquier
-- otra vía. La siembra es arranque en frío —no hay todavía quien decida—, así que reclama
-- la excepción de forma explícita y visible en vez de escribir la columna por la espalda.
-- La marca sólo sirve al dueño de la base: desde la API, con `authenticated` o
-- `service_role`, el disparador la ignora.
select set_config('app.organization_habilitation', 'on', false);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000101','authenticated','authenticated','admin@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Ana Coordinadora"}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000102','authenticated','authenticated','aliado@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Luis Aliado"}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000103','authenticated','authenticated','bodega@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Marta Bodega"}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000104','authenticated','authenticated','solicita@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Sofía Solicitudes"}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000105','authenticated','authenticated','aprueba@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Carlos Aprobaciones"}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000106','authenticated','authenticated','superadmin@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Elena Plataforma"}',now(),now(),'','','',''),
  -- Opera una sola organización. Existe para que la solicitud entre organizaciones se
  -- pueda comprobar contra la API real: si quien pide tuviera membresía en las dos, nada
  -- de lo que probara diría algo sobre el aislamiento.
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000107','authenticated','authenticated','manizales@rutasolidaria.local',crypt('RutaSolidaria2026!',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Rosa Manizales"}',now(),now(),'','','','')
on conflict (id) do nothing;

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id::text, u.id, jsonb_build_object('sub',u.id::text,'email',u.email,'email_verified',true), 'email', now(), now(), now()
from auth.users u
where u.id in (
  '00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000104',
  '00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000106',
  '00000000-0000-0000-0000-000000000107'
)
on conflict (provider_id, provider) do nothing;

insert into public.organizations(id,name,slug,verified) values
('20000000-0000-0000-0000-000000000001','Red Humanitaria Demo','red-humanitaria-demo',true),
('20000000-0000-0000-0000-000000000002','Aliados Unidos Demo','aliados-unidos-demo',true);

insert into public.emergency_events(id,name,slug,status,simulated,starts_at,public_summary) values
('10000000-0000-0000-0000-000000000001','Simulación sísmica · Región Andina','simulacion-andina-2026','active',true,'2026-08-13T08:00:00-05:00','Ejercicio local con datos ficticios para probar coordinación, trazabilidad y transparencia segura.');

insert into public.memberships(user_id,organization_id,event_id,role) values
('00000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','event_admin'),
('00000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','verifier'),
('00000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','auditor'),
('00000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','event_admin'),
('00000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','verifier'),
('00000000-0000-0000-0000-000000000102','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','partner_reporter'),
('00000000-0000-0000-0000-000000000103','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','warehouse_operator'),
('00000000-0000-0000-0000-000000000103','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','logistics_operator'),
('00000000-0000-0000-0000-000000000103','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','warehouse_operator'),
('00000000-0000-0000-0000-000000000103','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','logistics_operator'),
('00000000-0000-0000-0000-000000000104','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','treasury_requester'),
('00000000-0000-0000-0000-000000000105','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','treasury_approver'),
('00000000-0000-0000-0000-000000000107','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','warehouse_operator'),
('00000000-0000-0000-0000-000000000107','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','logistics_operator');

-- SUPER_ADMIN se siembra por la misma operación privilegiada que lo concede en cualquier
-- entorno, no con un insert a mano: la escritura directa de esa fila está bloqueada por
-- `assert_super_admin_grant_path`, así que el sandbox ejercita el camino real. La
-- organización y el evento de la fila no acotan nada; el alcance lo declara el rol.
select public.grant_super_admin(
  'superadmin@rutasolidaria.local',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Siembra del sandbox local para el recorrido de parametrización'
);

-- Promueve los aliados de referencia a organizaciones operativas con su punto de acopio.
-- Misma función que usa la migración; aquí se ejecuta con el evento y las membresías ya
-- creados. Debe ir después de las membresías para que replique la administración vigente.
select public.seed_ally_operational_points('10000000-0000-0000-0000-000000000001');

insert into public.official_sources(id,event_id,organization_name,title,url,published_at,checksum) values
('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Fuente oficial simulada','Boletín de ejercicio #1','https://example.invalid/fuente-simulada','2026-08-13T08:30:00-05:00','synthetic-only');

insert into public.territorial_units(id,divipola_code,name,department_code,level,version,centroid,valid_from) values
('40000000-0000-0000-0000-000000000001','05001','Medellín','05','municipality','demo-2026',st_geogfromtext('POINT(-75.5812 6.2442)'),'2026-01-01'),
('40000000-0000-0000-0000-000000000002','11001','Bogotá, D.C.','11','district','demo-2026',st_geogfromtext('POINT(-74.0721 4.7110)'),'2026-01-01'),
('40000000-0000-0000-0000-000000000003','17001','Manizales','17','municipality','demo-2026',st_geogfromtext('POINT(-75.5138 5.0703)'),'2026-01-01');

insert into public.catalogs(id,key,name) values
('50000000-0000-0000-0000-000000000001','need_categories','Categorías de necesidad'),
('50000000-0000-0000-0000-000000000002','units','Unidades normalizadas')
on conflict do nothing;
insert into public.catalog_versions(catalog_id,version,values_json,effective_from) values
('50000000-0000-0000-0000-000000000001',1,'["Agua","Alimentos","Higiene","Refugio","Salud","Protección"]','2026-08-13T00:00:00-05:00'),
('50000000-0000-0000-0000-000000000002',1,'["unidad","litro","kilogramo","kit","caja"]','2026-08-13T00:00:00-05:00')
on conflict do nothing;

insert into public.need_cases(id,event_id,organization_id,tracking_code,category,description,facts,status,priority_score,public_location_text,source_type,expires_at,visibility) values
('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','NEC-A1B2C3D4E5F60718293A4B5C','Agua','Se requieren botellas de agua para el albergue temporal del ejercicio.','{"households":48,"source":"field_verification"}','published',72,'Medellín · zona nororiental','authorized_organization','2026-12-31T23:59:59-05:00','public'),
('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','NEC-B1C2D3E4F5061728394A5B6C','Higiene','Se requieren kits de higiene familiar en el punto comunitario del ejercicio.','{"households":32,"source":"field_verification"}','published',58,'Manizales · sector centro','authorized_organization','2026-12-31T23:59:59-05:00','public'),
('60000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',null,'NEC-C1D2E3F40516273849A5B6C7','Alimentos','Reporte ciudadano ficticio en espera de verificación y contacto mediado.','{"source":"citizen"}','in_verification',null,'Bogotá · localidad aproximada','citizen','2026-08-14T12:00:00-05:00','private');

-- Las necesidades publicadas conservan la decisión que las llevó ahí. Sin estas filas el
-- estado sería una afirmación sin respaldo y la cadena de trazabilidad quedaría hueca.
insert into public.need_verifications(need_case_id,decision,note,confidence,decided_by,created_at) values
('60000000-0000-0000-0000-000000000001','verify','Verificación sintética del ejercicio.',90,'00000000-0000-0000-0000-000000000101','2026-08-13T09:20:00-05:00'),
('60000000-0000-0000-0000-000000000001','publish','Publicación sintética sin datos sensibles.',90,'00000000-0000-0000-0000-000000000101','2026-08-13T09:40:00-05:00'),
('60000000-0000-0000-0000-000000000002','verify','Verificación sintética del ejercicio.',85,'00000000-0000-0000-0000-000000000101','2026-08-13T10:00:00-05:00'),
('60000000-0000-0000-0000-000000000002','publish','Publicación sintética sin datos sensibles.',85,'00000000-0000-0000-0000-000000000101','2026-08-13T10:10:00-05:00');

insert into public.need_items(id,need_case_id,category,description,quantity_required,unit,quantity_covered) values
('61000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','Agua','Botellas de agua de 1 litro',200,'unidad',89),
('61000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000002','Higiene','Kits de higiene familiar',80,'kit',24),
('61000000-0000-0000-0000-000000000003','60000000-0000-0000-0000-000000000003','Alimentos','Kits alimentarios',60,'kit',0);

insert into public.public_need_projections(id,source_need_id,event_id,category,summary,location_label,latitude,longitude,status,confidence_label,verified_at,expires_at,needed_quantity,covered_quantity,unit,published) values
('62000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Agua','Agua para albergue temporal','Medellín · zona aproximada',6.252,-75.566,'Parcialmente cubierta','Verificada por organización','2026-08-13T09:00:00-05:00','2026-12-31T23:59:59-05:00',200,89,'unidad',true),
('62000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Higiene','Kits de higiene familiar','Manizales · sector aproximado',5.066,-75.507,'Parcialmente cubierta','Verificada por organización','2026-08-13T10:10:00-05:00','2026-12-31T23:59:59-05:00',80,24,'kit',true);

-- Cada punto declara su propósito: los dos primeros reciben y despachan; el tercero solo
-- despacha, para que la demostración local cubra también ese caso.
insert into public.inventory_locations(id,event_id,organization_id,name,public_location_text,exact_address_private,cold_chain_capable,public_latitude,public_longitude,accepts_donations,dispatches_shipments) values
('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Centro de acopio Norte','Medellín · zona norte','Dirección sintética no operativa',false,6.267,-75.560,true,true),
('70000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','Centro aliado temporal','Manizales · zona centro','Dirección sintética no operativa',false,5.066,-75.507,true,true),
('70000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','Base logística temporal','Manizales · salida occidental','Dirección sintética no operativa',false,5.058,-75.530,false,true);

-- Cadena logística sintética visible para demostrar origen-destino y Realtime.
insert into public.donations(id,event_id,organization_id,kind,status,donor_tracking_code) values
-- El código sigue el formato real (DON- y 24 hexadecimales) para que sea consultable en
-- /seguimiento: un código de demostración con otro formato nunca resolvía.
('71000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','in_kind','in_transit','DON-7A1C4E2B9D6F03B85C1A47E9');

insert into public.donation_items(id,donation_id,category,description,quantity_promised,unit,quantity_received) values
('71100000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','Agua','Botellas selladas del despacho cartográfico sintético',40,'unidad',40);

insert into public.inventory_lots(id,event_id,organization_id,donation_item_id,location_id,lot_code,status,category,quantity_initial,unit,condition,received_by) values
('71200000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71100000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','LOT-DEMO-MAPA-001','reserved','Agua',40,'unidad','sellado','00000000-0000-0000-0000-000000000103');

insert into public.allocations(id,event_id,organization_id,lot_id,need_item_id,quantity,status,idempotency_key,allocated_by) values
('71300000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71200000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001',40,'dispatched','seed-map-allocation-001','00000000-0000-0000-0000-000000000103');

insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id) values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71200000-0000-0000-0000-000000000001','receipt',40,'seed-map-receipt-001','Recepción sintética para demostración cartográfica','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71200000-0000-0000-0000-000000000001','reserve',-40,'seed-map-reserve-001','Reserva sintética para necesidad pública','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71200000-0000-0000-0000-000000000001','release',40,'seed-map-release-001','Conversión sintética de reserva a despacho','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','71200000-0000-0000-0000-000000000001','dispatch',-40,'seed-map-dispatch-001','Salida sintética en tránsito','00000000-0000-0000-0000-000000000103');

-- El despacho de demostración lleva los datos de transporte que la regla de negocio exige antes
-- de salir; sin ellos no habría podido pasar a EN MOVIMIENTO.
insert into public.shipments(id,event_id,organization_id,shipment_code,status,public_destination,origin_location_id,dispatched_at,created_by,idempotency_key,transport_mode,transport_company,transport_contact_name,transport_contact_document,transport_contact_phone,transport_vehicle,transport_plate,transport_responsible) values
('71400000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','DSP-DEMO-MAPA-001','in_transit','Medellín · zona aproximada','70000000-0000-0000-0000-000000000002','2026-08-14T08:30:00-05:00','00000000-0000-0000-0000-000000000103','seed-map-shipment-001','transportadora','Transportes Sintéticos SAS','Conductor Sintético','CC-00000001','6040000000','Camión sencillo','ABC123','Marta Bodega');

insert into public.shipment_items(id,shipment_id,allocation_id,quantity) values
('71500000-0000-0000-0000-000000000001','71400000-0000-0000-0000-000000000001','71300000-0000-0000-0000-000000000001',40);

-- Existencia disponible en la bodega de Red Humanitaria Demo. Sin ella la red no tiene qué
-- ofrecer: esto es lo que las demás organizaciones del evento ven como disponibilidad
-- compartida y lo que permite recorrer SOLICITAR → AUTORIZAR → DESPACHAR → RECIBIR entre
-- dos organizaciones sin preparar nada a mano.
insert into public.donations(id,event_id,organization_id,kind,status,donor_tracking_code) values
('71000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','in_kind','received','DON-9B2D5F3C8E7A14C96D2B58FA');

insert into public.donation_items(id,donation_id,category,description,quantity_promised,unit,quantity_received) values
('71100000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000002','Agua','Agua embotellada en cajas selladas',1000,'litro',1000),
('71100000-0000-0000-0000-000000000003','71000000-0000-0000-0000-000000000002','Alimentos','Mercados familiares completos',300,'kit',300),
('71100000-0000-0000-0000-000000000004','71000000-0000-0000-0000-000000000002','Refugio','Cobijas nuevas empacadas',120,'unidad',120);

insert into public.inventory_lots(id,event_id,organization_id,donation_item_id,location_id,lot_code,status,category,quantity_initial,unit,condition,expires_on,received_by) values
('71200000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71100000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000001','LOT-DEMO-AGUA-001','available','Agua',1000,'litro','sellado','2026-12-31','00000000-0000-0000-0000-000000000103'),
('71200000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71100000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000001','LOT-DEMO-MERCADO-001','available','Alimentos',300,'kit','sellado',null,'00000000-0000-0000-0000-000000000103'),
('71200000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71100000-0000-0000-0000-000000000004','70000000-0000-0000-0000-000000000001','LOT-DEMO-COBIJA-001','available','Refugio',120,'unidad','usado',null,'00000000-0000-0000-0000-000000000103');

insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id) values
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71200000-0000-0000-0000-000000000002','receipt',1000,'seed-norte-agua','Recepción sintética en el Centro de acopio Norte','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71200000-0000-0000-0000-000000000003','receipt',300,'seed-norte-mercados','Recepción sintética en el Centro de acopio Norte','00000000-0000-0000-0000-000000000103'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','71200000-0000-0000-0000-000000000004','receipt',120,'seed-norte-cobijas','Recepción sintética en el Centro de acopio Norte','00000000-0000-0000-0000-000000000103');

insert into public.item_acceptance_rules(organization_id,event_id,category,decision,rule_text,requires_cold_chain,version,effective_from) values
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Agua','accepted','Sellada, vigente y con empaque íntegro.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Alimentos','accepted','Empaque íntegro, rotulado y con vigencia suficiente.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Higiene','accepted','Kits nuevos, cerrados y rotulados.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Refugio','accepted','Artículos nuevos o en condición apta para revisión.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Salud','accepted','Solo insumos sellados; medicamentos requieren revisión especializada.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Protección','accepted','Artículos nuevos, limpios y empacados.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Logística','accepted','Sujeto a coordinación previa de capacidad y seguridad.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Otro','accepted','Requiere descripción suficiente y validación previa.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Medicamentos abiertos','prohibited','No se aceptan medicamentos abiertos.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Cadena de frío','restricted','Este centro no tiene capacidad de cadena de frío.',true,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Agua','accepted','Sellada, vigente y con empaque íntegro.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Alimentos','accepted','Empaque íntegro, rotulado y con vigencia suficiente.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Higiene','accepted','Kits nuevos, cerrados y rotulados.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Refugio','accepted','Artículos nuevos o en condición apta para revisión.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Salud','accepted','Solo insumos sellados; medicamentos requieren revisión especializada.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Protección','accepted','Artículos nuevos, limpios y empacados.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Logística','accepted','Sujeto a coordinación previa de capacidad y seguridad.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Otro','accepted','Requiere descripción suficiente y validación previa.',false,1,'2026-08-13T00:00:00-05:00'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Cadena de frío','restricted','Este centro no tiene capacidad de cadena de frío.',true,1,'2026-08-13T00:00:00-05:00');

insert into public.funds(id,event_id,organization_id,name,verified,restrictions) values
('80000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Fondo de respuesta · sandbox',true,'Solo gastos del ejercicio; sin movimientos reales.');


-- Canal de recaudo de práctica. Se registra por la misma RPC auditada que se usaría con un
-- proveedor real —de ahí el `set_config` con la sesión de administración— para que el
-- sandbox ejercite el camino verdadero y no una fila escrita a mano. No mueve dinero: su
-- «pasarela» es una página del propio sandbox y su secreto es público a propósito, porque
-- lo único que protege es un cobro simulado. Activar un canal que sí mueve dinero exige
-- autoridad global y queda registrado con su motivo.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',true);
select public.set_payment_provider(
  null,
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '80000000-0000-0000-0000-000000000001',
  'practica', 'Pasarela de práctica', true, true,
  '{"etiqueta":"Pago simulado del sandbox","moneda":"COP"}'::jsonb,
  'secreto-de-practica-solo-para-el-sandbox-local',
  'Canal sintético del sandbox local para probar el recorrido de recaudo'
);
select set_config('request.jwt.claims','', true);

insert into public.public_metric_snapshots(event_id,metric_key,value,unit,formula,source_cut_at,reconciled,owner_role) values
('10000000-0000-0000-0000-000000000001','needs_verified',2,'casos','count(public_need_projections where published and not expired)','2026-08-13T12:00:00-05:00',true,'verifier'),
('10000000-0000-0000-0000-000000000001','units_delivered',113,'unidades','sum(covered_quantity), sin mezclar unidades en presentación detallada','2026-08-13T12:00:00-05:00',true,'auditor'),
('10000000-0000-0000-0000-000000000001','median_verification_time',74,'minutos','percentile_cont(0.5) of verified_at-created_at','2026-08-13T12:00:00-05:00',true,'verifier');
insert into public.public_metric_snapshots(event_id,metric_key,value,unit,formula,source_cut_at,reconciled,owner_role) values
('10000000-0000-0000-0000-000000000001','reconciled_balance',0,'COP','credits - debits - reversals; sandbox','2026-08-13T12:00:00-05:00',true,'treasury_approver');
