-- G-028 · «Observación → corregir sin borrar historia → volver a verificación»
--
-- Antes de esta migración `observed` era un callejón sin salida: el verificador
-- podía marcar «Con observaciones» y no existía ninguna función ni superficie
-- para que el aliado corrigiera y devolviera el aporte a la cola. El nodo del
-- diagrama de recorrido quedaba sin implementación ni cobertura.
--
-- `donation_intakes` ya traía `version` y `previous_version_id` sin usar: la
-- corrección los activa. La historia no se sobrescribe — cada enmienda queda en
-- una fila append-only con el antes y el después de cada campo.
--
-- `donation_intake_items` NO está en la lista de tablas con trigger de
-- auditoría, así que un cambio de cantidad no dejaría rastro por sí solo. Por
-- eso la fila de enmienda guarda el diff explícito y no se delega al trigger.

create table if not exists public.intake_amendments (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.donation_intakes(id),
  from_version integer not null check (from_version > 0),
  to_version integer not null check (to_version > 0),
  note text not null check (char_length(btrim(note)) between 10 and 1000),
  -- [{"field":"item:<uuid>","before":"100.000","after":"80.000"}, ...]
  changes jsonb not null default '[]'::jsonb,
  amended_by uuid not null references auth.users(id),
  amended_at timestamptz not null default now(),
  check (to_version > from_version)
);

create index if not exists intake_amendments_intake_idx
  on public.intake_amendments (intake_id, amended_at desc);
-- Convención del proyecto (`202608140009`): toda clave foránea lleva índice de
-- soporte. `database_test.sql` lo comprueba y falla si falta alguno.
create index if not exists intake_amendments_amended_by_idx
  on public.intake_amendments (amended_by);

alter table public.intake_amendments enable row level security;

-- Misma regla de lectura que las decisiones de verificación: solo la
-- organización dueña del ingreso y quien verifica el evento.
drop policy if exists "org members read intake amendments" on public.intake_amendments;
create policy "org members read intake amendments"
  on public.intake_amendments for select to authenticated
  using (
    exists (
      select 1 from public.donation_intakes i
      where i.id = intake_id
        and (
          public.is_org_member(i.organization_id, i.event_id)
          or public.has_event_role(i.event_id, array['verifier','event_admin','auditor']::public.app_role[])
        )
    )
  );

-- Append-only: ninguna política de insert/update/delete para `authenticated`.
-- La única escritura ocurre dentro de la RPC, que es `security definer`.

create trigger intake_amendments_audit
  after insert or update or delete on public.intake_amendments
  for each row execute function public.audit_row_change();

create or replace function public.amend_donation_intake(
  p_intake_id uuid,
  p_note text,
  p_expected_version integer,
  p_items jsonb default '[]'::jsonb,
  p_declared_amount numeric default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake public.donation_intakes;
  item public.donation_intake_items;
  entry jsonb;
  new_quantity numeric;
  changes jsonb := '[]'::jsonb;
  next_version integer;
  clean_note text := btrim(coalesce(p_note, ''));
begin
  select * into intake from public.donation_intakes where id = p_intake_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Ingreso no encontrado';
  end if;

  -- Solo la organización dueña puede corregir, y solo con rol de reporte.
  -- `has_any_role` acota organización y evento a la vez: cierra el cruce de tenant.
  if not public.has_any_role(
    intake.organization_id, intake.event_id, array['partner_reporter']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes corregir este ingreso';
  end if;

  -- Corregir es responder una observación: cualquier otro estado no aplica.
  if intake.status <> 'observed' then
    raise exception using errcode = '22023', message = 'Solo un ingreso con observaciones admite corrección';
  end if;

  -- Concurrencia optimista: si el ingreso cambió desde que se leyó, no se pisa.
  if p_expected_version is null or p_expected_version <> intake.version then
    raise exception using errcode = '40001',
      message = 'El ingreso cambió desde que lo abriste; vuelve a cargarlo';
  end if;

  if char_length(clean_note) < 10 then
    raise exception using errcode = '22023', message = 'Explica la corrección en al menos 10 caracteres';
  end if;
  if public.contains_sensitive_content(clean_note) then
    raise exception using errcode = '22023',
      message = 'La respuesta no puede incluir contactos, cuentas ni datos sensibles';
  end if;

  -- Cantidades por artículo. Cada línea debe pertenecer a este ingreso.
  for entry in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    select * into item
    from public.donation_intake_items
    where id = (entry->>'item_id')::uuid and intake_id = p_intake_id
    for update;

    if not found then
      raise exception using errcode = '22023',
        message = 'Una de las líneas corregidas no pertenece a este ingreso';
    end if;

    -- Se ajusta a la escala de la columna para que el antes y el después del
    -- diff sean comparables; sin esto quedaban '100.000' contra '80'.
    new_quantity := (entry->>'quantity')::numeric(14,3);
    if new_quantity is null or new_quantity <= 0 then
      raise exception using errcode = '22023', message = 'La cantidad corregida debe ser mayor que cero';
    end if;

    if new_quantity <> item.quantity then
      changes := changes || jsonb_build_object(
        'field', 'item:' || item.id::text,
        'before', item.quantity::text,
        'after', new_quantity::text
      );
      update public.donation_intake_items set quantity = new_quantity where id = item.id;
    end if;
  end loop;

  -- El monto declarado solo existe en aportes de dinero.
  if p_declared_amount is not null then
    if intake.kind <> 'money' then
      raise exception using errcode = '22023', message = 'Solo un aporte económico tiene monto declarado';
    end if;
    if p_declared_amount <= 0 then
      raise exception using errcode = '22023', message = 'El monto corregido debe ser mayor que cero';
    end if;
    if p_declared_amount <> intake.declared_amount then
      changes := changes || jsonb_build_object(
        'field', 'declared_amount',
        'before', intake.declared_amount::text,
        'after', p_declared_amount::text
      );
      update public.donation_intakes set declared_amount = p_declared_amount where id = p_intake_id;
    end if;
  end if;

  next_version := intake.version + 1;

  -- Vuelve a la cola: quien verifica decide sobre la versión nueva.
  update public.donation_intakes
  set version = next_version,
      status = 'pending_verification',
      updated_at = now()
  where id = p_intake_id;

  insert into public.intake_amendments(
    intake_id, from_version, to_version, note, changes, amended_by
  )
  values (
    p_intake_id, intake.version, next_version, clean_note, changes, (select auth.uid())
  );

  return next_version;
end;
$$;

revoke all on function public.amend_donation_intake(uuid, text, integer, jsonb, numeric)
  from public, anon, authenticated;
grant execute on function public.amend_donation_intake(uuid, text, integer, jsonb, numeric)
  to authenticated;

comment on table public.intake_amendments is
  'Historial append-only de correcciones del aliado a un ingreso observado; conserva el antes y el después de cada campo. Cierra G-028.';
comment on function public.amend_donation_intake(uuid, text, integer, jsonb, numeric) is
  'Corrección del aliado sobre un ingreso observado: valida organización, estado y versión esperada, registra el diff y devuelve el aporte a verificación sin sobrescribir historia.';
