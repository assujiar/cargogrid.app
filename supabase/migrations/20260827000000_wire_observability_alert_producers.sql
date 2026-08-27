-- Track B Batch 1, ISS-2026-249 (closes docs/runtime/KNOWN_ISSUES.md ISS-2026-249):
-- app.raise_observability_alert (IAE-030) exists, is fully functional (real
-- dedup, real severity validation), and is already wired into
-- app.record_job_failure and the 3 webhook-ingestion functions -- but 3 other
-- real failure producers never call it at all. Each part below is a
-- `create or replace function` on an UNCHANGED signature, reproducing the
-- function's own current, live-effective body verbatim (confirmed by direct
-- read against the migration that last defined each one) plus exactly one
-- new `perform app.raise_observability_alert(...)` call in the function's
-- own existing terminal-failure branch, immediately before that branch's
-- own normal RETURN -- never before a RAISE EXCEPTION (see the withdrawn
-- Part D note below for why that placement is unsafe). No new grant is
-- needed for any part: app.raise_observability_alert is SECURITY DEFINER,
-- service_role-granted: HDN-373/ADR-0011's own established composition
-- pattern (already proven live for app.record_job_failure and the 3
-- webhook-ingestion functions) means a SECURITY DEFINER caller (or a
-- service_role-granted invoker caller) reaches it with zero extra grant.
--
-- Three related gaps investigated but deliberately NOT folded into this
-- pass, disclosed rather than silently narrowed:
--   - app.evaluate_permission (the general RBAC denial path) is decision-only
--     (never raises) and is called for both real enforcement and pure UI
--     permission-probing -- wiring an alert there would fire on benign
--     "should I show this button" checks, a false-positive-flood design
--     error, not a bounded fix. Genuinely architectural; stays open.
--   - app.assert_current_step_up_authorization (MFA step-up denial) captures
--     ZERO durable evidence today (no audit row, unlike the issue's own
--     framing assumed) and is declared `stable`, so closing it needs a new
--     log table/insert AND a volatility change, not a one-line mirror of the
--     pattern below. A materially bigger unit of work; stays open.
--   - app.assert_ip_allowed (a bounded security-denial slice, originally
--     drafted as Part D of this migration) was WITHDRAWN before being
--     applied, caught by the local db-tests suite itself: its own denial
--     path calls `perform app.raise_observability_alert(...)` and then
--     immediately `raise exception 'ip_not_allowed...'` to deny the caller
--     -- but every real caller of this function catches that specific
--     exception (that is the entire mechanism by which "enforce and let the
--     caller handle the denial" works), and PL/pgSQL's implicit savepoint
--     at a caught exception's own BEGIN...EXCEPTION...END block rolls back
--     EVERYTHING since that savepoint, including the alert INSERT the
--     callee already made -- so the alert would silently never persist in
--     the exact scenario it exists to cover. Closing this correctly needs
--     either an autonomous-transaction mechanism (e.g. dblink, a real new
--     dependency) or moving the alert call to the CALLING code instead of
--     inside the enforcement function itself (a design change, not a
--     same-signature body edit) -- stays open, disclosed with this exact
--     root cause rather than shipped silently non-functional.

-- ===========================================================================
-- Part A: app.record_webhook_delivery_attempt -- alert on dead-letter
-- ===========================================================================
-- Verbatim current body from 20260809100000_harden_intelligence_iae037_
-- security_ai_hardening.sql, plus one new alert call once a delivery reaches
-- its terminal 'dead_letter' state (endpoint auto-disable at 10 consecutive
-- failures is the OTHER, already-alerted symptom of the same underlying
-- pattern -- this closes the delivery-level signal directly, which fires
-- earlier and per-delivery rather than only once per endpoint).
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
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id for update;
  if not found then
    raise exception 'webhook_delivery_not_found: no delivery %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if v_delivery.status in ('delivered', 'dead_letter') then
    raise exception 'webhook_delivery_already_terminal: delivery % is already %, no further attempts may be recorded', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  if not (p_status = any (array['success', 'failed'])) then
    raise exception 'webhook_invalid_attempt_status: % is not one of success/failed', p_status using errcode = 'check_violation';
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

    -- ISS-2026-249: the delivery just reached its own terminal failure state
    -- (dead_letter) -- raise a real, tenant-scoped observability alert. Fires
    -- once per dead-lettered delivery, independent of the endpoint-level
    -- auto-disable counter, and dedupes against a same-window repeat via
    -- app.raise_observability_alert's own existing advisory-lock dedup.
    if v_updated.status = 'dead_letter' then
      perform app.raise_observability_alert(
        v_delivery.tenant_id, 'webhook', 'error',
        format('webhook delivery dead-lettered: endpoint %s', v_delivery.webhook_endpoint_id),
        'high', p_error_message
      );
    end if;
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
  'PLT-129, extended by IAE-012: real, tested delivery adapter -- exponential backoff on transient failure, dead_letter once max_attempts is reached, endpoint auto-disables at 10 consecutive failures (ADR-0011), a single success resets that counter. IAE-037 Tier C fix: the initial read locks the delivery row (FOR UPDATE), mirroring app.record_notification_delivery_attempt''s own identical fix. ISS-2026-249 fix (Track B Batch 1): a delivery reaching dead_letter now raises a real app.raise_observability_alert (source_type=webhook, signal_type=error, high) -- previously this producer never alerted at all.';

-- ===========================================================================
-- Part B: app.record_integration_health_check -- alert on auto-disable
-- ===========================================================================
-- Verbatim current (sole) body from 20260803020000_create_intelligence_
-- integration_hub.sql, plus one new alert call when an active connection is
-- auto-disabled by the 10-consecutive-unhealthy-check threshold.
create or replace function app.record_integration_health_check(
  p_connection_id uuid,
  p_status text,
  p_detail text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_health_checks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
  v_check app.integration_health_checks;
  v_new_failure_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id for update;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('healthy', 'unhealthy') then
    raise exception 'integration_health_check_invalid_status: % is not one of healthy/unhealthy', p_status using errcode = 'check_violation';
  end if;

  insert into app.integration_health_checks (connection_id, status, detail, checked_by)
  values (p_connection_id, p_status, p_detail, p_actor_label)
  returning * into v_check;

  v_new_failure_count := case when p_status = 'unhealthy' then v_connection.consecutive_failure_count + 1 else 0 end;

  update app.integration_connections
  set last_health_check_at = now(),
      last_health_status = p_status,
      consecutive_failure_count = v_new_failure_count,
      status = case when v_new_failure_count >= 10 and status = 'active' then 'disabled' else status end,
      auto_disabled_at = case when v_new_failure_count >= 10 and status = 'active' then now() else auto_disabled_at end,
      disabled_reason = case when v_new_failure_count >= 10 and status = 'active' then 'auto-disabled after 10 consecutive failed health checks' else disabled_reason end
  where id = p_connection_id;

  -- ISS-2026-249: mirrors Part A above -- alert exactly when THIS call is the
  -- one that crosses the threshold (v_connection.status = 'active' captured
  -- before the UPDATE above), never on every subsequent unhealthy check
  -- after the connection is already disabled.
  if v_new_failure_count >= 10 and v_connection.status = 'active' then
    perform app.raise_observability_alert(
      v_connection.tenant_id, 'integration', 'error',
      format('integration connection auto-disabled: %s consecutive unhealthy checks', v_new_failure_count),
      'high', p_detail
    );
  end if;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_integration_health_check',
    'app.integration_health_checks', v_check.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_check;
end;
$$;

comment on function app.record_integration_health_check is
  'IAE-008: INTHUB:Configure-gated. Records a real, caller-supplied health-check RESULT (the "Test connection" UI action, Prompt 336 §21) -- an automated poller that performs the actual outbound call is disclosed NOT_RUN (design decision 4). Auto-disables an active connection at 10 consecutive unhealthy checks, mirroring ADR-0011''s own threshold. ISS-2026-249 fix (Track B Batch 1): the auto-disable transition now also raises a real app.raise_observability_alert (source_type=integration, signal_type=error, high) -- previously this producer never alerted at all.';

-- ===========================================================================
-- Part C: app.record_ai_governed_request_outcome -- alert on failure
-- ===========================================================================
-- Verbatim current body from 20260809100000_harden_intelligence_iae037_
-- security_ai_hardening.sql, plus one new alert call when a request's
-- genuinely-won pending->terminal transition lands on 'failed'. Placed after
-- the "v_row.id is null" race-loser guard so a losing concurrent caller
-- (which gets ai_governed_request_not_pending, not a real outcome) never
-- raises a spurious alert.
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
  if p_provider_unit_cost_amount is not null and (
    p_provider_unit_cost_amount < 0
    or p_provider_unit_cost_amount >= 'infinity'::numeric
  ) then
    raise exception 'ai_governed_request_invalid_cost_amount: provider_unit_cost_amount must be a real, non-negative, finite number' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

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

  -- ISS-2026-249: a genuinely-recorded failure (never a race loser -- those
  -- raised above already) alerts. Severity medium: a single failed AI call
  -- is not structurally terminal the way a dead-lettered webhook delivery or
  -- an auto-disabled integration connection is.
  if p_status = 'failed' then
    perform app.raise_observability_alert(
      v_request.tenant_id, 'ai', 'error',
      format('AI governed action failed: %s', v_request.feature_code),
      'medium', p_error_message
    );
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
  'IAE-019, hardened by the merged Batch 4 Tier C review (the single most severe finding of this review): the pending-only transition is now the atomic UPDATE ... WHERE status = ''pending'' step itself, closing a live-reproduced race where every concurrent caller could win and silently destroy a human-approved AI output. output_payload is now redacted (app.redact_ai_output_payload_secret_shaped_values), never rejected. billed_amount computed server-side via app.compute_provider_billed_amount (RPD-028). IAE-037 Tier C fix: provider_unit_cost_amount now also rejects NaN and Infinity. ISS-2026-249 fix (Track B Batch 1): a genuinely-recorded failure now raises a real app.raise_observability_alert (source_type=ai, signal_type=error, medium) -- previously this producer never alerted at all.';
