-- G-046 · La evidencia tiene que ser visible para quien decide sobre el aporte.
--
-- El aporte ya era legible para verificación; su fotografía no. Estas comprobaciones
-- fijan que las tres superficies —tabla, bucket y RPC de revisión— contemplen los mismos
-- roles del evento que la política del aporte, para que nadie las vuelva a separar.
begin;
select plan(9);

select has_function(
  'public', 'intake_evidence_for_review', array['uuid'],
  'Existe la superficie de revisión de evidencia'
);
select ok(
  has_function_privilege('authenticated','public.intake_evidence_for_review(uuid)','EXECUTE'),
  'La revisión de evidencia es alcanzable con sesión'
);
select ok(
  not has_function_privilege('anon','public.intake_evidence_for_review(uuid)','EXECUTE'),
  'La revisión de evidencia no es alcanzable de forma anónima'
);

-- La política de la tabla y la del bucket tienen que decir lo mismo que la del aporte.
select ok(
  (select qual::text like '%has_event_role%' from pg_catalog.pg_policies
   where schemaname='public' and tablename='evidence' and cmd='SELECT'),
  'La evidencia es legible por los roles de verificación del evento'
);
select ok(
  (select qual::text like '%is_org_member%' from pg_catalog.pg_policies
   where schemaname='public' and tablename='evidence' and cmd='SELECT'),
  'La organización que la subió la sigue viendo'
);
select ok(
  (select qual::text like '%has_event_role%' from pg_catalog.pg_policies
   where schemaname='storage' and tablename='objects' and policyname='members read private evidence'),
  'El bucket privado también admite a los roles de verificación'
);
select ok(
  (select qual::text like '%evidence-private%' from pg_catalog.pg_policies
   where schemaname='storage' and tablename='objects' and policyname='members read private evidence'),
  'La apertura se limita al bucket de evidencia y no a todo el almacenamiento'
);

-- El nombre original del archivo no hace falta para decidir y deja de repartirse.
select ok(
  not has_column_privilege('authenticated','public.evidence','file_name_private','SELECT'),
  'El nombre privado del archivo no se expone a la sesión'
);
select ok(
  has_column_privilege('authenticated','public.evidence','storage_path','SELECT'),
  'La ruta en el bucket sí, porque es lo que permite abrir la imagen'
);

select * from finish();
rollback;
