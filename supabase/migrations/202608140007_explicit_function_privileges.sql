-- PostgreSQL concede EXECUTE a PUBLIC por defecto. Las funciones SECURITY DEFINER
-- deben partir de denegación total y abrir únicamente los recorridos documentados.

do $$
declare
  target_function regprocedure;
begin
  for target_function in
    select function_proc.oid::regprocedure
    from pg_catalog.pg_proc as function_proc
    join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_proc.pronamespace
    where function_schema.nspname = 'public'
      and function_proc.prosecdef
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      target_function
    );
  end loop;
end;
$$;

alter default privileges in schema public revoke execute on functions from public;

-- Recorridos anónimos explícitos y acotados.
grant execute on function public.submit_need_report(uuid,text,text,text,numeric,text,text,jsonb)
  to anon, authenticated;
grant execute on function public.submit_donation_intake(
  uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb
) to anon, authenticated;
grant execute on function public.track_public_code(text) to anon, authenticated;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

-- Helpers de autorización usados por RLS y mutaciones operativas autenticadas.
grant execute on function public.has_any_role(uuid,uuid,public.app_role[]) to authenticated;
grant execute on function public.has_event_role(uuid,public.app_role[]) to authenticated;
grant execute on function public.is_event_member(uuid) to authenticated;
grant execute on function public.is_org_member(uuid,uuid) to authenticated;

grant execute on function public.allocate_stock(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.approve_expense(uuid,text,text) to authenticated;
grant execute on function public.create_shipment(uuid,text,text,text) to authenticated;
grant execute on function public.import_legacy_fixture(uuid,text,text,jsonb) to authenticated;
grant execute on function public.pay_expense(uuid,text) to authenticated;
grant execute on function public.place_lot_control(uuid,text,text) to authenticated;
grant execute on function public.receive_donation(uuid,uuid,numeric,numeric,text,text) to authenticated;
grant execute on function public.reconcile_sandbox_payment(uuid,numeric,text,text) to authenticated;
grant execute on function public.register_delivery(uuid,numeric,numeric,text) to authenticated;
grant execute on function public.request_expense(uuid,numeric,text) to authenticated;
grant execute on function public.review_donation_intake(uuid,text,text) to authenticated;
grant execute on function public.review_need_case(uuid,text,text,integer,timestamptz) to authenticated;
grant execute on function public.rollback_migration_batch(uuid) to authenticated;
grant execute on function public.validate_delivery(uuid,text) to authenticated;

