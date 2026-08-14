alter table public.donation_items add constraint donation_items_source_unique unique (source_intake_item_id);
alter table public.shipments add column idempotency_key text;
alter table public.shipments add constraint shipments_idempotency_unique unique (organization_id, idempotency_key);
alter table public.deliveries add column idempotency_key text;
alter table public.deliveries add constraint deliveries_idempotency_unique unique (shipment_id, idempotency_key);

create or replace function public.place_lot_control(
  p_lot_id uuid,
  p_action text,
  p_reason text
)
returns public.lot_status language plpgsql security definer set search_path = '' as $$
declare lot public.inventory_lots;
declare next_status public.lot_status;
begin
  select * into lot from public.inventory_lots where id = p_lot_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Lote no encontrado'; end if;
  if not public.has_any_role(lot.organization_id, lot.event_id, array['warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes controlar este lote';
  end if;
  if p_action not in ('hold','release','recall','dispose') then raise exception using errcode = '22023', message = 'Acción de lote inválida'; end if;
  if p_action = 'release' and lot.status not in ('hold','quarantined') then raise exception using errcode = '22023', message = 'Solo un lote retenido puede liberarse'; end if;
  next_status := case p_action when 'hold' then 'hold'::public.lot_status when 'release' then 'available'::public.lot_status when 'recall' then 'recalled'::public.lot_status else 'disposed'::public.lot_status end;
  insert into public.lot_hold_or_recalls(lot_id, action, reason, decided_by) values (lot.id, p_action, trim(p_reason), (select auth.uid()));
  update public.inventory_lots set status = next_status where id = lot.id;
  return next_status;
end;
$$;

create or replace function public.create_shipment(
  p_allocation_id uuid,
  p_public_destination text,
  p_carrier_name text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target public.allocations;
declare lot public.inventory_lots;
declare shipment_id uuid;
declare donation_id uuid;
begin
  select s.id into shipment_id from public.shipments s where s.idempotency_key = p_idempotency_key;
  if found then return shipment_id; end if;
  select * into target from public.allocations where id = p_allocation_id for update;
  if not found or target.status <> 'reserved' then raise exception using errcode = '22023', message = 'La asignación no está disponible para despacho'; end if;
  select * into lot from public.inventory_lots where id = target.lot_id for update;
  if lot.status in ('quarantined','hold','recalled','disposed') then raise exception using errcode = '22023', message = 'El lote está bloqueado y no puede salir'; end if;
  if not public.has_any_role(target.organization_id, target.event_id, array['logistics_operator','warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes crear este despacho';
  end if;

  insert into public.shipments(event_id,organization_id,status,carrier_name,public_destination,dispatched_at,created_by,idempotency_key)
  values (target.event_id,target.organization_id,'dispatched',nullif(trim(p_carrier_name),''),trim(p_public_destination),now(),(select auth.uid()),p_idempotency_key)
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

create or replace function public.register_delivery(
  p_shipment_id uuid,
  p_quantity_delivered numeric,
  p_quantity_damaged numeric,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target public.shipments;
declare shipped numeric;
declare delivery_id uuid;
begin
  select d.id into delivery_id from public.deliveries d where d.shipment_id = p_shipment_id and d.idempotency_key = p_idempotency_key;
  if found then return delivery_id; end if;
  select * into target from public.shipments where id = p_shipment_id for update;
  if not found or target.status not in ('dispatched','in_transit','incident') then raise exception using errcode = '22023', message = 'El despacho no admite entrega'; end if;
  if not public.has_any_role(target.organization_id,target.event_id,array['logistics_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes registrar esta entrega';
  end if;
  select coalesce(sum(quantity),0) into shipped from public.shipment_items where shipment_id = target.id;
  if p_quantity_delivered < 0 or p_quantity_damaged < 0 or p_quantity_delivered + p_quantity_damaged <> shipped then
    raise exception using errcode = '22023', message = 'La entrega y la novedad deben conciliar con el despacho';
  end if;
  insert into public.deliveries(shipment_id,status,quantity_delivered,quantity_damaged,delivered_at,idempotency_key)
  values (target.id,case when p_quantity_damaged > 0 then 'incident' else 'delivered' end,p_quantity_delivered,p_quantity_damaged,now(),p_idempotency_key)
  returning id into delivery_id;
  update public.shipments set status = case when p_quantity_damaged > 0 then 'incident'::public.shipment_status else 'delivered'::public.shipment_status end where id = target.id;
  return delivery_id;
end;
$$;

create or replace function public.validate_delivery(p_delivery_id uuid, p_note text default 'Validación sandbox')
returns uuid language plpgsql security definer set search_path = '' as $$
declare target public.deliveries;
declare shipment public.shipments;
declare shipped_item public.shipment_items;
declare allocation public.allocations;
declare need_item public.need_items;
declare donation public.donations;
declare intake public.donation_intakes;
begin
  select * into target from public.deliveries where id = p_delivery_id for update;
  if not found or target.status not in ('delivered','incident') then raise exception using errcode = '22023', message = 'Entrega no disponible para validación'; end if;
  select * into shipment from public.shipments where id = target.shipment_id for update;
  if not public.has_event_role(shipment.event_id,array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes validar esta entrega';
  end if;
  select * into shipped_item from public.shipment_items where shipment_id = shipment.id limit 1;
  select * into allocation from public.allocations where id = shipped_item.allocation_id for update;
  select * into need_item from public.need_items where id = allocation.need_item_id for update;
  if need_item.quantity_covered + target.quantity_delivered > need_item.quantity_required then
    raise exception using errcode = '22023', message = 'La entrega excede la necesidad pendiente';
  end if;
  update public.deliveries set status='validated',validated_by=(select auth.uid()),validated_at=now(),recipient_confirmation_private=jsonb_build_object('note',left(p_note,240)) where id=target.id;
  update public.shipments set status='validated' where id=shipment.id;
  update public.allocations set status='delivered' where id=allocation.id;
  update public.need_items set quantity_covered=quantity_covered+target.quantity_delivered where id=need_item.id;
  update public.need_cases set status=case when need_item.quantity_covered+target.quantity_delivered >= need_item.quantity_required then 'covered'::public.need_status else 'partially_covered'::public.need_status end where id=need_item.need_case_id;
  update public.public_need_projections set covered_quantity=covered_quantity+target.quantity_delivered,status=case when covered_quantity+target.quantity_delivered>=needed_quantity then 'Cubierta' else 'Parcialmente cubierta' end,updated_at=now() where source_need_id=need_item.need_case_id;

  select d.* into donation from public.donations d join public.donation_items di on di.donation_id=d.id join public.inventory_lots il on il.donation_item_id=di.id where il.id=allocation.lot_id limit 1;
  select * into intake from public.donation_intakes where id=donation.intake_id;
  update public.donations set status='validated' where id=donation.id;
  insert into public.public_donation_projections(donation_id,event_id,public_code,attribution,kind,category,verified_quantity,unit,destination_label,operational_state,evidence_level,published,published_at)
  values (donation.id,donation.event_id,donation.donor_tracking_code,
    case intake.public_attribution_kind when 'anonymous' then 'Anónimo' when 'organization' then coalesce(intake.public_attribution,'Organización aliada') else coalesce(intake.public_attribution,'Atribución reservada') end,
    donation.kind,need_item.category,target.quantity_delivered,need_item.unit,shipment.public_destination,'validated','operational_events',true,now())
  on conflict(donation_id) do update set verified_quantity=public.public_donation_projections.verified_quantity+excluded.verified_quantity,operational_state='validated',published=true,updated_at=now();
  return donation.id;
end;
$$;

create or replace function public.pay_expense(p_expense_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare expense public.expense_requests;
declare available numeric;
declare tx_id uuid;
begin
  select ep.financial_transaction_id into tx_id from public.expense_payments ep where ep.expense_request_id=p_expense_id;
  if found then return tx_id; end if;
  select * into expense from public.expense_requests where id=p_expense_id for update;
  if not found or expense.status<>'approved' then raise exception using errcode='22023', message='El gasto no está aprobado'; end if;
  if not public.has_any_role(expense.organization_id,expense.event_id,array['treasury_approver','event_admin']::public.app_role[]) then raise exception using errcode='42501', message='No puedes pagar este gasto'; end if;
  if expense.requested_by=(select auth.uid()) then raise exception using errcode='42501', message='El solicitante no puede pagar su propio gasto'; end if;
  select coalesce(sum(case when transaction_type='credit' then amount when transaction_type in ('debit','refund','chargeback') then -amount else 0 end),0) into available
  from public.financial_transactions where fund_id=expense.fund_id and status='reconciled';
  if available<expense.amount then raise exception using errcode='22023', message='Saldo conciliado insuficiente'; end if;
  insert into public.financial_transactions(event_id,organization_id,fund_id,transaction_type,amount,status,provider,provider_reference_private,public_reference,idempotency_key,actor_id,reconciled_at)
  values(expense.event_id,expense.organization_id,expense.fund_id,'debit',expense.amount,'reconciled','sandbox','EXP-'||expense.id::text,'GASTO-'||right(expense.id::text,8),p_idempotency_key,(select auth.uid()),now()) returning id into tx_id;
  insert into public.expense_payments(expense_request_id,financial_transaction_id,paid_by) values(expense.id,tx_id,(select auth.uid()));
  update public.expense_requests set status='paid' where id=expense.id;
  return tx_id;
end;
$$;

create or replace function public.import_legacy_fixture(
  p_event_id uuid,
  p_source_system text,
  p_checksum text,
  p_records jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare batch_id uuid;
declare record jsonb;
declare result_code text;
declare errors jsonb;
declare v_approved_count integer:=0;
declare v_rejected_count integer:=0;
declare v_duplicate_count integer:=0;
declare v_quarantine_count integer:=0;
begin
  if not public.has_event_role(p_event_id,array['event_admin']::public.app_role[]) then raise exception using errcode='42501',message='Solo administración puede ensayar migraciones'; end if;
  if jsonb_typeof(p_records)<>'array' then raise exception using errcode='22023',message='El lote debe ser un arreglo JSON'; end if;
  insert into public.migration_batches(event_id,source_system,source_cut_at,checksum_sha256,status,input_count,created_by)
  values(p_event_id,p_source_system,now(),p_checksum,'quarantined',jsonb_array_length(p_records),(select auth.uid())) returning id into batch_id;
  for record in select value from jsonb_array_elements(p_records) loop
    errors:='[]'::jsonb;
    result_code:='approved';
    if coalesce(record->>'external_id','')='' then errors:=errors||'"missing_external_id"'::jsonb; result_code:='rejected';
    elsif public.contains_sensitive_content(coalesce(record->>'text','')) or coalesce((record->>'contains_pii')::boolean,false) then errors:=errors||'"pii_or_financial_content"'::jsonb; result_code:='quarantined';
    elsif coalesce((record->>'is_duplicate')::boolean,false) then errors:=errors||'"possible_duplicate"'::jsonb; result_code:='duplicate';
    elsif coalesce((record->>'is_expired')::boolean,false) or coalesce(record->>'location','')='' then errors:=errors||'"expired_or_unlocated"'::jsonb; result_code:='quarantined';
    elsif coalesce((record->>'is_disproved')::boolean,false) then errors:=errors||'"disproved"'::jsonb; result_code:='rejected';
    end if;
    insert into public.migration_record_results(batch_id,external_row_id,result,quality_errors,duplicate_of_external_id)
    values(batch_id,coalesce(record->>'external_id','missing-'||gen_random_uuid()::text),result_code,errors,record->>'duplicate_of');
    v_approved_count:=v_approved_count+(result_code='approved')::integer;
    v_rejected_count:=v_rejected_count+(result_code='rejected')::integer;
    v_duplicate_count:=v_duplicate_count+(result_code='duplicate')::integer;
    v_quarantine_count:=v_quarantine_count+(result_code='quarantined')::integer;
  end loop;
  update public.migration_batches set approved_count=v_approved_count,rejected_count=v_rejected_count,duplicate_count=v_duplicate_count,quarantine_count=v_quarantine_count where id=batch_id;
  return batch_id;
end;
$$;

create or replace function public.rollback_migration_batch(p_batch_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare batch public.migration_batches;
begin
  select * into batch from public.migration_batches where id=p_batch_id for update;
  if not found then raise exception using errcode='P0002',message='Lote no encontrado'; end if;
  if not public.has_event_role(batch.event_id,array['event_admin']::public.app_role[]) then raise exception using errcode='42501',message='Solo administración puede revertir'; end if;
  update public.migration_batches set status='rolled_back' where id=batch.id;
  return 'rolled_back';
end;
$$;

create policy "members read shipments items" on public.shipment_items for select to authenticated using(exists(select 1 from public.shipments s where s.id=shipment_id and public.is_org_member(s.organization_id,s.event_id)));
create policy "members read deliveries" on public.deliveries for select to authenticated using(exists(select 1 from public.shipments s where s.id=shipment_id and public.is_org_member(s.organization_id,s.event_id)));
create policy "members read holds" on public.lot_hold_or_recalls for select to authenticated using(exists(select 1 from public.inventory_lots l where l.id=lot_id and public.is_org_member(l.organization_id,l.event_id)));
create policy "members read need item allocations" on public.allocations for select to authenticated using(public.is_org_member(organization_id,event_id));

grant execute on function public.place_lot_control(uuid,text,text) to authenticated;
grant execute on function public.create_shipment(uuid,text,text,text) to authenticated;
grant execute on function public.register_delivery(uuid,numeric,numeric,text) to authenticated;
grant execute on function public.validate_delivery(uuid,text) to authenticated;
grant execute on function public.pay_expense(uuid,text) to authenticated;
grant execute on function public.import_legacy_fixture(uuid,text,text,jsonb) to authenticated;
grant execute on function public.rollback_migration_batch(uuid) to authenticated;
