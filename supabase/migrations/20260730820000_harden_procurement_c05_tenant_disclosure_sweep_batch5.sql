-- Prompt 269 (CG-S11-PRC-020, Procurement/Vendor Integrity, Security and Financial
-- Hardening) -- Fix 4, Fix 5, and Fix 6.
--
-- ===========================================================================
-- Fix 4: ISS-2026-054 (MEDIUM) -- C-05 tenant-id-disclosure oracle, 15 functions
-- ===========================================================================
--
-- The same defect this repository has already fixed twice before (ISS-2026-043 for
-- reads, ISS-2026-048 for writes, both closed by
-- `20260730670000_harden_procurement_batch_257_259_review_fixes.sql` /
-- `20260730690000_harden_procurement_purchase_order_batch_260_review_fixes.sql`):
-- each of the 15 functions below resolves the target row's real tenant_id into a local
-- variable, THEN calls app.evaluate_permission, so a denial raises 'insufficient_
-- authority: ... for tenant %' with the REAL tenant_id interpolated -- disclosed to a
-- caller who has not yet been shown to belong to that tenant at all. Fixed using the
-- exact already-established pattern (app.get_rfq's own CREATE OR REPLACE in
-- `20260730670000`, lines ~99-124, is the literal template): fold
-- `app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id)` into the SAME
-- not-found branch the row-miss case already raises, so a non-member gets the identical
-- error shape a nonexistent id would get, and only a real member ever reaches the real
-- evaluate_permission/authority check below it. No permission check is weakened -- the
-- authority check itself is unchanged, only its ordering relative to the
-- tenant-membership pre-check. Every function below is CREATE OR REPLACE against its
-- CURRENT, still-original live body (each verified by direct read against its owning,
-- already-applied migration file before writing this replacement -- none of the 15 had
-- been amended by any later migration).
--
-- ===========================================================================
-- Fix 5: ISS-2026-055 (LOW) -- record_version disclosed before the authority check
-- ===========================================================================
--
-- app.suspend_vendor_profile's own `stale_version` check (discloses the row's real
-- current record_version in its error text) ran strictly BEFORE app.evaluate_
-- permission. Its three lifecycle-transition siblings (reactivate_/archive_/
-- blacklist_vendor_profile) were each individually read and confirmed to share the
-- IDENTICAL ordering bug (a structural sweep, not a blind grep-and-copy) -- fixed the
-- same way in all four, in this same migration: fetch row (folded into the Fix 4
-- not-found branch) -> evaluate_permission/authority check -> THEN stale_version check.
--
-- CORRECTION (same checkpoint, security-regression spot-check of this file's own
-- original "checked and found NOT affected" claim -- superseded before ever being
-- committed): app.decide_vendor_compliance_waiver, below, was initially believed to NOT
-- share this defect because its own self_approval_not_allowed check runs before
-- stale_version on identity grounds. Live re-verification against the actual applied
-- function body found that claim FALSE -- stale_version ran BEFORE BOTH
-- self_approval_not_allowed and the PRC:Approve/PRC:Reject authority check, so a real
-- tenant member lacking both could still extract the row's genuine current
-- record_version via a deliberately stale p_expected_version, before ever being told
-- they lack authority to decide it. Fixed below, in this same function definition: both
-- self_approval_not_allowed and the authority check now run before
-- stale_version/invalid_transition (their own prior relative order to each other is
-- unchanged) -- same "authority before state-disclosure" discipline as the four
-- vendor_profiles functions. This is a disclosure-ordering fix only; the actual decision
-- was never bypassable (a correct expected_version + no authority was, and remains,
-- correctly denied).
--
-- No other function in this migration carries this defect (verified by reading each of
-- the 15 bodies individually; the other 10 pure-read functions have no
-- record_version/stale_version check to reorder at all, and no other write RPC in this
-- batch shares the vendor_profiles lifecycle-transition template).
--
-- ===========================================================================
-- Fix 6: ISS-2026-056 (MEDIUM) -- missing covering index on app.vendor_contracts
-- ===========================================================================
--
-- app.vendor_contracts carries indexes on (tenant_id, contract_number, version_no) x2,
-- (tenant_id, effective_end) partial, and (tenant_id, vendor_master_id, status) -- but
-- none on (tenant_id, created_at desc), unlike its three siblings in the same
-- capability family (purchase_orders_tenant_created_idx, rfqs_tenant_created_idx,
-- vendor_comparisons_tenant_created_idx). app.list_vendor_contracts's own internal
-- query is the identical `... where tenant_id = p_tenant_id ... order by created_at
-- desc limit ...` shape, but lacking the matching index the planner cannot do an
-- ordered Index Scan with early-LIMIT termination. Plain CREATE INDEX (no CONCURRENTLY
-- -- this repository does not use it anywhere, confirmed by repository-wide grep,
-- matching the exact naming convention of its three siblings.
-- ===========================================================================

-- ===========================================================================
-- Group 1 of 5: supabase/migrations/20260730580000_create_procurement_vendor_registration.sql
-- (Fix 4 + Fix 5 combined on all four -- the vendor_profiles lifecycle-transition family)
-- ===========================================================================

create or replace function app.suspend_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
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
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend a vendor profile' using errcode = 'check_violation';
  end if;

  -- Fix 4 (ISS-2026-054, C-05): a non-member gets the identical not-found error a
  -- genuinely missing row would produce, never the real tenant_id.
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  -- Fix 5 (ISS-2026-055): authority check now runs BEFORE the stale_version check
  -- below, so a caller who both lacks authority AND supplied a stale version never
  -- learns the row's real current record_version.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.lifecycle_status <> 'active' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be suspended', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'suspended', suspend_reason = p_reason, record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'active', 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.suspend_vendor_profile is
  'PRC-251. Prompt 269: ISS-2026-054 (C-05) folds tenant membership into the not-found branch; ISS-2026-055 reorders the stale_version check to run AFTER the authority check, so neither the real tenant_id nor the real record_version is ever disclosed to a caller not yet shown to hold both tenant membership and PRC:Override.';

create or replace function app.reactivate_vendor_profile(
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be reactivated', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'active', suspend_reason = null, record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'suspended', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.reactivate_vendor_profile is
  'PRC-251. Prompt 269: ISS-2026-054 (C-05) folds tenant membership into the not-found branch; ISS-2026-055 reorders the stale_version check to run AFTER the authority check (confirmed to share suspend_vendor_profile''s identical ordering bug by direct read, not assumed).';

create or replace function app.archive_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
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
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be archived (must be suspended first)', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'archived', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'suspended', 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.archive_vendor_profile is
  'PRC-251: reachable only from suspended, per docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md §9''s literal arrow chain (active <-> suspended -> archived) -- an active vendor must be suspended (with its own required reason) before it can be archived. Prompt 269: ISS-2026-054 (C-05) folds tenant membership into the not-found branch; ISS-2026-055 reorders the stale_version check to run AFTER the authority check (confirmed to share suspend_vendor_profile''s identical ordering bug by direct read, not assumed).';

create or replace function app.blacklist_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_evidence_ref text,
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
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to blacklist a vendor profile' using errcode = 'check_violation';
  end if;
  if p_evidence_ref is null or length(trim(p_evidence_ref)) = 0 then
    raise exception 'evidence_required: evidence is required to blacklist a vendor profile' using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.lifecycle_status not in ('active', 'suspended') then
    raise exception 'invalid_transition: vendor profile % is % and cannot be blacklisted', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_profile.lifecycle_status;

  update app.vendor_profiles
  set lifecycle_status = 'blacklisted', blacklist_reason = p_reason, blacklist_evidence_ref = p_evidence_ref,
      record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, v_from_status, 'blacklisted', p_reason, p_evidence_ref, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'blacklist_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, jsonb_build_object('evidence_ref', p_evidence_ref)
  );

  return v_profile;
end;
$$;

comment on function app.blacklist_vendor_profile is
  'PRC-251. Prompt 269: ISS-2026-054 (C-05) folds tenant membership into the not-found branch; ISS-2026-055 reorders the stale_version check to run AFTER the authority check (confirmed to share suspend_vendor_profile''s identical ordering bug by direct read, not assumed).';

-- ===========================================================================
-- Group 2 of 5: supabase/migrations/20260730590000_create_procurement_vendor_assessment.sql
-- (Fix 4 only -- pure reads, no record_version/stale_version check present)
-- ===========================================================================

create or replace function app.get_vendor_assessment_score_breakdown(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (
  criterion_id uuid, label text, purpose_tag text, weight numeric, answer_score numeric, contribution numeric,
  value text, notes text, evidence_file_id uuid, answered boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_view_cost boolean;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_view_cost := app.has_prc_view_cost(v_assessment.tenant_id, p_actor_auth_user_id);

  return query
  select c.id, c.label, c.purpose_tag, c.weight, a.score,
    round(c.weight * coalesce(a.score, 0) / 100.0, 2),
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.value end,
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.notes end,
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.evidence_file_id end,
    (a.id is not null)
  from app.vendor_assessment_template_criteria c
  left join app.vendor_assessment_answers a on a.criterion_id = c.id and a.assessment_id = p_assessment_id
  where c.template_version_id = v_assessment.template_version_id and c.status = 'active'
  order by c.display_order, c.label;
end;
$$;

comment on function app.get_vendor_assessment_score_breakdown is 'PRC-252: the explainable-scoring READ RPC (design note 3) -- one row per active criterion in the assessment''s own applied template version, with weight/answer_score/contribution ("criterion X contributed Y points because weight Z * score W"). value/notes/evidence_file_id are ALL masked (null) together for financial purpose_tag unless the caller holds PRC:View cost (design note 7). safety/compliance are not masked -- no seeded PRC action fits either distinctly; see design note 7 for why this migration does not widen the fixed action enum to add one. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.list_vendor_assessment_findings(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_findings where assessment_id = p_assessment_id order by created_at desc;
end;
$$;

comment on function app.list_vendor_assessment_findings is 'PRC-252. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.list_vendor_assessment_template_criteria(p_template_version_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_template_criteria
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_template_criteria where template_version_id = p_template_version_id and status = 'active' order by display_order, label;
end;
$$;

comment on function app.list_vendor_assessment_template_criteria is 'PRC-252. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.list_vendor_assessment_corrective_actions(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found or not app.has_active_tenant_membership(v_assessment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_corrective_actions where assessment_id = p_assessment_id order by created_at desc;
end;
$$;

comment on function app.list_vendor_assessment_corrective_actions is 'PRC-252. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

-- ===========================================================================
-- Group 3 of 5: supabase/migrations/20260730600000_create_procurement_vendor_compliance.sql
-- (Fix 4 only)
-- ===========================================================================

create or replace function app.get_vendor_compliance_requirement(p_requirement_version_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
begin
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id;
  if not found or not app.has_active_tenant_membership(v_requirement.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_requirements where id = p_requirement_version_id;
end;
$$;

comment on function app.get_vendor_compliance_requirement is 'PRC-253. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member -- the exact instance live-reproduced by PRC-268''s own synthesis pass.';

create or replace function app.get_vendor_compliance_waiver(p_waiver_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
begin
  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id;
  if not found or not app.has_active_tenant_membership(v_waiver.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_waivers where id = p_waiver_id;
end;
$$;

comment on function app.get_vendor_compliance_waiver is 'PRC-253. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.get_vendor_compliance_document(p_document_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
begin
  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found or not app.has_active_tenant_membership(v_document.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_documents where id = p_document_id;
end;
$$;

comment on function app.get_vendor_compliance_document is 'PRC-253. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.decide_vendor_compliance_waiver(
  p_waiver_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
  v_requirement app.vendor_compliance_requirements;
  v_gate text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a compliance waiver' using errcode = 'check_violation';
  end if;

  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id for update;
  if not found or not app.has_active_tenant_membership(v_waiver.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;

  -- Security-regression review (this same checkpoint, spot-checking the build log's own
  -- "checked and found NOT affected" claim per the task's own instruction): the
  -- self-approval identity check and the PRC:Approve/PRC:Reject authority check are now
  -- BOTH moved ahead of stale_version/invalid_transition -- same "authority before
  -- state-disclosure" discipline ISS-2026-055 already applied to the four
  -- vendor_profiles lifecycle-transition functions above. Live-reproduced defect this
  -- closes: a real tenant member holding neither PRC:Approve nor PRC:Reject (and not the
  -- waiver's own requester) could still extract the row's real, current record_version
  -- by supplying a deliberately wrong p_expected_version -- the stale_version check ran
  -- BEFORE either identity/authority check, disclosing it before the caller was ever
  -- shown to hold the authority to decide this waiver at all. The self-approval check
  -- keeps running before the authority check (its own pre-existing relative order,
  -- unchanged) -- both now simply run before, not after, stale_version/invalid_transition.
  if p_actor_auth_user_id = v_waiver.requested_by_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested vendor compliance waiver % and may not also decide it', p_actor_auth_user_id, p_waiver_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_waiver.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance waiver % expected version % but found %', p_waiver_id, p_expected_version, v_waiver.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_waiver.status <> 'pending' then
    raise exception 'invalid_transition: vendor compliance waiver % is already %', p_waiver_id, v_waiver.status using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_waivers
  set status = p_decision, approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, decision_reason = p_decision_reason,
      record_version = record_version + 1, updated_at = now()
  where id = p_waiver_id and record_version = p_expected_version
  returning * into v_waiver;
  if not found then
    raise exception 'stale_version: vendor compliance waiver % target row was concurrently modified (expected version %)', p_waiver_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_waiver.requirement_version_id;
  perform app._recalculate_vendor_compliance_status_family(v_waiver.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_waiver.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', p_decision_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_waiver;
end;
$$;

comment on function app.decide_vendor_compliance_waiver is 'PRC-253: MANDATORY maker-checker (design note 12) -- rejects self_approval_not_allowed if the actor is the waiver''s own requester, mirroring app.decide_vendor_assessment_review''s exact wording/shape. Approved requires PRC:Approve, rejected requires PRC:Reject. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member. Same-checkpoint security-regression fix (ISS-2026-055 discipline, not originally scoped to this function): self_approval_not_allowed and the PRC:Approve/PRC:Reject authority check now BOTH run before stale_version/invalid_transition, so the row''s real record_version/status are never disclosed to a caller not yet shown to hold the authority to decide it (the write itself was never bypassable -- only the disclosure ordering is fixed here).';

-- ===========================================================================
-- Group 4 of 5: supabase/migrations/20260730610000_create_procurement_vendor_financial_security.sql
-- (Fix 4 only)
-- ===========================================================================

create or replace function app.get_vendor_payment_term_proposal(p_proposal_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_proposal app.vendor_payment_term_proposals;
begin
  select * into v_proposal from app.vendor_payment_term_proposals where id = p_proposal_id;
  if not found or not app.has_active_tenant_membership(v_proposal.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_payment_term_proposal_not_found: %', p_proposal_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_proposal.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_proposal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_proposal;
end;
$$;

comment on function app.get_vendor_payment_term_proposal is 'PRC-254. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

-- ===========================================================================
-- Group 5 of 5: supabase/migrations/20260730630000_create_procurement_sourcing.sql
-- (Fix 4 only)
-- ===========================================================================

create or replace function app.list_sourcing_candidates(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.sourcing_candidates_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- app.sourcing_candidates_directory carries no masking (design note 11) -- its own
  -- row filter is still auth.uid()-based, so this RPC (already independently
  -- authorized above via the explicit p_actor_auth_user_id) reads the base table
  -- directly, same reasoning as app.get_sourcing_request.
  return query
  select c.* from app.sourcing_candidates c
  where c.sourcing_request_id = p_sourcing_request_id
  order by c.eligible desc, c.created_at;
end;
$$;

comment on function app.list_sourcing_candidates is 'PRC-256. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

create or replace function app.get_sourcing_request_history(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.sourcing_request_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.sourcing_request_events where sourcing_request_id = p_sourcing_request_id order by occurred_at;
end;
$$;

comment on function app.get_sourcing_request_history is 'PRC-256. Prompt 269 (ISS-2026-054, C-05): folds tenant membership into the not-found branch, never disclosing the real tenant_id to a non-member.';

-- ===========================================================================
-- Fix 6: ISS-2026-056 (MEDIUM) -- missing (tenant_id, created_at desc) covering
-- index on app.vendor_contracts, mirroring purchase_orders_tenant_created_idx /
-- rfqs_tenant_created_idx / vendor_comparisons_tenant_created_idx exactly. Plain
-- CREATE INDEX (no CONCURRENTLY -- this repository does not use it anywhere).
-- ===========================================================================

create index vendor_contracts_tenant_created_idx on app.vendor_contracts (tenant_id, created_at desc);

comment on index app.vendor_contracts_tenant_created_idx is
  'ISS-2026-056 (Prompt 269): closes the one covering index app.vendor_contracts was missing relative to its three siblings (purchase_orders_tenant_created_idx / rfqs_tenant_created_idx / vendor_comparisons_tenant_created_idx) -- lets app.list_vendor_contracts''s own tenant-scoped `order by created_at desc limit` do an ordered Index Scan with early-LIMIT termination instead of degrading to a full Seq Scan under single-tenant-concentration skew (live-reproduced by PRC-268''s own synthesis).';
