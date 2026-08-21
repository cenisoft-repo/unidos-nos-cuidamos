-- G-055 · La habilitación operativa de una organización tiene exactamente una puerta.
--
-- Qué estaba roto, medido contra la base viva antes de escribir esto:
--
--   A) `activate_ally_registration` escribía `organizations.verified = true`
--      (`202608190001:352-353`). Quien llenaba el formulario de autorregistro se concedía
--      a sí mismo la habilitación para operar, sin actor y sin sustento.
--   B) `decide_organization_verification` (`202608200003`) —la vía que ADR-013 declara
--      obligatoria— sólo sabía poner `verified = false` al rechazar. **Nunca la concedía.**
--      Es decir: la única vía que concedía la habilitación era la no auditada.
--   C) `public_collection_centers` no mira la organización en absoluto: filtra por
--      `active`, `accepts_donations` y coordenadas. Un visitante anónimo veía el punto de
--      acopio del autorregistrado —con su dirección— sin que nadie lo hubiera revisado.
--      Esta es la mitad que no pasa por `verified`, así que arreglar sólo la columna
--      habría dejado la exposición pública abierta.
--   D) `service_role` tiene INSERT y UPDATE sobre `organizations` (arranque en frío de
--      `202608160004`), y `manage_organization` aceptaba `p_verified => true` sin motivo.
--      Dos vías silenciosas más.
--
-- Lo que NO estaba roto y no se toca: el nivel de comprobación. El autorregistro ya escribía
-- `organization_verifications.state = 'email_verified'`, que es exactamente lo que ADR-013
-- pide. G-039 hizo su parte; lo que faltaba era la otra columna.
--
-- La regla que queda: `organizations.verified` sólo sube por
-- `decide_organization_verification` (decisión humana, con actor y sustento) o por
-- `bootstrap_organization_habilitation` (arranque en frío, con motivo, sólo `service_role`).
-- Cualquier otra ruta —escritura directa con privilegios de tabla incluida— la rechaza un
-- disparador, igual que `202608200002` cerró la escritura directa de SUPER_ADMIN.

-- ---------------------------------------------------------------- la puerta

-- **No** es `security definer`, y eso es la mitad del control. Con derechos del invocador,
-- `current_user` dentro del disparador es el rol que ejecuta de verdad la sentencia:
-- `service_role` o `authenticated` si viene de la API, y el dueño sólo si viene de dentro de
-- una función `security definer` de este esquema o del arranque en frío. Declararlo
-- `security definer` haría que `current_user` fuera siempre el dueño y la comprobación no
-- distinguiría nada —se escribió así primero y la prueba de la marca a mano lo destapó—.
-- PostgreSQL no exige EXECUTE sobre una función de disparador, así que no hace falta.
create or replace function public.assert_organization_habilitation_path()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Bajar la habilitación, o no tocarla, nunca necesita permiso: suspender una
  -- organización debe poder hacerse por cualquier vía administrativa ya existente.
  if not new.verified then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.verified then
    return new;
  end if;

  -- Sube. Dos condiciones, y ninguna sobra:
  --   · la marca es local a la transacción y sólo la ponen las dos funciones sancionadas;
  --   · `current_user` es el dueño de la tabla únicamente dentro de una función
  --     `security definer` de este esquema o en el arranque en frío. Una escritura directa
  --     desde la API llega como `authenticated` o `service_role` y queda fuera aunque tenga
  --     privilegios de tabla y aunque lograra poner la marca.
  -- El dueño se lee del catálogo en vez de escribirse a mano: un nombre incrustado que no
  -- coincida convertiría la comprobación en un «siempre no» o, peor, se corregiría a mano
  -- por el lado equivocado.
  if coalesce(current_setting('app.organization_habilitation', true), '') = 'on'
     and current_user = (
       select owner.relowner::regrole::text
       from pg_catalog.pg_class as owner where owner.oid = tg_relid
     ) then
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Habilitar una organización exige decide_organization_verification() con actor y sustento';
end;
$$;

drop trigger if exists organizations_habilitation_guard on public.organizations;
create trigger organizations_habilitation_guard
  before insert or update on public.organizations
  for each row execute function public.assert_organization_habilitation_path();

comment on function public.assert_organization_habilitation_path() is
  'Impide que organizations.verified pase a verdadero fuera de decide_organization_verification() o del arranque en frío. Cierra la escritura directa que service_role conserva por sus privilegios de tabla (G-055).';

-- ---------------------------------------------------------------- la vía humana

-- Cambia respecto de `202608200003`: `verify` ahora **concede** la habilitación operativa,
-- que es lo que faltaba. Los requisitos ya estaban y no se relajan —rol, sustento de cinco
-- caracteres, historial append-only, auditoría—; lo que se añade es que la decisión tenga
-- efecto sobre la columna de la que dependen `/donar`, el aporte y el mapa público.
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
  habilitation_before boolean;
  habilitation_after boolean;
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

  habilitation_before := organization.verified;
  habilitation_after := habilitation_before;

  -- G-055: verificar documentalmente es lo que habilita para operar, y es la única vía que
  -- lo hace. Rechazar la retira. `request_documents` no la mueve en ninguna dirección:
  -- pedir papeles no es ni conceder ni quitar.
  if next_state = 'verified' then
    perform set_config('app.organization_habilitation', 'on', true);
    update public.organizations set verified = true where id = p_organization_id;
    perform set_config('app.organization_habilitation', '', true);
    habilitation_after := true;
  elsif next_state = 'rejected' then
    update public.organizations set verified = false where id = p_organization_id;
    habilitation_after := false;
  end if;

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    p_event_id, p_organization_id, (select auth.uid()), 'decide_organization_verification',
    'organization_verifications', p_organization_id,
    jsonb_build_object(
      'valor_nuevo', next_state,
      'metodo', next_method,
      'sustento', btrim(p_note),
      'habilitacion_antes', habilitation_before,
      'habilitacion_despues', habilitation_after
    )
  );
  return next_state;
end;
$$;

revoke all on function public.decide_organization_verification(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.decide_organization_verification(uuid, uuid, text, text) to authenticated;

comment on function public.decide_organization_verification(uuid, uuid, text, text) is
  'Unica via humana para verificar una organizacion y, con ello, habilitarla para operar. Exige rol, sustento escrito y deja historial append-only y auditoria con el antes y el despues de la habilitacion.';

-- ---------------------------------------------------------------- el arranque en frío

-- Simétrica de `grant_super_admin`: un entorno recién provisionado no tiene todavía una
-- persona que pueda decidir, así que la herramienta de arranque necesita una vía propia.
-- Lo que no puede es mentir sobre cómo llegó: el nivel de comprobación queda en
-- `document_pending` —nadie revisó documentos— y la auditoría dice que fue configuración.
create or replace function public.bootstrap_organization_habilitation(
  p_organization_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization public.organizations;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Registra el motivo de la habilitacion de arranque';
  end if;
  select * into organization from public.organizations where id = p_organization_id;
  if organization.id is null then
    raise exception using errcode = 'P0002', message = 'La organizacion indicada no existe';
  end if;
  if organization.verified then
    return false;
  end if;

  perform set_config('app.organization_habilitation', 'on', true);
  update public.organizations set verified = true where id = p_organization_id;
  perform set_config('app.organization_habilitation', '', true);

  insert into public.organization_verifications(organization_id, state, method, decided_at)
  select p_organization_id, 'document_pending', 'bootstrap_configuration', clock_timestamp()
  where not exists (
    select 1 from public.organization_verifications as existing
    where existing.organization_id = p_organization_id
      and existing.method = 'bootstrap_configuration'
  );

  insert into public.audit_events(organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    p_organization_id, null, 'bootstrap_organization_habilitation',
    'organizations', p_organization_id,
    jsonb_build_object('motivo', btrim(p_reason), 'habilitacion_antes', false, 'habilitacion_despues', true)
  );
  return true;
end;
$$;

revoke all on function public.bootstrap_organization_habilitation(uuid, text) from public, anon, authenticated;
grant execute on function public.bootstrap_organization_habilitation(uuid, text) to service_role;

comment on function public.bootstrap_organization_habilitation(uuid, text) is
  'Habilitacion de arranque en frio para la herramienta de provision, con motivo obligatorio. Deja el nivel de comprobacion en document_pending: habilitar para operar no es haber revisado documentos.';

-- ---------------------------------------------------------------- las vías que se cierran

-- `manage_organization` deja de poder conceder la habilitación. Puede seguir creando,
-- renombrando y suspendiendo; lo que ya no puede es sustituir a la decisión de verificación,
-- porque hacerlo por aquí no dejaba motivo escrito. Bajarla sí, que es retirar permiso.
create or replace function public.manage_organization(
  p_organization_id uuid,
  p_name text,
  p_slug text,
  p_status text,
  p_verified boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_id uuid;
  normalized_slug text;
  current_verified boolean;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = 'Solo SUPER_ADMIN administra organizaciones';
  end if;
  if p_status is not null and p_status not in ('active','suspended','closed') then
    raise exception using errcode = '22023', message = 'Estado de organizacion no valido';
  end if;

  if p_organization_id is null then
    if char_length(btrim(coalesce(p_name, ''))) < 2 then
      raise exception using errcode = '22023', message = 'La organizacion necesita un nombre';
    end if;
    normalized_slug := lower(btrim(coalesce(p_slug, '')));
    if normalized_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      raise exception using errcode = '22023',
        message = 'El identificador debe ser minusculas, numeros y guiones simples';
    end if;
    if exists (select 1 from public.organizations as taken where taken.slug = normalized_slug) then
      raise exception using errcode = '22023', message = 'Ese identificador ya esta en uso';
    end if;
    -- G-055: nace sin habilitar, siempre. El parametro se conserva en la firma para no
    -- romper a quien ya la invoca, pero pedir `true` aqui es un error explicito.
    if coalesce(p_verified, false) then
      raise exception using errcode = '42501',
        message = 'Habilitar una organizacion exige decide_organization_verification() con actor y sustento';
    end if;
    insert into public.organizations(name, slug, status, verified)
    values (btrim(p_name), normalized_slug, coalesce(p_status, 'active'), false)
    returning id into organization_id;
  else
    -- El `slug` no se toca: es el identificador con el que la organizacion aparece en
    -- proyecciones publicas y enlaces ya emitidos. Renombrarlo desde aqui romperia
    -- referencias que este modulo no puede ver. Y se suspende en vez de borrar, porque una
    -- organizacion con historial no puede desaparecer sin dejar huerfanos sus aportes.
    if p_slug is not null and lower(btrim(p_slug)) is distinct from (
      select organization.slug from public.organizations as organization where organization.id = p_organization_id
    ) then
      raise exception using errcode = '22023',
        message = 'El identificador publico de una organizacion existente no se cambia';
    end if;
    select organization.verified into current_verified
    from public.organizations as organization where organization.id = p_organization_id;
    if current_verified is null then
      raise exception using errcode = 'P0002', message = 'La organizacion indicada no existe';
    end if;
    if coalesce(p_verified, current_verified) and not current_verified then
      raise exception using errcode = '42501',
        message = 'Habilitar una organizacion exige decide_organization_verification() con actor y sustento';
    end if;
    update public.organizations
    set name = coalesce(nullif(btrim(p_name), ''), name),
        status = coalesce(p_status, status),
        verified = coalesce(p_verified, verified)
    where id = p_organization_id
    returning id into organization_id;
  end if;
  return organization_id;
end;
$$;

comment on function public.manage_organization(uuid, text, text, text, boolean) is
  'Administracion de organizaciones para SUPER_ADMIN: crear, renombrar, suspender y retirar la habilitacion. Concederla no: eso exige decide_organization_verification() (G-055).';

-- ---------------------------------------------------------------- el autorregistro

-- Cambia el tipo de retorno —se añade `operational`— así que hay que soltarla antes.
-- Sin ese dato la pantalla de activación no puede decir la verdad: seguiría prometiendo
-- «ya puedes registrar aportes» a quien todavía no puede.
drop function if exists public.activate_ally_registration();

create or replace function public.activate_ally_registration()
returns table(
  registration_id uuid,
  organization_id uuid,
  organization_name text,
  platform_identifier text,
  activated_at timestamptz,
  operational boolean
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
    -- Al repetir la activación la habilitación puede haber cambiado entre medias: se lee,
    -- no se supone.
    return query
      select registration.id, registration.organization_id, organizations.name,
             registration.platform_identifier, registration.activated_at,
             organizations.verified and organizations.status = 'active'
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

  -- G-055: la organización nace **sin habilitar**. Antes se escribía `true` aquí, y eso
  -- era el autorregistro concediéndose la confianza a sí mismo: `/donar`, el aporte y el
  -- mapa público dependen de esta columna. Subirla exige `decide_organization_verification`.
  insert into public.organizations(name, slug, verified, status)
  values (registration.legal_name, organization_slug, false, 'active')
  returning * into created_org;

  -- G-039: la verificación queda escrita con su método y con su nivel reales. Confirmar
  -- el correo es `email_verified`, no `verified`: comprobar el buzón no es comprobar que
  -- la organización es quien dice ser. Elevarla exige una decisión humana, que se registra
  -- con `decide_organization_verification`.
  insert into public.organization_verifications(organization_id, state, method, decided_at, expires_at)
  values (created_org.id, 'email_verified', 'self_registration_email_confirmed', now(), now() + interval '90 days');

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
  -- lo entregado allí no podría continuar la cadena. Que exista no lo hace público: la
  -- proyección de acopios sólo publica los de organizaciones habilitadas.
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
           registration.platform_identifier, registration.activated_at, false;
end;
$$;

revoke all on function public.activate_ally_registration() from public, anon, authenticated;
grant execute on function public.activate_ally_registration() to authenticated;
comment on function public.activate_ally_registration() is
  'Paso Activación: exige correo confirmado en Auth y entrega organización + membresía ALIADO, sin habilitación para operar. Devuelve `operational` para que la interfaz no prometa lo que la organización todavía no puede hacer. Idempotente.';

-- ---------------------------------------------------------------- la exposición pública

-- La mitad del defecto que no pasaba por `verified`. Esta proyección es ejecutable por
-- `anon` y sólo miraba el punto: activo, que reciba aportes y que tenga coordenadas. La
-- organización dueña no se consultaba, así que el acopio de quien acababa de llenar un
-- formulario aparecía en el portal, en el mapa y en la exportación de transparencia, con su
-- dirección, sin que nadie lo hubiera revisado. Se comprobó contra la base viva antes de
-- cambiarlo. El resto de la función es la de `202608170002`, sin tocar.
create or replace function public.public_collection_centers(p_event_id uuid)
returns table(
  id uuid,
  name text,
  location_label text,
  accepts text[],
  restricted_items text[],
  cold_chain_capable boolean,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  with current_rules as (
    select distinct on (
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category
    )
      rule.organization_id,
      rule.event_id,
      rule.location_id,
      rule.category,
      rule.decision
    from public.item_acceptance_rules as rule
    where rule.effective_from <= now()
      and (rule.effective_to is null or rule.effective_to > now())
    order by
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category,
      rule.version desc
  ), applicable_rules as (
    select location.id as location_id, rule.category, rule.decision
    from public.inventory_locations as location
    join current_rules as rule
      on rule.organization_id = location.organization_id
      and rule.event_id = location.event_id
      and (
        rule.location_id = location.id
        or (
          rule.location_id is null
          and not exists (
            select 1 from current_rules as override
            where override.organization_id = location.organization_id
              and override.event_id = location.event_id
              and override.location_id = location.id
              and override.category = rule.category
          )
        )
      )
  )
  select
    location.id,
    location.name,
    -- Punto de acopio: su dirección exacta es la ubicación pública real.
    coalesce(nullif(btrim(location.exact_address_private), ''), location.public_location_text),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  -- G-055: decir a un donante dónde llevar su aporte es una afirmación de la plataforma
  -- sobre quien lo recibe. Sólo se publica el punto de una organización habilitada.
  join public.organizations as organization
    on organization.id = location.organization_id
    and organization.verified
    and organization.status = 'active'
  where location.event_id = p_event_id
    and location.active
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

revoke all on function public.public_collection_centers(uuid) from public;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

comment on function public.public_collection_centers(uuid) is
  'Puntos de acopio publicables: activos, que reciben aportes, con coordenada y de una organizacion habilitada para operar. Publica la direccion exacta porque un acopio es un lugar de entrega (202608170002), y por eso mismo exige que la organizacion este habilitada (G-055).';

-- ---------------------------------------------------------------- la misma regla, otra vez

-- Y aquí estaba la tercera mitad, encontrada atacando lo ya arreglado: la regla de
-- publicación de un acopio existe **dos veces**. `public_collection_centers` la calcula al
-- leer; `sync_public_collection_projection` la calcula al escribir, sobre
-- `public_logistics_projections`, que es la tabla que alimenta el mapa público y que `anon`
-- lee directamente. Las dos copias tenían las mismas tres condiciones y ninguna miraba la
-- organización, así que arreglar sólo la primera dejaba al impostor en el mapa —con su
-- etiqueta, su dirección y sus coordenadas, y con `published = true`—.
--
-- Se comprobó barriendo las diez superficies legibles por `anon` con el nombre de una
-- organización recién autorregistrada: nueve daban cero y ésta daba uno.
create or replace function public.sync_public_collection_projection(p_location_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare location public.inventory_locations;
begin
  select * into location from public.inventory_locations where id = p_location_id;
  if not found then
    update public.public_logistics_projections
    set published = false, updated_at = now()
    where source_type = 'collection_center' and source_id = p_location_id;
    return;
  end if;

  insert into public.public_logistics_projections(
    event_id, source_type, source_id, public_code, label, status,
    origin_label, origin_latitude, origin_longitude, published, updated_at
  ) values (
    location.event_id,
    'collection_center',
    location.id,
    'CAC-' || upper(right(replace(location.id::text, '-', ''), 8)),
    location.name,
    case when location.active then 'active' else 'inactive' end,
    location.public_location_text,
    location.public_latitude,
    location.public_longitude,
    location.active
      and location.accepts_donations
      and location.public_latitude is not null
      and location.public_longitude is not null
      -- G-055: misma condición que `public_collection_centers`. Un punto de acopio sólo se
      -- publica si su organización está habilitada para operar.
      and exists (
        select 1 from public.organizations as organization
        where organization.id = location.organization_id
          and organization.verified
          and organization.status = 'active'
      ),
    now()
  )
  on conflict (source_type, source_id) do update set
    event_id = excluded.event_id,
    public_code = excluded.public_code,
    label = excluded.label,
    status = excluded.status,
    origin_label = excluded.origin_label,
    origin_latitude = excluded.origin_latitude,
    origin_longitude = excluded.origin_longitude,
    published = excluded.published,
    updated_at = now();
end;
$$;

comment on function public.sync_public_collection_projection(uuid) is
  'Proyecta un punto de acopio al mapa publico. Publica solo si el punto esta activo, recibe aportes, tiene coordenada y su organizacion esta habilitada para operar (G-055).';

-- Como la proyección es una tabla y no una vista, la condición nueva sólo se evalúa cuando
-- algo escribe. Sin esto, habilitar una organización dejaría su acopio invisible en el mapa
-- hasta que alguien tocara el punto, y retirarle la habilitación lo dejaría publicado: las
-- dos mentiras, una en cada dirección.
create or replace function public.resync_organization_public_points()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  point_id uuid;
begin
  if new.verified is not distinct from old.verified
     and new.status is not distinct from old.status then
    return new;
  end if;
  for point_id in
    select location.id from public.inventory_locations as location
    where location.organization_id = new.id
  loop
    perform public.sync_public_collection_projection(point_id);
  end loop;
  return new;
end;
$$;

drop trigger if exists organizations_public_points_resync on public.organizations;
create trigger organizations_public_points_resync
  after update on public.organizations
  for each row execute function public.resync_organization_public_points();

comment on function public.resync_organization_public_points() is
  'Repropaga al mapa publico los puntos de una organizacion cuando cambia su habilitacion o su estado. Sin esto la proyeccion conservaria el valor calculado la ultima vez que se toco el punto (G-055).';

-- Compensación de lo ya proyectado: las filas escritas antes de esta migración llevan el
-- `published` de la regla vieja. Se recalculan todas con la nueva. En el sandbox sintético
-- esto no cambia nada —las organizaciones sembradas están habilitadas—, pero deja el estado
-- coherente en cualquier base donde ya hubiera un autorregistro.
select public.sync_public_collection_projection(location.id)
from public.inventory_locations as location;
