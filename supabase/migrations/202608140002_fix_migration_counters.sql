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
