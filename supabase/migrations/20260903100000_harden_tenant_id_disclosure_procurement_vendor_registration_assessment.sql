-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Third fix pass, Procurement lane (vendor registration + vendor assessment).
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
-- that defines each function (20260730580000_create_procurement_vendor_registration.sql, 20260730590000_create_procurement_vendor_assessment.sql) -- copied
-- verbatim, with the single `if not found` line per function changed as described above.
-- Signatures are unchanged throughout, so grants are unaffected.
--
-- This file: 30 functions, 33 at-risk raise sites.

create or replace function app.adjust_vendor_assessment_score(
  p_assessment_id uuid, p_expected_version integer, p_adjusted_score numeric, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_before numeric;
  v_before_band text;
  v_new_band text;
  v_pass numeric;
  v_conditional numeric;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to manually adjust a vendor assessment score' using errcode = 'check_violation';
  end if;
  if p_adjusted_score is null or p_adjusted_score < 0 or p_adjusted_score > 100 then
    raise exception 'invalid_adjusted_score: adjusted_score must be between 0 and 100' using errcode = 'check_violation';
  end if;

  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor assessment % is % -- a score may only be manually adjusted while submitted or under_review', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  -- "before" is the prior EFFECTIVE score -- a second override in the same
  -- assessment correctly records the prior adjustment as its own before value
  -- (design note 5), not the original machine-calculated score a first override
  -- may have already superseded.
  v_before := coalesce(v_assessment.adjusted_score, v_assessment.calculated_score);
  v_before_band := v_assessment.score_band;

  -- score_band is RECOMPUTED against the adjusted score (adversarial review,
  -- reproduced: previously score_band stayed frozen at whatever the machine
  -- calculation last produced, so an approved assessment could persist
  -- adjusted_score=55/score_band='pass' -- a materially misleading pairing on the
  -- exact source-of-truth row app.get_vendor_current_assessment_status exposes to
  -- downstream eligibility composition, Sec.4/21/33's own "explainable" requirement).
  select pass_threshold, conditional_threshold into v_pass, v_conditional
  from app.vendor_assessment_templates where id = v_assessment.template_version_id;
  v_new_band := case
    when p_adjusted_score >= v_pass then 'pass'
    when p_adjusted_score >= v_conditional then 'conditional'
    else 'fail'
  end;

  update app.vendor_assessments
  set adjusted_score = p_adjusted_score, score_band = v_new_band, adjustment_reason = p_reason, adjusted_by = p_actor_label, adjusted_by_auth_user_id = p_actor_auth_user_id,
      adjusted_at = now(), record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'adjust_vendor_assessment_score',
    'app.vendor_assessments', v_assessment.id, 'success', p_reason,
    jsonb_build_object('score', v_before, 'score_band', v_before_band), jsonb_build_object('score', p_adjusted_score, 'score_band', v_new_band)
  );

  return v_assessment;
end;
$$;

create or replace function app.archive_vendor_assessment_template(p_template_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a vendor assessment template' using errcode = 'check_violation';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template % expected version % but found %', p_template_version_id, p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.status <> 'published' then
    raise exception 'invalid_transition: vendor assessment template % is % and cannot be archived', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_templates
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_template_version_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: vendor assessment template % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_assessment_template',
    'app.vendor_assessment_templates', v_template.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_template;
end;
$$;

create or replace function app.assert_vendor_assessment_editable(p_assessment_id uuid, p_actor_auth_user_id uuid, out v_assessment app.vendor_assessments)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: same TOCTOU-closing discipline -- serializes answer-recording
  -- against app.submit_vendor_assessment_for_review's own terminal UPDATE on the
  -- same row (an answer must never be recorded into an assessment that just left
  -- draft/in_progress a moment earlier).
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_actor_auth_user_id <> v_assessment.assessor_auth_user_id then
    raise exception 'not_assigned_assessor: identity % is not the assigned assessor for vendor assessment %', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('draft', 'in_progress') then
    raise exception 'vendor_assessment_not_editable: vendor assessment % is % -- answers may only be recorded while draft or in_progress', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.assert_vendor_assessment_template_editable(p_template_version_id uuid, p_actor_auth_user_id uuid, out v_template app.vendor_assessment_templates)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: closes the same TOCTOU race class PRC-251's adversarial review
  -- found in app.assert_vendor_profile_editable -- serializes every criteria-CRUD
  -- call against app.publish_vendor_assessment_template's own terminal UPDATE on the
  -- same row.
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id for update;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.status <> 'draft' then
    raise exception 'vendor_assessment_template_not_draft: template version % is % -- criteria may only be edited while draft', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.assert_vendor_profile_editable(p_master_record_id uuid, p_actor_auth_user_id uuid, out v_profile app.vendor_profiles)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: closes a real TOCTOU race found in adversarial review -- without a
  -- row lock here, a lifecycle transition (e.g. submit_vendor_profile_for_review,
  -- whose own UPDATE only takes the row lock at UPDATE time) could commit
  -- draft->submitted concurrently with a child-CRUD call that already read
  -- lifecycle_status='draft' a moment earlier, letting a contact/address/service/
  -- coverage row be added after the profile left draft. Every lifecycle RPC's
  -- terminal UPDATE acquires this same row's lock, so contending on it here fully
  -- serializes the two paths: whichever transaction locks first wins, and the loser
  -- re-reads the post-commit status, matching a single sequential run.
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'draft' then
    raise exception 'vendor_profile_not_draft: vendor profile % is % -- child records may only be edited while draft', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.begin_vendor_assessment_review(p_assessment_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Defense in depth (design note 4) -- the mandatory block point is
  -- app.decide_vendor_assessment_review, but refusing the assessor here too avoids
  -- a reviewer identity ever being set to the assessor in the first place.
  if p_actor_auth_user_id = v_assessment.assessor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % assessed vendor assessment % and may not also review it', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_assessment.reviewer_auth_user_id is not null and v_assessment.reviewer_auth_user_id <> p_actor_auth_user_id then
    raise exception 'review_already_assigned: vendor assessment % is already assigned to a different reviewer', p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status <> 'submitted' then
    raise exception 'invalid_transition: vendor assessment % is % and cannot begin review', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assessments
  set status = 'under_review', reviewer_auth_user_id = p_actor_auth_user_id, record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'begin_vendor_assessment_review',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, '{}'::jsonb
  );

  return v_assessment;
end;
$$;

create or replace function app.begin_vendor_profile_review(
  p_master_record_id uuid,
  p_expected_version integer,
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
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'submitted' then
    raise exception 'invalid_transition: vendor profile % is % and cannot begin review', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'under_review', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'submitted', 'under_review', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'begin_vendor_profile_review',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create or replace function app.calculate_vendor_assessment_score(p_assessment_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_score record;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status = 'closed' then
    raise exception 'vendor_assessment_closed: cannot recalculate a closed vendor assessment %', p_assessment_id using errcode = 'check_violation';
  end if;

  select * into v_score from app._compute_vendor_assessment_score(v_assessment.template_version_id, p_assessment_id);

  update app.vendor_assessments
  set calculated_score = v_score.out_total, score_band = v_score.out_band, record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_vendor_assessment_score',
    'app.vendor_assessments', v_assessment.id, 'success', null, null,
    jsonb_build_object('calculated_score', v_score.out_total, 'score_band', v_score.out_band, 'answered_count', v_score.out_answered_count, 'criterion_count', v_score.out_criterion_count)
  );

  return v_assessment;
end;
$$;

create or replace function app.close_vendor_assessment(p_assessment_id uuid, p_expected_version integer, p_override_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_open_count integer;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status not in ('approved', 'rejected') then
    raise exception 'invalid_transition: vendor assessment % is % and cannot be closed', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_open_count from app.vendor_assessment_corrective_actions where assessment_id = p_assessment_id and status in ('open', 'overdue');

  if v_open_count > 0 then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'open_corrective_actions_block_close: % open corrective action(s) remain on vendor assessment % -- supply an override reason to close anyway', v_open_count, p_assessment_id
        using errcode = 'check_violation';
    end if;
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Override');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.vendor_assessments
  set status = 'closed', record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_vendor_assessment',
    'app.vendor_assessments', v_assessment.id, 'success', p_override_reason, null, jsonb_build_object('open_corrective_action_count', v_open_count)
  );

  return v_assessment;
end;
$$;

create or replace function app.create_vendor_assessment_corrective_action(p_finding_id uuid, p_description text, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_finding app.vendor_assessment_findings;
  v_assessment app.vendor_assessments;
  v_action app.vendor_assessment_corrective_actions;
begin
  select * into v_finding from app.vendor_assessment_findings where id = p_finding_id;
  if not found or not app.has_active_tenant_membership(v_finding.tenant_id, p_actor_auth_user_id) then
    raise exception 'finding_not_found: %', p_finding_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_finding.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_finding.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_finding.status <> 'open' then
    raise exception 'finding_not_open: vendor assessment finding % is % -- a corrective action may only be raised against an open finding', p_finding_id, v_finding.status
      using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'invalid_corrective_action: description must not be empty' using errcode = 'check_violation';
  end if;

  -- `for update` on the parent assessment: closes a real, reproduced defect
  -- (adversarial review, both deterministic and true-concurrent-race forms) where a
  -- brand-new OPEN corrective action could be attached to an assessment that was
  -- already closed (or was being closed concurrently), silently defeating
  -- app.close_vendor_assessment's own PRC:Override + mandatory-reason governance
  -- gate for open-corrective-actions-at-close-time. Locking the SAME assessment row
  -- app.close_vendor_assessment itself locks serializes the two RPCs against each
  -- other; both a plain sequential closed-assessment attempt and a genuine
  -- concurrent race now correctly reject.
  select * into v_assessment from app.vendor_assessments where id = v_finding.assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', v_finding.assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.status = 'closed' then
    raise exception 'vendor_assessment_closed: vendor assessment % is closed -- no new corrective action may be added', v_finding.assessment_id
      using errcode = 'check_violation';
  end if;

  insert into app.vendor_assessment_corrective_actions (tenant_id, finding_id, assessment_id, description, due_date, created_by)
  values (v_finding.tenant_id, p_finding_id, v_finding.assessment_id, p_description, p_due_date, p_actor_label)
  returning * into v_action;

  perform app.capture_audit_event(
    v_finding.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_assessment_corrective_action',
    'app.vendor_assessment_corrective_actions', v_action.id, 'success', null, null, to_jsonb(v_action)
  );

  return v_action;
end;
$$;

create or replace function app.decide_vendor_assessment_finding(p_finding_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_finding app.vendor_assessment_findings;
  v_assessment app.vendor_assessments;
begin
  if p_decision not in ('resolved', 'waived') then
    raise exception 'invalid_decision: % is not resolved or waived', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a vendor assessment finding' using errcode = 'check_violation';
  end if;

  select * into v_finding from app.vendor_assessment_findings where id = p_finding_id;
  if not found or not app.has_active_tenant_membership(v_finding.tenant_id, p_actor_auth_user_id) then
    raise exception 'finding_not_found: %', p_finding_id using errcode = 'no_data_found';
  end if;
  if v_finding.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment finding % expected version % but found %', p_finding_id, p_expected_version, v_finding.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_assessment from app.vendor_assessments where id = v_finding.assessment_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_finding.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_finding.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_finding.status <> 'open' then
    raise exception 'invalid_transition: vendor assessment finding % is already %', p_finding_id, v_finding.status using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_findings
  set status = p_decision, resolution_reason = p_reason, resolved_by = p_actor_label, resolved_at = now()
  where id = p_finding_id and record_version = p_expected_version
  returning * into v_finding;
  if not found then
    raise exception 'stale_version: vendor assessment finding % target row was concurrently modified (expected version %)', p_finding_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_finding.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_assessment_finding',
    'app.vendor_assessment_findings', v_finding.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_finding;
end;
$$;

create or replace function app.decide_vendor_assessment_review(
  p_assessment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_template app.vendor_assessment_templates;
  v_new_status text;
  v_expiry date;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a vendor assessment' using errcode = 'check_violation';
  end if;

  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- MANDATORY maker-checker block (design note 4, prompt Sec.23) -- checked before
  -- the authority evaluation so an assessor who also happens to hold PRC:Approve/
  -- Reject for their own tenant is refused on identity grounds, not merely on
  -- permission grounds.
  if p_actor_auth_user_id = v_assessment.assessor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % assessed vendor assessment % and may not also decide its review', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Reviewer exclusivity (adversarial review, reproduced): once a reviewer is
  -- assigned (app.begin_vendor_assessment_review, or a p_reviewer_auth_user_id
  -- pre-assignment at start/submit), only THAT reviewer may decide -- otherwise the
  -- terminal `coalesce(reviewer_auth_user_id, p_actor_auth_user_id)` below is a
  -- no-op once reviewer_auth_user_id is already non-null, so a DIFFERENT
  -- Approve/Reject-holding actor could decide while the row silently kept
  -- misattributing the decision to the originally-assigned reviewer. Mirrors
  -- app.begin_vendor_assessment_review's own review_already_assigned guard.
  if v_assessment.reviewer_auth_user_id is not null and v_assessment.reviewer_auth_user_id <> p_actor_auth_user_id then
    raise exception 'review_already_assigned: vendor assessment % is already assigned to a different reviewer', p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', case p_decision when 'approve' then 'Approve' else 'Reject' end);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, initcap(p_decision), v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor assessment % is % and cannot be decided', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;
  v_expiry := null;
  if p_decision = 'approve' then
    select * into v_template from app.vendor_assessment_templates where id = v_assessment.template_version_id;
    v_expiry := (now())::date + v_template.validity_period_days;
  end if;

  update app.vendor_assessments
  set status = v_new_status, decision_reason = p_reason, decided_at = now(), expiry_date = v_expiry,
      reviewer_auth_user_id = coalesce(reviewer_auth_user_id, p_actor_auth_user_id), record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_assessment_review',
    'app.vendor_assessments', v_assessment.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'status', v_new_status, 'expiry_date', v_expiry)
  );

  return v_assessment;
end;
$$;

create or replace function app.decide_vendor_duplicate_candidate(
  p_candidate_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.vendor_duplicate_candidates;
begin
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate' using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.vendor_duplicate_candidates where id = p_candidate_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate % expected version % but found %', p_candidate_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_candidate.decision <> 'pending' then
    raise exception 'invalid_transition: duplicate candidate % is already %', p_candidate_id, v_candidate.decision using errcode = 'check_violation';
  end if;

  update app.vendor_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: duplicate candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_duplicate_candidate',
    'app.vendor_duplicate_candidates', v_candidate.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_candidate;
end;
$$;

create or replace function app.flag_vendor_duplicate_candidate(
  p_source_master_record_id uuid, p_candidate_master_record_id uuid, p_similarity_basis text, p_similarity_score numeric,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_source app.vendor_profiles;
  v_candidate app.vendor_duplicate_candidates;
begin
  select * into v_source from app.vendor_profiles where master_record_id = p_source_master_record_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_source_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.vendor_profiles where master_record_id = p_candidate_master_record_id and tenant_id = v_source.tenant_id) then
    raise exception 'vendor_profile_not_found: candidate %', p_candidate_master_record_id using errcode = 'no_data_found';
  end if;
  if p_source_master_record_id = p_candidate_master_record_id then
    raise exception 'invalid_candidate: a vendor profile cannot be flagged as its own duplicate' using errcode = 'check_violation';
  end if;
  if p_similarity_basis is null or length(trim(p_similarity_basis)) = 0 then
    raise exception 'invalid_candidate: similarity_basis must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_duplicate_candidates (tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, created_by)
  values (v_source.tenant_id, p_source_master_record_id, p_candidate_master_record_id, p_similarity_basis, p_similarity_score, p_actor_label)
  returning * into v_candidate;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'flag_vendor_duplicate_candidate',
    'app.vendor_duplicate_candidates', v_candidate.id, 'success', null, null, to_jsonb(v_candidate)
  );

  return v_candidate;
end;
$$;

create or replace function app.get_vendor_assessment(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, template_version_id uuid, assessment_type text, status text,
  assessor_auth_user_id uuid, reviewer_auth_user_id uuid, calculated_score numeric, score_band text, adjusted_score numeric,
  adjustment_reason text, adjusted_by text, adjusted_at timestamptz, submitted_at timestamptz, decided_at timestamptz,
  decision_reason text, expiry_date date, reassessment_due boolean, predecessor_assessment_id uuid, record_version integer,
  created_by text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments a where a.id = p_assessment_id;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_assessment.id, v_assessment.tenant_id, v_assessment.vendor_master_record_id, v_assessment.template_version_id, v_assessment.assessment_type, v_assessment.status,
    v_assessment.assessor_auth_user_id, v_assessment.reviewer_auth_user_id, v_assessment.calculated_score, v_assessment.score_band, v_assessment.adjusted_score,
    v_assessment.adjustment_reason, v_assessment.adjusted_by, v_assessment.adjusted_at, v_assessment.submitted_at, v_assessment.decided_at,
    v_assessment.decision_reason, v_assessment.expiry_date, (v_assessment.expiry_date is not null and v_assessment.expiry_date < current_date), v_assessment.predecessor_assessment_id,
    v_assessment.record_version, v_assessment.created_by, v_assessment.created_at, v_assessment.updated_at;
end;
$$;

create or replace function app.get_vendor_assessment_template(p_template_version_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_category text, assessment_type text, name text, description text, validity_period_days integer,
  pass_threshold numeric, conditional_threshold numeric, weight_total_required numeric, status text, supersedes_version_id uuid,
  effective_from timestamptz, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz, criterion_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  select * into v_template from app.vendor_assessment_templates t where t.id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_template.id, v_template.tenant_id, v_template.vendor_category, v_template.assessment_type, v_template.name, v_template.description,
    v_template.validity_period_days, v_template.pass_threshold, v_template.conditional_threshold, v_template.weight_total_required, v_template.status,
    v_template.supersedes_version_id, v_template.effective_from, v_template.record_version, v_template.created_by, v_template.created_at, v_template.updated_at,
    (select count(*)::integer from app.vendor_assessment_template_criteria c where c.template_version_id = p_template_version_id and c.status = 'active');
end;
$$;

create or replace function app.get_vendor_current_assessment_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  assessment_type text, assessment_id uuid, status text, calculated_score numeric, adjusted_score numeric, score_band text,
  decided_at timestamptz, expiry_date date, reassessment_due boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select distinct on (a.assessment_type)
    a.assessment_type, a.id, a.status, a.calculated_score, a.adjusted_score, a.score_band, a.decided_at, a.expiry_date,
    (a.expiry_date is not null and a.expiry_date < current_date)
  from app.vendor_assessments a
  where a.vendor_master_record_id = p_vendor_master_record_id and a.status in ('approved', 'rejected')
  order by a.assessment_type, (a.status = 'approved') desc, a.created_at desc;
end;
$$;

create or replace function app.get_vendor_lifecycle_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_profile_lifecycle_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_profile_lifecycle_events where master_record_id = p_master_record_id order by occurred_at;
end;
$$;

create or replace function app.get_vendor_profile(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  master_record_id uuid, tenant_id uuid, vendor_code text, legal_name text, trade_name text,
  legal_entity_type text, business_registration_number text, vendor_category text, payment_term_days integer,
  intake_source text, lifecycle_status text, revision_reason text, suspend_reason text, blacklist_reason text,
  blacklist_evidence_ref text, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz,
  contact_count integer, address_count integer, service_count integer, coverage_count integer, pending_duplicate_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles vp where vp.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v_profile.master_record_id, v_profile.tenant_id, m.code, v_profile.legal_name, v_profile.trade_name,
    v_profile.legal_entity_type, v_profile.business_registration_number, v_profile.vendor_category, v_profile.payment_term_days,
    v_profile.intake_source, v_profile.lifecycle_status, v_profile.revision_reason, v_profile.suspend_reason, v_profile.blacklist_reason,
    v_profile.blacklist_evidence_ref, v_profile.record_version, v_profile.created_by, v_profile.created_at, v_profile.updated_at,
    (select count(*)::integer from app.vendor_contacts c where c.master_record_id = p_master_record_id and c.status = 'active'),
    (select count(*)::integer from app.vendor_addresses a where a.master_record_id = p_master_record_id and a.status = 'active'),
    (select count(*)::integer from app.vendor_services s where s.master_record_id = p_master_record_id and s.status = 'active'),
    (select count(*)::integer from app.vendor_coverage cv where cv.master_record_id = p_master_record_id and cv.status = 'active'),
    (select count(*)::integer from app.vendor_duplicate_candidates d where d.source_master_record_id = p_master_record_id and d.decision = 'pending')
  from app.master_records m
  where m.id = p_master_record_id;
end;
$$;

create or replace function app.list_vendor_addresses(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_addresses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_addresses where master_record_id = p_master_record_id and status = 'active' order by address_type, created_at;
end;
$$;

create or replace function app.list_vendor_contacts(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, master_record_id uuid, name text, title text, email text, phone text, is_primary boolean, record_version integer, created_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_masked boolean;
begin
  select * into v_profile from app.vendor_profiles vp where vp.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_masked := not app.has_prc_view_personal_data(v_profile.tenant_id, p_actor_auth_user_id);

  return query
  select c.id, c.master_record_id, c.name, c.title,
         case when v_masked then null else c.email end,
         case when v_masked then null else c.phone end,
         c.is_primary, c.record_version, c.created_at
  from app.vendor_contacts c
  where c.master_record_id = p_master_record_id and c.status = 'active'
  order by c.is_primary desc, c.created_at;
end;
$$;

create or replace function app.list_vendor_coverage(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_coverage
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_coverage where master_record_id = p_master_record_id and status = 'active' order by origin_lane;
end;
$$;

create or replace function app.list_vendor_duplicate_candidates(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_duplicate_candidates where source_master_record_id = p_master_record_id order by created_at desc;
end;
$$;

create or replace function app.list_vendor_services(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_services
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_services where master_record_id = p_master_record_id and status = 'active' order by service_type;
end;
$$;

create or replace function app.publish_vendor_assessment_template(
  p_template_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
  v_superseded app.vendor_assessment_templates;
  v_weight_sum numeric;
  v_criterion_count integer;
begin
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id for update;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template % expected version % but found %', p_template_version_id, p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'invalid_transition: vendor assessment template % is % and cannot be published', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;

  select count(*), coalesce(sum(weight), 0) into v_criterion_count, v_weight_sum
  from app.vendor_assessment_template_criteria where template_version_id = p_template_version_id and status = 'active';
  if v_criterion_count = 0 then
    raise exception 'template_has_no_criteria: vendor assessment template % defines no active criteria' , p_template_version_id
      using errcode = 'check_violation';
  end if;
  if abs(v_weight_sum - v_template.weight_total_required) > 0.01 then
    raise exception 'weight_sum_mismatch: vendor assessment template % criteria weights sum to % but must sum to %', p_template_version_id, v_weight_sum, v_template.weight_total_required
      using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    -- `for update`: closes a real, reproduced race (adversarial review) where a
    -- concurrent, independent app.archive_vendor_assessment_template call on the SAME
    -- superseded row could commit between this read and the terminal UPDATE below,
    -- which previously carried no record_version/status guard and no "not found"
    -- re-check at all -- silently re-archiving an already-independently-archived row
    -- with no audit trail of its own for that second archival.
    select * into v_superseded from app.vendor_assessment_templates where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_template_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_template.tenant_id or v_superseded.assessment_type <> v_template.assessment_type or coalesce(v_superseded.vendor_category, '') <> coalesce(v_template.vendor_category, '') then
      raise exception 'invalid_supersede: superseded template must share the same tenant/vendor_category/assessment_type' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded template % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.vendor_assessment_templates
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor assessment template % was concurrently modified (expected version %)', p_supersedes_version_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_assessment_templates
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_template_version_id and record_version = p_expected_version
    returning * into v_template;
  exception
    when unique_violation then
      raise exception 'active_template_exists: a published template already exists for tenant %, vendor_category %, assessment_type % -- supply p_supersedes_version_id to replace it', v_template.tenant_id, v_template.vendor_category, v_template.assessment_type
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: vendor assessment template % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_assessment_template',
    'app.vendor_assessment_templates', v_template.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id, 'weight_sum', v_weight_sum)
  );

  return v_template;
end;
$$;

create or replace function app.raise_vendor_assessment_finding(p_assessment_id uuid, p_severity text, p_description text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_finding app.vendor_assessment_findings;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('draft', 'in_progress', 'submitted', 'under_review') then
    raise exception 'vendor_assessment_not_active: vendor assessment % is % -- a finding may only be raised against an active assessment', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;
  if coalesce(p_severity, '') not in ('low', 'medium', 'high', 'critical') then
    raise exception 'invalid_severity: % is not a recognized severity', p_severity using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'invalid_finding: description must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_assessment_findings (tenant_id, assessment_id, severity, description, created_by)
  values (v_assessment.tenant_id, p_assessment_id, p_severity, p_description, p_actor_label)
  returning * into v_finding;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_assessment_finding',
    'app.vendor_assessment_findings', v_finding.id, 'success', null, null, to_jsonb(v_finding)
  );

  return v_finding;
end;
$$;

create or replace function app.start_vendor_assessment(
  p_vendor_master_record_id uuid, p_template_version_id uuid, p_reviewer_auth_user_id uuid, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_template app.vendor_assessment_templates;
  v_existing app.vendor_assessments;
  v_constraint_name text;
  v_assessment app.vendor_assessments;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vendor.lifecycle_status = 'blacklisted' then
    raise exception 'vendor_blacklisted: vendor % is blacklisted -- no new assessment cycle may be started', p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_reviewer_auth_user_id is not null and p_reviewer_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: assessor % may not pre-assign themselves as the reviewer', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id and tenant_id = v_vendor.tenant_id;
  if not found or v_template.status <> 'published' then
    raise exception 'template_not_published: vendor assessment template % is not a published template for tenant %', p_template_version_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_template.vendor_category is not null and v_template.vendor_category <> v_vendor.vendor_category then
    raise exception 'template_category_mismatch: template % applies to vendor_category % but vendor % is %', p_template_version_id, v_template.vendor_category, p_vendor_master_record_id, v_vendor.vendor_category
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assessments where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.template_version_id is distinct from p_template_version_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assessment (vendor %, template %)', p_idempotency_key, v_existing.vendor_master_record_id, v_existing.template_version_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- One open assessment per (vendor, assessment_type) is a structural guard
  -- (vendor_assessments_one_open_per_type_idx) -- a pre-check here gives a clean
  -- error for the ordinary sequential case; the nested exception below recovers
  -- correctly for a genuine concurrent race, distinguishing WHICH unique index
  -- fired via GET STACKED DIAGNOSTICS rather than guessing.
  if exists (
    select 1 from app.vendor_assessments
    where vendor_master_record_id = p_vendor_master_record_id and assessment_type = v_template.assessment_type
      and status in ('draft', 'in_progress', 'submitted', 'under_review')
  ) then
    raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', p_vendor_master_record_id, v_template.assessment_type
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assessments (
      tenant_id, vendor_master_record_id, template_version_id, assessment_type, assessor_auth_user_id, reviewer_auth_user_id,
      idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_template_version_id, v_template.assessment_type, p_actor_auth_user_id, p_reviewer_auth_user_id,
      p_idempotency_key, p_actor_label
    )
    returning * into v_assessment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_assessments_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_assessments where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.template_version_id is distinct from p_template_version_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assessment (vendor %, template %)', p_idempotency_key, v_existing.vendor_master_record_id, v_existing.template_version_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_assessments_one_open_per_type_idx' then
        raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', p_vendor_master_record_id, v_template.assessment_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_vendor_assessment',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, to_jsonb(v_assessment)
  );

  return v_assessment;
end;
$$;

create or replace function app.start_vendor_assessment_reassessment(
  p_predecessor_assessment_id uuid, p_template_version_id uuid, p_reviewer_auth_user_id uuid, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_predecessor app.vendor_assessments;
  v_template app.vendor_assessment_templates;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_assessments;
  v_constraint_name text;
  v_assessment app.vendor_assessments;
begin
  select * into v_predecessor from app.vendor_assessments where id = p_predecessor_assessment_id;
  if not found or not app.has_active_tenant_membership(v_predecessor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_predecessor_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_predecessor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_predecessor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- 'closed' is a legitimate predecessor too -- it is 'approved' plus a completed
  -- corrective-action reconciliation (app.close_vendor_assessment), never a
  -- regression away from approved; a rejected/draft/in-flight assessment is not.
  if v_predecessor.status not in ('approved', 'closed') then
    raise exception 'predecessor_not_approved: vendor assessment % is % -- only an approved or closed assessment may be reassessed', p_predecessor_assessment_id, v_predecessor.status
      using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id is not null and p_reviewer_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: assessor % may not pre-assign themselves as the reviewer', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = v_predecessor.vendor_master_record_id;
  if v_vendor.lifecycle_status = 'blacklisted' then
    raise exception 'vendor_blacklisted: vendor % is blacklisted -- no new assessment cycle may be started', v_predecessor.vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id and tenant_id = v_predecessor.tenant_id;
  if not found or v_template.status <> 'published' then
    raise exception 'template_not_published: vendor assessment template % is not a published template for tenant %', p_template_version_id, v_predecessor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_template.assessment_type <> v_predecessor.assessment_type then
    raise exception 'reassessment_type_mismatch: template % is type % but predecessor assessment % is type %', p_template_version_id, v_template.assessment_type, p_predecessor_assessment_id, v_predecessor.assessment_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assessments where tenant_id = v_predecessor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.predecessor_assessment_id is distinct from p_predecessor_assessment_id or v_existing.template_version_id is distinct from p_template_version_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reassessment (predecessor %, template %)', p_idempotency_key, v_existing.predecessor_assessment_id, v_existing.template_version_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if exists (
    select 1 from app.vendor_assessments
    where vendor_master_record_id = v_predecessor.vendor_master_record_id and assessment_type = v_template.assessment_type
      and status in ('draft', 'in_progress', 'submitted', 'under_review')
  ) then
    raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', v_predecessor.vendor_master_record_id, v_template.assessment_type
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assessments (
      tenant_id, vendor_master_record_id, template_version_id, assessment_type, assessor_auth_user_id, reviewer_auth_user_id,
      predecessor_assessment_id, idempotency_key, created_by
    ) values (
      v_predecessor.tenant_id, v_predecessor.vendor_master_record_id, p_template_version_id, v_template.assessment_type, p_actor_auth_user_id, p_reviewer_auth_user_id,
      p_predecessor_assessment_id, p_idempotency_key, p_actor_label
    )
    returning * into v_assessment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_assessments_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_assessments where tenant_id = v_predecessor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.predecessor_assessment_id is distinct from p_predecessor_assessment_id or v_existing.template_version_id is distinct from p_template_version_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reassessment (predecessor %, template %)', p_idempotency_key, v_existing.predecessor_assessment_id, v_existing.template_version_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_assessments_one_open_per_type_idx' then
        raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', v_predecessor.vendor_master_record_id, v_template.assessment_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_predecessor.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_vendor_assessment_reassessment',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, jsonb_build_object('predecessor_assessment_id', p_predecessor_assessment_id)
  );

  return v_assessment;
end;
$$;

create or replace function app.submit_vendor_profile_for_review(
  p_master_record_id uuid,
  p_expected_version integer,
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
  v_contact_count integer;
  v_legal_address_count integer;
  v_service_count integer;
  v_pending_dupes integer;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'draft' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be submitted for review', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_contact_count from app.vendor_contacts where master_record_id = p_master_record_id and status = 'active';
  if v_contact_count = 0 then
    raise exception 'missing_required_contact: vendor profile % has no active contact', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_legal_address_count from app.vendor_addresses where master_record_id = p_master_record_id and status = 'active' and address_type = 'legal';
  if v_legal_address_count = 0 then
    raise exception 'missing_required_address: vendor profile % has no active legal address', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_service_count from app.vendor_services where master_record_id = p_master_record_id and status = 'active';
  if v_service_count = 0 then
    raise exception 'missing_required_service: vendor profile % has no active service', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_dupes from app.vendor_duplicate_candidates where source_master_record_id = p_master_record_id and decision = 'pending';
  if v_pending_dupes > 0 then
    raise exception 'unresolved_duplicate_candidates: vendor profile % has % unresolved duplicate candidate(s)', p_master_record_id, v_pending_dupes
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'submitted', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'draft', 'submitted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_profile_for_review',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, jsonb_build_object('lifecycle_status', v_profile.lifecycle_status)
  );

  return v_profile;
end;
$$;

create or replace function app.update_vendor_assessment_corrective_action_status(
  p_corrective_action_id uuid, p_expected_version integer, p_new_status text, p_resolution_notes text, p_resolved_evidence_file_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_action app.vendor_assessment_corrective_actions;
  v_resolved_by text;
  v_resolved_at timestamptz;
  v_notes text;
  v_evidence uuid;
  v_file app.files;
begin
  if p_new_status not in ('open', 'completed', 'overdue', 'waived') then
    raise exception 'invalid_status: % is not a recognized corrective action status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_action from app.vendor_assessment_corrective_actions where id = p_corrective_action_id;
  if not found or not app.has_active_tenant_membership(v_action.tenant_id, p_actor_auth_user_id) then
    raise exception 'corrective_action_not_found: %', p_corrective_action_id using errcode = 'no_data_found';
  end if;
  if v_action.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment corrective action % expected version % but found %', p_corrective_action_id, p_expected_version, v_action.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_action.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_action.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if (v_action.status = 'open' and p_new_status not in ('completed', 'overdue', 'waived')) or
     (v_action.status = 'overdue' and p_new_status not in ('completed', 'waived')) or
     (v_action.status in ('completed', 'waived')) then
    raise exception 'invalid_transition: vendor assessment corrective action % is % and cannot move to %', p_corrective_action_id, v_action.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status in ('completed', 'waived') then
    if p_resolution_notes is null or length(trim(p_resolution_notes)) = 0 then
      raise exception 'resolution_notes_required: non-empty resolution_notes are required to mark a corrective action % ', p_new_status using errcode = 'check_violation';
    end if;
    v_resolved_by := p_actor_label;
    v_resolved_at := now();
    v_notes := p_resolution_notes;
    v_evidence := p_resolved_evidence_file_id;

    -- Evidence re-validation (adversarial review, reproduced): same shape as
    -- app.record_vendor_assessment_answer's own fix above -- re-fetch and reject on
    -- tenant mismatch, wrong record_type/record_id, or a non-clean malware scan.
    -- record_id is the ASSESSMENT's own id (v_action.assessment_id), matching how the
    -- server action actually uploads corrective-action evidence (record_type=
    -- 'vendor_assessment', record_id=assessmentId, the same evidence trail an
    -- answer's own evidence_file_id is uploaded against).
    if v_evidence is not null then
      select * into v_file from app.files where id = v_evidence;
      if not found then
        raise exception 'evidence_file_not_found: %', v_evidence using errcode = 'no_data_found';
      end if;
      if v_file.tenant_id <> v_action.tenant_id or v_file.record_type <> 'vendor_assessment' or v_file.record_id <> v_action.assessment_id then
        raise exception 'assessment_evidence_file_mismatch: file % does not belong to vendor assessment % in tenant %', v_evidence, v_action.assessment_id, v_action.tenant_id
          using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'assessment_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', v_evidence, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end if;
  else
    v_resolved_by := null;
    v_resolved_at := null;
    v_notes := null;
    v_evidence := null;
  end if;

  update app.vendor_assessment_corrective_actions
  set status = p_new_status, resolution_notes = v_notes, resolved_evidence_file_id = v_evidence, resolved_by = v_resolved_by, resolved_at = v_resolved_at
  where id = p_corrective_action_id and record_version = p_expected_version
  returning * into v_action;
  if not found then
    raise exception 'stale_version: vendor assessment corrective action % target row was concurrently modified (expected version %)', p_corrective_action_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_action.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_assessment_corrective_action_status',
    'app.vendor_assessment_corrective_actions', v_action.id, 'success', p_resolution_notes, null, jsonb_build_object('status', p_new_status)
  );

  return v_action;
end;
$$;
