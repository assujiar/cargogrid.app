-- Intelligence, Automation and Enterprise Expansion: Forecasting and
-- Recommendation Assistance (IAE-025, CG-S14-IAE-025, Prompt 353). Fifth
-- and final capability of Group 6 ("Further AI-Assisted Capabilities",
-- Prompts 349-353). Depends on IAE-019 (AI Governance Provider Boundary,
-- VERIFIED) exactly as IAE-020/021/022/023/024 already do.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Forecasts can never create commitments, budgets, vendor awards,
--    maintenance orders or customer actions autonomously -- structurally.**
--    No function in this migration writes to any existing Finance/
--    Commercial/Procurement/Operations domain table.
--    app.record_forecast_planning_decision records a manager's own
--    planning-decision NOTE (free text) -- never a write into any real
--    commitment/budget/vendor-award/maintenance-order table, mirroring
--    IAE-023's own "acknowledge, never mutate" boundary and IAE-024's own
--    "self-contained governance record" boundary.
-- 2. **A small-inference-cohort control is a real, structural mask, not a
--    permission-tiered convenience** (business rule "small-cohort and
--    customer-sensitive inference controls apply"). Whenever the governed
--    request's own output reports a cohortSize below 10 (a disclosed,
--    fixed k-anonymity-style threshold -- this checkpoint's own choice,
--    not a source-cited statutory figure), app.get_forecast_job masks any
--    customer/name/email/phone/account/address-shaped key in the output
--    payload at ANY nesting depth, mirroring IAE-023's own recursive
--    app.mask_optimization_sensitive_fields shape, reusing AI:Approve as
--    the "may see small-cohort detail anyway" elevation tier.
-- 3. **Insufficient data is a real, distinct terminal status, never a
--    fabricated forecast** (business rule "insufficient data produces a
--    no-forecast state with data-quality recommendations", Prompt 353
--    §22). app.record_forecast_job_outcome reads the governed request's
--    own insufficientData flag and lands the job in
--    'insufficient_data' with a defensively-extracted data_quality_note --
--    never in 'succeeded' with a fabricated predicted_value.
-- 4. **predicted_value/cohort_size/data_quality_note extraction is
--    defensive**, mirroring IAE-022's app._parse_eta_timestamp /
--    IAE-024's app._parse_risk_score exactly -- malformed input yields
--    null fields, never a crash or a fabricated value.
-- 5. **Feedback and planning decisions are recorded separately from
--    evaluation** -- app.forecast_job_feedback (a manager's own
--    usefulness judgment + planning note) and app.forecast_job_evaluations
--    (real observed-outcome accuracy/drift evidence) are two genuinely
--    distinct tables/writers, mirroring every prior AI-assisted
--    capability's own "N distinct tables, N distinct writers" shape.
-- 6. AI dispatch reuses dispatchAiGovernedRequest (IAE-019) unmodified --
--    feature_code = 'forecasting_recommendation', correlation_record_type
--    = 'forecast_job' (self-correlated: a forecast's own scope can span
--    many customers/vendors/SKUs, so -- like IAE-023's optimization
--    scenario -- there is no single stable external entity to correlate
--    to instead).
-- 7. No new entitlement module -- the AI module's own comment (IAE-019)
--    already names forecasting/recommendation as one of its owned
--    features.
-- 8-10. Proactively applied lessons from IAE-020/021/022/023/024:
--    SECURITY DEFINER + assert_actor_is_session_identity on every
--    authenticated-granted function; explicit table aliases in every
--    RETURNS TABLE; IS DISTINCT FROM for every nullable correlation
--    cross-check; every RAISE % placeholder carries a real argument
--    (IAE-024's own self-caught compilation-time bug, applied
--    proactively here).
-- 11. Per ERR-2026-004: explicit revoke execute on all functions in
--    schema app from public.

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_forecast_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Defensive extraction helpers (design decisions 3, 4)
-- ===========================================================================

create function app._parse_forecast_numeric(p_payload jsonb)
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
  return v_result;
end;
$$;

create function app._parse_forecast_int(p_payload jsonb)
returns integer
language plpgsql
immutable
as $$
declare
  v_result integer;
begin
  if p_payload is null or jsonb_typeof(p_payload) not in ('number', 'string') then
    return null;
  end if;
  begin
    v_result := round((p_payload #>> '{}')::numeric)::integer;
  exception when others then
    return null;
  end;
  if v_result < 0 then
    return null;
  end if;
  return v_result;
end;
$$;

create function app._parse_forecast_text(p_payload jsonb, p_max_length integer default 2000)
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
  if length(v_result) > p_max_length then
    return left(v_result, p_max_length);
  end if;
  return v_result;
end;
$$;

create function app._parse_forecast_bool(p_payload jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_result boolean;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'boolean' then
    return false;
  end if;
  begin
    v_result := (p_payload #>> '{}')::boolean;
  exception when others then
    return false;
  end;
  return v_result;
end;
$$;

comment on function app._parse_forecast_bool is 'IAE-025 (design decision 3): defensive boolean extraction (used for insufficientData) -- only a genuine JSON boolean is accepted; anything else (including a prompt-injection-shaped string) yields false, never a crash.';
comment on function app._parse_forecast_numeric is 'IAE-025 (design decision 4): defensive numeric extraction -- malformed input yields NULL, never a crash or a fabricated value.';
comment on function app._parse_forecast_int is 'IAE-025 (design decision 4): defensive non-negative integer extraction (used for cohort_size) -- malformed/negative input yields NULL.';
comment on function app._parse_forecast_text is 'IAE-025 (design decision 3): defensive, length-bounded text extraction (used for data_quality_note) -- never trusted verbatim beyond a hard length cap.';

-- ===========================================================================
-- Small-cohort masking (design decision 2) -- mirrors IAE-023's own
-- app.mask_optimization_sensitive_fields recursive shape, different regex.
-- ===========================================================================

create function app.mask_forecast_small_cohort_fields(p_payload jsonb, p_can_view_small_cohort boolean)
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

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key in select jsonb_object_keys(p_payload) loop
      if v_key ~* '(customer|name|email|phone|account|address)' then
        continue;
      end if;
      v_result := v_result || jsonb_build_object(v_key, app.mask_forecast_small_cohort_fields(p_payload -> v_key, false));
    end loop;
    return v_result;
  end if;

  if jsonb_typeof(p_payload) = 'array' then
    v_array_result := '[]'::jsonb;
    for v_element in select value from jsonb_array_elements(p_payload) loop
      v_array_result := v_array_result || jsonb_build_array(app.mask_forecast_small_cohort_fields(v_element, false));
    end loop;
    return v_array_result;
  end if;

  return p_payload;
end;
$$;

-- ===========================================================================
-- Core job table
-- ===========================================================================

create table app.forecast_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  forecast_type text not null,
  scenario_label text not null default 'baseline',
  scope_snapshot jsonb not null,
  feature_snapshot jsonb not null,
  horizon_days integer not null,
  ai_governed_request_id uuid unique references app.ai_governed_requests (id),
  status text not null default 'pending',
  predicted_value numeric,
  cohort_size integer,
  is_small_cohort_suppressed boolean not null default false,
  data_quality_note text,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint forecast_jobs_forecast_type_check check (forecast_type in ('demand', 'revenue', 'churn', 'vendor_recommendation', 'predictive_maintenance')),
  constraint forecast_jobs_status_check check (status in ('pending', 'succeeded', 'failed', 'insufficient_data')),
  constraint forecast_jobs_horizon_check check (horizon_days > 0 and horizon_days <= 1095),
  constraint forecast_jobs_scope_snapshot_check check (app.validate_config_value(scope_snapshot)),
  constraint forecast_jobs_feature_snapshot_check check (app.validate_config_value(feature_snapshot)),
  constraint forecast_jobs_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.forecast_jobs is
  'IAE-025: one row per forecast/recommendation request. NEVER writes to any existing Finance/Commercial/Procurement/Operations domain table (design decision 1). is_small_cohort_suppressed marks a real structural privacy control (design decision 2), not a permission convenience.';

create index forecast_jobs_tenant_idx on app.forecast_jobs (tenant_id, created_at desc);
create index forecast_jobs_type_idx on app.forecast_jobs (tenant_id, forecast_type, created_at desc);

-- ===========================================================================
-- Request
-- ===========================================================================

create function app.request_forecast_job(
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

  insert into app.forecast_jobs (
    tenant_id, forecast_type, scenario_label, scope_snapshot, feature_snapshot, horizon_days,
    status, requested_by_auth_user_id, requested_by, idempotency_key
  ) values (
    p_tenant_id, p_forecast_type, coalesce(nullif(trim(p_scenario_label), ''), 'baseline'), p_scope_snapshot, p_feature_snapshot, p_horizon_days,
    'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_forecast_job',
    'app.forecast_jobs', v_row.id, 'success', null, null, jsonb_build_object('forecast_type', v_row.forecast_type, 'scenario_label', v_row.scenario_label)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Record outcome after dispatch (design decisions 2, 3, 4)
-- ===========================================================================

create function app.record_forecast_job_outcome(
  p_job_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.forecast_jobs;
  v_request app.ai_governed_requests;
  v_insufficient_data boolean;
  v_predicted_value numeric;
  v_cohort_size integer;
  v_data_quality_note text;
  v_status text;
  v_row app.forecast_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_job from app.forecast_jobs where id = p_job_id;
  if not found then
    raise exception 'forecast_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_forecast_authority('Create', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.ai_governed_request_id is not null then
    if v_job.ai_governed_request_id = p_ai_governed_request_id then
      return v_job;
    end if;
    raise exception 'forecast_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  if v_job.status <> 'pending' then
    raise exception 'forecast_job_not_pending: job % is % not pending', p_job_id, v_job.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_job.tenant_id then
    raise exception 'forecast_job_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_job.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'forecasting_recommendation' then
    raise exception 'forecast_job_wrong_feature: governed request % has feature_code % not forecasting_recommendation', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'forecast_job' or v_request.correlation_record_id is distinct from v_job.id then
    raise exception 'forecast_job_correlation_mismatch: governed request % does not correlate to job %', p_ai_governed_request_id, p_job_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'forecast_job_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_insufficient_data := app._parse_forecast_bool(v_request.output_payload -> 'insufficientData');
    if v_insufficient_data then
      v_status := 'insufficient_data';
      v_data_quality_note := app._parse_forecast_text(v_request.output_payload -> 'dataQualityNote');
    else
      v_status := 'succeeded';
      v_predicted_value := app._parse_forecast_numeric(v_request.output_payload -> 'predictedValue');
      v_cohort_size := app._parse_forecast_int(v_request.output_payload -> 'cohortSize');
    end if;
  else
    v_status := 'failed';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending job -- live-reproduced on the sibling IAE-022 function
  -- before this fix, applied proactively here.
  update app.forecast_jobs
  set ai_governed_request_id = p_ai_governed_request_id,
      status = v_status,
      predicted_value = v_predicted_value,
      cohort_size = v_cohort_size,
      is_small_cohort_suppressed = (v_cohort_size is not null and v_cohort_size < 10),
      data_quality_note = v_data_quality_note,
      completed_at = now()
  where id = p_job_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.forecast_jobs where id = p_job_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'forecast_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_forecast_job_outcome',
    'app.forecast_jobs', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'is_small_cohort_suppressed', v_row.is_small_cohort_suppressed)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Feedback / planning decision (design decision 1, 5)
-- ===========================================================================

create table app.forecast_job_feedback (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  forecast_job_id uuid not null unique references app.forecast_jobs (id),
  feedback text not null,
  planning_decision_note text,
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz not null default now(),
  constraint forecast_job_feedback_feedback_check check (feedback in ('useful', 'not_useful', 'inaccurate'))
);

comment on table app.forecast_job_feedback is
  'IAE-025: a manager''s own usefulness judgment plus a free-text planning-decision note (design decision 1) -- never a write into any real commitment/budget/vendor-award/maintenance-order table. Recorded at most once per job.';

create function app.record_forecast_planning_decision(
  p_job_id uuid,
  p_tenant_id uuid,
  p_feedback text,
  p_planning_decision_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_job_feedback
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.forecast_jobs;
  v_row app.forecast_job_feedback;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_forecast_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_feedback not in ('useful', 'not_useful', 'inaccurate') then
    raise exception 'forecast_job_invalid_feedback: % is not one of useful/not_useful/inaccurate', p_feedback using errcode = 'check_violation';
  end if;

  select * into v_job from app.forecast_jobs where id = p_job_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'forecast_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;
  if v_job.status not in ('succeeded', 'insufficient_data') then
    raise exception 'forecast_job_not_feedback_eligible: job % is % -- only a succeeded/insufficient_data job may receive feedback', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.forecast_job_feedback where forecast_job_id = p_job_id) then
    raise exception 'forecast_job_already_has_feedback: job % already has feedback', p_job_id using errcode = 'check_violation';
  end if;

  insert into app.forecast_job_feedback (tenant_id, forecast_job_id, feedback, planning_decision_note, decided_by_auth_user_id, decided_by)
  values (p_tenant_id, p_job_id, p_feedback, p_planning_decision_note, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_forecast_planning_decision',
    'app.forecast_job_feedback', v_row.id, 'success', null, null, jsonb_build_object('feedback', v_row.feedback)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Evaluation / drift tracking (design decision 5)
-- ===========================================================================

create table app.forecast_job_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  forecast_job_id uuid not null unique references app.forecast_jobs (id),
  actual_outcome_value numeric not null,
  error_pct numeric,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
  created_at timestamptz not null default now()
);

comment on table app.forecast_job_evaluations is
  'IAE-025: real observed-outcome accuracy/drift evidence -- one evaluation per job, never a mutation of the job row itself.';

create function app.evaluate_forecast_job(
  p_job_id uuid,
  p_tenant_id uuid,
  p_actual_outcome_value numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_job_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.forecast_jobs;
  v_error_pct numeric;
  v_row app.forecast_job_evaluations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_forecast_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_job from app.forecast_jobs where id = p_job_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'forecast_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;
  if v_job.status <> 'succeeded' then
    raise exception 'forecast_job_not_evaluable: job % is % -- only a succeeded job may be evaluated', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.forecast_job_evaluations where forecast_job_id = p_job_id) then
    raise exception 'forecast_job_already_evaluated: job % already has an evaluation', p_job_id using errcode = 'check_violation';
  end if;

  if v_job.predicted_value is not null and v_job.predicted_value <> 0 then
    v_error_pct := abs(p_actual_outcome_value - v_job.predicted_value) / abs(v_job.predicted_value) * 100;
  end if;

  insert into app.forecast_job_evaluations (tenant_id, forecast_job_id, actual_outcome_value, error_pct, evaluated_by_auth_user_id, evaluated_by)
  values (p_tenant_id, p_job_id, p_actual_outcome_value, v_error_pct, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_forecast_job',
    'app.forecast_job_evaluations', v_row.id, 'success', null, null, jsonb_build_object('error_pct', v_row.error_pct)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Reads (design decision 2)
-- ===========================================================================

create function app.get_forecast_job(p_job_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, forecast_type text, scenario_label text, scope_snapshot jsonb, feature_snapshot jsonb,
  horizon_days integer, status text, predicted_value numeric, cohort_size integer, is_small_cohort_suppressed boolean,
  data_quality_note text, requested_by text, created_at timestamptz, completed_at timestamptz,
  output_payload jsonb, output_payload_masked boolean, confidence_label text, model_version text, request_status text,
  feedback text, planning_decision_note text, decided_by text, decided_at timestamptz,
  actual_outcome_value numeric, error_pct numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_can_view_small_cohort boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_forecast_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_small_cohort := app.check_forecast_authority('Approve', p_tenant_id, p_actor_auth_user_id);

  return query
  select j.id, j.tenant_id, j.forecast_type, j.scenario_label, j.scope_snapshot, j.feature_snapshot,
         j.horizon_days, j.status, j.predicted_value, j.cohort_size, j.is_small_cohort_suppressed,
         j.data_quality_note, j.requested_by, j.created_at, j.completed_at,
         app.mask_forecast_small_cohort_fields(r.output_payload, not j.is_small_cohort_suppressed or v_can_view_small_cohort),
         (r.output_payload is not null and j.is_small_cohort_suppressed and not v_can_view_small_cohort),
         r.confidence_label, r.model_version, r.status,
         f.feedback, f.planning_decision_note, f.decided_by, f.decided_at,
         e.actual_outcome_value, e.error_pct
  from app.forecast_jobs j
  left join app.ai_governed_requests r on r.id = j.ai_governed_request_id
  left join app.forecast_job_feedback f on f.forecast_job_id = j.id
  left join app.forecast_job_evaluations e on e.forecast_job_id = j.id
  where j.id = p_job_id and j.tenant_id = p_tenant_id;
end;
$$;

create function app.list_forecast_jobs_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_forecast_type text default null,
  p_status text default null,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, forecast_type text, scenario_label text, status text, predicted_value numeric,
  is_small_cohort_suppressed boolean, requested_by text, created_at timestamptz, confidence_label text, feedback text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_forecast_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'forecast_job_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select j.id, j.tenant_id, j.forecast_type, j.scenario_label, j.status, j.predicted_value, j.is_small_cohort_suppressed,
         j.requested_by, j.created_at, r.confidence_label, f.feedback
  from app.forecast_jobs j
  left join app.ai_governed_requests r on r.id = j.ai_governed_request_id
  left join app.forecast_job_feedback f on f.forecast_job_id = j.id
  where j.tenant_id = p_tenant_id and (p_forecast_type is null or j.forecast_type = p_forecast_type) and (p_status is null or j.status = p_status)
  order by j.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.forecast_jobs enable row level security;
alter table app.forecast_job_feedback enable row level security;
alter table app.forecast_job_evaluations enable row level security;

-- No direct authenticated grant and zero policies -- the only read paths
-- are the two dedicated functions (AI:View-gated).

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_forecast_authority(text, uuid, uuid) to service_role;
grant execute on function app._parse_forecast_bool(jsonb) to service_role;
grant execute on function app._parse_forecast_numeric(jsonb) to service_role;
grant execute on function app._parse_forecast_int(jsonb) to service_role;
grant execute on function app._parse_forecast_text(jsonb, integer) to service_role;
grant execute on function app.mask_forecast_small_cohort_fields(jsonb, boolean) to service_role;
grant execute on function app.request_forecast_job(uuid, text, text, jsonb, jsonb, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_forecast_job_outcome(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.record_forecast_planning_decision(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_forecast_job(uuid, uuid, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.get_forecast_job(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_forecast_jobs_for_tenant(uuid, uuid, text, text, integer) to authenticated, service_role;
