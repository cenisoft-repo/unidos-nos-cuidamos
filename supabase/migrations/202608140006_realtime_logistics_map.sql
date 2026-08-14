-- Cartografía real en cliente + proyección pública segura para acopio y despachos.
-- La proyección solo conserva zonas/coordenadas aproximadas ya autorizadas.

create table public.public_logistics_projections (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  source_type text not null check (source_type in ('collection_center', 'dispatch')),
  source_id uuid not null,
  public_code text not null,
  label text not null,
  status text not null,
  origin_label text,
  origin_latitude numeric(9,6),
  origin_longitude numeric(9,6),
  destination_label text,
  destination_latitude numeric(9,6),
  destination_longitude numeric(9,6),
  published boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (source_type, source_id),
  check ((origin_latitude is null) = (origin_longitude is null)),
  check ((destination_latitude is null) = (destination_longitude is null)),
  check (origin_latitude is null or origin_latitude between -90 and 90),
  check (origin_longitude is null or origin_longitude between -180 and 180),
  check (destination_latitude is null or destination_latitude between -90 and 90),
  check (destination_longitude is null or destination_longitude between -180 and 180)
);

create index public_logistics_projections_event_idx
  on public.public_logistics_projections(event_id, source_type, updated_at desc)
  where published;

alter table public.public_logistics_projections enable row level security;
alter table public.public_logistics_projections replica identity full;

create policy "public reads published logistics"
  on public.public_logistics_projections
  for select
  using (published);

revoke all on public.public_logistics_projections from anon, authenticated;
grant select on public.public_logistics_projections to anon, authenticated;

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
    location.active and location.public_latitude is not null and location.public_longitude is not null,
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

create or replace function public.sync_public_shipment_projection(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare projection record;
begin
  select
    shipment.event_id,
    shipment.id,
    shipment.shipment_code,
    shipment.status::text,
    location.name as origin_name,
    location.public_location_text as origin_label,
    location.public_latitude as origin_latitude,
    location.public_longitude as origin_longitude,
    coalesce(need_projection.location_label, shipment.public_destination) as destination_label,
    need_projection.latitude as destination_latitude,
    need_projection.longitude as destination_longitude,
    need_projection.published as destination_published
  into projection
  from public.shipments as shipment
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  left join public.inventory_locations as location on location.id = lot.location_id
  left join public.need_items as need_item on need_item.id = allocation.need_item_id
  left join public.need_cases as need_case on need_case.id = need_item.need_case_id
  left join public.public_need_projections as need_projection on need_projection.source_need_id = need_case.id
  where shipment.id = p_shipment_id
  order by shipment_item.id nulls last
  limit 1;

  if not found then
    update public.public_logistics_projections
    set published = false, updated_at = now()
    where source_type = 'dispatch' and source_id = p_shipment_id;
    return;
  end if;

  insert into public.public_logistics_projections(
    event_id, source_type, source_id, public_code, label, status,
    origin_label, origin_latitude, origin_longitude,
    destination_label, destination_latitude, destination_longitude,
    published, updated_at
  ) values (
    projection.event_id,
    'dispatch',
    projection.id,
    projection.shipment_code,
    'Despacho ' || projection.shipment_code,
    projection.status,
    nullif(concat_ws(' · ', projection.origin_name, projection.origin_label), ''),
    projection.origin_latitude,
    projection.origin_longitude,
    projection.destination_label,
    projection.destination_latitude,
    projection.destination_longitude,
    projection.status in ('dispatched', 'in_transit', 'delivered', 'validated')
      and projection.origin_latitude is not null
      and projection.origin_longitude is not null
      and projection.destination_latitude is not null
      and projection.destination_longitude is not null
      and coalesce(projection.destination_published, false),
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
    destination_label = excluded.destination_label,
    destination_latitude = excluded.destination_latitude,
    destination_longitude = excluded.destination_longitude,
    published = excluded.published,
    updated_at = now();
end;
$$;

create or replace function public.sync_collection_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare shipment_row record;
begin
  if tg_op = 'DELETE' then
    perform public.sync_public_collection_projection(old.id);
    return old;
  end if;

  perform public.sync_public_collection_projection(new.id);
  for shipment_row in
    select distinct shipment_item.shipment_id
    from public.shipment_items as shipment_item
    join public.allocations as allocation on allocation.id = shipment_item.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    where lot.location_id = new.id
  loop
    perform public.sync_public_shipment_projection(shipment_row.shipment_id);
  end loop;
  return new;
end;
$$;

create or replace function public.sync_shipment_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_public_shipment_projection(case when tg_op = 'DELETE' then old.id else new.id end);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.sync_shipment_item_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_public_shipment_projection(case when tg_op = 'DELETE' then old.shipment_id else new.shipment_id end);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.sync_need_logistics_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare shipment_row record;
begin
  for shipment_row in
    select distinct shipment_item.shipment_id
    from public.shipment_items as shipment_item
    join public.allocations as allocation on allocation.id = shipment_item.allocation_id
    join public.need_items as need_item on need_item.id = allocation.need_item_id
    where need_item.need_case_id = new.source_need_id
  loop
    perform public.sync_public_shipment_projection(shipment_row.shipment_id);
  end loop;
  return new;
end;
$$;

create trigger inventory_locations_public_projection
after insert or update or delete on public.inventory_locations
for each row execute function public.sync_collection_projection_trigger();

create trigger shipments_public_projection
after insert or update or delete on public.shipments
for each row execute function public.sync_shipment_projection_trigger();

create trigger shipment_items_public_projection
after insert or update or delete on public.shipment_items
for each row execute function public.sync_shipment_item_projection_trigger();

create trigger public_need_logistics_projection
after update on public.public_need_projections
for each row execute function public.sync_need_logistics_projection_trigger();

create or replace function public.public_logistics_map(p_event_id uuid)
returns table(
  id uuid,
  source_type text,
  public_code text,
  label text,
  status text,
  origin_label text,
  origin_latitude double precision,
  origin_longitude double precision,
  destination_label text,
  destination_latitude double precision,
  destination_longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    projection.id,
    projection.source_type,
    projection.public_code,
    projection.label,
    projection.status,
    projection.origin_label,
    projection.origin_latitude::double precision,
    projection.origin_longitude::double precision,
    projection.destination_label,
    projection.destination_latitude::double precision,
    projection.destination_longitude::double precision,
    projection.updated_at
  from public.public_logistics_projections as projection
  where projection.event_id = p_event_id and projection.published
  order by projection.source_type, projection.updated_at desc;
$$;

revoke all on function public.sync_public_collection_projection(uuid) from public, anon, authenticated;
revoke all on function public.sync_public_shipment_projection(uuid) from public, anon, authenticated;
revoke all on function public.sync_collection_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_shipment_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_shipment_item_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_need_logistics_projection_trigger() from public, anon, authenticated;
grant execute on function public.public_logistics_map(uuid) to anon, authenticated;

select public.sync_public_collection_projection(id) from public.inventory_locations;
select public.sync_public_shipment_projection(id) from public.shipments;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'public_logistics_projections'
  ) then
    alter publication supabase_realtime add table public.public_logistics_projections;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgname = 'inventory_locations_audit' and tgrelid = 'public.inventory_locations'::regclass
  ) then
    create trigger inventory_locations_audit
    after insert or update or delete on public.inventory_locations
    for each row execute function public.audit_row_change();
  end if;
end;
$$;

comment on table public.public_logistics_projections is
  'Proyección cartográfica pública: centros y rutas origen-destino aproximadas. No contiene direcciones, transportadores, custodios ni GPS.';
comment on function public.public_logistics_map(uuid) is
  'Devuelve centros activos y despachos publicables con coordenadas aproximadas para MapLibre y Realtime.';
