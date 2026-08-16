-- Defensa local para la entrada ciudadana. El identificador de red se resume
-- dentro de PostgreSQL y nunca se conserva en claro.
create table public.anonymous_rate_limits (
  action text not null,
  bucket_hash text not null check (bucket_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null default 1 check (request_count between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (action, bucket_hash, window_started_at)
);

create index anonymous_rate_limits_window_idx
on public.anonymous_rate_limits (window_started_at);

alter table public.anonymous_rate_limits enable row level security;
revoke all on table public.anonymous_rate_limits from public, anon, authenticated;

comment on table public.anonymous_rate_limits is
  'Contadores operativos sin IP en claro; no forman parte del historial crítico.';

create or replace function public.submit_need_report(
  p_event_id uuid,
  p_category text,
  p_description text,
  p_public_location text,
  p_quantity numeric,
  p_unit text,
  p_exact_address_private text,
  p_contact_private jsonb,
  p_bot_field text
)
returns table(need_id uuid, tracking_code text, status public.need_status)
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_headers jsonb := '{}'::jsonb;
  source_hint text;
  rate_bucket text;
  rate_window timestamptz;
  accepted_count integer;
begin
  if nullif(btrim(coalesce(p_bot_field, '')), '') is not null then
    raise exception using errcode = '22023', message = 'No fue posible procesar el reporte';
  end if;

  begin
    request_headers := coalesce(
      nullif(current_setting('request.headers', true), ''),
      '{}'
    )::jsonb;
  exception when others then
    request_headers := '{}'::jsonb;
  end;

  source_hint := left(
    lower(btrim(coalesce(
      nullif(request_headers ->> 'cf-connecting-ip', ''),
      nullif(split_part(request_headers ->> 'x-forwarded-for', ',', 1), ''),
      nullif(request_headers ->> 'x-real-ip', ''),
      'direct-client'
    ))),
    128
  );
  rate_bucket := encode(
    extensions.digest(source_hint || '|' || p_event_id::text, 'sha256'),
    'hex'
  );
  rate_window := date_bin(
    interval '10 minutes',
    clock_timestamp(),
    timestamptz '2000-01-01 00:00:00+00'
  );

  insert into public.anonymous_rate_limits as limits (
    action,
    bucket_hash,
    window_started_at,
    request_count
  ) values (
    'submit_need_report',
    rate_bucket,
    rate_window,
    1
  )
  on conflict (action, bucket_hash, window_started_at)
  do update set
    request_count = limits.request_count + 1,
    updated_at = now()
  where limits.request_count < 5
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using
      errcode = 'P0001',
      message = 'Se alcanzó el límite temporal de reportes. Intenta de nuevo en unos minutos';
  end if;

  return query
  select *
  from public.submit_need_report(
    p_event_id,
    p_category,
    p_description,
    p_public_location,
    p_quantity,
    p_unit,
    p_exact_address_private,
    p_contact_private
  );
end;
$$;

revoke all on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb
) from public, anon, authenticated;
revoke all on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.submit_need_report(
  uuid, text, text, text, numeric, text, text, jsonb, text
) to anon, authenticated;
