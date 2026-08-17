-- G-025 (P1): la auditoría de varias tablas hijas quedaba sin evento/organización porque
-- el trigger solo leía columnas propias de la fila. Las tablas hijas sin `event_id`/
-- `organization_id` (need_verifications, intake_verification_decisions, receipts,
-- deliveries, expense_approvals, expense_payments) generaban registros de auditoría
-- huérfanos, sin contexto de tenant. Ahora el trigger deriva el tenant del padre.

create or replace function public.audit_row_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  payload jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  changed text[];
  v_event uuid;
  v_org uuid;
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
    end if;
  end if;

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    v_event,
    v_org,
    (select auth.uid()), lower(tg_op), tg_table_name,
    case when payload ? 'id' then (payload->>'id')::uuid else null end,
    jsonb_build_object('changed_fields', to_jsonb(coalesce(changed, '{}'::text[])))
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function public.audit_row_change() is
  'Auditoría append-only; deriva event_id/organization_id del padre para tablas hijas sin columnas de tenant. Cierra G-025.';
