-- Intelligence, Automation and Enterprise Expansion: Optimization Assistance
-- (IAE-023, CG-S14-IAE-023, Prompt 351). Third of Group 6 ("Further
-- AI-Assisted Capabilities", Prompts 349-353). Depends on IAE-019 (AI
-- Governance Provider Boundary, VERIFIED) exactly as IAE-020/021/022
-- already do.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **This capability's own write surface never touches ANY existing
--    TMS/WMS domain table -- not even in draft form.** Prompt 351 §24's own
--    business rule ("never dispatches, reassigns, moves stock or changes
--    route autonomously") is structurally the strongest of any AI-assisted
--    capability so far: unlike a Commercial quotation or a Ticket (which
--    both have a genuine, existing DRAFT state a human-reviewed value can
--    safely land in, per IAE-020/IAE-021's own "apply to draft" shape),
--    dispatch/reassignment/stock-movement/route-change actions in this
--    repository's own TMS/WMS domain are immediate operational actions
--    with no equivalent draft precondition to target. Rather than force
--    a fake "draft" concept onto a domain that has none (which this
--    project's own Definition of Done forbids as placeholder behavior),
--    this checkpoint's own terminal action is
--    app.acknowledge_optimization_recommendation_applied -- it records
--    that a human asserts they carried out the recommendation through the
--    EXISTING, UNMODIFIED TMS/WMS mechanism, citing the resulting real
--    record as evidence (applied_reference, free text), but never creates
--    or mutates that record itself. This is a stricter, more conservative
--    reading of "advisory only" than any prior AI-assisted capability
--    needed, and is the correct one given this prompt's own stronger
--    business rule.
-- 2. **Sensitive fields are masked by role, at the READ boundary, not by
--    scrubbing what gets stored.** input_snapshot/constraint_set/the
--    governed request's own output_payload may legitimately carry
--    cost/margin/vendor-identifying figures a requester needs for the
--    optimization itself to run -- app.get_optimization_scenario masks
--    any top-level key matching a cost/margin/vendor-shaped pattern
--    (app.mask_optimization_sensitive_fields, mirrors app.redact_audit_
--    payload's own key-name-regex shape) unless the VIEWING actor holds
--    AI:Approve, reusing AI:Approve as the "may see sensitive planning
--    figures" tier exactly as IAE-021/IAE-022 already reuse it as the
--    "may override low-confidence output" tier -- one elevated action,
--    two distinct, disclosed uses.
-- 3. **A scenario has no owning business record to scope access
--    against** -- unlike a file (IAE-021) or a shipment (IAE-022), an
--    optimization scenario is an internal planning artifact with no
--    pre-existing owner/org-unit stake. Tenant + AI-module authority is
--    the correct, sufficient gate here; no app.can_access_record check
--    is fabricated where no owning record exists.
-- 4. **Staleness is an explicit, human- or job-triggered flag, never an
--    automatic timestamp comparison** (business rule "scenario results
--    expire when source data changes materially" -- "materially" is a
--    domain judgment this checkpoint cannot compute generically across
--    route/dispatch/warehouse_slotting/picking scopes). app.mark_
--    optimization_scenario_stale is the real, auditable mechanism;
--    app.decide_optimization_scenario refuses to accept/reject a stale
--    scenario. A future scheduled job that detects material source-data
--    drift and calls this function is a disclosed, deferred extension,
--    not built here.
-- 5. **Human decision and edits are recorded separately from the AI's own
--    output** -- app.optimization_scenario_decisions is a genuinely
--    distinct table/writer from app.optimization_scenarios, mirroring
--    every prior AI-assisted capability's "N distinct tables, N distinct
--    writers" shape. accepted_option_index is validated against the real
--    length of the governed request's own output_payload.recommendations
--    array -- never trusted blindly.
-- 6. AI dispatch reuses dispatchAiGovernedRequest (IAE-019) unmodified --
--    feature_code = 'optimization_assistance', correlation_record_type =
--    'optimization_scenario' (correlated to the scenario's own id, the
--    only stable identity that exists before dispatch, mirroring how a
--    scenario has no other pre-existing business record to correlate to,
--    per decision 3).
-- 7. No new entitlement module -- the AI module's own comment (IAE-019)
--    already names optimization as one of its owned features.
-- 8-10. Proactively applied lessons from IAE-020/021/022: SECURITY DEFINER
--    + assert_actor_is_session_identity on every authenticated-granted
--    function; explicit table aliases in every RETURNS TABLE; IS
--    DISTINCT FROM for every nullable correlation cross-check.
-- 11. Per ERR-2026-004: explicit revoke execute on all functions in
--    schema app from public.

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_optimization_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Masking helper (design decision 2) -- mirrors app.redact_audit_payload's
-- own key-name-regex shape, applied as a read-time mask (null out), never a
-- write-time scrub.
-- ===========================================================================

create function app.mask_optimization_sensitive_fields(p_payload jsonb, p_can_view_sensitive boolean)
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

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key in select jsonb_object_keys(p_payload) loop
      if v_key ~* '(cost|margin|vendor|rate|price|wholesale)' then
        continue;
      end if;
      v_result := v_result || jsonb_build_object(v_key, app.mask_optimization_sensitive_fields(p_payload -> v_key, false));
    end loop;
    return v_result;
  end if;

  if jsonb_typeof(p_payload) = 'array' then
    v_array_result := '[]'::jsonb;
    for v_element in select value from jsonb_array_elements(p_payload) loop
      v_array_result := v_array_result || jsonb_build_array(app.mask_optimization_sensitive_fields(v_element, false));
    end loop;
    return v_array_result;
  end if;

  return p_payload;
end;
$$;

comment on function app.mask_optimization_sensitive_fields is
  'IAE-023 (design decision 2): recursively walks objects and arrays, stripping any key matching a cost/margin/vendor/rate/price-shaped pattern at ANY depth -- a shallow, top-level-only mask would leave recommendations[].vendor_rate_ref (the realistic, nested shape every real optimization output takes) fully exposed, which this checkpoint''s own db-test caught live before this fix.';

-- ===========================================================================
-- Core scenario table (design decisions 3, 4, 6)
-- ===========================================================================

create table app.optimization_scenarios (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scope_type text not null,
  input_snapshot jsonb not null,
  constraint_set jsonb not null,
  ai_governed_request_id uuid unique references app.ai_governed_requests (id),
  status text not null default 'pending',
  is_stale boolean not null default false,
  stale_reason text,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint optimization_scenarios_scope_type_check check (scope_type in ('route', 'dispatch', 'warehouse_slotting', 'picking')),
  constraint optimization_scenarios_status_check check (status in ('pending', 'succeeded', 'failed')),
  constraint optimization_scenarios_input_snapshot_check check (app.validate_config_value(input_snapshot)),
  constraint optimization_scenarios_constraint_set_check check (app.validate_config_value(constraint_set)),
  constraint optimization_scenarios_stale_reason_check check (is_stale = false or stale_reason is not null),
  constraint optimization_scenarios_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.optimization_scenarios is
  'IAE-023: one row per optimization request. NEVER writes to any existing TMS/WMS domain table (design decision 1) -- recommendations live only in the referenced app.ai_governed_requests row; the only human-decision write path is app.optimization_scenario_decisions, a genuinely separate table/writer.';

create index optimization_scenarios_tenant_idx on app.optimization_scenarios (tenant_id, created_at desc);
create index optimization_scenarios_scope_idx on app.optimization_scenarios (tenant_id, scope_type, created_at desc);

-- ===========================================================================
-- Request
-- ===========================================================================

create function app.request_optimization_scenario(
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

  insert into app.optimization_scenarios (
    tenant_id, scope_type, input_snapshot, constraint_set, status, requested_by_auth_user_id, requested_by, idempotency_key
  ) values (
    p_tenant_id, p_scope_type, p_input_snapshot, p_constraint_set, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_optimization_scenario',
    'app.optimization_scenarios', v_row.id, 'success', null, null, jsonb_build_object('scope_type', v_row.scope_type)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Record outcome after dispatch
-- ===========================================================================

create function app.record_optimization_scenario_outcome(
  p_scenario_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.optimization_scenarios;
  v_request app.ai_governed_requests;
  v_row app.optimization_scenarios;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_scenario from app.optimization_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'optimization_scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  if not app.check_optimization_authority('Create', v_scenario.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_scenario.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_scenario.ai_governed_request_id is not null then
    if v_scenario.ai_governed_request_id = p_ai_governed_request_id then
      return v_scenario;
    end if;
    raise exception 'optimization_scenario_outcome_already_recorded: scenario % is already linked to a different governed request', p_scenario_id
      using errcode = 'check_violation';
  end if;

  if v_scenario.status <> 'pending' then
    raise exception 'optimization_scenario_not_pending: scenario % is % not pending', p_scenario_id, v_scenario.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_scenario.tenant_id then
    raise exception 'optimization_scenario_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_scenario.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'optimization_assistance' then
    raise exception 'optimization_scenario_wrong_feature: governed request % has feature_code % not optimization_assistance', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'optimization_scenario' or v_request.correlation_record_id is distinct from v_scenario.id then
    raise exception 'optimization_scenario_correlation_mismatch: governed request % does not correlate to scenario %', p_ai_governed_request_id, p_scenario_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'optimization_scenario_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending scenario -- live-reproduced on the sibling IAE-022
  -- function before this fix, applied proactively here.
  update app.optimization_scenarios
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      completed_at = now()
  where id = p_scenario_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.optimization_scenarios where id = p_scenario_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'optimization_scenario_outcome_already_recorded: scenario % is already linked to a different governed request', p_scenario_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_scenario.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_optimization_scenario_outcome',
    'app.optimization_scenarios', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Staleness (design decision 4)
-- ===========================================================================

create function app.mark_optimization_scenario_stale(
  p_scenario_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.optimization_scenarios;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'optimization_scenario_stale_reason_required: a reason is required' using errcode = 'check_violation';
  end if;

  update app.optimization_scenarios
  set is_stale = true, stale_reason = p_reason
  where id = p_scenario_id and tenant_id = p_tenant_id
  returning * into v_row;

  if not found then
    raise exception 'optimization_scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_optimization_scenario_stale',
    'app.optimization_scenarios', v_row.id, 'success', null, null, jsonb_build_object('stale_reason', v_row.stale_reason)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Human decision (design decision 5)
-- ===========================================================================

create table app.optimization_scenario_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null unique references app.optimization_scenarios (id),
  decision text not null,
  selected_option_index integer,
  decision_note text,
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz not null default now(),
  applied_acknowledged boolean not null default false,
  applied_reference text,
  applied_acknowledged_by_auth_user_id uuid,
  applied_acknowledged_by text,
  applied_acknowledged_at timestamptz,
  constraint optimization_scenario_decisions_decision_check check (decision in ('accepted', 'rejected')),
  constraint optimization_scenario_decisions_option_shape_check check ((decision = 'accepted') = (selected_option_index is not null)),
  constraint optimization_scenario_decisions_applied_shape_check check (applied_acknowledged = false or applied_reference is not null)
);

comment on table app.optimization_scenario_decisions is
  'IAE-023: the human decision, recorded separately from the AI''s own recommendations (design decision 5). applied_reference (design decision 1) is a free-text citation of the real record a human created through the EXISTING, UNMODIFIED TMS/WMS mechanism -- this table never creates or mutates that record itself.';

create index optimization_scenario_decisions_tenant_idx on app.optimization_scenario_decisions (tenant_id, decided_at desc);

create function app.decide_optimization_scenario(
  p_scenario_id uuid,
  p_tenant_id uuid,
  p_decision text,
  p_selected_option_index integer,
  p_decision_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenario_decisions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.optimization_scenarios;
  v_request app.ai_governed_requests;
  v_recommendation_count integer;
  v_row app.optimization_scenario_decisions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('accepted', 'rejected') then
    raise exception 'optimization_scenario_invalid_decision: % is not one of accepted/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.optimization_scenarios where id = p_scenario_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'optimization_scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;
  if v_scenario.status <> 'succeeded' then
    raise exception 'optimization_scenario_not_decidable: scenario % is % -- only a succeeded scenario may be decided', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;
  if v_scenario.is_stale then
    raise exception 'optimization_scenario_stale: scenario % was marked stale (%) -- request a fresh scenario', p_scenario_id, v_scenario.stale_reason
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.optimization_scenario_decisions where scenario_id = p_scenario_id) then
    raise exception 'optimization_scenario_already_decided: scenario % already has a decision', p_scenario_id using errcode = 'check_violation';
  end if;

  if p_decision = 'accepted' then
    select * into v_request from app.ai_governed_requests where id = v_scenario.ai_governed_request_id;
    v_recommendation_count := coalesce(jsonb_array_length(v_request.output_payload -> 'recommendations'), 0);
    if p_selected_option_index is null or p_selected_option_index < 0 or p_selected_option_index >= v_recommendation_count then
      raise exception 'optimization_scenario_invalid_option_index: % is out of range for % recommendation(s)', p_selected_option_index, v_recommendation_count
        using errcode = 'check_violation';
    end if;
  elsif p_selected_option_index is not null then
    raise exception 'optimization_scenario_option_index_not_allowed: selected_option_index must be null when rejecting' using errcode = 'check_violation';
  end if;

  insert into app.optimization_scenario_decisions (tenant_id, scenario_id, decision, selected_option_index, decision_note, decided_by_auth_user_id, decided_by)
  values (p_tenant_id, p_scenario_id, p_decision, p_selected_option_index, p_decision_note, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_optimization_scenario',
    'app.optimization_scenario_decisions', v_row.id, 'success', null, null,
    jsonb_build_object('decision', v_row.decision, 'selected_option_index', v_row.selected_option_index)
  );

  return v_row;
end;
$$;

create function app.acknowledge_optimization_recommendation_applied(
  p_decision_id uuid,
  p_tenant_id uuid,
  p_applied_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenario_decisions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.optimization_scenario_decisions;
  v_row app.optimization_scenario_decisions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_decision from app.optimization_scenario_decisions where id = p_decision_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'optimization_scenario_decision_not_found: %', p_decision_id using errcode = 'no_data_found';
  end if;
  if v_decision.decision <> 'accepted' then
    raise exception 'optimization_scenario_decision_not_accepted: decision % is % -- only an accepted decision may be marked applied', p_decision_id, v_decision.decision
      using errcode = 'check_violation';
  end if;
  if v_decision.applied_acknowledged then
    raise exception 'optimization_scenario_decision_already_applied: decision % is already marked applied', p_decision_id using errcode = 'check_violation';
  end if;
  if p_applied_reference is null or length(trim(p_applied_reference)) = 0 then
    raise exception 'optimization_scenario_applied_reference_required: a reference to the real record you created is required' using errcode = 'check_violation';
  end if;

  update app.optimization_scenario_decisions
  set applied_acknowledged = true, applied_reference = p_applied_reference,
      applied_acknowledged_by_auth_user_id = p_actor_auth_user_id, applied_acknowledged_by = p_actor_label, applied_acknowledged_at = now()
  where id = p_decision_id and applied_acknowledged = false
  returning * into v_row;

  if not found then
    raise exception 'optimization_scenario_decision_already_applied: decision % is already marked applied', p_decision_id using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_optimization_recommendation_applied',
    'app.optimization_scenario_decisions', v_row.id, 'success', null, null, jsonb_build_object('applied_reference', v_row.applied_reference)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Reads (design decision 2)
-- ===========================================================================

create function app.get_optimization_scenario(p_scenario_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, scope_type text, input_snapshot jsonb, constraint_set jsonb, status text,
  is_stale boolean, stale_reason text, requested_by text, created_at timestamptz, completed_at timestamptz,
  output_payload jsonb, output_payload_masked boolean, confidence_label text, model_version text, request_status text,
  decision text, selected_option_index integer, decision_note text, decided_by text, decided_at timestamptz,
  applied_acknowledged boolean, applied_reference text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_can_view_sensitive boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_sensitive := app.check_optimization_authority('Approve', p_tenant_id, p_actor_auth_user_id);

  return query
  select s.id, s.tenant_id, s.scope_type,
         app.mask_optimization_sensitive_fields(s.input_snapshot, v_can_view_sensitive),
         app.mask_optimization_sensitive_fields(s.constraint_set, v_can_view_sensitive),
         s.status, s.is_stale, s.stale_reason, s.requested_by, s.created_at, s.completed_at,
         app.mask_optimization_sensitive_fields(r.output_payload, v_can_view_sensitive),
         (r.output_payload is not null and not v_can_view_sensitive),
         r.confidence_label, r.model_version, r.status,
         d.decision, d.selected_option_index, d.decision_note, d.decided_by, d.decided_at,
         d.applied_acknowledged, d.applied_reference
  from app.optimization_scenarios s
  left join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  left join app.optimization_scenario_decisions d on d.scenario_id = s.id
  where s.id = p_scenario_id and s.tenant_id = p_tenant_id;
end;
$$;

create function app.list_optimization_scenarios_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_scope_type text default null,
  p_status text default null,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, scope_type text, status text, is_stale boolean,
  requested_by text, created_at timestamptz, confidence_label text, decision text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_optimization_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'optimization_scenario_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select s.id, s.tenant_id, s.scope_type, s.status, s.is_stale, s.requested_by, s.created_at, r.confidence_label, d.decision
  from app.optimization_scenarios s
  left join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  left join app.optimization_scenario_decisions d on d.scenario_id = s.id
  where s.tenant_id = p_tenant_id and (p_scope_type is null or s.scope_type = p_scope_type) and (p_status is null or s.status = p_status)
  order by s.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.optimization_scenarios enable row level security;
alter table app.optimization_scenario_decisions enable row level security;

-- No direct authenticated grant and zero policies -- the only read paths
-- are the two dedicated functions (AI:View-gated).

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_optimization_authority(text, uuid, uuid) to service_role;
grant execute on function app.mask_optimization_sensitive_fields(jsonb, boolean) to service_role;
grant execute on function app.request_optimization_scenario(uuid, text, jsonb, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_optimization_scenario_outcome(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.mark_optimization_scenario_stale(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_optimization_scenario(uuid, uuid, text, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.acknowledge_optimization_recommendation_applied(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_optimization_scenario(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_optimization_scenarios_for_tenant(uuid, uuid, text, text, integer) to authenticated, service_role;
