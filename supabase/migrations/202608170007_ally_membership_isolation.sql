-- G-030 · La promocion de aliados concedia autoridad cruzada entre organizaciones.
--
-- La migracion 202608170001 replica las membresias vigentes del evento sobre
-- cada una de las 21 organizaciones aliadas que crea. Con un solo reportante en
-- el evento, esa cuenta terminaba con `partner_reporter` sobre 22
-- organizaciones: podia reportar, corregir y usar los puntos de ANDI, Cruz Roja
-- o la Camara de Comercio.
--
-- Es la suplantacion que la plataforma existe para impedir —«elegir un nombre de
-- una lista no acredita pertenencia»— reintroducida como autoridad realmente
-- concedida. `scripts/verify-rls.mjs` lo detecto: esperaba una organizacion
-- visible para el aliado y veia 22. La comprobacion estaba en lo correcto y por
-- eso no se relajo.
--
-- La replicacion de `event_admin` se conserva: administrar el evento si abarca
-- sus organizaciones, y es rol de operador, no de reporte en nombre de terceros.
--
-- El remoto conserva 15 migraciones, asi que esto corrige antes de que el
-- sobre-otorgamiento salga de local.
--
-- El cuerpo de la funcion es el de 202608170001 sin el bloque de replicacion de
-- `partner_reporter`; se extrajo del archivo original para no reescribirlo de
-- memoria.
--
-- CONSECUENCIA VISIBLE: un gremio sin representante habilitado conserva su punto
-- publico de acopio, pero ningun aliado puede registrar aportes a su nombre ni
-- enrutar una entrega a su punto, porque `assert_delivery_point_tenant` exige
-- mismo tenant (G-022). Esa tension de modelo queda registrada como G-031.

create or replace function public.seed_ally_operational_points(p_event_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  ally record;
  v_org uuid;
  v_loc uuid;
  v_category text;
begin
  if not exists (select 1 from public.emergency_events where id = p_event_id) then
    return;
  end if;

  for ally in
    select * from (values
      ('PROPACIFICO',                                  'propacifico',                          'Cali · centro',                3.4520::numeric, -76.5310::numeric, false, array['Logística','Higiene']::text[]),
      ('ACE Colombia',                                 'ace-colombia',                         'Cali · zona sur',              3.3900,          -76.5400,          false, array['Logística']),
      ('ACODRES',                                      'acodres',                              'Cali · zona granada',          3.4560,          -76.5380,          true,  array['Alimentos','Higiene']),
      ('COTELCO',                                      'cotelco',                              'Cali · zona granada',          3.4575,          -76.5365,          true,  array['Refugio','Higiene','Alimentos']),
      ('Asocaña',                                      'asocana',                              'Valle · corredor del ingenio', 3.5200,          -76.3100,          false, array['Agua','Alimentos','Logística']),
      ('Procaña',                                      'procana',                              'Palmira · zona rural',         3.5390,          -76.3040,          false, array['Alimentos','Logística']),
      ('Adicomex',                                     'adicomex',                             'Buenaventura · zona portuaria',3.8800,          -77.0300,          false, array['Logística']),
      ('Analdex',                                      'analdex',                              'Cali · centro',                3.4510,          -76.5325,          false, array['Logística']),
      ('Fenavi',                                       'fenavi',                               'Palmira · zona industrial',    3.5300,          -76.2980,          true,  array['Alimentos']),
      ('Fenalco',                                      'fenalco',                              'Cali · centro',                3.4505,          -76.5330,          false, array['Logística','Higiene','Alimentos']),
      ('Aciem',                                        'aciem',                                'Cali · centro',                3.4500,          -76.5300,          false, array['Logística']),
      ('AES',                                          'aes',                                  'Yumbo · zona industrial',      3.5850,          -76.4980,          false, array['Logística']),
      ('ACES',                                         'aces',                                 'Cali · zona sur',              3.3950,          -76.5350,          false, array['Higiene','Salud']),
      ('Comité Intergremial y Empresarial del Valle', 'comite-intergremial-empresarial-valle','Cali · centro',                3.4515,          -76.5320,          false, array['Logística']),
      ('Cámara de Comercio de Cali',                  'camara-comercio-cali',                 'Cali · centro',                3.4525,          -76.5340,          false, array['Logística','Higiene','Refugio']),
      ('ANDI – Seccional Valle',                       'andi-seccional-valle',                 'Cali · zona norte',            3.4700,          -76.5150,          false, array['Logística','Higiene']),
      ('Camacol Valle',                                'camacol-valle',                        'Cali · zona sur',              3.3980,          -76.5300,          false, array['Refugio','Logística']),
      ('Acopi Valle',                                  'acopi-valle',                          'Cali · zona industrial',       3.4300,          -76.5100,          false, array['Logística','Higiene']),
      ('Comfandi',                                     'comfandi',                             'Cali · zona sur',              3.4000,          -76.5450,          true,  array['Alimentos','Higiene','Salud']),
      ('Comfenalco Valle',                             'comfenalco-valle',                     'Cali · zona norte',            3.4750,          -76.5100,          true,  array['Alimentos','Higiene','Logística']),
      ('Cruz Roja – Seccional Valle',                  'cruz-roja-seccional-valle',            'Cali · centro',                3.4540,          -76.5290,          true,  array['Salud','Agua','Higiene','Protección'])
    ) as t(org_name, org_slug, zone, lat, lng, cold, cats)
  loop
    -- 1) Organización verificada y activa (idempotente por slug).
    insert into public.organizations(name, slug, verified, status)
    values (ally.org_name, ally.org_slug, true, 'active')
    on conflict (slug) do nothing;
    select id into v_org from public.organizations where slug = ally.org_slug;

    -- 2) Membresías: replica a los administradores vigentes del evento sobre la nueva
    --    organización, y a los reportantes de aliado, sin depender de usuarios fijos.
    insert into public.memberships(user_id, organization_id, event_id, role)
    select distinct m.user_id, v_org, p_event_id, 'event_admin'::public.app_role
    from public.memberships as m
    where m.event_id = p_event_id and m.role = 'event_admin' and m.active
    on conflict (user_id, organization_id, event_id, role) do nothing;

    -- NO se replica `partner_reporter`: reportar en nombre de una organizacion
    -- exige que esa organizacion habilite a su representante. Un gremio sin
    -- representante conserva su punto publico de acopio, pero nadie puede
    -- registrar aportes a su nombre. Cierra G-030.

    -- 3) Punto de acopio sintético (idempotente por organización + evento + nombre).
    select id into v_loc
    from public.inventory_locations
    where organization_id = v_org and event_id = p_event_id and name = 'Acopio ' || ally.org_name;
    if v_loc is null then
      insert into public.inventory_locations(
        event_id, organization_id, name, public_location_text, exact_address_private,
        public_instructions, public_latitude, public_longitude, cold_chain_capable,
        active, accepts_donations, dispatches_shipments
      ) values (
        p_event_id, v_org, 'Acopio ' || ally.org_name, ally.zone,
        'Dirección sintética no operativa · ' || ally.org_name,
        'Coordina el horario después de recibir tu código APO.',
        ally.lat, ally.lng, ally.cold, true, true, false
      ) returning id into v_loc;
    end if;

    -- 4) Reglas de aceptación por categoría del catálogo vigente, versión inicial.
    for v_category in
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
      )
      select
        v_org, p_event_id, v_loc, v_category,
        case when v_category = any(ally.cats) then 'accepted' else 'prohibited' end,
        case when v_category = any(ally.cats)
          then 'Categoría habilitada en la parametrización inicial del aliado.'
          else 'Categoría no habilitada en la parametrización inicial del aliado.'
        end,
        false, 1, now()
      where not exists (
        select 1 from public.item_acceptance_rules as r
        where r.organization_id = v_org and r.event_id = p_event_id
          and r.location_id = v_loc and r.category = v_category
      );
    end loop;
  end loop;
end;
$$;
-- Compensacion de lo ya concedido: se desactiva, no se borra, para conservar
-- historia. El trigger de auditoria deja constancia del cambio.
update public.memberships as m
set active = false
where m.role = 'partner_reporter'
  and m.active
  and exists (
    select 1
    from public.organizations as o
    join public.inventory_locations as l on l.organization_id = o.id
    where o.id = m.organization_id
      and l.name = 'Acopio ' || o.name
  );

comment on function public.seed_ally_operational_points(uuid) is
  'Siembra aliados de referencia como organizaciones con punto de acopio publico. No concede partner_reporter sobre ellas: reportar a nombre de un gremio exige que el gremio habilite a su representante. Cierra G-030.';
