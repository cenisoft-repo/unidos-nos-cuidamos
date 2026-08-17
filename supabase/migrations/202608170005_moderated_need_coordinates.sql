-- G-024 (P1, parte 1): el reporte ciudadano no producía coordenadas aprobadas, así que una
-- necesidad publicada por la app no aparecía en el mapa. Ahora la verificación autorizada
-- puede asignar una coordenada pública APROXIMADA y MODERADA (redondeada a ~110 m) al
-- verificar/publicar; nunca la ubicación exacta. Al publicar, esa coordenada alimenta la
-- proyección pública (cuya geometría se genera de latitud/longitud) y el mapa la muestra.
-- (La parte 2 —despachos visibles en el mapa— ya está cubierta por 202608160005.)

alter table public.need_cases
  add column if not exists public_latitude numeric(9,6),
  add column if not exists public_longitude numeric(9,6);

alter table public.need_cases
  add constraint need_cases_public_latitude_range
    check (public_latitude is null or public_latitude between -4.5 and 13.5),
  add constraint need_cases_public_longitude_range
    check (public_longitude is null or public_longitude between -82 and -66.5),
  add constraint need_cases_public_coordinate_pair
    check ((public_latitude is null) = (public_longitude is null));

drop function if exists public.review_need_case(uuid, text, text, integer, timestamptz);

create or replace function public.review_need_case(
  p_need_id uuid,
  p_decision text,
  p_note text,
  p_confidence integer default null,
  p_expires_at timestamptz default null,
  p_public_latitude numeric default null,
  p_public_longitude numeric default null
)
returns public.need_status language plpgsql security definer set search_path = '' as $$
declare
  target public.need_cases;
  next_status public.need_status;
  item public.need_items;
  -- Coordenada moderada: precisión aproximada (~110 m) para no revelar el punto exacto.
  v_lat numeric := round(p_public_latitude, 3);
  v_lon numeric := round(p_public_longitude, 3);
begin
  select * into target from public.need_cases where id = p_need_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Necesidad no encontrada'; end if;
  if not public.has_event_role(target.event_id, array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes verificar esta necesidad';
  end if;
  if p_decision not in ('verify','observe','reject','duplicate','disprove','renew','expire','publish','suspend') then
    raise exception using errcode = '22023', message = 'Decisión inválida';
  end if;

  -- Coordenada aproximada opcional: se envían ambas o ninguna, y dentro de Colombia.
  if (p_public_latitude is null) <> (p_public_longitude is null) then
    raise exception using errcode = '22023', message = 'Proporciona latitud y longitud aproximadas juntas o ninguna';
  end if;
  if v_lat is not null and (v_lat not between -4.5 and 13.5 or v_lon not between -82 and -66.5) then
    raise exception using errcode = '22023', message = 'La coordenada aproximada debe estar dentro de Colombia';
  end if;
  -- Coordenada efectiva: la recién moderada o la ya aprobada antes.
  v_lat := coalesce(v_lat, target.public_latitude);
  v_lon := coalesce(v_lon, target.public_longitude);

  next_status := case p_decision
    when 'verify' then 'verified'::public.need_status
    when 'observe' then 'in_verification'::public.need_status
    when 'reject' then 'rejected'::public.need_status
    when 'duplicate' then 'duplicate'::public.need_status
    when 'disprove' then 'disproved'::public.need_status
    when 'renew' then target.status
    when 'expire' then 'expired'::public.need_status
    when 'publish' then 'published'::public.need_status
    else 'suspended'::public.need_status end;

  if p_decision = 'publish' and target.status not in ('verified','published','partially_covered') then
    raise exception using errcode = '22023', message = 'Solo una necesidad verificada puede publicarse';
  end if;

  insert into public.need_verifications(need_case_id, decision, note, confidence, expires_at, decided_by)
  values (target.id, p_decision, trim(p_note), p_confidence, p_expires_at, (select auth.uid()));

  update public.need_cases set
    status = next_status,
    priority_score = case when p_decision in ('verify','publish') then p_confidence else priority_score end,
    expires_at = case when p_decision = 'renew' then coalesce(p_expires_at, now() + interval '24 hours') else expires_at end,
    public_latitude = v_lat,
    public_longitude = v_lon,
    visibility = case when p_decision = 'publish' then 'public'::public.visibility_level when p_decision in ('suspend','expire') then 'private'::public.visibility_level else visibility end
  where id = target.id;

  if p_decision = 'publish' then
    select * into item from public.need_items where need_case_id = target.id order by created_at limit 1;
    insert into public.public_need_projections(
      source_need_id,event_id,category,summary,location_label,latitude,longitude,status,confidence_label,
      verified_at,expires_at,needed_quantity,covered_quantity,unit,published
    ) values (
      target.id,target.event_id,target.category,left(target.description,180),target.public_location_text,
      v_lat,v_lon,'Publicada','Verificada por organización',now(),target.expires_at,
      item.quantity_required,item.quantity_covered,item.unit,true
    ) on conflict (source_need_id) do update set
      summary = excluded.summary, location_label = excluded.location_label,
      latitude = excluded.latitude, longitude = excluded.longitude,
      status = excluded.status, confidence_label = excluded.confidence_label,
      verified_at = excluded.verified_at, expires_at = excluded.expires_at,
      needed_quantity = excluded.needed_quantity, covered_quantity = excluded.covered_quantity,
      unit = excluded.unit, published = true, updated_at = now();
  elsif p_decision in ('suspend','expire','reject','disprove') then
    update public.public_need_projections set published = false, updated_at = now() where source_need_id = target.id;
  end if;
  return next_status;
end;
$$;

revoke all on function public.review_need_case(uuid,text,text,integer,timestamptz,numeric,numeric) from public, anon, authenticated;
grant execute on function public.review_need_case(uuid,text,text,integer,timestamptz,numeric,numeric) to authenticated;

comment on function public.review_need_case(uuid,text,text,integer,timestamptz,numeric,numeric) is
  'Verifica/publica una necesidad; la verificación puede asignar una coordenada pública aproximada moderada (~110 m) que alimenta el mapa sin revelar la ubicación exacta. Cierra G-024 (parte ciudadana).';
