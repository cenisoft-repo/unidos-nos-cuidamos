-- G-046 · Quien verifica un aporte no podia ver su evidencia.
--
-- El aporte era visible para verificacion —su politica contempla `verifier`,
-- `event_admin` y `auditor`— pero la fotografia no: tanto `public.evidence` como el
-- bucket `evidence-private` exigian `is_org_member` de la organizacion del ALIADO, y
-- quien verifica pertenece a la organizacion que coordina, no a la que aporta.
--
-- El resultado practico es que la persona que tiene que decidir veia todo menos aquello
-- sobre lo que decide. La foto se subia, quedaba registrada, y no habia forma de mirarla.
--
-- Se alinean las tres reglas con la que ya gobierna el aporte. No se amplia a cualquiera:
-- exactamente los mismos roles del evento que ya podian leer el aporte.

drop policy if exists "org members read evidence" on public.evidence;
create policy "org members read evidence" on public.evidence
  for select to authenticated
  using (
    public.is_org_member(organization_id, event_id)
    or public.has_event_role(event_id, array['verifier','event_admin','auditor']::public.app_role[])
  );

-- El nombre original del archivo que subio la persona no lo necesita nadie para decidir:
-- lo que se revisa es la imagen. Se retira de la superficie legible en vez de repartirlo
-- junto con el resto de la fila.
--
-- Revocar una columna suelta no basta: mientras exista la concesion sobre la tabla
-- entera, la columna sigue siendo legible. Hay que retirar la de tabla y conceder las
-- columnas restantes, que es el mismo patron con el que se cerro G-021.
revoke select on public.evidence from authenticated;
grant select (
  id, event_id, organization_id, storage_path, mime_type,
  size_bytes, sha256, scan_status, sensitivity, uploaded_by, created_at
) on public.evidence to authenticated;

drop policy if exists "members read private evidence" on storage.objects;
create policy "members read private evidence" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence-private'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/'
    and (
      public.is_org_member(
        (split_part(name, '/', 2))::uuid,
        (split_part(name, '/', 1))::uuid
      )
      or public.has_event_role(
        (split_part(name, '/', 1))::uuid,
        array['verifier','event_admin','auditor']::public.app_role[]
      )
    )
  );

-- Superficie de revision. Devuelve lo justo para mirar la fotografia y decidir: la ruta
-- en el bucket, el tipo y cuando se subio. Ni el nombre original del archivo, ni quien la
-- subio, ni la huella.
create or replace function public.intake_evidence_for_review(p_intake_id uuid)
returns table(
  evidence_id uuid,
  -- `position` es palabra reservada en la lista de columnas de un RETURNS TABLE.
  evidence_position smallint,
  storage_path text,
  mime_type text,
  size_bytes bigint,
  uploaded_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    link.evidence_id,
    link.position,
    file.storage_path,
    file.mime_type,
    file.size_bytes,
    link.uploaded_at
  from public.donation_intake_evidence as link
  join public.evidence as file on file.id = link.evidence_id
  join public.donation_intakes as intake on intake.id = link.intake_id
  where link.intake_id = p_intake_id
    and link.uploaded_at is not null
    and (
      public.is_org_member(intake.organization_id, intake.event_id)
      or public.has_event_role(intake.event_id, array['verifier','event_admin','auditor']::public.app_role[])
    )
  order by link.position;
$$;

revoke all on function public.intake_evidence_for_review(uuid) from public, anon, authenticated;
grant execute on function public.intake_evidence_for_review(uuid) to authenticated;

comment on function public.intake_evidence_for_review(uuid) is
  'Evidencia fotografica de un aporte para quien lo revisa: ruta, tipo y fecha, sin nombre de archivo, autoria ni huella. Autoriza a la organizacion duenna del aporte y a los roles de verificacion del evento.';
comment on policy "members read private evidence" on storage.objects is
  'Lectura de la evidencia privada por la organizacion que la subio y por los roles de verificacion del evento, alineada con la politica del aporte que esa evidencia sustenta.';
