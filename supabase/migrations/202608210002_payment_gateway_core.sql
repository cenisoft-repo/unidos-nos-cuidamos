-- Pasarela de pagos para aportes en dinero: el núcleo, agnóstico del proveedor.
--
-- Hasta hoy un aporte económico era una declaración: alguien decía «entregué 500 000» y
-- tesorería lo conciliaba a mano contra un extracto. Eso sigue existiendo y no se toca.
-- Lo que falta para operar de verdad es que el dinero pueda entrar por la plataforma.
--
-- Cuatro decisiones que gobiernan todo lo que sigue:
--
--   1. **La plataforma no ve datos de pago.** Aquí no hay tarjeta, ni cuenta, ni CVV, ni
--      token de tarjeta. Lo único que se guarda es cuánto se pidió cobrar, por qué canal y
--      qué referencia devolvió el proveedor. El cobro ocurre en el proveedor.
--   2. **Confirmar no es conciliar.** Que el proveedor diga «pagado» NO escribe nada en el
--      libro de movimientos: deja la intención en `confirmed`. El asiento lo escribe una
--      persona de tesorería al casarlo con el extracto, y ese asiento nace ya conciliado.
--      No es una preferencia de diseño: `financial_transactions` tiene un disparador que
--      prohíbe UPDATE y DELETE, así que un movimiento que cambia de estado no existe. El
--      libro guarda hechos liquidados; lo que está en vuelo vive en la intención de cobro.
--   3. **La base no guarda secretos.** `payment_providers` guarda el SHA-256 del secreto de
--      webhook, nunca el secreto. El secreto vive donde se despliega y se envía en cada
--      llamada; PostgreSQL solo compara huellas.
--   4. **La aplicación no estrena una clave de administración.** El webhook se autentica
--      con ese secreto compartido, verificado dentro de la transacción, en vez de meter una
--      clave `service_role` en el servidor web. Hoy `src/` no contiene ninguna y este
--      cambio no es motivo suficiente para que contenga la primera.

-- ============================================================ 1. proveedores

create table public.payment_providers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  fund_id uuid not null references public.funds(id),
  provider_key text not null check (provider_key ~ '^[a-z][a-z0-9_]{2,31}$'),
  display_name text not null check (char_length(btrim(display_name)) between 3 and 80),
  -- Un proveedor de práctica no mueve dinero. Activar uno que sí lo mueve exige autoridad
  -- global y un motivo escrito: es la puerta entre el ejercicio y el recaudo real.
  sandbox boolean not null default true,
  active boolean not null default false,
  public_config jsonb not null default '{}'::jsonb,
  webhook_secret_sha256 text not null check (webhook_secret_sha256 ~ '^[0-9a-f]{64}$'),
  activated_by uuid references auth.users(id),
  activated_at timestamptz,
  activation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, organization_id, provider_key)
);

create index payment_providers_organization_idx on public.payment_providers (organization_id, event_id);
create index payment_providers_fund_idx on public.payment_providers (fund_id);
create index payment_providers_activated_by_idx on public.payment_providers (activated_by);

create trigger payment_providers_updated_at
  before update on public.payment_providers
  for each row execute function public.set_updated_at();
create trigger payment_providers_audit
  after insert or update or delete on public.payment_providers
  for each row execute function public.audit_row_change();

alter table public.payment_providers enable row level security;
revoke all on table public.payment_providers from public, anon, authenticated;
-- La concesión es por columnas y no por tabla a propósito: revocar una columna después de
-- conceder la tabla entera no quita nada en PostgreSQL, así que la huella del secreto
-- simplemente no se concede nunca.
grant select (
  id, event_id, organization_id, fund_id, provider_key, display_name,
  sandbox, active, public_config, activated_by, activated_at, activation_reason,
  created_at, updated_at
) on table public.payment_providers to authenticated;

-- Sin política de escritura: la única forma de registrar o activar un proveedor es la RPC
-- auditada.
create policy "org members read payment providers"
  on public.payment_providers for select to authenticated
  using (public.is_org_member(organization_id, event_id));

comment on table public.payment_providers is
  'Canales de recaudo parametrizados por organización y evento. No guarda claves de API ni secretos: solo la huella del secreto de webhook.';
comment on column public.payment_providers.public_config is
  'Configuración publicable del canal (etiquetas, moneda, límites). Nunca claves, tokens ni secretos: la RPC que la escribe rechaza esas llaves.';
comment on column public.payment_providers.webhook_secret_sha256 is
  'SHA-256 del secreto compartido con el proveedor. El secreto vive en el entorno de despliegue y nunca se escribe aquí.';

-- ============================================================ 2. intención de pago

create type public.payment_intent_status as enum ('pending', 'confirmed', 'failed', 'expired', 'cancelled');

create table public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  provider_id uuid not null references public.payment_providers(id),
  intake_id uuid not null references public.donation_intakes(id),
  reference text not null unique default public.generate_tracking_code('PAG'),
  amount numeric(16,2) not null check (amount > 0),
  currency char(3) not null default 'COP',
  status public.payment_intent_status not null default 'pending',
  provider_reference_private text,
  failure_reason text,
  idempotency_key text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unique (intake_id, idempotency_key),
  unique (provider_id, provider_reference_private)
);

create index payment_intents_event_idx on public.payment_intents (event_id, status, created_at);
create index payment_intents_organization_idx on public.payment_intents (organization_id, event_id);
create index payment_intents_created_by_idx on public.payment_intents (created_by);

create trigger payment_intents_updated_at
  before update on public.payment_intents
  for each row execute function public.set_updated_at();
create trigger payment_intents_audit
  after insert or update or delete on public.payment_intents
  for each row execute function public.audit_row_change();

alter table public.payment_intents enable row level security;
revoke all on table public.payment_intents from public, anon, authenticated;
grant select on table public.payment_intents to authenticated;

-- El dinero entra al fondo de la organización que recauda, pero el aporte lo registró otra:
-- las dos partes tienen que poder seguir el cobro, y ninguna más.
create policy "both sides read payment intents"
  on public.payment_intents for select to authenticated
  using (
    public.is_org_member(organization_id, event_id)
    or exists (
      select 1 from public.donation_intakes as intake
      where intake.id = intake_id
        and public.is_org_member(intake.organization_id, intake.event_id)
    )
  );

comment on table public.payment_intents is
  'Intención de cobro de un aporte económico: cuánto, por qué canal y con qué resultado. No contiene ningún dato de medio de pago.';
comment on column public.payment_intents.provider_reference_private is
  'Identificador que devuelve el proveedor. Es privado porque permite consultar la transacción en su panel, no porque contenga datos de pago.';

-- ============================================================ 3. parametrizar el canal

create or replace function public.set_payment_provider(
  p_provider_id uuid,
  p_event_id uuid,
  p_organization_id uuid,
  p_fund_id uuid,
  p_provider_key text,
  p_display_name text,
  p_sandbox boolean,
  p_active boolean,
  p_public_config jsonb,
  p_webhook_secret text,
  p_reason text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  fund public.funds;
  existing public.payment_providers;
  actor uuid := (select auth.uid());
  digest_hex text;
  offending text;
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Autenticación requerida';
  end if;
  if not public.has_any_role(p_organization_id, p_event_id, array['event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'Solo la administración del evento parametriza el canal de recaudo';
  end if;
  -- Abrir un canal que mueve dinero real no es parametrizar: es cambiar la naturaleza de
  -- la plataforma. Exige autoridad global y queda escrito quién y por qué.
  if p_sandbox is not true and not public.is_super_admin() then
    raise exception using errcode = '42501',
      message = 'Activar un canal de recaudo real exige autoridad global y queda registrado';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception using errcode = '22023', message = 'Escribe por qué se registra o cambia este canal';
  end if;

  select * into fund from public.funds where id = p_fund_id;
  if not found or not fund.verified or fund.event_id <> p_event_id or fund.organization_id <> p_organization_id then
    raise exception using errcode = '22023', message = 'El fondo no corresponde a esta organización y evento, o no está verificado';
  end if;

  -- Ninguna llave que huela a secreto entra en la configuración publicable. La huella del
  -- secreto se calcula aquí y el secreto se descarta con la transacción.
  select key into offending
  from jsonb_object_keys(coalesce(p_public_config, '{}'::jsonb)) as key
  where key ~* '(secret|secreto|private|privad|token|password|contrase|api_?key|clave)'
  limit 1;
  if offending is not null then
    raise exception using errcode = '22023',
      message = format('La configuración publicable no puede contener «%s»: los secretos viven fuera de la base', offending);
  end if;

  if char_length(coalesce(p_webhook_secret, '')) < 24 then
    raise exception using errcode = '22023', message = 'El secreto de webhook debe tener al menos 24 caracteres';
  end if;
  digest_hex := encode(extensions.digest(p_webhook_secret::bytea, 'sha256'), 'hex');

  if p_provider_id is not null then
    select * into existing from public.payment_providers where id = p_provider_id for update;
    if not found or existing.event_id <> p_event_id or existing.organization_id <> p_organization_id then
      raise exception using errcode = 'P0002', message = 'Canal de recaudo no encontrado';
    end if;
    update public.payment_providers
    set fund_id = fund.id,
        display_name = btrim(p_display_name),
        sandbox = coalesce(p_sandbox, true),
        active = coalesce(p_active, false),
        public_config = coalesce(p_public_config, '{}'::jsonb),
        webhook_secret_sha256 = digest_hex,
        activated_by = case when coalesce(p_active, false) then actor else existing.activated_by end,
        activated_at = case when coalesce(p_active, false) then now() else existing.activated_at end,
        activation_reason = btrim(p_reason)
    where id = existing.id;
    return existing.id;
  end if;

  insert into public.payment_providers(
    event_id, organization_id, fund_id, provider_key, display_name,
    sandbox, active, public_config, webhook_secret_sha256,
    activated_by, activated_at, activation_reason
  ) values (
    p_event_id, p_organization_id, fund.id, btrim(p_provider_key), btrim(p_display_name),
    coalesce(p_sandbox, true), coalesce(p_active, false), coalesce(p_public_config, '{}'::jsonb), digest_hex,
    case when coalesce(p_active, false) then actor end,
    case when coalesce(p_active, false) then now() end,
    btrim(p_reason)
  )
  returning id into existing.id;

  return existing.id;
end;
$$;

revoke all on function public.set_payment_provider(uuid, uuid, uuid, uuid, text, text, boolean, boolean, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function public.set_payment_provider(uuid, uuid, uuid, uuid, text, text, boolean, boolean, jsonb, text, text)
  to authenticated;
comment on function public.set_payment_provider(uuid, uuid, uuid, uuid, text, text, boolean, boolean, jsonb, text, text) is
  'Registra o cambia un canal de recaudo. Guarda solo la huella del secreto; activar un canal no sandbox exige autoridad global.';

-- Canales que puede usar un aporte concreto. No devuelve la huella del secreto.
create or replace function public.payment_options_for_intake(p_intake_id uuid)
returns table(
  provider_id uuid,
  provider_key text,
  display_name text,
  sandbox boolean,
  currency char(3),
  amount numeric,
  already_paid boolean
)
language sql stable security definer set search_path = '' as $$
  select
    provider.id,
    provider.provider_key,
    provider.display_name,
    provider.sandbox,
    intake.currency,
    intake.declared_amount,
    exists (
      select 1 from public.payment_intents as paid
      where paid.intake_id = intake.id and paid.status = 'confirmed'
    )
  from public.donation_intakes as intake
  join public.payment_providers as provider
    on provider.event_id = intake.event_id
   and provider.active
  where intake.id = p_intake_id
    and intake.kind = 'money'
    and coalesce(intake.declared_amount, 0) > 0
    and public.is_org_member(intake.organization_id, intake.event_id)
  order by provider.display_name;
$$;

revoke all on function public.payment_options_for_intake(uuid) from public, anon, authenticated;
grant execute on function public.payment_options_for_intake(uuid) to authenticated;
comment on function public.payment_options_for_intake(uuid) is
  'Canales de recaudo activos para un aporte económico propio, con su importe y si ya está pagado.';

-- ============================================================ 4. abrir la intención

create or replace function public.start_payment_intent(
  p_intake_id uuid,
  p_provider_id uuid,
  p_idempotency_key text
)
returns table(
  intent_id uuid,
  reference text,
  amount numeric,
  currency char(3),
  provider_key text,
  sandbox boolean,
  was_duplicate boolean
)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  intake public.donation_intakes;
  provider public.payment_providers;
  existing public.payment_intents;
  created public.payment_intents;
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Autenticación requerida';
  end if;
  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;

  select * into intake from public.donation_intakes where id = p_intake_id for update;
  if not found or intake.kind <> 'money' then
    raise exception using errcode = 'P0002', message = 'Aporte económico no encontrado';
  end if;
  if not public.is_org_member(intake.organization_id, intake.event_id) then
    raise exception using errcode = '42501', message = 'No puedes pagar un aporte de otra organización';
  end if;
  if coalesce(intake.declared_amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'El aporte no declara un valor a pagar';
  end if;

  select * into provider from public.payment_providers where id = p_provider_id;
  if not found or not provider.active or provider.event_id <> intake.event_id then
    raise exception using errcode = '22023', message = 'Ese canal de recaudo no está disponible para este aporte';
  end if;

  select * into existing
  from public.payment_intents as candidate
  where candidate.intake_id = intake.id
    and candidate.idempotency_key = p_idempotency_key;
  if existing.id is not null then
    return query select existing.id, existing.reference, existing.amount, existing.currency,
      provider.provider_key, provider.sandbox, true;
    return;
  end if;

  -- Un aporte se paga una vez. Reintentar mientras está pendiente es normal; volver a
  -- cobrar algo ya confirmado no lo es.
  if exists (
    select 1 from public.payment_intents as paid
    where paid.intake_id = intake.id and paid.status = 'confirmed'
  ) then
    raise exception using errcode = '22023', message = 'Este aporte ya tiene un pago confirmado';
  end if;

  insert into public.payment_intents(
    event_id, organization_id, provider_id, intake_id, amount, currency, idempotency_key, created_by
  ) values (
    intake.event_id, provider.organization_id, provider.id, intake.id,
    intake.declared_amount, intake.currency, btrim(p_idempotency_key), actor
  )
  returning * into created;

  return query select created.id, created.reference, created.amount, created.currency,
    provider.provider_key, provider.sandbox, false;
end;
$$;

revoke all on function public.start_payment_intent(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.start_payment_intent(uuid, uuid, text) to authenticated;
comment on function public.start_payment_intent(uuid, uuid, text) is
  'Abre la intención de cobro de un aporte económico propio. No cobra: solo declara cuánto se va a cobrar y por qué canal.';

-- ============================================================ 5. la vuelta del proveedor

-- La escribe el proveedor, no una persona, así que se autentica con el secreto compartido
-- que se pactó al registrar el canal. La comprobación ocurre aquí dentro, contra la huella
-- guardada: la base nunca conoce el secreto y la aplicación no necesita una clave de
-- administración para llamar a esta función.
--
-- Un mensaje con un importe distinto al que se pidió cobrar NO crea ningún ingreso: deja la
-- intención en `failed` con su razón, para que la discrepancia quede vista y no se resuelva
-- sola en el siguiente reintento del proveedor.
create or replace function public.confirm_payment_intent(
  p_reference text,
  p_provider_key text,
  p_webhook_secret text,
  p_outcome text,
  p_provider_reference text,
  p_amount numeric,
  p_note text
)
returns table(intent_status text, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  intent public.payment_intents;
  provider public.payment_providers;
begin
  if p_outcome not in ('confirmed', 'failed') then
    raise exception using errcode = '22023', message = 'Resultado de pago inválido';
  end if;

  select * into intent from public.payment_intents where reference = btrim(coalesce(p_reference, '')) for update;
  if not found then
    -- Sin oráculo: una referencia inexistente y un secreto equivocado responden igual.
    raise exception using errcode = '42501', message = 'Pago no reconocido';
  end if;
  select * into provider from public.payment_providers where id = intent.provider_id;
  if provider.provider_key <> btrim(coalesce(p_provider_key, ''))
     or provider.webhook_secret_sha256 is distinct from encode(extensions.digest(coalesce(p_webhook_secret, '')::bytea, 'sha256'), 'hex') then
    raise exception using errcode = '42501', message = 'Pago no reconocido';
  end if;

  if intent.status = 'confirmed' then
    if intent.provider_reference_private is distinct from btrim(coalesce(p_provider_reference, '')) then
      raise exception using errcode = '22023', message = 'Ese pago ya fue confirmado con otra referencia del proveedor';
    end if;
    return query select intent.status::text, true;
    return;
  end if;

  if p_outcome = 'failed' then
    update public.payment_intents
    set status = 'failed', failure_reason = left(coalesce(btrim(p_note), 'Rechazado por el proveedor'), 240)
    where id = intent.id;
    return query select 'failed'::text, false;
    return;
  end if;

  if char_length(btrim(coalesce(p_provider_reference, ''))) not between 4 and 160 then
    raise exception using errcode = '22023', message = 'Referencia del proveedor inválida';
  end if;
  if p_amount is distinct from intent.amount then
    update public.payment_intents
    set status = 'failed',
        failure_reason = format('El proveedor informó %s y se pidió cobrar %s',
          public.format_quantity(coalesce(p_amount, 0)), public.format_quantity(intent.amount))
    where id = intent.id;
    return query select 'failed'::text, false;
    return;
  end if;

  update public.payment_intents
  set status = 'confirmed',
      provider_reference_private = btrim(p_provider_reference),
      confirmed_at = now(),
      failure_reason = null
  where id = intent.id;

  return query select 'confirmed'::text, false;
end;
$$;

revoke all on function public.confirm_payment_intent(text, text, text, text, text, numeric, text)
  from public, anon, authenticated;
-- El proveedor no tiene sesión. Lo que lo autentica es el secreto, comprobado arriba contra
-- la huella del canal antes de tocar nada.
grant execute on function public.confirm_payment_intent(text, text, text, text, text, numeric, text) to anon;
comment on function public.confirm_payment_intent(text, text, text, text, text, numeric, text) is
  'Resultado del proveedor sobre una intención de cobro. Se autentica con el secreto del canal y no escribe en el libro: el asiento lo hace tesorería al conciliar.';

-- ============================================================ 6. publicar lo conciliado

-- Publicar un aporte económico conciliado tiene reglas: el estado de la donación, la
-- atribución pública, el destino solo si fue declarado, la proyección con su importe y la
-- constancia con su huella. Estaban escritas dentro de `reconcile_money_donation` y ahora
-- hay un segundo camino que llega al mismo sitio —el cobro por pasarela—, así que se
-- extraen. Dos copias de estas reglas serían dos cifras públicas distintas para el mismo
-- dinero, que es exactamente el defecto que este proyecto ya se ha encontrado antes.
create or replace function public.publish_reconciled_money_donation(
  p_donation_id uuid,
  p_transaction_id uuid,
  p_provider_reference text,
  p_actor uuid
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  donation public.donations;
  intake public.donation_intakes;
  movement public.financial_transactions;
  destination_label text;
begin
  select * into donation from public.donations where id = p_donation_id;
  select * into intake from public.donation_intakes where id = donation.intake_id;
  select * into movement from public.financial_transactions where id = p_transaction_id;

  update public.donations
  set status = 'validated', updated_at = now()
  where id = donation.id;

  destination_label := case
    when intake.specific_destination
      then nullif(concat_ws(', ', intake.destination_municipality, intake.destination_department), '')
    else null
  end;

  insert into public.public_donation_projections(
    donation_id, donation_item_id, event_id, public_code, attribution, kind, category,
    reconciled_amount, currency, destination_label, operational_state, evidence_level,
    published, published_at
  ) values (
    donation.id, null, donation.event_id, donation.donor_tracking_code,
    case intake.public_attribution_kind
      when 'anonymous' then 'Anónimo'
      when 'organization' then coalesce(intake.public_attribution, 'Organización aliada')
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    'money', 'Aporte económico',
    movement.amount, movement.currency, destination_label,
    'reconciled', 'financial_reconciliation', true, now()
  )
  on conflict (donation_id) where donation_item_id is null do update
  set reconciled_amount = excluded.reconciled_amount,
      currency = excluded.currency,
      destination_label = excluded.destination_label,
      operational_state = excluded.operational_state,
      evidence_level = excluded.evidence_level,
      published = true,
      published_at = excluded.published_at,
      updated_at = now();

  insert into public.receipts(donation_id, receipt_type, issued_by, disclaimer, payload_hash)
  values (
    donation.id, 'payment_receipt', p_actor,
    'Constancia sandbox de conciliación: no certifica beneficio, impacto ni deducibilidad tributaria.',
    encode(extensions.digest((movement.id::text || ':' || btrim(p_provider_reference))::bytea, 'sha256'), 'hex')
  );
end;
$$;

revoke all on function public.publish_reconciled_money_donation(uuid, uuid, text, uuid) from public, anon, authenticated;
comment on function public.publish_reconciled_money_donation(uuid, uuid, text, uuid) is
  'Reglas de publicación de un aporte económico conciliado. Único lugar donde se escriben: lo usan la conciliación declarada y la de pasarela.';

-- Misma función de siempre, con su cola delegada al lugar común. El contrato, los estados y
-- los mensajes no cambian: lo único que cambia es que las reglas de publicación dejan de
-- estar escritas dos veces.
create or replace function public.reconcile_money_donation(
  p_donation_id uuid,
  p_fund_id uuid,
  p_provider_reference_private text,
  p_idempotency_key text
)
returns table(transaction_id uuid, source_donation_id uuid, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  donation public.donations;
  intake public.donation_intakes;
  fund public.funds;
  transaction_record public.financial_transactions;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Autenticación requerida';
  end if;
  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;
  if char_length(btrim(coalesce(p_provider_reference_private, ''))) not between 4 and 160 then
    raise exception using errcode = '22023', message = 'Referencia privada inválida';
  end if;

  select * into donation from public.donations where id = p_donation_id for update;
  if not found or donation.kind <> 'money' then
    raise exception using errcode = 'P0002', message = 'Aporte monetario no encontrado';
  end if;
  select * into intake from public.donation_intakes where id = donation.intake_id for update;
  select * into fund from public.funds where id = p_fund_id for update;

  if fund.id is null or not fund.verified or fund.event_id <> donation.event_id then
    raise exception using errcode = '22023', message = 'Fondo inválido para el evento';
  end if;
  if not public.has_any_role(
    fund.organization_id,
    fund.event_id,
    array['treasury_approver', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes conciliar este aporte';
  end if;

  select * into transaction_record
  from public.financial_transactions as existing
  where existing.organization_id = fund.organization_id
    and existing.idempotency_key = p_idempotency_key;
  if transaction_record.id is not null then
    if transaction_record.donation_id is distinct from donation.id
       or transaction_record.fund_id is distinct from fund.id
       or transaction_record.amount is distinct from intake.declared_amount then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;
    return query select transaction_record.id, donation.id, true;
    return;
  end if;

  select * into transaction_record
  from public.financial_transactions as existing
  where existing.donation_id = donation.id;
  if transaction_record.id is not null then
    if transaction_record.fund_id is distinct from fund.id
       or transaction_record.amount is distinct from intake.declared_amount then
      raise exception using errcode = '22023', message = 'El aporte ya fue conciliado con datos diferentes';
    end if;
    return query select transaction_record.id, donation.id, true;
    return;
  end if;

  if intake.status <> 'approved' or donation.status <> 'promised' then
    raise exception using errcode = '22023', message = 'El aporte no está aprobado y pendiente de conciliación';
  end if;
  if intake.declared_amount is null or intake.declared_amount <= 0 then
    raise exception using errcode = '22023', message = 'El aporte no tiene un valor declarado válido';
  end if;

  insert into public.financial_transactions(
    event_id, organization_id, fund_id, donation_id, transaction_type, amount, currency,
    status, provider, provider_reference_private, public_reference, idempotency_key,
    actor_id, reconciled_at
  ) values (
    fund.event_id, fund.organization_id, fund.id, donation.id, 'credit',
    intake.declared_amount, intake.currency, 'reconciled', 'donation_intake',
    btrim(p_provider_reference_private), 'DON-' || donation.donor_tracking_code,
    p_idempotency_key, actor_id, now()
  )
  returning * into transaction_record;

  perform public.publish_reconciled_money_donation(
    donation.id, transaction_record.id, btrim(p_provider_reference_private), actor_id
  );

  return query select transaction_record.id, donation.id, false;
end;
$$;

revoke all on function public.reconcile_money_donation(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.reconcile_money_donation(uuid, uuid, text, text) to authenticated;
comment on function public.reconcile_money_donation(uuid, uuid, text, text) is
  'Concilia un aporte económico declarado fuera de la plataforma contra su soporte; delega la publicación en publish_reconciled_money_donation.';

-- ============================================================ 7. conciliar lo cobrado

-- Lo que el proveedor confirmó todavía no es saldo. Esta es la puerta: una persona de
-- tesorería lo casa con el extracto y solo entonces se escribe el asiento, que nace
-- conciliado porque el libro no admite estados intermedios. La donación no se pasa por
-- parámetro —se deriva del aporte que originó el cobro— para que sea imposible colgar un
-- pago de la donación equivocada.
create or replace function public.reconcile_provider_payment(
  p_payment_reference text,
  p_statement_reference text,
  p_idempotency_key text
)
returns table(transaction_id uuid, source_donation_id uuid, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  intent public.payment_intents;
  provider public.payment_providers;
  intake public.donation_intakes;
  donation public.donations;
  fund public.funds;
  movement public.financial_transactions;
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Autenticación requerida';
  end if;
  if char_length(btrim(coalesce(p_statement_reference, ''))) not between 4 and 160 then
    raise exception using errcode = '22023', message = 'Escribe la referencia del extracto contra la que concilias';
  end if;
  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;

  select * into intent from public.payment_intents
  where reference = btrim(coalesce(p_payment_reference, '')) for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Cobro no encontrado';
  end if;
  select * into provider from public.payment_providers where id = intent.provider_id;
  select * into fund from public.funds where id = provider.fund_id;
  if not public.has_any_role(
    fund.organization_id, fund.event_id,
    array['treasury_approver', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes conciliar este ingreso';
  end if;
  if intent.status <> 'confirmed' then
    raise exception using errcode = '22023', message = 'Ese cobro no está confirmado por el proveedor';
  end if;

  select * into intake from public.donation_intakes where id = intent.intake_id for update;
  select * into donation from public.donations
  where intake_id = intake.id and kind = 'money' for update;
  if not found then
    raise exception using errcode = '22023',
      message = 'El aporte todavía no fue aprobado por verificación: no hay nada que conciliar aún';
  end if;

  -- Idempotencia por las dos vías que importan: la clave de quien concilia y el hecho de
  -- que un aporte solo puede tener un ingreso.
  select * into movement from public.financial_transactions as existing
  where existing.organization_id = fund.organization_id
    and existing.idempotency_key = btrim(p_idempotency_key);
  if movement.id is null then
    select * into movement from public.financial_transactions as existing
    where existing.donation_id = donation.id;
  end if;
  if movement.id is not null then
    if movement.donation_id is distinct from donation.id or movement.amount is distinct from intent.amount then
      raise exception using errcode = '22023', message = 'Ese ingreso ya fue conciliado con datos diferentes';
    end if;
    return query select movement.id, donation.id, true;
    return;
  end if;

  if donation.status <> 'promised' then
    raise exception using errcode = '22023', message = 'El aporte no está pendiente de conciliación';
  end if;
  -- Cobrar algo distinto de lo declarado no se concilia por decreto: se corrige el aporte.
  if intake.declared_amount is distinct from intent.amount then
    raise exception using errcode = '22023',
      message = format('Lo cobrado (%s) no coincide con lo declarado (%s); corrige el aporte antes de conciliar',
        public.format_quantity(intent.amount), public.format_quantity(coalesce(intake.declared_amount, 0)));
  end if;

  insert into public.financial_transactions(
    event_id, organization_id, fund_id, donation_id, transaction_type, amount, currency,
    status, provider, provider_reference_private, public_reference, idempotency_key,
    actor_id, reconciled_at
  ) values (
    fund.event_id, fund.organization_id, fund.id, donation.id, 'credit',
    intent.amount, intent.currency, 'reconciled', provider.provider_key,
    concat_ws(' · ', intent.reference, intent.provider_reference_private, btrim(p_statement_reference)),
    'DON-' || donation.donor_tracking_code, btrim(p_idempotency_key), actor, now()
  )
  returning * into movement;

  perform public.publish_reconciled_money_donation(
    donation.id, movement.id, btrim(p_statement_reference), actor
  );

  return query select movement.id, donation.id, false;
end;
$$;

revoke all on function public.reconcile_provider_payment(text, text, text) from public, anon, authenticated;
grant execute on function public.reconcile_provider_payment(text, text, text) to authenticated;
comment on function public.reconcile_provider_payment(text, text, text) is
  'Tesorería casa un cobro confirmado por el proveedor con el extracto y escribe el asiento, que nace conciliado.';

-- Cola de tesorería: cobros confirmados por el proveedor que todavía no son saldo.
--
-- Es `security definer` porque tiene que cruzar el aporte, y el aporte es de la organización
-- que lo registró, no de la que recauda: tesorería no puede leer esa tabla y sin este cruce
-- la cola saldría vacía. Lo que devuelve es el código público del aporte y su importe;
-- ni donante, ni contacto, ni nada más. La compuerta es explícita.
create or replace function public.treasury_provider_payments(p_event_id uuid)
returns table(
  payment_reference text,
  provider_key text,
  sandbox boolean,
  amount numeric,
  currency char(3),
  confirmed_at timestamptz,
  intake_tracking_code text,
  declared_amount numeric,
  donation_ready boolean
)
language sql stable security definer set search_path = '' as $$
  select
    intent.reference,
    provider.provider_key,
    provider.sandbox,
    intent.amount,
    intent.currency,
    intent.confirmed_at,
    intake.tracking_code,
    intake.declared_amount,
    exists (
      select 1 from public.donations as donation
      where donation.intake_id = intake.id and donation.kind = 'money' and donation.status = 'promised'
    )
  from public.payment_intents as intent
  join public.payment_providers as provider on provider.id = intent.provider_id
  join public.donation_intakes as intake on intake.id = intent.intake_id
  where intent.event_id = p_event_id
    and intent.status = 'confirmed'
    and public.is_org_member(intent.organization_id, intent.event_id)
    and public.has_event_role(
      p_event_id,
      array['treasury_requester','treasury_approver','event_admin','auditor']::public.app_role[]
    )
    and not exists (
      select 1
      from public.donations as donation
      join public.financial_transactions as movement on movement.donation_id = donation.id
      where donation.intake_id = intake.id and donation.kind = 'money'
    )
  order by intent.confirmed_at;
$$;

revoke all on function public.treasury_provider_payments(uuid) from public, anon, authenticated;
grant execute on function public.treasury_provider_payments(uuid) to authenticated;
comment on function public.treasury_provider_payments(uuid) is
  'Cobros confirmados por el proveedor que aún no entran en el saldo. Atraviesa el tenant para leer el código del aporte, con compuerta de rol de tesorería.';
