-- Intelligence, Automation and Enterprise Expansion: Predictive ETA
-- (IAE-022, CG-S14-IAE-022, Prompt 350). Second of Group 6 ("Further
-- AI-Assisted Capabilities", Prompts 349-353). Depends on IAE-019 (AI
-- Governance Provider Boundary, VERIFIED) exactly as IAE-020/IAE-021
-- already do, and on OPS-173's own disclosed gap: app.shipment_milestone_
-- projections.current_eta is explicitly documented as "never a predictive
-- ETA algorithm, which remains out of this bounded capability's scope" --
-- this checkpoint is that future capability, built as a genuinely separate,
-- advisory-only signal, never a replacement for that projection.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Predictive ETA can NEVER overwrite app.shipment_orders or
--    app.shipment_milestone_projections -- structurally, not by
--    convention.** No function in this migration grants INSERT/UPDATE on
--    either table; this migration's own app.eta_predictions is a genuinely
--    separate, additive signal that a caller reads ALONGSIDE the existing,
--    unmodified milestone projection, never a value the projection itself
--    is recomputed from.
-- 2. **predicted_eta/predicted_eta_earliest/predicted_eta_latest ARE
--    extracted from the governed request's own output_payload** -- unlike
--    IAE-020/IAE-021 (where AI output must never become applied domain
--    truth without a human step), displaying the AI's own predicted number
--    AS AN ADVISORY SIGNAL is this capability's entire purpose, not a
--    bypass risk: nothing here writes to any canonical shipment/milestone
--    table, so there is no "truth" for the AI to corrupt. Extraction is
--    defensive (a malformed/missing timestamp in the AI's own response
--    yields a null field, never a crash or a fabricated value) --
--    business rule "untrusted output cannot control the system" is
--    satisfied by "the untrusted value can only ever become a displayed,
--    clearly-advisory number or nothing, never an action."
-- 3. **Only 'confirmed', non-terminal shipments are eligible.** A 'draft'
--    shipment has no real milestone history to feature-engineer from; a
--    shipment whose current milestone is_terminal (app.milestone_codes,
--    OPS-173) has already arrived -- predicting its own ETA is meaningless
--    and would silently mask real delivery in a stale/misleading way.
-- 4. **Tenant-wide enable/disable is a real, persisted governance
--    action, not a soft client-side flag** (business rule "poor accuracy
--    or drift can disable prediction per tenant/module") --
--    app.eta_prediction_tenant_settings, AI:Approve-gated, enabled by
--    default (a tenant with no row yet is enabled) until an operator
--    explicitly disables it with a reason. request_eta_prediction refuses
--    with a clear, distinguishable error while disabled -- callers can
--    build the "degraded note" UI state (Prompt 350 §22) directly off that
--    error rather than polling a separate flag first.
-- 5. **Override is a one-way, human-authored distrust flag, never a value
--    edit.** app.override_eta_prediction never changes predicted_eta itself
--    (immutable evidence) -- it only marks the row so a display layer can
--    show "an ops reviewer flagged this prediction as unreliable," mirroring
--    the same "evidence is immutable, human judgment is recorded
--    separately" shape as IAE-020/IAE-021's own suggestion/job tables.
-- 6. **Evaluation is a genuinely separate table (1:1), not a column
--    mutation on app.eta_predictions** -- accuracy/drift tracking (task
--    item 4) needs its own actor/timestamp/error evidence trail,
--    independent of the prediction row it evaluates; a prediction is
--    evaluated at most once (a new observation calls for a NEW prediction
--    request, not a re-evaluation of a stale one).
-- 7. AI dispatch reuses dispatchAiGovernedRequest (IAE-019) unmodified --
--    feature_code = 'predictive_eta', correlation_record_type =
--    'shipment_order'. Zero new rows in app.integration_adapters/app.jobs.
-- 8. No new entitlement module -- the AI module's own comment (IAE-019)
--    already names ETA as one of its owned features.
-- 9. Every authenticated-granted function is SECURITY DEFINER plus
--    app.assert_actor_is_session_identity, applied proactively (the
--    Batch 4/IAE-020/IAE-021 Tier C reviews' own most-repeated lesson).
-- 10. RETURNS TABLE column names are always qualified with an explicit
--    table alias (IAE-020's own self-caught column-shadowing bug).
-- 11. Nullable-column correlation cross-checks always use IS DISTINCT
--    FROM, never bare <> (IAE-020's own self-caught bug).
-- 12. Per ERR-2026-004: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public` before
--    its final grants.

-- ===========================================================================
-- Tenant-wide enable/disable governance (design decision 4)
-- ===========================================================================

create table app.eta_prediction_tenant_settings (
  tenant_id uuid primary key references app.tenants (id),
  enabled boolean not null default true,
  disabled_reason text,
  disabled_by_auth_user_id uuid,
  disabled_by text,
  updated_at timestamptz not null default now(),
  constraint eta_prediction_tenant_settings_disabled_reason_check check (enabled = true or disabled_reason is not null)
);

comment on table app.eta_prediction_tenant_settings is
  'IAE-022: a tenant with no row here is enabled by default. Only app.set_eta_prediction_enabled writes this table (AI:Approve-gated) -- a real, persisted governance action for the "poor accuracy or drift can disable prediction per tenant" business rule.';

create function app.is_eta_prediction_enabled_for_tenant(p_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce((select enabled from app.eta_prediction_tenant_settings where tenant_id = p_tenant_id), true);
$$;

create function app.set_eta_prediction_enabled(
  p_tenant_id uuid,
  p_enabled boolean,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_prediction_tenant_settings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.eta_prediction_tenant_settings;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', 'Approve')).allowed then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not p_enabled and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'eta_prediction_disable_reason_required: a reason is required to disable prediction for a tenant' using errcode = 'check_violation';
  end if;

  insert into app.eta_prediction_tenant_settings (tenant_id, enabled, disabled_reason, disabled_by_auth_user_id, disabled_by, updated_at)
  values (p_tenant_id, p_enabled, case when p_enabled then null else p_reason end, case when p_enabled then null else p_actor_auth_user_id end, case when p_enabled then null else p_actor_label end, now())
  on conflict (tenant_id) do update set
    enabled = excluded.enabled, disabled_reason = excluded.disabled_reason,
    disabled_by_auth_user_id = excluded.disabled_by_auth_user_id, disabled_by = excluded.disabled_by, updated_at = now()
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_eta_prediction_enabled',
    'app.eta_prediction_tenant_settings', p_tenant_id, 'success', null, null, jsonb_build_object('enabled', v_row.enabled)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_eta_prediction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Core prediction table (design decisions 1, 2, 5)
-- ===========================================================================

create table app.eta_predictions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  ai_governed_request_id uuid unique references app.ai_governed_requests (id),
  feature_snapshot jsonb not null,
  status text not null default 'pending',
  predicted_eta timestamptz,
  predicted_eta_earliest timestamptz,
  predicted_eta_latest timestamptz,
  overridden boolean not null default false,
  override_reason text,
  overridden_by_auth_user_id uuid,
  overridden_by text,
  overridden_at timestamptz,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint eta_predictions_status_check check (status in ('pending', 'succeeded', 'failed')),
  constraint eta_predictions_feature_snapshot_check check (app.validate_config_value(feature_snapshot)),
  constraint eta_predictions_overridden_shape_check check (overridden = false or override_reason is not null),
  constraint eta_predictions_band_order_check check (predicted_eta_earliest is null or predicted_eta_latest is null or predicted_eta_earliest <= predicted_eta_latest),
  constraint eta_predictions_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.eta_predictions is
  'IAE-022: one row per prediction request. NEVER writes to app.shipment_orders/app.shipment_milestone_projections (design decision 1) -- purely additive, advisory evidence read alongside the canonical projection, never a replacement for it.';

create index eta_predictions_tenant_idx on app.eta_predictions (tenant_id, created_at desc);
create index eta_predictions_shipment_idx on app.eta_predictions (tenant_id, shipment_order_id, created_at desc);

-- ===========================================================================
-- Request (design decision 3)
-- ===========================================================================

create function app.request_eta_prediction(
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

  insert into app.eta_predictions (
    tenant_id, shipment_order_id, feature_snapshot, status, requested_by_auth_user_id, requested_by, idempotency_key
  ) values (
    p_tenant_id, p_shipment_order_id, p_feature_snapshot, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_eta_prediction',
    'app.eta_predictions', v_row.id, 'success', null, null, jsonb_build_object('shipment_order_id', v_row.shipment_order_id)
  );

  return v_row;
end;
$$;

comment on function app.request_eta_prediction is
  'IAE-022: the entry point the TS orchestration client calls before dispatching a real governed AI request. Refuses a non-confirmed or already-terminal shipment, and while the tenant has disabled prediction (design decisions 3, 4). Idempotent per (tenant, idempotency key), enforced by a real unique constraint.';

-- ===========================================================================
-- Record outcome after dispatch (design decisions 1, 2, 7, 11)
-- ===========================================================================

create function app._parse_eta_timestamp(p_value jsonb)
returns timestamptz
language plpgsql
immutable
as $$
declare
  v_result timestamptz;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'string' then
    return null;
  end if;
  begin
    v_result := (p_value #>> '{}')::timestamptz;
  exception when others then
    return null;
  end;
  return v_result;
end;
$$;

comment on function app._parse_eta_timestamp is
  'IAE-022 (design decision 2): defensive extraction of an AI-provided timestamp -- a malformed/missing value yields NULL, never an exception. Untrusted AI output can only ever become a displayed number or nothing, never crash this function or the caller.';

create function app.record_eta_prediction_outcome(
  p_prediction_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_predictions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prediction app.eta_predictions;
  v_request app.ai_governed_requests;
  v_predicted_eta timestamptz;
  v_earliest timestamptz;
  v_latest timestamptz;
  v_row app.eta_predictions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_prediction from app.eta_predictions where id = p_prediction_id;
  if not found then
    raise exception 'eta_prediction_not_found: %', p_prediction_id using errcode = 'no_data_found';
  end if;

  if not app.check_eta_prediction_authority('Create', v_prediction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_prediction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prediction.ai_governed_request_id is not null then
    if v_prediction.ai_governed_request_id = p_ai_governed_request_id then
      return v_prediction;
    end if;
    raise exception 'eta_prediction_outcome_already_recorded: prediction % is already linked to a different governed request', p_prediction_id
      using errcode = 'check_violation';
  end if;

  if v_prediction.status <> 'pending' then
    raise exception 'eta_prediction_not_pending: prediction % is % not pending', p_prediction_id, v_prediction.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_prediction.tenant_id then
    raise exception 'eta_prediction_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_prediction.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'predictive_eta' then
    raise exception 'eta_prediction_wrong_feature: governed request % has feature_code % not predictive_eta', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'shipment_order' or v_request.correlation_record_id is distinct from v_prediction.shipment_order_id then
    raise exception 'eta_prediction_correlation_mismatch: governed request % does not correlate to prediction %''s own shipment %', p_ai_governed_request_id, p_prediction_id, v_prediction.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'eta_prediction_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_predicted_eta := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEta');
    v_earliest := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEtaEarliest');
    v_latest := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEtaLatest');
    if v_earliest is not null and v_latest is not null and v_earliest > v_latest then
      v_earliest := null;
      v_latest := null;
    end if;
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending prediction -- live-reproduced before this fix: both
  -- callers returned a false "success" and the loser's own outcome was
  -- silently overwritten with no error. A losing caller now re-selects the
  -- winner's own row and either returns it (if it happens to be its own
  -- request id) or raises the same already-recorded/not-pending errors the
  -- sequential case already uses.
  update app.eta_predictions
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      predicted_eta = v_predicted_eta, predicted_eta_earliest = v_earliest, predicted_eta_latest = v_latest,
      completed_at = now()
  where id = p_prediction_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.eta_predictions where id = p_prediction_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'eta_prediction_outcome_already_recorded: prediction % is already linked to a different governed request', p_prediction_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_prediction.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_eta_prediction_outcome',
    'app.eta_predictions', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'has_predicted_eta', v_row.predicted_eta is not null)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Override (design decision 5)
-- ===========================================================================

create function app.override_eta_prediction(
  p_prediction_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_predictions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.eta_predictions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_eta_prediction_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'eta_prediction_override_reason_required: a reason is required' using errcode = 'check_violation';
  end if;

  update app.eta_predictions
  set overridden = true, override_reason = p_reason, overridden_by_auth_user_id = p_actor_auth_user_id, overridden_by = p_actor_label, overridden_at = now()
  where id = p_prediction_id and tenant_id = p_tenant_id and overridden = false
  returning * into v_row;

  if not found then
    if exists (select 1 from app.eta_predictions where id = p_prediction_id and tenant_id = p_tenant_id) then
      raise exception 'eta_prediction_already_overridden: prediction % is already overridden', p_prediction_id using errcode = 'check_violation';
    end if;
    raise exception 'eta_prediction_not_found: %', p_prediction_id using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'override_eta_prediction',
    'app.eta_predictions', v_row.id, 'success', null, null, jsonb_build_object('override_reason', v_row.override_reason)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Evaluation (design decision 6)
-- ===========================================================================

create table app.eta_prediction_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  eta_prediction_id uuid not null unique references app.eta_predictions (id),
  actual_arrival_at timestamptz not null,
  error_minutes numeric,
  within_confidence_band boolean,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
  created_at timestamptz not null default now()
);

comment on table app.eta_prediction_evaluations is
  'IAE-022: real accuracy/drift evidence -- one evaluation per prediction (unique on eta_prediction_id), never a mutation of the prediction row itself.';

create function app.evaluate_eta_prediction(
  p_prediction_id uuid,
  p_tenant_id uuid,
  p_actual_arrival_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_prediction_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prediction app.eta_predictions;
  v_error_minutes numeric;
  v_within boolean;
  v_row app.eta_prediction_evaluations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_eta_prediction_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prediction from app.eta_predictions where id = p_prediction_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'eta_prediction_not_found: %', p_prediction_id using errcode = 'no_data_found';
  end if;
  if v_prediction.status <> 'succeeded' then
    raise exception 'eta_prediction_not_evaluable: prediction % is % -- only a succeeded prediction may be evaluated', p_prediction_id, v_prediction.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.eta_prediction_evaluations where eta_prediction_id = p_prediction_id) then
    raise exception 'eta_prediction_already_evaluated: prediction % already has an evaluation', p_prediction_id using errcode = 'check_violation';
  end if;

  if v_prediction.predicted_eta is not null then
    v_error_minutes := extract(epoch from (p_actual_arrival_at - v_prediction.predicted_eta)) / 60.0;
  end if;
  if v_prediction.predicted_eta_earliest is not null and v_prediction.predicted_eta_latest is not null then
    v_within := p_actual_arrival_at between v_prediction.predicted_eta_earliest and v_prediction.predicted_eta_latest;
  end if;

  insert into app.eta_prediction_evaluations (tenant_id, eta_prediction_id, actual_arrival_at, error_minutes, within_confidence_band, evaluated_by_auth_user_id, evaluated_by)
  values (p_tenant_id, p_prediction_id, p_actual_arrival_at, v_error_minutes, v_within, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_eta_prediction',
    'app.eta_prediction_evaluations', v_row.id, 'success', null, null, jsonb_build_object('error_minutes', v_row.error_minutes)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Reads
-- ===========================================================================

create function app.get_eta_prediction(p_prediction_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, shipment_order_id uuid, ai_governed_request_id uuid, status text,
  predicted_eta timestamptz, predicted_eta_earliest timestamptz, predicted_eta_latest timestamptz,
  overridden boolean, override_reason text, requested_by text, created_at timestamptz, completed_at timestamptz,
  confidence_label text, model_version text, request_status text,
  error_minutes numeric, within_confidence_band boolean, actual_arrival_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_eta_prediction_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select p.id, p.tenant_id, p.shipment_order_id, p.ai_governed_request_id, p.status,
         p.predicted_eta, p.predicted_eta_earliest, p.predicted_eta_latest,
         p.overridden, p.override_reason, p.requested_by, p.created_at, p.completed_at,
         r.confidence_label, r.model_version, r.status,
         e.error_minutes, e.within_confidence_band, e.actual_arrival_at
  from app.eta_predictions p
  left join app.ai_governed_requests r on r.id = p.ai_governed_request_id
  left join app.eta_prediction_evaluations e on e.eta_prediction_id = p.id
  where p.id = p_prediction_id and p.tenant_id = p_tenant_id;
end;
$$;

create function app.list_eta_predictions_for_shipment(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, shipment_order_id uuid, status text,
  predicted_eta timestamptz, predicted_eta_earliest timestamptz, predicted_eta_latest timestamptz,
  overridden boolean, created_at timestamptz, confidence_label text, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_eta_prediction_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'eta_prediction_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select p.id, p.tenant_id, p.shipment_order_id, p.status,
         p.predicted_eta, p.predicted_eta_earliest, p.predicted_eta_latest,
         p.overridden, p.created_at, r.confidence_label, r.status
  from app.eta_predictions p
  left join app.ai_governed_requests r on r.id = p.ai_governed_request_id
  where p.tenant_id = p_tenant_id and p.shipment_order_id = p_shipment_order_id
  order by p.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.eta_predictions enable row level security;
alter table app.eta_prediction_evaluations enable row level security;
alter table app.eta_prediction_tenant_settings enable row level security;

-- No direct authenticated grant and zero policies on any of the three
-- tables above -- the only read paths are the two dedicated functions
-- (AI:View-gated), mirroring app.ai_quotation_suggestions/app.ocr_
-- document_jobs' own posture exactly.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.is_eta_prediction_enabled_for_tenant(uuid) to authenticated, service_role;
grant execute on function app.set_eta_prediction_enabled(uuid, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.check_eta_prediction_authority(text, uuid, uuid) to service_role;
grant execute on function app.request_eta_prediction(uuid, uuid, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app._parse_eta_timestamp(jsonb) to service_role;
grant execute on function app.record_eta_prediction_outcome(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.override_eta_prediction(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_eta_prediction(uuid, uuid, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_eta_prediction(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_eta_predictions_for_shipment(uuid, uuid, uuid, integer) to authenticated, service_role;
