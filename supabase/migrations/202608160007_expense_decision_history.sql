-- Historial legible de decisiones sobre gastos.
--
-- `expense_approvals` guarda quién aprobó o rechazó y por qué, pero la tabla quedó con RLS
-- activo y sin ninguna política: ningún rol podía leerla. La justificación era, en la
-- práctica, de solo escritura, y un control que nadie puede consultar no es trazabilidad.
--
-- Se expone por función, como el resto del sistema, en vez de abrir la tabla: así el
-- alcance queda acotado al evento y a las organizaciones donde la persona es miembro.

create or replace function public.expense_decisions(p_event_id uuid)
returns table(
  expense_request_id uuid,
  decision text,
  note text,
  decided_at timestamptz
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
    raise exception using errcode = '42501', message = 'No puedes consultar las decisiones de gasto de este evento';
  end if;

  return query
  select approval.expense_request_id, approval.decision, approval.note, approval.created_at
  from public.expense_approvals as approval
  join public.expense_requests as request on request.id = approval.expense_request_id
  where request.event_id = p_event_id
    and public.is_org_member(request.organization_id, p_event_id)
  order by approval.created_at desc;
end;
$$;

revoke all on function public.expense_decisions(uuid) from public, anon, authenticated;
grant execute on function public.expense_decisions(uuid) to authenticated;
