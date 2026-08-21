-- G-074 · Un rechazo total no dejaba huella, y la cola sin conexión lo repetía.
--
-- `receive_donation` tiene una rama de salida temprana para el rechazo total: si no se acepta
-- nada, incrementa `quantity_rejected`, marca el aporte como rechazado y **devuelve sin
-- escribir un solo movimiento de Kardex**. Como la idempotencia se resuelve buscando ese
-- movimiento, un reintento con la misma clave no encuentra nada y vuelve a sumar.
--
-- Comprobado contra la base, no razonado:
--
--   rechazo total de 10, con clave  -> rechazado = 10
--   la cola reintenta, misma clave  -> rechazado = 20
--   otro reintento                  -> rechazado = 30 de 30 prometidos
--   y después, una recepción real   -> «Las cantidades no concilian con la promesa»
--
-- El aporte queda bloqueado **para siempre**, y quien lo bloquea es el propio guardián de la
-- función. Lo alcanza cualquiera que rechace estando sin conexión: la cola reintenta sola y
-- cada reintento empeora el estado sin poder eliminarse.
--
-- POR QUÉ UNA TABLA Y NO UN MOVIMIENTO DE CERO
-- -------------------------------------------
-- La solución obvia sería escribir un movimiento de Kardex con cantidad cero que llevara la
-- clave. No se puede: `stock_movements.lot_id` es obligatoria, y en un rechazo total no hay
-- lote —precisamente porque nada entró—. Crear un lote de cero para colgar la huella sería
-- escribir en el inventario algo que no existe, que es la regla número uno del proyecto.
--
-- Así que el rechazo pasa a tener su propio registro. Y de paso se arregla algo que estaba
-- mal aparte: hoy un rechazo total solo deja un contador incrementado. No quién, no cuándo,
-- no en qué bodega. Un hecho operacional que decide que unos bienes no entran merece más que
-- eso.

create table if not exists public.intake_rejections (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  donation_item_id uuid not null references public.donation_items(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete cascade,
  quantity_rejected numeric not null check (quantity_rejected >= 0),
  condition text,
  reason text,
  idempotency_key text not null,
  actor_id uuid,
  created_at timestamptz not null default now(),
  -- La misma forma de unicidad que el resto del sistema: la clave pertenece a una
  -- organizacion. Buscarla sin decir de quien es fue el defecto de B5 (ADR-023).
  unique (organization_id, idempotency_key)
);

comment on table public.intake_rejections is
  'Rechazos totales de recepcion. Append-only: da al rechazo el registro que no tenia y la huella idempotente que la cola sin conexion necesita para no repetirlo (G-074).';

create index if not exists intake_rejections_event_id_idx on public.intake_rejections (event_id);
create index if not exists intake_rejections_organization_id_idx on public.intake_rejections (organization_id);
create index if not exists intake_rejections_donation_item_id_idx on public.intake_rejections (donation_item_id);
create index if not exists intake_rejections_location_id_idx on public.intake_rejections (location_id);

-- Append-only como sus hermanas: un rechazo es un hecho, y los hechos no se editan. Si hubo
-- error, se compensa recibiendo lo que corresponda, no reescribiendo lo que se dijo.
drop trigger if exists intake_rejections_immutable on public.intake_rejections;
create trigger intake_rejections_immutable
  before update or delete on public.intake_rejections
  for each row execute function public.prevent_mutation();

drop trigger if exists intake_rejections_audit on public.intake_rejections;
create trigger intake_rejections_audit
  after insert on public.intake_rejections
  for each row execute function public.audit_row_change();

alter table public.intake_rejections enable row level security;

create policy "org members read intake rejections" on public.intake_rejections
  for select using (public.is_org_member(organization_id, event_id));

-- Solo lectura desde la API, y la escribe unicamente `receive_donation`.
revoke all on table public.intake_rejections from public, anon, authenticated, service_role;
grant select on table public.intake_rejections to authenticated;

-- ---------------------------------------------------------------- la funcion

create or replace function public.receive_donation(
  p_donation_item_id uuid,
  p_location_id uuid,
  p_accepted numeric,
  p_rejected numeric,
  p_condition text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare item public.donation_items;
declare donation public.donations;
declare location public.inventory_locations;
declare existing uuid;
declare lot_id uuid;
declare organizacion uuid;
begin
  -- B5 · La clave de idempotencia es unica POR ORGANIZACION, asi que buscarla sola encuentra
  -- la de otra. Se resuelve la organizacion una vez y se usa en las dos busquedas.
  select propietaria.organization_id into organizacion
  from public.donation_items as articulo
  join public.donations as propietaria on propietaria.id = articulo.donation_id
  where articulo.id = p_donation_item_id;

  select l.id into existing from public.inventory_lots l
    join public.stock_movements s on s.lot_id = l.id
    where s.idempotency_key = p_idempotency_key
      and s.organization_id = organizacion;
  if found then return existing; end if;

  -- G-074 · La segunda huella: un rechazo total no crea lote ni movimiento, asi que sin esto
  -- el reintento no encontraba nada y volvia a sumar al contador de rechazado.
  if exists (
    select 1 from public.intake_rejections as rechazo
    where rechazo.idempotency_key = p_idempotency_key
      and rechazo.organization_id = organizacion
  ) then
    return null;
  end if;

  select * into item from public.donation_items where id = p_donation_item_id for update;
  select * into donation from public.donations where id = item.donation_id for update;
  select * into location from public.inventory_locations where id = p_location_id;
  if not found or item.id is null or donation.id is null then raise exception using errcode = 'P0002', message = 'Donación o centro no encontrado'; end if;
  if not public.has_any_role(donation.organization_id, donation.event_id, array['warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes recibir en este centro';
  end if;
  if location.organization_id <> donation.organization_id or location.event_id <> donation.event_id then
    raise exception using errcode = '42501', message = 'Centro fuera del tenant';
  end if;
  if not public.has_location_scope(
    location.id,
    array['warehouse_operator','event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'Esa bodega no está dentro de tu alcance';
  end if;
  if p_accepted < 0 or p_rejected < 0 or item.quantity_received + item.quantity_rejected + p_accepted + p_rejected > item.quantity_promised then
    raise exception using errcode = '22023', message = 'Las cantidades no concilian con la promesa';
  end if;
  if p_accepted = 0 then
    -- El registro va ANTES de tocar el contador: si algo fallara entre las dos escrituras, es
    -- preferible una huella sin contador que un contador sin huella, que es lo que permitia
    -- repetir. Van en la misma transaccion, asi que en la practica no se separan.
    insert into public.intake_rejections(
      event_id, organization_id, donation_item_id, location_id,
      quantity_rejected, condition, reason, idempotency_key, actor_id
    ) values (
      donation.event_id, donation.organization_id, item.id, location.id,
      p_rejected, p_condition, 'Recepción rechazada en su totalidad', p_idempotency_key,
      (select auth.uid())
    );
    update public.donation_items set quantity_rejected = quantity_rejected + p_rejected where id = item.id;
    update public.donations set status = 'rejected' where id = donation.id;
    return null;
  end if;

  insert into public.inventory_lots(event_id, organization_id, donation_item_id, location_id, category, quantity_initial, unit, condition, received_by)
  values (donation.event_id, donation.organization_id, item.id, location.id, item.category, p_accepted, item.unit, p_condition, (select auth.uid()))
  returning id into lot_id;
  insert into public.stock_movements(event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id)
  values (donation.event_id, donation.organization_id, lot_id, 'receipt', p_accepted, p_idempotency_key, 'Recepción aceptada', (select auth.uid()));
  update public.donation_items set quantity_received = quantity_received + p_accepted, quantity_rejected = quantity_rejected + p_rejected where id = item.id;
  update public.donations set status = case when p_accepted + p_rejected < item.quantity_promised then 'partial'::public.donation_status else 'received'::public.donation_status end where id = donation.id;
  return lot_id;
end;
$function$;
