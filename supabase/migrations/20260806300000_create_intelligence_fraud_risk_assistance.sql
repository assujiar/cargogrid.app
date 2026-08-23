-- Intelligence, Automation and Enterprise Expansion: Fraud and Risk
-- Assistance (IAE-024, CG-S14-IAE-024, Prompt 352). Fourth of Group 6
-- ("Further AI-Assisted Capabilities", Prompts 349-353). Depends on
-- IAE-019 (AI Governance Provider Boundary, VERIFIED) exactly as
-- IAE-020/021/022/023 already do. Disclosed, confirmed-separate from the
-- existing Phase 8 rule-based Loyalty fraud prevention
-- (app/(tenant)/.../admin/loyalty-fraud-review, customer_portal_loyalty_
-- expiry_fraud_prevention migration) -- that is domain-specific,
-- rule-based, pre-existing prior art; this checkpoint is the genuinely new,
-- AI-governed, cross-domain (loyalty/payment/vendor/ticket/api_abuse) risk
-- signal layer, left alone and unmodified per the "narrower prior art
-- stays, broader capability is new and additive" precedent (ADR-0024
-- Part A).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **The AI model can never autonomously punish or finalize a fraud
--    decision -- structurally.** No function in this migration writes to
--    any existing loyalty/payment/vendor/ticket/API table. A signal is
--    evidence; app.decide_risk_signal is a human's own recorded judgment;
--    app.hold_risk_signal_entity/app.release_risk_signal_entity are this
--    checkpoint's own real, self-contained governance record of "an
--    authorized reviewer is holding/released this entity pending
--    investigation" -- never a live enforcement write into the held
--    entity's own domain table. Real-time cross-domain enforcement (e.g.
--    a loyalty redemption UI actually consulting an active hold before
--    allowing a redemption) is a disclosed, deferred integration point,
--    not built here -- mirrors IAE-023's own "acknowledge, never mutate
--    the external system" boundary, adapted: here the hold/release
--    lifecycle itself IS real, owned, audited state (not a mere
--    acknowledgement of someone else's action), but it stops at this
--    checkpoint's own schema boundary.
-- 2. **A hold/release always requires an underlying, human-CONFIRMED
--    signal, never a raw AI score alone.** app.hold_risk_signal_entity
--    refuses unless app.risk_signal_reviews already has a 'confirmed'
--    decision for the signal -- the business rule "all holds/releases
--    require reason, reviewer and source policy" is enforced as a real
--    precondition, not a UI convention.
-- 3. **Customer-facing text is a structurally SEPARATE, required field,
--    never derived from the internal reason.** app.hold_risk_signal_entity
--    requires customer_safe_reason distinct from the internal reason (a
--    real CHECK constraint) -- a cheap, honest structural nudge against
--    copy-pasting internal detection reasoning into customer-facing text,
--    not a fake NLP leak-detector (this project's own "no placeholder/
--    fake defense" Definition of Done, the same reasoning IAE-019's own
--    migration used to justify not building a prompt-injection content
--    classifier).
-- 4. **Score/band extraction from the governed request's own output is
--    defensive, mirroring IAE-022's app._parse_eta_timestamp exactly** --
--    a malformed score/band yields null fields, never a crash or a
--    fabricated value.
-- 5. **Fraud signals/thresholds are restricted internal data by
--    construction, not by masking** -- every function in this migration is
--    gated on the AI module (internal actors only); no customer-facing RPC
--    exists anywhere in this checkpoint, so there is no "internal vs
--    customer view" to mask between (unlike IAE-023's cost/margin
--    masking, which exists because internal actors themselves have tiered
--    visibility).
-- 6. **At most one ACTIVE hold per signal** -- a partial unique index
--    (risk_signal_id where status = 'active') prevents a duplicate,
--    concurrent hold on the same signal.
-- 7. AI dispatch reuses dispatchAiGovernedRequest (IAE-019) unmodified --
--    feature_code = 'fraud_risk_assistance', correlation_record_type =
--    the signal's own entity_type (a real, polymorphic reference to the
--    entity actually being evaluated, mirroring app.files.record_type/
--    record_id's own established soft-reference posture -- never a
--    self-correlation the way IAE-023's optimization_scenario had to,
--    since a risk signal DOES have a genuine external subject).
-- 8. No new entitlement module -- the AI module's own comment (IAE-019)
--    already names fraud/risk as one of its owned features.
-- 9-11. Proactively applied lessons from IAE-020/021/022/023: SECURITY
--    DEFINER + assert_actor_is_session_identity on every authenticated-
--    granted function; explicit table aliases in every RETURNS TABLE; IS
--    DISTINCT FROM for every nullable correlation cross-check.
-- 12. Per ERR-2026-004: explicit revoke execute on all functions in
--    schema app from public.

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_risk_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Defensive extraction helpers (design decision 4)
-- ===========================================================================

create function app._parse_risk_score(p_payload jsonb)
returns numeric
language plpgsql
immutable
as $$
declare
  v_result numeric;
begin
  if p_payload is null or jsonb_typeof(p_payload) not in ('number', 'string') then
    return null;
  end if;
  begin
    v_result := (p_payload #>> '{}')::numeric;
  exception when others then
    return null;
  end;
  if v_result < 0 or v_result > 100 then
    return null;
  end if;
  return v_result;
end;
$$;

create function app._parse_risk_band(p_payload jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v_result text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'string' then
    return null;
  end if;
  v_result := p_payload #>> '{}';
  if v_result not in ('low', 'medium', 'high', 'critical') then
    return null;
  end if;
  return v_result;
end;
$$;

comment on function app._parse_risk_score is 'IAE-024 (design decision 4): defensive, bounded [0,100] extraction -- malformed/out-of-range input yields NULL, never a crash or a fabricated value.';
comment on function app._parse_risk_band is 'IAE-024 (design decision 4): defensive extraction -- only a real low/medium/high/critical string is accepted, anything else (including a prompt-injection-shaped string) yields NULL.';

-- ===========================================================================
-- Core signal table
-- ===========================================================================

create table app.risk_signals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  risk_domain text not null,
  entity_type text not null,
  entity_id uuid not null,
  input_snapshot jsonb not null,
  ai_governed_request_id uuid unique references app.ai_governed_requests (id),
  status text not null default 'pending',
  score numeric,
  band text,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint risk_signals_risk_domain_check check (risk_domain in ('loyalty', 'payment', 'vendor', 'ticket', 'api_abuse')),
  constraint risk_signals_status_check check (status in ('pending', 'succeeded', 'failed')),
  constraint risk_signals_band_check check (band is null or band in ('low', 'medium', 'high', 'critical')),
  constraint risk_signals_score_check check (score is null or (score >= 0 and score <= 100)),
  constraint risk_signals_input_snapshot_check check (app.validate_config_value(input_snapshot)),
  constraint risk_signals_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.risk_signals is
  'IAE-024: one row per risk signal request. Restricted internal data (design decision 5) -- every read/write function is AI-module-gated, no customer-facing RPC exists. NEVER writes to any existing loyalty/payment/vendor/ticket/API table (design decision 1).';

create index risk_signals_tenant_idx on app.risk_signals (tenant_id, created_at desc);
create index risk_signals_entity_idx on app.risk_signals (tenant_id, entity_type, entity_id);
create index risk_signals_domain_idx on app.risk_signals (tenant_id, risk_domain, created_at desc);

-- ===========================================================================
-- Request
-- ===========================================================================

create function app.request_risk_signal(
  p_tenant_id uuid,
  p_risk_domain text,
  p_entity_type text,
  p_entity_id uuid,
  p_input_snapshot jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.risk_signals;
  v_row app.risk_signals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_risk_domain not in ('loyalty', 'payment', 'vendor', 'ticket', 'api_abuse') then
    raise exception 'risk_signal_invalid_domain: % is not one of loyalty/payment/vendor/ticket/api_abuse', p_risk_domain
      using errcode = 'check_violation';
  end if;
  if p_entity_type is null or length(trim(p_entity_type)) = 0 then
    raise exception 'risk_signal_entity_type_required: a non-empty entity_type is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.risk_signals where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.entity_type is distinct from p_entity_type or v_existing.entity_id is distinct from p_entity_id then
      raise exception 'idempotency_key_conflict: key % was already used for a different entity', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if not app.validate_config_value(p_input_snapshot) then
    raise exception 'risk_signal_invalid_input_snapshot: input_snapshot failed the structural safety check' using errcode = 'check_violation';
  end if;

  insert into app.risk_signals (
    tenant_id, risk_domain, entity_type, entity_id, input_snapshot, status, requested_by_auth_user_id, requested_by, idempotency_key
  ) values (
    p_tenant_id, p_risk_domain, p_entity_type, p_entity_id, p_input_snapshot, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_risk_signal',
    'app.risk_signals', v_row.id, 'success', null, null, jsonb_build_object('risk_domain', v_row.risk_domain, 'entity_type', v_row.entity_type)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Record outcome after dispatch
-- ===========================================================================

create function app.record_risk_signal_outcome(
  p_signal_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_signal app.risk_signals;
  v_request app.ai_governed_requests;
  v_score numeric;
  v_band text;
  v_row app.risk_signals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_signal from app.risk_signals where id = p_signal_id;
  if not found then
    raise exception 'risk_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;

  if not app.check_risk_authority('Create', v_signal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_signal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_signal.ai_governed_request_id is not null then
    if v_signal.ai_governed_request_id = p_ai_governed_request_id then
      return v_signal;
    end if;
    raise exception 'risk_signal_outcome_already_recorded: signal % is already linked to a different governed request', p_signal_id
      using errcode = 'check_violation';
  end if;

  if v_signal.status <> 'pending' then
    raise exception 'risk_signal_not_pending: signal % is % not pending', p_signal_id, v_signal.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_signal.tenant_id then
    raise exception 'risk_signal_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_signal.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'fraud_risk_assistance' then
    raise exception 'risk_signal_wrong_feature: governed request % has feature_code % not fraud_risk_assistance', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from v_signal.entity_type or v_request.correlation_record_id is distinct from v_signal.entity_id then
    raise exception 'risk_signal_correlation_mismatch: governed request % does not correlate to signal %''s own entity', p_ai_governed_request_id, p_signal_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'risk_signal_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_score := app._parse_risk_score(v_request.output_payload -> 'score');
    v_band := app._parse_risk_band(v_request.output_payload -> 'band');
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending signal -- live-reproduced on the sibling IAE-022
  -- function before this fix, applied proactively here.
  update app.risk_signals
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      score = v_score, band = v_band, completed_at = now()
  where id = p_signal_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.risk_signals where id = p_signal_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'risk_signal_outcome_already_recorded: signal % is already linked to a different governed request', p_signal_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_signal.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_risk_signal_outcome',
    'app.risk_signals', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'band', v_row.band)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Human review (design decision 2's own precondition source)
-- ===========================================================================

create table app.risk_signal_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  risk_signal_id uuid not null unique references app.risk_signals (id),
  decision text not null,
  reviewer_note text,
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz not null default now(),
  constraint risk_signal_reviews_decision_check check (decision in ('confirmed', 'dismissed', 'false_positive'))
);

comment on table app.risk_signal_reviews is
  'IAE-024: the human decision, recorded separately from the AI''s own signal. decision=confirmed is the ONLY state that unlocks app.hold_risk_signal_entity (design decision 2). false_positive/dismissed feed governance feedback tracking (Prompt 352 §20 task 4).';

create function app.decide_risk_signal(
  p_signal_id uuid,
  p_tenant_id uuid,
  p_decision text,
  p_reviewer_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signal_reviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_signal app.risk_signals;
  v_row app.risk_signal_reviews;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('confirmed', 'dismissed', 'false_positive') then
    raise exception 'risk_signal_invalid_decision: % is not one of confirmed/dismissed/false_positive', p_decision using errcode = 'check_violation';
  end if;

  select * into v_signal from app.risk_signals where id = p_signal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'risk_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;
  if v_signal.status <> 'succeeded' then
    raise exception 'risk_signal_not_reviewable: signal % is % -- only a succeeded signal may be reviewed', p_signal_id, v_signal.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.risk_signal_reviews where risk_signal_id = p_signal_id) then
    raise exception 'risk_signal_already_reviewed: signal % already has a review', p_signal_id using errcode = 'check_violation';
  end if;

  insert into app.risk_signal_reviews (tenant_id, risk_signal_id, decision, reviewer_note, decided_by_auth_user_id, decided_by)
  values (p_tenant_id, p_signal_id, p_decision, p_reviewer_note, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_risk_signal',
    'app.risk_signal_reviews', v_row.id, 'success', null, null, jsonb_build_object('decision', v_row.decision)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Governed hold/release (design decisions 1, 2, 3, 6)
-- ===========================================================================

create table app.risk_signal_actions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  risk_signal_id uuid not null references app.risk_signals (id),
  reason text not null,
  customer_safe_reason text not null,
  status text not null default 'active',
  held_by_auth_user_id uuid not null,
  held_by text,
  held_at timestamptz not null default now(),
  released_by_auth_user_id uuid,
  released_by text,
  released_at timestamptz,
  release_reason text,
  constraint risk_signal_actions_status_check check (status in ('active', 'released')),
  constraint risk_signal_actions_release_shape_check check (status = 'active' or (released_by_auth_user_id is not null and release_reason is not null)),
  constraint risk_signal_actions_customer_safe_distinct_check check (customer_safe_reason is distinct from reason)
);

comment on table app.risk_signal_actions is
  'IAE-024: a real, self-contained hold/release governance record (design decision 1) -- never a write into the held entity''s own domain table. customer_safe_reason must differ from the internal reason (design decision 3, a structural nudge, not a content classifier).';

create unique index risk_signal_actions_one_active_per_signal_idx on app.risk_signal_actions (risk_signal_id) where status = 'active';

create function app.hold_risk_signal_entity(
  p_signal_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_customer_safe_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signal_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_signal app.risk_signals;
  v_review app.risk_signal_reviews;
  v_row app.risk_signal_actions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_signal from app.risk_signals where id = p_signal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'risk_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;

  select * into v_review from app.risk_signal_reviews where risk_signal_id = p_signal_id;
  if not found or v_review.decision <> 'confirmed' then
    raise exception 'risk_signal_not_confirmed: signal % has no confirmed review -- a hold requires a human-confirmed signal (design decision 2)', p_signal_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'risk_signal_hold_reason_required: a reason is required' using errcode = 'check_violation';
  end if;
  if p_customer_safe_reason is null or length(trim(p_customer_safe_reason)) = 0 then
    raise exception 'risk_signal_customer_safe_reason_required: a customer-safe reason is required' using errcode = 'check_violation';
  end if;
  if p_customer_safe_reason = p_reason then
    raise exception 'risk_signal_customer_safe_reason_not_distinct: customer_safe_reason must not be identical to the internal reason (design decision 3)'
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.risk_signal_actions where risk_signal_id = p_signal_id and status = 'active') then
    raise exception 'risk_signal_already_held: signal % already has an active hold', p_signal_id using errcode = 'check_violation';
  end if;

  insert into app.risk_signal_actions (tenant_id, risk_signal_id, reason, customer_safe_reason, held_by_auth_user_id, held_by)
  values (p_tenant_id, p_signal_id, p_reason, p_customer_safe_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_risk_signal_entity',
    'app.risk_signal_actions', v_row.id, 'success', null, null, jsonb_build_object('risk_signal_id', v_row.risk_signal_id)
  );

  return v_row;
end;
$$;

create function app.release_risk_signal_entity(
  p_action_id uuid,
  p_tenant_id uuid,
  p_release_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signal_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.risk_signal_actions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_release_reason is null or length(trim(p_release_reason)) = 0 then
    raise exception 'risk_signal_release_reason_required: a reason is required' using errcode = 'check_violation';
  end if;

  update app.risk_signal_actions
  set status = 'released', released_by_auth_user_id = p_actor_auth_user_id, released_by = p_actor_label, released_at = now(), release_reason = p_release_reason
  where id = p_action_id and tenant_id = p_tenant_id and status = 'active'
  returning * into v_row;

  if not found then
    if exists (select 1 from app.risk_signal_actions where id = p_action_id and tenant_id = p_tenant_id) then
      raise exception 'risk_signal_action_not_active: action % is already released', p_action_id using errcode = 'check_violation';
    end if;
    raise exception 'risk_signal_action_not_found: %', p_action_id using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'release_risk_signal_entity',
    'app.risk_signal_actions', v_row.id, 'success', null, null, jsonb_build_object('release_reason', v_row.release_reason)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Reads
-- ===========================================================================

create function app.get_risk_signal(p_signal_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, risk_domain text, entity_type text, entity_id uuid, input_snapshot jsonb,
  status text, score numeric, band text, requested_by text, created_at timestamptz, completed_at timestamptz,
  output_payload jsonb, confidence_label text, model_version text, request_status text,
  review_decision text, reviewer_note text, decided_by text, decided_at timestamptz,
  hold_status text, hold_reason text, hold_customer_safe_reason text, held_by text, held_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.id, s.tenant_id, s.risk_domain, s.entity_type, s.entity_id, s.input_snapshot,
         s.status, s.score, s.band, s.requested_by, s.created_at, s.completed_at,
         r.output_payload, r.confidence_label, r.model_version, r.status,
         rv.decision, rv.reviewer_note, rv.decided_by, rv.decided_at,
         a.status, a.reason, a.customer_safe_reason, a.held_by, a.held_at
  from app.risk_signals s
  left join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  left join app.risk_signal_reviews rv on rv.risk_signal_id = s.id
  left join app.risk_signal_actions a on a.risk_signal_id = s.id and a.status = 'active'
  where s.id = p_signal_id and s.tenant_id = p_tenant_id;
end;
$$;

create function app.list_risk_signals_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_risk_domain text default null,
  p_status text default null,
  p_band text default null,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, risk_domain text, entity_type text, entity_id uuid, status text,
  score numeric, band text, requested_by text, created_at timestamptz, review_decision text, hold_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_risk_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'risk_signal_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select s.id, s.tenant_id, s.risk_domain, s.entity_type, s.entity_id, s.status, s.score, s.band, s.requested_by, s.created_at,
         rv.decision, a.status
  from app.risk_signals s
  left join app.risk_signal_reviews rv on rv.risk_signal_id = s.id
  left join app.risk_signal_actions a on a.risk_signal_id = s.id and a.status = 'active'
  where s.tenant_id = p_tenant_id
    and (p_risk_domain is null or s.risk_domain = p_risk_domain)
    and (p_status is null or s.status = p_status)
    and (p_band is null or s.band = p_band)
  order by s.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.risk_signals enable row level security;
alter table app.risk_signal_reviews enable row level security;
alter table app.risk_signal_actions enable row level security;

-- No direct authenticated grant and zero policies -- the only read paths
-- are the two dedicated functions (AI:View-gated).

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_risk_authority(text, uuid, uuid) to service_role;
grant execute on function app._parse_risk_score(jsonb) to service_role;
grant execute on function app._parse_risk_band(jsonb) to service_role;
grant execute on function app.request_risk_signal(uuid, text, text, uuid, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_risk_signal_outcome(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.decide_risk_signal(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.hold_risk_signal_entity(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_risk_signal_entity(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_risk_signal(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_risk_signals_for_tenant(uuid, uuid, text, text, text, integer) to authenticated, service_role;
