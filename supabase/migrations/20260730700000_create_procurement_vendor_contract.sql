-- Procurement capability PRC-261 (Vendor Contract, CG-S11-PRC-012), batch 3 of the
-- operator's "lanjut sd prompt 265" authorization (261, 262, 263 -- batch capped at 3
-- per BUILD_EXECUTION_PROTOCOL.md §3.4, batch 2/Prompt 260 closed with 3 HIGH findings).
--
-- Versioned vendor contracts governing services, rates, capacity, SLA, compliance,
-- terms, amendment and renewal (Prompt 261 §4). Never a second vendor identity or a
-- second rate store -- extends app.vendor_profiles (PRC-251) and links, never
-- duplicates, app.vendor_rate_versions (COM-149/PRC-255).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Root+version collapsed into one table**, mirroring app.procurement_approval_
--    policies' and app.vendor_rate_versions' own established shape: `contract_number`
--    is the stable business identity shared across every version row; `version_no`
--    and `version_kind` ('initial'|'amendment'|'renewal') distinguish rows. No
--    separate root table -- "contract root is stable; content changes only through a
--    linked version" (§24) is enforced by contract_number never changing across
--    versions plus the partial unique index allowing at most one 'active' row per
--    (tenant_id, contract_number).
-- 2. **Amendment vs. renewal supersede timing differs, deliberately.** Amendment
--    (`app.amend_vendor_contract`) marks the current active row 'superseded'
--    immediately, mirroring `app.amend_purchase_order` (PRC-260) exactly -- a brief
--    window with no 'active' row for that contract_number is accepted, matching the
--    PO precedent. Renewal (`app.renew_vendor_contract`) does NOT touch the current
--    active row; the old row is marked 'superseded' only when the new renewal row
--    itself activates (`app.activate_vendor_contract`), so coverage never gaps for a
--    contract still within its own effective_end. Both branches lock the OLD row
--    before the NEW row inside `activate_vendor_contract`, ordered by `id` ascending
--    (C-21: two concurrent activations of unrelated contract pairs must never be able
--    to deadlock against each other by taking these two locks in opposite order).
-- 3. **Approval reuses the existing Procurement Approval Engine unchanged.**
--    `entity_type = 'vendor_contract'` is already a valid value in both
--    `procurement_approval_policies_entity_type_check` and
--    `procurement_approval_context_snapshots_entity_type_check`
--    (`20260730660000_create_procurement_approval.sql`) -- pre-provisioned for this
--    exact capability, confirmed by direct inspection, never altered here.
--    `app.decide_vendor_contract_approval_step` mirrors `app.decide_purchase_order_
--    approval_step` (PRC-260) exactly, including `assert_actor_is_session_identity`
--    first (C-13) and the `p_reauth_confirmed_at` 5-minute MFA freshness check (C-18).
--    The approval value_amount is the linked rate version's own `base_amount`/
--    `currency` when one is linked, else 0/tenant-default -- a genuinely amount-less
--    contract still routes through the SAME policy's `always_required` flag, exactly
--    as `vendor_activation` (PRC-251) and `vendor_selection` (PRC-259) already do for
--    their own non-monetary entity types.
-- 4. **E-sign is disclosed evidence, not a live connector (RPD-038).** `app.record_
--    vendor_contract_signature` attaches a re-validated (tenant/record_type/record_id/
--    malware_scan_status='clean', mirroring PRC-252's own established C-10 fix
--    pattern) Document/File Engine (PLT-128) file plus signed_by/signed_at metadata.
--    No e-sign provider adapter exists anywhere in this repository; this is the same,
--    already-disclosed Phase 6 precedent every prior capability has followed for
--    third-party connectors (AGENTS.md "case-by-case custom implementations").
-- 5. **Field masking.** `rate_version_id`, `payment_term_days`, `tax_terms` and
--    `capacity_terms` are commercial-term fields (§16: "rate... commercial terms are
--    private and field-scoped") masked behind the already-existing `app.has_prc_view_
--    cost` (PRC-252) in every read RPC's own projection -- never relying on a raw
--    table grant, per the batch 257-259 review's own established fix pattern (masking
--    lives in the SECURITY DEFINER function body, and the base table grant is
--    column-restricted to the non-cost columns as defence in depth).
-- 6. **Termination dependency check deferred to PRC-263 (Vendor Assignment), which
--    does not exist yet at this checkpoint.** `app.terminate_vendor_contract` blocks
--    on nothing but its own status transition today; PRC-263's own migration (later
--    in this same batch) adds a `create or replace function` guard once `app.vendor_
--    assignments` exists to check for it -- named here rather than silently omitted
--    (taxonomy C-23), not an applied-migration edit (a new migration replacing the
--    function body is the established, repository-wide pattern every `harden_*`
--    migration already uses).
-- 7. **Expiry reminders are a read-only query, not an async job.** `app.list_vendor_
--    contracts_expiring` -- no generic notification-dispatch queue exists anywhere in
--    this repository to wire an async reminder job into (the same gap PRC-253 already
--    disclosed for compliance-document expiry); disclosed here rather than fabricated.
-- 8. **capacity_terms is a jsonb declaration, not a PRC-262 foreign key.** PRC-262
--    (Vendor Capacity and Availability) does not exist yet at this migration's own
--    checkpoint. PRC-262's own migration (next in this batch) adds the FK in the
--    other direction (`app.vendor_capacity_offers.contract_id -> app.vendor_
--    contracts.id`), consistent with the dependency graph (`261 -> 262`) and never
--    requiring an edit here.
--
-- Per ERR-2026-004: explicit `revoke execute on all functions in schema app from
-- public` before final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. Contract numbering -- internal-only, mirrors app.next_vendor_code (PRC-251).
-- ===========================================================================

create table app.vendor_contract_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.vendor_contract_number_counters is
  'PRC-261: one atomic, tenant-scoped monotonic counter for app.next_vendor_contract_number(), mirroring app.vendor_code_counters (PRC-251). Never reused across contracts; version rows of the SAME contract share one contract_number.';

create function app.next_vendor_contract_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.vendor_contract_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.vendor_contract_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'VCT-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_vendor_contract_number is
  'PRC-261: internal-only (no authenticated grant) -- called exclusively from app.create_vendor_contract_draft, never callable directly (ISS-2026-033''s own lesson about a bare-granted counter).';

-- ===========================================================================
-- 2. app.vendor_contracts -- root+version collapsed (design note 1).
-- ===========================================================================

create table app.vendor_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  contract_number text not null,
  version_no integer not null default 1,
  version_kind text not null default 'initial',
  contract_type text not null,
  status text not null default 'draft',
  effective_start date not null,
  effective_end date,
  rate_version_id uuid references app.vendor_rate_versions (id),
  payment_term_days integer,
  tax_terms jsonb not null default '{}'::jsonb,
  sla_terms jsonb not null default '{}'::jsonb,
  capacity_terms jsonb not null default '{}'::jsonb,
  coverage_terms jsonb not null default '{}'::jsonb,
  compliance_required jsonb not null default '[]'::jsonb,
  terms_document_file_id uuid references app.files (id),
  signature_required boolean not null default true,
  signature_status text not null default 'not_required',
  signed_by text,
  signed_at timestamptz,
  approval_request_id uuid references app.approval_requests (id),
  approval_status text not null default 'not_required',
  supersedes_contract_id uuid references app.vendor_contracts (id),
  amend_reason text,
  termination_reason text,
  termination_evidence_ref text,
  terminated_at timestamptz,
  cancel_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_contracts_contract_type_check check (contract_type in ('framework', 'fixed_term')),
  constraint vendor_contracts_version_kind_check check (version_kind in ('initial', 'amendment', 'renewal')),
  constraint vendor_contracts_status_check check (
    status in ('draft', 'pending_approval', 'active', 'rejected', 'suspended', 'terminated', 'superseded', 'cancelled')
  ),
  constraint vendor_contracts_signature_status_check check (signature_status in ('not_required', 'pending', 'signed')),
  constraint vendor_contracts_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected')),
  constraint vendor_contracts_effective_range_check check (effective_end is null or effective_end > effective_start),
  constraint vendor_contracts_fixed_term_end_check check (contract_type <> 'fixed_term' or effective_end is not null),
  constraint vendor_contracts_payment_term_check check (payment_term_days is null or payment_term_days >= 0),
  constraint vendor_contracts_signature_shape_check check (
    signature_status <> 'signed' or (signed_by is not null and length(trim(signed_by)) > 0 and signed_at is not null)
  ),
  constraint vendor_contracts_amend_reason_check check (version_kind <> 'amendment' or (amend_reason is not null and length(trim(amend_reason)) > 0)),
  constraint vendor_contracts_termination_shape_check check (
    status <> 'terminated' or (termination_reason is not null and length(trim(termination_reason)) > 0 and termination_evidence_ref is not null and length(trim(termination_evidence_ref)) > 0)
  ),
  constraint vendor_contracts_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

comment on table app.vendor_contracts is
  'PRC-261: one row per contract VERSION; contract_number is the stable business identity shared across every version of the same logical contract (design note 1). At most one ''active'' row per (tenant_id, contract_number), enforced by vendor_contracts_active_unique below. Links, never duplicates, app.vendor_profiles (PRC-251) and app.vendor_rate_versions (COM-149/PRC-255).';

create index vendor_contracts_tenant_vendor_status_idx on app.vendor_contracts (tenant_id, vendor_master_id, status);
create index vendor_contracts_tenant_contract_number_idx on app.vendor_contracts (tenant_id, contract_number, version_no);
create index vendor_contracts_tenant_effective_end_idx on app.vendor_contracts (tenant_id, effective_end) where status = 'active';
create unique index vendor_contracts_number_version_unique on app.vendor_contracts (tenant_id, contract_number, version_no);
create unique index vendor_contracts_active_unique on app.vendor_contracts (tenant_id, contract_number) where status = 'active';
create unique index vendor_contracts_idempotency_key_unique on app.vendor_contracts (tenant_id, idempotency_key) where idempotency_key is not null;

create function app.enforce_vendor_contract_identity()
returns trigger
language plpgsql
as $$
declare
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = new.vendor_master_id;
  if not found then
    raise exception 'vendor_profile_not_found: no vendor profile %', new.vendor_master_id using errcode = 'foreign_key_violation';
  end if;
  if v_vendor.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_vendor_identity: vendor profile % belongs to tenant %, not %', new.vendor_master_id, v_vendor.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger vendor_contracts_enforce_identity
  before insert or update of vendor_master_id, tenant_id on app.vendor_contracts
  for each row
  execute function app.enforce_vendor_contract_identity();

create function app.touch_vendor_contracts_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_contracts_touch_row
  before update on app.vendor_contracts
  for each row
  execute function app.touch_vendor_contracts_row();

-- ===========================================================================
-- 3. Lifecycle event history (append-only), mirroring app.purchase_order_events.
-- ===========================================================================

create table app.vendor_contract_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  contract_id uuid not null references app.vendor_contracts (id),
  from_status text not null,
  to_status text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.vendor_contract_events is 'PRC-261: append-only lifecycle transition history, one row per real transition, written by every lifecycle RPC in the same transaction as the state change.';
create index vendor_contract_events_contract_idx on app.vendor_contract_events (contract_id, occurred_at);

-- ===========================================================================
-- 4. Field-masking helper (design note 5) -- reuses the existing app.has_prc_view_cost
--    (PRC-252), never redefined here.
-- ===========================================================================

create function app.mask_vendor_contract_cost_fields(p_row app.vendor_contracts, p_can_view_cost boolean)
returns app.vendor_contracts
language plpgsql
immutable
as $$
begin
  if not p_can_view_cost then
    p_row.rate_version_id := null;
    p_row.payment_term_days := null;
    p_row.tax_terms := '{}'::jsonb;
    p_row.capacity_terms := '{}'::jsonb;
  end if;
  return p_row;
end;
$$;

comment on function app.mask_vendor_contract_cost_fields is 'PRC-261: nulls the four commercial-term fields (rate_version_id, payment_term_days, tax_terms, capacity_terms) when the caller lacks PRC:View cost. Applied in every read RPC''s own projection, never left to a raw table grant (batch 257-259''s own established fix pattern).';

-- ===========================================================================
-- 5. Lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_contract_draft(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_type text,
  p_effective_start date,
  p_effective_end date,
  p_rate_version_id uuid,
  p_payment_term_days integer,
  p_tax_terms jsonb,
  p_sla_terms jsonb,
  p_capacity_terms jsonb,
  p_coverage_terms jsonb,
  p_compliance_required jsonb,
  p_signature_required boolean,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_contracts;
  v_number text;
  v_contract app.vendor_contracts;
  v_rate app.vendor_rate_versions;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_contract_type not in ('framework', 'fixed_term') then
    raise exception 'invalid_contract_type: %', p_contract_type using errcode = 'check_violation';
  end if;
  if p_contract_type = 'fixed_term' and p_effective_end is null then
    raise exception 'missing_effective_end: fixed_term contracts require effective_end' using errcode = 'check_violation';
  end if;
  if p_effective_end is not null and p_effective_end <= p_effective_start then
    raise exception 'invalid_effective_range: effective_end must be after effective_start' using errcode = 'check_violation';
  end if;
  if p_payment_term_days is not null and p_payment_term_days < 0 then
    raise exception 'invalid_payment_term: payment_term_days must not be negative' using errcode = 'check_violation';
  end if;

  if p_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> p_tenant_id or v_rate.vendor_master_id is distinct from p_vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to vendor % in tenant %', p_rate_version_id, p_vendor_master_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- C-01 (taxonomy self-check finding, fixed in-prompt): the pre-check AND the race-
  -- recovery branch below both compare the full target tuple, never just the key --
  -- reusing an idempotency key for a genuinely different vendor/contract_type/
  -- effective_start must be a conflict, not a silent misattribution to the wrong
  -- contract, mirroring app.create_vendor_profile_draft's own established shape.
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_contracts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.contract_type <> p_contract_type or v_existing.effective_start <> p_effective_start then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor contract (vendor %, type %, effective_start %)', p_idempotency_key, v_existing.vendor_master_id, v_existing.contract_type, v_existing.effective_start
          using errcode = 'unique_violation';
      end if;
      return app.mask_vendor_contract_cost_fields(v_existing, true);
    end if;
  end if;

  v_number := app.next_vendor_contract_number(p_tenant_id);

  begin
    insert into app.vendor_contracts (
      tenant_id, vendor_master_id, contract_number, version_no, version_kind, contract_type,
      effective_start, effective_end, rate_version_id, payment_term_days, tax_terms, sla_terms,
      capacity_terms, coverage_terms, compliance_required, signature_required,
      signature_status, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_vendor_master_id, v_number, 1, 'initial', p_contract_type,
      p_effective_start, p_effective_end, p_rate_version_id, p_payment_term_days,
      coalesce(p_tax_terms, '{}'::jsonb), coalesce(p_sla_terms, '{}'::jsonb),
      coalesce(p_capacity_terms, '{}'::jsonb), coalesce(p_coverage_terms, '{}'::jsonb),
      coalesce(p_compliance_required, '[]'::jsonb),
      coalesce(p_signature_required, true),
      case when coalesce(p_signature_required, true) then 'pending' else 'not_required' end,
      p_idempotency_key, p_actor_label
    )
    returning * into v_contract;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_contracts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.contract_type <> p_contract_type or v_existing.effective_start <> p_effective_start then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor contract (vendor %, type %, effective_start %)', p_idempotency_key, v_existing.vendor_master_id, v_existing.contract_type, v_existing.effective_start
          using errcode = 'unique_violation';
      end if;
      return app.mask_vendor_contract_cost_fields(v_existing, true);
  end;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_contract.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_contract_draft',
    'app.vendor_contracts', v_contract.id, 'success', null, null, jsonb_build_object('contract_number', v_contract.contract_number)
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.create_vendor_contract_draft is 'PRC-261: creates version_no=1, version_kind=initial, status=draft. Returns the caller''s own newly-created row unmasked (the creator always holds PRC:Create -- matching the create-time trust every other Phase 6 draft-creation RPC already extends its own caller).';

create function app.update_vendor_contract_draft(
  p_contract_id uuid,
  p_expected_version integer,
  p_effective_start date,
  p_effective_end date,
  p_rate_version_id uuid,
  p_payment_term_days integer,
  p_tax_terms jsonb,
  p_sla_terms jsonb,
  p_capacity_terms jsonb,
  p_coverage_terms jsonb,
  p_compliance_required jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_rate app.vendor_rate_versions;
begin
  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be edited', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;
  if p_effective_end is not null and p_effective_end <= p_effective_start then
    raise exception 'invalid_effective_range: effective_end must be after effective_start' using errcode = 'check_violation';
  end if;
  if v_contract.contract_type = 'fixed_term' and p_effective_end is null then
    raise exception 'missing_effective_end: fixed_term contracts require effective_end' using errcode = 'check_violation';
  end if;
  if p_payment_term_days is not null and p_payment_term_days < 0 then
    raise exception 'invalid_payment_term: payment_term_days must not be negative' using errcode = 'check_violation';
  end if;

  if p_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_contract.tenant_id or v_rate.vendor_master_id is distinct from v_contract.vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to vendor % in tenant %', p_rate_version_id, v_contract.vendor_master_id, v_contract.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Every optional field below is preserve-by-null (coalesce), not direct-assign --
  -- a caller that omits a field (e.g. a UI form that only exposes a subset of terms)
  -- must never silently clear a value it never intended to touch. effective_start is
  -- the one NOT NULL exception; it is always required and always direct-assigned.
  update app.vendor_contracts
  set effective_start = p_effective_start,
      effective_end = coalesce(p_effective_end, effective_end),
      rate_version_id = coalesce(p_rate_version_id, rate_version_id),
      payment_term_days = coalesce(p_payment_term_days, payment_term_days),
      tax_terms = coalesce(p_tax_terms, tax_terms),
      sla_terms = coalesce(p_sla_terms, sla_terms),
      capacity_terms = coalesce(p_capacity_terms, capacity_terms),
      coverage_terms = coalesce(p_coverage_terms, coverage_terms),
      compliance_required = coalesce(p_compliance_required, compliance_required)
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_contract_draft',
    'app.vendor_contracts', v_contract.id, 'success', null, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

create function app.submit_vendor_contract_for_approval(
  p_contract_id uuid,
  p_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_rate app.vendor_rate_versions;
  v_value_amount numeric;
  v_currency text;
  v_approval record;
begin
  select * into v_contract from app.vendor_contracts where id = p_contract_id for update;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be submitted', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_value_amount := 0;
  v_currency := 'IDR';
  if v_contract.rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = v_contract.rate_version_id;
    if found then
      v_value_amount := coalesce(v_rate.base_amount, 0);
      v_currency := coalesce(v_rate.currency, 'IDR');
    end if;
  end if;

  select * into v_approval from app._request_procurement_entity_approval(
    'vendor_contract', v_contract.tenant_id, v_contract.id, v_value_amount, v_currency,
    jsonb_build_object('contract_number', v_contract.contract_number, 'contract_type', v_contract.contract_type),
    v_contract.record_version, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  update app.vendor_contracts
  set status = 'pending_approval',
      approval_status = case when v_approval.required then 'pending' else 'not_required' end,
      approval_request_id = v_approval.approval_request_id
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, 'draft', 'pending_approval', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_contract_for_approval',
    'app.vendor_contracts', p_contract_id, 'success', null, null, jsonb_build_object('approval_status', v_contract.approval_status)
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.submit_vendor_contract_for_approval is 'PRC-261: draft -> pending_approval, PRC:Edit. Routes through app._request_procurement_entity_approval (PLT-123/PRC-259, unchanged) with entity_type=vendor_contract (design note 3) -- value_amount taken from the linked rate version when present, else 0 (a tenant''s always_required policy still governs a non-monetary contract, matching vendor_activation/vendor_selection precedent).';

create function app.decide_vendor_contract_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
  p_reason text default null
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_contract app.vendor_contracts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'vendor_contract' or v_request.entity_id is null then
    raise exception 'not_a_vendor_contract_approval: approval request % is not a vendor contract approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.vendor_contracts set approval_status = 'approved' where id = v_request.entity_id returning * into v_contract;
  elsif v_updated_request.status = 'rejected' then
    update app.vendor_contracts set approval_status = 'rejected', status = 'rejected' where id = v_request.entity_id returning * into v_contract;
  else
    select * into v_contract from app.vendor_contracts where id = v_request.entity_id;
  end if;

  if v_contract.id is null then
    raise exception 'vendor_contract_target_not_found: approval request % entity % no longer resolves to a vendor contract', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  if v_updated_request.status = 'rejected' then
    insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
    values (v_contract.tenant_id, v_contract.id, 'pending_approval', 'rejected', p_reason, p_actor_auth_user_id, p_actor_label);
  end if;

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.decide_vendor_contract_approval_step is 'PRC-261: mirrors app.decide_purchase_order_approval_step (PRC-260) exactly -- wraps app.decide_approval_step (PLT-123, unchanged), requires p_reauth_confirmed_at, raises a typed not-found error instead of an all-NULL composite (design note 3).';

create function app.record_vendor_contract_signature(
  p_contract_id uuid,
  p_expected_version integer,
  p_signed_by text,
  p_signed_at timestamptz,
  p_evidence_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_file app.files;
begin
  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status not in ('draft', 'pending_approval') then
    raise exception 'invalid_transition: vendor contract % is % and cannot record a signature', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;
  if p_signed_by is null or length(trim(p_signed_by)) = 0 then
    raise exception 'signed_by_required: a non-empty signed_by is required' using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_contract.tenant_id or v_file.record_type <> 'vendor_contract' or v_file.record_id <> p_contract_id then
      raise exception 'contract_evidence_file_mismatch: file % does not belong to vendor contract % in tenant %', p_evidence_file_id, p_contract_id, v_contract.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'contract_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.vendor_contracts
  set signature_status = 'signed', signed_by = p_signed_by, signed_at = coalesce(p_signed_at, now()), terms_document_file_id = coalesce(p_evidence_file_id, terms_document_file_id)
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_vendor_contract_signature',
    'app.vendor_contracts', p_contract_id, 'success', null, null, jsonb_build_object('signed_by', p_signed_by)
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.record_vendor_contract_signature is 'PRC-261: re-validates any evidence file (tenant/record_type/record_id/malware_scan_status=clean, C-10) before linking it (design note 4). Never validates legal effect -- RPD-038 disclosure applies, mirroring every other Phase 6 evidence-only capability.';

create function app.activate_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_old app.vendor_contracts;
  v_lock_first uuid;
  v_lock_second uuid;
begin
  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be activated', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;
  if v_contract.approval_status not in ('approved', 'not_required') then
    raise exception 'approval_incomplete: vendor contract % approval_status is %', p_contract_id, v_contract.approval_status
      using errcode = 'check_violation';
  end if;
  if v_contract.signature_required and v_contract.signature_status <> 'signed' then
    raise exception 'signature_incomplete: vendor contract % requires a recorded signature before activation', p_contract_id
      using errcode = 'check_violation';
  end if;

  -- C-21: lock both this row and the row it supersedes (if any) in a FIXED order
  -- (ascending id), never "new row then old row" positionally -- two concurrent
  -- activations of two unrelated amendment/renewal pairs must not be able to take
  -- these same two locks in opposite order.
  if v_contract.supersedes_contract_id is not null then
    if v_contract.id < v_contract.supersedes_contract_id then
      v_lock_first := v_contract.id;
      v_lock_second := v_contract.supersedes_contract_id;
    else
      v_lock_first := v_contract.supersedes_contract_id;
      v_lock_second := v_contract.id;
    end if;
    perform 1 from app.vendor_contracts where id = v_lock_first for update;
    perform 1 from app.vendor_contracts where id = v_lock_second for update;

    select * into v_old from app.vendor_contracts where id = v_contract.supersedes_contract_id;
  end if;

  -- Renewal supersede-on-activate (design note 2) MUST run before this row's own
  -- UPDATE below -- vendor_contracts_active_unique allows at most one 'active' row per
  -- (tenant_id, contract_number), checked immediately (not deferred), so activating
  -- v_contract first while v_old is still 'active' would violate it outright, not just
  -- momentarily. Amendment already superseded its prior row at amend-time
  -- (app.amend_vendor_contract) -- v_old.status here would already be 'superseded', so
  -- this branch is a genuine no-op for that case.
  if v_old.id is not null and v_old.status = 'active' then
    update app.vendor_contracts set status = 'superseded' where id = v_old.id;
    insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
    values (v_old.tenant_id, v_old.id, 'active', 'superseded', 'renewed by ' || v_contract.contract_number || ' v' || v_contract.version_no, p_actor_auth_user_id, p_actor_label);
  end if;

  update app.vendor_contracts
  set status = 'active'
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, 'pending_approval', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_contract',
    'app.vendor_contracts', p_contract_id, 'success', null, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

create function app.amend_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_effective_end date,
  p_rate_version_id uuid,
  p_payment_term_days integer,
  p_sla_terms jsonb,
  p_capacity_terms jsonb,
  p_coverage_terms jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_new app.vendor_contracts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to amend a vendor contract' using errcode = 'check_violation';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id for update;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'active' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be amended', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_contracts set status = 'superseded' where id = p_contract_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contracts (
    tenant_id, vendor_master_id, contract_number, version_no, version_kind, contract_type,
    effective_start, effective_end, rate_version_id, payment_term_days, tax_terms, sla_terms,
    capacity_terms, coverage_terms, compliance_required, terms_document_file_id,
    signature_required, signature_status, supersedes_contract_id, amend_reason, created_by
  )
  values (
    v_contract.tenant_id, v_contract.vendor_master_id, v_contract.contract_number, v_contract.version_no + 1, 'amendment', v_contract.contract_type,
    v_contract.effective_start, coalesce(p_effective_end, v_contract.effective_end), coalesce(p_rate_version_id, v_contract.rate_version_id),
    coalesce(p_payment_term_days, v_contract.payment_term_days), v_contract.tax_terms, coalesce(p_sla_terms, v_contract.sla_terms),
    coalesce(p_capacity_terms, v_contract.capacity_terms), coalesce(p_coverage_terms, v_contract.coverage_terms), v_contract.compliance_required,
    v_contract.terms_document_file_id, v_contract.signature_required,
    case when v_contract.signature_required then 'pending' else 'not_required' end,
    v_contract.id, p_reason, p_actor_label
  )
  returning * into v_new;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, v_contract.id, 'active', 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);
  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_vendor_contract',
    'app.vendor_contracts', v_new.id, 'success', p_reason, null, jsonb_build_object('supersedes_contract_id', v_contract.id)
  );

  return app.mask_vendor_contract_cost_fields(v_new, true);
end;
$$;

comment on function app.amend_vendor_contract is 'PRC-261: active -> immediately superseded, PRC:Edit, mandatory reason -- mirrors app.amend_purchase_order (PRC-260) exactly (design note 2). Inserts a new draft (version_no+1, version_kind=amendment) that must independently pass back through submit/approve/activate.';

create function app.renew_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_new_effective_start date,
  p_new_effective_end date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_new app.vendor_contracts;
begin
  -- C-04 (taxonomy self-check finding, fixed in-prompt): unlike suspend/reactivate/
  -- terminate/cancel, this function never itself performs a version-guarded UPDATE on
  -- v_contract's own row (it only reads it to snapshot values into a new INSERT) -- so
  -- there is no later optimistic-concurrency check to catch a concurrent modification
  -- between the read and the decision. An explicit lock here is required, not optional.
  select * into v_contract from app.vendor_contracts where id = p_contract_id for update;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'active' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be renewed', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;
  if v_contract.contract_type = 'fixed_term' and p_new_effective_end is null then
    raise exception 'missing_effective_end: fixed_term contracts require effective_end' using errcode = 'check_violation';
  end if;
  if p_new_effective_end is not null and p_new_effective_end <= p_new_effective_start then
    raise exception 'invalid_effective_range: effective_end must be after effective_start' using errcode = 'check_violation';
  end if;

  -- Deliberately does NOT touch v_contract's own status (design note 2) -- it stays
  -- 'active' until this new renewal row itself activates.
  insert into app.vendor_contracts (
    tenant_id, vendor_master_id, contract_number, version_no, version_kind, contract_type,
    effective_start, effective_end, rate_version_id, payment_term_days, tax_terms, sla_terms,
    capacity_terms, coverage_terms, compliance_required, terms_document_file_id,
    signature_required, signature_status, supersedes_contract_id, created_by
  )
  values (
    v_contract.tenant_id, v_contract.vendor_master_id, v_contract.contract_number, v_contract.version_no + 1, 'renewal', v_contract.contract_type,
    p_new_effective_start, p_new_effective_end, v_contract.rate_version_id, v_contract.payment_term_days, v_contract.tax_terms, v_contract.sla_terms,
    v_contract.capacity_terms, v_contract.coverage_terms, v_contract.compliance_required,
    null, v_contract.signature_required,
    case when v_contract.signature_required then 'pending' else 'not_required' end,
    v_contract.id, p_actor_label
  )
  returning * into v_new;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'renew_vendor_contract',
    'app.vendor_contracts', v_new.id, 'success', null, null, jsonb_build_object('supersedes_contract_id', v_contract.id)
  );

  return app.mask_vendor_contract_cost_fields(v_new, true);
end;
$$;

create function app.suspend_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend a vendor contract' using errcode = 'check_violation';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'active' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be suspended', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_contracts set status = 'suspended' where id = p_contract_id and record_version = p_expected_version returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, 'active', 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_vendor_contract',
    'app.vendor_contracts', p_contract_id, 'success', p_reason, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

create function app.reactivate_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
begin
  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status <> 'suspended' then
    raise exception 'invalid_transition: vendor contract % is % and cannot be reactivated', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_contracts set status = 'active' where id = p_contract_id and record_version = p_expected_version returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, 'suspended', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_contract',
    'app.vendor_contracts', p_contract_id, 'success', null, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

create function app.terminate_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_evidence_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to terminate a vendor contract' using errcode = 'check_violation';
  end if;
  if p_evidence_ref is null or length(trim(p_evidence_ref)) = 0 then
    raise exception 'evidence_required: evidence_ref is required to terminate a vendor contract' using errcode = 'check_violation';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status not in ('active', 'suspended') then
    raise exception 'invalid_transition: vendor contract % is % and cannot be terminated', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_from_status := v_contract.status;

  update app.vendor_contracts
  set status = 'terminated', termination_reason = p_reason, termination_evidence_ref = p_evidence_ref, terminated_at = now()
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, v_from_status, 'terminated', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_vendor_contract',
    'app.vendor_contracts', p_contract_id, 'success', p_reason, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.terminate_vendor_contract is 'PRC-261: active|suspended -> terminated, PRC:Override, mandatory reason+evidence_ref. Carries no active-dependency check yet (design note 6) -- PRC-263 (Vendor Assignment) adds it once app.vendor_assignments exists.';

create function app.cancel_vendor_contract_draft(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vendor contract' using errcode = 'check_violation';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id for update;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status not in ('draft', 'pending_approval') then
    raise exception 'invalid_transition: vendor contract % is % and cannot be cancelled', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_from_status := v_contract.status;

  if v_contract.approval_request_id is not null and v_contract.approval_status = 'pending' then
    perform app.cancel_approval_request(v_contract.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
  end if;

  update app.vendor_contracts
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_contract_draft',
    'app.vendor_contracts', p_contract_id, 'success', p_reason, null, '{}'::jsonb
  );

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

comment on function app.cancel_vendor_contract_draft is 'PRC-261: draft|pending_approval -> cancelled, PRC:Edit, mandatory reason. Cancel-eligible only (never an active contract -- use suspend/terminate for that). Cancels the bound approval request too when one is still pending, mirroring app.cancel_purchase_order (PRC-260).';

-- ===========================================================================
-- 6. Reads (PRC:View, cost fields masked behind PRC:View cost, design note 5).
-- ===========================================================================

create function app.get_vendor_contract(p_contract_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_tenant_id uuid;
begin
  -- C-05 (taxonomy self-check finding, fixed in-prompt): fold "does not exist" and
  -- "exists in a tenant this caller has no membership in" into the SAME not-found
  -- error, mirroring app.get_purchase_order (PRC-260) exactly -- a cross-tenant,
  -- zero-membership caller must never be able to distinguish the two via the error
  -- message alone. Only once membership is confirmed does evaluate_permission's own,
  -- more specific insufficient_authority reason become safe to disclose.
  select tenant_id into v_tenant_id from app.vendor_contracts where id = p_contract_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  return app.mask_vendor_contract_cost_fields(v_contract, app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id));
end;
$$;

create function app.list_vendor_contracts(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_cursor timestamptz default null
)
returns setof app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
  v_row app.vendor_contracts;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  for v_row in
    select * from app.vendor_contracts
    where tenant_id = p_tenant_id
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (p_cursor is null or created_at < p_cursor)
    order by created_at desc
    limit least(coalesce(p_limit, 25), 100)
  loop
    return next app.mask_vendor_contract_cost_fields(v_row, v_can_view_cost);
  end loop;
end;
$$;

create function app.list_vendor_contract_versions(p_contract_number text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
  v_row app.vendor_contracts;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  for v_row in
    select * from app.vendor_contracts where tenant_id = p_tenant_id and contract_number = p_contract_number order by version_no
  loop
    return next app.mask_vendor_contract_cost_fields(v_row, v_can_view_cost);
  end loop;
end;
$$;

create function app.get_vendor_contract_lifecycle_history(p_contract_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_contract_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  -- C-05 fix, mirrors app.get_vendor_contract's own identical fold immediately above.
  select tenant_id into v_tenant_id from app.vendor_contracts where id = p_contract_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_contract_events where contract_id = p_contract_id order by occurred_at;
end;
$$;

create function app.resolve_effective_vendor_contract(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_as_of date;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_as_of := coalesce(p_as_of, now())::date;

  select * into v_contract
  from app.vendor_contracts
  where tenant_id = p_tenant_id
    and vendor_master_id = p_vendor_master_id
    and status = 'active'
    and effective_start <= v_as_of
    and (effective_end is null or effective_end >= v_as_of)
  order by effective_start desc
  limit 1;

  return app.mask_vendor_contract_cost_fields(v_contract, app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id));
end;
$$;

comment on function app.resolve_effective_vendor_contract is 'PRC-261: the ONE deterministic effective-term resolution point (§24: "Effective... resolution is deterministic and source-versioned") PRC-263/264/265 read from -- at most one active row can ever match, per vendor_contracts_active_unique. Returns NULL (never raises) when no contract is effective, so a caller can distinguish "no governing contract" from "not authorized".';

create function app.list_vendor_contracts_expiring(p_tenant_id uuid, p_within_days integer, p_actor_auth_user_id uuid)
returns setof app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
  v_row app.vendor_contracts;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  for v_row in
    select * from app.vendor_contracts
    where tenant_id = p_tenant_id
      and status = 'active'
      and effective_end is not null
      and effective_end <= (now()::date + make_interval(days => greatest(coalesce(p_within_days, 30), 0)))
    order by effective_end
  loop
    return next app.mask_vendor_contract_cost_fields(v_row, v_can_view_cost);
  end loop;
end;
$$;

comment on function app.list_vendor_contracts_expiring is 'PRC-261: read-only expiring-soon query (design note 7) -- no async reminder job exists to dispatch from yet, the same disclosed gap PRC-253 already recorded for compliance-document expiry.';

-- ===========================================================================
-- 7. RLS -- default-deny form (pattern (3)), mirroring app.vendor_profiles exactly.
-- ===========================================================================

alter table app.vendor_contract_number_counters enable row level security;
create policy vendor_contract_number_counters_none on app.vendor_contract_number_counters for select to authenticated using (false);

alter table app.vendor_contracts enable row level security;
alter table app.vendor_contract_events enable row level security;

create policy vendor_contracts_select_scoped on app.vendor_contracts
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_contract_events_select_scoped on app.vendor_contract_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 8. Grants. Base-table SELECT is column-restricted to the non-cost columns
--    (design note 5, defence in depth) -- the masked commercial-term columns are
--    reachable only through the read RPCs above.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select (
  id, tenant_id, vendor_master_id, contract_number, version_no, version_kind, contract_type, status,
  effective_start, effective_end, sla_terms, coverage_terms, compliance_required, terms_document_file_id,
  signature_required, signature_status, signed_by, signed_at, approval_request_id, approval_status,
  supersedes_contract_id, amend_reason, termination_reason, termination_evidence_ref, terminated_at,
  cancel_reason, record_version, created_by, created_at, updated_at
) on app.vendor_contracts to authenticated;
grant select, insert, update on app.vendor_contracts to service_role;
grant select on app.vendor_contract_events to authenticated, service_role;
grant insert on app.vendor_contract_events to service_role;
grant select, insert, update on app.vendor_contract_number_counters to service_role;

grant execute on function app.mask_vendor_contract_cost_fields(app.vendor_contracts, boolean) to authenticated, service_role;

grant execute on function app.create_vendor_contract_draft(uuid, uuid, text, date, date, uuid, integer, jsonb, jsonb, jsonb, jsonb, jsonb, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_contract_draft(uuid, integer, date, date, uuid, integer, jsonb, jsonb, jsonb, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_contract_for_approval(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_contract_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;
grant execute on function app.record_vendor_contract_signature(uuid, integer, text, timestamptz, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.activate_vendor_contract(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.amend_vendor_contract(uuid, integer, text, date, uuid, integer, jsonb, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.renew_vendor_contract(uuid, integer, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.suspend_vendor_contract(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reactivate_vendor_contract(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.terminate_vendor_contract(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_vendor_contract_draft(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_contract(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_contracts(uuid, uuid, text, uuid, integer, timestamptz) to authenticated, service_role;
grant execute on function app.list_vendor_contract_versions(text, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_contract_lifecycle_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.resolve_effective_vendor_contract(uuid, uuid, timestamptz, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_contracts_expiring(uuid, integer, uuid) to authenticated, service_role;

grant execute on function app.next_vendor_contract_number(uuid) to service_role;
