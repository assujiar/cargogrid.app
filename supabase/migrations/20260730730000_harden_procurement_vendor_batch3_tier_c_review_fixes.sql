-- Batch 3 (261-263, CG-S11-PRC-012/013/014) Tier C review fix pass (ADR-0021,
-- BUILD_EXECUTION_PROTOCOL.md §5). Every fix below closes a finding CONFIRMED by
-- live reproduction (real disposable Postgres, forged/alternate-actor sessions, real
-- concurrent psql processes) against the batch's own combined diff by four parallel
-- adversarial lenses (spec-compliance, security/RLS/isolation, correctness/
-- concurrency, cross-prompt integration). See this batch's own fix commit message and
-- docs/build-log/phase-06/PRC-263.md's own batch-close section for the full four-lens
-- disposition (findings closed / disclosed-not-fixed / rejected as unconfirmed).
--
-- Applied-migration discipline (AGENTS.md, mirrors 20260730690000's own precedent for
-- batch 260): every fix here is CREATE OR REPLACE FUNCTION against the ORIGINAL,
-- already-committed 20260730700000/20260730710000/20260730720000 migrations -- never
-- an edit to those files themselves. Same signatures throughout except one explicit
-- DROP + CREATE (fix 7, a genuine OUT-parameter addition Postgres does not permit via
-- CREATE OR REPLACE) -- re-granted explicitly there; every other function keeps its
-- original grant untouched (CREATE OR REPLACE preserves ACLs when the signature is
-- unchanged).

-- ===========================================================================
-- 1. C-01 (correctness/concurrency lens, HIGH, live-reproduced): app.create_vendor_contract_draft's
--    idempotency pre-check AND race-recovery branch originally compared only vendor/
--    contract_type/effective_start -- a replay with a genuinely different effective_end/
--    rate_version_id/payment_term_days/terms silently returned the ORIGINAL row instead
--    of raising idempotency_key_conflict, discarding the caller's real second request.
--    Both branches now compare the FULL caller-supplied tuple. Same signature, CREATE OR
--    REPLACE only.
-- ===========================================================================

create or replace function app.create_vendor_contract_draft(
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

  -- C-01 (Tier C batch-3 fix: the original in-prompt self-check only compared
  -- vendor/type/effective_start, live-reproduced as reusable to silently discard a
  -- caller's real effective_end/rate_version_id/payment_term_days/terms on replay --
  -- the pre-check AND the race-recovery branch below both now compare the FULL
  -- caller-supplied tuple, against the SAME coalesce()-defaulted shape actually
  -- stored, never just a leading subset of fields.
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_contracts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id
         or v_existing.contract_type <> p_contract_type
         or v_existing.effective_start <> p_effective_start
         or v_existing.effective_end is distinct from p_effective_end
         or v_existing.rate_version_id is distinct from p_rate_version_id
         or v_existing.payment_term_days is distinct from p_payment_term_days
         or v_existing.tax_terms is distinct from coalesce(p_tax_terms, '{}'::jsonb)
         or v_existing.sla_terms is distinct from coalesce(p_sla_terms, '{}'::jsonb)
         or v_existing.capacity_terms is distinct from coalesce(p_capacity_terms, '{}'::jsonb)
         or v_existing.coverage_terms is distinct from coalesce(p_coverage_terms, '{}'::jsonb)
         or v_existing.compliance_required is distinct from coalesce(p_compliance_required, '[]'::jsonb)
         or v_existing.signature_required is distinct from coalesce(p_signature_required, true) then
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
      if v_existing.vendor_master_id is distinct from p_vendor_master_id
         or v_existing.contract_type <> p_contract_type
         or v_existing.effective_start <> p_effective_start
         or v_existing.effective_end is distinct from p_effective_end
         or v_existing.rate_version_id is distinct from p_rate_version_id
         or v_existing.payment_term_days is distinct from p_payment_term_days
         or v_existing.tax_terms is distinct from coalesce(p_tax_terms, '{}'::jsonb)
         or v_existing.sla_terms is distinct from coalesce(p_sla_terms, '{}'::jsonb)
         or v_existing.capacity_terms is distinct from coalesce(p_capacity_terms, '{}'::jsonb)
         or v_existing.coverage_terms is distinct from coalesce(p_coverage_terms, '{}'::jsonb)
         or v_existing.compliance_required is distinct from coalesce(p_compliance_required, '[]'::jsonb)
         or v_existing.signature_required is distinct from coalesce(p_signature_required, true) then
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

-- ===========================================================================
-- 2. C-04/C-21 (correctness/concurrency lens, HIGH, live-reproduced as a REAL deadlock in ~50%
--    of a concurrent-race trial): app.decide_vendor_contract_approval_step wrote app.
--    vendor_contracts with NO lock and NO version guard, AFTER calling into the approval
--    engine (which locks app.approval_requests/app.approval_request_steps) -- the exact
--    inverse of app.cancel_vendor_contract_draft's own lock order (vendor_contracts,
--    then approval_requests). Fixed by locking the target contract row FIRST, before
--    calling into the approval engine, matching app.cancel_vendor_contract_draft's own
--    order exactly -- closes the cycle, live-reproduced deadlock-free across both
--    possible race orderings after the fix. Also fixes a second latent bug this same
--    reorder exposed: the approval step could previously be decided (consumed) even when
--    its entity_id no longer resolved to a real contract row -- now checked, and
--    rejected, first. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.decide_vendor_contract_approval_step(
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

  -- C-04/C-21 (Tier C batch-3 fix, live-reproduced real deadlocks in ~50% of a
  -- concurrent-race trial): lock the target contract row FIRST, before calling into
  -- app.decide_approval_step (which locks approval_requests/approval_request_steps)
  -- -- matching app.cancel_vendor_contract_draft's own lock order (vendor_contracts,
  -- then approval_requests) exactly, so no two functions in this migration ever take
  -- these two tables' locks in opposite order. This also fixes a second latent bug:
  -- the approval step could previously be decided (consumed) even when its entity_id
  -- no longer resolved to a real contract row -- now checked, and rejected, first.
  select * into v_contract from app.vendor_contracts where id = v_request.entity_id for update;
  if not found then
    raise exception 'vendor_contract_target_not_found: approval request % entity % no longer resolves to a vendor contract', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.vendor_contracts set approval_status = 'approved' where id = v_contract.id returning * into v_contract;
  elsif v_updated_request.status = 'rejected' then
    update app.vendor_contracts set approval_status = 'rejected', status = 'rejected' where id = v_contract.id returning * into v_contract;
  end if;

  if v_updated_request.status = 'rejected' then
    insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
    values (v_contract.tenant_id, v_contract.id, 'pending_approval', 'rejected', p_reason, p_actor_auth_user_id, p_actor_label);
  end if;

  return app.mask_vendor_contract_cost_fields(v_contract, true);
end;
$$;

-- ===========================================================================
-- 3. C-05 (security/RLS lens, MEDIUM, live-reproduced): every lifecycle WRITE RPC in
--    20260730700000 resolved the target row's real tenant_id BEFORE checking whether the
--    calling identity may access that tenant at all, then echoed that real tenant_id
--    verbatim into the resulting insufficient_authority error text -- letting any
--    authenticated user of ANY tenant, given an arbitrary contract UUID, learn (a)
--    whether it is a real row and (b) the exact real tenant_id that owns it, with zero
--    membership in that tenant. This is the SAME oracle already registered repository-
--    wide as ISS-2026-048 (batch 260's own fix for CG-S11-PRC-011's 6 write RPCs) --
--    this batch reintroduced it in 10 new functions, since each prompt's own per-prompt
--    Tier B self-check only checked the read-RPC fold, never the write-RPC shape. Fixed
--    by folding app.has_active_tenant_membership into the SAME not-found branch, exactly
--    the pattern every read RPC in this same file already uses. Affects: update_vendor_
--    contract_draft, submit_vendor_contract_for_approval, record_vendor_contract_
--    signature, activate_vendor_contract, amend_vendor_contract, renew_vendor_contract,
--    suspend_vendor_contract, reactivate_vendor_contract, terminate_vendor_contract,
--    cancel_vendor_contract_draft. Same signatures throughout, CREATE OR REPLACE only --
--    no re-GRANT needed.
-- ===========================================================================

create or replace function app.update_vendor_contract_draft(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.submit_vendor_contract_for_approval(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.record_vendor_contract_signature(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.activate_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.amend_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.renew_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.suspend_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.reactivate_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.terminate_vendor_contract(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.cancel_vendor_contract_draft(
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold already used in every read RPC
  -- in this same file (e.g. app.get_vendor_contract).
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

-- ===========================================================================
-- 4. C-01 (correctness/concurrency lens, HIGH, live-reproduced): app.create_vendor_capacity_
--    offer_draft's idempotency pre-check AND race-recovery branch originally compared
--    only vendor/service_type/quantity/window_start -- a replay with a genuinely
--    different window_end (or mode/lane/resource_type/resource_master_id/contract_id)
--    silently returned the ORIGINAL row. Both branches now compare the FULL
--    caller-supplied tuple. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.create_vendor_capacity_offer_draft(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_resource_type text,
  p_resource_master_id uuid,
  p_quantity numeric,
  p_uom text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_capacity_offers;
  v_offer app.vendor_capacity_offers;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  -- C-01 (Tier C batch-3 fix): the original pre-check/recovery comparison only
  -- covered vendor/service_type/quantity/window_start -- live-reproduced as reusable
  -- to silently discard a caller's real window_end (and every other field) on
  -- replay. Both branches now compare the FULL caller-supplied tuple, against the
  -- SAME coalesce()-defaulted shape actually stored.
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_capacity_offers where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id
         or v_existing.contract_id is distinct from p_contract_id
         or v_existing.service_type <> p_service_type
         or v_existing.mode is distinct from p_mode
         or v_existing.origin_lane is distinct from p_origin_lane
         or v_existing.destination_lane is distinct from p_destination_lane
         or v_existing.resource_type <> coalesce(p_resource_type, 'general')
         or v_existing.resource_master_id is distinct from p_resource_master_id
         or v_existing.quantity <> p_quantity
         or v_existing.uom <> p_uom
         or v_existing.window_start <> p_window_start
         or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor capacity offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_capacity_offers (
      tenant_id, vendor_master_id, contract_id, service_type, mode, origin_lane, destination_lane,
      resource_type, resource_master_id, quantity, uom, window_start, window_end, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_vendor_master_id, p_contract_id, p_service_type, p_mode, p_origin_lane, p_destination_lane,
      coalesce(p_resource_type, 'general'), p_resource_master_id, p_quantity, p_uom, p_window_start, p_window_end, p_idempotency_key, p_actor_label
    )
    returning * into v_offer;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_capacity_offers where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_id is distinct from p_vendor_master_id
         or v_existing.contract_id is distinct from p_contract_id
         or v_existing.service_type <> p_service_type
         or v_existing.mode is distinct from p_mode
         or v_existing.origin_lane is distinct from p_origin_lane
         or v_existing.destination_lane is distinct from p_destination_lane
         or v_existing.resource_type <> coalesce(p_resource_type, 'general')
         or v_existing.resource_master_id is distinct from p_resource_master_id
         or v_existing.quantity <> p_quantity
         or v_existing.uom <> p_uom
         or v_existing.window_start <> p_window_start
         or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor capacity offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_capacity_offer_draft',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, jsonb_build_object('service_type', v_offer.service_type, 'quantity', v_offer.quantity)
  );

  return v_offer;
end;
$$;

-- ===========================================================================
-- 5. C-05 (security/RLS lens, MEDIUM, live-reproduced): the SAME tenant-id-disclosure
--    oracle as fix 3 above (ISS-2026-048's own shape), independently reintroduced in 8
--    more write RPCs in 20260730710000. Same fix: fold app.has_active_tenant_membership
--    into the not-found branch. Affects: update_vendor_capacity_offer_draft, archive_
--    vendor_capacity_offer, add_vendor_capacity_blackout, remove_vendor_capacity_
--    blackout, accept_vendor_capacity_reservation, decline_vendor_capacity_reservation,
--    release_vendor_capacity_reservation, consume_vendor_capacity_reservation (publish_
--    vendor_capacity_offer and reserve_vendor_capacity get the SAME C-05 fold too, folded
--    into fix 6 below since both also gain a real C-15 behavioral change in the same
--    pass). Same signatures throughout, CREATE OR REPLACE only -- no re-GRANT needed.
-- ===========================================================================

create or replace function app.update_vendor_capacity_offer_draft(
  p_offer_id uuid,
  p_expected_version integer,
  p_contract_id uuid,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_resource_master_id uuid,
  p_quantity numeric,
  p_uom text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.compute_vendor_capacity_available).
  if not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be edited', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  -- contract_id/mode/origin_lane/destination_lane/resource_master_id are truly
  -- optional -- preserve-by-null (coalesce). quantity/uom/window are always-required
  -- direct assignment (PRC-261's own Tier B lesson: never conflate the two shapes).
  update app.vendor_capacity_offers
  set contract_id = coalesce(p_contract_id, contract_id),
      mode = coalesce(p_mode, mode),
      origin_lane = coalesce(p_origin_lane, origin_lane),
      destination_lane = coalesce(p_destination_lane, destination_lane),
      resource_master_id = coalesce(p_resource_master_id, resource_master_id),
      quantity = p_quantity,
      uom = p_uom,
      window_start = p_window_start,
      window_end = p_window_end
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_capacity_offer_draft',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

create or replace function app.archive_vendor_capacity_offer(
  p_offer_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_active_count integer;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.compute_vendor_capacity_available).
  if not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status not in ('draft', 'published') then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be archived', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_active_count from app.vendor_capacity_reservations where offer_id = p_offer_id and status in ('held', 'accepted');
  if v_active_count > 0 then
    raise exception 'active_reservations_exist: vendor capacity offer % has % active reservation(s) -- decline or release them first', p_offer_id, v_active_count
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_offers set status = 'archived' where id = p_offer_id and record_version = p_expected_version returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_capacity_offer',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

create or replace function app.add_vendor_capacity_blackout(
  p_offer_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_blackouts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_blackout app.vendor_capacity_blackouts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to add a blackout' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.compute_vendor_capacity_available).
  if not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.vendor_capacity_blackouts (tenant_id, offer_id, window_start, window_end, reason, created_by)
  values (v_offer.tenant_id, p_offer_id, p_window_start, p_window_end, p_reason, p_actor_label)
  returning * into v_blackout;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_capacity_blackout',
    'app.vendor_capacity_blackouts', v_blackout.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_blackout;
end;
$$;

create or replace function app.remove_vendor_capacity_blackout(
  p_blackout_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_blackout app.vendor_capacity_blackouts;
begin
  select * into v_blackout from app.vendor_capacity_blackouts where id = p_blackout_id;
  if not found then
    raise exception 'vendor_capacity_blackout_not_found: %', p_blackout_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- the offer-scoped functions above.
  if not app.has_active_tenant_membership(v_blackout.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_blackout_not_found: %', p_blackout_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_blackout.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_blackout.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_blackout.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity blackout % expected version % but found %', p_blackout_id, p_expected_version, v_blackout.record_version
      using errcode = 'serialization_failure';
  end if;

  delete from app.vendor_capacity_blackouts where id = p_blackout_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor capacity blackout % target row was concurrently modified (expected version %)', p_blackout_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_blackout.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_capacity_blackout',
    'app.vendor_capacity_blackouts', p_blackout_id, 'success', null, null, '{}'::jsonb
  );
end;
$$;

create or replace function app.accept_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- the offer-scoped functions above.
  if not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be accepted', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'accepted' where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create or replace function app.decline_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- the offer-scoped functions above.
  if not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be declined', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'declined', decline_reason = p_reason where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create or replace function app.release_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to release a reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- the offer-scoped functions above.
  if not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be released', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create or replace function app.consume_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- the offer-scoped functions above.
  if not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be consumed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'consumed' where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'consume_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

-- ===========================================================================
-- 6. C-15 (spec-compliance lens, HIGH, live-reproduced) + C-05 (folded in, same functions):
--    a compliance-holded vendor, or an inactive/lapsed/not-yet-effective governing
--    contract, could previously have capacity published and reserved against it with
--    ZERO rejection anywhere in this pipeline -- directly contradicting PRC-262 §23's own
--    named exception-flow requirement ("Block expired contract/compliance"). Fixed by
--    checking vendor lifecycle_status, app.vendor_compliance_status.eligibility_hold, and
--    the linked contract's status/effective_start/effective_end window at BOTH publish
--    time (makes the offer reservable) and reserve time (the actual commitment, never
--    trusted from publish time alone -- live-reproduced: a vendor placed on hold AFTER
--    its offer was already published is still correctly blocked at reserve). Also folds
--    the SAME C-05 tenant-membership check fix 5 applied to the rest of this file's write
--    RPCs. Same signatures, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.publish_vendor_capacity_offer(
  p_offer_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_vendor app.vendor_profiles;
  v_governing_contract app.vendor_contracts;
  v_compliance_hold boolean;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.compute_vendor_capacity_available).
  if not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be published', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  -- C-15 (Tier C batch-3 fix, live-reproduced): a compliance-holded or non-active
  -- vendor, or a lapsed/not-yet-effective/inactive governing contract, could
  -- previously be published against with zero rejection anywhere in this pipeline --
  -- directly contradicting PRC-262 §23's own named exception-flow requirement
  -- ("Block expired contract/compliance"). Re-checked again at reserve time below,
  -- never trusted from publish time alone.
  select * into v_vendor from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  if v_vendor.lifecycle_status <> 'active' then
    raise exception 'vendor_not_eligible: vendor % is % and cannot have capacity published', v_offer.vendor_master_id, v_vendor.lifecycle_status
      using errcode = 'check_violation';
  end if;
  select bool_or(coalesce(s.eligibility_hold, false)) into v_compliance_hold from app.vendor_compliance_status s where s.vendor_master_record_id = v_offer.vendor_master_id;
  if coalesce(v_compliance_hold, false) then
    raise exception 'vendor_compliance_hold: vendor % is currently on a compliance hold', v_offer.vendor_master_id
      using errcode = 'check_violation';
  end if;
  if v_offer.contract_id is not null then
    select * into v_governing_contract from app.vendor_contracts where id = v_offer.contract_id;
    if v_governing_contract.status <> 'active' then
      raise exception 'governing_contract_not_active: contract % governing offer % is %', v_offer.contract_id, p_offer_id, v_governing_contract.status
        using errcode = 'check_violation';
    end if;
    if v_governing_contract.effective_start > current_date then
      raise exception 'governing_contract_not_yet_effective: contract % governing offer % is not effective until %', v_offer.contract_id, p_offer_id, v_governing_contract.effective_start
        using errcode = 'check_violation';
    end if;
    if v_governing_contract.effective_end is not null and v_governing_contract.effective_end < current_date then
      raise exception 'governing_contract_expired: contract % governing offer % expired on %', v_offer.contract_id, p_offer_id, v_governing_contract.effective_end
        using errcode = 'check_violation';
    end if;
  end if;

  update app.vendor_capacity_offers set status = 'published' where id = p_offer_id and record_version = p_expected_version returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_capacity_offer',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

create or replace function app.reserve_vendor_capacity(
  p_offer_id uuid,
  p_requested_quantity numeric,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_source_reference_type text,
  p_source_reference_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_vendor app.vendor_profiles;
  v_governing_contract app.vendor_contracts;
  v_compliance_hold boolean;
  v_existing app.vendor_capacity_reservations;
  v_committed numeric;
  v_blackout_count integer;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_requested_quantity is null or p_requested_quantity <= 0 then
    raise exception 'invalid_quantity: requested_quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_capacity_reservations where offer_id = p_offer_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.requested_quantity <> p_requested_quantity or v_existing.window_start <> p_window_start or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reservation on this offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- Design note 2: locking the OFFER row serializes every concurrent reservation
  -- attempt against it -- the "available" computation and the INSERT below happen
  -- inside the SAME lock, so no two concurrent callers can both observe capacity that
  -- only one of them can actually have.
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.compute_vendor_capacity_available).
  if not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.status <> 'published' then
    raise exception 'invalid_transition: vendor capacity offer % is % -- only a published offer may be reserved against', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;
  if p_window_start < v_offer.window_start or p_window_end > v_offer.window_end then
    raise exception 'reservation_outside_offer_window: requested window is not within offer %''s own declared window', p_offer_id
      using errcode = 'check_violation';
  end if;

  -- C-15 (Tier C batch-3 fix, live-reproduced): re-verify vendor/compliance/contract
  -- governance fresh at the actual commitment point too, not trusted from whatever
  -- was true at publish time -- see the identical check on app.publish_vendor_
  -- capacity_offer above for the full rationale.
  select * into v_vendor from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  if v_vendor.lifecycle_status <> 'active' then
    raise exception 'vendor_not_eligible: vendor % is % and cannot have capacity reserved', v_offer.vendor_master_id, v_vendor.lifecycle_status
      using errcode = 'check_violation';
  end if;
  select bool_or(coalesce(s.eligibility_hold, false)) into v_compliance_hold from app.vendor_compliance_status s where s.vendor_master_record_id = v_offer.vendor_master_id;
  if coalesce(v_compliance_hold, false) then
    raise exception 'vendor_compliance_hold: vendor % is currently on a compliance hold', v_offer.vendor_master_id
      using errcode = 'check_violation';
  end if;
  if v_offer.contract_id is not null then
    select * into v_governing_contract from app.vendor_contracts where id = v_offer.contract_id;
    if v_governing_contract.status <> 'active' then
      raise exception 'governing_contract_not_active: contract % governing offer % is %', v_offer.contract_id, p_offer_id, v_governing_contract.status
        using errcode = 'check_violation';
    end if;
    if v_governing_contract.effective_start > current_date then
      raise exception 'governing_contract_not_yet_effective: contract % governing offer % is not effective until %', v_offer.contract_id, p_offer_id, v_governing_contract.effective_start
        using errcode = 'check_violation';
    end if;
    if v_governing_contract.effective_end is not null and v_governing_contract.effective_end < current_date then
      raise exception 'governing_contract_expired: contract % governing offer % expired on %', v_offer.contract_id, p_offer_id, v_governing_contract.effective_end
        using errcode = 'check_violation';
    end if;
  end if;

  select count(*) into v_blackout_count
  from app.vendor_capacity_blackouts b
  where b.offer_id = p_offer_id and b.window_start < p_window_end and b.window_end > p_window_start;
  if v_blackout_count > 0 then
    raise exception 'reservation_in_blackout: requested window overlaps a declared blackout on offer %', p_offer_id
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(r.requested_quantity), 0) into v_committed
  from app.vendor_capacity_reservations r
  where r.offer_id = p_offer_id
    and r.status in ('held', 'accepted', 'consumed')
    and r.window_start < p_window_end and r.window_end > p_window_start;

  if v_committed + p_requested_quantity > v_offer.quantity then
    raise exception 'over_reservation: requesting % of % but only % of % remains uncommitted for this window on offer %', p_requested_quantity, v_offer.uom, v_offer.quantity - v_committed, v_offer.uom, p_offer_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_capacity_reservations (
      tenant_id, offer_id, requested_quantity, window_start, window_end, source_reference_type, source_reference_id, idempotency_key, created_by
    )
    values (
      v_offer.tenant_id, p_offer_id, p_requested_quantity, p_window_start, p_window_end, p_source_reference_type, p_source_reference_id, p_idempotency_key, p_actor_label
    )
    returning * into v_reservation;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_capacity_reservations where offer_id = p_offer_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.requested_quantity <> p_requested_quantity or v_existing.window_start <> p_window_start or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reservation on this offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_vendor_capacity',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, jsonb_build_object('requested_quantity', p_requested_quantity)
  );

  return v_reservation;
end;
$$;

-- ===========================================================================
-- 7. C-15/C-20 (spec-compliance lens, HIGH, CONFIRMED independently by TWO Tier C lenses --
--    spec-compliance and cross-prompt-integration, live-reproduced by both): app.
--    evaluate_vendor_assignment_eligibility only checked a SUPPLIED contract's status,
--    never its effective-date window, and never auto-resolved a contract when the caller
--    left p_contract_id null. app.resolve_effective_vendor_contract was built by PRC-261
--    explicitly "for PRC-263... to read from" (its own migration comment) but PRC-263's
--    own first draft never actually called it -- a real cross-prompt integration gap, not
--    caught by either prompt's own per-prompt Tier B self-check (which by construction
--    cannot see cross-prompt effects). Fixed: this function gains a new OUT resolved_
--    contract_id (a genuine signature change, DROP + CREATE below); when p_contract_id
--    is null, it now auto-resolves the vendor's currently-effective governing contract
--    via the EXACT SAME resolution query app.resolve_effective_vendor_contract itself
--    uses (never the PRC:View-gated RPC wrapper -- this function has no actor parameter
--    to gate a wrapper call with, matching its own already-established "read the table
--    directly" reasoning for compliance status); when a contract IS supplied, its
--    effective_start/effective_end window is now checked, not just its status. Also
--    folds a related C-19-adjacent fix in the SAME function: a capacity reservation
--    still 'held' (never accepted) was treated as eligible even though app.confirm_
--    vendor_assignment's own consumption UPDATE only ever matches status='accepted' --
--    live-reproduced as a silent capacity leak (confirmed, never actually consumed after
--    confirm); tightened to require 'accepted' only, matching consumption's real scope.
-- ===========================================================================

-- Postgres does not permit CREATE OR REPLACE FUNCTION to add an OUT parameter
-- ("cannot change return type of existing function", verified against this session's
-- own live Postgres before choosing this path) -- an explicit DROP is required. Safe
-- within this one migration transaction: PL/pgSQL function bodies calling this
-- function by name (propose_vendor_assignment_invitation, confirm_vendor_assignment,
-- reassign_vendor_assignment, get_vendor_assignment_eligibility_preview, all fixed/
-- re-created later in this SAME migration) carry no catalog-level dependency on it --
-- the function exists again, correctly, before any of them can ever be invoked.
drop function app.evaluate_vendor_assignment_eligibility(uuid, uuid, uuid, uuid, uuid);

create function app.evaluate_vendor_assignment_eligibility(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_po_id uuid,
  p_capacity_reservation_id uuid,
  out eligible boolean,
  out reasons text[],
  out snapshot jsonb,
  out resolved_contract_id uuid
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_vendor app.vendor_profiles;
  v_contract app.vendor_contracts;
  v_po app.purchase_orders;
  v_reservation app.vendor_capacity_reservations;
  v_compliance_hold boolean;
begin
  reasons := array[]::text[];

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;
  if v_vendor.lifecycle_status <> 'active' then
    reasons := array_append(reasons, 'vendor_not_active');
  end if;

  -- Reads app.vendor_compliance_status directly, NOT the PRC:View-gated app.get_
  -- vendor_compliance_eligibility RPC -- the caller of THIS function (propose/confirm/
  -- reassign/preview) has already performed its own complete authorization check for
  -- the overall action; re-entering a differently-gated public RPC here would force
  -- every caller (including an OPS:Assign-only confirming dispatcher) to also hold
  -- PRC:View for no real reason (the exact same reasoning as design note 2's inline
  -- capacity-consumption choice, applied here too).
  select bool_or(coalesce(s.eligibility_hold, false)) into v_compliance_hold
  from app.vendor_compliance_status s
  where s.vendor_master_record_id = p_vendor_master_id;
  if coalesce(v_compliance_hold, false) then
    reasons := array_append(reasons, 'compliance_hold');
  end if;

  -- C-15/C-20 (Tier C batch-3 fix, cross-validated live by two independent review
  -- lenses): the original version only checked a SUPPLIED contract's status, never
  -- its effective-date window, and never auto-resolved a contract when the caller
  -- left p_contract_id null -- silently leaving a not-yet-effective or lapsed
  -- contract, or "no contract at all", indistinguishable from a genuinely governed
  -- assignment. app.resolve_effective_vendor_contract was built by PRC-261
  -- specifically "for PRC-263... to read from" (its own comment) but was never
  -- actually called -- fixed here by reusing its EXACT resolution query directly
  -- (never the PRC:View-gated RPC wrapper itself, matching this function's own
  -- already-established "read the table directly, the caller has already authorized
  -- the overall action" reasoning for compliance status above -- this function has no
  -- actor parameter to gate a wrapper call with in the first place).
  resolved_contract_id := p_contract_id;
  if p_contract_id is not null then
    select * into v_contract from app.vendor_contracts where id = p_contract_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_contract_reference: contract % does not govern vendor % in tenant %', p_contract_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    if v_contract.status <> 'active' then
      reasons := array_append(reasons, 'contract_not_active');
    elsif v_contract.effective_start > current_date then
      reasons := array_append(reasons, 'contract_not_yet_effective');
    elsif v_contract.effective_end is not null and v_contract.effective_end < current_date then
      reasons := array_append(reasons, 'contract_expired');
    end if;
  else
    select * into v_contract
    from app.vendor_contracts
    where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and status = 'active'
      and effective_start <= current_date and (effective_end is null or effective_end >= current_date)
    order by effective_start desc
    limit 1;
    if found then
      resolved_contract_id := v_contract.id;
    end if;
  end if;

  if p_po_id is not null then
    select * into v_po from app.purchase_orders where id = p_po_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_po_reference: purchase order % does not belong to vendor % in tenant %', p_po_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    if v_po.status not in ('issued', 'acknowledged') then
      reasons := array_append(reasons, 'po_not_issued');
    end if;
  end if;

  if p_capacity_reservation_id is not null then
    select r.* into v_reservation
    from app.vendor_capacity_reservations r
    join app.vendor_capacity_offers o on o.id = r.offer_id
    where r.id = p_capacity_reservation_id and r.tenant_id = p_tenant_id and o.vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_capacity_reservation_reference: reservation % does not belong to vendor % in tenant %', p_capacity_reservation_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    -- C-19-adjacent (Tier C batch-3 fix, live-reproduced): this previously accepted
    -- 'held' OR 'accepted' as eligible, but app.confirm_vendor_assignment's own
    -- inline consumption UPDATE only ever matches status='accepted' -- a 'held'
    -- reservation could be confirmed straight through and silently never actually
    -- consumed, permanently double-counted as still-available capacity. Tightened to
    -- the SAME scope confirm's own consumption actually uses.
    if v_reservation.status <> 'accepted' then
      reasons := array_append(reasons, 'capacity_not_available');
    end if;
  end if;

  eligible := array_length(reasons, 1) is null;
  snapshot := jsonb_build_object(
    'vendor_lifecycle_status', v_vendor.lifecycle_status,
    'compliance_hold', coalesce(v_compliance_hold, false),
    'contract_id', resolved_contract_id, 'contract_status', v_contract.status,
    'po_id', p_po_id, 'po_status', v_po.status,
    'capacity_reservation_id', p_capacity_reservation_id, 'capacity_reservation_status', v_reservation.status,
    'evaluated_at', now()
  );
end;
$$;

-- service_role-only, NOT authenticated -- the DROP above removed the original C-12
-- fix's grant along with the old function; re-granted here identically (verified: this
-- statement is the ONLY EXECUTE grant on this function after this migration runs, same
-- as before the drop).
grant execute on function app.evaluate_vendor_assignment_eligibility(uuid, uuid, uuid, uuid, uuid) to service_role;

-- ===========================================================================
-- 8. C-01 (correctness/concurrency lens, HIGH, live-reproduced) + C-15 (rate_version_id
--    scope, live-reproduced) + C-20 (resolved_contract_id persistence, fix 7 above):
--    app.propose_vendor_assignment_invitation's idempotency comparison originally
--    covered only shipment_order_id/vendor_master_id -- a replay with a genuinely
--    different contract/PO/rate/capacity-reservation link or response_deadline silently
--    returned the ORIGINAL row. Now compares the FULL caller-supplied tuple (contract_id
--    compared strictly only when the caller explicitly supplied one -- a replay against
--    an auto-resolved null must still match the already-stored resolution, not fail).
--    Also: rate_version_id was the one linked-evidence field with ZERO vendor/tenant
--    scope validation, unlike contract_id/po_id/capacity_reservation_id (all validated
--    inside evaluate_vendor_assignment_eligibility) -- fixed by mirroring app.create_
--    vendor_contract_draft's own established rate_version_scope_mismatch check. And: the
--    INSERT now stores v_eligibility.resolved_contract_id (fix 7's new output) rather
--    than the raw, possibly-null p_contract_id, so an auto-resolved contract is actually
--    persisted onto the invitation, not silently dropped after being computed. Same
--    signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.propose_vendor_assignment_invitation(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_po_id uuid,
  p_rate_version_id uuid,
  p_capacity_reservation_id uuid,
  p_response_deadline timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_rate app.vendor_rate_versions;
  v_existing app.vendor_assignment_invitations;
  v_eligibility record;
  v_invitation app.vendor_assignment_invitations;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive vendor invitations', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  -- C-15 (Tier C batch-3 fix, live-reproduced): rate_version_id was the one linked-
  -- evidence field with zero vendor/tenant scope validation, unlike contract_id/
  -- po_id/capacity_reservation_id (all validated inside app.evaluate_vendor_
  -- assignment_eligibility) -- mirrors app.create_vendor_contract_draft's own
  -- established rate_version_scope_mismatch check exactly.
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

  -- C-01 (Tier C batch-3 fix): the original pre-check/recovery comparison only
  -- covered shipment_order_id/vendor_master_id -- live-reproduced as reusable to
  -- silently discard a caller's real contract/PO/rate/capacity-reservation linkage
  -- or response_deadline on replay. Both branches now compare the FULL
  -- caller-supplied tuple. contract_id is compared strictly only when the caller
  -- explicitly supplied one -- when left null, eligibility below auto-resolves the
  -- vendor's currently-effective contract, and a replay must still match whatever
  -- was resolved and stored on the FIRST call, not fail because a fresh resolution
  -- attempt (against a raw null) looks different from the already-stored value.
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.shipment_order_id is distinct from p_shipment_order_id
         or v_existing.vendor_master_id is distinct from p_vendor_master_id
         or (p_contract_id is not null and v_existing.contract_id is distinct from p_contract_id)
         or v_existing.po_id is distinct from p_po_id
         or v_existing.rate_version_id is distinct from p_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_capacity_reservation_id
         or v_existing.response_deadline is distinct from p_response_deadline then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment invitation', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(p_tenant_id, p_vendor_master_id, p_contract_id, p_po_id, p_capacity_reservation_id);
  if not v_eligibility.eligible then
    raise exception 'vendor_not_eligible: vendor % is not currently eligible for assignment (%)', p_vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assignment_invitations (
      tenant_id, shipment_order_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
      eligibility_snapshot, response_deadline, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_shipment_order_id, p_vendor_master_id, v_eligibility.resolved_contract_id, p_po_id, p_rate_version_id, p_capacity_reservation_id,
      v_eligibility.snapshot, p_response_deadline, p_idempotency_key, p_actor_label
    )
    returning * into v_invitation;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_existing.shipment_order_id is distinct from p_shipment_order_id
           or v_existing.vendor_master_id is distinct from p_vendor_master_id
           or (p_contract_id is not null and v_existing.contract_id is distinct from p_contract_id)
           or v_existing.po_id is distinct from p_po_id
           or v_existing.rate_version_id is distinct from p_rate_version_id
           or v_existing.capacity_reservation_id is distinct from p_capacity_reservation_id
           or v_existing.response_deadline is distinct from p_response_deadline then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment invitation', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise exception 'invitation_conflict: shipment order % already has a live (invited or accepted) vendor invitation', p_shipment_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('vendor_master_id', p_vendor_master_id, 'shipment_order_id', p_shipment_order_id)
  );

  return v_invitation;
end;
$$;

-- ===========================================================================
-- 9. C-05 (security/RLS lens, MEDIUM, live-reproduced): the SAME tenant-id-disclosure
--    oracle as fixes 3/5 above, independently reintroduced in 20260730720000. Affects:
--    accept_vendor_assignment_invitation, decline_vendor_assignment_invitation, cancel_
--    vendor_assignment_invitation (confirm_vendor_assignment, reassign_vendor_
--    assignment, and this migration's own terminate_vendor_contract replace get the SAME
--    C-05 fold too, folded into fixes 10/11/12 below since each also gains a real
--    behavioral change in the same pass). Same signatures, CREATE OR REPLACE only -- no
--    re-GRANT needed.
-- ===========================================================================

create or replace function app.accept_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.get_vendor_assignment_invitation).
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be accepted', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'accepted' where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

create or replace function app.decline_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.get_vendor_assignment_invitation).
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be declined', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'declined', decline_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

create or replace function app.cancel_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): fold "does not exist" and "exists in
  -- a tenant this caller has no membership in" into the SAME not-found error BEFORE
  -- evaluate_permission's own insufficient_authority message (which echoes the real
  -- tenant_id) becomes reachable -- mirrors the fold every read RPC in this file
  -- already uses (e.g. app.get_vendor_assignment_invitation).
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status not in ('invited', 'accepted') then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be cancelled', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'cancelled', cancel_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

-- ===========================================================================
-- 10. C-05 (folded in, same function): confirm_vendor_assignment gains the SAME tenant-
--    membership fold as fix 9, plus persists v_eligibility.resolved_contract_id (fix 7)
--    onto the canonical row at confirm time too -- if no contract was linked at propose
--    time but one has since become effective (or this is the first time eligibility ever
--    resolved it), design note 3's own "re-verify fresh at confirm" must not silently
--    drop the resolution it just computed. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.confirm_vendor_assignment(
  p_invitation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
  v_eligibility record;
  v_assignment app.resource_assignments;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment above.
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be confirmed', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  -- Design note 3: re-verify eligibility fresh, never trust the propose-time snapshot.
  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(
    v_invitation.tenant_id, v_invitation.vendor_master_id, v_invitation.contract_id, v_invitation.po_id, v_invitation.capacity_reservation_id
  );
  if not v_eligibility.eligible then
    raise exception 'vendor_no_longer_eligible: vendor % is no longer eligible for assignment (%)', v_invitation.vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  -- The canonical commitment -- never re-implemented, always this exact call.
  v_assignment := app.assign_resource(v_invitation.shipment_order_id, 'vendor', v_invitation.vendor_master_id, p_actor_auth_user_id, p_actor_label);

  -- Design note 2: inline, not a second call to the PRC:Edit-gated public RPC.
  if v_invitation.capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = v_invitation.capacity_reservation_id and status = 'accepted';
  end if;

  -- C-20 (Tier C batch-3 fix): if no contract was linked at propose time but one has
  -- since become effective (or the eligibility re-check above just auto-resolved it
  -- for the first time), persist that resolution onto the canonical row now -- design
  -- note 3 already re-verifies eligibility fresh at confirm; the resolved contract_id
  -- itself must not be silently dropped after being computed.
  update app.vendor_assignment_invitations
  set status = 'assigned', assignment_id = v_assignment.id, eligibility_snapshot = v_eligibility.snapshot, contract_id = v_eligibility.resolved_contract_id
  where id = p_invitation_id and record_version = p_expected_version
  returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_vendor_assignment',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('assignment_id', v_assignment.id)
  );

  return v_invitation;
end;
$$;

-- ===========================================================================
-- 11. C-01/C-02 (correctness/concurrency lens, HIGH, live-reproduced) + C-05 (folded in) +
--    C-15 (rate_version_id scope, folded in): app.reassign_vendor_assignment previously
--    carried NO idempotency pre-check or race-recovery handler at all, unlike every
--    sibling idempotency-keyed write in this migration -- a raw retry of an
--    already-completed reassignment with the same key surfaced as a bare, unclassified
--    unique_violation (23505) instead of a clean idempotency_key_conflict. Fixed by
--    adding both, matching the established pattern exactly -- the pre-check runs BEFORE
--    the version/status checks specifically because a genuine replay's prior invitation
--    is already 'superseded' by the time of the replay, which would otherwise be
--    misclassified as invalid_transition. Also gains: the SAME tenant-membership C-05
--    fold; the SAME rate_version_id scope-mismatch check as fix 8; and stores v_
--    eligibility.resolved_contract_id (fix 7) rather than the raw p_new_contract_id.
--    Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.reassign_vendor_assignment(
  p_invitation_id uuid,
  p_expected_version integer,
  p_new_vendor_master_id uuid,
  p_new_contract_id uuid,
  p_new_po_id uuid,
  p_new_rate_version_id uuid,
  p_new_capacity_reservation_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_prior app.vendor_assignment_invitations;
  v_rate app.vendor_rate_versions;
  v_existing app.vendor_assignment_invitations;
  v_eligibility record;
  v_assignment app.resource_assignments;
  v_new app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reassign a vendor assignment' using errcode = 'check_violation';
  end if;

  select * into v_prior from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment above.
  if not app.has_active_tenant_membership(v_prior.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prior.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prior.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-15 (Tier C batch-3 fix, live-reproduced): see the identical rate_version_id
  -- scope-mismatch comment on app.propose_vendor_assignment_invitation above.
  if p_new_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_new_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_new_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_prior.tenant_id or v_rate.vendor_master_id is distinct from p_new_vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to vendor % in tenant %', p_new_rate_version_id, p_new_vendor_master_id, v_prior.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- C-01/C-02 (Tier C batch-3 fix): this function previously carried no idempotency
  -- pre-check or race-recovery handler at all, unlike every sibling idempotency-keyed
  -- write in this migration -- a raw retry of an already-completed reassignment with
  -- the same key live-reproduced as a bare unique_violation (23505) instead of a
  -- clean idempotency_key_conflict, and (because the prior invitation is already
  -- 'superseded' by the time of a replay) would otherwise be misclassified as
  -- invalid_transition below if this check ran any later. Checked BEFORE the version/
  -- status checks for exactly that reason -- a genuine replay must short-circuit past
  -- state that a successful prior call has already advanced.
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = v_prior.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_prior.superseded_by_id is distinct from v_existing.id
         or v_existing.vendor_master_id is distinct from p_new_vendor_master_id
         or (p_new_contract_id is not null and v_existing.contract_id is distinct from p_new_contract_id)
         or v_existing.po_id is distinct from p_new_po_id
         or v_existing.rate_version_id is distinct from p_new_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_new_capacity_reservation_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment reassignment', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if v_prior.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_prior.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_prior.status <> 'assigned' then
    raise exception 'invalid_transition: vendor assignment invitation % is % -- only an assigned invitation may be reassigned (use cancel for anything earlier)', p_invitation_id, v_prior.status
      using errcode = 'check_violation';
  end if;

  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(
    v_prior.tenant_id, p_new_vendor_master_id, p_new_contract_id, p_new_po_id, p_new_capacity_reservation_id
  );
  if not v_eligibility.eligible then
    raise exception 'vendor_not_eligible: vendor % is not currently eligible for assignment (%)', p_new_vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  v_assignment := app.reassign_resource(v_prior.shipment_order_id, 'vendor', p_new_vendor_master_id, p_reason, p_actor_auth_user_id, p_actor_label);

  if p_new_capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = p_new_capacity_reservation_id and status = 'accepted';
  end if;

  update app.vendor_assignment_invitations set status = 'superseded' where id = p_invitation_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.vendor_assignment_invitations (
      tenant_id, shipment_order_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
      eligibility_snapshot, status, assignment_id, idempotency_key, created_by
    )
    values (
      v_prior.tenant_id, v_prior.shipment_order_id, p_new_vendor_master_id, v_eligibility.resolved_contract_id, p_new_po_id, p_new_rate_version_id, p_new_capacity_reservation_id,
      v_eligibility.snapshot, 'assigned', v_assignment.id, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assignment_invitations where tenant_id = v_prior.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_id is distinct from p_new_vendor_master_id
         or (p_new_contract_id is not null and v_existing.contract_id is distinct from p_new_contract_id)
         or v_existing.po_id is distinct from p_new_po_id
         or v_existing.rate_version_id is distinct from p_new_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_new_capacity_reservation_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment reassignment', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  update app.vendor_assignment_invitations set superseded_by_id = v_new.id where id = p_invitation_id;

  perform app.capture_audit_event(
    v_prior.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_vendor_assignment',
    'app.vendor_assignment_invitations', v_new.id, 'success', p_reason, null, jsonb_build_object('supersedes_invitation_id', p_invitation_id, 'assignment_id', v_assignment.id)
  );

  return v_new;
end;
$$;

-- ===========================================================================
-- 12. C-05 (folded in, same function): this migration's own `create or replace function
--    app.terminate_vendor_contract` (PRC-263's hardening of PRC-261's own function with
--    the active-dependency guard) carried the identical tenant-id-disclosure oracle as
--    fix 3's original app.terminate_vendor_contract -- the C-05 fold did not survive
--    PRC-263's own replace. Fixed the same way. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.terminate_vendor_contract(
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
  v_active_dependency_count integer;
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
  -- C-05 (Tier C batch-3 fix, live-reproduced): see the identical fold comment on
  -- app.vendor_assignment_invitations-scoped functions above -- this hardened
  -- app.terminate_vendor_contract replace carried the same defect PRC-261's own
  -- original definition had.
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
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

  -- PRC-263's own promised guard (PRC-261 design note 6): block termination while a
  -- live (invited/accepted/assigned) vendor assignment invitation still cites this
  -- contract as its own governing evidence.
  select count(*) into v_active_dependency_count
  from app.vendor_assignment_invitations
  where contract_id = p_contract_id and status in ('invited', 'accepted', 'assigned');
  if v_active_dependency_count > 0 then
    raise exception 'active_dependency_exists: vendor contract % has % active assignment invitation(s) citing it -- cancel or reassign them first', p_contract_id, v_active_dependency_count
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

  return v_contract;
end;
$$;

