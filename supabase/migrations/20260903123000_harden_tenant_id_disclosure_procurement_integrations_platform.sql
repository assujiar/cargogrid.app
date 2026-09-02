-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 4 of 4 -- Procurement/vendor, finance journals, third-party integrations & webhooks, AI governance, ticketing, and platform security
--
-- Continues the already-established, already-precedented repository fix pass for this
-- defect class (ISS-2026-043 / ISS-2026-048 / ISS-2026-054, and the eight 20260902*
-- harden_tenant_id_disclosure_* migrations immediately preceding these four). Root cause
-- unchanged: a SECURITY DEFINER function looks a record up by its own bare id (the caller
-- does not yet know which tenant owns it), THEN evaluates the actor's authority against
-- the looked-up row's own real tenant_id, and on denial raises
-- 'insufficient_authority: ... for tenant %' interpolating that real tenant_id -- handing
-- it to a caller who has not yet been shown to have ANY relationship to that tenant.
--
-- The fix, identical in shape to 20260902100000_harden_tenant_id_disclosure_finance.sql:
-- fold app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id) into the
-- SAME not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode = 'no_data_found'. A caller with zero membership in the
-- row's real tenant now gets byte-for-byte the error a nonexistent id already produced.
--
-- What is deliberately NOT changed: the authority check itself (evaluate_permission /
-- check_*_authority / can_access_record) is untouched, and a genuine member of that same
-- tenant who merely lacks the specific ROLE authority still reaches the original
-- insufficient_authority raise, with the same insufficient_privilege errcode and the same
-- message text, exactly as before. Preserving that distinction is the point of the fix:
-- only the zero-relationship caller's error shape changes. app.has_active_tenant_membership
-- is itself supreme-admin- and support-grant-aware (20260716111315_create_support_access),
-- so platform administrators and live support grants are unaffected.
--
-- Why this cannot deny a caller who was previously allowed: since
-- 20260810300000_harden_rbac_evaluator_tenant_membership_check, app.evaluate_permission
-- ITSELF refuses to return allowed=true without app.has_active_tenant_membership on the
-- same tenant, and the check_*_authority helpers wrap it. The gate added below is
-- therefore strictly implied by every authority check that already had to pass -- it only
-- moves WHEN the refusal is decided, never WHETHER it is.
--
-- 22 functions in this part. Every definition below is CREATE OR REPLACE against the
-- function's CURRENT live body -- the last migration that defines it, verified per
-- function, not an earlier superseded text. Signatures, volatility, security attribute and
-- search_path are copied verbatim and unchanged, so grants are unaffected.


-- app.access_vendor_compliance_document_evidence
create or replace function app.access_vendor_compliance_document_evidence(
  p_document_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found or not app.has_active_tenant_membership(v_document.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_log := app.authorize_vendor_evidence_file_access(v_document.file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_compliance_document_evidence',
    'app.vendor_compliance_documents', v_document.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_document.file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;


-- app.activate_enterprise_idp_connection
create or replace function app.activate_enterprise_idp_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) then
    raise exception 'iam_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_connection.adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'iam_connection_wrong_adapter: % is not an enterprise SSO connection', p_connection_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from app.iam_sso_login_attempts
    where connection_id = p_connection_id and outcome = 'matched'
  ) then
    raise exception 'enterprise_idp_no_verified_test_login: connection % has no recorded successful test-login resolution -- run app.resolve_enterprise_sso_claims first to prevent a lockout', p_connection_id
      using errcode = 'check_violation';
  end if;

  perform app.assert_current_step_up_authorization(v_connection.tenant_id, p_actor_auth_user_id, 'IAM', 'Configure');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_connection.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_connection.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.set_integration_connection_status(p_connection_id, 'active', null, p_actor_auth_user_id, p_actor_label);
end;
$$;


-- app.approve_mfa_exception
create or replace function app.approve_mfa_exception(
  p_exception_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.mfa_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_exception app.mfa_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_exception from app.mfa_exceptions where id = p_exception_id and status = 'pending' for update;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'mfa_exception_not_pending: % is not a pending exception request', p_exception_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'SEC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_exception.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'mfa_exception_self_approval_forbidden: identity % cannot approve their own request', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.assert_current_step_up_authorization(v_exception.tenant_id, p_actor_auth_user_id, 'SEC', 'Approve');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_exception.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_exception.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.mfa_exceptions
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, decided_at = now()
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_mfa_exception',
    'app.mfa_exceptions', v_exception.id, 'success', null, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;


-- app.assign_ticket
create or replace function app.assign_ticket(
  p_ticket_id uuid, p_expected_version integer, p_assignee_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text,
  p_reason text default null, p_override_workload_limit boolean default false
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_rule app.ticket_routing_rule_versions;
  v_active_count integer;
  v_event_type text;
  v_updated app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or not app.has_active_tenant_membership(v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.assign_helpdesk_ticket instead', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.check_ticket_authority('Assign', v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Assign for tenant %', p_actor_auth_user_id, v_ticket.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reassign a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;

  if p_assignee_employee_id is not null then
    if not exists (select 1 from app.employees e where e.master_record_id = p_assignee_employee_id and e.tenant_id = v_ticket.tenant_id) then
      raise exception 'employee_not_found: %', p_assignee_employee_id using errcode = 'no_data_found';
    end if;
    if not exists (select 1 from app.ticket_queue_members m where m.queue_id = v_ticket.queue_id and m.employee_id = p_assignee_employee_id and m.status = 'active') then
      raise exception 'assignee_not_queue_member: employee % is not an active member of queue %', p_assignee_employee_id, v_ticket.queue_id using errcode = 'check_violation';
    end if;
    -- HRT-290 (decision 9): eligibility (active/available) is a HARD block
    -- for every path, no override -- an inactive/on-leave/terminated
    -- employee can never become a ticket owner regardless of actor
    -- authority. The workload CAP, by contrast, is override-able here
    -- (p_override_workload_limit) -- a manager legitimately needs to push a
    -- genuinely urgent ticket onto someone already at their configured cap;
    -- app.claim_ticket has no such override (decision 9).
    if not app._is_employee_ticket_eligible(v_ticket.tenant_id, p_assignee_employee_id) then
      raise exception 'employee_not_eligible: employee % is not currently active/available for ticket assignment', p_assignee_employee_id using errcode = 'check_violation';
    end if;
    if v_ticket.assignee_employee_id is distinct from p_assignee_employee_id and not p_override_workload_limit then
      v_rule := app._resolve_ticket_routing_rule_for_ticket(v_ticket);
      if v_rule.max_active_assignments_per_member is not null then
        -- Batch-review fix (Finding 2, HIGH, correctness/concurrency lens):
        -- same shared, unlocked-count race as app.claim_ticket above --
        -- serialize on the same (tenant_id, queue_id) resource before
        -- reading the count.
        perform pg_advisory_xact_lock(hashtextextended('ticket_assignment_workload:' || v_ticket.tenant_id::text || ':' || v_ticket.queue_id::text, 0));
        v_active_count := app._count_employee_active_ticket_assignments(v_ticket.tenant_id, p_assignee_employee_id, v_ticket.queue_id);
        if v_active_count >= v_rule.max_active_assignments_per_member then
          raise exception 'workload_limit_exceeded: employee already holds % active tickets in this queue, at or above the configured limit of % -- pass p_override_workload_limit to override', v_active_count, v_rule.max_active_assignments_per_member
            using errcode = 'check_violation';
        end if;
      end if;
    end if;
  end if;

  if v_ticket.assignee_employee_id is null and p_assignee_employee_id is not null then
    v_event_type := 'manual_assign';
  elsif v_ticket.assignee_employee_id is not null and p_assignee_employee_id is null then
    v_event_type := 'unassign';
  elsif v_ticket.assignee_employee_id is distinct from p_assignee_employee_id then
    v_event_type := 'reassign';
  else
    -- Idempotent replay: same assignee already set. A real, deliberate
    -- no-op, never a duplicate ledger row (C-01 discipline).
    return v_ticket;
  end if;

  v_updated := app._apply_ticket_assignment(v_ticket, p_expected_version, p_assignee_employee_id, v_event_type, 'manual', null, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;


-- app.close_rfq_for_comparison
create or replace function app.close_rfq_for_comparison(
  p_rfq_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
begin
  -- Batch 257-259 review (C-04, HIGH): child (invitations) locked before parent
  -- (rfq), matching design note 8 and closing a live-reproduced deadlock against
  -- app.submit_rfq_response/app.decline_rfq_invitation's own established order.
  -- A no-op (locks nothing) when p_rfq_id has zero currently-invited invitations.
  perform 1 from app.rfq_invitations where rfq_id = p_rfq_id and status = 'invited' for update;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and cannot be closed for comparison', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  update app.rfq_invitations set status = 'no_response' where rfq_id = p_rfq_id and status = 'invited';

  update app.rfqs
  set status = 'closed', closed_at = now()
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'issued', 'closed', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_rfq_for_comparison',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('status', v_rfq.status)
  );

  return v_rfq;
end;
$$;


-- app.decide_ai_output_approval
create or replace function app.decide_ai_output_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null,
  p_client_ip text default null
)
returns app.approval_request_steps
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_request app.ai_governed_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'ai_output_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'ai_governed_output' then
    raise exception 'ai_output_approval_wrong_domain: step % does not belong to an AI output acceptance request', p_request_step_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_approval_request.entity_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_output_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;
  if not app.check_ai_governance_authority('Approve', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.assert_current_step_up_authorization(v_request.tenant_id, p_actor_auth_user_id, 'AI', 'Approve');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_request.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_request.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;


-- app.decide_vendor_kpi_manual_adjustment
create or replace function app.decide_vendor_kpi_manual_adjustment(p_adjustment_id uuid, p_expected_version integer, p_decision text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_adjustment app.vendor_kpi_manual_adjustments;
  v_scorecard app.vendor_kpi_scorecards;
  v_line app.vendor_kpi_scorecard_lines;
  v_new_composite numeric;
  v_weighted_sum numeric := 0;
  v_computable_weight numeric := 0;
  v_row record;
begin
  select * into v_adjustment from app.vendor_kpi_manual_adjustments where id = p_adjustment_id for update;
  if not found or not app.has_active_tenant_membership(v_adjustment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_manual_adjustment_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_adjustment.tenant_id, 'PRC', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_adjustment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_adjustment.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested manual adjustment % and may not also decide it', p_actor_auth_user_id, p_adjustment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_adjustment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI manual adjustment % expected version % but found %', p_adjustment_id, p_expected_version, v_adjustment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_adjustment.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor KPI manual adjustment % is % and cannot be decided', p_adjustment_id, v_adjustment.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_manual_adjustments
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = now(), decision_notes = p_decision_notes
  where id = p_adjustment_id and record_version = p_expected_version
  returning * into v_adjustment;
  if not found then
    raise exception 'stale_version: vendor KPI manual adjustment % target row was concurrently modified (expected version %)', p_adjustment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approved' then
    select * into v_scorecard from app.vendor_kpi_scorecards where id = v_adjustment.scorecard_id for update;

    -- C-04 (Tier C batch-4 fix, HIGH, live-reproduced): re-verify the scorecard is
    -- STILL the current, published one at the actual point of commitment -- never
    -- trust that it still is just because it was published when the adjustment was
    -- first requested. An ordinary recalculation cycle in between (app.calculate_
    -- vendor_kpi_metrics + app.publish_vendor_kpi_scorecard superseding it) must fail
    -- this loudly rather than silently rewrite a dead, superseded scorecard while the
    -- vendor's real current scorecard stays untouched. Mirrors app.decide_vendor_bill_
    -- match_exception_approval's own identical C-15 re-verification in the companion
    -- PRC-265 migration.
    if not v_scorecard.is_current or v_scorecard.status <> 'published' then
      raise exception 'stale_scorecard: vendor KPI scorecard % is no longer the current published scorecard for this vendor/window -- it was superseded by a later recalculation while this adjustment was pending. Request a fresh manual adjustment against the current scorecard instead', v_scorecard.id
        using errcode = 'check_violation';
    end if;

    update app.vendor_kpi_scorecard_lines
    set normalized_score = v_adjustment.adjusted_normalized_score,
      band = app._band_for_score(v_adjustment.adjusted_normalized_score, band_thresholds_snapshot),
      is_computable = true, adjusted = true
    where id = v_adjustment.scorecard_line_id
    returning * into v_line;

    for v_row in select weight_snapshot, normalized_score, is_computable from app.vendor_kpi_scorecard_lines where scorecard_id = v_scorecard.id loop
      if v_row.is_computable then
        v_computable_weight := v_computable_weight + v_row.weight_snapshot;
        v_weighted_sum := v_weighted_sum + (v_row.weight_snapshot * v_row.normalized_score);
      end if;
    end loop;
    v_new_composite := round(v_weighted_sum / nullif(v_computable_weight, 0), 2);

    update app.vendor_kpi_scorecards
    set composite_score = v_new_composite, band = app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb), computable_weight_total = v_computable_weight
    where id = v_scorecard.id and record_version = v_scorecard.record_version;
    if not found then
      raise exception 'stale_version: vendor KPI scorecard % was concurrently modified while applying an adjustment', v_scorecard.id using errcode = 'serialization_failure';
    end if;

    perform app.capture_audit_event(
      v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_vendor_kpi_manual_adjustment',
      'app.vendor_kpi_scorecards', v_scorecard.id, 'success', p_decision_notes,
      jsonb_build_object('composite_score', v_scorecard.composite_score, 'band', v_scorecard.band),
      jsonb_build_object('composite_score', v_new_composite, 'band', app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb))
    );
  end if;

  perform app.capture_audit_event(
    v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_kpi_manual_adjustment',
    'app.vendor_kpi_manual_adjustments', v_adjustment.id, 'success', p_decision_notes, null, jsonb_build_object('status', v_adjustment.status)
  );

  return v_adjustment;
end;
$$;


-- app.decide_vendor_profile_review
create or replace function app.decide_vendor_profile_review(
  p_master_record_id uuid,
  p_expected_version integer,
  p_decision text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_new_status text;
  v_from_status text;
  v_action text;
  v_next_version integer;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a vendor profile' using errcode = 'check_violation';
  end if;

  -- Batch 257-259 review (C-04, HIGH): locked, closing a live-reproduced
  -- concurrent-double-decide crash (see migration header above this function).
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_action := case p_decision when 'approve' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor profile % is % and cannot be decided', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'draft' end;
  -- Capture the row's REAL prior status before the UPDATE overwrites v_profile --
  -- begin_vendor_profile_review is optional (design note 5), so a decision can
  -- legitimately be made directly from 'submitted', skipping 'under_review'. A
  -- hardcoded 'under_review' literal here would corrupt the append-only audit
  -- timeline the vendor detail UI reads directly (found in adversarial review).
  v_from_status := v_profile.lifecycle_status;
  v_next_version := p_expected_version + 1;

  -- PRC-259: only the approve arm ever routes for governance -- a reject returns the
  -- profile to draft, never reaching activation, so there is nothing to route.
  if p_decision = 'approve' then
    select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
    from app._request_procurement_entity_approval(
      'vendor_activation', v_profile.tenant_id, p_master_record_id, null, null,
      jsonb_build_object('legal_name', v_profile.legal_name, 'vendor_category', v_profile.vendor_category),
      v_next_version, 'vendor_activation:' || p_master_record_id::text || ':v' || v_next_version::text,
      p_actor_auth_user_id, p_actor_label
    ) r;
  else
    v_gov_approval_status := v_profile.approval_status;
    v_gov_approval_request_id := v_profile.approval_request_id;
  end if;

  update app.vendor_profiles
  set lifecycle_status = v_new_status,
      revision_reason = case when p_decision = 'reject' then p_reason else revision_reason end,
      approval_status = v_gov_approval_status,
      approval_request_id = v_gov_approval_request_id,
      record_version = record_version + 1,
      updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, v_from_status, v_new_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_profile_review',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'lifecycle_status', v_new_status, 'approval_status', v_gov_approval_status)
  );

  return v_profile;
end;
$$;


-- app.disable_third_party_provider_connection
create or replace function app.disable_third_party_provider_connection(
  p_connection_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.third_party_provider_connections
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_updated app.third_party_provider_connections;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_conn.tenant_id, p_actor_auth_user_id) then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_conn.status = 'disabled' then
    return v_conn;
  end if;

  update app.third_party_provider_connections
  set status = 'disabled', auto_disabled_at = now(), disabled_reason = coalesce(p_reason, 'manual disable')
  where id = p_connection_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'disable_third_party_provider_connection',
    'app.third_party_provider_connections', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_conn.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;


-- app.get_ai_quotation_suggestion
create or replace function app.get_ai_quotation_suggestion(p_suggestion_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, opportunity_id uuid, ai_governed_request_id uuid, status text,
  accepted_quotation_id uuid, dismiss_reason text, requested_by text, reviewed_by text, reviewed_at timestamptz, created_at timestamptz,
  output_payload jsonb, output_payload_masked boolean, confidence_label text, model_version text, billed_amount numeric, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_can_view_cost boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select s.* into v_suggestion from app.ai_quotation_suggestions s where s.id = p_suggestion_id;
  if not found or not app.has_active_tenant_membership(v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('View', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_cost := app.check_ai_quotation_suggestion_authority('View cost', v_suggestion.tenant_id, p_actor_auth_user_id);

  return query
  select s.id, s.tenant_id, s.opportunity_id, s.ai_governed_request_id, s.status,
    s.accepted_quotation_id, s.dismiss_reason, s.requested_by, s.reviewed_by, s.reviewed_at, s.created_at,
    case when v_can_view_cost then r.output_payload else null end, not v_can_view_cost,
    r.confidence_label, r.model_version, r.billed_amount, r.status
  from app.ai_quotation_suggestions s
  join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  where s.id = p_suggestion_id;
end;
$$;


-- app.re_evaluate_vendor_bill_match_case
create or replace function app.re_evaluate_vendor_bill_match_case(
  p_match_case_id uuid,
  p_expected_version integer,
  p_purchase_order_id uuid,
  p_line_inputs jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bill_match_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prior app.vendor_bill_match_cases;
  v_bill app.finance_vendor_bills;
  v_po app.purchase_orders;
  v_contract app.vendor_contracts;
  v_policy app.vendor_bill_match_tolerance_policies;
  v_case app.vendor_bill_match_cases;
  v_bill_line app.finance_vendor_bill_lines;
  v_line_input jsonb;
  v_line app.vendor_bill_match_lines;
  v_component app.shipment_actual_cost_components;
  v_fingerprint text;
  v_dup_case_id uuid;
  v_match_mode text;
  v_has_epod boolean := false;
  v_has_delivery_ms boolean := false;
  v_shipment_id uuid;
begin
  -- C-04: lock the CURRENT version row before deciding anything from it.
  select * into v_prior from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_prior.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_prior.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_prior.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_prior.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_prior.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_prior.is_current then
    raise exception 'invalid_transition: match case % is not the current version', p_match_case_id using errcode = 'check_violation';
  end if;
  if v_prior.overall_status in ('cancelled', 'disputed') then
    raise exception 'invalid_transition: match case % is % and cannot be re-evaluated -- resolve the open dispute or start a new case', p_match_case_id, v_prior.overall_status
      using errcode = 'check_violation';
  end if;

  -- C-15: re-verify the bill's own current state at the actual point of commitment,
  -- never trust the version 1 snapshot.
  select * into v_bill from app.finance_vendor_bills where id = v_prior.bill_id;
  if not found or v_bill.status = 'void' then
    raise exception 'finance_vendor_bill_void: bill % is void and cannot be re-evaluated', v_prior.bill_id using errcode = 'check_violation';
  end if;

  if p_line_inputs is null or jsonb_typeof(p_line_inputs) <> 'array' then
    raise exception 'line_inputs_required: p_line_inputs must be a jsonb array' using errcode = 'check_violation';
  end if;

  if p_purchase_order_id is not null then
    select * into v_po from app.purchase_orders where id = p_purchase_order_id and tenant_id = v_prior.tenant_id;
    if not found then
      raise exception 'purchase_order_not_found: % is not a known purchase order for tenant %', p_purchase_order_id, v_prior.tenant_id using errcode = 'no_data_found';
    end if;
    if v_po.vendor_master_id <> v_bill.vendor_master_id then
      raise exception 'po_vendor_mismatch: purchase order % belongs to a different vendor than bill %', p_purchase_order_id, v_prior.bill_id using errcode = 'check_violation';
    end if;
    if v_po.status not in ('issued', 'acknowledged') then
      raise exception 'po_not_committed: purchase order % is % -- only issued/acknowledged purchase orders are valid match evidence', p_purchase_order_id, v_po.status
        using errcode = 'check_violation';
    end if;
    if v_po.currency <> v_bill.currency then
      raise exception 'po_currency_mismatch: purchase order % is % but bill % is %', p_purchase_order_id, v_po.currency, v_prior.bill_id, v_bill.currency
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_contract from app.resolve_effective_vendor_contract(v_prior.tenant_id, v_bill.vendor_master_id, v_bill.bill_date::timestamptz, p_actor_auth_user_id);
  v_match_mode := case when v_po.id is not null then 'po_three_way' when v_contract.id is not null then 'contract_two_way' else 'non_po' end;
  select * into v_policy from app.vendor_bill_match_tolerance_policies where tenant_id = v_prior.tenant_id and status = 'active';
  v_fingerprint := app.compute_vendor_bill_match_fingerprint(v_prior.tenant_id, v_bill.vendor_master_id, v_bill.currency, v_bill.total_amount);

  -- C-04 (Tier C batch-4 fix, CRITICAL, live-reproduced): the identical duplicate-
  -- fingerprint race app.create_vendor_bill_match_case had, serialized the same way.
  perform pg_advisory_xact_lock(hashtext(v_prior.tenant_id::text || ':' || v_fingerprint));

  -- NEW (Tier C batch-4 fix, MEDIUM, live-reproduced): re-resolve fulfillment evidence
  -- fresh, exactly like app.create_vendor_bill_match_case does -- NEVER copy v_prior's
  -- own has_epod_evidence/has_delivery_milestone_evidence forward. A case re-evaluated
  -- after new delivery evidence actually arrived must reflect it, not keep showing a
  -- stale "no ePOD"/"no delivery milestone" badge indefinitely.
  select ra.shipment_order_id into v_shipment_id
  from app.shipment_actual_cost_components sacc
  join app.resource_assignments ra on ra.id = sacc.assignment_id
  where sacc.actual_cost_id = v_bill.actual_cost_id
  limit 1;
  if v_shipment_id is not null then
    v_has_epod := exists (select 1 from app.epod_captures e where e.shipment_order_id = v_shipment_id and e.status = 'completed');
    v_has_delivery_ms := exists (
      select 1 from app.milestone_events ev join app.milestone_codes mc on mc.code = ev.milestone_code
      where ev.shipment_order_id = v_shipment_id and mc.category = 'delivery'
    );
  end if;

  update app.vendor_bill_match_cases set is_current = false where id = v_prior.id;

  insert into app.vendor_bill_match_cases (
    tenant_id, bill_id, version_no, vendor_master_id, currency, match_mode, is_partial_invoice, is_consolidated_invoice,
    purchase_order_id, vendor_contract_id, tolerance_policy_id, tolerance_policy_version_no,
    quantity_tolerance_pct_snapshot, rate_tolerance_pct_snapshot, tax_tolerance_pct_snapshot, line_amount_tolerance_abs_snapshot, auto_clear_enabled_snapshot,
    has_epod_evidence, has_delivery_milestone_evidence, duplicate_fingerprint, evaluated_by, idempotency_key, created_by
  )
  values (
    v_prior.tenant_id, v_prior.bill_id, v_prior.version_no + 1, v_bill.vendor_master_id, v_bill.currency, v_match_mode, v_prior.is_partial_invoice, v_prior.is_consolidated_invoice,
    p_purchase_order_id, v_contract.id, v_policy.id, v_policy.version_no,
    coalesce(v_policy.quantity_tolerance_pct, 0), coalesce(v_policy.rate_tolerance_pct, 0), coalesce(v_policy.tax_tolerance_pct, 0), coalesce(v_policy.line_amount_tolerance_abs, 0), coalesce(v_policy.auto_clear_enabled, false),
    v_has_epod, v_has_delivery_ms, v_fingerprint, p_actor_label, v_prior.tenant_id::text || ':' || p_match_case_id::text || ':v' || (v_prior.version_no + 1)::text, p_actor_label
  )
  returning * into v_case;

  select mc.id into v_dup_case_id
  from app.vendor_bill_match_cases mc
  join app.finance_vendor_bills b on b.id = mc.bill_id
  where mc.tenant_id = v_prior.tenant_id and mc.is_current and mc.id <> v_case.id and mc.duplicate_fingerprint = v_fingerprint
    and abs(b.bill_date - v_bill.bill_date) <= coalesce(v_policy.duplicate_window_days, 30)
  order by mc.created_at asc
  limit 1;
  if found then
    update app.vendor_bill_match_cases set is_duplicate_flagged = true, duplicate_of_case_id = v_dup_case_id where id = v_case.id;
  end if;

  for v_bill_line in select * from app.finance_vendor_bill_lines where bill_id = v_prior.bill_id order by line_number asc loop
    select value into v_line_input from jsonb_array_elements(p_line_inputs) as value
      where (value ->> 'billLineId')::uuid = v_bill_line.id
      limit 1;
    if v_line_input is null or v_line_input ->> 'vendorStatedAmount' is null then
      raise exception 'vendor_stated_amount_required: bill line % has no vendor-stated amount supplied in p_line_inputs', v_bill_line.id using errcode = 'check_violation';
    end if;

    v_component := null;
    if v_bill_line.source_component_id is not null then
      select * into v_component from app.shipment_actual_cost_components where id = v_bill_line.source_component_id;
    end if;

    insert into app.vendor_bill_match_lines (
      tenant_id, match_case_id, bill_line_id, line_no, line_type,
      vendor_stated_quantity, vendor_stated_uom, vendor_stated_rate, vendor_stated_amount,
      actual_cost_component_id, evidence_quantity, evidence_uom, evidence_rate, evidence_amount, evidence_currency
    )
    values (
      v_prior.tenant_id, v_case.id, v_bill_line.id, v_bill_line.line_number, v_bill_line.line_type,
      (v_line_input ->> 'vendorStatedQuantity')::numeric, v_line_input ->> 'vendorStatedUom', (v_line_input ->> 'vendorStatedRate')::numeric, (v_line_input ->> 'vendorStatedAmount')::numeric,
      v_component.id,
      case when v_component.id is not null then v_component.quantity else null end,
      case when v_component.id is not null then v_component.uom else null end,
      case when v_component.id is not null then v_component.rate else null end,
      case when v_bill_line.line_type = 'tax' then v_bill_line.amount when v_component.id is not null then v_component.amount else null end,
      case when v_component.id is not null then v_component.currency when v_bill_line.line_type = 'tax' then v_bill.currency else null end
    )
    returning * into v_line;

    v_line := app._score_vendor_bill_match_line(v_line, v_case);
    update app.vendor_bill_match_lines set
      quantity_variance_pct = v_line.quantity_variance_pct, rate_variance_pct = v_line.rate_variance_pct,
      amount_variance_amount = v_line.amount_variance_amount, amount_variance_pct = v_line.amount_variance_pct,
      uom_mismatch = v_line.uom_mismatch, currency_mismatch = v_line.currency_mismatch, line_status = v_line.line_status
    where id = v_line.id;
  end loop;

  v_case := app._reroll_vendor_bill_match_case(v_case.id);

  perform app._record_vendor_bill_match_event(v_prior.tenant_id, v_case.id, 'case_re_evaluated', jsonb_build_object('versionNo', v_case.version_no, 'overallStatus', v_case.overall_status), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_prior.tenant_id, p_actor_auth_user_id, p_actor_label, 're_evaluate_vendor_bill_match_case', 'app.vendor_bill_match_cases', v_case.id, 'success', null, null, jsonb_build_object('versionNo', v_case.version_no, 'overallStatus', v_case.overall_status));

  return v_case;
end;
$$;


-- app.reenable_third_party_provider_connection
create or replace function app.reenable_third_party_provider_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.third_party_provider_connections
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_updated app.third_party_provider_connections;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_conn.tenant_id, p_actor_auth_user_id) then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.third_party_provider_connections
  set status = 'active', consecutive_failure_count = 0, auto_disabled_at = null, disabled_reason = null
  where id = p_connection_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'reenable_third_party_provider_connection',
    'app.third_party_provider_connections', v_updated.id, 'success', null,
    jsonb_build_object('status', v_conn.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;


-- app.replay_webhook_delivery
create or replace function app.replay_webhook_delivery(
  p_delivery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_delivery app.webhook_deliveries;
  v_updated app.webhook_deliveries;
  v_idempotency_key text;
begin
  -- Tier C Batch 3 fix (finding 2): FOR UPDATE serializes concurrent
  -- replays of the SAME delivery -- a second caller blocks here, then (once
  -- the first commits) re-reads the ALREADY-UPDATED row and is cleanly
  -- rejected by the status check below instead of double-enqueuing.
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id for update;
  if not found or not app.has_active_tenant_membership(v_delivery.tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_delivery_not_found: no delivery %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_delivery.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_delivery.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_delivery.status <> 'dead_letter' then
    raise exception 'webhook_delivery_not_replayable: delivery % is %, only a dead_letter delivery may be replayed', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  -- Tier C Batch 3 fix (finding 1): NEVER reset attempts -- app.webhook_
  -- delivery_attempts is append-only and app.record_webhook_delivery_attempt
  -- computes the next attempt_number as attempts+1, so resetting to 0 would
  -- collide with the already-recorded history. Instead grant a fresh BUDGET
  -- of max_attempts (the delivery's own currently-configured value) MORE
  -- real attempts on top of whatever was already used.
  update app.webhook_deliveries
  set status = 'pending', next_attempt_at = now(), max_attempts = attempts + max_attempts
  where id = p_delivery_id
  returning * into v_updated;

  v_idempotency_key := 'webhook-replay:' || p_delivery_id::text || ':' || extract(epoch from clock_timestamp())::text;

  perform app.enqueue_job(
    v_delivery.tenant_id, 'webhook_retry',
    jsonb_build_object('delivery_id', p_delivery_id),
    5, v_idempotency_key, v_updated.max_attempts,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_delivery.tenant_id, p_actor_auth_user_id, p_actor_label, 'replay_webhook_delivery',
    'app.webhook_deliveries', p_delivery_id, 'success', null,
    jsonb_build_object('status', v_delivery.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;


-- app.request_ai_output_approval
create or replace function app.request_ai_output_approval(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.approval_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.ai_governed_requests;
  v_approval_version_id uuid;
  v_approval_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'succeeded' then
    raise exception 'ai_governed_request_not_succeeded: request % is % not succeeded -- only a real, completed output may be sent for approval', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_request.approval_request_id is not null then
    raise exception 'ai_governed_request_approval_already_requested: request % already has an approval request', p_request_id using errcode = 'check_violation';
  end if;

  select cv.id into v_approval_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:ai_output_acceptance' and co.tenant_id = v_request.tenant_id and co.scope_level = 'tenant';

  if v_approval_version_id is null then
    raise exception 'ai_output_acceptance_approval_not_configured: tenant % has not published an approval:ai_output_acceptance definition yet', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  -- Tier C fix: app.request_approval's own idempotency guard (PLT-123) is
  -- itself an unlocked check-then-insert -- two concurrent callers here can
  -- both pass the approval_request_id is not null check above, then race
  -- into app.request_approval, where the loser hits a raw unique_violation
  -- on approval_requests_tenant_idempotency_unique. Translate that into the
  -- same clean, named error the sequential (non-racing) path already
  -- raises above, rather than a raw 23505 naming an internal constraint.
  begin
    select * into v_approval_request from app.request_approval(
      v_approval_version_id, v_request.tenant_id, 'ai_governed_output', v_request.id,
      'ai-output-acceptance-' || v_request.id, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'ai_governed_request_approval_already_requested: request % already has an approval request', p_request_id using errcode = 'check_violation';
  end;

  update app.ai_governed_requests set approval_request_id = v_approval_request.id where id = p_request_id;

  return v_approval_request;
end;
$$;


-- app.review_external_sync_conflict
create or replace function app.review_external_sync_conflict(
  p_record_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.external_sync_records;
  v_row app.external_sync_records;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'external_sync_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_record from app.external_sync_records where id = p_record_id;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'external_sync_record_not_found: %', p_record_id using errcode = 'no_data_found';
  end if;

  if not app.check_external_sync_entity_authority('Edit', v_record.entity_type, v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: only a record still awaiting review (no_conflict or
  -- conflicts_detected -- a no_conflict record CAN still be explicitly
  -- reviewed/acknowledged) may be decided; reviewed/dismissed is terminal.
  -- Mirrors app.review_logistics_partner_event's own fix.
  update app.external_sync_records
  set conflict_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_record_id and conflict_status in ('no_conflict', 'conflicts_detected')
  returning * into v_row;

  if v_row.id is null then
    raise exception 'external_sync_record_already_reviewed: record % has already been decided (%)', p_record_id, v_record.conflict_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_external_sync_conflict',
    'app.external_sync_records', v_row.id, 'success', null, to_jsonb(v_record), to_jsonb(v_row)
  );

  return v_row;
end;
$$;


-- app.review_finance_payment_gateway_event
create or replace function app.review_finance_payment_gateway_event(
  p_event_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_payment_gateway_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_event app.finance_payment_gateway_events;
  v_row app.finance_payment_gateway_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'finance_payment_event_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_event from app.finance_payment_gateway_events where id = p_event_id;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_payment_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_provider_trigger_authority(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: mirrors app.review_logistics_partner_event's own fix
  -- exactly -- only a not-yet-decided ('received') event may be decided.
  update app.finance_payment_gateway_events
  set processing_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_event_id and processing_status = 'received'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'finance_payment_event_already_reviewed: event % has already been decided (%)', p_event_id, v_event.processing_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_finance_payment_gateway_event',
    'app.finance_payment_gateway_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;


-- app.review_logistics_partner_event
create or replace function app.review_logistics_partner_event(
  p_event_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.logistics_partner_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_event app.logistics_partner_events;
  v_decision app.rbac_decision;
  v_row app.logistics_partner_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'logistics_partner_event_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_event from app.logistics_partner_events where id = p_event_id;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'logistics_partner_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: only a not-yet-decided ('received') event may be decided --
  -- live-reproduced that two concurrent reviewers could both be told they
  -- succeeded, with the second decision silently overwriting the first (a
  -- lost update, no optimistic-concurrency token existed at all).
  update app.logistics_partner_events
  set processing_status = p_decision,
      review_notes = p_notes,
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now()
  where id = p_event_id and processing_status = 'received'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'logistics_partner_event_already_reviewed: event % has already been decided (%)', p_event_id, v_event.processing_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_logistics_partner_event',
    'app.logistics_partner_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;


-- app.revoke_vendor_intake_token
create or replace function app.revoke_vendor_intake_token(p_token_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_intake_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_token app.vendor_intake_tokens;
  v_prior_version integer;
begin
  select * into v_token from app.vendor_intake_tokens where id = p_token_id;
  if not found or not app.has_active_tenant_membership(v_token.tenant_id, p_actor_auth_user_id) then
    raise exception 'token_not_found: %', p_token_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_token.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_token.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke an intake token' using errcode = 'check_violation';
  end if;
  if v_token.status <> 'pending' then
    raise exception 'invalid_transition: intake token % is % and cannot be revoked', p_token_id, v_token.status using errcode = 'check_violation';
  end if;

  v_prior_version := v_token.record_version;
  update app.vendor_intake_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, record_version = record_version + 1
  where id = p_token_id and record_version = v_prior_version
  returning * into v_token;
  if not found then
    raise exception 'stale_version: intake token % target row was concurrently modified (expected version %)', p_token_id, v_prior_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_token.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_vendor_intake_token',
    'app.vendor_intake_tokens', v_token.id, 'success', p_reason, null, '{}'::jsonb
  );

  -- ISS-2026-232 Tier C fix: mask token_hash on the returned composite.
  v_token.token_hash := null;
  return v_token;
end;
$$;


-- app.rotate_third_party_provider_webhook_secret
create or replace function app.rotate_third_party_provider_webhook_secret(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (connection_id uuid, raw_webhook_secret text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_raw_secret text;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_conn.tenant_id, p_actor_auth_user_id) then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_conn.integration_mode <> 'webhook' then
    raise exception 'not_a_webhook_connection: % is a % connection, has no webhook secret to rotate', p_connection_id, v_conn.integration_mode
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_raw_secret := 'tpws_' || encode(gen_random_bytes(32), 'hex');

  update app.third_party_provider_connections set webhook_secret_value_encrypted = app._encrypt_integration_secret(v_raw_secret) where id = p_connection_id;

  perform app.capture_audit_event(
    v_conn.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_third_party_provider_webhook_secret',
    'app.third_party_provider_connections', p_connection_id, 'success', null, null, jsonb_build_object('connection_id', p_connection_id)
  );

  return query select v_conn.id, v_raw_secret;
end;
$$;


-- app.rotate_webhook_secret
create or replace function app.rotate_webhook_secret(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (id uuid, tenant_id uuid, url text, status text, raw_secret text)
language plpgsql
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_new_secret text;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where app.webhook_endpoints.id = p_endpoint_id;
  if not found or not app.has_active_tenant_membership(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  update app.webhook_endpoints set secret_value_encrypted = app._encrypt_integration_secret(v_new_secret) where app.webhook_endpoints.id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_webhook_secret',
    'app.webhook_endpoints', v_updated.id, 'success', null, null, jsonb_build_object('id', v_updated.id)
  );

  return query select v_updated.id, v_updated.tenant_id, v_updated.url, v_updated.status, v_new_secret;
end;
$$;


-- app.submit_finance_journal_for_approval
create or replace function app.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found or not app.has_active_tenant_membership(v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Edit', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'draft' then
    raise exception 'finance_journal_not_draft: journal % is % not draft', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals
    set status = 'submitted', submitted_by = p_actor_label, submitted_by_auth_user_id = p_actor_auth_user_id, submitted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_journal_for_approval',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;


-- app.update_master_record
create or replace function app.update_master_record(p_record_id uuid, p_expected_version integer, p_name text, p_aliases jsonb, p_attributes jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.master_records
 LANGUAGE plpgsql
AS $function$
declare
  v_before app.master_records;
  v_after app.master_records;
begin
  select * into v_before from app.master_records where id = p_record_id for update;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'master_record_not_found: no master record %', p_record_id
      using errcode = 'no_data_found';
  end if;

  if v_before.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may update a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_before.canonical_status <> 'active' then
    raise exception 'master_record_not_active: record % is %, only an active record may be updated', p_record_id, v_before.canonical_status
      using errcode = 'check_violation';
  end if;

  if v_before.record_version <> p_expected_version then
    raise exception 'stale_record_version: expected version % but record % is at version %', p_expected_version, p_record_id, v_before.record_version
      using errcode = 'check_violation';
  end if;

  update app.master_records
  set name = coalesce(p_name, name),
      aliases = coalesce(p_aliases, aliases),
      attributes = coalesce(p_attributes, attributes)
  where id = p_record_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_master_record',
    'app.master_records', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$function$;
