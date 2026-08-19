-- Fase 2 del loop de consolidación: una sola lógica de registro para empresa, organización,
-- ONG, fundación, entidad y persona aportante. Todas quedan bajo el mismo rol operativo
-- ALIADO (`partner_reporter`); no se crea ningún rol nuevo.
--
-- La cadena que debe quedar reconstruible es Aliado → Usuario → Organización → Donación:
-- `ally_registrations` guarda el aliado declarado, `user_id` fija la persona que lo activó,
-- `organization_id` la organización creada y las donaciones ya cuelgan de la organización.
--
-- Identificador de plataforma: se genera `alias@rutasolidaria.co` como identidad del aliado.
-- **No** es un buzón real y esta migración no provisiona correo. Separar los dos conceptos es
-- deliberado: si más adelante se decide provisionar buzones, el alias ya existe y es estable.

create type public.ally_kind as enum (
  'empresa', 'organizacion', 'ong', 'fundacion', 'entidad_publica', 'persona'
);

create type public.ally_registration_status as enum (
  'pending_email', 'activated', 'rejected'
);

create table public.ally_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  ally_kind public.ally_kind not null,
  legal_name text not null check (char_length(btrim(legal_name)) between 3 and 160),
  tax_id text not null check (char_length(btrim(tax_id)) between 5 and 40),
  responsible_name text not null check (char_length(btrim(responsible_name)) between 3 and 120),
  contact_phone text not null check (char_length(btrim(contact_phone)) between 7 and 30),
  contact_email text not null check (contact_email = lower(contact_email) and contact_email like '%@%'),
  public_location_text text not null check (char_length(btrim(public_location_text)) between 4 and 120),
  public_latitude numeric(9,6),
  public_longitude numeric(9,6),
  platform_username text not null unique check (platform_username ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  platform_identifier text not null unique,
  status public.ally_registration_status not null default 'pending_email',
  user_id uuid references auth.users(id),
  organization_id uuid references public.organizations(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  activated_at timestamptz,
  unique (event_id, contact_email)
);

create index ally_registrations_event_status_idx
  on public.ally_registrations (event_id, status);
create index ally_registrations_user_idx
  on public.ally_registrations (user_id) where user_id is not null;
create index ally_registrations_organization_idx
  on public.ally_registrations (organization_id) where organization_id is not null;

create trigger ally_registrations_updated_at
  before update on public.ally_registrations
  for each row execute function public.set_updated_at();

create trigger ally_registrations_audit
  after insert or update or delete on public.ally_registrations
  for each row execute function public.audit_row_change();

alter table public.ally_registrations enable row level security;
revoke all on table public.ally_registrations from public, anon, authenticated;
grant select on table public.ally_registrations to authenticated;

-- Cada persona ve su propio registro. Verificación y administración del evento lo ven para
-- poder responder por la trazabilidad del aliado; nadie más alcanza NIT, teléfono ni responsable.
create policy "owners read own ally registration"
  on public.ally_registrations for select to authenticated
  using (user_id = (select auth.uid()));

create policy "event verification reads ally registrations"
  on public.ally_registrations for select to authenticated
  using (public.has_event_role(event_id, array['verifier','event_admin']::public.app_role[]));

comment on table public.ally_registrations is
  'Registro único de aliados (empresa/ONG/fundación/entidad/persona) con su identificador de plataforma; no provisiona buzón de correo.';
comment on column public.ally_registrations.platform_identifier is
  'Identificador del aliado en el dominio de la plataforma. Es una identidad, no un buzón real.';
comment on column public.ally_registrations.status is
  'pending_email hasta que la persona confirma el correo; activated cuando ya existe organización y membresía ALIADO.';

-- El dominio vive en un solo lugar para que cambiarlo no implique tocar la lógica de registro.
create or replace function public.platform_identity_domain()
returns text language sql immutable set search_path = '' as $$
  select 'rutasolidaria.co'::text;
$$;

-- Convierte una razón social en un alias estable y legible. No usa `unaccent` para no
-- depender de una extensión adicional en el proyecto remoto.
create or replace function public.build_platform_username(p_source text, p_taken_from uuid default null)
returns text language plpgsql stable set search_path = '' as $$
declare
  base text;
  candidate text;
  suffix integer := 1;
begin
  base := lower(btrim(coalesce(p_source, '')));
  base := translate(base, 'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc');
  base := regexp_replace(base, '[^a-z0-9]+', '-', 'g');
  base := btrim(base, '-');
  base := left(base, 40);
  base := btrim(base, '-');
  if base = '' then
    base := 'aliado';
  end if;

  candidate := base;
  while exists (
    select 1 from public.ally_registrations as taken
    where taken.platform_username = candidate
      and (p_taken_from is null or taken.id <> p_taken_from)
  ) loop
    suffix := suffix + 1;
    candidate := left(base, 36) || '-' || suffix::text;
  end loop;
  return candidate;
end;
$$;

-- Paso 1 del recorrido: Registro. Se ejecuta antes de crear la identidad en Auth para que un
-- dato inválido no deje una cuenta huérfana. No otorga ningún permiso por sí solo.
create or replace function public.register_ally(
  p_event_id uuid,
  p_ally_kind public.ally_kind,
  p_legal_name text,
  p_tax_id text,
  p_responsible_name text,
  p_contact_phone text,
  p_contact_email text,
  p_public_location_text text,
  p_public_latitude numeric,
  p_public_longitude numeric,
  p_bot_field text default null
)
returns table(registration_id uuid, platform_identifier text, status public.ally_registration_status)
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_headers jsonb := '{}'::jsonb;
  source_hint text;
  rate_bucket text;
  rate_window timestamptz;
  accepted_count integer;
  normalized_email text := lower(btrim(coalesce(p_contact_email, '')));
  normalized_name text := btrim(coalesce(p_legal_name, ''));
  normalized_tax text := upper(regexp_replace(coalesce(p_tax_id, ''), '[^A-Za-z0-9-]', '', 'g'));
  normalized_phone text := btrim(coalesce(p_contact_phone, ''));
  normalized_responsible text := btrim(coalesce(p_responsible_name, ''));
  normalized_zone text := btrim(coalesce(p_public_location_text, ''));
  existing public.ally_registrations;
  created public.ally_registrations;
  username text;
begin
  if nullif(btrim(coalesce(p_bot_field, '')), '') is not null then
    raise exception using errcode = '22023', message = 'No fue posible procesar el registro';
  end if;
  if not exists (
    select 1 from public.emergency_events as event
    where event.id = p_event_id and event.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'El evento no está disponible para registros';
  end if;
  if char_length(normalized_name) < 3 or char_length(normalized_name) > 160 then
    raise exception using errcode = '22023', message = 'Escribe el nombre o razón social (3 a 160 caracteres)';
  end if;
  if public.contains_sensitive_content(normalized_name) then
    raise exception using errcode = '22023', message = 'El nombre o razón social no puede incluir teléfonos, cuentas ni enlaces';
  end if;
  if char_length(normalized_tax) < 5 or char_length(normalized_tax) > 40 then
    raise exception using errcode = '22023', message = 'Escribe la identificación o NIT del aliado';
  end if;
  if char_length(normalized_responsible) < 3 or char_length(normalized_responsible) > 120 then
    raise exception using errcode = '22023', message = 'Escribe el nombre del responsable';
  end if;
  if normalized_phone !~ '^[0-9+()\s-]{7,30}$' then
    raise exception using errcode = '22023', message = 'Escribe un teléfono de contacto válido';
  end if;
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception using errcode = '22023', message = 'Escribe un correo de contacto válido';
  end if;
  if char_length(normalized_zone) < 4 or char_length(normalized_zone) > 120 then
    raise exception using errcode = '22023', message = 'Escribe la zona pública desde la que entregas (municipio y sector amplio)';
  end if;
  if public.contains_sensitive_content(normalized_zone) then
    raise exception using errcode = '22023', message = 'La zona pública no puede incluir teléfonos, cuentas ni enlaces';
  end if;
  if (p_public_latitude is null) <> (p_public_longitude is null) then
    raise exception using errcode = '22023', message = 'La coordenada aproximada necesita latitud y longitud';
  end if;
  if p_public_latitude is not null
     and (p_public_latitude not between -90 and 90 or p_public_longitude not between -180 and 180) then
    raise exception using errcode = '22023', message = 'La coordenada aproximada no es válida';
  end if;

  begin
    request_headers := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  exception when others then
    request_headers := '{}'::jsonb;
  end;
  source_hint := left(
    lower(btrim(coalesce(
      nullif(request_headers ->> 'cf-connecting-ip', ''),
      nullif(split_part(request_headers ->> 'x-forwarded-for', ',', 1), ''),
      nullif(request_headers ->> 'x-real-ip', ''),
      'direct-client'
    ))),
    128
  );
  rate_bucket := encode(extensions.digest(source_hint || '|' || p_event_id::text, 'sha256'), 'hex');
  rate_window := date_bin(interval '10 minutes', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00');

  insert into public.anonymous_rate_limits as limits (action, bucket_hash, window_started_at, request_count)
  values ('register_ally', rate_bucket, rate_window, 1)
  on conflict (action, bucket_hash, window_started_at)
  do update set request_count = limits.request_count + 1, updated_at = now()
  where limits.request_count < 5
  returning limits.request_count into accepted_count;

  if accepted_count is null then
    raise exception using
      errcode = 'P0001',
      message = 'Se alcanzó el límite temporal de registros. Intenta de nuevo en unos minutos';
  end if;

  select * into existing
  from public.ally_registrations as registration
  where registration.event_id = p_event_id
    and registration.contact_email = normalized_email
  for update;

  if existing.id is not null then
    if existing.status = 'activated' then
      raise exception using
        errcode = '22023',
        message = 'Ese correo ya tiene una cuenta ALIADO activa. Ingresa con tu contraseña';
    end if;
    update public.ally_registrations
    set ally_kind = p_ally_kind,
        legal_name = normalized_name,
        tax_id = normalized_tax,
        responsible_name = normalized_responsible,
        contact_phone = normalized_phone,
        public_location_text = normalized_zone,
        public_latitude = p_public_latitude,
        public_longitude = p_public_longitude,
        status = 'pending_email'
    where id = existing.id
    returning * into created;
    return query select created.id, created.platform_identifier, created.status;
    return;
  end if;

  username := public.build_platform_username(normalized_name);
  insert into public.ally_registrations(
    event_id, ally_kind, legal_name, tax_id, responsible_name,
    contact_phone, contact_email, public_location_text, public_latitude, public_longitude,
    platform_username, platform_identifier
  ) values (
    p_event_id, p_ally_kind, normalized_name, normalized_tax, normalized_responsible,
    normalized_phone, normalized_email, normalized_zone, p_public_latitude, p_public_longitude,
    username, username || '@' || public.platform_identity_domain()
  )
  returning * into created;

  return query select created.id, created.platform_identifier, created.status;
end;
$$;

revoke all on function public.register_ally(uuid, public.ally_kind, text, text, text, text, text, text, numeric, numeric, text)
  from public, anon, authenticated;
grant execute on function public.register_ally(uuid, public.ally_kind, text, text, text, text, text, text, numeric, numeric, text)
  to anon, authenticated;
comment on function public.register_ally(uuid, public.ally_kind, text, text, text, text, text, text, numeric, numeric, text) is
  'Paso Registro: guarda el aliado declarado y reserva su identificador. No crea usuario, organización ni permiso alguno.';

-- Paso 3 del recorrido: Activación. Es la única puerta que entrega el rol ALIADO y exige que
-- Auth ya haya confirmado el correo. Es idempotente: repetirla devuelve la misma organización.
create or replace function public.activate_ally_registration()
returns table(
  registration_id uuid,
  organization_id uuid,
  organization_name text,
  platform_identifier text,
  activated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_email text;
  confirmed_at timestamptz;
  registration public.ally_registrations;
  created_org public.organizations;
  organization_slug text;
  ally_point uuid;
  in_kind_category text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión para activar la cuenta';
  end if;

  select lower(users.email), users.email_confirmed_at
  into actor_email, confirmed_at
  from auth.users as users
  where users.id = actor_id;

  if actor_email is null then
    raise exception using errcode = 'P0002', message = 'La cuenta no tiene correo asociado';
  end if;
  if confirmed_at is null then
    raise exception using
      errcode = '42501',
      message = 'Confirma el correo desde el mensaje que te enviamos antes de activar la cuenta ALIADO';
  end if;

  select * into registration
  from public.ally_registrations as candidate
  where candidate.contact_email = actor_email
  order by candidate.created_at desc
  limit 1
  for update;

  if registration.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'No encontramos un registro de aliado para este correo. Completa el formulario de registro';
  end if;
  if registration.status = 'rejected' then
    raise exception using errcode = '42501', message = 'Este registro fue rechazado por el equipo de verificación';
  end if;
  if registration.status = 'activated' then
    if registration.user_id is distinct from actor_id then
      raise exception using errcode = '42501', message = 'Ese registro pertenece a otra cuenta';
    end if;
    return query
      select registration.id, registration.organization_id, organizations.name,
             registration.platform_identifier, registration.activated_at
      from public.organizations as organizations
      where organizations.id = registration.organization_id;
    return;
  end if;

  organization_slug := registration.platform_username;
  if exists (select 1 from public.organizations as taken where taken.slug = organization_slug) then
    -- El identificador de plataforma ya es único; basta con anexarle el registro para
    -- desempatar frente a una organización creada por otro camino (bootstrap, semilla).
    organization_slug := left(registration.platform_username, 33) || '-' || left(replace(registration.id::text, '-', ''), 6);
  end if;

  insert into public.organizations(name, slug, verified, status)
  values (registration.legal_name, organization_slug, true, 'active')
  returning * into created_org;

  -- La verificación queda escrita con su método real: correo confirmado, no revisión documental.
  -- Elevarla a verificación documental del NIT es una decisión externa, no de esta migración.
  insert into public.organization_verifications(organization_id, state, method, decided_at, expires_at)
  values (created_org.id, 'verified', 'self_registration_email_confirmed', now(), now() + interval '90 days');

  insert into public.memberships(user_id, organization_id, event_id, role, active)
  values (actor_id, created_org.id, registration.event_id, 'partner_reporter', true)
  -- `organization_id` tambien es columna de la tabla que devuelve esta funcion, asi que
  -- inferir el conflicto por nombre de columna es ambiguo (42702). Se nombra la restriccion.
  on conflict on constraint memberships_user_id_organization_id_event_id_role_key
  do update set active = true;

  -- La operación administra el punto del aliado igual que administra los suyos: sin estas
  -- membresías, lo que el aliado entrega quedaría almacenado y sin nadie que pueda moverlo.
  insert into public.memberships(user_id, organization_id, event_id, role)
  select distinct existing.user_id, created_org.id, registration.event_id, existing.role
  from public.memberships as existing
  where existing.event_id = registration.event_id
    and existing.active
    and existing.role in ('event_admin','warehouse_operator','logistics_operator')
  on conflict on constraint memberships_user_id_organization_id_event_id_role_key do nothing;

  -- El punto nace habilitado para recibir y para entregar a la operación: si solo recibiera,
  -- lo entregado allí no podría continuar la cadena.
  insert into public.inventory_locations(
    event_id, organization_id, name, public_location_text, exact_address_private,
    public_instructions, public_latitude, public_longitude, cold_chain_capable,
    active, accepts_donations, dispatches_shipments
  ) values (
    registration.event_id, created_org.id, 'Acopio ' || created_org.name,
    registration.public_location_text, null,
    'Coordina el horario después de recibir tu código APO.',
    registration.public_latitude, registration.public_longitude, false,
    true, true, true
  )
  returning id into ally_point;

  for in_kind_category in
    select distinct option.value ->> 'parent_category'
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'donation_categories'
      and option.value ->> 'kind' = 'in_kind'
      and option.value ->> 'parent_category' is not null
  loop
    insert into public.item_acceptance_rules(
      organization_id, event_id, location_id, category, decision, rule_text,
      requires_cold_chain, version, effective_from
    ) values (
      created_org.id, registration.event_id, ally_point, in_kind_category, 'accepted',
      'Categoría habilitada en la parametrización inicial del aliado.', false, 1, now()
    );
  end loop;

  update public.ally_registrations
  set status = 'activated',
      user_id = actor_id,
      organization_id = created_org.id,
      activated_at = now()
  where id = registration.id
  returning * into registration;

  return query
    select registration.id, created_org.id, created_org.name,
           registration.platform_identifier, registration.activated_at;
end;
$$;

revoke all on function public.activate_ally_registration() from public, anon, authenticated;
grant execute on function public.activate_ally_registration() to authenticated;
comment on function public.activate_ally_registration() is
  'Paso Activación: exige correo confirmado en Auth y entrega organización + membresía ALIADO. Idempotente.';

-- Lectura mínima para que la interfaz sepa en qué paso está la persona sin exponer el registro
-- completo de otra cuenta.
create or replace function public.my_ally_registration()
returns table(
  registration_id uuid,
  legal_name text,
  ally_kind public.ally_kind,
  platform_identifier text,
  status public.ally_registration_status,
  email_confirmed boolean,
  organization_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_email text;
  confirmed_at timestamptz;
begin
  if actor_id is null then
    return;
  end if;
  select lower(users.email), users.email_confirmed_at
  into actor_email, confirmed_at
  from auth.users as users
  where users.id = actor_id;

  return query
  select registration.id, registration.legal_name, registration.ally_kind,
         registration.platform_identifier, registration.status,
         confirmed_at is not null, registration.organization_id
  from public.ally_registrations as registration
  where registration.contact_email = actor_email
     or registration.user_id = actor_id
  order by registration.created_at desc
  limit 1;
end;
$$;

revoke all on function public.my_ally_registration() from public, anon, authenticated;
grant execute on function public.my_ally_registration() to authenticated;
comment on function public.my_ally_registration() is
  'Estado del registro de aliado de quien consulta, para orientar el recorrido de confirmación y activación.';
