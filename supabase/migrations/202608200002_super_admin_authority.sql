-- Autoridad global de SUPER_ADMIN.
--
-- Regla de diseno (Fase 8 del loop): SUPER_ADMIN no es un bypass. No desactiva RLS, no
-- escribe inventario directamente y no tiene una segunda logica de negocio. Tiene mas
-- ALCANCE sobre exactamente las mismas reglas: pasa las mismas compuertas que un
-- administrador, solo que sin quedar acotado a una organizacion, un evento o una bodega.
-- Por eso el cambio se concentra en las cuatro funciones de compuerta y en las pocas
-- politicas que no pasan por ellas, y no se toca ninguna RPC de operacion.

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.memberships as membership
    where membership.user_id = (select auth.uid())
      and membership.active
      and membership.role = 'super_admin'
  );
$$;

revoke all on function public.is_super_admin() from public, anon, authenticated;
grant execute on function public.is_super_admin() to authenticated;
comment on function public.is_super_admin() is
  'Autoridad global del aplicativo. La concesion vive en memberships como cualquier otro rol; la organizacion y el evento de esa fila no acotan el alcance.';

-- Las cuatro compuertas. Cada una conserva su regla original y le suma el alcance global.
create or replace function public.is_org_member(target_org uuid, target_event uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_super_admin() or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.organization_id = target_org and m.active
      and (target_event is null or m.event_id = target_event)
  );
$$;

create or replace function public.has_any_role(target_org uuid, target_event uuid, allowed_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_super_admin() or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.organization_id = target_org
      and m.event_id = target_event and m.active and m.role = any(allowed_roles)
  );
$$;

create or replace function public.has_event_role(target_event uuid, allowed_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_super_admin() or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.event_id = target_event
      and m.active and m.role = any(allowed_roles)
  );
$$;

create or replace function public.has_location_scope(p_location_id uuid, allowed_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_super_admin() or exists (
    select 1
    from public.inventory_locations as location
    join public.memberships as membership
      on membership.organization_id = location.organization_id
     and membership.event_id = location.event_id
    where location.id = p_location_id
      and membership.user_id = (select auth.uid())
      and membership.active
      and membership.role = any(allowed_roles)
      and (
        not exists (
          select 1 from public.membership_locations as scope
          where scope.membership_id = membership.id
        )
        or exists (
          select 1 from public.membership_locations as scope
          where scope.membership_id = membership.id
            and scope.location_id = location.id
        )
      )
  );
$$;

-- Politicas que no pasan por las compuertas y que la consola global necesita leer.
drop policy if exists "users read own memberships" on public.memberships;
create policy "users read own memberships" on public.memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_super_admin());

drop policy if exists "members read own location scope" on public.membership_locations;
create policy "members read own location scope" on public.membership_locations
  for select to authenticated
  using (
    public.is_super_admin() or exists (
      select 1 from public.memberships as membership
      where membership.id = membership_locations.membership_id
        and membership.user_id = (select auth.uid())
    )
  );

drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_super_admin());

drop policy if exists "auditors read audit" on public.audit_events;
create policy "auditors read audit" on public.audit_events
  for select to authenticated
  using (
    public.is_super_admin() or exists (
      select 1 from public.memberships m
      where m.user_id = (select auth.uid()) and m.active
        and m.role = any(array['auditor','event_admin']::public.app_role[])
        and (audit_events.event_id is null or m.event_id = audit_events.event_id)
    )
  );

-- El historial completo de catalogos, no solo la version vigente.
drop policy if exists "public reads catalog versions" on public.catalog_versions;
create policy "public reads catalog versions" on public.catalog_versions
  for select
  using (
    (effective_from <= now() and (effective_to is null or effective_to > now()))
    or public.is_super_admin()
  );

-- ---------------------------------------------------------------------------
-- Auditoria del parametrizador (Fase 11 del loop).
--
-- No se crea una segunda auditoria: se reutiliza `audit_events`, que ya guarda actor,
-- accion, entidad, id de entidad y fecha, y ya es inmutable. Lo unico que le faltaba
-- para «quien cambio que y cuando» era el valor anterior y el nuevo.
--
-- Ese detalle NO se activa para todas las tablas: la mayoria de las auditadas guardan
-- datos personales (nombre del donante, contacto, direccion exacta) y copiarlos a
-- `audit_events` seria una fuga. Se activa por tabla, pasando 'with_values' como
-- argumento del disparador, y aun asi se excluye toda columna cuyo nombre termine en
-- `_private` o que este en la lista de campos sensibles.
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  changed text[];
  v_event uuid;
  v_org uuid;
  v_metadata jsonb;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
  v_field text;
  sensitive constant text[] := array['contact_private','exact_address_private','donor_name_private','metadata'];
begin
  if tg_op = 'UPDATE' then
    select array_agg(n.key order by n.key) into changed
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o using (key)
    where n.value is distinct from o.value;
  else
    changed := array[tg_op];
  end if;

  v_event := case when payload ? 'event_id' and payload->>'event_id' is not null then (payload->>'event_id')::uuid else null end;
  v_org := case when payload ? 'organization_id' and payload->>'organization_id' is not null then (payload->>'organization_id')::uuid else null end;

  -- Tablas hijas sin columnas de tenant: se deriva del padre para no dejar auditoría huérfana.
  if v_event is null then
    if tg_table_name = 'need_verifications' then
      select need.event_id, need.organization_id into v_event, v_org
      from public.need_cases as need where need.id = (payload->>'need_case_id')::uuid;
    elsif tg_table_name = 'intake_verification_decisions' then
      select intake.event_id, intake.organization_id into v_event, v_org
      from public.donation_intakes as intake where intake.id = (payload->>'intake_id')::uuid;
    elsif tg_table_name = 'receipts' then
      select donation.event_id, donation.organization_id into v_event, v_org
      from public.donations as donation where donation.id = (payload->>'donation_id')::uuid;
    elsif tg_table_name = 'deliveries' then
      select shipment.event_id, shipment.organization_id into v_event, v_org
      from public.shipments as shipment where shipment.id = (payload->>'shipment_id')::uuid;
    elsif tg_table_name in ('expense_approvals', 'expense_payments') then
      select request.event_id, request.organization_id into v_event, v_org
      from public.expense_requests as request where request.id = (payload->>'expense_request_id')::uuid;
    elsif tg_table_name = 'membership_locations' then
      select membership.event_id, membership.organization_id into v_event, v_org
      from public.memberships as membership where membership.id = (payload->>'membership_id')::uuid;
    end if;
  end if;

  v_metadata := jsonb_build_object('changed_fields', to_jsonb(coalesce(changed, '{}'::text[])));

  if tg_nargs > 0 and tg_argv[0] = 'with_values' then
    foreach v_field in array coalesce(changed, '{}'::text[])
    loop
      if v_field = any(array['INSERT','UPDATE','DELETE'])
         or v_field like '%\_private' or v_field = any(sensitive) then
        continue;
      end if;
      if tg_op <> 'INSERT' then
        v_before := v_before || jsonb_build_object(v_field, to_jsonb(old) -> v_field);
      end if;
      if tg_op <> 'DELETE' then
        v_after := v_after || jsonb_build_object(v_field, to_jsonb(new) -> v_field);
      end if;
    end loop;
    -- En alta y baja el detalle util es la fila entera menos lo sensible.
    if tg_op in ('INSERT','DELETE') then
      select coalesce(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
      into v_metadata
      from jsonb_each(payload) as entry
      where entry.key not like '%\_private' and entry.key <> all(sensitive);
      v_metadata := jsonb_build_object(
        'changed_fields', to_jsonb(coalesce(changed, '{}'::text[])),
        case when tg_op = 'INSERT' then 'valor_nuevo' else 'valor_anterior' end, v_metadata
      );
    else
      v_metadata := v_metadata
        || jsonb_build_object('valor_anterior', v_before, 'valor_nuevo', v_after);
    end if;
  end if;

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    v_event,
    v_org,
    (select auth.uid()), lower(tg_op), tg_table_name,
    case when payload ? 'id' then (payload->>'id')::uuid else null end,
    v_metadata
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Las tablas que administra el parametrizador pasan a estar auditadas con antes/despues.
-- `membership_locations` no tiene columna `id`: se audita por su membresia.
drop trigger if exists memberships_audit on public.memberships;
create trigger memberships_audit
  after insert or update or delete on public.memberships
  for each row execute function public.audit_row_change('with_values');

drop trigger if exists membership_locations_audit on public.membership_locations;
create trigger membership_locations_audit
  after insert or update or delete on public.membership_locations
  for each row execute function public.audit_row_change('with_values');

drop trigger if exists organizations_audit on public.organizations;
create trigger organizations_audit
  after insert or update or delete on public.organizations
  for each row execute function public.audit_row_change('with_values');

-- `catalog_versions` no lleva disparador a proposito: su unico escritor es
-- `manage_catalog_values`, que ya deja un registro completo —motivo, versiones, antes y
-- despues emparejados—. Anadirlo guardaria el mismo `values_json` dos veces.

-- ---------------------------------------------------------------------------
-- Concesion de SUPER_ADMIN: operacion privilegiada, nunca desde el cliente.
--
-- Restriccion critica de la Fase 7: nadie puede otorgarse SUPER_ADMIN a si mismo ni
-- escalar su rol desde el navegador. Se sostiene en tres capas que ya existen:
--   1. `memberships` no tiene politica de INSERT ni de UPDATE, asi que ningun cliente
--      escribe roles directamente por PostgREST;
--   2. la unica RPC que asigna roles (`assign_membership_role`) rechaza `super_admin`
--      y rechaza actuar sobre uno mismo;
--   3. conceder `super_admin` solo es posible por esta funcion, revocada para `anon` y
--      `authenticated`, que solo alcanza `service_role`.
-- El JWT no interviene: el rol se lee de la tabla, no de un claim manipulable.
-- La escritura directa de una membresia SUPER_ADMIN queda cerrada por disparador.
-- `202608160004` concede INSERT y UPDATE sobre `memberships` a `service_role` para el
-- arranque en frio, asi que sin esta guardia la autoridad global podia escribirse a mano,
-- sin motivo, sin actor y sin auditoria: la via sancionada habria sido la dificil y la
-- silenciosa la facil.
create or replace function public.assert_super_admin_grant_path()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La marca es local a la transaccion y solo la ponen `grant_super_admin` y
  -- `revoke_super_admin`. Cualquier otra ruta —incluida una escritura directa con
  -- `service_role`, que tiene INSERT y UPDATE sobre esta tabla— queda bloqueada.
  if coalesce(current_setting('app.super_admin_grant', true), '') = 'on' then
    return new;
  end if;
  -- El orden importa para que cada mensaje diga la verdad: alterar una membresia que ya
  -- es SUPER_ADMIN no es «concederla», y con la comprobacion al reves ese caso caia
  -- siempre en el primer mensaje.
  if tg_op = 'UPDATE' and old.role = 'super_admin' then
    raise exception using
      errcode = '42501',
      message = 'La membresia SUPER_ADMIN no se modifica por escritura directa';
  end if;
  if new.role = 'super_admin' then
    raise exception using
      errcode = '42501',
      message = 'SUPER_ADMIN solo se concede o revoca con grant_super_admin() / revoke_super_admin()';
  end if;
  return new;
end;
$$;

drop trigger if exists memberships_super_admin_guard on public.memberships;
create trigger memberships_super_admin_guard
  before insert or update on public.memberships
  for each row execute function public.assert_super_admin_grant_path();

comment on function public.assert_super_admin_grant_path() is
  'Impide escribir o alterar una membresia SUPER_ADMIN fuera de grant_super_admin()/revoke_super_admin(). Cierra la via directa que service_role tenia por sus privilegios de arranque en frio.';

create or replace function public.grant_super_admin(
  p_email text,
  p_organization_id uuid,
  p_event_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user uuid;
  membership_id uuid;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception using errcode = '22023', message = 'Registra el motivo de la concesion';
  end if;
  select users.id into target_user from auth.users as users where lower(users.email) = lower(btrim(p_email));
  if target_user is null then
    raise exception using errcode = 'P0002', message = 'No existe una cuenta con ese correo';
  end if;

  perform set_config('app.super_admin_grant', 'on', true);
  insert into public.memberships(user_id, organization_id, event_id, role, active)
  values (target_user, p_organization_id, p_event_id, 'super_admin', true)
  on conflict on constraint memberships_user_id_organization_id_event_id_role_key
  do update set active = true
  returning id into membership_id;
  perform set_config('app.super_admin_grant', '', true);

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    p_event_id, p_organization_id, (select auth.uid()), 'grant_super_admin', 'memberships', membership_id,
    jsonb_build_object('motivo', btrim(p_reason), 'usuario', target_user, 'via', 'operacion_privilegiada')
  );
  return membership_id;
end;
$$;

create or replace function public.revoke_super_admin(p_user_id uuid, p_reason text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  revoked integer;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception using errcode = '22023', message = 'Registra el motivo de la revocacion';
  end if;
  perform set_config('app.super_admin_grant', 'on', true);
  update public.memberships
  set active = false
  where user_id = p_user_id and role = 'super_admin' and active;
  get diagnostics revoked = row_count;
  perform set_config('app.super_admin_grant', '', true);

  insert into public.audit_events(actor_id, action, entity_table, entity_id, metadata)
  values ((select auth.uid()), 'revoke_super_admin', 'memberships', null,
          jsonb_build_object('motivo', btrim(p_reason), 'usuario', p_user_id, 'membresias', revoked));
  return revoked;
end;
$$;

revoke all on function public.grant_super_admin(text, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.revoke_super_admin(uuid, text) from public, anon, authenticated;
-- Sin esta concesion la operacion privilegiada no era alcanzable por nadie salvo el
-- superusuario, y quien administra el entorno terminaba escribiendo la fila a mano.
grant execute on function public.grant_super_admin(text, uuid, uuid, text) to service_role;
grant execute on function public.revoke_super_admin(uuid, text) to service_role;

comment on function public.grant_super_admin(text, uuid, uuid, text) is
  'Unica via para conceder SUPER_ADMIN. Revocada para anon y authenticated, concedida a service_role, y obligada por el disparador de memberships: la escritura directa de esa fila esta bloqueada aunque se tengan privilegios de tabla.';
comment on function public.revoke_super_admin(uuid, text) is
  'Unica via para revocar SUPER_ADMIN. Desactiva la membresia sin borrarla, con motivo y auditoria.';

-- ---------------------------------------------------------------------------
-- Administracion de usuarios y roles desde la consola global.
create or replace function public.assign_membership_role(
  p_user_id uuid,
  p_organization_id uuid,
  p_event_id uuid,
  p_role public.app_role,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  membership_id uuid;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = 'Solo SUPER_ADMIN administra roles';
  end if;
  -- Ni concederse ni quitarse permisos a uno mismo: una consola que permite editar la
  -- propia membresia deja de ser auditable frente a quien la usa.
  if p_user_id = (select auth.uid()) then
    raise exception using errcode = '42501', message = 'No puedes modificar tus propios roles';
  end if;
  -- SUPER_ADMIN no se concede ni se retira desde la aplicacion.
  if p_role = 'super_admin' then
    raise exception using errcode = '42501',
      message = 'SUPER_ADMIN solo se concede mediante la operacion privilegiada';
  end if;
  if exists (
    select 1 from public.memberships as existing
    where existing.user_id = p_user_id and existing.role = 'super_admin' and existing.active
  ) then
    raise exception using errcode = '42501', message = 'Ese usuario es SUPER_ADMIN; su acceso se administra fuera de la consola';
  end if;
  if not exists (select 1 from auth.users as users where users.id = p_user_id) then
    raise exception using errcode = 'P0002', message = 'La cuenta indicada no existe';
  end if;
  if not exists (select 1 from public.organizations as organization where organization.id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'La organizacion indicada no existe';
  end if;
  if not exists (select 1 from public.emergency_events as event where event.id = p_event_id) then
    raise exception using errcode = 'P0002', message = 'El evento indicado no existe';
  end if;

  insert into public.memberships(user_id, organization_id, event_id, role, active)
  values (p_user_id, p_organization_id, p_event_id, p_role, coalesce(p_active, true))
  on conflict on constraint memberships_user_id_organization_id_event_id_role_key
  do update set active = coalesce(p_active, true)
  returning id into membership_id;
  return membership_id;
end;
$$;

create or replace function public.set_user_platform_access(p_user_id uuid, p_active boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  touched integer;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = 'Solo SUPER_ADMIN activa o desactiva cuentas';
  end if;
  if p_user_id = (select auth.uid()) then
    raise exception using errcode = '42501', message = 'No puedes desactivar tu propia cuenta';
  end if;
  if exists (
    select 1 from public.memberships as existing
    where existing.user_id = p_user_id and existing.role = 'super_admin' and existing.active
  ) then
    raise exception using errcode = '42501', message = 'Ese usuario es SUPER_ADMIN; su acceso se administra fuera de la consola';
  end if;
  -- Desactivar es retirar el alcance, no borrar el historial: las membresias se
  -- conservan para que la trazabilidad de lo que hizo esa cuenta siga en pie.
  update public.memberships
  set active = coalesce(p_active, false)
  where user_id = p_user_id and role <> 'super_admin' and active is distinct from coalesce(p_active, false);
  get diagnostics touched = row_count;
  return touched;
end;
$$;

revoke all on function public.assign_membership_role(uuid, uuid, uuid, public.app_role, boolean) from public, anon, authenticated;
revoke all on function public.set_user_platform_access(uuid, boolean) from public, anon, authenticated;
grant execute on function public.assign_membership_role(uuid, uuid, uuid, public.app_role, boolean) to authenticated;
grant execute on function public.set_user_platform_access(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- PARAMETRIZACION.
--
-- Fase 10 del loop: lo que aqui se puede editar son datos, nunca contratos. No se
-- parametrizan reglas de RLS, de autorizacion, transiciones de despacho, tipos del
-- Kardex, formulas de disponibilidad, concurrencia, integridad ni recepcion. Tampoco
-- se toca inventario: la unica fuente de verdad sigue siendo el Kardex y este modulo
-- no tiene ninguna via para escribir existencias.
--
-- La estructura territorial y operativa (centros, bodegas y puntos de acopio) ya se
-- administra con `manage_delivery_point`, que valida, versiona categorias aceptadas y
-- deja rastro en `delivery_point_changes`. SUPER_ADMIN la alcanza sin cambios porque
-- esa RPC autoriza por `has_any_role`, que ahora reconoce el alcance global. No se
-- crea una segunda RPC para lo mismo.

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
    insert into public.organizations(name, slug, status, verified)
    values (btrim(p_name), normalized_slug, coalesce(p_status, 'active'), coalesce(p_verified, false))
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
    update public.organizations
    set name = coalesce(nullif(btrim(p_name), ''), name),
        status = coalesce(p_status, status),
        verified = coalesce(p_verified, verified)
    where id = p_organization_id
    returning id into organization_id;
    if organization_id is null then
      raise exception using errcode = 'P0002', message = 'La organizacion indicada no existe';
    end if;
  end if;
  return organization_id;
end;
$$;

revoke all on function public.manage_organization(uuid, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.manage_organization(uuid, text, text, text, boolean) to authenticated;
comment on function public.manage_organization(uuid, text, text, text, boolean) is
  'Alta y edicion de organizaciones desde la parametrizacion. El identificador publico es inmutable y la baja es suspension, no borrado.';

-- Catalogos parametrizables. La lista blanca es deliberada: quedan fuera los catalogos
-- que no son datos sino contrato. `declared_donation_statuses` alimenta el mapeo a los
-- estados operativos dentro de la RPC de aporte, y `departments` es la referencia
-- DIVIPOLA; editarlos desde una pantalla romperia una invariante, no una preferencia.
create or replace function public.parameterizable_catalogs()
returns table(key text, name text, version integer, values_json jsonb, effective_from timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select catalog.key, catalog.name, version.version, version.values_json, version.effective_from
  from public.catalogs as catalog
  join public.catalog_versions as version on version.catalog_id = catalog.id and version.effective_to is null
  where public.is_super_admin()
    and catalog.key = any(array[
      'need_categories','units','donor_types','economic_sectors',
      'donation_categories','reporting_allies','coverage_departments'
    ])
  order by catalog.key;
$$;

revoke all on function public.parameterizable_catalogs() from public, anon, authenticated;
grant execute on function public.parameterizable_catalogs() to authenticated;

create or replace function public.manage_catalog_values(p_key text, p_values jsonb, p_note text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_catalog uuid;
  current_version public.catalog_versions;
  next_version integer;
  current_shape text;
  new_shape text;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = 'Solo SUPER_ADMIN parametriza catalogos';
  end if;
  if not exists (select 1 from public.parameterizable_catalogs() as allowed where allowed.key = p_key) then
    raise exception using errcode = '42501', message = 'Ese catalogo no es parametrizable';
  end if;
  if jsonb_typeof(coalesce(p_values, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_values) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'El catalogo necesita entre 1 y 200 valores';
  end if;

  select catalog.id into target_catalog from public.catalogs as catalog where catalog.key = p_key;
  select * into current_version
  from public.catalog_versions as version
  where version.catalog_id = target_catalog and version.effective_to is null;

  -- La forma no se negocia: quien consume el catalogo espera texto plano o un objeto con
  -- `value`. Cambiarla desde una pantalla romperia el codigo que lo lee.
  select jsonb_typeof(entry.value) into current_shape
  from jsonb_array_elements(current_version.values_json) as entry(value) limit 1;
  select jsonb_typeof(entry.value) into new_shape
  from jsonb_array_elements(p_values) as entry(value) limit 1;
  if new_shape is distinct from current_shape then
    raise exception using errcode = '22023', message = 'El nuevo catalogo debe conservar la forma del vigente';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_values) as entry(value)
    where jsonb_typeof(entry.value) is distinct from current_shape
  ) then
    raise exception using errcode = '22023', message = 'Todos los valores deben tener la misma forma';
  end if;
  if current_shape = 'object' and exists (
    select 1 from jsonb_array_elements(p_values) as entry(value)
    where nullif(btrim(coalesce(entry.value ->> 'value', '')), '') is null
       or nullif(btrim(coalesce(entry.value ->> 'label', '')), '') is null
  ) then
    raise exception using errcode = '22023', message = 'Cada valor necesita clave y etiqueta';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_values) as entry(value)
    group by case when current_shape = 'object' then entry.value ->> 'value' else entry.value #>> '{}' end
    having count(*) > 1
  ) then
    raise exception using errcode = '22023', message = 'El catalogo no admite valores repetidos';
  end if;
  -- El aporte economico depende de una categoria concreta; no puede quedar fuera.
  if p_key = 'donation_categories' and not exists (
    select 1 from jsonb_array_elements(p_values) as entry(value)
    where entry.value ->> 'value' = 'apoyo_economico_recursos'
  ) then
    raise exception using errcode = '22023', message = 'El catalogo debe conservar la categoria economica';
  end if;

  -- Versionar en vez de sobrescribir: el aporte guarda la version con la que se valido,
  -- asi que la vigente se cierra y la nueva empieza. Nada del historial se pierde.
  next_version := coalesce(current_version.version, 0) + 1;
  update public.catalog_versions set effective_to = now() where id = current_version.id;
  insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
  values (target_catalog, next_version, p_values, now());

  insert into public.audit_events(actor_id, action, entity_table, entity_id, metadata)
  values ((select auth.uid()), 'parameterize_catalog', 'catalogs', target_catalog,
          jsonb_build_object(
            'catalogo', p_key,
            'motivo', nullif(btrim(coalesce(p_note, '')), ''),
            'valor_anterior', current_version.values_json,
            'valor_nuevo', p_values,
            'version_anterior', current_version.version,
            'version_nueva', next_version
          ));
  return next_version;
end;
$$;

revoke all on function public.manage_catalog_values(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.manage_catalog_values(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Lecturas de la consola global. Son `security definer` porque cruzan `auth.users`,
-- que ningun rol de aplicacion puede leer, y todas empiezan comprobando el alcance.
create or replace function public.platform_users_admin(p_event_id uuid)
returns table(
  user_id uuid,
  email text,
  full_name text,
  is_super_admin boolean,
  active_roles text[],
  inactive_roles text[],
  organizations text[],
  location_scope text[],
  last_sign_in_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id,
    users.email::text,
    coalesce(profile.full_name, users.raw_user_meta_data ->> 'full_name'),
    bool_or(membership.role = 'super_admin' and membership.active),
    coalesce(array_agg(distinct membership.role::text) filter (where membership.active and membership.event_id = p_event_id), '{}'),
    coalesce(array_agg(distinct membership.role::text) filter (where not membership.active and membership.event_id = p_event_id), '{}'),
    coalesce(array_agg(distinct organization.name) filter (where membership.active and membership.event_id = p_event_id), '{}'),
    coalesce(array_agg(distinct location.name) filter (where scope.location_id is not null), '{}'),
    users.last_sign_in_at
  from auth.users as users
  left join public.profiles as profile on profile.id = users.id
  left join public.memberships as membership on membership.user_id = users.id
  left join public.organizations as organization on organization.id = membership.organization_id
  left join public.membership_locations as scope on scope.membership_id = membership.id
  left join public.inventory_locations as location on location.id = scope.location_id
  where public.is_super_admin()
  group by users.id, users.email, profile.full_name, users.raw_user_meta_data, users.last_sign_in_at
  order by users.email;
$$;

create or replace function public.platform_audit_admin(p_event_id uuid, p_limit integer default 60)
returns table(
  occurred_at timestamptz,
  actor_email text,
  action text,
  entity_table text,
  entity_id uuid,
  organization_name text,
  metadata jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    audit.occurred_at,
    actor.email::text,
    audit.action,
    audit.entity_table,
    audit.entity_id,
    organization.name,
    audit.metadata
  from public.audit_events as audit
  left join auth.users as actor on actor.id = audit.actor_id
  left join public.organizations as organization on organization.id = audit.organization_id
  where public.is_super_admin()
    and (audit.event_id is null or audit.event_id = p_event_id)
    and audit.entity_table = any(array['memberships','membership_locations','organizations','catalogs','catalog_versions','inventory_locations'])
  order by audit.occurred_at desc
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$$;

revoke all on function public.platform_users_admin(uuid) from public, anon, authenticated;
revoke all on function public.platform_audit_admin(uuid, integer) from public, anon, authenticated;
grant execute on function public.platform_users_admin(uuid) to authenticated;
grant execute on function public.platform_audit_admin(uuid, integer) to authenticated;

comment on function public.parameterizable_catalogs() is
  'Catalogos que son datos y no contrato. Los que alimentan invariantes (estados declarados, DIVIPOLA) quedan deliberadamente fuera.';
comment on function public.manage_catalog_values(text, jsonb, text) is
  'Publica una version nueva de un catalogo parametrizable conservando la anterior y su forma; audita el antes y el despues.';
comment on function public.platform_users_admin(uuid) is
  'Padron de cuentas con sus roles activos e inactivos, organizaciones y alcance por bodega; solo SUPER_ADMIN.';
comment on function public.platform_audit_admin(uuid, integer) is
  'Auditoria de la administracion: quien cambio que y cuando sobre roles, organizaciones, catalogos y puntos.';
