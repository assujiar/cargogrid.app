-- Phase 9 Security/AI Hardening (IAE-037, Prompt 365) fix pass. Four parallel
-- adversarial attack lenses (API/access-leakage; AI/prompt-injection;
-- queue/idempotency stress under genuine concurrent load; enterprise IAM/
-- security hardening, including a mandatory step-up-authorization ruling)
-- attacked the whole merged, already-`VERIFIED` 34-capability Phase 9
-- system. This migration is the bounded fix pass for every finding judged
-- in-scope. Per Prompt 365 §12's own explicit "no applied-migration edits"
-- rule, no already-applied migration's own past statements are edited
-- (`create or replace function`/`alter table add constraint` only), no gate
-- weakened, no test disabled.
--
-- ===========================================================================
-- Findings fixed
-- ===========================================================================
--
-- 1. (Medium/High, AI/prompt-injection lens, live-reproduced). `app.hold_
--    risk_signal_entity` (IAE-024) had no maker-checker separation between
--    the human who CONFIRMS a risk signal (`app.decide_risk_signal`) and the
--    human who then HOLDS the entity based on that confirmation -- the same
--    identity could do both alone, unlike every other approval-gated flow
--    in Phase 9 (MFA exception, IP allowlist bypass, automation publish
--    approval, dedicated deployment/region assignment all forbid this).
--    Fixed by rejecting a hold whose actor matches the confirming review's
--    own `decided_by_auth_user_id`.
--
-- 2. (Medium, AI/prompt-injection lens, live-reproduced). Three jsonb-
--    walking functions (`app.redact_ai_output_payload_secret_shaped_
--    values`, `app.mask_optimization_sensitive_fields`, `app.mask_forecast_
--    small_cohort_fields`) recurse with no depth bound -- a ~400-level-deep
--    nested `output_payload` (ordinary AI-provider content, not a crafted
--    attack) crashes each with a raw Postgres `stack depth limit exceeded`.
--    For the outcome-recording function this reproduces the exact "governed
--    request permanently stranded at pending" failure the merged Batch 4
--    Tier C review already fixed once for a different trigger (payload
--    shape, not depth); for the two masking functions it is additionally a
--    permission-differentiated denial-of-service (a non-privileged viewer
--    crashes on every read of an otherwise-valid row; a privileged viewer,
--    for whom masking is skipped, does not). Fixed by adding a bounded
--    depth accumulator (cap 32, generously above any real schema depth)
--    that raises a clean, named error instead of a raw stack overflow.
--
-- 3. (Low, AI/prompt-injection lens). `app.record_ai_governed_request_
--    outcome`'s cost check (`p_provider_unit_cost_amount < 0`) admits
--    Postgres `NaN` (`NaN < 0` is false), silently poisoning a tenant-wide
--    billing `SUM` (RPD-028 "customer-visible metering"). Not live-
--    exploitable today (`service_role`-only; the one real caller computes a
--    deterministic, non-NaN JS value) -- a defense-in-depth fix. Fixed by
--    also rejecting any value `>= 'Infinity'::numeric` -- Postgres numeric
--    NaN does NOT follow IEEE-754 self-inequality (unlike floating point,
--    `NaN = NaN` is TRUE in Postgres) but instead sorts as strictly greater
--    than Infinity, so this single comparison catches real Infinity and
--    NaN alike, mirroring the same established idiom Group 8's own IAE-035
--    RPO/RTO sanity check already uses.
--
-- 4. (Medium, API/access-leakage lens, live-reproduced). `app.rotate_api_
--    key` silently minted a dead-on-arrival successor key when rotating an
--    already-expired key: `app.authenticate_api_key`'s own lazy `status`
--    column transition to `'expired'` is rolled back by its own subsequent
--    `raise`, so the stored `status` column never actually reflects real
--    expiry, and `rotate_api_key`'s `v_old.status <> 'active'` check
--    (trusting that stale column) let a rotation of an expired key proceed,
--    copying the already-past `expires_at` verbatim onto the brand-new key.
--    Never an auth bypass (auth always correctly fails closed on the dead
--    key and its dead successor), but a real, silent operational defect: an
--    admin renewing a key at/after expiry gets a fresh `raw_key` that is
--    non-functional from its first call. Fixed by independently re-checking
--    real-time expiry (`expires_at <= now()`), not the stale status column,
--    and rejecting rotation of an expired key outright.
--
-- 5. (High, queue/idempotency-stress lens, live-reproduced with genuine
--    concurrent OS processes). `app.record_webhook_delivery_attempt`
--    (PLT-129, IAE-012) reads its own delivery row with no lock, computes
--    `attempt_number` from that unlocked read, and has no atomic terminal-
--    state guard on its own final `UPDATE` -- racing a genuine `'success'`
--    against a `'failed'` recording for the SAME decisive attempt slot
--    crashes the loser with a raw, uncaught `duplicate key value violates
--    unique constraint "webhook_delivery_attempts_unique"`, and in 1 of 5
--    trials the genuinely successful delivery's own evidence was discarded
--    entirely while the delivery was incorrectly, permanently marked
--    `dead_letter`. The real worker (`lib/webhooks/process-webhook-
--    delivery-job.server.ts`) calls this RPC with no try/catch, so this is
--    a live crash-loop risk. The identical defect class was already found
--    and fixed once in the sibling `app.record_notification_delivery_
--    attempt` (IAE-014, merged Batch 4 Tier C review) -- the original
--    webhook function this pattern is modeled on was never given the same
--    fix. Fixed identically: `select ... for update` on the initial read,
--    serializing concurrent callers on the same delivery row.
--
-- 6. (Medium/High, queue/idempotency-stress lens, live-reproduced with 20
--    genuinely concurrent processes per function). All five Group 6 AI-job
--    REQUEST/SUBMIT functions (`app.submit_ocr_document_job`, `app.request_
--    optimization_scenario`, `app.request_risk_signal`, `app.request_
--    forecast_job`, `app.request_eta_prediction`) do an unguarded check-
--    then-insert on their own `(tenant_id, idempotency_key)` -- despite
--    each backing table already carrying a real unique constraint, a real
--    client retry racing the original call gets a raw, unclassified
--    Postgres `unique_violation` in up to 65% of racing callers in the
--    lens's own trials, instead of the documented idempotent-replay
--    behavior. The identical defect class has already been found and fixed
--    twice in this codebase generation (Batch 3's `register_n8n_
--    allowlisted_action`/`queue_webhook_delivery`; the HRIS/KPI Batch
--    283-285 review's own `app.enqueue_job` fix, whose exact shape this fix
--    mirrors) -- it recurred here because Group 6's own Tier C review only
--    stress-tested the OUTCOME-recording side of these five capabilities,
--    never the request/submission side. Fixed by wrapping each function's
--    own `insert` in a `begin ... exception when unique_violation` handler
--    that re-selects the existing row and applies the SAME content-mismatch
--    check the function's own pre-check already performs.
--
-- 7. (Mandatory ruling, enterprise IAM/hardening lens -- RULED, WIRING
--    DEFERRED after this checkpoint's own independent live re-verification;
--    see `ISS-2026-151`, not code-fixed here). `app.assert_current_step_up_
--    authorization` (IAE-027) is real and independently correct (already
--    proven at `IAE-355.md` §10) but had ZERO real callers anywhere in the
--    repository, live-confirmed against four DIFFERENT platform-default
--    high-risk `(module, action)` tuples this checkpoint -- `(SEC,
--    Configure)`, `(SEC,Approve)`, `(IAM,Configure)`, `(INTHUB,Configure)`
--    all succeeded with zero step-up challenge. RPD-023 ("MFA/current
--    authorization for privileged, AI-approval, integration, API key, SSO,
--    export and support actions") is a currently-ratified, currently-
--    violated mandatory business rule this checkpoint's own §24 operates
--    under. RULING (mirroring `CPL-325`'s own mandatory `ISS-2026-130`
--    ruling methodology): identified 4 bounded, Phase-9-native targets --
--    `app.decide_ai_output_approval` (AI:Approve), `app.activate_
--    enterprise_idp_connection` (IAM:Configure), `app.approve_mfa_
--    exception` (SEC:Approve), `app.create_integration_connection`
--    (INTHUB:Configure) -- each already carrying both a tenant id and the
--    acting identity in scope, composing with zero signature change. The
--    orchestrating session attempted to wire all 4 in and independently
--    re-verified against the full db-test suite BEFORE trusting the fix,
--    per this repository's own "never accept a fix without live re-
--    verification" discipline -- and that re-verification is what caught
--    the real problem the lens's own reasoning did not surface:
--    `is_high_risk_action`'s platform-default classification for these 4
--    tuples is UNCONDITIONAL, with no tenant-level opt-out, so wiring the
--    gate in makes step-up authorization mandatory immediately, for every
--    tenant, with no transition path. Live-confirmed this breaks 17
--    already-`VERIFIED` capabilities' own db-test fixtures across 5
--    different groups (Integration Hub; all 5 provider integrations;
--    all 5 Group 6 AI-assisted capabilities; AI governance; enterprise IAM/
--    MFA; disaster recovery/support) -- none of which model a step-up
--    challenge today, since the mechanism had zero callers when they were
--    each built and reviewed. Wiring it in without also adapting all 17
--    fixtures would be exactly the "half-finished implementation" this
--    repository's own standards forbid; adapting all 17 (each needing a
--    real request+verify step-up-challenge call inserted before the now-
--    gated action) is real, substantial, cross-capability test-adaptation
--    work spanning 5 already-closed groups -- genuinely exceeding this
--    checkpoint's own bounded, single-migration-fix scope, the same
--    reasoning that already excluded API-key/support-access wiring below.
--    REVISED RULING: disclose with the full, concrete blast-radius data
--    above (not merely "the gate exists and is unwired," which every prior
--    disclosure already said) as `ISS-2026-151`, naming all 4 target
--    functions and all 17 affected fixture files, so the dedicated future
--    task this requires starts from an exact worklist rather than a fresh
--    investigation.
--
-- 8. (High, enterprise IAM/hardening lens, live-reproduced, new finding).
--    Impersonation-session audit linkage (`app.audit_logs.support_access_
--    grant_id`, added by IAE-029) is a real, correct mechanism with ZERO
--    live callers -- of ~1735 `capture_audit_event(...)` call sites across
--    the whole repository, none pass the 12th (optional)
--    `p_support_access_grant_id` argument. Live-reproduced: a real, audited
--    action performed during a genuinely open support session produced a
--    real `app.audit_logs` row, but `app.list_audit_logs_for_support_
--    session` returned zero rows for that session's own grant. Fixed at
--    the single, generic composition point rather than ~1735 call sites:
--    `app.capture_audit_event` itself now defaults `p_support_access_
--    grant_id` from a live lookup of the caller's own currently-open
--    support session (`app.current_support_session`) whenever the caller
--    omits it explicitly -- every existing call site is unaffected (same
--    parameter list, same defaults for the ordinary, non-support-session
--    case, where the lookup finds no row and behavior is unchanged).
--
-- 9. (Low, enterprise IAM/hardening lens, live-reproduced, new finding).
--    `app.set_support_entitlement`'s `enterprise_24_7` tier requires a real
--    escalation contact and P1 response time, but `contract_reference`
--    stays fully optional -- an ordinary tenant-side `SUP:Configure` actor
--    (ordinary tenant self-service, not a platform operator) can self-
--    declare a premium support tier with zero contract evidence, directly
--    undercutting `IAE-363.md` design decision 5's own "follows RPD-010 and
--    contract terms" claim. Fixed by requiring a real, non-empty `contract_
--    reference` for `enterprise_24_7`, structurally (a table CHECK
--    constraint mirroring the existing escalation-contact requirement) and
--    at the application layer.
--
-- ===========================================================================
-- Findings NOT changed here (disclosed, not code-fixed; see
-- docs/build-log/phase-09/IAE-365.md §7 and docs/runtime/KNOWN_ISSUES.md)
-- ===========================================================================
--
-- - `app.resolve_enterprise_idp_by_email_domain` is an unthrottled,
--   anonymous, cross-tenant SSO-configuration enumeration oracle -- a
--   currently dead-code path (zero live HTTP callers) whose real fix (a new
--   attempt-tracking table + per-caller rate limit) is disproportionate
--   schema work for a dormant, Low-severity surface. `ISS-2026-149`.
-- - IP allowlist enforcement (`app.assert_ip_allowed`, IAE-028) is real and
--   correct when called directly, but structurally unreachable from any
--   real business mutation -- a genuine fix requires threading a real HTTP
--   client IP through the TypeScript mutation layer and route handlers, a
--   materially larger cross-layer change than a migration-only fix, and
--   this repository's own "no half-finished implementation" principle
--   forbids a cosmetic partial wire-up. `ISS-2026-150` (sharpens `IAE-356.
--   md` §8's own existing, narrower disclosure).
-- - The RPD-023 step-up-authorization gate (`app.assert_current_step_up_
--   authorization`, IAE-027) remains real, correct, and unwired everywhere
--   -- the mandatory ruling above names 4 exact target functions and, from
--   this checkpoint's own attempted-then-reverted wiring, the exact 17
--   already-`VERIFIED` db-test fixture files (spanning 5 groups) a real fix
--   must also adapt. `ISS-2026-151`.
-- - The region/service-capability matrix (`IAE-033`) has zero run-time
--   consequence on any data-plane function (e.g. AI dispatch proceeds
--   identically for a region marked `ai_provider`-unsupported via an
--   accepted-risk exception) -- a real fix means editing `app.request_ai_
--   governed_action`, a different, already-`VERIFIED` capability (`IAE-
--   019`) from an earlier batch, for a risk that is currently theoretical
--   (no region infrastructure is actually deployed today, disclosed and
--   accepted). `ISS-2026-152`.
--
-- ===========================================================================
-- Fix 1: app.hold_risk_signal_entity self-review-then-hold guard
-- ===========================================================================

create or replace function app.hold_risk_signal_entity(
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

  -- IAE-037 Tier C fix (AI/prompt-injection lens): maker-checker separation
  -- -- the actor who confirmed the signal may not also be the one who holds
  -- it, mirroring the self-approval guard every other approval-gated Phase
  -- 9 flow already carries.
  if v_review.decided_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'risk_signal_hold_self_review_forbidden: identity % cannot hold an entity based on a risk signal they themselves confirmed', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
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

comment on function app.hold_risk_signal_entity is
  'IAE-024. IAE-037 Tier C fix: forbids the confirming reviewer from also being the holding actor (risk_signal_hold_self_review_forbidden), mirroring every other maker-checker gate in Phase 9. Never a write into the held entity''s own domain table (design decision 1).';

-- ===========================================================================
-- Fix 2: bounded recursion depth in three jsonb-walking functions
-- ===========================================================================

-- `CREATE OR REPLACE FUNCTION` does not replace a function whose own
-- parameter COUNT differs (even with a default on the new one) -- it
-- silently creates a second, overloaded function instead (the same gotcha
-- IAE-029's own app.capture_audit_event widening already documented and
-- worked around). An explicit DROP then CREATE is required for each of the
-- three masking functions below, with every pre-existing grant reissued
-- identically.
drop function app.redact_ai_output_payload_secret_shaped_values(jsonb);

create function app.redact_ai_output_payload_secret_shaped_values(p_payload jsonb, p_depth integer default 0)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
  v_element jsonb;
  v_result jsonb;
begin
  if p_payload is null then
    return null;
  end if;

  if p_depth > 32 then
    raise exception 'ai_output_payload_nesting_too_deep: output_payload exceeds the maximum supported nesting depth (32)' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key, v_value in select * from jsonb_each(p_payload) loop
      if v_key ~* '(secret|password|token|api_key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll)' then
        v_result := v_result || jsonb_build_object(v_key, '[REDACTED]'::text);
      else
        v_result := v_result || jsonb_build_object(v_key, app.redact_ai_output_payload_secret_shaped_values(v_value, p_depth + 1));
      end if;
    end loop;
    return v_result;
  elsif jsonb_typeof(p_payload) = 'array' then
    v_result := '[]'::jsonb;
    for v_element in select * from jsonb_array_elements(p_payload) loop
      v_result := v_result || jsonb_build_array(app.redact_ai_output_payload_secret_shaped_values(v_element, p_depth + 1));
    end loop;
    return v_result;
  else
    return p_payload;
  end if;
end;
$$;

comment on function app.redact_ai_output_payload_secret_shaped_values is
  'IAE-019, added by the merged Batch 4 Tier C review fix pass: recursively REDACTS (never rejects) a secret-shaped key''s own value in output_payload before app.record_ai_governed_request_outcome stores it. output_payload is provider-controlled, untrusted content -- rejecting it (the posture prompt_payload correctly keeps, since that side is caller-authored) would let an ordinary, legitimate AI response permanently strand a governed request at pending with its real HTTP outcome, model version, confidence and metered cost all lost. Mirrors the same key-name regex app.assert_ai_prompt_payload_has_no_secret_shaped_keys uses. IAE-037 Tier C fix: bounded to 32 levels of nesting (a hard cap raising a clean, named error) -- unbounded recursion crashed the whole call with a raw Postgres stack-depth error around ~400 levels, live-reproduced with ordinary, non-malicious deeply-nested content.';

grant execute on function app.redact_ai_output_payload_secret_shaped_values(jsonb, integer) to service_role;

drop function app.mask_optimization_sensitive_fields(jsonb, boolean);

create function app.mask_optimization_sensitive_fields(p_payload jsonb, p_can_view_sensitive boolean, p_depth integer default 0)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_result jsonb;
  v_key text;
  v_element jsonb;
  v_array_result jsonb;
begin
  if p_payload is null or p_can_view_sensitive then
    return p_payload;
  end if;

  if p_depth > 32 then
    raise exception 'optimization_scenario_payload_nesting_too_deep: payload exceeds the maximum supported nesting depth (32)' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key in select jsonb_object_keys(p_payload) loop
      if v_key ~* '(cost|margin|vendor|rate|price|wholesale)' then
        continue;
      end if;
      v_result := v_result || jsonb_build_object(v_key, app.mask_optimization_sensitive_fields(p_payload -> v_key, false, p_depth + 1));
    end loop;
    return v_result;
  end if;

  if jsonb_typeof(p_payload) = 'array' then
    v_array_result := '[]'::jsonb;
    for v_element in select value from jsonb_array_elements(p_payload) loop
      v_array_result := v_array_result || jsonb_build_array(app.mask_optimization_sensitive_fields(v_element, false, p_depth + 1));
    end loop;
    return v_array_result;
  end if;

  return p_payload;
end;
$$;

comment on function app.mask_optimization_sensitive_fields is
  'IAE-023 (design decision 2): recursively walks objects and arrays, stripping any key matching a cost/margin/vendor/rate/price-shaped pattern at ANY depth. IAE-037 Tier C fix: bounded to 32 levels of nesting -- unbounded recursion made this a permission-differentiated denial-of-service (a non-privileged viewer crashed on every read of an otherwise-valid, deeply-nested row; a privileged viewer, for whom masking is skipped, did not), live-reproduced with ordinary, non-malicious content around ~400 levels deep.';

grant execute on function app.mask_optimization_sensitive_fields(jsonb, boolean, integer) to service_role;

drop function app.mask_forecast_small_cohort_fields(jsonb, boolean);

create function app.mask_forecast_small_cohort_fields(p_payload jsonb, p_can_view_small_cohort boolean, p_depth integer default 0)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_result jsonb;
  v_key text;
  v_element jsonb;
  v_array_result jsonb;
begin
  if p_payload is null or p_can_view_small_cohort then
    return p_payload;
  end if;

  if p_depth > 32 then
    raise exception 'forecast_job_payload_nesting_too_deep: payload exceeds the maximum supported nesting depth (32)' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key in select jsonb_object_keys(p_payload) loop
      if v_key ~* '(customer|name|email|phone|account|address)' then
        continue;
      end if;
      v_result := v_result || jsonb_build_object(v_key, app.mask_forecast_small_cohort_fields(p_payload -> v_key, false, p_depth + 1));
    end loop;
    return v_result;
  end if;

  if jsonb_typeof(p_payload) = 'array' then
    v_array_result := '[]'::jsonb;
    for v_element in select value from jsonb_array_elements(p_payload) loop
      v_array_result := v_array_result || jsonb_build_array(app.mask_forecast_small_cohort_fields(v_element, false, p_depth + 1));
    end loop;
    return v_array_result;
  end if;

  return p_payload;
end;
$$;

comment on function app.mask_forecast_small_cohort_fields is
  'IAE-025: recursively walks objects and arrays, stripping any key matching a customer/PII-shaped pattern at ANY depth for a small-cohort-suppressed forecast. IAE-037 Tier C fix: bounded to 32 levels of nesting, same rationale and shape as app.mask_optimization_sensitive_fields''s own identical fix.';

grant execute on function app.mask_forecast_small_cohort_fields(jsonb, boolean, integer) to service_role;

-- ===========================================================================
-- Fix 3: reject NaN/Infinity provider cost
-- ===========================================================================

create or replace function app.record_ai_governed_request_outcome(
  p_request_id uuid,
  p_status text,
  p_output_payload jsonb,
  p_confidence_label text,
  p_model_version text,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
as $$
declare
  v_request app.ai_governed_requests;
  v_billed_amount numeric;
  v_row app.ai_governed_requests;
  v_current_status text;
begin
  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('succeeded', 'failed') then
    raise exception 'ai_governed_request_invalid_status: % is not one of succeeded/failed', p_status using errcode = 'check_violation';
  end if;
  -- IAE-037 Tier C fix (defense-in-depth): `p_provider_unit_cost_amount <
  -- 0` alone admits Postgres NaN (NaN < 0 is false) and real Infinity,
  -- either of which would silently poison a tenant-wide billing SUM.
  -- Postgres numeric NaN does NOT follow IEEE-754 self-inequality (`NaN =
  -- NaN` is TRUE in Postgres, unlike floating point) -- it instead sorts as
  -- strictly GREATER than Infinity, so `x >= 'Infinity'::numeric` is the
  -- correct catch-all for both real Infinity and NaN alike (the same
  -- established idiom Group 8's own IAE-035 RPO/RTO sanity check already
  -- uses, `x < 'Infinity'::numeric` as the upper bound of the allowed
  -- range).
  if p_provider_unit_cost_amount is not null and (
    p_provider_unit_cost_amount < 0
    or p_provider_unit_cost_amount >= 'infinity'::numeric
  ) then
    raise exception 'ai_governed_request_invalid_cost_amount: provider_unit_cost_amount must be a real, non-negative, finite number' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  -- Tier C fix (THE Critical finding of this review): the pending-only
  -- transition must be the ATOMIC step itself -- live-reproduced with 6
  -- genuinely concurrent callers on ONE pending request under the prior
  -- SELECT-then-UPDATE shape: all 6 won, zero were rejected, silently
  -- destroying a human-APPROVED AI output (output_payload wiped,
  -- billed_amount corrupted) while approval_status stayed 'approved',
  -- pointing at nothing. WHERE status = 'pending' here is what actually
  -- prevents a double-transition; a losing concurrent caller now hits
  -- v_row.id is null below and gets the same named error, never a silent
  -- overwrite. output_payload is redacted (never rejected) -- it is
  -- provider-controlled, untrusted content; rejecting it here would strand
  -- the request permanently (see app.redact_ai_output_payload_secret_
  -- shaped_values''s own comment).
  update app.ai_governed_requests
  set status = p_status, output_payload = app.redact_ai_output_payload_secret_shaped_values(p_output_payload), confidence_label = p_confidence_label, model_version = p_model_version,
      provider_unit_cost_amount = p_provider_unit_cost_amount, currency = p_currency, billed_amount = v_billed_amount,
      error_message = p_error_message, completed_at = now()
  where id = p_request_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    select status into v_current_status from app.ai_governed_requests where id = p_request_id;
    raise exception 'ai_governed_request_not_pending: request % is % not pending', p_request_id, v_current_status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ai_governed_request_outcome',
    'app.ai_governed_requests', v_row.id, case when p_status = 'succeeded' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('status', v_row.status, 'confidence_label', v_row.confidence_label)
  );

  return v_row;
end;
$$;

comment on function app.record_ai_governed_request_outcome is
  'IAE-019, hardened by the merged Batch 4 Tier C review (the single most severe finding of this review): the pending-only transition is now the atomic UPDATE ... WHERE status = ''pending'' step itself, closing a live-reproduced race where every concurrent caller could win and silently destroy a human-approved AI output. output_payload is now redacted (app.redact_ai_output_payload_secret_shaped_values), never rejected -- it is untrusted provider content, and rejecting it would permanently strand the request. billed_amount computed server-side via app.compute_provider_billed_amount (RPD-028), never trusted from the caller. IAE-037 Tier C fix: provider_unit_cost_amount now also rejects NaN and Infinity, not just negative values.';

-- ===========================================================================
-- Fix 4: app.rotate_api_key rejects rotating an already-expired key
-- ===========================================================================

create or replace function app.rotate_api_key(
  p_key_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_old app.api_keys;
  v_new_raw_key text;
  v_new_key_prefix text;
  v_new_key_hash text;
  v_new_key app.api_keys;
  v_new_expiry timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Tier C Batch 3 fix (finding 3): FOR UPDATE serializes concurrent/
  -- retried rotations of the SAME source key.
  select * into v_old from app.api_keys where app.api_keys.id = p_key_id for update;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_key_manage_authority(v_old.tenant_id, v_old.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_old.status <> 'active' then
    raise exception 'api_key_not_active: key % is %, only an active key may be rotated', p_key_id, v_old.status
      using errcode = 'check_violation';
  end if;

  -- IAE-037 Tier C fix (API/access-leakage lens, live-reproduced):
  -- app.authenticate_api_key's own lazy status='expired' transition is
  -- rolled back by its own subsequent raise, so the stored status column
  -- can read 'active' long after the key has genuinely expired -- the
  -- check above alone is not reliable. Independently re-check real-time
  -- expiry here rather than trusting that column, closing the "rotate an
  -- expired key -> mint an already-dead successor key" defect: the
  -- successor previously inherited the OLD, already-past expires_at
  -- verbatim (below), so it was non-functional from its very first call
  -- with no error at rotation time.
  if v_old.expires_at is not null and v_old.expires_at <= now() then
    raise exception 'api_key_expired: key % has expired -- rotate is not available for an expired key, mint a new key instead', p_key_id
      using errcode = 'check_violation';
  end if;

  -- Tier C Batch 3 fix (finding 3): status alone cannot guard against a
  -- second rotation, since a normal overlap-window rotation deliberately
  -- leaves the old key status='active'. superseded_by_key_id is the real
  -- guard, checked and set under the SAME row lock acquired above.
  if v_old.superseded_by_key_id is not null then
    raise exception 'api_key_already_rotated: key % was already rotated to %, rotate the successor key instead', p_key_id, v_old.superseded_by_key_id
      using errcode = 'check_violation';
  end if;

  if p_overlap_minutes is null or p_overlap_minutes < 0 or p_overlap_minutes > 10080 then
    raise exception 'api_key_invalid_overlap_minutes: % must be between 0 and 10080 (7 days)', p_overlap_minutes
      using errcode = 'check_violation';
  end if;

  v_new_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_new_key_prefix := substring(v_new_raw_key from 1 for 12);
  v_new_key_hash := encode(digest(v_new_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id, vendor_master_record_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id, v_old.customer_account_id, v_old.customer_actor_auth_user_id, v_old.vendor_master_record_id)
  returning * into v_new_key;

  v_new_expiry := now() + (p_overlap_minutes::text || ' minutes')::interval;

  update app.api_keys
  set status = case when p_overlap_minutes = 0 then 'revoked' else v_old.status end,
      revoked_at = case when p_overlap_minutes = 0 then now() else revoked_at end,
      revoked_reason = case when p_overlap_minutes = 0 then 'rotated' else revoked_reason end,
      expires_at = case when v_old.expires_at is not null and v_old.expires_at < v_new_expiry then v_old.expires_at else v_new_expiry end,
      superseded_by_key_id = v_new_key.id
  where app.api_keys.id = v_old.id;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_api_key',
    'app.api_keys', v_new_key.id, 'success', null,
    jsonb_build_object('id', v_old.id, 'key_prefix', v_old.key_prefix),
    jsonb_build_object('id', v_new_key.id, 'key_prefix', v_new_key.key_prefix, 'overlap_minutes', p_overlap_minutes)
  );

  return query select v_new_key.id, v_new_key.tenant_id, v_new_key.name, v_new_key.key_prefix, v_new_key.scopes, v_new_key.status, v_new_key.rate_limit_per_minute, v_new_key.expires_at, v_new_key.created_at, v_new_raw_key;
end;
$$;

comment on function app.rotate_api_key is
  'PLT-129, extended by IAE-010, IAE-011, Tier C Batch 3 fix: overlap-window rotation (0 = immediate revoke), row-locked and superseded_by_key_id-guarded against a second concurrent/retried rotation of the same source key (status alone cannot guard this, since an overlap-window rotation deliberately leaves the old key active). The rotated key carries customer/vendor scoping columns forward. Also calls app.assert_actor_is_session_identity first. IAE-037 Tier C fix: independently re-checks real-time expiry (expires_at <= now()) rather than trusting the stored status column alone, which app.authenticate_api_key''s own lazy transition can leave stale -- closes a live-reproduced dead-on-arrival successor key defect.';

-- ===========================================================================
-- Fix 5: app.record_webhook_delivery_attempt row lock
-- ===========================================================================

create or replace function app.record_webhook_delivery_attempt(
  p_delivery_id uuid,
  p_status text,
  p_http_status_code integer,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_delivery app.webhook_deliveries;
  v_endpoint app.webhook_endpoints;
  v_attempt_number integer;
  v_updated app.webhook_deliveries;
  v_new_failure_count integer;
begin
  -- IAE-037 Tier C fix (queue/idempotency-stress lens, live-reproduced with
  -- genuine concurrent processes): FOR UPDATE serializes concurrent
  -- attempt-recording calls for THIS delivery only, mirroring the identical,
  -- already-established fix on the sibling app.record_notification_
  -- delivery_attempt (IAE-014) -- without this lock, a genuine 'success'
  -- racing a 'failed' recording for the same decisive attempt slot could
  -- crash the loser with a raw unique-constraint violation and, in some
  -- interleavings, permanently discard the genuinely successful delivery's
  -- own evidence while marking the delivery dead_letter.
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id for update;
  if not found then
    raise exception 'webhook_delivery_not_found: no delivery %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if v_delivery.status in ('delivered', 'dead_letter') then
    raise exception 'webhook_delivery_already_terminal: delivery % is already %, no further attempts may be recorded', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  if not (p_status = any (array['success', 'failed'])) then
    raise exception 'webhook_invalid_attempt_status: % is not one of success/failed', p_status
      using errcode = 'check_violation';
  end if;

  select * into v_endpoint from app.webhook_endpoints where id = v_delivery.webhook_endpoint_id;

  v_attempt_number := v_delivery.attempts + 1;

  insert into app.webhook_delivery_attempts (webhook_delivery_id, attempt_number, status, http_status_code, error_message)
  values (p_delivery_id, v_attempt_number, p_status, p_http_status_code, p_error_message);

  if p_status = 'success' then
    update app.webhook_deliveries
    set attempts = v_attempt_number, status = 'delivered', next_attempt_at = null
    where id = p_delivery_id
    returning * into v_updated;

    update app.webhook_endpoints set consecutive_failure_count = 0 where id = v_endpoint.id;
  else
    v_new_failure_count := v_endpoint.consecutive_failure_count + 1;

    update app.webhook_deliveries
    set attempts = v_attempt_number,
        status = case when v_attempt_number >= v_delivery.max_attempts then 'dead_letter' else v_delivery.status end,
        next_attempt_at = case when v_attempt_number >= v_delivery.max_attempts then null else now() + (power(2, v_attempt_number)::text || ' minutes')::interval end
    where id = p_delivery_id
    returning * into v_updated;

    update app.webhook_endpoints
    set consecutive_failure_count = v_new_failure_count,
        status = case when v_new_failure_count >= 10 then 'disabled' else v_endpoint.status end,
        auto_disabled_at = case when v_new_failure_count >= 10 and v_endpoint.status <> 'disabled' then now() else auto_disabled_at end,
        disabled_reason = case when v_new_failure_count >= 10 and v_endpoint.status <> 'disabled' then 'consecutive_failure_threshold_exceeded' else disabled_reason end
    where id = v_endpoint.id;
  end if;

  perform app.capture_audit_event(
    v_delivery.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_webhook_delivery_attempt',
    'app.webhook_deliveries', v_updated.id,
    case when p_status = 'success' then 'success' else 'failure' end,
    p_error_message, to_jsonb(v_delivery), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.record_webhook_delivery_attempt is
  'PLT-129, extended by IAE-012: real, tested delivery adapter -- exponential backoff on transient failure, dead_letter once max_attempts is reached, endpoint auto-disables at 10 consecutive failures (ADR-0011), a single success resets that counter. IAE-037 Tier C fix: the initial read now locks the delivery row (FOR UPDATE), mirroring app.record_notification_delivery_attempt''s own identical fix -- closes a live-reproduced race where a genuine success racing a failure for the same attempt slot could crash with a raw constraint violation and, in some interleavings, permanently discard the successful delivery''s own evidence.';

-- ===========================================================================
-- Fix 6: idempotency-key race guard on the five Group 6 AI-job request/
-- submit functions
-- ===========================================================================

create or replace function app.submit_ocr_document_job(
  p_tenant_id uuid,
  p_file_id uuid,
  p_document_type_hint text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.ocr_document_jobs;
  v_file app.files;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ocr_document_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_document_type_hint not in ('logistics', 'finance', 'hr', 'ticket', 'other') then
    raise exception 'ocr_document_job_invalid_type_hint: % is not one of logistics/finance/hr/ticket/other', p_document_type_hint
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.ocr_document_jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.file_id is distinct from p_file_id or v_existing.document_type_hint is distinct from p_document_type_hint then
      raise exception 'idempotency_key_conflict: key % was already used for a different OCR job', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_file from app.files where id = p_file_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'ocr_document_job_file_not_found: % is not a known file for tenant %', p_file_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_file.lifecycle_status <> 'active' then
    raise exception 'ocr_document_job_file_not_active: file % is % not active', p_file_id, v_file.lifecycle_status using errcode = 'check_violation';
  end if;

  if v_file.malware_scan_status <> 'clean' then
    raise exception 'ocr_document_job_file_not_scanned: file % has malware_scan_status % -- unscanned/quarantined files never enter OCR', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_file.uploaded_by_auth_user_id, v_file.shared_org_unit_ids, v_file.customer_account_ref) then
    raise exception 'insufficient_authority: identity % may not access file %', p_actor_auth_user_id, p_file_id
      using errcode = 'insufficient_privilege';
  end if;

  -- IAE-037 Tier C fix (queue/idempotency-stress lens, live-reproduced with
  -- 20 genuinely concurrent processes): the check-then-insert above is not
  -- atomic. Mirrors this repository's own established check-then-insert-
  -- with-handler shape (app.enqueue_job).
  begin
    insert into app.ocr_document_jobs (
      tenant_id, file_id, document_type_hint, status, requested_by_auth_user_id, requested_by, idempotency_key
    ) values (
      p_tenant_id, p_file_id, p_document_type_hint, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_existing from app.ocr_document_jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.file_id is distinct from p_file_id or v_existing.document_type_hint is distinct from p_document_type_hint then
        raise exception 'idempotency_key_conflict: key % was already used for a different OCR job', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_ocr_document_job',
    'app.ocr_document_jobs', v_row.id, 'success', null, null,
    jsonb_build_object('file_id', v_row.file_id, 'document_type_hint', v_row.document_type_hint)
  );

  return v_row;
end;
$$;

comment on function app.submit_ocr_document_job is
  'IAE-021: the entry point the TS orchestration client calls before dispatching a real governed AI request. Never writes to app.ai_governed_requests itself. IAE-037 Tier C fix: the insert is now wrapped in a unique_violation handler that re-selects and content-checks, closing a live-reproduced race where a genuine client retry got a raw Postgres error instead of the documented idempotent replay.';

create or replace function app.request_optimization_scenario(
  p_tenant_id uuid,
  p_scope_type text,
  p_input_snapshot jsonb,
  p_constraint_set jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.optimization_scenarios;
  v_row app.optimization_scenarios;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_scope_type not in ('route', 'dispatch', 'warehouse_slotting', 'picking') then
    raise exception 'optimization_scenario_invalid_scope_type: % is not one of route/dispatch/warehouse_slotting/picking', p_scope_type
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.optimization_scenarios where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.scope_type is distinct from p_scope_type then
      raise exception 'idempotency_key_conflict: key % was already used for a different scope_type', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if not app.validate_config_value(p_input_snapshot) then
    raise exception 'optimization_scenario_invalid_input_snapshot: input_snapshot failed the structural safety check' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(p_constraint_set) then
    raise exception 'optimization_scenario_invalid_constraint_set: constraint_set failed the structural safety check' using errcode = 'check_violation';
  end if;

  -- IAE-037 Tier C fix: same check-then-insert race guard as
  -- app.submit_ocr_document_job above.
  begin
    insert into app.optimization_scenarios (
      tenant_id, scope_type, input_snapshot, constraint_set, status, requested_by_auth_user_id, requested_by, idempotency_key
    ) values (
      p_tenant_id, p_scope_type, p_input_snapshot, p_constraint_set, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_existing from app.optimization_scenarios where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.scope_type is distinct from p_scope_type then
        raise exception 'idempotency_key_conflict: key % was already used for a different scope_type', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_optimization_scenario',
    'app.optimization_scenarios', v_row.id, 'success', null, null, jsonb_build_object('scope_type', v_row.scope_type)
  );

  return v_row;
end;
$$;

comment on function app.request_optimization_scenario is
  'IAE-023: the entry point the TS orchestration client calls before dispatching a real governed AI request. IAE-037 Tier C fix: the insert is now wrapped in a unique_violation handler that re-selects and content-checks, closing a live-reproduced race on the idempotency key.';

create or replace function app.request_risk_signal(
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

  -- IAE-037 Tier C fix: same check-then-insert race guard as
  -- app.submit_ocr_document_job above.
  begin
    insert into app.risk_signals (
      tenant_id, risk_domain, entity_type, entity_id, input_snapshot, status, requested_by_auth_user_id, requested_by, idempotency_key
    ) values (
      p_tenant_id, p_risk_domain, p_entity_type, p_entity_id, p_input_snapshot, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_existing from app.risk_signals where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.entity_type is distinct from p_entity_type or v_existing.entity_id is distinct from p_entity_id then
        raise exception 'idempotency_key_conflict: key % was already used for a different entity', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_risk_signal',
    'app.risk_signals', v_row.id, 'success', null, null, jsonb_build_object('risk_domain', v_row.risk_domain, 'entity_type', v_row.entity_type)
  );

  return v_row;
end;
$$;

comment on function app.request_risk_signal is
  'IAE-024: the entry point the TS orchestration client calls before dispatching a real governed AI request. IAE-037 Tier C fix: the insert is now wrapped in a unique_violation handler that re-selects and content-checks, closing a live-reproduced race on the idempotency key.';

create or replace function app.request_forecast_job(
  p_tenant_id uuid,
  p_forecast_type text,
  p_scenario_label text,
  p_scope_snapshot jsonb,
  p_feature_snapshot jsonb,
  p_horizon_days integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.forecast_jobs;
  v_row app.forecast_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_forecast_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_forecast_type not in ('demand', 'revenue', 'churn', 'vendor_recommendation', 'predictive_maintenance') then
    raise exception 'forecast_job_invalid_type: % is not one of demand/revenue/churn/vendor_recommendation/predictive_maintenance', p_forecast_type
      using errcode = 'check_violation';
  end if;
  if p_horizon_days is null or p_horizon_days <= 0 or p_horizon_days > 1095 then
    raise exception 'forecast_job_invalid_horizon: horizon_days must be between 1 and 1095, got %', p_horizon_days using errcode = 'check_violation';
  end if;

  select * into v_existing from app.forecast_jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.forecast_type is distinct from p_forecast_type then
      raise exception 'idempotency_key_conflict: key % was already used for a different forecast_type', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if not app.validate_config_value(p_scope_snapshot) then
    raise exception 'forecast_job_invalid_scope_snapshot: scope_snapshot failed the structural safety check' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(p_feature_snapshot) then
    raise exception 'forecast_job_invalid_feature_snapshot: feature_snapshot failed the structural safety check' using errcode = 'check_violation';
  end if;

  -- IAE-037 Tier C fix: same check-then-insert race guard as
  -- app.submit_ocr_document_job above.
  begin
    insert into app.forecast_jobs (
      tenant_id, forecast_type, scenario_label, scope_snapshot, feature_snapshot, horizon_days,
      status, requested_by_auth_user_id, requested_by, idempotency_key
    ) values (
      p_tenant_id, p_forecast_type, coalesce(nullif(trim(p_scenario_label), ''), 'baseline'), p_scope_snapshot, p_feature_snapshot, p_horizon_days,
      'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_existing from app.forecast_jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.forecast_type is distinct from p_forecast_type then
        raise exception 'idempotency_key_conflict: key % was already used for a different forecast_type', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_forecast_job',
    'app.forecast_jobs', v_row.id, 'success', null, null, jsonb_build_object('forecast_type', v_row.forecast_type, 'scenario_label', v_row.scenario_label)
  );

  return v_row;
end;
$$;

comment on function app.request_forecast_job is
  'IAE-025: the entry point the TS orchestration client calls before dispatching a real governed AI request. IAE-037 Tier C fix: the insert is now wrapped in a unique_violation handler that re-selects and content-checks, closing a live-reproduced race on the idempotency key.';

create or replace function app.request_eta_prediction(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_feature_snapshot jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_predictions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.eta_predictions;
  v_shipment app.shipment_orders;
  v_projection app.shipment_milestone_projections;
  v_is_terminal boolean;
  v_row app.eta_predictions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_eta_prediction_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_eta_prediction_enabled_for_tenant(p_tenant_id) then
    raise exception 'eta_prediction_disabled_for_tenant: tenant % has disabled predictive ETA', p_tenant_id using errcode = 'check_violation';
  end if;

  select * into v_existing from app.eta_predictions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.shipment_order_id is distinct from p_shipment_order_id then
      raise exception 'idempotency_key_conflict: key % was already used for a different shipment', p_idempotency_key using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'eta_prediction_shipment_not_found: % is not a known shipment order for tenant %', p_shipment_order_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status <> 'confirmed' then
    raise exception 'eta_prediction_shipment_not_eligible: shipment % is % -- only confirmed shipments are eligible', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_shipment.owner_user_id, case when v_shipment.org_unit_id is null then '{}'::uuid[] else array[v_shipment.org_unit_id] end, null) then
    raise exception 'insufficient_authority: identity % may not access shipment %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = p_shipment_order_id;
  if found and v_projection.last_milestone_code is not null then
    select is_terminal into v_is_terminal from app.milestone_codes where code = v_projection.last_milestone_code;
    if coalesce(v_is_terminal, false) then
      raise exception 'eta_prediction_shipment_already_delivered: shipment % has already reached a terminal milestone', p_shipment_order_id using errcode = 'check_violation';
    end if;
  end if;

  if not app.validate_config_value(p_feature_snapshot) then
    raise exception 'eta_prediction_invalid_feature_snapshot: feature_snapshot failed the structural safety check' using errcode = 'check_violation';
  end if;

  -- IAE-037 Tier C fix: same check-then-insert race guard as
  -- app.submit_ocr_document_job above (disclosed as code-analysis-only in
  -- the review that found this class -- not itself live-fired there, since
  -- reaching a confirmed shipment order requires the full booking
  -- pipeline; the shape is byte-for-byte identical to its four already
  -- live-reproduced siblings).
  begin
    insert into app.eta_predictions (
      tenant_id, shipment_order_id, feature_snapshot, status, requested_by_auth_user_id, requested_by, idempotency_key
    ) values (
      p_tenant_id, p_shipment_order_id, p_feature_snapshot, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_existing from app.eta_predictions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.shipment_order_id is distinct from p_shipment_order_id then
        raise exception 'idempotency_key_conflict: key % was already used for a different shipment', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_eta_prediction',
    'app.eta_predictions', v_row.id, 'success', null, null, jsonb_build_object('shipment_order_id', v_row.shipment_order_id)
  );

  return v_row;
end;
$$;

comment on function app.request_eta_prediction is
  'IAE-022: the entry point the TS orchestration client calls before dispatching a real governed AI request. Refuses a non-confirmed or already-terminal shipment, and while the tenant has disabled prediction (design decisions 3, 4). Idempotent per (tenant, idempotency key), enforced by a real unique constraint. IAE-037 Tier C fix: the insert is now wrapped in a unique_violation handler that re-selects and content-checks, closing the same idempotency-key race its four sibling Group 6 request functions were live-confirmed to have.';

-- ===========================================================================
-- Fix 7: capture_audit_event defaults support_access_grant_id from a live
-- session lookup
-- ===========================================================================

create or replace function app.capture_audit_event(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_action text,
  p_resource_type text,
  p_resource_id uuid,
  p_result text,
  p_reason text default null,
  p_before_value jsonb default null,
  p_after_value jsonb default null,
  p_correlation_id uuid default null,
  p_support_access_grant_id uuid default null
)
returns app.audit_logs
language plpgsql
as $$
declare
  v_row app.audit_logs;
  v_grant_id uuid;
  v_session app.support_access_sessions;
begin
  v_grant_id := p_support_access_grant_id;

  -- IAE-037 Tier C fix (enterprise IAM/hardening lens, live-reproduced): the
  -- impersonation-audit linkage IAE-029 added was a real, correct mechanism
  -- with ZERO live callers -- every real mutation across the whole
  -- repository always omitted this optional parameter. Rather than editing
  -- ~1735 call sites, default it here, at the single generic composition
  -- point, from the caller's own currently-open support session whenever
  -- they did not pass it explicitly. Ordinary calls with no open support
  -- session (the overwhelming majority) see v_session as no row found and
  -- behavior is completely unchanged.
  if v_grant_id is null and p_tenant_id is not null and p_actor_auth_user_id is not null then
    select * into v_session from app.current_support_session(p_tenant_id, p_actor_auth_user_id);
    if found then
      v_grant_id := v_session.grant_id;
    end if;
  end if;

  insert into app.audit_logs (
    correlation_id, tenant_id, actor_auth_user_id, actor_label, action,
    resource_type, resource_id, result, reason, before_value, after_value,
    support_access_grant_id
  )
  values (
    coalesce(p_correlation_id, gen_random_uuid()), p_tenant_id, p_actor_auth_user_id, p_actor_label, p_action,
    p_resource_type, p_resource_id, p_result, p_reason,
    app.redact_audit_payload(p_before_value), app.redact_audit_payload(p_after_value),
    v_grant_id
  )
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app.capture_audit_event is
  'IAE-029: widened, backward-compatibly (drop + create, not create or replace -- see the original migration''s own header), with one trailing optional parameter (p_support_access_grant_id) -- every pre-existing 11-arg call site across the whole repository is unaffected. Still the single real write path for app.audit_logs; still unconditionally redacts before_value/after_value (PLT-116). IAE-037 Tier C fix: when the caller omits p_support_access_grant_id, it is now defaulted from the actor''s own currently-open app.current_support_session for that tenant, closing a live-reproduced gap where the linkage column was real but never populated by any of the ~1735 real call sites.';

-- ===========================================================================
-- Fix 8: enterprise_24_7 support entitlement requires a real contract
-- reference
-- ===========================================================================

alter table app.support_entitlements
  add constraint support_entitlements_24_7_requires_contract_check check (
    tier <> 'enterprise_24_7' or (contract_reference is not null and length(trim(contract_reference)) > 0)
  );

create or replace function app.set_support_entitlement(
  p_tenant_id uuid,
  p_tier text,
  p_contract_reference text,
  p_escalation_contact_name text,
  p_escalation_contact_email text,
  p_p1_response_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.support_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.support_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tier not in ('standard', 'enterprise_24_7') then
    raise exception 'support_entitlement_invalid_tier: %', p_tier using errcode = 'check_violation';
  end if;
  if p_tier = 'enterprise_24_7' and (coalesce(trim(p_escalation_contact_email), '') = '' or p_p1_response_minutes is null or p_p1_response_minutes <= 0) then
    raise exception 'support_entitlement_24_7_requires_escalation: a real escalation_contact_email and a positive p1_response_minutes are required for enterprise_24_7'
      using errcode = 'check_violation';
  end if;
  -- IAE-037 Tier C fix (enterprise IAM/hardening lens): an ordinary
  -- tenant-side SUP:Configure actor could previously self-declare
  -- enterprise_24_7 with zero contract evidence, undercutting this
  -- capability's own "follows RPD-010 and contract terms" claim.
  if p_tier = 'enterprise_24_7' and coalesce(trim(p_contract_reference), '') = '' then
    raise exception 'support_entitlement_24_7_requires_contract_reference: a real, non-empty contract_reference is required for enterprise_24_7'
      using errcode = 'check_violation';
  end if;

  insert into app.support_entitlements (tenant_id, tier, contract_reference, escalation_contact_name, escalation_contact_email, p1_response_minutes, created_by)
  values (p_tenant_id, p_tier, p_contract_reference, p_escalation_contact_name, p_escalation_contact_email, p_p1_response_minutes, p_actor_label)
  on conflict (tenant_id) do update
    set tier = excluded.tier, contract_reference = excluded.contract_reference, escalation_contact_name = excluded.escalation_contact_name,
        escalation_contact_email = excluded.escalation_contact_email, p1_response_minutes = excluded.p1_response_minutes
  returning * into v_entitlement;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_support_entitlement',
    'app.support_entitlements', v_entitlement.id, 'success', null, null, jsonb_build_object('tier', v_entitlement.tier)
  );

  return v_entitlement;
end;
$$;

comment on function app.set_support_entitlement is
  'IAE-035: enterprise_24_7 REQUIRES a real escalation_contact_email, a real positive p1_response_minutes, AND (IAE-037 Tier C fix) a real, non-empty contract_reference -- Prompt 363''s own "Enterprise 24/7/P1 support follows RPD-010 and contract terms" enforced structurally, never a hollow tier claim, both at the table CHECK constraint level and the application layer.';

-- ===========================================================================
-- Grants -- every function above is a create-or-replace of an unchanged
-- signature (Fix 9's table constraint carries no grant of its own); nothing
-- new to grant.
-- ===========================================================================

revoke execute on all functions in schema app from public;
