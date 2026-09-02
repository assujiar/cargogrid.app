-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Third fix pass, Procurement lane (vendor performance + procurement dashboard saved views).
--
-- Root cause (unchanged since the original disclosure): these SECURITY DEFINER functions
-- look a record up by its own bare `id` (the caller does not yet know which tenant owns
-- it), THEN evaluate the actor's authority against the looked-up row's own real
-- tenant_id, and on denial raise 'insufficient_authority: ... for tenant %', interpolating
-- that real tenant_id -- disclosing it to a caller who has not been shown to have any
-- relationship to that tenant at all.
--
-- Fix (identical to the already-established, already-precedented shape this repository
-- has used for the same defect class in ISS-2026-043/048/054 and in the merged
-- 20260902100000-20260902104000 / 20260902200000-20260902201000 passes): fold
-- `app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id)` into the SAME
-- not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode='no_data_found'. A caller with zero relationship to the
-- record's real tenant now gets exactly the error a nonexistent id already produced; only
-- a confirmed member of that tenant (or a Supreme Admin / live support grant, both of
-- which app.has_active_tenant_membership already returns true for) ever reaches the
-- specific, tenant_id-bearing insufficient_authority line below it.
--
-- No authority check is weakened anywhere: every evaluate_permission /
-- check_*_authority call below is byte-identical to its pre-existing body, and a genuine
-- same-tenant member who merely lacks the role authority still gets the same
-- insufficient_authority message with the same insufficient_privilege errcode as before.
-- Only a zero-membership foreigner's outcome changes, and only to a less disclosing one.
--
-- Source of every body below: the CURRENT live definition on disk -- the LAST migration
-- that defines each function (20260730740000_create_procurement_vendor_performance.sql, 20260730780000_create_procurement_dashboard_reports.sql) -- copied
-- verbatim, with the single `if not found` line per function changed as described above.
-- Signatures are unchanged throughout, so grants are unaffected.
--
-- Three functions here (app.get_procurement_dashboard_saved_view,
-- app.update_procurement_dashboard_saved_view, app.delete_procurement_dashboard_saved_view)
-- already fold "row does not exist" and "not this actor's own saved view" into ONE generic
-- procurement_dashboard_saved_view_not_found; the membership term is added to that SAME
-- existing compound branch rather than a new one, so their already-correct owner-scoping is
-- preserved exactly and only the extra membership term is new.
--
-- This file: 12 functions, 12 at-risk raise sites.

create or replace function app.add_vendor_performance_corrective_action(
  p_issue_id uuid, p_description text, p_owner_label text, p_due_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_performance_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
  v_existing app.vendor_performance_corrective_actions;
  v_action app.vendor_performance_corrective_actions;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id;
  if not found or not app.has_active_tenant_membership(v_issue.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a non-empty description is required for a corrective action' using errcode = 'check_violation';
  end if;
  if v_issue.status = 'closed' then
    raise exception 'invalid_transition: vendor performance issue % is closed and cannot accept a new corrective action', p_issue_id using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_performance_corrective_actions where tenant_id = v_issue.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.issue_id is distinct from p_issue_id or v_existing.description is distinct from p_description then
        raise exception 'idempotency_key_conflict: key % was already used for a different corrective action', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_performance_corrective_actions (tenant_id, issue_id, description, owner_label, due_date, idempotency_key, created_by)
    values (v_issue.tenant_id, p_issue_id, p_description, p_owner_label, p_due_date, p_idempotency_key, p_actor_label)
    returning * into v_action;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02).
    when unique_violation then
      select * into v_action from app.vendor_performance_corrective_actions where tenant_id = v_issue.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_action.issue_id is distinct from p_issue_id or v_action.description is distinct from p_description then
        raise exception 'idempotency_key_conflict: key % was already used for a different corrective action', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_action;
  end;

  perform app.advance_vendor_performance_issue_in_progress(p_issue_id);

  perform app.capture_audit_event(
    v_issue.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_performance_corrective_action',
    'app.vendor_performance_corrective_actions', v_action.id, 'success', null, null, jsonb_build_object('issue_id', p_issue_id)
  );

  return v_action;
end;
$$;

create or replace function app.archive_vendor_kpi_definition(p_definition_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found or not app.has_active_tenant_membership(v_definition.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status not in ('draft', 'published') then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be archived', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_definitions set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_kpi_definition',
    'app.vendor_kpi_definitions', v_definition.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_definition;
end;
$$;

create or replace function app.decide_vendor_kpi_source_dispute(p_dispute_id uuid, p_expected_version integer, p_decision text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_source_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_dispute app.vendor_kpi_source_disputes;
begin
  select * into v_dispute from app.vendor_kpi_source_disputes where id = p_dispute_id for update;
  if not found or not app.has_active_tenant_membership(v_dispute.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_dispute.tenant_id, 'PRC', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_dispute.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_dispute.raised_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % raised dispute % and may not also decide it', p_actor_auth_user_id, p_dispute_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI source dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'pending' then
    raise exception 'invalid_transition: vendor KPI source dispute % is % and cannot be decided', p_dispute_id, v_dispute.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('upheld', 'rejected') then
    raise exception 'invalid_decision: % is not one of upheld/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_source_disputes
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = now(), decision_notes = p_decision_notes
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: vendor KPI source dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_dispute.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_kpi_source_dispute',
    'app.vendor_kpi_source_disputes', v_dispute.id, 'success', p_decision_notes, null, jsonb_build_object('status', v_dispute.status)
  );

  return v_dispute;
end;
$$;

create or replace function app.decide_vendor_lifecycle_recommendation(
  p_recommendation_id uuid, p_expected_version integer, p_decided_action text, p_decision_notes text, p_evidence_ref text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_lifecycle_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_recommendation app.vendor_lifecycle_recommendations;
  v_vendor app.vendor_profiles;
begin
  select * into v_recommendation from app.vendor_lifecycle_recommendations where id = p_recommendation_id for update;
  if not found or not app.has_active_tenant_membership(v_recommendation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_lifecycle_recommendation_not_found: %', p_recommendation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_recommendation.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_recommendation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Maker-checker, C-18: this is the highest-stakes decision this capability exposes (it can
  -- suspend/blacklist a vendor's eligibility), so self-approval is blocked exactly like the
  -- lower-stakes dispute/manual-adjustment decisions above, even though it is structurally
  -- possible for one actor to hold both PRC:Edit (evaluate) and PRC:Override (decide).
  if v_recommendation.recommended_by_auth_user_id is not null and v_recommendation.recommended_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % evaluated recommendation % and may not also decide it', p_actor_auth_user_id, p_recommendation_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_recommendation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor lifecycle recommendation % expected version % but found %', p_recommendation_id, p_expected_version, v_recommendation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_recommendation.status <> 'pending' then
    raise exception 'invalid_transition: vendor lifecycle recommendation % is % and cannot be decided', p_recommendation_id, v_recommendation.status
      using errcode = 'check_violation';
  end if;
  if p_decided_action not in ('none', 'watch', 'suspend', 'blacklist', 'reactivate') then
    raise exception 'invalid_action: % is not one of none/watch/suspend/blacklist/reactivate', p_decided_action using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;
  if p_decided_action = 'blacklist' and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: evidence is required to decide a blacklist lifecycle recommendation' using errcode = 'check_violation';
  end if;

  update app.vendor_lifecycle_recommendations
  set status = 'decided', decided_action = p_decided_action, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label,
    decided_at = now(), decision_notes = p_decision_notes, evidence_ref = p_evidence_ref
  where id = p_recommendation_id and record_version = p_expected_version
  returning * into v_recommendation;
  if not found then
    raise exception 'stale_version: vendor lifecycle recommendation % target row was concurrently modified (expected version %)', p_recommendation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- The one, and only, path that ever calls a real PRC-251 vendor-lifecycle RPC
  -- (design note 9). If the nested call raises (e.g. the vendor is no longer in the
  -- required state), the ENTIRE transaction -- including the status='decided' update
  -- just above -- rolls back, so a recommendation can never be left "decided but not
  -- executed" (no exception handler here catches it).
  if p_decided_action in ('suspend', 'blacklist', 'reactivate') then
    select * into v_vendor from app.vendor_profiles where master_record_id = v_recommendation.vendor_master_id;
    if p_decided_action = 'suspend' then
      perform app.suspend_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_decision_notes, p_actor_auth_user_id, p_actor_label);
    elsif p_decided_action = 'blacklist' then
      perform app.blacklist_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_decision_notes, p_evidence_ref, p_actor_auth_user_id, p_actor_label);
    elsif p_decided_action = 'reactivate' then
      perform app.reactivate_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_actor_auth_user_id, p_actor_label);
    end if;

    update app.vendor_lifecycle_recommendations set executed = true, executed_at = now() where id = p_recommendation_id;
  end if;

  perform app.capture_audit_event(
    v_recommendation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_lifecycle_recommendation',
    'app.vendor_lifecycle_recommendations', v_recommendation.id, 'success', p_decision_notes, null,
    jsonb_build_object('decided_action', p_decided_action, 'executed', p_decided_action in ('suspend', 'blacklist', 'reactivate'))
  );

  select * into v_recommendation from app.vendor_lifecycle_recommendations where id = p_recommendation_id;
  return v_recommendation;
end;
$$;

create or replace function app.delete_procurement_dashboard_saved_view(
  p_view_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
  v_deleted_count integer;
begin
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id for update;
  if not found or not app.has_active_tenant_membership(v_view.tenant_id, p_actor_auth_user_id) or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.procurement_dashboard_saved_views where id = p_view_id and record_version = p_expected_version;
  get diagnostics v_deleted_count = row_count;
  if v_deleted_count = 0 then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'delete_procurement_dashboard_saved_view',
    'app.procurement_dashboard_saved_views', p_view_id, 'success', null, to_jsonb(v_view), null
  );

  return true;
end;
$$;

create or replace function app.get_procurement_dashboard_saved_view(p_view_id uuid, p_actor_auth_user_id uuid)
returns app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
begin
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id;
  if not found or not app.has_active_tenant_membership(v_view.tenant_id, p_actor_auth_user_id) or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_view;
end;
$$;

create or replace function app.publish_vendor_kpi_definition(p_definition_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
  v_superseded app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found or not app.has_active_tenant_membership(v_definition.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status <> 'draft' then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be published', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  select * into v_superseded from app.vendor_kpi_definitions
  where tenant_id = v_definition.tenant_id and kpi_code = v_definition.kpi_code and status = 'published' and id <> v_definition.id
  for update;
  if found then
    update app.vendor_kpi_definitions set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = v_superseded.id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor KPI definition % was concurrently modified', v_superseded.id using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_kpi_definitions
  set status = 'published', supersedes_definition_id = v_superseded.id, updated_at = now(), record_version = record_version + 1
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_kpi_definition',
    'app.vendor_kpi_definitions', v_definition.id, 'success', null, null, jsonb_build_object('supersedes_definition_id', v_superseded.id)
  );

  return v_definition;
end;
$$;

create or replace function app.request_vendor_kpi_manual_adjustment(
  p_scorecard_id uuid, p_kpi_code text, p_adjusted_normalized_score numeric, p_reason text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scorecard app.vendor_kpi_scorecards;
  v_line app.vendor_kpi_scorecard_lines;
  v_existing app.vendor_kpi_manual_adjustments;
  v_adjustment app.vendor_kpi_manual_adjustments;
begin
  select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id;
  if not found or not app.has_active_tenant_membership(v_scorecard.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_scorecard_not_found: %', p_scorecard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_scorecard.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_scorecard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a manual KPI adjustment' using errcode = 'check_violation';
  end if;
  if p_adjusted_normalized_score is null or p_adjusted_normalized_score < 0 or p_adjusted_normalized_score > 100 then
    raise exception 'invalid_score: adjusted_normalized_score must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if v_scorecard.status <> 'published' then
    raise exception 'invalid_transition: vendor KPI scorecard % is % and cannot accept a manual adjustment', p_scorecard_id, v_scorecard.status
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.vendor_kpi_scorecard_lines where scorecard_id = p_scorecard_id and kpi_code = p_kpi_code;
  if not found then
    raise exception 'vendor_kpi_scorecard_line_not_found: scorecard % has no line for kpi_code %', p_scorecard_id, p_kpi_code using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_kpi_manual_adjustments where tenant_id = v_scorecard.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.scorecard_line_id is distinct from v_line.id or v_existing.adjusted_normalized_score is distinct from p_adjusted_normalized_score then
        raise exception 'idempotency_key_conflict: key % was already used for a different manual KPI adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_kpi_manual_adjustments (
      tenant_id, scorecard_id, scorecard_line_id, kpi_code, original_normalized_score, adjusted_normalized_score,
      reason, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      v_scorecard.tenant_id, p_scorecard_id, v_line.id, p_kpi_code, v_line.normalized_score, p_adjusted_normalized_score,
      p_reason, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_adjustment;
  exception
    -- Nested to scope ONLY this INSERT (taxonomy C-02, same fix shape as app.create_
    -- vendor_kpi_definition_draft above) -- the pre-check's own idempotency_key_conflict
    -- raise above shares this errcode but lives OUTSIDE this block, so it is never
    -- caught here. A genuine pending-adjustment race (two concurrent requests against
    -- the SAME line, vendor_kpi_manual_adjustments_pending_unique) is what this handler
    -- actually exists for.
    when unique_violation then
      raise exception 'adjustment_already_pending: scorecard line % already has a pending manual adjustment', v_line.id using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_scorecard.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_kpi_manual_adjustment',
    'app.vendor_kpi_manual_adjustments', v_adjustment.id, 'success', p_reason,
    jsonb_build_object('normalized_score', v_line.normalized_score), jsonb_build_object('requested_normalized_score', p_adjusted_normalized_score)
  );

  return v_adjustment;
end;
$$;

create or replace function app.update_procurement_dashboard_saved_view(
  p_view_id uuid,
  p_expected_version integer,
  p_name text,
  p_description text,
  p_filters jsonb,
  p_sort jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_updated app.procurement_dashboard_saved_views;
begin
  -- No p_tenant_id parameter -- the row lookup is structurally required before the
  -- permission check can even run (PRC-264's own established, accepted exception to
  -- C-05 for by-id functions with no tenant parameter). "Not found" and "not this
  -- actor's own view" fold into the identical error, never disclosing which.
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id for update;
  if not found or not app.has_active_tenant_membership(v_view.tenant_id, p_actor_auth_user_id) or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;

  -- C-03: the versioned update is immediately followed by an explicit stale-version guard.
  update app.procurement_dashboard_saved_views
  set name = p_name, description = p_description, filters = v_filters, sort = v_sort
  where id = p_view_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_procurement_dashboard_saved_view',
    'app.procurement_dashboard_saved_views', v_view.id, 'success', null, to_jsonb(v_view), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create or replace function app.update_vendor_kpi_definition_draft(
  p_definition_id uuid, p_expected_version integer, p_name text, p_description text,
  p_measurement_window_days integer, p_min_sample_size integer,
  p_target_value numeric, p_target_operator text, p_weight numeric, p_unit text,
  p_band_thresholds jsonb, p_exclusion_rules jsonb, p_rounding_scale integer,
  p_is_computable boolean, p_source_note text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found or not app.has_active_tenant_membership(v_definition.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status <> 'draft' then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be edited', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_definitions
  set name = p_name, description = p_description, measurement_window_days = p_measurement_window_days,
      min_sample_size = coalesce(p_min_sample_size, 1), target_value = p_target_value, target_operator = p_target_operator,
      weight = p_weight, unit = p_unit, band_thresholds = coalesce(p_band_thresholds, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb),
      exclusion_rules = coalesce(p_exclusion_rules, '{}'::jsonb), rounding_scale = coalesce(p_rounding_scale, 2),
      is_computable = coalesce(p_is_computable, true), source_note = p_source_note
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_kpi_definition_draft',
    'app.vendor_kpi_definitions', v_definition.id, 'success', null, null, '{}'::jsonb
  );

  return v_definition;
end;
$$;

create or replace function app.update_vendor_performance_corrective_action_status(p_action_id uuid, p_expected_version integer, p_status text, p_completion_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_performance_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_action app.vendor_performance_corrective_actions;
begin
  select * into v_action from app.vendor_performance_corrective_actions where id = p_action_id for update;
  if not found or not app.has_active_tenant_membership(v_action.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_performance_corrective_action_not_found: %', p_action_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_action.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_action.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_action.record_version <> p_expected_version then
    raise exception 'stale_version: vendor performance corrective action % expected version % but found %', p_action_id, p_expected_version, v_action.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('open', 'in_progress', 'completed', 'cancelled') then
    raise exception 'invalid_status: % is not one of open/in_progress/completed/cancelled', p_status using errcode = 'check_violation';
  end if;
  if v_action.status in ('completed', 'cancelled') then
    raise exception 'invalid_transition: vendor performance corrective action % is already %', p_action_id, v_action.status using errcode = 'check_violation';
  end if;
  if p_status = 'completed' and (p_completion_note is null or length(trim(p_completion_note)) = 0) then
    raise exception 'completion_note_required: a non-empty completion_note is required to complete a corrective action' using errcode = 'check_violation';
  end if;

  update app.vendor_performance_corrective_actions
  set status = p_status, completion_note = coalesce(p_completion_note, completion_note),
    completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_action_id and record_version = p_expected_version
  returning * into v_action;
  if not found then
    raise exception 'stale_version: vendor performance corrective action % target row was concurrently modified (expected version %)', p_action_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_action.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_performance_corrective_action_status',
    'app.vendor_performance_corrective_actions', v_action.id, 'success', p_completion_note, null, jsonb_build_object('status', v_action.status)
  );

  return v_action;
end;
$$;

create or replace function app.update_vendor_performance_issue_status(p_issue_id uuid, p_expected_version integer, p_status text, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_performance_issues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id for update;
  if not found or not app.has_active_tenant_membership(v_issue.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_issue.record_version <> p_expected_version then
    raise exception 'stale_version: vendor performance issue % expected version % but found %', p_issue_id, p_expected_version, v_issue.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('open', 'in_progress', 'resolved', 'closed') then
    raise exception 'invalid_status: % is not one of open/in_progress/resolved/closed', p_status using errcode = 'check_violation';
  end if;
  if v_issue.status in ('resolved', 'closed') and p_status not in ('resolved', 'closed') then
    raise exception 'invalid_transition: vendor performance issue % is already % and cannot be reopened via this path', p_issue_id, v_issue.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_performance_issues
  set status = p_status, resolution_note = coalesce(p_resolution_note, resolution_note),
    resolved_by_auth_user_id = case when p_status in ('resolved', 'closed') then p_actor_auth_user_id else resolved_by_auth_user_id end,
    resolved_by = case when p_status in ('resolved', 'closed') then p_actor_label else resolved_by end,
    resolved_at = case when p_status in ('resolved', 'closed') then coalesce(v_issue.resolved_at, now()) else resolved_at end
  where id = p_issue_id and record_version = p_expected_version
  returning * into v_issue;
  if not found then
    raise exception 'stale_version: vendor performance issue % target row was concurrently modified (expected version %)', p_issue_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_issue.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_performance_issue_status',
    'app.vendor_performance_issues', v_issue.id, 'success', p_resolution_note, null, jsonb_build_object('status', v_issue.status)
  );

  return v_issue;
end;
$$;
