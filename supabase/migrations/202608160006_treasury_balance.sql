-- Saldo conciliado calculado sobre el libro completo.
--
-- Hasta ahora el saldo se sumaba en el cliente sobre la lista ya cargada: en el centro
-- operativo eran las últimas ocho transacciones y en tesorería el tope que devolviera la
-- API. El número se mostraba como «Saldo conciliado» sin decir que era parcial, así que a
-- partir del noveno movimiento la cifra era simplemente falsa.
--
-- El cálculo baja a la base, sobre todo el libro del evento y solo de las organizaciones
-- donde la persona tiene membresía activa.

create or replace function public.treasury_balance(p_event_id uuid)
returns table(
  reconciled_credits numeric,
  reconciled_debits numeric,
  balance numeric,
  movement_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_event_role(
       p_event_id,
       array['treasury_requester','treasury_approver','event_admin','auditor']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No puedes consultar el saldo de este evento';
  end if;

  return query
  select
    coalesce(sum(movement.amount) filter (where movement.transaction_type = 'credit'), 0)::numeric,
    coalesce(sum(movement.amount) filter (where movement.transaction_type <> 'credit'), 0)::numeric,
    coalesce(sum(
      case when movement.transaction_type = 'credit' then movement.amount else -movement.amount end
    ), 0)::numeric,
    count(*)::integer
  from public.financial_transactions as movement
  where movement.event_id = p_event_id
    and movement.status = 'reconciled'
    -- El saldo solo suma las organizaciones donde la persona es miembro activo.
    and public.is_org_member(movement.organization_id, p_event_id);
end;
$$;

revoke all on function public.treasury_balance(uuid) from public, anon, authenticated;
grant execute on function public.treasury_balance(uuid) to authenticated;
