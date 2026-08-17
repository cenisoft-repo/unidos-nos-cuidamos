-- Puntos con propósito declarado, despacho con origen y cadena de trazabilidad completa.
--
-- Tres problemas que resuelve:
--
-- 1. Un punto servía a la vez para recibir y para despachar sin decirlo. Ahora cada punto
--    declara para qué sirve, y un punto que solo despacha deja de aparecer como centro de
--    acopio público y deja de ofrecerse al aliado que registra un aporte.
-- 2. El despacho no registraba desde dónde salía. `shipments.origin_location_id` lo fija y
--    la función valida que ese punto pertenezca al tenant y esté habilitado para despachar.
-- 3. El código `APO-*` del donante se quedaba congelado en «aprobado»: no heredaba el
--    avance operacional de su `DON-*`. `track_public_journey` devuelve la cadena real de
--    hitos con sus fechas, atravesando intake → donación → recepción → despacho → entrega.

-- ============================================================ 1. propósito del punto

alter table public.inventory_locations
  add column if not exists accepts_donations boolean not null default true,
  add column if not exists dispatches_shipments boolean not null default true;

-- Los puntos que ya existían podían usarse para ambas cosas porque nada lo distinguía:
-- conservan los dos propósitos. Los nuevos nacen solo como acopio salvo declaración expresa.
alter table public.inventory_locations alter column dispatches_shipments set default false;

alter table public.inventory_locations
  add constraint inventory_locations_purpose_declared
  check (accepts_donations or dispatches_shipments);

-- ============================================================ 2. origen del despacho

alter table public.shipments
  add column if not exists origin_location_id uuid references public.inventory_locations(id);

create index if not exists shipments_origin_idx on public.shipments(origin_location_id);

-- ============================================================ 3. parametrización

drop function if exists public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,text[],text);

create or replace function public.manage_delivery_point(
  p_location_id uuid,
  p_event_id uuid,
  p_organization_id uuid,
  p_name text,
  p_public_location_text text,
  p_exact_address_private text,
  p_public_instructions text,
  p_public_latitude numeric,
  p_public_longitude numeric,
  p_cold_chain_capable boolean,
  p_active boolean,
  p_accepts_donations boolean,
  p_dispatches_shipments boolean,
  p_accepted_categories text[],
  p_idempotency_key text
)
returns table(location_id uuid, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target public.inventory_locations;
  existing_change public.delivery_point_changes;
  request_fingerprint text;
  category_name text;
  next_version integer;
  accepts boolean := coalesce(p_accepts_donations, false);
  dispatches boolean := coalesce(p_dispatches_shipments, false);
  categories text[] := coalesce(p_accepted_categories, '{}'::text[]);
begin
  if actor_id is null or not public.has_event_role(p_event_id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo administración del evento puede parametrizar puntos de entrega';
  end if;
  if not exists (
    select 1 from public.organizations as organization
    where organization.id = p_organization_id
      and organization.verified
      and organization.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona una organización activa y verificada';
  end if;
  if not accepts and not dispatches then
    raise exception using errcode = '22023', message = 'El punto debe recibir aportes, despachar salidas o ambas cosas';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 3 and 120 then
    raise exception using errcode = '22023', message = 'Escribe un nombre del punto entre 3 y 120 caracteres';
  end if;
  if char_length(btrim(coalesce(p_public_location_text, ''))) not between 3 and 180 then
    raise exception using errcode = '22023', message = 'Describe públicamente la ciudad y zona aproximada';
  end if;
  if char_length(btrim(coalesce(p_exact_address_private, ''))) not between 5 and 300 then
    raise exception using errcode = '22023', message = 'Registra la dirección exacta privada del punto';
  end if;
  if nullif(btrim(coalesce(p_public_instructions, '')), '') is not null
     and char_length(btrim(p_public_instructions)) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'Las instrucciones públicas deben tener entre 3 y 500 caracteres';
  end if;
  if p_public_latitude is null or p_public_latitude not between -4.5 and 13.5
     or p_public_longitude is null or p_public_longitude not between -82 and -66.5 then
    raise exception using errcode = '22023', message = 'Registra coordenadas aproximadas válidas dentro de Colombia';
  end if;
  if char_length(coalesce(p_idempotency_key, '')) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'La clave idempotente no es válida';
  end if;
  -- Las categorías describen qué se recibe: solo tienen sentido si el punto recibe.
  if accepts and cardinality(categories) not between 1 and 8 then
    raise exception using errcode = '22023', message = 'Un punto que recibe aportes necesita entre 1 y 8 categorías aceptadas';
  end if;
  if not accepts and cardinality(categories) > 0 then
    raise exception using errcode = '22023', message = 'Un punto que solo despacha no declara categorías de recepción';
  end if;
  if exists (
    select 1
    from unnest(categories) as supplied(category)
    where not exists (
      select 1
      from public.donation_flow_catalogs() as catalog,
        jsonb_array_elements(catalog.values_json) as option(value)
      where catalog.key = 'donation_categories'
        and option.value ->> 'kind' = 'in_kind'
        and option.value ->> 'parent_category' = supplied.category
    )
  ) then
    raise exception using errcode = '22023', message = 'Una categoría aceptada no pertenece al catálogo vigente';
  end if;

  request_fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'location_id', p_location_id,
        'event_id', p_event_id,
        'organization_id', p_organization_id,
        'name', btrim(p_name),
        'public_location_text', btrim(p_public_location_text),
        'exact_address_private', btrim(p_exact_address_private),
        'public_instructions', nullif(btrim(coalesce(p_public_instructions, '')), ''),
        'public_latitude', p_public_latitude,
        'public_longitude', p_public_longitude,
        'cold_chain_capable', coalesce(p_cold_chain_capable, false),
        'active', coalesce(p_active, false),
        'accepts_donations', accepts,
        'dispatches_shipments', dispatches,
        'accepted_categories', to_jsonb(categories)
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || p_idempotency_key, 0));
  select * into existing_change
  from public.delivery_point_changes
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if existing_change.id is not null then
    if existing_change.request_fingerprint is distinct from request_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con otros parámetros';
    end if;
    return query select existing_change.location_id, true;
    return;
  end if;

  if p_location_id is null then
    insert into public.inventory_locations(
      event_id, organization_id, name, public_location_text, exact_address_private,
      public_instructions, public_latitude, public_longitude, cold_chain_capable, active,
      accepts_donations, dispatches_shipments
    ) values (
      p_event_id, p_organization_id, btrim(p_name), btrim(p_public_location_text),
      btrim(p_exact_address_private), nullif(btrim(coalesce(p_public_instructions, '')), ''),
      p_public_latitude, p_public_longitude, coalesce(p_cold_chain_capable, false), coalesce(p_active, false),
      accepts, dispatches
    ) returning * into target;
  else
    select * into target
    from public.inventory_locations
    where id = p_location_id
      and event_id = p_event_id
      and organization_id = p_organization_id
    for update;
    if target.id is null then
      raise exception using errcode = '22023', message = 'El punto no pertenece al evento y organización indicados';
    end if;
    update public.inventory_locations
    set name = btrim(p_name),
        public_location_text = btrim(p_public_location_text),
        exact_address_private = btrim(p_exact_address_private),
        public_instructions = nullif(btrim(coalesce(p_public_instructions, '')), ''),
        public_latitude = p_public_latitude,
        public_longitude = p_public_longitude,
        cold_chain_capable = coalesce(p_cold_chain_capable, false),
        active = coalesce(p_active, false),
        accepts_donations = accepts,
        dispatches_shipments = dispatches
    where id = target.id
    returning * into target;
  end if;

  for category_name in
    select distinct option.value ->> 'parent_category'
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'donation_categories'
      and option.value ->> 'kind' = 'in_kind'
      and option.value ->> 'parent_category' is not null
    order by 1
  loop
    update public.item_acceptance_rules as rule
    set effective_to = now()
    where rule.organization_id = target.organization_id
      and rule.event_id = target.event_id
      and rule.location_id = target.id
      and rule.category = category_name
      and rule.effective_to is null;

    select coalesce(max(version), 0) + 1 into next_version
    from public.item_acceptance_rules as rule
    where rule.organization_id = target.organization_id
      and rule.event_id = target.event_id
      and rule.category = category_name;

    insert into public.item_acceptance_rules(
      organization_id, event_id, location_id, category, decision, rule_text,
      requires_cold_chain, version, effective_from
    ) values (
      target.organization_id, target.event_id, target.id, category_name,
      case when category_name = any(categories) then 'accepted' else 'prohibited' end,
      case when category_name = any(categories)
        then 'Categoría habilitada en la parametrización vigente del punto.'
        else 'Categoría no habilitada en la parametrización vigente del punto.'
      end,
      false, next_version, now()
    );
  end loop;

  insert into public.delivery_point_changes(
    event_id, organization_id, location_id, idempotency_key, request_fingerprint, actor_id
  ) values (
    target.event_id, target.organization_id, target.id, p_idempotency_key, request_fingerprint, actor_id
  );

  return query select target.id, false;
end;
$$;

-- El conjunto de columnas cambia, así que no basta `create or replace`.
drop function if exists public.delivery_points_admin(uuid);

create or replace function public.delivery_points_admin(p_event_id uuid)
returns table(
  id uuid,
  organization_id uuid,
  organization_name text,
  name text,
  public_location_text text,
  exact_address_private text,
  public_instructions text,
  public_latitude numeric,
  public_longitude numeric,
  cold_chain_capable boolean,
  active boolean,
  accepts_donations boolean,
  dispatches_shipments boolean,
  accepted_categories text[],
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not public.has_event_role(p_event_id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo administración del evento puede consultar la parametrización';
  end if;

  return query
  with current_rules as (
    select distinct on (rule.location_id, rule.category)
      rule.location_id, rule.category, rule.decision
    from public.item_acceptance_rules as rule
    where rule.event_id = p_event_id
      and rule.location_id is not null
      and rule.effective_from <= now()
      and (rule.effective_to is null or rule.effective_to > now())
    order by rule.location_id, rule.category, rule.version desc
  )
  select
    location.id,
    location.organization_id,
    organization.name,
    location.name,
    location.public_location_text,
    location.exact_address_private,
    location.public_instructions,
    location.public_latitude,
    location.public_longitude,
    location.cold_chain_capable,
    location.active,
    location.accepts_donations,
    location.dispatches_shipments,
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    location.updated_at
  from public.inventory_locations as location
  join public.organizations as organization on organization.id = location.organization_id
  left join current_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
  group by location.id, organization.name
  order by location.active desc, organization.name, location.name;
end;
$$;

-- Un punto que solo despacha no se ofrece a quien registra un aporte.
create or replace function public.organization_delivery_points(
  p_event_id uuid,
  p_organization_id uuid
)
returns table(
  id uuid,
  name text,
  location_label text,
  public_instructions text,
  accepts text[],
  restricted_items text[],
  cold_chain_capable boolean,
  latitude double precision,
  longitude double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_any_role(
       p_organization_id,
       p_event_id,
       array['partner_reporter','event_admin']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No puedes consultar los puntos de esta organización';
  end if;

  return query
  with current_rules as (
    select distinct on (
      rule.organization_id,
      rule.event_id,
      coalesce(rule.location_id, '00000000-0000-0000-0000-000000000000'::uuid),
      rule.category
    )
      rule.organization_id, rule.event_id, rule.location_id, rule.category, rule.decision
    from public.item_acceptance_rules as rule
    where rule.organization_id = p_organization_id
      and rule.event_id = p_event_id
      and rule.effective_from <= now()
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
    location.public_location_text,
    location.public_instructions,
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
    and location.organization_id = p_organization_id
    and location.active
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
end;
$$;

-- Puntos habilitados como origen de una salida, para la consola de bodega y logística.
create or replace function public.organization_dispatch_points(
  p_event_id uuid,
  p_organization_id uuid
)
returns table(
  id uuid,
  name text,
  location_label text,
  cold_chain_capable boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_any_role(
       p_organization_id,
       p_event_id,
       array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No puedes consultar los puntos de despacho de esta organización';
  end if;

  return query
  select location.id, location.name, location.public_location_text, location.cold_chain_capable
  from public.inventory_locations as location
  where location.event_id = p_event_id
    and location.organization_id = p_organization_id
    and location.active
    and location.dispatches_shipments
  order by location.name;
end;
$$;

revoke all on function public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,boolean,boolean,text[],text) from public, anon, authenticated;
revoke all on function public.delivery_points_admin(uuid) from public, anon, authenticated;
revoke all on function public.organization_dispatch_points(uuid,uuid) from public, anon, authenticated;
grant execute on function public.manage_delivery_point(uuid,uuid,uuid,text,text,text,text,numeric,numeric,boolean,boolean,boolean,boolean,text[],text) to authenticated;
grant execute on function public.delivery_points_admin(uuid) to authenticated;
grant execute on function public.organization_dispatch_points(uuid,uuid) to authenticated;

-- El mapa y el listado público solo muestran puntos que reciben.
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
    location.public_location_text,
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join applicable_rules as rule on rule.location_id = location.id
  where location.event_id = p_event_id
    and location.active
    and location.accepts_donations
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

-- El mapa público publica centros de acopio: una base que solo despacha no es uno de ellos.
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
      and location.public_longitude is not null,
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

-- ============================================================ 4. despacho con origen

drop function if exists public.create_shipment(uuid,text,text,text);

create or replace function public.create_shipment(
  p_allocation_id uuid,
  p_origin_location_id uuid,
  p_public_destination text,
  p_carrier_name text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target public.allocations;
  lot public.inventory_lots;
  origin public.inventory_locations;
  shipment_id uuid;
  donation_id uuid;
begin
  select s.id into shipment_id from public.shipments s where s.idempotency_key = p_idempotency_key;
  if found then return shipment_id; end if;

  select * into target from public.allocations where id = p_allocation_id for update;
  if not found or target.status <> 'reserved' then
    raise exception using errcode = '22023', message = 'La asignación no está disponible para despacho';
  end if;
  select * into lot from public.inventory_lots where id = target.lot_id for update;
  if lot.status in ('quarantined','hold','recalled','disposed') then
    raise exception using errcode = '22023', message = 'El lote está bloqueado y no puede salir';
  end if;
  if not public.has_any_role(target.organization_id, target.event_id, array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes crear este despacho';
  end if;

  select * into origin from public.inventory_locations where id = p_origin_location_id;
  if not found then
    raise exception using errcode = '22023', message = 'Selecciona el punto desde el que sale el despacho';
  end if;
  if origin.organization_id <> target.organization_id or origin.event_id <> target.event_id then
    raise exception using errcode = '42501', message = 'El punto de origen pertenece a otra organización o evento';
  end if;
  if not origin.active or not origin.dispatches_shipments then
    raise exception using errcode = '22023', message = 'Ese punto no está habilitado para despachar salidas';
  end if;
  if char_length(btrim(coalesce(p_public_destination, ''))) not between 3 and 180 then
    raise exception using errcode = '22023', message = 'Describe públicamente la zona de destino';
  end if;
  if public.contains_sensitive_content(p_public_destination) then
    raise exception using errcode = '22023', message = 'El destino público no puede incluir teléfonos, cuentas ni enlaces';
  end if;

  insert into public.shipments(event_id,organization_id,status,carrier_name,public_destination,origin_location_id,dispatched_at,created_by,idempotency_key)
  values (target.event_id,target.organization_id,'dispatched',nullif(btrim(p_carrier_name),''),btrim(p_public_destination),origin.id,now(),(select auth.uid()),p_idempotency_key)
  returning id into shipment_id;
  insert into public.shipment_items(shipment_id,allocation_id,quantity) values (shipment_id,target.id,target.quantity);
  insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id)
  values (target.event_id,target.organization_id,lot.id,'release',target.quantity,p_idempotency_key || ':release','Conversión de reserva a despacho',(select auth.uid()));
  insert into public.stock_movements(event_id,organization_id,lot_id,movement_type,quantity_delta,idempotency_key,reason,actor_id)
  values (target.event_id,target.organization_id,lot.id,'dispatch',-target.quantity,p_idempotency_key || ':dispatch','Salida física despachada',(select auth.uid()));
  update public.allocations set status = 'dispatched' where id = target.id;
  select di.donation_id into donation_id from public.inventory_lots il join public.donation_items di on di.id = il.donation_item_id where il.id = lot.id;
  update public.donations set status = 'dispatched' where id = donation_id;
  return shipment_id;
end;
$$;

revoke all on function public.create_shipment(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.create_shipment(uuid,uuid,text,text,text) to authenticated;

-- ============================================================ 5. trazabilidad

-- Devuelve la cadena de hitos que realmente ocurrió, con su fecha, para cualquiera de los
-- tres códigos. La diferencia con `track_public_code` es que aquí un `APO-*` sí atraviesa
-- su donación operacional: el donante ve recepción, despacho, entrega y validación.
--
-- Todo lo que sale es información ya aprobada para superficie pública: etiquetas fijas,
-- cantidades conciliadas y la zona pública del despacho. No sale el transportador, ni la
-- dirección exacta, ni el contacto, ni las notas internas de quien decide.
create or replace function public.track_public_journey(p_tracking_code text)
returns table(
  step integer,
  stage_key text,
  stage_label text,
  detail text,
  occurred_at timestamptz,
  related_code text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  need public.need_cases;
  intake public.donation_intakes;
  donation public.donations;
begin
  if p_tracking_code !~ '^(NEC|APO|DON)-[A-F0-9]{24}$' then return; end if;

  select * into need from public.need_cases as candidate where candidate.tracking_code = p_tracking_code;
  select * into intake from public.donation_intakes as candidate where candidate.tracking_code = p_tracking_code;
  select * into donation from public.donations as candidate where candidate.donor_tracking_code = p_tracking_code;

  -- Los dos códigos del mismo aporte son la misma historia vista desde dos lados.
  if donation.id is not null and intake.id is null and donation.intake_id is not null then
    select * into intake from public.donation_intakes as candidate where candidate.id = donation.intake_id;
  end if;
  if intake.id is not null and donation.id is null then
    select * into donation from public.donations as candidate where candidate.intake_id = intake.id;
  end if;

  return query
  select entry.step, entry.stage_key, entry.stage_label, entry.detail, entry.occurred_at, entry.related_code
  from (
    -- Necesidad ciudadana
    select 10 as step, 'need_reported' as stage_key, 'Reporte recibido' as stage_label,
      'El caso quedó protegido y entró a la cola de verificación.' as detail,
      need.created_at as occurred_at, need.tracking_code as related_code
    where need.id is not null

    union all
    select 20, 'need_verified', 'Necesidad verificada',
      'Una organización autorizada contrastó los hechos.',
      verification.created_at, need.tracking_code
    from public.need_verifications as verification
    where need.id is not null and verification.need_case_id = need.id and verification.decision = 'verify'

    union all
    select 30, 'need_published', 'Necesidad publicada',
      'El caso quedó visible sin dirección exacta ni contacto.',
      verification.created_at, need.tracking_code
    from public.need_verifications as verification
    where need.id is not null and verification.need_case_id = need.id and verification.decision = 'publish'

    -- Aporte declarado
    union all
    select 40, 'intake_reported', 'Aporte reportado',
      case when intake.kind = 'money'
        then 'Se registró un aporte económico gestionado fuera de la plataforma.'
        else 'Se registró una promesa de bienes. Todavía no acredita recepción.' end,
      intake.submitted_at, intake.tracking_code
    where intake.id is not null

    union all
    select 50, 'intake_approved', 'Aporte aprobado',
      'La revisión autorizó continuar con la coordinación.',
      decision.decided_at, intake.tracking_code
    from public.intake_verification_decisions as decision
    where intake.id is not null and decision.intake_id = intake.id and decision.decision = 'approve'

    -- Recorrido operacional. Aquí es donde el APO deja de quedarse congelado.
    union all
    select 60, 'donation_opened', 'Coordinación abierta',
      'El aporte pasó a tener seguimiento operacional propio.',
      donation.created_at, donation.donor_tracking_code
    where donation.id is not null

    union all
    select 70, 'stock_received', 'Recepción confirmada',
      -- `FM` quita los ceros decimales pero deja el punto: 40.000 quedaría como «40.».
      'El centro confirmó ' || rtrim(trim(to_char(lot.quantity_initial, 'FM999999990.999')), '.') || ' ' || lot.unit || ' en custodia.',
      lot.received_at, donation.donor_tracking_code
    from public.inventory_lots as lot
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id

    union all
    select 80, 'stock_allocated', 'Reservado para una necesidad',
      'La existencia quedó comprometida con un caso verificado.',
      allocation.created_at, donation.donor_tracking_code
    from public.allocations as allocation
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id

    union all
    select 90, 'shipment_dispatched', 'Despachado',
      'Salida hacia ' || shipment.public_destination || '.',
      shipment.dispatched_at, shipment.shipment_code
    from public.shipments as shipment
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and shipment.dispatched_at is not null

    union all
    select 100, 'delivery_registered', 'Entrega registrada',
      case when delivery.quantity_damaged > 0
        then 'Se registró la entrega con una novedad pendiente de revisión.'
        else 'Se registró la entrega, pendiente de validación independiente.' end,
      delivery.delivered_at, shipment.shipment_code
    from public.deliveries as delivery
    join public.shipments as shipment on shipment.id = delivery.shipment_id
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and delivery.delivered_at is not null

    union all
    select 110, 'delivery_validated', 'Entrega validada',
      'Una persona distinta de quien entregó confirmó el resultado y se actualizó la cobertura.',
      delivery.validated_at, shipment.shipment_code
    from public.deliveries as delivery
    join public.shipments as shipment on shipment.id = delivery.shipment_id
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and delivery.validated_at is not null

    -- Dinero
    union all
    select 120, 'money_reconciled', 'Aporte conciliado',
      'Tesorería contrastó el soporte y publicó el monto conciliado.',
      movement.reconciled_at, donation.donor_tracking_code
    from public.financial_transactions as movement
    where donation.id is not null and movement.donation_id = donation.id and movement.reconciled_at is not null
  ) as entry
  where entry.occurred_at is not null
  -- Se ordena por etapa del proceso y no por fecha: el orden lógico del recorrido es un
  -- hecho estable, mientras que una fecha registrada con retraso desordenaría la lectura.
  order by entry.step, entry.occurred_at;
end;
$$;

revoke all on function public.track_public_journey(text) from public;
grant execute on function public.track_public_journey(text) to anon, authenticated;
