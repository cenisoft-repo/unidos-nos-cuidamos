create or replace function public.has_event_role(target_event uuid, allowed_roles public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.event_id = target_event
      and m.active and m.role = any(allowed_roles)
  );
$$;

create or replace function public.review_need_case(
  p_need_id uuid,
  p_decision text,
  p_note text,
  p_confidence integer default null,
  p_expires_at timestamptz default null
)
returns public.need_status language plpgsql security definer set search_path = '' as $$
declare target public.need_cases;
declare next_status public.need_status;
declare item public.need_items;
begin
  select * into target from public.need_cases where id = p_need_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Necesidad no encontrada'; end if;
  if not public.has_event_role(target.event_id, array['verifier','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes verificar esta necesidad';
  end if;
  if p_decision not in ('verify','observe','reject','duplicate','disprove','renew','expire','publish','suspend') then
    raise exception using errcode = '22023', message = 'Decisión inválida';
  end if;

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
    visibility = case when p_decision = 'publish' then 'public'::public.visibility_level when p_decision in ('suspend','expire') then 'private'::public.visibility_level else visibility end
  where id = target.id;

  if p_decision = 'publish' then
    select * into item from public.need_items where need_case_id = target.id order by created_at limit 1;
    insert into public.public_need_projections(
      source_need_id,event_id,category,summary,location_label,status,confidence_label,
      verified_at,expires_at,needed_quantity,covered_quantity,unit,published
    ) values (
      target.id,target.event_id,target.category,left(target.description,180),target.public_location_text,
      'Publicada','Verificada por organización',now(),target.expires_at,
      item.quantity_required,item.quantity_covered,item.unit,true
    ) on conflict (source_need_id) do update set
      summary = excluded.summary, status = excluded.status, confidence_label = excluded.confidence_label,
      verified_at = excluded.verified_at, expires_at = excluded.expires_at,
      needed_quantity = excluded.needed_quantity, covered_quantity = excluded.covered_quantity,
      unit = excluded.unit, published = true, updated_at = now();
  elsif p_decision in ('suspend','expire','reject','disprove') then
    update public.public_need_projections set published = false, updated_at = now() where source_need_id = target.id;
  end if;
  return next_status;
end;
$$;

create or replace function public.review_donation_intake(p_intake_id uuid, p_decision text, p_note text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare intake public.donation_intakes;
declare donation_id uuid;
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
    insert into public.donation_items(donation_id, source_intake_item_id, category, description, quantity_promised, unit)
    select donation_id, i.id, i.category, i.description, i.quantity, i.unit
    from public.donation_intake_items i where i.intake_id = intake.id
      and not exists (select 1 from public.donation_items d where d.source_intake_item_id = i.id);
  end if;
  return donation_id;
end;
$$;

create policy "event verifiers read all intakes" on public.donation_intakes for select to authenticated using (
  public.has_event_role(event_id, array['verifier','event_admin','auditor']::public.app_role[])
);
create policy "event verifiers read all intake items" on public.donation_intake_items for select to authenticated using (
  exists (select 1 from public.donation_intakes i where i.id = intake_id and public.has_event_role(i.event_id, array['verifier','event_admin','auditor']::public.app_role[]))
);
create policy "event verifiers read all intake decisions" on public.intake_verification_decisions for select to authenticated using (
  exists (select 1 from public.donation_intakes i where i.id = intake_id and public.has_event_role(i.event_id, array['verifier','event_admin','auditor']::public.app_role[]))
);

grant execute on function public.has_event_role(uuid, public.app_role[]) to authenticated;
grant execute on function public.review_need_case(uuid,text,text,integer,timestamptz) to authenticated;
