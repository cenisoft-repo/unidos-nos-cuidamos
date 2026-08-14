-- El registro de aportes conserva datos privados y exige membresía aliada.
-- El reporte ciudadano y el seguimiento por código continúan siendo anónimos.
revoke execute on function public.submit_donation_intake(
  uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb
) from anon;

