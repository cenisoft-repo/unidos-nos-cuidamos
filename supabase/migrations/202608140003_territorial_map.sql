-- Capa geoespacial pública para el centro territorial.
-- Solo transforma coordenadas aproximadas ya aprobadas para publicación.

create extension if not exists postgis with schema extensions;

alter table public.public_need_projections
  add column if not exists approximate_location extensions.geometry(Point, 4326)
  generated always as (
    case
      when latitude is null or longitude is null then null
      else extensions.st_setsrid(
        extensions.st_makepoint(longitude::double precision, latitude::double precision),
        4326
      )
    end
  ) stored;

create index if not exists public_need_projections_approximate_location_gix
  on public.public_need_projections
  using gist (approximate_location)
  where published;

create or replace function public.public_need_map(
  p_event_id uuid,
  p_min_longitude double precision default null,
  p_min_latitude double precision default null,
  p_max_longitude double precision default null,
  p_max_latitude double precision default null
)
returns table(
  id uuid,
  category text,
  summary text,
  location_label text,
  status text,
  needed_quantity numeric,
  covered_quantity numeric,
  unit text,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    projection.id,
    projection.category,
    projection.summary,
    projection.location_label,
    projection.status,
    projection.needed_quantity,
    projection.covered_quantity,
    projection.unit,
    extensions.st_y(projection.approximate_location),
    extensions.st_x(projection.approximate_location),
    projection.updated_at
  from public.public_need_projections as projection
  where projection.event_id = p_event_id
    and projection.published
    and projection.expires_at > now()
    and projection.approximate_location is not null
    and (
      p_min_longitude is null
      or p_min_latitude is null
      or p_max_longitude is null
      or p_max_latitude is null
      or extensions.st_intersects(
        projection.approximate_location,
        extensions.st_makeenvelope(
          p_min_longitude,
          p_min_latitude,
          p_max_longitude,
          p_max_latitude,
          4326
        )
      )
    )
  order by projection.updated_at desc;
$$;

grant execute on function public.public_need_map(uuid, double precision, double precision, double precision, double precision)
  to anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'public_need_projections'
  ) then
    alter publication supabase_realtime add table public.public_need_projections;
  end if;
end;
$$;

comment on column public.public_need_projections.approximate_location is
  'Punto público aproximado derivado de la proyección aprobada; nunca contiene una dirección operacional.';

comment on function public.public_need_map(uuid, double precision, double precision, double precision, double precision) is
  'Devuelve únicamente necesidades públicas vigentes con coordenadas aproximadas y filtro espacial opcional.';
