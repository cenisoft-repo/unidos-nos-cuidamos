-- Aliado de referencia para el resumen del aporte y fotografías privadas de soporte.
-- La organización autorizada continúa derivándose exclusivamente de la membresía activa.

insert into public.catalogs(id, key, name)
values ('50000000-0000-0000-0000-000000000009', 'reporting_allies', 'Aliados de referencia del aporte')
on conflict (key) do update set name = excluded.name;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, jsonb_build_array(
  jsonb_build_object('value','propacifico','label','PROPACIFICO'),
  jsonb_build_object('value','ace_colombia','label','ACE Colombia'),
  jsonb_build_object('value','acodres','label','ACODRES'),
  jsonb_build_object('value','cotelco','label','COTELCO'),
  jsonb_build_object('value','asocana','label','Asocaña'),
  jsonb_build_object('value','procana','label','Procaña'),
  jsonb_build_object('value','adicomex','label','Adicomex'),
  jsonb_build_object('value','analdex','label','Analdex'),
  jsonb_build_object('value','fenavi','label','Fenavi'),
  jsonb_build_object('value','fenalco','label','Fenalco'),
  jsonb_build_object('value','aciem','label','Aciem'),
  jsonb_build_object('value','aes','label','AES'),
  jsonb_build_object('value','aces','label','ACES'),
  jsonb_build_object('value','comite_intergremial_empresarial_valle','label','Comité Intergremial y Empresarial del Valle'),
  jsonb_build_object('value','camara_comercio_cali','label','Cámara de Comercio de Cali'),
  jsonb_build_object('value','andi_seccional_valle','label','ANDI – Seccional Valle'),
  jsonb_build_object('value','camacol_valle','label','Camacol Valle'),
  jsonb_build_object('value','acopi_valle','label','Acopi Valle'),
  jsonb_build_object('value','comfandi','label','Comfandi'),
  jsonb_build_object('value','comfenalco_valle','label','Comfenalco Valle'),
  jsonb_build_object('value','cruz_roja_seccional_valle','label','Cruz Roja – Seccional Valle'),
  jsonb_build_object('value','otro','label','Otro (especificar en Observaciones)')
), '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'reporting_allies'
on conflict (catalog_id, version) do nothing;

create or replace function public.donation_flow_catalogs()
returns table(key text, version integer, values_json jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (catalog.key)
    catalog.key,
    version.version,
    version.values_json
  from public.catalogs as catalog
  join public.catalog_versions as version on version.catalog_id = catalog.id
  where catalog.key = any (array[
    'donor_types', 'economic_sectors', 'donation_categories',
    'declared_donation_statuses', 'coverage_departments', 'departments', 'units',
    'reporting_allies'
  ]::text[])
    and version.effective_from <= now()
    and (version.effective_to is null or version.effective_to > now())
  order by catalog.key, version.version desc;
$$;

alter table public.donation_intakes
  add column if not exists reporting_ally_code text;

alter table public.donation_intakes
  add constraint donation_intakes_reporting_ally_code_length
  check (reporting_ally_code is null or char_length(reporting_ally_code) between 2 and 80);

-- Se conserva el contrato anterior como implementación interna. Revocar EXECUTE evita
-- que el cliente salte la validación del aliado de referencia.
alter function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) rename to submit_donation_intake_v2_catalogs_v1;

revoke all on function public.submit_donation_intake_v2_catalogs_v1(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) from public, anon, authenticated;

create or replace function public.submit_donation_intake_v2(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric,
  p_preferred_location_id uuid,
  p_reporting_context jsonb,
  p_catalog_versions jsonb,
  p_declared_category_code text
)
returns table(
  intake_id uuid,
  tracking_code text,
  status public.intake_status,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  reporting_ally text;
  submitted record;
begin
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;

  reporting_ally := nullif(btrim(context ->> 'reporting_ally'), '');
  if reporting_ally is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'reporting_allies'
      and option.value ->> 'value' = reporting_ally
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un aliado de referencia vigente';
  end if;
  if reporting_ally = 'otro' and char_length(btrim(coalesce(context ->> 'observations', ''))) < 3 then
    raise exception using errcode = '22023', message = 'Especifica el otro aliado en Observaciones';
  end if;

  select * into submitted
  from public.submit_donation_intake_v2_catalogs_v1(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    p_declared_status,
    p_items,
    p_declared_amount,
    p_preferred_location_id,
    context,
    p_catalog_versions,
    p_declared_category_code
  );

  update public.donation_intakes
  set reporting_ally_code = reporting_ally
  where id = submitted.intake_id
    and reporting_ally_code is distinct from reporting_ally;

  return query
  select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

revoke all on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean,
  text, jsonb, numeric, uuid, jsonb, jsonb, text
) to authenticated;

create table public.donation_intake_evidence (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.donation_intakes(id),
  evidence_id uuid not null unique references public.evidence(id),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  position smallint not null check (position between 1 and 3),
  uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (intake_id, position)
);

create index donation_intake_evidence_intake_idx
  on public.donation_intake_evidence(intake_id);
create index donation_intake_evidence_event_idx
  on public.donation_intake_evidence(event_id);
create index donation_intake_evidence_organization_idx
  on public.donation_intake_evidence(organization_id);

alter table public.donation_intake_evidence enable row level security;

create policy "org members read intake photo evidence"
on public.donation_intake_evidence
for select
to authenticated
using (public.is_org_member(organization_id, event_id));

grant select on public.donation_intake_evidence to authenticated;

create trigger donation_intake_evidence_audit
after insert or update or delete on public.donation_intake_evidence
for each row execute function public.audit_row_change();

create or replace function public.prepare_intake_photo_evidence(
  p_intake_id uuid,
  p_file_name_private text,
  p_mime_type text,
  p_size_bytes bigint,
  p_sha256 text
)
returns table(evidence_id uuid, storage_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  intake public.donation_intakes;
  created_evidence_id uuid := gen_random_uuid();
  created_storage_path text;
  extension text;
  next_position smallint;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión para adjuntar evidencia';
  end if;

  select * into intake
  from public.donation_intakes
  where id = p_intake_id
  for update;

  if intake.id is null then
    raise exception using errcode = '22023', message = 'El aporte indicado no existe';
  end if;
  if not public.is_org_member(intake.organization_id, intake.event_id)
     or (
       intake.submitted_by <> actor_id
       and not public.has_event_role(intake.event_id, array['verifier','event_admin']::public.app_role[])
     ) then
    raise exception using errcode = '42501', message = 'No puedes adjuntar evidencia a este aporte';
  end if;
  if p_mime_type not in ('image/jpeg', 'image/png') then
    raise exception using errcode = '22023', message = 'La evidencia fotográfica debe ser JPG o PNG';
  end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 5242880 then
    raise exception using errcode = '22023', message = 'Cada fotografía debe pesar entre 1 byte y 5 MB';
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'La huella de la fotografía no es válida';
  end if;
  if char_length(btrim(coalesce(p_file_name_private, ''))) not between 1 and 240 then
    raise exception using errcode = '22023', message = 'El nombre privado del archivo no es válido';
  end if;

  select (count(*) + 1)::smallint into next_position
  from public.donation_intake_evidence
  where intake_id = intake.id;
  if next_position > 3 then
    raise exception using errcode = '22023', message = 'Solo puedes adjuntar hasta 3 fotografías por aporte';
  end if;

  extension := case p_mime_type when 'image/jpeg' then 'jpg' else 'png' end;
  created_storage_path := concat(
    intake.event_id::text, '/', intake.organization_id::text,
    '/intakes/', intake.id::text, '/', created_evidence_id::text, '.', extension
  );

  insert into public.evidence(
    id, event_id, organization_id, storage_path, file_name_private,
    mime_type, size_bytes, sha256, scan_status, sensitivity, uploaded_by
  ) values (
    created_evidence_id, intake.event_id, intake.organization_id, created_storage_path,
    btrim(p_file_name_private), p_mime_type, p_size_bytes, lower(p_sha256),
    'pending', 'private', actor_id
  );

  insert into public.donation_intake_evidence(
    intake_id, evidence_id, event_id, organization_id, position
  ) values (
    intake.id, created_evidence_id, intake.event_id, intake.organization_id, next_position
  );

  return query select created_evidence_id, created_storage_path;
end;
$$;

create or replace function public.confirm_intake_photo_evidence(p_evidence_id uuid)
returns table(evidence_id uuid, uploaded_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  linked public.donation_intake_evidence;
  intake public.donation_intakes;
  evidence_record public.evidence;
  confirmed_at timestamptz;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión para confirmar evidencia';
  end if;

  select * into linked
  from public.donation_intake_evidence
  where donation_intake_evidence.evidence_id = p_evidence_id
  for update;
  if linked.id is null then
    raise exception using errcode = '22023', message = 'La evidencia indicada no existe';
  end if;

  select * into intake from public.donation_intakes where id = linked.intake_id;
  if not public.is_org_member(linked.organization_id, linked.event_id)
     or (
       intake.submitted_by <> actor_id
       and not public.has_event_role(linked.event_id, array['verifier','event_admin']::public.app_role[])
     ) then
    raise exception using errcode = '42501', message = 'No puedes confirmar esta evidencia';
  end if;

  select * into evidence_record from public.evidence where id = linked.evidence_id;
  if not exists (
    select 1 from storage.objects as object
    where object.bucket_id = 'evidence-private'
      and object.name = evidence_record.storage_path
  ) then
    raise exception using errcode = '22023', message = 'La fotografía todavía no fue cargada';
  end if;

  confirmed_at := coalesce(linked.uploaded_at, now());
  update public.donation_intake_evidence as intake_evidence
  set uploaded_at = confirmed_at
  where intake_evidence.id = linked.id and intake_evidence.uploaded_at is null;

  return query select linked.evidence_id, confirmed_at;
end;
$$;

revoke all on function public.prepare_intake_photo_evidence(uuid,text,text,bigint,text) from public, anon, authenticated;
revoke all on function public.confirm_intake_photo_evidence(uuid) from public, anon, authenticated;
grant execute on function public.prepare_intake_photo_evidence(uuid,text,text,bigint,text) to authenticated;
grant execute on function public.confirm_intake_photo_evidence(uuid) to authenticated;

comment on column public.donation_intakes.reporting_ally_code is
  'Aliado declarado como referencia del reporte; no concede membresía ni autorización.';
comment on table public.donation_intake_evidence is
  'Vínculo privado entre un intake y hasta tres fotografías; uploaded_at solo confirma la carga, no valida recepción o entrega.';
comment on function public.prepare_intake_photo_evidence(uuid,text,text,bigint,text) is
  'Reserva evidencia JPG/PNG privada para un intake autorizado y devuelve una ruta generada por servidor.';
comment on function public.confirm_intake_photo_evidence(uuid) is
  'Confirma que el objeto reservado existe en el bucket privado; conserva scan_status pending hasta revisión segura.';
