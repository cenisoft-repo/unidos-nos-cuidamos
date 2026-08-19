-- G-039 · Confirmar un correo no es verificar una organizacion.
--
-- El autorregistro dejaba `organization_verifications.state = 'verified'` en cuanto la
-- persona confirmaba su correo. Eso mezcla dos hechos distintos: que el buzon existe y
-- que la organizacion es quien dice ser. La consecuencia practica es que nadie podia
-- distinguir una organizacion comprobada documentalmente de una que solo abrio un correo,
-- porque ambas quedaban escritas igual.
--
-- Aqui NO se implementa la verificacion documental: eso es politica de aceptacion (G-003)
-- y decision humana. Lo que se corrige es el modelo, para que cuando esa politica exista
-- tenga donde escribirse y para que hoy el estado diga la verdad.
--
--   REGISTERED          ally_registrations.status = 'pending_email'
--   EMAIL_VERIFIED      organization_verifications.state = 'email_verified'
--   DOCUMENT_PENDING    organization_verifications.state = 'document_pending'
--   ORGANIZATION_VERIFIED  organization_verifications.state = 'verified'
--   REJECTED            organization_verifications.state = 'rejected'
--
-- `organizations.verified` sigue significando lo que siempre significo: habilitada para
-- operar. No se toca, porque de el dependen las RPC del aporte. Lo que cambia es que ya
-- no se confunde con el nivel de comprobacion, que ahora vive en su propia tabla.

alter table public.organization_verifications
  drop constraint if exists organization_verifications_state_check;
alter table public.organization_verifications
  add constraint organization_verifications_state_check
  check (state in ('pending','email_verified','document_pending','verified','rejected','expired'));

comment on column public.organization_verifications.state is
  'Nivel de comprobacion de la organizacion: pending, email_verified (solo buzon), document_pending (documentos solicitados), verified (comprobacion documental), rejected, expired. No confundir con organizations.verified, que es la habilitacion para operar.';
comment on column public.organization_verifications.method is
  'Como se comprobo: self_registration_email_confirmed, document_reviewed, manual_review. El metodo explica el estado.';

-- Estado vigente por organizacion, que es lo que una consola necesita leer.
create or replace function public.organization_verification_status(p_event_id uuid)
returns table(
  organization_id uuid,
  organization_name text,
  operational boolean,
  verification_state text,
  verification_method text,
  decided_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    organization.id,
    organization.name,
    organization.verified and organization.status = 'active',
    coalesce(latest.state, 'pending'),
    latest.method,
    latest.decided_at,
    latest.expires_at
  from public.organizations as organization
  left join lateral (
    select verification.state, verification.method, verification.decided_at, verification.expires_at
    from public.organization_verifications as verification
    where verification.organization_id = organization.id
    -- `created_at` es la hora de la transaccion: dos decisiones seguidas la comparten y
    -- el orden quedaria al azar. `decided_at` se escribe con `clock_timestamp()`, que si
    -- avanza dentro de la misma transaccion, y es ademas el dato que interesa.
    order by verification.decided_at desc nulls last, verification.created_at desc
    limit 1
  ) as latest on true
  where public.is_super_admin()
     or public.has_any_role(organization.id, p_event_id, array['event_admin','verifier']::public.app_role[])
  order by organization.name;
$$;

revoke all on function public.organization_verification_status(uuid) from public, anon, authenticated;
grant execute on function public.organization_verification_status(uuid) to authenticated;

-- La decision de verificacion es humana y auditable. No la toma el autorregistro.
create or replace function public.decide_organization_verification(
  p_organization_id uuid,
  p_event_id uuid,
  p_decision text,
  p_note text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_state text;
  next_method text;
  organization public.organizations;
begin
  if not (
    public.is_super_admin()
    or public.has_any_role(p_organization_id, p_event_id, array['event_admin','verifier']::public.app_role[])
  ) then
    raise exception using errcode = '42501', message = 'No puedes decidir la verificacion de esta organizacion';
  end if;
  select * into organization from public.organizations where id = p_organization_id;
  if organization.id is null then
    raise exception using errcode = 'P0002', message = 'La organizacion indicada no existe';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Registra el sustento de la decision';
  end if;

  next_state := case p_decision
    when 'request_documents' then 'document_pending'
    when 'verify' then 'verified'
    when 'reject' then 'rejected'
    else null end;
  if next_state is null then
    raise exception using errcode = '22023', message = 'Decision de verificacion no valida';
  end if;
  next_method := case p_decision when 'verify' then 'document_reviewed' else 'manual_review' end;

  insert into public.organization_verifications(
    organization_id, state, method, decided_by, decided_at, expires_at
  ) values (
    p_organization_id, next_state, next_method, (select auth.uid()), clock_timestamp(),
    case when next_state = 'verified' then now() + interval '365 days' else null end
  );

  -- Rechazar retira la habilitacion operativa; los demas estados no la conceden ni la
  -- quitan, porque comprobar documentos y poder operar son decisiones distintas.
  if next_state = 'rejected' then
    update public.organizations set verified = false where id = p_organization_id;
  end if;

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    p_event_id, p_organization_id, (select auth.uid()), 'decide_organization_verification',
    'organization_verifications', p_organization_id,
    jsonb_build_object('valor_nuevo', next_state, 'metodo', next_method, 'sustento', btrim(p_note))
  );
  return next_state;
end;
$$;

revoke all on function public.decide_organization_verification(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.decide_organization_verification(uuid, uuid, text, text) to authenticated;

comment on function public.organization_verification_status(uuid) is
  'Nivel de comprobacion vigente por organizacion, separado de su habilitacion para operar.';
comment on function public.decide_organization_verification(uuid, uuid, text, text) is
  'Registra una decision humana de verificacion (solicitar documentos, verificar, rechazar) sin borrar la anterior; el autorregistro nunca alcanza el estado verificado.';

-- Las organizaciones sembradas por el bootstrap no tienen fila de verificacion: se les
-- escribe la que corresponde a como fueron creadas, que es una decision de configuracion,
-- no una comprobacion documental.
insert into public.organization_verifications(organization_id, state, method, decided_at)
select organization.id, 'document_pending', 'manual_review', now()
from public.organizations as organization
where not exists (
  select 1 from public.organization_verifications as existing
  where existing.organization_id = organization.id
);
