-- Track B Batch 4 (loyalty-fraud-reconciliation), ISS-2026-133 item 1
-- (docs/runtime/KNOWN_ISSUES.md): self-approval was NOT structurally
-- blocked between app.open_loyalty_fraud_review_case and app.decide_
-- loyalty_fraud_review_case -- the same staff member (already holding the
-- elevated LYL:Configure authority both functions require) could open a
-- fraud review case (which immediately applies a provisional account hold)
-- and then decide that SAME case themselves, with no maker/checker
-- separation at all.
--
-- Independently re-verified before drafting this fix (not accepted from
-- the issue's own text at face value): direct read of both function bodies
-- in supabase/migrations/20260801240000_create_customer_portal_loyalty_
-- expiry_fraud_prevention.sql confirms neither function compares the
-- opening actor's identity against the deciding actor's identity anywhere
-- -- app.loyalty_fraud_review_cases.opened_by is a plain `text` label
-- (p_actor_label), never an auth_user_id, so no such comparison was even
-- possible before this migration.
--
-- This is the IDENTICAL self_approval_not_allowed convention already
-- established repository-wide for every other maker-checker pair with two
-- DIFFERENT actor identities on the same row, mirrored here exactly:
--  - app.decide_loyalty_point_adjustment (CPL-318, this same Loyalty
--    domain): `if v_request.requested_by_auth_user_id = p_actor_auth_user_id
--    then raise exception 'self_approval_not_allowed: ...'` against a
--    `requested_by_auth_user_id uuid not null` column captured at request
--    time (supabase/migrations/20260801200000_create_customer_portal_
--    loyalty_points_ledger.sql:1171-1172).
--  - app.decide_vendor_assessment_review (PRC-264):
--    `self_approval_not_allowed: identity % assessed vendor assessment %
--    and may not also decide its review`.
--  - app.decide_claim_responsibility (ATW-025): `decided_by <> proposed_by
--    (self_approval_not_allowed, the exact app.approve_warehouse_billing_
--    event convention)`.
--  - app.approve_warehouse_billing_event (ATW-022) and app.approve_cycle_
--    count_adjustment (ATW-020) both established the original shape.
--
-- Scope, deliberately bounded per ISS-2026-133's own recommended fix: only
-- item 1 (self-approval) is closed here. Item 2 (entitlement-level fraud
-- hold) remains a disclosed, reasoned scope boundary, not a defect --
-- unchanged. Item 3 (expiry sweep is on-demand/staff-triggered only)
-- mirrors the already-accepted repository-wide "no live scheduler exists"
-- precedent family (ISS-2026-126/127/128/129) -- unchanged, requires a
-- future scheduler capability, not a migration.
--
-- Retroactivity, disclosed: `opened_by_auth_user_id` is added as a nullable
-- column (existing rows cannot be backfilled with a real historical actor
-- identity -- only `opened_by`, a text label, was ever captured before this
-- fix). The self-approval check below is therefore a no-op (never blocks)
-- for any case opened before this migration and still sitting in
-- open/under_review at the moment it applies -- a real, narrow,
-- disclosed limitation, mirroring ISS-2026-130's own precedent of a fix
-- that does not retroactively cover pre-existing rows/tables outside its
-- own bounded scope. Every case opened AFTER this migration is fully
-- covered.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit `revoke execute on all functions in schema app from
-- public` statement before its final grants, the standing per-migration
-- convention since PLT-118.

-- ===========================================================================
-- 1. New column: the real opening actor's own auth_user_id, captured going
--    forward (mirrors app.loyalty_point_adjustment_requests.requested_by_
--    auth_user_id exactly -- same nullability shape is not required there
--    since that table was born with the column; here it must be nullable
--    because it is added to an existing, already-populated table).
-- ===========================================================================

alter table app.loyalty_fraud_review_cases
  add column opened_by_auth_user_id uuid;

comment on column app.loyalty_fraud_review_cases.opened_by_auth_user_id is
  'ISS-2026-133 item 1 fix: the real auth_user_id of the actor who opened this case, captured going forward only (nullable -- cases opened before this migration have no historical value here and are NOT retroactively covered by the self-approval block in app.decide_loyalty_fraud_review_case). opened_by (text label) remains the display-facing field, unchanged.';

-- ===========================================================================
-- 2. app.open_loyalty_fraud_review_case -- same signature, byte-identical
--    body except the INSERT now also captures opened_by_auth_user_id.
-- ===========================================================================

create or replace function app.open_loyalty_fraud_review_case(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_risk_signal_type text,
  p_risk_signal_detail text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.loyalty_fraud_review_cases;
  v_account app.loyalty_accounts;
  v_suppression app.loyalty_fraud_review_suppressions;
  v_case app.loyalty_fraud_review_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant % -- opening a fraud review case immediately applies a provisional account hold, the same elevated authority app.hold_loyalty_account_tier_benefits itself requires (design decision 4)', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_risk_signal_type is null or p_risk_signal_type not in ('velocity_anomaly', 'duplicate_device', 'manual_flag', 'other') then
    raise exception 'invalid_risk_signal_type: % is not one of velocity_anomaly/duplicate_device/manual_flag/other', p_risk_signal_type using errcode = 'check_violation';
  end if;
  if p_risk_signal_detail is null or length(trim(p_risk_signal_detail)) = 0 then
    raise exception 'risk_signal_detail_required: a non-empty internal risk signal detail is required' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern),
  -- verifying the full target tuple on a key match (C-01).
  select * into v_existing from app.loyalty_fraud_review_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.risk_signal_type <> p_risk_signal_type then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different fraud review case', p_idempotency_key using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- Suppression gate (design decision 7, mirrors app._evaluate_ticket_
  -- escalation's own auto-revoke-on-check pattern, HRT-291): an active,
  -- unexpired suppression blocks a NEW case; a stale, unrevoked, already-
  -- expired one is auto-revoked here, the first time it is checked.
  select * into v_suppression from app.loyalty_fraud_review_suppressions where loyalty_account_id = p_loyalty_account_id and revoked_at is null for update;
  if v_suppression.id is not null then
    if v_suppression.expires_at > clock_timestamp() then
      raise exception 'fraud_review_suppressed: an active suppression prevents opening a new review case for loyalty account % until %', p_loyalty_account_id, v_suppression.expires_at using errcode = 'check_violation';
    end if;
    update app.loyalty_fraud_review_suppressions set revoked_at = clock_timestamp(), revoked_by = 'system:fraud-review-case-open', revoked_reason = 'expired'
    where id = v_suppression.id;
  end if;

  -- The case row's own INSERT (the idempotency claim, and the partial-
  -- unique-index guard) happens strictly BEFORE composing the hold (design
  -- decision 12) -- a losing idempotency-key racer never reaches the hold
  -- composition step at all.
  begin
    insert into app.loyalty_fraud_review_cases (tenant_id, loyalty_account_id, risk_signal_type, risk_signal_detail, opened_by, opened_by_auth_user_id, idempotency_key)
    values (p_tenant_id, p_loyalty_account_id, p_risk_signal_type, trim(p_risk_signal_detail), p_actor_label, p_actor_auth_user_id, p_idempotency_key)
    returning * into v_case;
  exception
    when unique_violation then
      -- Could be a genuine idempotency-key race (another caller already
      -- won) OR the partial "one open/under_review case per account" index
      -- -- distinguish by re-checking the idempotency key first (mirrors
      -- app.issue_loyalty_benefit_entitlement's own identical distinguishing
      -- shape, CPL-319).
      select * into v_existing from app.loyalty_fraud_review_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise exception 'fraud_review_case_already_active: loyalty account % already has an open or under_review fraud review case', p_loyalty_account_id using errcode = 'check_violation';
  end;

  -- Composes app.hold_loyalty_account_tier_benefits (CPL-317) -- never a
  -- direct app.loyalty_account_tier_holds write (design decision 3).
  -- Idempotent by construction on the composed side too: an already-held
  -- account (from a prior case or a direct staff hold) is a safe no-op
  -- preserving the ORIGINAL hold_reason.
  perform app.hold_loyalty_account_tier_benefits(
    p_tenant_id, p_loyalty_account_id,
    'Fraud review case ' || v_case.id::text || ' opened (' || p_risk_signal_type || '): ' || trim(p_risk_signal_detail),
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'open_loyalty_fraud_review_case',
    'app.loyalty_fraud_review_cases', v_case.id, 'success', null, null,
    jsonb_build_object('loyalty_account_id', p_loyalty_account_id, 'risk_signal_type', p_risk_signal_type)
  );

  return v_case;
end;
$$;

comment on function app.open_loyalty_fraud_review_case is
  'CPL-322: idempotent on (tenant_id, idempotency_key), verifying the full target tuple on a key match. At most one OPEN/UNDER_REVIEW case per loyalty_account at a time (lfrc_single_active_per_account). Composes app.hold_loyalty_account_tier_benefits (design decision 3) -- the SAME account-level hold app.submit_loyalty_redemption (CPL-321) already reads directly. ISS-2026-133 item 1 fix: now also captures opened_by_auth_user_id, the real opening actor identity, so app.decide_loyalty_fraud_review_case can block self-approval.';

-- ===========================================================================
-- 3. app.decide_loyalty_fraud_review_case -- same signature, adds the
--    self_approval_not_allowed check, the exact established convention
--    (app.decide_loyalty_point_adjustment, app.decide_vendor_assessment_
--    review, app.decide_claim_responsibility), immediately after the
--    version/status checks and before the decision is applied.
-- ===========================================================================

create or replace function app.decide_loyalty_fraud_review_case(
  p_tenant_id uuid,
  p_case_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.loyalty_fraud_review_cases;
  v_updated app.loyalty_fraud_review_cases;
  v_new_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision is null or p_decision not in ('confirm', 'clear') then
    raise exception 'invalid_decision: % is not one of confirm/clear', p_decision using errcode = 'check_violation';
  end if;
  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a non-empty review reason is required to decide a fraud review case' using errcode = 'not_null_violation';
  end if;

  select * into v_case from app.loyalty_fraud_review_cases c where c.id = p_case_id and c.tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_fraud_review_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  -- NULL-bypass double-defense (design decision 13, mirrors app.decide_
  -- loyalty_redemption exactly): an explicit up-front check, not only the
  -- UPDATE's own repeated predicate.
  if p_expected_version is null or v_case.record_version <> p_expected_version then
    raise exception 'stale_version: fraud review case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_case.status not in ('open', 'under_review') then
    raise exception 'invalid_transition: fraud review case % is % and cannot be decided', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-133 item 1 fix: self_approval_not_allowed, the exact
  -- app.decide_loyalty_point_adjustment / app.decide_vendor_assessment_
  -- review / app.decide_claim_responsibility convention. Only blocks when
  -- opened_by_auth_user_id is a real, known identity -- a case opened
  -- before this migration (opened_by_auth_user_id null) is not retroactively
  -- covered (disclosed limitation, this migration's own header).
  if v_case.opened_by_auth_user_id is not null and v_case.opened_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % opened fraud review case % and may not also decide it', p_actor_auth_user_id, p_case_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_status := case when p_decision = 'confirm' then 'confirmed' else 'cleared' end;

  update app.loyalty_fraud_review_cases
  set status = v_new_status, reviewed_by = p_actor_label, review_reason = p_review_reason, decided_at = clock_timestamp()
  -- NULL-bypass fix: the predicate is repeated on the UPDATE itself.
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: fraud review case % was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Design decision 10 (no autonomous punitive action): 'clear' composes
  -- app.release_loyalty_account_tier_benefits (never a direct table write).
  -- 'confirm' performs NO further action -- the hold, already applied at
  -- open time, simply stays in place; nothing beyond exactly what this
  -- human reviewer's own call just decided.
  if p_decision = 'clear' then
    perform app.release_loyalty_account_tier_benefits(p_tenant_id, v_case.loyalty_account_id, p_actor_auth_user_id, p_actor_label);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_loyalty_fraud_review_case',
    'app.loyalty_fraud_review_cases', v_updated.id, 'success', p_review_reason,
    jsonb_build_object('status', v_case.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.decide_loyalty_fraud_review_case is
  'CPL-322: staff-only, LYL:Configure. Mandatory non-empty review_reason. ISS-2026-133 item 1 fix: rejects self_approval_not_allowed when the deciding actor is the same identity recorded in opened_by_auth_user_id (not retroactive -- a case opened before this migration has no historical opener identity to compare against). clear composes app.release_loyalty_account_tier_benefits (CPL-317) -- releases whatever hold is currently active on the account, regardless of whether it originated from THIS case or a separate staff action (disclosed limitation, consistent with CPL-317''s own single-hold-row-per-account model). confirm keeps the hold in place with no further autonomous action (design decision 10).';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, applied before any role-specific grant below.
revoke execute on all functions in schema app from public;

grant execute on function app.open_loyalty_fraud_review_case(uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_loyalty_fraud_review_case(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
