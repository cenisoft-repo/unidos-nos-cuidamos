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
