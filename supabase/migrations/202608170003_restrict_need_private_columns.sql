-- G-021 (P0): un partner_reporter (o cualquier miembro del evento) podía leer la ubicación
-- exacta y el contacto privado de las necesidades por la política amplia de miembros.
-- RLS es por fila, no por columna, así que la superficie privada se cierra con privilegios
-- por columna: el rol autenticado solo puede seleccionar columnas públicas; la ubicación
-- operativa exacta, la dirección exacta, el contacto privado y el reportante quedan fuera
-- de la consulta directa. La verificación autorizada los obtiene por una RPC mínima.
--
-- La política de fila "event members read needs" se conserva: gobierna qué filas ve cada
-- miembro; los privilegios por columna gobiernan qué campos. La app solo lee columnas
-- públicas, así que ningún recorrido vigente se rompe.

revoke select on public.need_cases from authenticated;
grant select (
  id, event_id, organization_id, tracking_code, category, description, facts,
  status, priority_score, public_location_text, source_type, expires_at,
  visibility, duplicate_of, created_at, updated_at
) on public.need_cases to authenticated;

-- Detalle privado de una necesidad, solo para verificación o administración del evento.
create or replace function public.need_case_private_detail(p_need_id uuid)
returns table(
  id uuid,
  tracking_code text,
  exact_address_private text,
  contact_private jsonb,
  operational_location_geojson jsonb,
  submitted_by uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event uuid;
begin
  select event_id into v_event from public.need_cases where need_cases.id = p_need_id;
  if v_event is null then
    raise exception using errcode = '22023', message = 'Necesidad no encontrada';
  end if;
  if (select auth.uid()) is null
     or not public.has_event_role(v_event, array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo verificación o administración del evento puede ver los datos privados de la necesidad';
  end if;

  return query
  select
    need.id,
    need.tracking_code,
    need.exact_address_private,
    need.contact_private,
    case
      when need.operational_location is null then null
      else extensions.st_asgeojson(need.operational_location)::jsonb
    end,
    need.submitted_by
  from public.need_cases as need
  where need.id = p_need_id;
end;
$$;

revoke all on function public.need_case_private_detail(uuid) from public, anon, authenticated;
grant execute on function public.need_case_private_detail(uuid) to authenticated;

comment on function public.need_case_private_detail(uuid) is
  'Datos privados de una necesidad (dirección exacta, contacto, ubicación operativa, reportante); solo verifier/event_admin del evento. Cierra G-021.';
