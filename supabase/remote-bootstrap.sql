-- Esquema completo de Unidos Nos Cuidamos
-- Generado a partir de las 14 migraciones versionadas.
-- Ejecutar UNA vez en el SQL Editor de Supabase.
-- No incluye seed.sql: no crea cuentas de practica.

create schema if not exists extensions;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);

-- ============================================================
-- 202608130001_initial_schema.sql
-- ============================================================
create extension if not exists pgcrypto with schema extensions;
create extension if not exists postgis with schema extensions;

create type public.app_role as enum (
  'event_admin', 'verifier', 'partner_reporter', 'warehouse_operator',
  'logistics_operator', 'treasury_requester', 'treasury_approver', 'auditor'
);
create type public.visibility_level as enum ('private', 'organization', 'event', 'public');
create type public.event_status as enum ('draft', 'active', 'suspended', 'closed', 'archived');
create type public.need_status as enum (
  'reported', 'in_verification', 'verified', 'published', 'partially_covered',
  'covered', 'closed', 'duplicate', 'disproved', 'rejected', 'expired', 'suspended', 'quarantined'
);
create type public.intake_status as enum (
  'draft', 'reported', 'pending_verification', 'observed', 'approved',
  'rejected', 'duplicate', 'cancelled', 'quarantined'
);
create type public.donation_kind as enum ('in_kind', 'money');
create type public.donation_status as enum (
  'promised', 'scheduled', 'received', 'inspected', 'stored', 'allocated',
  'dispatched', 'in_transit', 'delivered', 'validated', 'closed', 'partial',
  'rejected', 'quarantined', 'incident', 'returned', 'lost', 'written_off', 'cancelled'
);
create type public.lot_status as enum ('available', 'reserved', 'quarantined', 'hold', 'recalled', 'depleted', 'disposed');
create type public.stock_movement_type as enum ('receipt', 'transfer_in', 'transfer_out', 'reserve', 'release', 'dispatch', 'adjustment', 'write_off', 'return');
create type public.shipment_status as enum ('draft', 'dispatched', 'in_transit', 'delivered', 'validated', 'incident', 'cancelled');
create type public.financial_transaction_type as enum ('credit', 'debit', 'reversal', 'refund', 'chargeback');
create type public.expense_status as enum ('requested', 'approved', 'rejected', 'paid', 'supported', 'closed', 'cancelled');
create type public.case_status as enum ('open', 'in_review', 'resolved', 'rejected', 'closed');

create or replace function public.generate_tracking_code(prefix text default 'RS')
returns text language sql volatile set search_path = '' as $$
  select upper(prefix || '-' || encode(extensions.gen_random_bytes(12), 'hex'));
$$;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  verified boolean not null default false,
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_at timestamptz not null default now()
);

create table public.organization_verifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  state text not null check (state in ('pending','verified','rejected','expired')),
  method text not null,
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 120),
  locale text not null default 'es-CO',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.emergency_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status public.event_status not null default 'draft',
  simulated boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  public_summary text not null default '',
  timezone text not null default 'America/Bogota',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.emergency_events(id) on delete cascade,
  role public.app_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, organization_id, event_id, role)
);
create index memberships_lookup_idx on public.memberships(user_id, event_id, organization_id) where active;

create table public.official_sources (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_name text not null,
  title text not null,
  url text not null,
  published_at timestamptz,
  checked_at timestamptz not null default now(),
  checksum text,
  created_at timestamptz not null default now()
);

create table public.source_assertions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  source_id uuid not null references public.official_sources(id),
  subject text not null,
  predicate text not null,
  value jsonb not null,
  valid_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.source_conflicts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  assertion_a_id uuid not null references public.source_assertions(id),
  assertion_b_id uuid not null references public.source_assertions(id),
  status public.case_status not null default 'open',
  resolution_note text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (assertion_a_id <> assertion_b_id)
);

create table public.territorial_units (
  id uuid primary key default gen_random_uuid(),
  divipola_code text not null,
  name text not null,
  department_code text,
  level text not null check (level in ('country','department','municipality','district','locality')),
  version text not null,
  centroid extensions.geography(point, 4326),
  valid_from date not null,
  valid_to date,
  unique (divipola_code, version)
);

create table public.public_location_projections (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  territorial_unit_id uuid references public.territorial_units(id),
  label text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  precision_meters integer not null default 5000 check (precision_meters >= 100),
  risk_decision text not null,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.need_cases (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid references public.organizations(id),
  tracking_code text not null unique default public.generate_tracking_code('NEC'),
  category text not null,
  description text not null check (char_length(description) between 20 and 2000),
  facts jsonb not null default '{}'::jsonb,
  status public.need_status not null default 'reported',
  priority_score integer check (priority_score between 0 and 100),
  public_location_text text not null,
  operational_location extensions.geography(point, 4326),
  exact_address_private text,
  contact_private jsonb not null default '{}'::jsonb,
  source_type text not null default 'citizen',
  expires_at timestamptz not null default (now() + interval '24 hours'),
  submitted_by uuid references auth.users(id),
  visibility public.visibility_level not null default 'private',
  duplicate_of uuid references public.need_cases(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index need_cases_queue_idx on public.need_cases(event_id, status, expires_at);

create table public.need_items (
  id uuid primary key default gen_random_uuid(),
  need_case_id uuid not null references public.need_cases(id) on delete cascade,
  category text not null,
  description text,
  quantity_required numeric(14,3) not null check (quantity_required > 0),
  unit text not null,
  quantity_covered numeric(14,3) not null default 0 check (quantity_covered >= 0),
  service_window interval,
  created_at timestamptz not null default now(),
  check (quantity_covered <= quantity_required)
);

create table public.need_verifications (
  id uuid primary key default gen_random_uuid(),
  need_case_id uuid not null references public.need_cases(id),
  decision text not null check (decision in ('verify','observe','reject','duplicate','disprove','renew','expire','publish','suspend')),
  note text not null,
  confidence integer check (confidence between 0 and 100),
  expires_at timestamptz,
  decided_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.public_need_projections (
  id uuid primary key default gen_random_uuid(),
  source_need_id uuid not null unique references public.need_cases(id),
  event_id uuid not null references public.emergency_events(id),
  category text not null,
  summary text not null,
  location_label text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  status text not null,
  confidence_label text not null,
  verified_at timestamptz,
  expires_at timestamptz not null,
  needed_quantity numeric(14,3) not null,
  covered_quantity numeric(14,3) not null,
  unit text not null,
  published boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.donation_intakes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  kind public.donation_kind not null,
  status public.intake_status not null default 'reported',
  tracking_code text not null unique default public.generate_tracking_code('APO'),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  donor_name_private text not null,
  contact_private jsonb not null default '{}'::jsonb,
  public_attribution_kind text not null check (public_attribution_kind in ('organization','authorized_name','alias','anonymous')),
  public_attribution text,
  attribution_authorized boolean not null default false,
  declared_status text,
  declared_amount numeric(16,2) check (declared_amount is null or declared_amount > 0),
  currency char(3) not null default 'COP',
  destination_note text,
  version integer not null default 1 check (version > 0),
  previous_version_id uuid references public.donation_intakes(id),
  submitted_by uuid not null references auth.users(id),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create table public.donation_intake_items (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.donation_intakes(id) on delete cascade,
  category text not null,
  description text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null,
  condition text,
  expires_on date,
  storage_requirement text,
  declared_estimated_value_cop numeric(16,2),
  created_at timestamptz not null default now()
);

create table public.intake_verification_decisions (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.donation_intakes(id),
  decision text not null check (decision in ('approve','observe','reject','duplicate','quarantine','cancel')),
  note text not null,
  decided_by uuid not null references auth.users(id),
  decided_at timestamptz not null default now()
);

create table public.donations (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid unique references public.donation_intakes(id),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  kind public.donation_kind not null,
  status public.donation_status not null default 'promised',
  donor_tracking_code text not null unique default public.generate_tracking_code('DON'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.donation_items (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id) on delete cascade,
  source_intake_item_id uuid references public.donation_intake_items(id),
  category text not null,
  description text not null,
  quantity_promised numeric(14,3) not null check (quantity_promised > 0),
  unit text not null,
  quantity_received numeric(14,3) not null default 0 check (quantity_received >= 0),
  quantity_rejected numeric(14,3) not null default 0 check (quantity_rejected >= 0),
  created_at timestamptz not null default now(),
  check (quantity_received + quantity_rejected <= quantity_promised)
);

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id),
  receipt_code text not null unique default public.generate_tracking_code('REC'),
  receipt_type text not null check (receipt_type in ('intake_acknowledgement','physical_receipt','payment_receipt')),
  issued_by uuid references auth.users(id),
  issued_at timestamptz not null default now(),
  disclaimer text not null,
  payload_hash text not null
);

create table public.tax_certificate_requests (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id),
  state public.case_status not null default 'open',
  requested_by uuid not null references auth.users(id),
  eligibility_note text,
  created_at timestamptz not null default now()
);

create table public.tax_certificates (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.tax_certificate_requests(id),
  certificate_number text not null unique,
  tax_eligible_value numeric(16,2) not null check (tax_eligible_value > 0),
  signed_by uuid not null references auth.users(id),
  evidence_id uuid,
  issued_at timestamptz not null default now()
);

create table public.item_acceptance_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  event_id uuid not null references public.emergency_events(id),
  category text not null,
  decision text not null check (decision in ('accepted','restricted','prohibited')),
  rule_text text not null,
  requires_cold_chain boolean not null default false,
  version integer not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  unique (organization_id, event_id, category, version)
);

create table public.inventory_locations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  name text not null,
  public_location_text text not null,
  exact_address_private text,
  cold_chain_capable boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.inventory_lots (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  donation_item_id uuid not null references public.donation_items(id),
  location_id uuid not null references public.inventory_locations(id),
  lot_code text not null unique default public.generate_tracking_code('LOT'),
  status public.lot_status not null default 'available',
  category text not null,
  quantity_initial numeric(14,3) not null check (quantity_initial > 0),
  unit text not null,
  condition text not null,
  expires_on date,
  storage_requirement text,
  received_by uuid not null references auth.users(id),
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index inventory_lots_fefo_idx on public.inventory_lots(event_id, category, expires_on) where status = 'available';

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  lot_id uuid not null references public.inventory_lots(id),
  movement_type public.stock_movement_type not null,
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  idempotency_key text not null,
  reason text not null,
  actor_id uuid not null references auth.users(id),
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create table public.inventory_counts (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.inventory_lots(id),
  expected_quantity numeric(14,3) not null,
  counted_quantity numeric(14,3) not null check (counted_quantity >= 0),
  note text not null,
  counted_by uuid not null references auth.users(id),
  counted_at timestamptz not null default now()
);

create table public.storage_condition_events (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.inventory_lots(id),
  event_type text not null check (event_type in ('temperature_reading','temperature_breach','damage','inspection')),
  reading numeric(10,3),
  unit text,
  note text not null,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.lot_hold_or_recalls (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.inventory_lots(id),
  action text not null check (action in ('hold','release','recall','dispose')),
  reason text not null,
  affected_delivery_ids uuid[] not null default '{}',
  decided_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.allocations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  lot_id uuid not null references public.inventory_lots(id),
  need_item_id uuid not null references public.need_items(id),
  quantity numeric(14,3) not null check (quantity > 0),
  status text not null default 'reserved' check (status in ('reserved','picked','dispatched','delivered','cancelled')),
  idempotency_key text not null,
  allocated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create table public.shipments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  shipment_code text not null unique default public.generate_tracking_code('DSP'),
  status public.shipment_status not null default 'draft',
  carrier_name text,
  custodian_private jsonb not null default '{}'::jsonb,
  destination_private text,
  public_destination text not null,
  dispatched_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.shipment_items (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  allocation_id uuid not null unique references public.allocations(id),
  quantity numeric(14,3) not null check (quantity > 0)
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id),
  status text not null check (status in ('reported','delivered','validated','incident')),
  quantity_delivered numeric(14,3) not null check (quantity_delivered >= 0),
  quantity_damaged numeric(14,3) not null default 0 check (quantity_damaged >= 0),
  recipient_confirmation_private jsonb not null default '{}'::jsonb,
  evidence_id uuid,
  delivered_at timestamptz,
  validated_by uuid references auth.users(id),
  validated_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.funds (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  name text not null,
  currency char(3) not null default 'COP',
  verified boolean not null default false,
  restrictions text,
  created_at timestamptz not null default now()
);

create table public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  fund_id uuid not null references public.funds(id),
  provider text not null,
  account_reference_private text not null,
  display_reference text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  fund_id uuid not null references public.funds(id),
  transaction_type public.financial_transaction_type not null,
  amount numeric(16,2) not null check (amount > 0),
  currency char(3) not null default 'COP',
  status text not null check (status in ('reported','provider_confirmed','reconciled','pending','failed','disputed')),
  provider text not null,
  provider_reference_private text not null,
  public_reference text not null,
  idempotency_key text not null,
  reverses_transaction_id uuid references public.financial_transactions(id),
  actor_id uuid references auth.users(id),
  reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_reference_private),
  unique (organization_id, idempotency_key)
);

create table public.expense_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  fund_id uuid not null references public.funds(id),
  amount numeric(16,2) not null check (amount > 0),
  purpose text not null,
  status public.expense_status not null default 'requested',
  requested_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expense_approvals (
  id uuid primary key default gen_random_uuid(),
  expense_request_id uuid not null references public.expense_requests(id),
  decision text not null check (decision in ('approved','rejected')),
  note text not null,
  approved_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (expense_request_id, approved_by)
);

create table public.expense_payments (
  id uuid primary key default gen_random_uuid(),
  expense_request_id uuid not null unique references public.expense_requests(id),
  financial_transaction_id uuid not null unique references public.financial_transactions(id),
  evidence_id uuid,
  paid_by uuid not null references auth.users(id),
  paid_at timestamptz not null default now()
);

create table public.evidence (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid not null references public.organizations(id),
  storage_path text not null unique,
  file_name_private text not null,
  mime_type text not null check (mime_type in ('image/jpeg','image/png','application/pdf')),
  size_bytes bigint not null check (size_bytes between 1 and 5242880),
  sha256 text not null,
  scan_status text not null default 'pending' check (scan_status in ('pending','clean','rejected','failed')),
  sensitivity public.visibility_level not null default 'private',
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.tax_certificates add constraint tax_certificates_evidence_fk foreign key (evidence_id) references public.evidence(id);
alter table public.deliveries add constraint deliveries_evidence_fk foreign key (evidence_id) references public.evidence(id);
alter table public.expense_payments add constraint expense_payments_evidence_fk foreign key (evidence_id) references public.evidence(id);

create table public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  organization_id uuid references public.organizations(id),
  target_table text not null,
  target_id uuid,
  reason_code text not null,
  status public.case_status not null default 'open',
  reporter_id uuid references auth.users(id),
  assigned_to uuid references auth.users(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.complaint_or_feedback_cases (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  tracking_code text not null unique default public.generate_tracking_code('CAS'),
  kind text not null check (kind in ('complaint','feedback','fraud','rectification','withdrawal')),
  message_private text not null,
  contact_private jsonb not null default '{}'::jsonb,
  status public.case_status not null default 'open',
  assigned_to uuid references auth.users(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.data_subject_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.emergency_events(id),
  tracking_code text not null unique default public.generate_tracking_code('DAT'),
  request_type text not null check (request_type in ('access','correction','deletion','withdraw_consent')),
  identity_evidence_private jsonb not null,
  status public.case_status not null default 'open',
  assigned_to uuid references auth.users(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.emergency_events(id),
  user_id uuid not null references auth.users(id),
  template_key text not null,
  channel text not null check (channel in ('in_app','email','sms')),
  payload_private jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','sent','failed','cancelled')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create table public.integration_events (
  id uuid primary key default gen_random_uuid(),
  integration text not null,
  event_type text not null,
  idempotency_key text not null,
  payload_hash text not null,
  status text not null check (status in ('received','processed','failed','ignored')),
  occurred_at timestamptz not null,
  processed_at timestamptz,
  attempt_count integer not null default 1,
  created_at timestamptz not null default now(),
  unique (integration, idempotency_key)
);

create table public.catalogs (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.catalog_versions (
  id uuid primary key default gen_random_uuid(),
  catalog_id uuid not null references public.catalogs(id),
  version integer not null,
  values_json jsonb not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  unique (catalog_id, version)
);

create table public.migration_batches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  source_system text not null,
  source_cut_at timestamptz not null,
  checksum_sha256 text not null,
  status text not null check (status in ('profiled','quarantined','reconciled','approved','applied','rolled_back','rejected')),
  input_count integer not null check (input_count >= 0),
  approved_count integer not null default 0,
  rejected_count integer not null default 0,
  duplicate_count integer not null default 0,
  quarantine_count integer not null default 0,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.migration_record_results (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.migration_batches(id),
  external_row_id text not null,
  result text not null check (result in ('approved','rejected','duplicate','quarantined')),
  quality_errors jsonb not null default '[]'::jsonb,
  duplicate_of_external_id text,
  created_entity_table text,
  created_entity_id uuid,
  created_at timestamptz not null default now(),
  unique (batch_id, external_row_id)
);

create table public.public_donation_projections (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null unique references public.donations(id),
  event_id uuid not null references public.emergency_events(id),
  public_code text not null unique,
  attribution text not null,
  kind public.donation_kind not null,
  category text not null,
  verified_quantity numeric(14,3),
  unit text,
  reconciled_amount numeric(16,2),
  currency char(3),
  destination_label text,
  operational_state text not null,
  evidence_level text not null,
  published boolean not null default false,
  published_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.public_metric_snapshots (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  metric_key text not null,
  value numeric(20,3) not null,
  unit text not null,
  formula text not null,
  source_cut_at timestamptz not null,
  timezone text not null default 'America/Bogota',
  dimensions jsonb not null default '{}'::jsonb,
  reconciled boolean not null default false,
  owner_role text not null,
  created_at timestamptz not null default now()
);

create table public.security_or_operational_incidents (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.emergency_events(id),
  organization_id uuid references public.organizations(id),
  severity text not null check (severity in ('P0','P1','P2','P3')),
  category text not null,
  summary text not null,
  status public.case_status not null default 'open',
  detected_by uuid references auth.users(id),
  assigned_to uuid references auth.users(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.emergency_events(id),
  organization_id uuid references public.organizations(id),
  actor_id uuid references auth.users(id),
  action text not null,
  entity_table text not null,
  entity_id uuid,
  correlation_id uuid not null default gen_random_uuid(),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index audit_events_entity_idx on public.audit_events(entity_table, entity_id, occurred_at);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger emergency_events_updated_at before update on public.emergency_events for each row execute function public.set_updated_at();
create trigger need_cases_updated_at before update on public.need_cases for each row execute function public.set_updated_at();
create trigger donation_intakes_updated_at before update on public.donation_intakes for each row execute function public.set_updated_at();
create trigger donations_updated_at before update on public.donations for each row execute function public.set_updated_at();
create trigger shipments_updated_at before update on public.shipments for each row execute function public.set_updated_at();
create trigger expense_requests_updated_at before update on public.expense_requests for each row execute function public.set_updated_at();

create or replace function public.prevent_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '42501', message = 'El historial append-only no puede modificarse ni eliminarse';
end;
$$;
create trigger audit_events_immutable before update or delete on public.audit_events for each row execute function public.prevent_mutation();
create trigger stock_movements_immutable before update or delete on public.stock_movements for each row execute function public.prevent_mutation();
create trigger financial_transactions_immutable before update or delete on public.financial_transactions for each row execute function public.prevent_mutation();
create trigger intake_decisions_immutable before update or delete on public.intake_verification_decisions for each row execute function public.prevent_mutation();

create or replace function public.is_event_member(target_event uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.event_id = target_event and m.active
  );
$$;

create or replace function public.is_org_member(target_org uuid, target_event uuid default null)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.organization_id = target_org and m.active
      and (target_event is null or m.event_id = target_event)
  );
$$;

create or replace function public.has_any_role(target_org uuid, target_event uuid, allowed_roles public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.organization_id = target_org
      and m.event_id = target_event and m.active and m.role = any(allowed_roles)
  );
$$;

create or replace function public.contains_sensitive_content(input text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(input, '') ~* '(\+?57[[:space:]-]?)?3[0-9]{2}[[:space:]-]?[0-9]{3}[[:space:]-]?[0-9]{4}|\m(cuenta|cuentas|ahorros|corriente|nequi|daviplata|bancolombia)\M|n[uú]mero de tarjeta|https?://';
$$;

create or replace function public.audit_row_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  payload jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  changed text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(n.key order by n.key) into changed
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o using (key)
    where n.value is distinct from o.value;
  else
    changed := array[tg_op];
  end if;

  insert into public.audit_events(event_id, organization_id, actor_id, action, entity_table, entity_id, metadata)
  values (
    case when payload ? 'event_id' and payload->>'event_id' is not null then (payload->>'event_id')::uuid else null end,
    case when payload ? 'organization_id' and payload->>'organization_id' is not null then (payload->>'organization_id')::uuid else null end,
    (select auth.uid()), lower(tg_op), tg_table_name,
    case when payload ? 'id' then (payload->>'id')::uuid else null end,
    jsonb_build_object('changed_fields', to_jsonb(coalesce(changed, '{}'::text[])))
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'need_cases','need_verifications','donation_intakes','intake_verification_decisions',
    'donations','receipts','inventory_lots','stock_movements','allocations','shipments',
    'deliveries','financial_transactions','expense_requests','expense_approvals','expense_payments',
    'evidence','moderation_reports','migration_batches','security_or_operational_incidents'
  ] loop
    execute format('create trigger %I_audit after insert or update or delete on public.%I for each row execute function public.audit_row_change()', table_name, table_name);
  end loop;
end $$;

create or replace function public.submit_need_report(
  p_event_id uuid,
  p_category text,
  p_description text,
  p_public_location text,
  p_quantity numeric,
  p_unit text,
  p_exact_address_private text default null,
  p_contact_private jsonb default '{}'::jsonb
)
returns table(need_id uuid, tracking_code text, status public.need_status)
language plpgsql security definer set search_path = '' as $$
declare created public.need_cases;
begin
  if not exists (select 1 from public.emergency_events e where e.id = p_event_id and e.status = 'active') then
    raise exception using errcode = '22023', message = 'El evento no está disponible para reportes';
  end if;
  if char_length(trim(p_description)) < 20 or char_length(trim(p_description)) > 2000 then
    raise exception using errcode = '22023', message = 'Describe los hechos con entre 20 y 2000 caracteres';
  end if;
  if public.contains_sensitive_content(p_description) or public.contains_sensitive_content(p_public_location) then
    insert into public.moderation_reports(event_id, target_table, reason_code, due_at)
    values (p_event_id, 'need_cases', 'sensitive_content_blocked', now() + interval '15 minutes');
    raise exception using errcode = '22023', message = 'No incluyas teléfonos, cuentas ni enlaces en campos públicos';
  end if;
  if p_quantity <= 0 or length(trim(p_unit)) = 0 then
    raise exception using errcode = '22023', message = 'Cantidad y unidad deben ser válidas';
  end if;

  insert into public.need_cases(event_id, category, description, public_location_text, exact_address_private, contact_private, submitted_by)
  values (p_event_id, trim(p_category), trim(p_description), trim(p_public_location), nullif(trim(p_exact_address_private), ''), p_contact_private, (select auth.uid()))
  returning * into created;

  insert into public.need_items(need_case_id, category, description, quantity_required, unit)
  values (created.id, trim(p_category), trim(p_description), p_quantity, trim(p_unit));

  return query select created.id, created.tracking_code, created.status;
end;
$$;

create or replace function public.submit_donation_intake(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric default null
)
returns table(intake_id uuid, tracking_code text, status public.intake_status, was_duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare created public.donation_intakes;
declare item jsonb;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión como aliado';
  end if;
  if not public.has_any_role(p_organization_id, p_event_id, array['partner_reporter','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No perteneces al aliado indicado';
  end if;
  if length(p_idempotency_key) < 8 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;

  select * into created from public.donation_intakes
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return query select created.id, created.tracking_code, created.status, true;
    return;
  end if;

  if p_attribution_kind = 'authorized_name' and not p_attribution_authorized then
    raise exception using errcode = '22023', message = 'La atribución personal exige autorización expresa';
  end if;
  if p_kind = 'in_kind' and (jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 20) then
    raise exception using errcode = '22023', message = 'Agrega entre 1 y 20 artículos';
  end if;
  if p_kind = 'money' and (p_declared_amount is null or p_declared_amount <= 0) then
    raise exception using errcode = '22023', message = 'El monto declarado debe ser mayor que cero';
  end if;

  insert into public.donation_intakes(
    event_id, organization_id, kind, status, idempotency_key, donor_name_private,
    contact_private, public_attribution_kind, public_attribution, attribution_authorized,
    declared_status, declared_amount, submitted_by
  ) values (
    p_event_id, p_organization_id, p_kind, 'pending_verification', p_idempotency_key,
    trim(p_donor_name_private), p_contact_private, p_attribution_kind,
    case when p_attribution_kind = 'anonymous' then null else nullif(trim(p_public_attribution), '') end,
    p_attribution_authorized, p_declared_status, p_declared_amount, (select auth.uid())
  ) returning * into created;

  if p_kind = 'in_kind' then
    for item in select value from jsonb_array_elements(p_items) loop
      if coalesce((item->>'quantity')::numeric, 0) <= 0 or length(trim(coalesce(item->>'unit',''))) = 0 then
        raise exception using errcode = '22023', message = 'Cada artículo requiere cantidad y unidad válidas';
      end if;
      if lower(coalesce(item->>'condition','')) in ('abierto','vencido') then
        raise exception using errcode = '22023', message = 'No se aceptan artículos abiertos o vencidos';
      end if;
      insert into public.donation_intake_items(intake_id, category, description, quantity, unit, condition, expires_on, storage_requirement)
      values (
        created.id, trim(item->>'category'), trim(item->>'description'), (item->>'quantity')::numeric,
        trim(item->>'unit'), nullif(trim(item->>'condition'), ''), nullif(item->>'expires_on','')::date,
        nullif(trim(item->>'storage_requirement'), '')
      );
    end loop;
  end if;

  insert into public.receipts(donation_id, receipt_type, disclaimer, payload_hash)
  select d.id, 'intake_acknowledgement', 'Constancia de reporte: no acredita recepción física, conciliación, entrega ni beneficio.', encode(extensions.digest(created.id::text || created.submitted_at::text, 'sha256'), 'hex')
  from public.donations d where false;

  return query select created.id, created.tracking_code, created.status, false;
end;
$$;

create or replace function public.review_donation_intake(p_intake_id uuid, p_decision text, p_note text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare intake public.donation_intakes;
declare donation_id uuid;
begin
  select * into intake from public.donation_intakes where id = p_intake_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Ingreso no encontrado'; end if;
  if not public.has_any_role(intake.organization_id, intake.event_id, array['verifier','event_admin']::public.app_role[]) then
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
    on conflict do nothing;
  end if;
  return donation_id;
end;
$$;

create or replace function public.receive_donation(
  p_donation_item_id uuid,
  p_location_id uuid,
  p_accepted numeric,
  p_rejected numeric,
  p_condition text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare item public.donation_items;
declare donation public.donations;
declare location public.inventory_locations;
declare existing uuid;
declare lot_id uuid;
begin
  select l.id into existing from public.inventory_lots l
    join public.stock_movements s on s.lot_id = l.id
    where s.idempotency_key = p_idempotency_key;
  if found then return existing; end if;

  select * into item from public.donation_items where id = p_donation_item_id for update;
  select * into donation from public.donations where id = item.donation_id for update;
  select * into location from public.inventory_locations where id = p_location_id;
  if not found or item.id is null or donation.id is null then raise exception using errcode = 'P0002', message = 'Donación o centro no encontrado'; end if;
  if not public.has_any_role(donation.organization_id, donation.event_id, array['warehouse_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes recibir en este centro';
  end if;
  if location.organization_id <> donation.organization_id or location.event_id <> donation.event_id then
    raise exception using errcode = '42501', message = 'Centro fuera del tenant';
  end if;
  if p_accepted < 0 or p_rejected < 0 or item.quantity_received + item.quantity_rejected + p_accepted + p_rejected > item.quantity_promised then
    raise exception using errcode = '22023', message = 'Las cantidades no concilian con la promesa';
  end if;
  if p_accepted = 0 then
    update public.donation_items set quantity_rejected = quantity_rejected + p_rejected where id = item.id;
    update public.donations set status = 'rejected' where id = donation.id;
    return null;
  end if;

  insert into public.inventory_lots(event_id, organization_id, donation_item_id, location_id, category, quantity_initial, unit, condition, received_by)
  values (donation.event_id, donation.organization_id, item.id, location.id, item.category, p_accepted, item.unit, p_condition, (select auth.uid()))
  returning id into lot_id;
  insert into public.stock_movements(event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id)
  values (donation.event_id, donation.organization_id, lot_id, 'receipt', p_accepted, p_idempotency_key, 'Recepción aceptada', (select auth.uid()));
  update public.donation_items set quantity_received = quantity_received + p_accepted, quantity_rejected = quantity_rejected + p_rejected where id = item.id;
  update public.donations set status = case when p_accepted + p_rejected < item.quantity_promised then 'partial'::public.donation_status else 'received'::public.donation_status end where id = donation.id;
  return lot_id;
end;
$$;

create or replace function public.allocate_stock(
  p_lot_id uuid,
  p_need_item_id uuid,
  p_quantity numeric,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare lot public.inventory_lots;
declare need_item public.need_items;
declare available numeric;
declare allocation_id uuid;
begin
  select a.id into allocation_id from public.allocations a where a.idempotency_key = p_idempotency_key;
  if found then return allocation_id; end if;
  select * into lot from public.inventory_lots where id = p_lot_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Lote no encontrado'; end if;
  if not public.has_any_role(lot.organization_id, lot.event_id, array['warehouse_operator','logistics_operator','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes asignar este lote';
  end if;
  if lot.status not in ('available','reserved') then raise exception using errcode = '22023', message = 'El lote está bloqueado o no disponible'; end if;
  select * into need_item from public.need_items where id = p_need_item_id;
  if not found then raise exception using errcode = 'P0002', message = 'Necesidad no encontrada'; end if;
  select coalesce(sum(quantity_delta),0) into available from public.stock_movements where lot_id = p_lot_id;
  if p_quantity <= 0 or available < p_quantity then raise exception using errcode = '22023', message = 'Existencia insuficiente'; end if;
  if need_item.unit <> lot.unit or need_item.category <> lot.category then raise exception using errcode = '22023', message = 'Categoría o unidad incompatible'; end if;

  insert into public.allocations(event_id, organization_id, lot_id, need_item_id, quantity, idempotency_key, allocated_by)
  values (lot.event_id, lot.organization_id, lot.id, need_item.id, p_quantity, p_idempotency_key, (select auth.uid()))
  returning id into allocation_id;
  insert into public.stock_movements(event_id, organization_id, lot_id, movement_type, quantity_delta, idempotency_key, reason, actor_id)
  values (lot.event_id, lot.organization_id, lot.id, 'reserve', -p_quantity, p_idempotency_key || ':stock', 'Reserva para necesidad', (select auth.uid()));
  update public.inventory_lots set status = case when available = p_quantity then 'reserved'::public.lot_status else status end where id = lot.id;
  return allocation_id;
end;
$$;

create or replace function public.reconcile_sandbox_payment(
  p_fund_id uuid,
  p_amount numeric,
  p_provider_reference text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_fund public.funds;
declare tx_id uuid;
begin
  select id into tx_id from public.financial_transactions where idempotency_key = p_idempotency_key;
  if found then return tx_id; end if;
  select * into target_fund from public.funds where id = p_fund_id for update;
  if not found or not target_fund.verified then raise exception using errcode = '22023', message = 'El fondo no está verificado'; end if;
  if not public.has_any_role(target_fund.organization_id, target_fund.event_id, array['treasury_approver','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes conciliar este fondo';
  end if;
  if p_amount <= 0 then raise exception using errcode = '22023', message = 'Monto inválido'; end if;
  insert into public.financial_transactions(event_id, organization_id, fund_id, transaction_type, amount, status, provider, provider_reference_private, public_reference, idempotency_key, actor_id, reconciled_at)
  values (target_fund.event_id, target_fund.organization_id, target_fund.id, 'credit', p_amount, 'reconciled', 'sandbox', p_provider_reference, 'SANDBOX-' || right(encode(extensions.digest(p_provider_reference, 'sha256'), 'hex'), 8), p_idempotency_key, (select auth.uid()), now())
  returning id into tx_id;
  return tx_id;
end;
$$;

create or replace function public.request_expense(p_fund_id uuid, p_amount numeric, p_purpose text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_fund public.funds;
declare expense_id uuid;
begin
  select * into target_fund from public.funds where id = p_fund_id;
  if not public.has_any_role(target_fund.organization_id, target_fund.event_id, array['treasury_requester','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes solicitar gastos';
  end if;
  insert into public.expense_requests(event_id, organization_id, fund_id, amount, purpose, requested_by)
  values (target_fund.event_id, target_fund.organization_id, target_fund.id, p_amount, trim(p_purpose), (select auth.uid())) returning id into expense_id;
  return expense_id;
end;
$$;

create or replace function public.approve_expense(p_expense_id uuid, p_decision text, p_note text)
returns public.expense_status language plpgsql security definer set search_path = '' as $$
declare expense public.expense_requests;
declare next_status public.expense_status;
begin
  select * into expense from public.expense_requests where id = p_expense_id for update;
  if not found or expense.status <> 'requested' then raise exception using errcode = '22023', message = 'Solicitud no disponible'; end if;
  if not public.has_any_role(expense.organization_id, expense.event_id, array['treasury_approver','event_admin']::public.app_role[]) then
    raise exception using errcode = '42501', message = 'No puedes aprobar gastos';
  end if;
  if expense.requested_by = (select auth.uid()) then raise exception using errcode = '42501', message = 'No puedes aprobar tu propia solicitud'; end if;
  if p_decision not in ('approved','rejected') then raise exception using errcode = '22023', message = 'Decisión inválida'; end if;
  insert into public.expense_approvals(expense_request_id, decision, note, approved_by)
  values (expense.id, p_decision, trim(p_note), (select auth.uid()));
  next_status := p_decision::public.expense_status;
  update public.expense_requests set status = next_status where id = expense.id;
  return next_status;
end;
$$;

create or replace function public.track_public_code(p_tracking_code text)
returns table(code text, record_type text, safe_status text, last_update timestamptz, message text)
language plpgsql security definer set search_path = '' as $$
begin
  if p_tracking_code !~ '^(NEC|APO|DON)-[A-F0-9]{24}$' then return; end if;
  return query
    select n.tracking_code, 'need', n.status::text, n.updated_at,
      'Tu reporte está protegido. La ubicación exacta y el contacto no son públicos.'
    from public.need_cases n where n.tracking_code = p_tracking_code
    union all
    select i.tracking_code, 'intake', i.status::text, i.updated_at,
      'Esta constancia corresponde a un reporte y no acredita recepción, entrega ni conciliación.'
    from public.donation_intakes i where i.tracking_code = p_tracking_code
    union all
    select d.donor_tracking_code, 'donation', d.status::text, d.updated_at,
      'El estado se deriva de eventos operacionales autorizados.'
    from public.donations d where d.donor_tracking_code = p_tracking_code
    limit 1;
end;
$$;

create or replace view public.public_event_dashboard
with (security_invoker = true) as
select e.id as event_id, e.slug, e.name, e.public_summary, e.starts_at, e.timezone,
  (select count(*) from public.public_need_projections n where n.event_id = e.id and n.published and n.expires_at > now()) as active_needs,
  (select coalesce(sum(n.covered_quantity),0) from public.public_need_projections n where n.event_id = e.id and n.published) as units_delivered,
  (select count(*) from public.public_donation_projections d where d.event_id = e.id and d.published) as visible_donations,
  (select coalesce(max(m.value) filter (where m.metric_key = 'reconciled_balance'),0)
    from public.public_metric_snapshots m where m.event_id = e.id and m.reconciled) as reconciled_balance
from public.emergency_events e
where e.status = 'active';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidence-private', 'evidence-private', false, 5242880, array['image/jpeg','image/png','application/pdf'])
on conflict (id) do nothing;

alter table public.organizations enable row level security;
alter table public.organization_verifications enable row level security;
alter table public.profiles enable row level security;
alter table public.emergency_events enable row level security;
alter table public.memberships enable row level security;
alter table public.official_sources enable row level security;
alter table public.source_assertions enable row level security;
alter table public.source_conflicts enable row level security;
alter table public.territorial_units enable row level security;
alter table public.public_location_projections enable row level security;
alter table public.need_cases enable row level security;
alter table public.need_items enable row level security;
alter table public.need_verifications enable row level security;
alter table public.public_need_projections enable row level security;
alter table public.donation_intakes enable row level security;
alter table public.donation_intake_items enable row level security;
alter table public.intake_verification_decisions enable row level security;
alter table public.donations enable row level security;
alter table public.donation_items enable row level security;
alter table public.receipts enable row level security;
alter table public.tax_certificate_requests enable row level security;
alter table public.tax_certificates enable row level security;
alter table public.item_acceptance_rules enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.inventory_lots enable row level security;
alter table public.stock_movements enable row level security;
alter table public.inventory_counts enable row level security;
alter table public.storage_condition_events enable row level security;
alter table public.lot_hold_or_recalls enable row level security;
alter table public.allocations enable row level security;
alter table public.shipments enable row level security;
alter table public.shipment_items enable row level security;
alter table public.deliveries enable row level security;
alter table public.funds enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.financial_transactions enable row level security;
alter table public.expense_requests enable row level security;
alter table public.expense_approvals enable row level security;
alter table public.expense_payments enable row level security;
alter table public.evidence enable row level security;
alter table public.moderation_reports enable row level security;
alter table public.complaint_or_feedback_cases enable row level security;
alter table public.data_subject_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.integration_events enable row level security;
alter table public.catalogs enable row level security;
alter table public.catalog_versions enable row level security;
alter table public.migration_batches enable row level security;
alter table public.migration_record_results enable row level security;
alter table public.public_donation_projections enable row level security;
alter table public.public_metric_snapshots enable row level security;
alter table public.security_or_operational_incidents enable row level security;
alter table public.audit_events enable row level security;

create policy "public reads active events" on public.emergency_events for select using (status = 'active');
create policy "members read events" on public.emergency_events for select to authenticated using (public.is_event_member(id));
create policy "public reads territory" on public.territorial_units for select using (true);
create policy "public reads approved locations" on public.public_location_projections for select using (approved_at is not null);
create policy "public reads published needs" on public.public_need_projections for select using (published and expires_at > now());
create policy "public reads published donations" on public.public_donation_projections for select using (published);
create policy "public reads reconciled metrics" on public.public_metric_snapshots for select using (reconciled);
create policy "public reads catalogs" on public.catalogs for select using (true);
create policy "public reads catalog versions" on public.catalog_versions for select using (effective_from <= now() and (effective_to is null or effective_to > now()));

create policy "users read own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "users update own profile" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "users read own memberships" on public.memberships for select to authenticated using (user_id = (select auth.uid()));
create policy "members read organizations" on public.organizations for select to authenticated using (public.is_org_member(id));

create policy "event members read needs" on public.need_cases for select to authenticated using (public.is_event_member(event_id));
create policy "event members read need items" on public.need_items for select to authenticated using (exists (select 1 from public.need_cases n where n.id = need_case_id and public.is_event_member(n.event_id)));
create policy "event members read verifications" on public.need_verifications for select to authenticated using (exists (select 1 from public.need_cases n where n.id = need_case_id and public.is_event_member(n.event_id)));

create policy "org members read intakes" on public.donation_intakes for select to authenticated using (public.is_org_member(organization_id, event_id));
create policy "org members read intake items" on public.donation_intake_items for select to authenticated using (exists (select 1 from public.donation_intakes i where i.id = intake_id and public.is_org_member(i.organization_id, i.event_id)));
create policy "org members read intake decisions" on public.intake_verification_decisions for select to authenticated using (exists (select 1 from public.donation_intakes i where i.id = intake_id and public.is_org_member(i.organization_id, i.event_id)));

do $$
declare table_name text;
begin
  foreach table_name in array array['donations','inventory_locations','inventory_lots','stock_movements','allocations','shipments','funds','financial_transactions','expense_requests','evidence','moderation_reports','security_or_operational_incidents'] loop
    execute format('create policy "org members read %1$s" on public.%1$I for select to authenticated using (public.is_org_member(organization_id, event_id))', table_name);
  end loop;
end $$;

create policy "members read donation items" on public.donation_items for select to authenticated using (exists (select 1 from public.donations d where d.id = donation_id and public.is_org_member(d.organization_id, d.event_id)));
create policy "members read receipts" on public.receipts for select to authenticated using (exists (select 1 from public.donations d where d.id = donation_id and public.is_org_member(d.organization_id, d.event_id)));
create policy "users read notifications" on public.notifications for select to authenticated using (user_id = (select auth.uid()));
create policy "auditors read audit" on public.audit_events for select to authenticated using (
  exists (select 1 from public.memberships m where m.user_id = (select auth.uid()) and m.active and m.role in ('auditor','event_admin') and (audit_events.event_id is null or m.event_id = audit_events.event_id))
);

create policy "members upload private evidence" on storage.objects for insert to authenticated with check (
  bucket_id = 'evidence-private' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/' and public.is_org_member((split_part(name,'/',2))::uuid, (split_part(name,'/',1))::uuid)
);
create policy "members read private evidence" on storage.objects for select to authenticated using (
  bucket_id = 'evidence-private' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/' and public.is_org_member((split_part(name,'/',2))::uuid, (split_part(name,'/',1))::uuid)
);

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.emergency_events, public.territorial_units, public.public_location_projections,
  public.public_need_projections, public.public_donation_projections, public.public_metric_snapshots,
  public.catalogs, public.catalog_versions, public.public_event_dashboard to anon, authenticated;
grant select on all tables in schema public to authenticated;
grant update on public.profiles to authenticated;
grant execute on function public.submit_need_report(uuid,text,text,text,numeric,text,text,jsonb) to anon, authenticated;
grant execute on function public.submit_donation_intake(uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric) to authenticated;
grant execute on function public.review_donation_intake(uuid,text,text) to authenticated;
grant execute on function public.receive_donation(uuid,uuid,numeric,numeric,text,text) to authenticated;
grant execute on function public.allocate_stock(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.reconcile_sandbox_payment(uuid,numeric,text,text) to authenticated;
grant execute on function public.request_expense(uuid,numeric,text) to authenticated;
grant execute on function public.approve_expense(uuid,text,text) to authenticated;
grant execute on function public.track_public_code(text) to anon, authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'full_name',''), split_part(new.email,'@',1), 'Usuario'))
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ============================================================
-- 202608130002_operational_workflows.sql
-- ============================================================
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

-- ============================================================
-- 202608130003_moderation_word_boundaries.sql
-- ============================================================
create or replace function public.contains_sensitive_content(input text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(input, '') ~* '(\+?57[[:space:]-]?)?3[0-9]{2}[[:space:]-]?[0-9]{3}[[:space:]-]?[0-9]{4}|\m(cuenta|cuentas|ahorros|corriente|nequi|daviplata|bancolombia)\M|n[uú]mero de tarjeta|https?://';
$$;

-- ============================================================
-- 202608140001_complete_operational_workflows.sql
-- ============================================================
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

-- ============================================================
-- 202608140002_fix_migration_counters.sql
-- ============================================================
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

-- ============================================================
-- 202608140003_territorial_map.sql
-- ============================================================
-- Capa geoespacial pública para el centro territorial.
-- Solo transforma coordenadas aproximadas ya aprobadas para publicación.

create extension if not exists postgis with schema extensions;

alter table public.public_need_projections
  add column if not exists approximate_location extensions.geometry(Point, 4326)
  generated always as (
    case
      when latitude is null or longitude is null then null
      else extensions.st_setsrid(
        extensions.st_makepoint(longitude::double precision, latitude::double precision),
        4326
      )
    end
  ) stored;

create index if not exists public_need_projections_approximate_location_gix
  on public.public_need_projections
  using gist (approximate_location)
  where published;

create or replace function public.public_need_map(
  p_event_id uuid,
  p_min_longitude double precision default null,
  p_min_latitude double precision default null,
  p_max_longitude double precision default null,
  p_max_latitude double precision default null
)
returns table(
  id uuid,
  category text,
  summary text,
  location_label text,
  status text,
  needed_quantity numeric,
  covered_quantity numeric,
  unit text,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    projection.id,
    projection.category,
    projection.summary,
    projection.location_label,
    projection.status,
    projection.needed_quantity,
    projection.covered_quantity,
    projection.unit,
    extensions.st_y(projection.approximate_location),
    extensions.st_x(projection.approximate_location),
    projection.updated_at
  from public.public_need_projections as projection
  where projection.event_id = p_event_id
    and projection.published
    and projection.expires_at > now()
    and projection.approximate_location is not null
    and (
      p_min_longitude is null
      or p_min_latitude is null
      or p_max_longitude is null
      or p_max_latitude is null
      or extensions.st_intersects(
        projection.approximate_location,
        extensions.st_makeenvelope(
          p_min_longitude,
          p_min_latitude,
          p_max_longitude,
          p_max_latitude,
          4326
        )
      )
    )
  order by projection.updated_at desc;
$$;

grant execute on function public.public_need_map(uuid, double precision, double precision, double precision, double precision)
  to anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'public_need_projections'
  ) then
    alter publication supabase_realtime add table public.public_need_projections;
  end if;
end;
$$;

comment on column public.public_need_projections.approximate_location is
  'Punto público aproximado derivado de la proyección aprobada; nunca contiene una dirección operacional.';

comment on function public.public_need_map(uuid, double precision, double precision, double precision, double precision) is
  'Devuelve únicamente necesidades públicas vigentes con coordenadas aproximadas y filtro espacial opcional.';

-- ============================================================
-- 202608140004_friendly_ux.sql
-- ============================================================
-- Proyección segura de centros y preferencia de entrega para el flujo amigable.

alter table public.inventory_locations
  add column if not exists public_latitude numeric(9,6),
  add column if not exists public_longitude numeric(9,6);

alter table public.inventory_locations
  add constraint inventory_locations_public_coordinates_pair
  check ((public_latitude is null) = (public_longitude is null));

alter table public.donation_intakes
  add column if not exists preferred_location_id uuid references public.inventory_locations(id);

create or replace function public.public_collection_centers(p_event_id uuid)
returns table(
  id uuid,
  name text,
  location_label text,
  accepts text[],
  restricted_items text[],
  cold_chain_capable boolean,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    location.id,
    location.name,
    location.public_location_text,
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision = 'accepted'), '{}'::text[]),
    coalesce(array_agg(distinct rule.category order by rule.category) filter (where rule.decision in ('restricted','prohibited')), '{}'::text[]),
    location.cold_chain_capable,
    location.public_latitude::double precision,
    location.public_longitude::double precision
  from public.inventory_locations as location
  left join public.item_acceptance_rules as rule
    on rule.organization_id = location.organization_id
    and rule.event_id = location.event_id
    and rule.effective_from <= now()
  where location.event_id = p_event_id
    and location.public_latitude is not null
    and location.public_longitude is not null
  group by location.id
  order by location.name;
$$;

revoke all on function public.public_collection_centers(uuid) from public;
grant execute on function public.public_collection_centers(uuid) to anon, authenticated;

create or replace function public.submit_donation_intake(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric,
  p_preferred_location_id uuid
)
returns table(intake_id uuid, tracking_code text, status public.intake_status, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare submitted record;
begin
  if p_kind = 'in_kind' then
    if p_preferred_location_id is null or not exists (
      select 1 from public.inventory_locations
      where id = p_preferred_location_id and event_id = p_event_id
    ) then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega válido';
    end if;
  end if;

  select * into submitted
  from public.submit_donation_intake(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    p_declared_status,
    p_items,
    p_declared_amount
  );

  if not submitted.was_duplicate then
    update public.donation_intakes
    set preferred_location_id = case when p_kind = 'in_kind' then p_preferred_location_id else null end
    where id = submitted.intake_id;
  end if;

  return query select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid
) to authenticated;

comment on function public.public_collection_centers(uuid) is
  'Proyección pública explícita de centros sintéticos, ubicación aproximada y reglas vigentes; excluye direcciones exactas.';

comment on column public.donation_intakes.preferred_location_id is
  'Preferencia operativa declarada; no acredita recepción y puede cambiar durante la coordinación autorizada.';

-- ============================================================
-- 202608140005_reporting_analytics.sql
-- ============================================================
-- Contexto declarativo para reportes y exportaciones analíticas.
-- Todos estos campos permanecen en la tabla operacional protegida por RLS.

alter table public.donation_intakes
  add column if not exists donor_type text,
  add column if not exists economic_sector text,
  add column if not exists specific_destination boolean not null default false,
  add column if not exists destination_department text,
  add column if not exists destination_municipality text,
  add column if not exists estimated_beneficiaries integer,
  add column if not exists delivery_channel text,
  add column if not exists internal_responsible_private text,
  add column if not exists internal_contact_private jsonb not null default '{}'::jsonb,
  add column if not exists observations_private text;

alter table public.donation_intakes
  add constraint donation_intakes_donor_type_check
    check (donor_type is null or donor_type in ('persona','empresa','gremio','fundacion','otro')),
  add constraint donation_intakes_economic_sector_length
    check (economic_sector is null or char_length(economic_sector) between 2 and 120),
  add constraint donation_intakes_destination_department_length
    check (destination_department is null or char_length(destination_department) between 2 and 100),
  add constraint donation_intakes_destination_municipality_length
    check (destination_municipality is null or char_length(destination_municipality) between 2 and 140),
  add constraint donation_intakes_estimated_beneficiaries_positive
    check (estimated_beneficiaries is null or estimated_beneficiaries > 0),
  add constraint donation_intakes_delivery_channel_length
    check (delivery_channel is null or char_length(delivery_channel) between 2 and 160),
  add constraint donation_intakes_internal_responsible_length
    check (internal_responsible_private is null or char_length(internal_responsible_private) between 2 and 160),
  add constraint donation_intakes_internal_contact_object
    check (jsonb_typeof(internal_contact_private) = 'object'),
  add constraint donation_intakes_observations_length
    check (observations_private is null or char_length(observations_private) <= 2000),
  add constraint donation_intakes_specific_destination_fields
    check (
      not specific_destination
      or (destination_department is not null and destination_municipality is not null)
    );

create or replace function public.submit_donation_intake(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric,
  p_preferred_location_id uuid,
  p_reporting_context jsonb
)
returns table(intake_id uuid, tracking_code text, status public.intake_status, was_duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare submitted record;
declare context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
declare wants_destination boolean := coalesce((context->>'specific_destination')::boolean, false);
declare beneficiary_count integer := nullif(context->>'estimated_beneficiaries', '')::integer;
begin
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;
  if nullif(context->>'donor_type', '') is not null
    and context->>'donor_type' not in ('persona','empresa','gremio','fundacion','otro') then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante válido';
  end if;
  if wants_destination and (
    length(trim(coalesce(context->>'destination_department', ''))) < 2
    or length(trim(coalesce(context->>'destination_municipality', ''))) < 2
  ) then
    raise exception using errcode = '22023', message = 'La destinación específica requiere departamento y municipio o zona';
  end if;
  if beneficiary_count is not null and beneficiary_count <= 0 then
    raise exception using errcode = '22023', message = 'Los beneficiarios estimados deben ser mayores que cero';
  end if;
  if context ? 'internal_contact' and jsonb_typeof(context->'internal_contact') <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto interno debe ser un objeto';
  end if;
  if jsonb_typeof(p_items) = 'array' and exists (
    select 1
    from jsonb_array_elements(p_items) as supplied(item)
    where nullif(item->>'declared_estimated_value_cop', '')::numeric <= 0
  ) then
    raise exception using errcode = '22023', message = 'El valor estimado de un artículo debe ser mayor que cero';
  end if;

  select * into submitted
  from public.submit_donation_intake(
    p_event_id,
    p_organization_id,
    p_kind,
    p_idempotency_key,
    p_donor_name_private,
    p_contact_private,
    p_attribution_kind,
    p_public_attribution,
    p_attribution_authorized,
    p_declared_status,
    p_items,
    p_declared_amount,
    p_preferred_location_id
  );

  if not submitted.was_duplicate then
    update public.donation_intakes
    set
      donor_type = nullif(context->>'donor_type', ''),
      economic_sector = nullif(trim(context->>'economic_sector'), ''),
      specific_destination = wants_destination,
      destination_note = case when wants_destination then nullif(trim(context->>'destination_note'), '') else null end,
      destination_department = case when wants_destination then nullif(trim(context->>'destination_department'), '') else null end,
      destination_municipality = case when wants_destination then nullif(trim(context->>'destination_municipality'), '') else null end,
      estimated_beneficiaries = beneficiary_count,
      delivery_channel = nullif(trim(context->>'delivery_channel'), ''),
      internal_responsible_private = nullif(trim(context->>'internal_responsible'), ''),
      internal_contact_private = coalesce(context->'internal_contact', '{}'::jsonb),
      observations_private = nullif(trim(context->>'observations'), '')
    where id = submitted.intake_id;

    with supplied as (
      select ordinality::integer as position, nullif(item->>'declared_estimated_value_cop', '')::numeric as estimated_value
      from jsonb_array_elements(p_items) with ordinality as valueset(item, ordinality)
    ), persisted as (
      select id, row_number() over (order by created_at, id)::integer as position
      from public.donation_intake_items as persisted_item
      where persisted_item.intake_id = submitted.intake_id
    )
    update public.donation_intake_items as item
    set declared_estimated_value_cop = supplied.estimated_value
    from supplied
    join persisted using (position)
    where item.id = persisted.id
      and supplied.estimated_value is not null;
  end if;

  return query select submitted.intake_id, submitted.tracking_code, submitted.status, submitted.was_duplicate;
end;
$$;

grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid, jsonb
) to authenticated;

comment on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text, boolean, text, jsonb, numeric, uuid, jsonb
) is 'Intake guiado con organización derivada de membresía, centro, contexto privado, idempotencia y auditoría.';

comment on column public.donation_intakes.estimated_beneficiaries is
  'Estimación declarada y privada; nunca alimenta métricas públicas de impacto sin verificación y conciliación.';
comment on column public.donation_intakes.internal_contact_private is
  'Contacto operacional privado sujeto a RLS; se excluye de proyecciones públicas y exportaciones de transparencia.';
comment on column public.donation_intake_items.declared_estimated_value_cop is
  'Valor declarado no conciliado; no constituye ingreso financiero ni cifra pública.';

-- ============================================================
-- 202608140006_realtime_logistics_map.sql
-- ============================================================
-- Cartografía real en cliente + proyección pública segura para acopio y despachos.
-- La proyección solo conserva zonas/coordenadas aproximadas ya autorizadas.

create table public.public_logistics_projections (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.emergency_events(id),
  source_type text not null check (source_type in ('collection_center', 'dispatch')),
  source_id uuid not null,
  public_code text not null,
  label text not null,
  status text not null,
  origin_label text,
  origin_latitude numeric(9,6),
  origin_longitude numeric(9,6),
  destination_label text,
  destination_latitude numeric(9,6),
  destination_longitude numeric(9,6),
  published boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (source_type, source_id),
  check ((origin_latitude is null) = (origin_longitude is null)),
  check ((destination_latitude is null) = (destination_longitude is null)),
  check (origin_latitude is null or origin_latitude between -90 and 90),
  check (origin_longitude is null or origin_longitude between -180 and 180),
  check (destination_latitude is null or destination_latitude between -90 and 90),
  check (destination_longitude is null or destination_longitude between -180 and 180)
);

create index public_logistics_projections_event_idx
  on public.public_logistics_projections(event_id, source_type, updated_at desc)
  where published;

alter table public.public_logistics_projections enable row level security;
alter table public.public_logistics_projections replica identity full;

create policy "public reads published logistics"
  on public.public_logistics_projections
  for select
  using (published);

revoke all on public.public_logistics_projections from anon, authenticated;
grant select on public.public_logistics_projections to anon, authenticated;

create or replace function public.sync_public_collection_projection(p_location_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare location public.inventory_locations;
begin
  select * into location from public.inventory_locations where id = p_location_id;
  if not found then
    update public.public_logistics_projections
    set published = false, updated_at = now()
    where source_type = 'collection_center' and source_id = p_location_id;
    return;
  end if;

  insert into public.public_logistics_projections(
    event_id, source_type, source_id, public_code, label, status,
    origin_label, origin_latitude, origin_longitude, published, updated_at
  ) values (
    location.event_id,
    'collection_center',
    location.id,
    'CAC-' || upper(right(replace(location.id::text, '-', ''), 8)),
    location.name,
    case when location.active then 'active' else 'inactive' end,
    location.public_location_text,
    location.public_latitude,
    location.public_longitude,
    location.active and location.public_latitude is not null and location.public_longitude is not null,
    now()
  )
  on conflict (source_type, source_id) do update set
    event_id = excluded.event_id,
    public_code = excluded.public_code,
    label = excluded.label,
    status = excluded.status,
    origin_label = excluded.origin_label,
    origin_latitude = excluded.origin_latitude,
    origin_longitude = excluded.origin_longitude,
    published = excluded.published,
    updated_at = now();
end;
$$;

create or replace function public.sync_public_shipment_projection(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare projection record;
begin
  select
    shipment.event_id,
    shipment.id,
    shipment.shipment_code,
    shipment.status::text,
    location.name as origin_name,
    location.public_location_text as origin_label,
    location.public_latitude as origin_latitude,
    location.public_longitude as origin_longitude,
    coalesce(need_projection.location_label, shipment.public_destination) as destination_label,
    need_projection.latitude as destination_latitude,
    need_projection.longitude as destination_longitude,
    need_projection.published as destination_published
  into projection
  from public.shipments as shipment
  left join public.shipment_items as shipment_item on shipment_item.shipment_id = shipment.id
  left join public.allocations as allocation on allocation.id = shipment_item.allocation_id
  left join public.inventory_lots as lot on lot.id = allocation.lot_id
  left join public.inventory_locations as location on location.id = lot.location_id
  left join public.need_items as need_item on need_item.id = allocation.need_item_id
  left join public.need_cases as need_case on need_case.id = need_item.need_case_id
  left join public.public_need_projections as need_projection on need_projection.source_need_id = need_case.id
  where shipment.id = p_shipment_id
  order by shipment_item.id nulls last
  limit 1;

  if not found then
    update public.public_logistics_projections
    set published = false, updated_at = now()
    where source_type = 'dispatch' and source_id = p_shipment_id;
    return;
  end if;

  insert into public.public_logistics_projections(
    event_id, source_type, source_id, public_code, label, status,
    origin_label, origin_latitude, origin_longitude,
    destination_label, destination_latitude, destination_longitude,
    published, updated_at
  ) values (
    projection.event_id,
    'dispatch',
    projection.id,
    projection.shipment_code,
    'Despacho ' || projection.shipment_code,
    projection.status,
    nullif(concat_ws(' · ', projection.origin_name, projection.origin_label), ''),
    projection.origin_latitude,
    projection.origin_longitude,
    projection.destination_label,
    projection.destination_latitude,
    projection.destination_longitude,
    projection.status in ('dispatched', 'in_transit', 'delivered', 'validated')
      and projection.origin_latitude is not null
      and projection.origin_longitude is not null
      and projection.destination_latitude is not null
      and projection.destination_longitude is not null
      and coalesce(projection.destination_published, false),
    now()
  )
  on conflict (source_type, source_id) do update set
    event_id = excluded.event_id,
    public_code = excluded.public_code,
    label = excluded.label,
    status = excluded.status,
    origin_label = excluded.origin_label,
    origin_latitude = excluded.origin_latitude,
    origin_longitude = excluded.origin_longitude,
    destination_label = excluded.destination_label,
    destination_latitude = excluded.destination_latitude,
    destination_longitude = excluded.destination_longitude,
    published = excluded.published,
    updated_at = now();
end;
$$;

create or replace function public.sync_collection_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare shipment_row record;
begin
  if tg_op = 'DELETE' then
    perform public.sync_public_collection_projection(old.id);
    return old;
  end if;

  perform public.sync_public_collection_projection(new.id);
  for shipment_row in
    select distinct shipment_item.shipment_id
    from public.shipment_items as shipment_item
    join public.allocations as allocation on allocation.id = shipment_item.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    where lot.location_id = new.id
  loop
    perform public.sync_public_shipment_projection(shipment_row.shipment_id);
  end loop;
  return new;
end;
$$;

create or replace function public.sync_shipment_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_public_shipment_projection(case when tg_op = 'DELETE' then old.id else new.id end);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.sync_shipment_item_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_public_shipment_projection(case when tg_op = 'DELETE' then old.shipment_id else new.shipment_id end);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.sync_need_logistics_projection_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare shipment_row record;
begin
  for shipment_row in
    select distinct shipment_item.shipment_id
    from public.shipment_items as shipment_item
    join public.allocations as allocation on allocation.id = shipment_item.allocation_id
    join public.need_items as need_item on need_item.id = allocation.need_item_id
    where need_item.need_case_id = new.source_need_id
  loop
    perform public.sync_public_shipment_projection(shipment_row.shipment_id);
  end loop;
  return new;
end;
$$;

create trigger inventory_locations_public_projection
after insert or update or delete on public.inventory_locations
for each row execute function public.sync_collection_projection_trigger();

create trigger shipments_public_projection
after insert or update or delete on public.shipments
for each row execute function public.sync_shipment_projection_trigger();

create trigger shipment_items_public_projection
after insert or update or delete on public.shipment_items
for each row execute function public.sync_shipment_item_projection_trigger();

create trigger public_need_logistics_projection
after update on public.public_need_projections
for each row execute function public.sync_need_logistics_projection_trigger();

create or replace function public.public_logistics_map(p_event_id uuid)
returns table(
  id uuid,
  source_type text,
  public_code text,
  label text,
  status text,
  origin_label text,
  origin_latitude double precision,
  origin_longitude double precision,
  destination_label text,
  destination_latitude double precision,
  destination_longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    projection.id,
    projection.source_type,
    projection.public_code,
    projection.label,
    projection.status,
    projection.origin_label,
    projection.origin_latitude::double precision,
    projection.origin_longitude::double precision,
    projection.destination_label,
    projection.destination_latitude::double precision,
    projection.destination_longitude::double precision,
    projection.updated_at
  from public.public_logistics_projections as projection
  where projection.event_id = p_event_id and projection.published
  order by projection.source_type, projection.updated_at desc;
$$;

revoke all on function public.sync_public_collection_projection(uuid) from public, anon, authenticated;
revoke all on function public.sync_public_shipment_projection(uuid) from public, anon, authenticated;
revoke all on function public.sync_collection_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_shipment_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_shipment_item_projection_trigger() from public, anon, authenticated;
revoke all on function public.sync_need_logistics_projection_trigger() from public, anon, authenticated;
grant execute on function public.public_logistics_map(uuid) to anon, authenticated;

select public.sync_public_collection_projection(id) from public.inventory_locations;
select public.sync_public_shipment_projection(id) from public.shipments;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'public_logistics_projections'
  ) then
    alter publication supabase_realtime add table public.public_logistics_projections;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgname = 'inventory_locations_audit' and tgrelid = 'public.inventory_locations'::regclass
  ) then
    create trigger inventory_locations_audit
    after insert or update or delete on public.inventory_locations
    for each row execute function public.audit_row_change();
  end if;
end;
$$;

comment on table public.public_logistics_projections is
  'Proyección cartográfica pública: centros y rutas origen-destino aproximadas. No contiene direcciones, transportadores, custodios ni GPS.';
comment on function public.public_logistics_map(uuid) is
  'Devuelve centros activos y despachos publicables con coordenadas aproximadas para MapLibre y Realtime.';

-- ============================================================
-- 202608140007_explicit_function_privileges.sql
-- ============================================================
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


-- ============================================================
-- 202608140008_authenticated_donation_intake.sql
-- ============================================================
-- El registro de aportes conserva datos privados y exige membresía aliada.
-- El reporte ciudadano y el seguimiento por código continúan siendo anónimos.
revoke execute on function public.submit_donation_intake(
  uuid,uuid,public.donation_kind,text,text,jsonb,text,text,boolean,text,jsonb,numeric,uuid,jsonb
) from anon;


-- ============================================================
-- 202608140009_foreign_key_indexes.sql
-- ============================================================
-- PostgreSQL no crea índices automáticamente para las columnas que referencian
-- claves foráneas. Indexarlas evita escaneos completos en joins, RLS y cascadas.

do $$
declare
  target record;
  target_index_name text;
begin
  for target in
    select distinct
      table_schema.nspname as schema_name,
      target_table.relname as table_name,
      target_column.attname as column_name
    from pg_catalog.pg_constraint as foreign_key
    join pg_catalog.pg_class as target_table
      on target_table.oid = foreign_key.conrelid
    join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = target_table.relnamespace
    join lateral unnest(foreign_key.conkey) as key_column(attnum)
      on true
    join pg_catalog.pg_attribute as target_column
      on target_column.attrelid = foreign_key.conrelid
      and target_column.attnum = key_column.attnum
    where foreign_key.contype = 'f'
      and table_schema.nspname = 'public'
      and not exists (
        select 1
        from pg_catalog.pg_index as existing_index
        where existing_index.indrelid = foreign_key.conrelid
          and key_column.attnum = any(existing_index.indkey)
      )
  loop
    target_index_name := format(
      'fk_%s_%s_%s_idx',
      left(target.table_name, 24),
      left(target.column_name, 20),
      substr(md5(target.schema_name || '.' || target.table_name || '.' || target.column_name), 1, 8)
    );

    execute format(
      'create index if not exists %I on %I.%I (%I)',
      target_index_name,
      target.schema_name,
      target.table_name,
      target.column_name
    );
  end loop;
end;
$$;

-- ============================================================
-- 20260815200619_align_donation_flow.sql
-- ============================================================
-- Alineación del registro de aportes con el recorrido funcional auditado.
-- Los datos declarados siguen siendo privados hasta que exista evidencia validada.

alter table public.donation_intakes
  add column request_fingerprint text;

update public.donation_intakes
set request_fingerprint = encode(
  extensions.digest(('legacy:' || id::text)::bytea, 'sha256'),
  'hex'
)
where request_fingerprint is null;

update public.donation_intakes
set declared_status = 'comprometida'
where declared_status is null
   or declared_status not in ('comprometida', 'en_transito', 'entregada_por_validar');

alter table public.donation_intakes
  alter column request_fingerprint set not null,
  alter column declared_status set not null,
  add constraint donation_intakes_request_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint donation_intakes_donor_name_check
    check (char_length(btrim(donor_name_private)) between 2 and 160),
  add constraint donation_intakes_contact_object_check
    check (jsonb_typeof(contact_private) = 'object'),
  add constraint donation_intakes_declared_status_check
    check (declared_status in ('comprometida', 'en_transito', 'entregada_por_validar'));

alter table public.donation_intake_items
  add constraint donation_intake_items_category_check
    check (category = any (array['Agua', 'Alimentos', 'Higiene', 'Refugio', 'Salud', 'Protección']::text[])),
  add constraint donation_intake_items_description_check
    check (char_length(btrim(description)) between 3 and 500),
  add constraint donation_intake_items_unit_check
    check (unit = any (array['unidad', 'litro', 'kilogramo', 'kit', 'caja']::text[])),
  add constraint donation_intake_items_declared_value_check
    check (declared_estimated_value_cop is null or declared_estimated_value_cop > 0);

alter table public.public_donation_projections
  add column donation_item_id uuid references public.donation_items(id);

update public.public_donation_projections as projection
set donation_item_id = (
  select item.id
  from public.donation_items as item
  where item.donation_id = projection.donation_id
  order by item.created_at, item.id
  limit 1
)
where projection.verified_quantity is not null;

alter table public.public_donation_projections
  drop constraint if exists public_donation_projections_donation_id_key,
  add constraint public_donation_projections_donation_item_key unique (donation_item_id);

create index public_donation_projections_donation_id_idx
  on public.public_donation_projections (donation_id);

create unique index public_donation_projections_money_donation_key
  on public.public_donation_projections (donation_id)
  where donation_item_id is null;

alter table public.financial_transactions
  add column donation_id uuid references public.donations(id);

create unique index financial_transactions_donation_id_key
  on public.financial_transactions (donation_id)
  where donation_id is not null;

create or replace function public.submit_donation_intake(
  p_event_id uuid,
  p_organization_id uuid,
  p_kind public.donation_kind,
  p_idempotency_key text,
  p_donor_name_private text,
  p_contact_private jsonb,
  p_attribution_kind text,
  p_public_attribution text,
  p_attribution_authorized boolean,
  p_declared_status text,
  p_items jsonb,
  p_declared_amount numeric,
  p_preferred_location_id uuid,
  p_reporting_context jsonb
)
returns table(
  intake_id uuid,
  tracking_code text,
  status public.intake_status,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  created public.donation_intakes;
  item jsonb;
  context jsonb := coalesce(p_reporting_context, '{}'::jsonb);
  wants_destination boolean;
  beneficiary_count integer;
  public_name text;
  organization_name text;
  contact_email text;
  contact_phone text;
  internal_contact jsonb;
  fingerprint text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Debes iniciar sesión como aliado';
  end if;
  if not public.has_any_role(
    p_organization_id,
    p_event_id,
    array['partner_reporter', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No perteneces al aliado indicado';
  end if;
  if not exists (
    select 1
    from public.emergency_events as event
    where event.id = p_event_id and event.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'El evento no está disponible para aportes';
  end if;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = p_organization_id;

  if char_length(btrim(coalesce(p_idempotency_key, ''))) not between 8 and 120 then
    raise exception using errcode = '22023', message = 'Clave idempotente inválida';
  end if;
  if char_length(btrim(coalesce(p_donor_name_private, ''))) not between 2 and 160 then
    raise exception using errcode = '22023', message = 'Escribe el nombre del donante';
  end if;
  if jsonb_typeof(coalesce(p_contact_private, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto privado debe ser un objeto';
  end if;

  contact_email := lower(btrim(coalesce(p_contact_private ->> 'email', '')));
  contact_phone := btrim(coalesce(p_contact_private ->> 'phone', ''));
  if contact_email !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$' then
    raise exception using errcode = '22023', message = 'Escribe un correo de coordinación válido';
  end if;
  if contact_phone <> '' and char_length(contact_phone) not between 7 and 30 then
    raise exception using errcode = '22023', message = 'El teléfono de coordinación no es válido';
  end if;

  if p_attribution_kind not in ('organization', 'authorized_name', 'alias', 'anonymous') then
    raise exception using errcode = '22023', message = 'Selecciona una atribución pública válida';
  end if;
  if p_attribution_kind = 'anonymous' then
    public_name := null;
  elsif p_attribution_kind = 'organization' then
    public_name := organization_name;
  else
    if p_attribution_kind = 'authorized_name' and not coalesce(p_attribution_authorized, false) then
      raise exception using errcode = '22023', message = 'La atribución personal exige autorización expresa';
    end if;
    if char_length(btrim(coalesce(p_public_attribution, ''))) not between 2 and 120 then
      raise exception using errcode = '22023', message = 'Escribe una atribución pública válida';
    end if;
    public_name := btrim(p_public_attribution);
  end if;

  if p_declared_status not in ('comprometida', 'en_transito', 'entregada_por_validar') then
    raise exception using errcode = '22023', message = 'Selecciona un estado declarado válido';
  end if;
  if jsonb_typeof(context) <> 'object' then
    raise exception using errcode = '22023', message = 'El contexto del aporte debe ser un objeto';
  end if;

  wants_destination := coalesce((context ->> 'specific_destination')::boolean, false);
  beneficiary_count := nullif(context ->> 'estimated_beneficiaries', '')::integer;
  internal_contact := coalesce(context -> 'internal_contact', '{}'::jsonb);

  if nullif(context ->> 'donor_type', '') is not null
     and context ->> 'donor_type' not in ('persona', 'empresa', 'gremio', 'fundacion', 'otro') then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de donante válido';
  end if;
  if nullif(btrim(coalesce(context ->> 'economic_sector', '')), '') is not null
     and char_length(btrim(context ->> 'economic_sector')) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'El sector económico no es válido';
  end if;
  if wants_destination and (
    char_length(btrim(coalesce(context ->> 'destination_department', ''))) < 2
    or char_length(btrim(coalesce(context ->> 'destination_municipality', ''))) < 2
  ) then
    raise exception using errcode = '22023', message = 'La destinación específica requiere departamento y municipio o zona';
  end if;
  if beneficiary_count is not null and beneficiary_count <= 0 then
    raise exception using errcode = '22023', message = 'Los beneficiarios estimados deben ser mayores que cero';
  end if;
  if jsonb_typeof(internal_contact) <> 'object' then
    raise exception using errcode = '22023', message = 'El contacto interno debe ser un objeto';
  end if;
  if char_length(coalesce(context ->> 'destination_note', '')) > 240
     or char_length(coalesce(context ->> 'destination_municipality', '')) > 140
     or char_length(coalesce(context ->> 'delivery_channel', '')) > 160
     or char_length(coalesce(context ->> 'internal_responsible', '')) > 160
     or char_length(coalesce(context ->> 'observations', '')) > 2000
     or char_length(coalesce(internal_contact ->> 'value', '')) > 180 then
    raise exception using errcode = '22023', message = 'Uno de los campos privados excede el tamaño permitido';
  end if;

  if p_kind = 'money' then
    if p_declared_amount is null or p_declared_amount <= 0 then
      raise exception using errcode = '22023', message = 'El monto declarado debe ser mayor que cero';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) <> 0 then
      raise exception using errcode = '22023', message = 'El aporte monetario no debe incluir artículos';
    end if;
  else
    if p_declared_amount is not null then
      raise exception using errcode = '22023', message = 'El aporte en especie no usa un monto global';
    end if;
    if p_preferred_location_id is null or not exists (
      select 1
      from public.inventory_locations as location
      where location.id = p_preferred_location_id
        and location.event_id = p_event_id
        and location.active
    ) then
      raise exception using errcode = '22023', message = 'Selecciona un centro de entrega válido';
    end if;
    if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) not between 1 and 20 then
      raise exception using errcode = '22023', message = 'Agrega entre 1 y 20 artículos';
    end if;

    for item in select value from jsonb_array_elements(p_items)
    loop
      if item ->> 'category' is null
         or item ->> 'category' <> all (array['Agua', 'Alimentos', 'Higiene', 'Refugio', 'Salud', 'Protección']::text[]) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una categoría válida';
      end if;
      if char_length(btrim(coalesce(item ->> 'description', ''))) not between 3 and 500 then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una descripción válida';
      end if;
      if coalesce((item ->> 'quantity')::numeric, 0) <= 0 then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una cantidad positiva';
      end if;
      if item ->> 'unit' is null
         or item ->> 'unit' <> all (array['unidad', 'litro', 'kilogramo', 'kit', 'caja']::text[]) then
        raise exception using errcode = '22023', message = 'Cada artículo requiere una unidad válida';
      end if;
      if coalesce(item ->> 'condition', '') not in ('sellado', 'nuevo') then
        raise exception using errcode = '22023', message = 'No se aceptan artículos abiertos o vencidos';
      end if;
      if coalesce(item ->> 'storage_requirement', '') not in ('ambiente', 'frio', 'seco') then
        raise exception using errcode = '22023', message = 'Selecciona un cuidado de almacenamiento válido';
      end if;
      if nullif(item ->> 'expires_on', '')::date is not null
         and nullif(item ->> 'expires_on', '')::date <= current_date then
        raise exception using errcode = '22023', message = 'No se aceptan artículos vencidos';
      end if;
      if nullif(item ->> 'declared_estimated_value_cop', '')::numeric is not null
         and nullif(item ->> 'declared_estimated_value_cop', '')::numeric <= 0 then
        raise exception using errcode = '22023', message = 'El valor estimado debe ser mayor que cero';
      end if;
    end loop;
  end if;

  fingerprint := encode(
    extensions.digest(
      jsonb_build_object(
        'event_id', p_event_id,
        'organization_id', p_organization_id,
        'kind', p_kind,
        'donor_name_private', btrim(p_donor_name_private),
        'contact_private', jsonb_build_object('email', contact_email, 'phone', nullif(contact_phone, '')),
        'attribution_kind', p_attribution_kind,
        'public_attribution', public_name,
        'attribution_authorized', coalesce(p_attribution_authorized, false),
        'declared_status', p_declared_status,
        'items', coalesce(p_items, '[]'::jsonb),
        'declared_amount', p_declared_amount,
        'preferred_location_id', p_preferred_location_id,
        'reporting_context', context
      )::text::bytea,
      'sha256'
    ),
    'hex'
  );

  insert into public.donation_intakes(
    event_id,
    organization_id,
    kind,
    status,
    tracking_code,
    idempotency_key,
    donor_name_private,
    contact_private,
    public_attribution_kind,
    public_attribution,
    attribution_authorized,
    declared_status,
    declared_amount,
    preferred_location_id,
    donor_type,
    economic_sector,
    specific_destination,
    destination_note,
    destination_department,
    destination_municipality,
    estimated_beneficiaries,
    delivery_channel,
    internal_responsible_private,
    internal_contact_private,
    observations_private,
    submitted_by,
    request_fingerprint
  ) values (
    p_event_id,
    p_organization_id,
    p_kind,
    'pending_verification',
    public.generate_tracking_code('APO'),
    p_idempotency_key,
    btrim(p_donor_name_private),
    jsonb_build_object('email', contact_email, 'phone', nullif(contact_phone, '')),
    p_attribution_kind,
    public_name,
    coalesce(p_attribution_authorized, false),
    p_declared_status,
    p_declared_amount,
    case when p_kind = 'in_kind' then p_preferred_location_id else null end,
    nullif(context ->> 'donor_type', ''),
    nullif(btrim(context ->> 'economic_sector'), ''),
    wants_destination,
    case when wants_destination then nullif(btrim(context ->> 'destination_note'), '') else null end,
    case when wants_destination then nullif(btrim(context ->> 'destination_department'), '') else null end,
    case when wants_destination then nullif(btrim(context ->> 'destination_municipality'), '') else null end,
    beneficiary_count,
    nullif(btrim(context ->> 'delivery_channel'), ''),
    nullif(btrim(context ->> 'internal_responsible'), ''),
    internal_contact,
    nullif(btrim(context ->> 'observations'), ''),
    actor_id,
    fingerprint
  )
  on conflict (organization_id, idempotency_key) do nothing
  returning * into created;

  if created.id is null then
    select * into created
    from public.donation_intakes as existing
    where existing.organization_id = p_organization_id
      and existing.idempotency_key = p_idempotency_key;

    if created.request_fingerprint is distinct from fingerprint then
      raise exception using errcode = '22023', message = 'La clave idempotente ya fue usada con datos diferentes';
    end if;

    return query select created.id, created.tracking_code, created.status, true;
    return;
  end if;

  if p_kind = 'in_kind' then
    insert into public.donation_intake_items(
      intake_id,
      category,
      description,
      quantity,
      unit,
      condition,
      expires_on,
      storage_requirement,
      declared_estimated_value_cop
    )
    select
      created.id,
      btrim(value ->> 'category'),
      btrim(value ->> 'description'),
      (value ->> 'quantity')::numeric,
      btrim(value ->> 'unit'),
      btrim(value ->> 'condition'),
      nullif(value ->> 'expires_on', '')::date,
      btrim(value ->> 'storage_requirement'),
      nullif(value ->> 'declared_estimated_value_cop', '')::numeric
    from jsonb_array_elements(p_items);
  end if;

  return query select created.id, created.tracking_code, created.status, false;
end;
$$;

revoke all on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) to authenticated;

comment on function public.submit_donation_intake(
  uuid, uuid, public.donation_kind, text, text, jsonb, text, text,
  boolean, text, jsonb, numeric, uuid, jsonb
) is 'Registro aliado validado en servidor, atómico e idempotente; conserva campos privados fuera de las proyecciones públicas.';

create or replace function public.validate_delivery(
  p_delivery_id uuid,
  p_note text default 'Validación sandbox'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.deliveries;
  shipment public.shipments;
  shipped_item public.shipment_items;
  allocation public.allocations;
  need_item public.need_items;
  donation_item public.donation_items;
  donation public.donations;
  intake public.donation_intakes;
begin
  select * into target
  from public.deliveries
  where id = p_delivery_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Entrega no encontrada';
  end if;

  select * into shipment
  from public.shipments
  where id = target.shipment_id
  for update;
  if not public.has_event_role(
    shipment.event_id,
    array['verifier', 'event_admin']::public.app_role[]
  ) then
    raise exception using errcode = '42501', message = 'No puedes validar esta entrega';
  end if;

  select * into shipped_item
  from public.shipment_items
  where shipment_id = shipment.id
  order by id
  limit 1;
  select * into allocation
  from public.allocations
  where id = shipped_item.allocation_id
  for update;
  select * into need_item
  from public.need_items
  where id = allocation.need_item_id
  for update;
  select * into donation_item
  from public.donation_items
  where id = (
    select lot.donation_item_id
    from public.inventory_lots as lot
    where lot.id = allocation.lot_id
  );
  select * into donation
  from public.donations
  where id = donation_item.donation_id
  for update;
  select * into intake
  from public.donation_intakes
  where id = donation.intake_id;

  if target.status = 'validated' then
    return donation.id;
  end if;
  if target.status not in ('delivered', 'incident') then
    raise exception using errcode = '22023', message = 'Entrega no disponible para validación';
  end if;
  if need_item.quantity_covered + target.quantity_delivered > need_item.quantity_required then
    raise exception using errcode = '22023', message = 'La entrega excede la necesidad pendiente';
  end if;

  update public.deliveries
  set status = 'validated',
      validated_by = (select auth.uid()),
      validated_at = now(),
      recipient_confirmation_private = jsonb_build_object('note', left(p_note, 240))
  where id = target.id;
  update public.shipments set status = 'validated' where id = shipment.id;
  update public.allocations set status = 'delivered' where id = allocation.id;
  update public.need_items
  set quantity_covered = quantity_covered + target.quantity_delivered
  where id = need_item.id;
  update public.need_cases
  set status = case
    when need_item.quantity_covered + target.quantity_delivered >= need_item.quantity_required
      then 'covered'::public.need_status
    else 'partially_covered'::public.need_status
  end
  where id = need_item.need_case_id;
  update public.public_need_projections
  set covered_quantity = covered_quantity + target.quantity_delivered,
      status = case
        when covered_quantity + target.quantity_delivered >= needed_quantity then 'Cubierta'
        else 'Parcialmente cubierta'
      end,
      updated_at = now()
  where source_need_id = need_item.need_case_id;

  update public.donations
  set status = 'validated', updated_at = now()
  where id = donation.id;

  insert into public.public_donation_projections(
    donation_id,
    donation_item_id,
    event_id,
    public_code,
    attribution,
    kind,
    category,
    verified_quantity,
    unit,
    destination_label,
    operational_state,
    evidence_level,
    published,
    published_at
  ) values (
    donation.id,
    donation_item.id,
    donation.event_id,
    donation.donor_tracking_code || '-' || left(replace(donation_item.id::text, '-', ''), 8),
    case intake.public_attribution_kind
      when 'anonymous' then 'Anónimo'
      when 'organization' then coalesce(intake.public_attribution, 'Organización aliada')
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    donation.kind,
    donation_item.category,
    target.quantity_delivered,
    donation_item.unit,
    shipment.public_destination,
    'validated',
    'operational_events',
    true,
    now()
  )
  on conflict (donation_item_id) do update
  set verified_quantity = public.public_donation_projections.verified_quantity + excluded.verified_quantity,
      destination_label = excluded.destination_label,
      operational_state = excluded.operational_state,
      evidence_level = excluded.evidence_level,
      published = true,
      published_at = excluded.published_at,
      updated_at = now();

  return donation.id;
end;
$$;

revoke all on function public.validate_delivery(uuid, text) from public, anon, authenticated;
grant execute on function public.validate_delivery(uuid, text) to authenticated;

create or replace function public.treasury_pending_money_donations(p_event_id uuid)
returns table(
  donation_id uuid,
  tracking_code text,
  intake_tracking_code text,
  declared_amount numeric,
  currency text,
  attribution text,
  submitted_at timestamptz
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or not public.has_event_role(
       p_event_id,
       array['treasury_approver', 'event_admin', 'auditor']::public.app_role[]
     ) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar aportes monetarios';
  end if;

  return query
  select
    donation.id,
    donation.donor_tracking_code,
    intake.tracking_code,
    intake.declared_amount,
    intake.currency::text,
    case
      when intake.public_attribution_kind = 'anonymous' then 'Anónimo'
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    intake.submitted_at
  from public.donations as donation
  join public.donation_intakes as intake on intake.id = donation.intake_id
  where donation.event_id = p_event_id
    and donation.kind = 'money'
    and donation.status = 'promised'
    and intake.status = 'approved'
  order by intake.submitted_at;
end;
$$;

revoke all on function public.treasury_pending_money_donations(uuid) from public, anon, authenticated;
grant execute on function public.treasury_pending_money_donations(uuid) to authenticated;

create or replace function public.reconcile_money_donation(
  p_donation_id uuid,
  p_fund_id uuid,
  p_provider_reference_private text,
  p_idempotency_key text
)
returns table(
  transaction_id uuid,
  source_donation_id uuid,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  donation public.donations;
  intake public.donation_intakes;
  fund public.funds;
  transaction_record public.financial_transactions;
  destination_label text;
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

  select * into donation
  from public.donations
  where id = p_donation_id
  for update;
  if not found or donation.kind <> 'money' then
    raise exception using errcode = 'P0002', message = 'Aporte monetario no encontrado';
  end if;
  select * into intake
  from public.donation_intakes
  where id = donation.intake_id
  for update;
  select * into fund
  from public.funds
  where id = p_fund_id
  for update;

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
    raise exception using errcode = '22023', message = 'El aporte no está listo para conciliación';
  end if;
  if intake.declared_amount is null or intake.declared_amount <= 0 then
    raise exception using errcode = '22023', message = 'El aporte no tiene un valor declarado válido';
  end if;

  insert into public.financial_transactions(
    event_id,
    organization_id,
    fund_id,
    donation_id,
    transaction_type,
    amount,
    currency,
    status,
    provider,
    provider_reference_private,
    public_reference,
    idempotency_key,
    actor_id,
    reconciled_at
  ) values (
    fund.event_id,
    fund.organization_id,
    fund.id,
    donation.id,
    'credit',
    intake.declared_amount,
    intake.currency,
    'reconciled',
    'donation_intake',
    btrim(p_provider_reference_private),
    'DON-' || donation.donor_tracking_code,
    p_idempotency_key,
    actor_id,
    now()
  )
  returning * into transaction_record;

  update public.donations
  set status = 'validated', updated_at = now()
  where id = donation.id;

  destination_label := case
    when intake.specific_destination
      then nullif(concat_ws(', ', intake.destination_municipality, intake.destination_department), '')
    else null
  end;

  insert into public.public_donation_projections(
    donation_id,
    donation_item_id,
    event_id,
    public_code,
    attribution,
    kind,
    category,
    reconciled_amount,
    currency,
    destination_label,
    operational_state,
    evidence_level,
    published,
    published_at
  ) values (
    donation.id,
    null,
    donation.event_id,
    donation.donor_tracking_code,
    case intake.public_attribution_kind
      when 'anonymous' then 'Anónimo'
      when 'organization' then coalesce(intake.public_attribution, 'Organización aliada')
      else coalesce(intake.public_attribution, 'Atribución reservada')
    end,
    'money',
    'Aporte económico',
    intake.declared_amount,
    intake.currency,
    destination_label,
    'reconciled',
    'financial_reconciliation',
    true,
    now()
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

  insert into public.receipts(
    donation_id,
    receipt_type,
    issued_by,
    disclaimer,
    payload_hash
  ) values (
    donation.id,
    'payment_receipt',
    actor_id,
    'Constancia sandbox de conciliación: no certifica beneficio, impacto ni deducibilidad tributaria.',
    encode(
      extensions.digest(
        (transaction_record.id::text || ':' || btrim(p_provider_reference_private))::bytea,
        'sha256'
      ),
      'hex'
    )
  );

  return query select transaction_record.id, donation.id, false;
end;
$$;

revoke all on function public.reconcile_money_donation(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.reconcile_money_donation(uuid, uuid, text, text) to authenticated;

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
begin
  if nullif(btrim(coalesce(p_bot_field, '')), '') is not null then
    raise exception using errcode = '22023', message = 'No fue posible procesar el reporte';
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

-- Una sola política permisiva por operación evita evaluaciones duplicadas sin
-- ampliar el alcance: se conserva la unión de miembro de organización y verificador.
drop policy if exists "members read need item allocations" on public.allocations;

drop policy if exists "event verifiers read all intakes" on public.donation_intakes;
drop policy if exists "org members read intakes" on public.donation_intakes;
create policy "authorized members read intakes"
on public.donation_intakes
for select
to authenticated
using (
  public.is_org_member(organization_id, event_id)
  or public.has_event_role(
    event_id,
    array['verifier', 'event_admin', 'auditor']::public.app_role[]
  )
);

drop policy if exists "event verifiers read all intake items" on public.donation_intake_items;
drop policy if exists "org members read intake items" on public.donation_intake_items;
create policy "authorized members read intake items"
on public.donation_intake_items
for select
to authenticated
using (
  exists (
    select 1
    from public.donation_intakes as intake
    where intake.id = donation_intake_items.intake_id
      and (
        public.is_org_member(intake.organization_id, intake.event_id)
        or public.has_event_role(
          intake.event_id,
          array['verifier', 'event_admin', 'auditor']::public.app_role[]
        )
      )
  )
);

drop policy if exists "event verifiers read all intake decisions" on public.intake_verification_decisions;
drop policy if exists "org members read intake decisions" on public.intake_verification_decisions;
create policy "authorized members read intake decisions"
on public.intake_verification_decisions
for select
to authenticated
using (
  exists (
    select 1
    from public.donation_intakes as intake
    where intake.id = intake_verification_decisions.intake_id
      and (
        public.is_org_member(intake.organization_id, intake.event_id)
        or public.has_event_role(
          intake.event_id,
          array['verifier', 'event_admin', 'auditor']::public.app_role[]
        )
      )
  )
);

drop policy if exists "public reads active events" on public.emergency_events;
create policy "public reads active events"
on public.emergency_events
for select
to anon
using (status = 'active');

comment on column public.donation_intakes.request_fingerprint is
  'SHA-256 del contenido validado; impide reutilizar una clave idempotente con una solicitud diferente.';
comment on column public.public_donation_projections.donation_item_id is
  'Ítem fuente de una proyección en especie. Las proyecciones monetarias conservan este campo nulo.';
comment on column public.financial_transactions.donation_id is
  'Aporte monetario conciliado por este movimiento financiero append-only.';

-- ============================================================
-- 20260815224447_harden_local_operations.sql
-- ============================================================
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

-- Registro de migraciones aplicadas, para que el CLI las reconozca
insert into supabase_migrations.schema_migrations (version, name) values ('202608130001', 'initial_schema') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608130002', 'operational_workflows') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608130003', 'moderation_word_boundaries') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140001', 'complete_operational_workflows') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140002', 'fix_migration_counters') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140003', 'territorial_map') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140004', 'friendly_ux') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140005', 'reporting_analytics') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140006', 'realtime_logistics_map') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140007', 'explicit_function_privileges') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140008', 'authenticated_donation_intake') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('202608140009', 'foreign_key_indexes') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('20260815200619', 'align_donation_flow') on conflict (version) do nothing;
insert into supabase_migrations.schema_migrations (version, name) values ('20260815224447', 'harden_local_operations') on conflict (version) do nothing;
