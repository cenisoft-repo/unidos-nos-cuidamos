-- Catálogos autoritativos y validación de su uso en el registro de aportes.
-- Los nombres de aliados no son un selector: la organización reportante se deriva
-- de una membresía activa y de una organización verificada.

insert into public.catalogs(id, key, name) values
  ('50000000-0000-0000-0000-000000000001', 'need_categories', 'Categorías operativas de necesidad'),
  ('50000000-0000-0000-0000-000000000002', 'units', 'Unidades normalizadas'),
  ('50000000-0000-0000-0000-000000000003', 'donor_types', 'Tipos de donante'),
  ('50000000-0000-0000-0000-000000000004', 'economic_sectors', 'Sectores económicos'),
  ('50000000-0000-0000-0000-000000000005', 'donation_categories', 'Categorías detalladas de aporte'),
  ('50000000-0000-0000-0000-000000000006', 'declared_donation_statuses', 'Estados declarados del aporte'),
  ('50000000-0000-0000-0000-000000000007', 'coverage_departments', 'Departamentos de cobertura inicial'),
  ('50000000-0000-0000-0000-000000000008', 'departments', 'Departamentos de Colombia')
on conflict (key) do update set name = excluded.name;

-- Se conserva la versión histórica que ya existía en instalaciones previas.
insert into public.catalog_versions(catalog_id, version, values_json, effective_from, effective_to)
select id, 1, '["Agua","Alimentos","Higiene","Refugio","Salud","Protección"]'::jsonb,
  '2026-08-13T00:00:00-05:00'::timestamptz, '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'need_categories'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from, effective_to)
select id, 1, '["unidad","litro","kilogramo","kit","caja"]'::jsonb,
  '2026-08-13T00:00:00-05:00'::timestamptz, '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'units'
on conflict (catalog_id, version) do nothing;

update public.catalog_versions as version
set effective_to = '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs as catalog
where version.catalog_id = catalog.id
  and catalog.key in ('need_categories', 'units')
  and version.version < 2
  and version.effective_to is null;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 2, '["Agua","Alimentos","Higiene","Refugio","Salud","Protección","Logística","Otro"]'::jsonb,
  '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'need_categories'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 2, '["unidad","litro","kilogramo","kit","caja"]'::jsonb,
  '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'units'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, jsonb_build_array(
  jsonb_build_object('value','empresa','label','Empresa'),
  jsonb_build_object('value','gremio_asociacion','label','Gremio o asociación'),
  jsonb_build_object('value','fundacion_empresarial','label','Fundación empresarial'),
  jsonb_build_object('value','cooperativa','label','Cooperativa'),
  jsonb_build_object('value','persona_natural','label','Persona natural'),
  jsonb_build_object('value','entidad_publica','label','Entidad pública'),
  jsonb_build_object('value','otro','label','Otro')
), '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'donor_types'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, jsonb_build_array(
  jsonb_build_object('value','agroindustria','label','Agroindustria'),
  jsonb_build_object('value','alimentos_bebidas','label','Alimentos y bebidas'),
  jsonb_build_object('value','comercio','label','Comercio'),
  jsonb_build_object('value','construccion','label','Construcción'),
  jsonb_build_object('value','salud_farmaceutico','label','Salud y farmacéutico'),
  jsonb_build_object('value','servicios_financieros','label','Servicios financieros'),
  jsonb_build_object('value','logistica_transporte','label','Logística y transporte'),
  jsonb_build_object('value','manufactura','label','Manufactura'),
  jsonb_build_object('value','energia_servicios_publicos','label','Energía y servicios públicos'),
  jsonb_build_object('value','tecnologia','label','Tecnología'),
  jsonb_build_object('value','educacion','label','Educación'),
  jsonb_build_object('value','turismo_hoteleria','label','Turismo y hotelería'),
  jsonb_build_object('value','otro','label','Otro')
), '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'economic_sectors'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, jsonb_build_array(
  jsonb_build_object('value','alimentos','label','Alimentos','kind','in_kind','parent_category','Alimentos'),
  jsonb_build_object('value','agua_potable','label','Agua potable','kind','in_kind','parent_category','Agua'),
  jsonb_build_object('value','kits_aseo_higiene','label','Kits de aseo e higiene','kind','in_kind','parent_category','Higiene'),
  jsonb_build_object('value','medicamentos_insumos_medicos','label','Medicamentos e insumos médicos','kind','in_kind','parent_category','Salud'),
  jsonb_build_object('value','materiales_construccion','label','Materiales de construcción','kind','in_kind','parent_category','Refugio'),
  jsonb_build_object('value','ropa_calzado','label','Ropa y calzado','kind','in_kind','parent_category','Protección'),
  jsonb_build_object('value','colchonetas_frazadas','label','Colchonetas y frazadas','kind','in_kind','parent_category','Refugio'),
  jsonb_build_object('value','menaje_cocina','label','Menaje y cocina','kind','in_kind','parent_category','Refugio'),
  jsonb_build_object('value','combustible','label','Combustible','kind','in_kind','parent_category','Logística'),
  jsonb_build_object('value','transporte_logistica','label','Transporte y logística','kind','in_kind','parent_category','Logística'),
  jsonb_build_object('value','maquinaria_herramientas','label','Maquinaria y herramientas','kind','in_kind','parent_category','Logística'),
  jsonb_build_object('value','apoyo_economico_recursos','label','Apoyo económico / recursos','kind','money','parent_category',null),
  jsonb_build_object('value','otro','label','Otro','kind','in_kind','parent_category','Otro')
), '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'donation_categories'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, jsonb_build_array(
  jsonb_build_object('value','comprometida','label','Comprometida'),
  jsonb_build_object('value','en_gestion','label','En gestión'),
  jsonb_build_object('value','en_transito','label','En tránsito'),
  jsonb_build_object('value','entregada','label','Entregada')
), '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'declared_donation_statuses'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, '["Valle del Cauca","Chocó","Risaralda","Quindío","Caldas"]'::jsonb,
  '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'coverage_departments'
on conflict (catalog_id, version) do nothing;

insert into public.catalog_versions(catalog_id, version, values_json, effective_from)
select id, 1, '["Amazonas","Antioquia","Arauca","Atlántico","Bolívar","Boyacá","Caldas","Caquetá","Casanare","Cauca","Cesar","Chocó","Córdoba","Cundinamarca","Guainía","Guaviare","Huila","La Guajira","Magdalena","Meta","Nariño","Norte de Santander","Putumayo","Quindío","Risaralda","San Andrés y Providencia","Santander","Sucre","Tolima","Valle del Cauca","Vaupés","Vichada","Bogotá D.C."]'::jsonb,
  '2026-08-16T00:00:00-05:00'::timestamptz
from public.catalogs where key = 'departments'
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
    'declared_donation_statuses', 'coverage_departments', 'departments', 'units'
  ]::text[])
    and version.effective_from <= now()
    and (version.effective_to is null or version.effective_to > now())
  order by catalog.key, version.version desc;
$$;

create or replace function public.current_donation_catalog_versions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(catalog.key, catalog.version), '{}'::jsonb)
  from public.donation_flow_catalogs() as catalog;
$$;

revoke all on function public.donation_flow_catalogs() from public;
revoke all on function public.current_donation_catalog_versions() from public;
grant execute on function public.donation_flow_catalogs() to anon, authenticated;
grant execute on function public.current_donation_catalog_versions() to anon, authenticated;

alter table public.donation_intakes
  add column if not exists declared_category_code text,
  add column if not exists catalog_versions jsonb not null default '{}'::jsonb,
  add column if not exists catalog_fingerprint text;

alter table public.donation_intake_items
  add column if not exists category_code text;

alter table public.donation_items
  add column if not exists category_code text;

alter table public.donation_intakes
  drop constraint if exists donation_intakes_donor_type_check,
  drop constraint if exists donation_intakes_declared_status_check;

alter table public.donation_intakes
  add constraint donation_intakes_donor_type_check check (
    donor_type is null or donor_type in (
      'persona','empresa','gremio','fundacion','otro',
      'gremio_asociacion','fundacion_empresarial','cooperativa','persona_natural','entidad_publica'
    )
  ),
  add constraint donation_intakes_declared_status_check check (
    declared_status in ('comprometida','en_gestion','en_transito','entregada','entregada_por_validar')
  ),
  add constraint donation_intakes_catalog_versions_object check (jsonb_typeof(catalog_versions) = 'object'),
  add constraint donation_intakes_catalog_fingerprint_check check (
    catalog_fingerprint is null or catalog_fingerprint ~ '^[0-9a-f]{64}$'
  );

alter table public.donation_intake_items
  drop constraint if exists donation_intake_items_category_check;

alter table public.donation_intake_items
  add constraint donation_intake_items_category_check check (
    category = any (array['Agua','Alimentos','Higiene','Refugio','Salud','Protección','Logística','Otro']::text[])
  );

alter table public.item_acceptance_rules
  add column if not exists location_id uuid references public.inventory_locations(id);

alter table public.item_acceptance_rules
  drop constraint if exists item_acceptance_rules_organization_id_event_id_category_version_key;

create unique index if not exists item_acceptance_rules_scope_version_key
  on public.item_acceptance_rules(
    organization_id,
    event_id,
    coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid),
    category,
    version
  );

create index if not exists item_acceptance_rules_location_id_idx
  on public.item_acceptance_rules(location_id);

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
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

revoke all on function public.public_collection_centers(uuid) from public;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

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
  actor_id uuid := (select auth.uid());
  submitted record;
  existing public.donation_intakes;
  center public.inventory_locations;
  item jsonb;
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  expected_versions jsonb := public.current_donation_catalog_versions();
  canonical_fingerprint text;
  legacy_status text;
  legacy_donor_type text;
  legacy_context jsonb;
  legacy_items jsonb := '[]'::jsonb;
  acceptance_decision text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión como aliado';
  end if;
  if not public.has_any_role(
    p_organization_id,
    p_event_id,
    array['partner_reporter','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No perteneces al aliado indicado';
  end if;
  if not exists (
    select 1 from public.organizations as organization
    where organization.id = p_organization_id
      and organization.verified
      and organization.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'La organización debe estar activa y verificada';
  end if;
  if jsonb_typeof(coalesce(p_catalog_versions, 'null'::jsonb)) <> 'object'
     or p_catalog_versions is distinct from expected_versions then
    raise exception using errcode = '22023', message = 'Los catálogos cambiaron; actualiza la página antes de continuar';
  end if;
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;
  if not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'declared_donation_statuses'
      and option.value ->> 'value' = p_declared_status
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un estado declarado vigente';
  end if;
  if nullif(context ->> 'donor_type', '') is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'donor_types'
      and option.value ->> 'value' = context ->> 'donor_type'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante vigente';
  end if;
  if nullif(context ->> 'economic_sector', '') is not null and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements(catalog.values_json) as option(value)
    where catalog.key = 'economic_sectors'
      and option.value ->> 'value' = context ->> 'economic_sector'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un sector económico vigente';
  end if;
  if coalesce((context ->> 'specific_destination')::boolean, false) and not exists (
    select 1
    from public.donation_flow_catalogs() as catalog,
      jsonb_array_elements_text(catalog.values_json) as department(value)
    where catalog.key = 'departments'
      and department.value = context ->> 'destination_department'
  ) then
    raise exception using errcode = '22023', message = 'Selecciona un departamento vigente';
  end if;

  if p_kind = 'money' then
    if p_declared_category_code <> 'apoyo_economico_recursos' or not exists (
      select 1
      from public.donation_flow_catalogs() as catalog,
        jsonb_array_elements(catalog.values_json) as option(value)
      where catalog.key = 'donation_categories'
        and option.value ->> 'value' = p_declared_category_code
        and option.value ->> 'kind' = 'money'
    ) then
      raise exception using errcode = '22023', message = 'Selecciona una categoría económica vigente';
    end if;
  else
    select * into center
    from public.inventory_locations as location
    where location.id = p_preferred_location_id
      and location.event_id = p_event_id
      and location.active;
    if center.id is null then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega activo';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) not between 1 and 20 then
      raise exception using errcode = '22023', message = 'Agrega entre 1 y 20 artículos';
    end if;

    for item in select value from jsonb_array_elements(p_items)
    loop
      if not exists (
        select 1
        from public.donation_flow_catalogs() as catalog,
          jsonb_array_elements(catalog.values_json) as option(value)
        where catalog.key = 'donation_categories'
          and option.value ->> 'value' = item ->> 'category_code'
          and option.value ->> 'kind' = 'in_kind'
          and option.value ->> 'parent_category' = item ->> 'category'
      ) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una categoría detallada vigente';
      end if;
      if not exists (
        select 1
        from public.donation_flow_catalogs() as catalog,
          jsonb_array_elements_text(catalog.values_json) as unit(value)
        where catalog.key = 'units' and unit.value = item ->> 'unit'
      ) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una unidad vigente';
      end if;
      if item ->> 'storage_requirement' = 'frio' and not center.cold_chain_capable then
        raise exception using errcode = '22023', message = 'El centro seleccionado no tiene cadena de frío';
      end if;

      select rule.decision into acceptance_decision
      from public.item_acceptance_rules as rule
      where rule.organization_id = center.organization_id
        and rule.event_id = center.event_id
        and rule.category = item ->> 'category'
        and (rule.location_id = center.id or rule.location_id is null)
        and rule.effective_from <= now()
        and (rule.effective_to is null or rule.effective_to > now())
      order by (rule.location_id = center.id) desc, rule.version desc
      limit 1;
      if acceptance_decision is distinct from 'accepted' then
        raise exception using errcode = '22023', message = 'El centro seleccionado no recibe una de las categorías indicadas';
      end if;
      acceptance_decision := null;
    end loop;
  end if;

  canonical_fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'event_id', p_event_id,
        'organization_id', p_organization_id,
        'kind', p_kind,
        'donor_name_private', btrim(p_donor_name_private),
        'contact_private', p_contact_private,
        'attribution_kind', p_attribution_kind,
        'public_attribution', p_public_attribution,
        'attribution_authorized', coalesce(p_attribution_authorized, false),
        'declared_status', p_declared_status,
        'declared_category_code', p_declared_category_code,
        'items', coalesce(p_items, '[]'::jsonb),
        'declared_amount', p_declared_amount,
        'preferred_location_id', p_preferred_location_id,
        'reporting_context', context,
        'catalog_versions', p_catalog_versions
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  select * into existing
  from public.donation_intakes as intake
  where intake.organization_id = p_organization_id
    and intake.idempotency_key = p_idempotency_key;
  if existing.id is not null then
    if existing.catalog_fingerprint is distinct from canonical_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select existing.id, existing.tracking_code, existing.status, true;
    return;
  end if;

  legacy_status := case p_declared_status
    when 'en_gestion' then 'comprometida'
    when 'entregada' then 'entregada_por_validar'
    else p_declared_status
  end;
  legacy_donor_type := case context ->> 'donor_type'
    when 'persona_natural' then 'persona'
    when 'gremio_asociacion' then 'gremio'
    when 'fundacion_empresarial' then 'fundacion'
    when 'cooperativa' then 'otro'
    when 'entidad_publica' then 'otro'
    else nullif(context ->> 'donor_type', '')
  end;
  legacy_context := jsonb_set(context, '{donor_type}', to_jsonb(coalesce(legacy_donor_type, '')));

  if p_kind = 'in_kind' then
    select coalesce(jsonb_agg(
      case
        when value ->> 'category' in ('Logística','Otro')
          then jsonb_set(value, '{category}', to_jsonb('Refugio'::text))
        else value
      end order by ordinality
    ), '[]'::jsonb)
    into legacy_items
    from jsonb_array_elements(p_items) with ordinality as supplied(value, ordinality);
  end if;

  select * into submitted
  from public.submit_donation_intake(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    legacy_status,
    legacy_items,
    p_declared_amount,
    p_preferred_location_id,
    legacy_context
  );

  if submitted.was_duplicate then
    select * into existing
    from public.donation_intakes as intake
    where intake.id = submitted.intake_id
    for update;
    if existing.catalog_fingerprint is distinct from canonical_fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select existing.id, existing.tracking_code, existing.status, true;
    return;
  end if;

  update public.donation_intakes
  set declared_status = p_declared_status,
      donor_type = nullif(context ->> 'donor_type', ''),
      economic_sector = nullif(context ->> 'economic_sector', ''),
      declared_category_code = p_declared_category_code,
      catalog_versions = p_catalog_versions,
      catalog_fingerprint = canonical_fingerprint
  where id = submitted.intake_id;

  if p_kind = 'in_kind' then
    with supplied as (
      select ordinality::integer as position,
        value ->> 'category' as category,
        value ->> 'category_code' as category_code
      from jsonb_array_elements(p_items) with ordinality as valueset(value, ordinality)
    ), persisted as (
      select stored.id, row_number() over (order by stored.created_at, stored.id)::integer as position
      from public.donation_intake_items as stored
      where stored.intake_id = submitted.intake_id
    )
    update public.donation_intake_items as intake_item
    set category = supplied.category,
        category_code = supplied.category_code
    from supplied
    join persisted using (position)
    where intake_item.id = persisted.id;
  end if;

  return query
  select submitted.intake_id, submitted.tracking_code, submitted.status, false;
end;
$$;

revoke all on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) from authenticated;
revoke all on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text
) to authenticated;

create or replace function public.review_donation_intake(p_intake_id uuid, p_decision text, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake public.donation_intakes;
  donation_id uuid;
begin
  select * into intake from public.donation_intakes where id = p_intake_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Ingreso no encontrado'; end if;
  if not public.has_event_role(intake.event_id, array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes verificar este ingreso';
  end if;
  if intake.status not in ('reported','pending_verification','observed') then
    raise exception using errcode = '22023', message = 'El ingreso no admite esta transición';
  end if;
  if p_decision not in ('approve','observe','reject','duplicate','quarantine','cancel') then
    raise exception using errcode = '22023', message = 'Decisión inválida';
  end if;

  insert into public.intake_verification_decisions(intake_id, decision, note, decided_by)
  values (p_intake_id, p_decision, trim(p_note), (select auth.uid()));
  update public.donation_intakes set status = case p_decision
    when 'approve' then 'approved'::public.intake_status
    when 'observe' then 'observed'::public.intake_status
    when 'reject' then 'rejected'::public.intake_status
    when 'duplicate' then 'duplicate'::public.intake_status
    when 'quarantine' then 'quarantined'::public.intake_status
    else 'cancelled'::public.intake_status end
  where id = p_intake_id;

  if p_decision = 'approve' then
    insert into public.donations(intake_id, event_id, organization_id, kind, status)
    values (intake.id, intake.event_id, intake.organization_id, intake.kind, 'promised')
    on conflict (intake_id) do update set updated_at = public.donations.updated_at
    returning id into donation_id;
    insert into public.donation_items(
      donation_id, source_intake_item_id, category, category_code,
      description, quantity_promised, unit
    )
    select donation_id, item.id, item.category, item.category_code,
      item.description, item.quantity, item.unit
    from public.donation_intake_items as item
    where item.intake_id = intake.id
      and not exists (
        select 1 from public.donation_items as donation_item
        where donation_item.source_intake_item_id = item.id
      );
  end if;
  return donation_id;
end;
$$;

comment on function public.donation_flow_catalogs() is
  'Contrato público, versionado y sin PII para construir el formulario de aportes.';
comment on function public.submit_donation_intake_v2(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb, jsonb, text
) is
  'Registro atómico que valida membresía, aliado verificado, versiones de catálogo y compatibilidad del centro.';
comment on column public.donation_intakes.declared_status is
  'Estado informado por el aliado; incluida Entregada, no cambia el estado operativo sin evidencia y revisión.';
comment on column public.donation_intakes.declared_category_code is
  'Categoría detallada del aporte monetario según el catálogo vigente al registrar.';
comment on column public.donation_intakes.catalog_versions is
  'Versiones autoritativas usadas al validar el registro.';
comment on column public.donation_intake_items.category_code is
  'Categoría detallada declarada; category conserva la agrupación operativa para inventario y asignación.';
comment on column public.item_acceptance_rules.location_id is
  'Centro específico al que aplica la regla; nulo representa la regla predeterminada de la organización.';
