-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Third fix pass, Procurement lane (sourcing + vendor comparison + procurement approval).
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
-- that defines each function (20260730630000_create_procurement_sourcing.sql, 20260730650000_create_procurement_vendor_comparison.sql, 20260730660000_create_procurement_approval.sql) -- copied
-- verbatim, with the single `if not found` line per function changed as described above.
-- Signatures are unchanged throughout, so grants are unaffected.
--
-- This file: 18 functions, 27 at-risk raise sites.

create or replace function app.activate_vendor_profile(
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

  if v_profile.lifecycle_status <> 'approved' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be activated', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- PRC-259: the gated "next lifecycle transition" -- a vendor cannot go active while a
  -- crossed governance threshold from app.decide_vendor_profile_review''s own approve
  -- arm is still pending platform-routed approval.
  if v_profile.approval_status not in ('approved', 'not_required') then
    raise exception 'vendor_activation_approval_pending: vendor profile % approval_status is % (must be approved or not_required)', p_master_record_id, v_profile.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'active', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'approved', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create or replace function app.cancel_procurement_exception_request(
  p_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_exception_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.procurement_exception_requests;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a procurement exception request' using errcode = 'check_violation';
  end if;

  select * into v_row from app.procurement_exception_requests where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'procurement_exception_request_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: procurement exception request % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'submitted' then
    raise exception 'invalid_transition: procurement exception request % is % and cannot be cancelled', p_id, v_row.status
      using errcode = 'check_violation';
  end if;

  if v_row.approval_request_id is not null then
    perform app.cancel_approval_request(v_row.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
  end if;

  update app.procurement_exception_requests
  set status = 'cancelled'
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: procurement exception request % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_procurement_exception_request',
    'app.procurement_exception_requests', v_row.id, 'success', p_reason, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create or replace function app.cancel_sourcing_request(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a sourcing request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('draft', 'open') then
    raise exception 'invalid_transition: sourcing request % is % and cannot be cancelled', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_request.status;

  update app.sourcing_requests
  set status = 'cancelled', closed_reason = p_reason
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create or replace function app.cancel_vendor_comparison(
  p_comparison_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vendor comparison' using errcode = 'check_violation';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found or not app.has_active_tenant_membership(v_comparison.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_comparison.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % and cannot be cancelled', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'cancelled'
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_comparison',
    'app.vendor_comparisons', v_comparison.id, 'success', p_reason, null, jsonb_build_object('status', v_comparison.status)
  );

  return v_comparison;
end;
$$;

create or replace function app.close_sourcing_request_no_source(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to close a sourcing request with no source' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and cannot be closed no-source', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'closed_no_source', closed_reason = p_reason
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'open', 'closed_no_source', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_sourcing_request_no_source',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create or replace function app.evaluate_sourcing_candidate_eligibility(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.sourcing_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_vendor record;
  v_vendor_count integer := 0;
  v_reasons text[];
  v_snapshot jsonb;
  v_service_match jsonb;
  v_coverage_match jsonb;
  v_compliance_rows jsonb;
  v_has_hold boolean;
  v_has_active_rate boolean;
  v_candidate app.sourcing_candidates;
  v_final_status text;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and candidate eligibility may only be evaluated while open', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  for v_vendor in
    select vp.master_record_id, mr.code, mr.name
    from app.vendor_profiles vp
    join app.master_records mr on mr.id = vp.master_record_id
    where vp.tenant_id = v_request.tenant_id and vp.lifecycle_status = 'active'
    order by vp.master_record_id
    limit 501
  loop
    v_vendor_count := v_vendor_count + 1;
    -- design note 9: bounded scan, disclosed via a real warning, never a silent
    -- truncation.
    if v_vendor_count > 500 then
      raise warning 'sourcing_candidate_scan_bounded: sourcing request % has more than 500 active vendors in tenant % -- only the first 500 (ordered by master_record_id) were evaluated this call; re-run to cover the remainder', p_sourcing_request_id, v_request.tenant_id;
      exit;
    end if;

    v_reasons := array[]::text[];

    -- vendor_not_active (design note 8): defensive completeness only -- the WHERE
    -- clause above already filters lifecycle_status='active', so this branch is
    -- structurally unreachable in a single-threaded evaluation. Kept as a named
    -- reason code for explainability if a future caller composes eligibility
    -- differently, or a race changes lifecycle_status mid-loop.
    if not exists (select 1 from app.vendor_profiles where master_record_id = v_vendor.master_record_id and lifecycle_status = 'active') then
      v_reasons := array_append(v_reasons, 'vendor_not_active');
    end if;

    select jsonb_agg(jsonb_build_object('id', vs.id, 'service_type', vs.service_type)) into v_service_match
    from app.vendor_services vs
    where vs.master_record_id = v_vendor.master_record_id and vs.status = 'active' and vs.service_type = v_request.service_type;
    if v_service_match is null then
      v_reasons := array_append(v_reasons, 'service_mismatch');
    end if;

    select jsonb_agg(jsonb_build_object('id', vc.id, 'origin_lane', vc.origin_lane, 'destination_lane', vc.destination_lane)) into v_coverage_match
    from app.vendor_coverage vc
    where vc.master_record_id = v_vendor.master_record_id and vc.status = 'active'
      and vc.origin_lane = v_request.origin_lane
      and (vc.destination_lane is null or vc.destination_lane = v_request.destination_lane);
    if v_coverage_match is null then
      v_reasons := array_append(v_reasons, 'coverage_mismatch');
    end if;

    select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb), bool_or(e.eligibility_hold)
    into v_compliance_rows, v_has_hold
    from app.get_vendor_compliance_eligibility(v_vendor.master_record_id, p_actor_auth_user_id) e;
    if coalesce(v_has_hold, false) then
      v_reasons := array_append(v_reasons, 'compliance_ineligible');
    end if;

    select exists (
      select 1 from app.vendor_rate_versions rv
      where rv.vendor_master_id = v_vendor.master_record_id and rv.tenant_id = v_request.tenant_id and rv.approval_status = 'approved'
        and rv.effective_from <= now() and (rv.effective_to is null or rv.effective_to > now())
    ) into v_has_active_rate;

    v_snapshot := jsonb_build_object(
      'vendor_code', v_vendor.code,
      'vendor_name', v_vendor.name,
      'service_match', coalesce(v_service_match, '[]'::jsonb),
      'coverage_match', coalesce(v_coverage_match, '[]'::jsonb),
      'compliance_rows', coalesce(v_compliance_rows, '[]'::jsonb),
      'has_active_rate', coalesce(v_has_active_rate, false),
      'evaluated_at', now()
    );

    insert into app.sourcing_candidates (tenant_id, sourcing_request_id, vendor_master_id, eligible, exclusion_reasons, evaluation_snapshot)
    values (v_request.tenant_id, p_sourcing_request_id, v_vendor.master_record_id, cardinality(v_reasons) = 0, v_reasons, v_snapshot)
    on conflict (sourcing_request_id, vendor_master_id) do update
    set eligible = excluded.eligible, exclusion_reasons = excluded.exclusion_reasons, evaluation_snapshot = excluded.evaluation_snapshot
    returning * into v_candidate;

    return next v_candidate;
  end loop;

  -- ADVERSARIAL REVIEW FIX (design note 16c): the leading status check above uses a
  -- plain, unlocked read (a fast-path early-exit, not the authoritative gate) -- a
  -- concurrent cancel_sourcing_request/close_sourcing_request_no_source/
  -- submit_sourcing_shortlist (each of which takes `for update` on this same row)
  -- could otherwise commit a status change mid-scan, leaving freshly written
  -- sourcing_candidates rows for a request that is no longer open. This final,
  -- locked re-check is the real gate: raising here rolls back every candidate
  -- upsert this call performed, in the same transaction. Locked only now, AFTER
  -- every candidate row this call itself touched is already locked by the loop's
  -- own upserts -- preserves the same lock order app.shortlist_sourcing_candidate
  -- uses (candidate row(s) before the parent request row), so the two functions
  -- cannot deadlock against each other.
  select status into v_final_status from app.sourcing_requests where id = p_sourcing_request_id for update;
  if v_final_status <> 'open' then
    raise exception 'invalid_transition: sourcing request % transitioned to % while candidate eligibility was being evaluated -- re-run once reopened', p_sourcing_request_id, v_final_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_sourcing_candidate_eligibility',
    'app.sourcing_requests', p_sourcing_request_id, 'success', null, null, jsonb_build_object('vendor_count_evaluated', least(v_vendor_count, 500))
  );

  return;
end;
$$;

create or replace function app.link_vendor_comparison_offer_rate(
  p_comparison_offer_id uuid,
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
  v_rate app.vendor_rate_versions;
  v_calc record;
  v_norm record;
begin
  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Design note 7 consistency: every whole-operation authority gate (PRC:Edit,
  -- PRC:View cost, FIN:View) runs together, before any state-dependent check
  -- (record_version/comparison.status/basis_quantity) can disclose anything
  -- beyond this row's bare existence -- mirrors app.create_vendor_comparison/
  -- app.revise_vendor_comparison's own gate ordering exactly, rather than
  -- letting the FIN:View gate surface after state has already been read.
  if not app.check_finance_exchange_rate_authority('View', v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison offer % expected version % but found %', p_comparison_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;

  -- design note 9: child (offer) already locked above, parent (comparison)
  -- locked here, second.
  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be edited while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;
  if v_comparison.basis_quantity is null or v_comparison.basis_quantity <= 0 then
    raise exception 'invalid_basis_quantity: comparison % has no positive basis_quantity -- the rate engine requires one to compute an amount', v_comparison.id
      using errcode = 'check_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;
  if v_rate.tenant_id <> v_comparison.tenant_id then
    raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_comparison.tenant_id
      using errcode = 'check_violation';
  end if;
  -- Self-caught during this checkpoint's own Tier B walk (RECURRING_DEFECT_
  -- TAXONOMY.md class-C-19-adjacent "wrong scope tuple" shape, fixed in place
  -- before this migration was ever applied anywhere): app.vendor_rate_
  -- versions.master_record_id is the vendor_rate-TYPED identity row
  -- (app.create_master_record('vendor_rate', ...), COM-149) -- a SEPARATE
  -- identity from the real canonical Procurement vendor
  -- (app.vendor_profiles.master_record_id, master_type_code='vendor') that
  -- app.vendor_comparison_offers.vendor_master_id always carries. Comparing
  -- against master_record_id would reject every real link attempt (the two
  -- id spaces never coincide). PRC-255's own ADR-0020 widening added the
  -- correctly-typed, correctly-named app.vendor_rate_versions.vendor_master_id
  -- column (nullable, optionally supplied at app.create_rate_version time)
  -- for exactly this comparison -- reused here, never re-derived.
  if v_rate.vendor_master_id is distinct from v_offer.vendor_master_id then
    raise exception 'vendor_mismatch: rate version % does not belong to the offer''s own vendor %', p_rate_version_id, v_offer.vendor_master_id
      using errcode = 'check_violation';
  end if;
  if v_rate.approval_status <> 'approved' then
    raise exception 'invalid_rate_status: rate version % is % -- only an approved rate may be linked', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  -- design note 4: the ONE call site for app.calculate_vendor_rate composition.
  select * into v_calc from app.calculate_vendor_rate(p_rate_version_id, v_comparison.basis_weight, v_comparison.basis_volume, v_comparison.basis_quantity, p_actor_auth_user_id);

  select * into v_norm from app._normalize_vendor_comparison_currency(
    v_comparison.tenant_id, v_comparison.comparison_currency, v_calc.currency, v_calc.computed_amount, p_actor_auth_user_id
  );
  if not v_norm.ok then
    raise exception 'fx_conversion_failed: could not normalize the rate-engine amount from % to % (%)', v_calc.currency, v_comparison.comparison_currency, v_norm.failure_code
      using errcode = 'no_data_found';
  end if;

  update app.vendor_comparison_offers
  set rate_version_id = p_rate_version_id,
      engine_computed_amount = v_calc.computed_amount,
      engine_currency = v_calc.currency,
      engine_breakdown = to_jsonb(v_calc),
      normalized_amount = v_norm.normalized_amount,
      normalization_lineage = v_norm.lineage || jsonb_build_object('basis', 'rate_engine', 'rateVersionId', p_rate_version_id)
  where id = p_comparison_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor comparison offer % target row was concurrently modified (expected version %)', p_comparison_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_vendor_comparison_offer_rate',
    'app.vendor_comparison_offers', v_offer.id, 'success', null, null, jsonb_build_object('rate_version_id', p_rate_version_id, 'normalized_amount', v_offer.normalized_amount)
  );

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id;
  return v_offer;
end;
$$;

create or replace function app.override_sourcing_request_constraints(
  p_sourcing_request_id uuid,
  p_cargo_weight_max numeric,
  p_cargo_volume_max numeric,
  p_destination_lane text,
  p_reason text,
  p_override_expires_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_new_weight_max numeric;
  v_new_volume_max numeric;
  v_new_destination_lane text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to override sourcing request constraints' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % -- constraints may only be overridden while open', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- design note 10: widen-only, literal reading -- the check only fires when a
  -- value is ALREADY stored; a null-to-value transition always succeeds.
  if p_cargo_weight_max is not null and v_request.cargo_weight_max is not null and p_cargo_weight_max < v_request.cargo_weight_max then
    raise exception 'constraint_narrowing_not_allowed: cargo_weight_max override % is less than the current value % -- an override widens, it never narrows', p_cargo_weight_max, v_request.cargo_weight_max
      using errcode = 'check_violation';
  end if;
  if p_cargo_volume_max is not null and v_request.cargo_volume_max is not null and p_cargo_volume_max < v_request.cargo_volume_max then
    raise exception 'constraint_narrowing_not_allowed: cargo_volume_max override % is less than the current value % -- an override widens, it never narrows', p_cargo_volume_max, v_request.cargo_volume_max
      using errcode = 'check_violation';
  end if;

  v_new_weight_max := coalesce(p_cargo_weight_max, v_request.cargo_weight_max);
  v_new_volume_max := coalesce(p_cargo_volume_max, v_request.cargo_volume_max);
  v_new_destination_lane := coalesce(nullif(trim(p_destination_lane), ''), v_request.destination_lane);

  update app.sourcing_requests
  set cargo_weight_max = v_new_weight_max, cargo_volume_max = v_new_volume_max, destination_lane = v_new_destination_lane
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (
    v_request.tenant_id, p_sourcing_request_id, 'open', 'open', p_reason,
    case when p_override_expires_at is not null then 'override_expires_at=' || p_override_expires_at::text else null end,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_sourcing_request_constraints',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null,
    jsonb_build_object('cargo_weight_max', v_request.cargo_weight_max, 'cargo_volume_max', v_request.cargo_volume_max, 'destination_lane', v_request.destination_lane, 'override_expires_at', p_override_expires_at)
  );

  return v_request;
end;
$$;

create or replace function app.publish_procurement_approval_policy_version(
  p_policy_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_approval_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.procurement_approval_policies;
  v_superseded app.procurement_approval_policies;
  v_decision app.rbac_decision;
begin
  select * into v_policy from app.procurement_approval_policies where id = p_policy_version_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'procurement_approval_policy_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;

  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: procurement approval policy % expected version % but found %', p_policy_version_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: procurement approval policy % is % and cannot be published', p_policy_version_id, v_policy.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.procurement_approval_policies where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_policy_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_policy.tenant_id or v_superseded.entity_type <> v_policy.entity_type then
      raise exception 'invalid_supersede: superseded policy must share the same tenant and entity_type'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded policy % is % (must be published)', p_supersedes_version_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
    update app.procurement_approval_policies set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.procurement_approval_policies
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_policy_version_id and record_version = p_expected_version
    returning * into v_policy;
  exception
    when unique_violation then
      raise exception 'active_policy_exists: tenant % already has a published % policy -- supply p_supersedes_version_id to replace it', v_policy.tenant_id, v_policy.entity_type
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: procurement approval policy % target row was concurrently modified (expected version %)', p_policy_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_procurement_approval_policy_version',
    'app.procurement_approval_policies', v_policy.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_policy;
end;
$$;

create or replace function app.recommend_vendor_comparison_offer(
  p_comparison_id uuid,
  p_comparison_offer_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_lowest_id uuid;
  v_from_status text;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found or not app.has_active_tenant_membership(v_comparison.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_comparison.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- only a draft or recommended comparison accepts a recommendation', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', p_comparison_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: offer % is excluded and cannot be recommended', p_comparison_offer_id using errcode = 'check_violation';
  end if;

  -- Business rule: lowest price is not automatic selection, but a reviewer
  -- who recommends anything OTHER than the lowest normalized cost among
  -- included offers must state why.
  select id into v_lowest_id
  from app.vendor_comparison_offers
  where comparison_id = p_comparison_id and included = true and normalized_amount is not null
  order by normalized_amount asc
  limit 1;

  if v_lowest_id is distinct from p_comparison_offer_id and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to recommend an offer other than the lowest normalized cost' using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'recommended', recommended_offer_id = p_comparison_offer_id, recommended_reason = p_reason, recommended_at = now()
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, v_from_status, 'recommended', p_reason, p_comparison_offer_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'recommend_vendor_comparison_offer',
    'app.vendor_comparisons', v_comparison.id, 'success', p_reason, null, jsonb_build_object('recommended_offer_id', p_comparison_offer_id)
  );

  return v_comparison;
end;
$$;

create or replace function app.reopen_sourcing_request(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a sourcing request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('shortlisted', 'closed_no_source', 'cancelled') then
    raise exception 'invalid_transition: sourcing request % is % and cannot be reopened', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_request.status;

  update app.sourcing_requests
  set status = 'open', shortlist_locked_at = null, closed_reason = null
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, v_from_status, 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create or replace function app.revise_vendor_comparison(
  p_comparison_id uuid,
  p_comparison_currency text,
  p_basis_weight numeric,
  p_basis_volume numeric,
  p_basis_quantity numeric,
  p_criteria jsonb,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_old app.vendor_comparisons;
  v_from_status text;
  v_existing app.vendor_comparisons;
  v_new app.vendor_comparisons;
  v_new_currency text;
  v_new_weight numeric;
  v_new_volume numeric;
  v_new_quantity numeric;
  v_new_criteria jsonb;
  v_constraint_name text;
  v_offer_count integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revise a vendor comparison' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_old from app.vendor_comparisons where id = p_comparison_id for update;
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_old.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_exchange_rate_authority('View', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_currency := coalesce(nullif(trim(p_comparison_currency), ''), v_old.comparison_currency);
  if not app.validate_currency_code(v_new_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', v_new_currency using errcode = 'check_violation';
  end if;
  v_new_weight := coalesce(p_basis_weight, v_old.basis_weight);
  v_new_volume := coalesce(p_basis_volume, v_old.basis_volume);
  v_new_quantity := coalesce(p_basis_quantity, v_old.basis_quantity);
  v_new_criteria := app._normalize_vendor_comparison_criteria(coalesce(p_criteria, v_old.criteria_snapshot));

  select * into v_existing from app.vendor_comparisons where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_comparison_id or v_existing.comparison_currency is distinct from v_new_currency
      or v_existing.basis_weight is distinct from v_new_weight or v_existing.basis_volume is distinct from v_new_volume
      or v_existing.basis_quantity is distinct from v_new_quantity or v_existing.criteria_snapshot is distinct from v_new_criteria
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison revision', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_old.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_old.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_old.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- only a draft or recommended comparison may be revised', p_comparison_id, v_old.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'superseded'
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_old;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.vendor_comparisons (
      tenant_id, org_unit_id, rfq_id, sourcing_request_id, version, revised_from_id, comparison_currency,
      basis_weight, basis_volume, basis_quantity, criteria_snapshot, status, idempotency_key, created_by
    ) values (
      v_old.tenant_id, v_old.org_unit_id, v_old.rfq_id, v_old.sourcing_request_id, v_old.version + 1, v_old.id, v_new_currency,
      v_new_weight, v_new_volume, v_new_quantity, v_new_criteria, 'draft', p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_comparisons_tenant_idempotency_unique' then
        select * into v_existing from app.vendor_comparisons where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.revised_from_id is distinct from p_comparison_id or v_existing.comparison_currency is distinct from v_new_currency
            or v_existing.basis_weight is distinct from v_new_weight or v_existing.basis_volume is distinct from v_new_volume
            or v_existing.basis_quantity is distinct from v_new_quantity or v_existing.criteria_snapshot is distinct from v_new_criteria
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison revision', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  perform app._snapshot_vendor_comparison_offers(v_new, p_actor_auth_user_id);

  select count(*) into v_offer_count from app.vendor_comparison_offers where comparison_id = v_new.id;
  if v_offer_count = 0 then
    raise exception 'no_comparable_responses: rfq % has no submitted, comparison-eligible responses to compare', v_new.rfq_id
      using errcode = 'check_violation';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_new.id);

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_old.tenant_id, v_old.id, v_from_status, 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);
  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_new.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_vendor_comparison',
    'app.vendor_comparisons', v_new.id, 'success', p_reason, to_jsonb(v_old), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

create or replace function app.score_vendor_comparison_offer_criterion(
  p_comparison_offer_id uuid,
  p_criterion_key text,
  p_score numeric,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offer_scores
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
  v_criterion jsonb;
  v_weight numeric;
  v_row app.vendor_comparison_offer_scores;
begin
  if p_criterion_key is null or length(trim(p_criterion_key)) = 0 then
    raise exception 'criterion_key_required: p_criterion_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_criterion_key = 'price' then
    raise exception 'invalid_criterion: price is system-computed and cannot be manually scored' using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_score > 100 then
    raise exception 'invalid_score: score must be between 0 and 100' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be scored while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select elem into v_criterion
  from jsonb_array_elements(v_comparison.criteria_snapshot) as elem
  where elem ->> 'key' = p_criterion_key
  limit 1;
  if not found then
    raise exception 'unknown_criterion: % is not a configured criterion for this comparison', p_criterion_key using errcode = 'check_violation';
  end if;
  v_weight := (v_criterion ->> 'weight')::numeric;

  insert into app.vendor_comparison_offer_scores (tenant_id, comparison_offer_id, criterion_key, criterion_weight, score, notes, scored_by)
  values (v_offer.tenant_id, p_comparison_offer_id, p_criterion_key, v_weight, p_score, p_notes, p_actor_label)
  on conflict (comparison_offer_id, criterion_key)
  do update set score = excluded.score, notes = excluded.notes, scored_by = excluded.scored_by, scored_at = now(), criterion_weight = excluded.criterion_weight
  returning * into v_row;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'score_vendor_comparison_offer_criterion',
    'app.vendor_comparison_offer_scores', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create or replace function app.set_vendor_comparison_offer_inclusion(
  p_comparison_offer_id uuid,
  p_included boolean,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
begin
  if not coalesce(p_included, true) and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to exclude a comparison offer' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison offer % expected version % but found %', p_comparison_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be edited while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparison_offers
  set included = p_included, exclusion_reason = case when p_included then null else p_reason end
  where id = p_comparison_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor comparison offer % target row was concurrently modified (expected version %)', p_comparison_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vendor_comparison_offer_inclusion',
    'app.vendor_comparison_offers', v_offer.id, 'success', p_reason, null, jsonb_build_object('included', v_offer.included)
  );

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id;
  return v_offer;
end;
$$;

create or replace function app.shortlist_sourcing_candidate(
  p_candidate_id uuid,
  p_shortlisted boolean,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.sourcing_candidates;
  v_request app.sourcing_requests;
  v_action text;
begin
  select * into v_candidate from app.sourcing_candidates where id = p_candidate_id for update;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;

  -- design note 6: reason is unconditionally required whenever shortlisted=true
  -- (mirrors the table CHECK), regardless of eligibility; only the AUTHORITY
  -- required differs by eligibility. v_action is derived from the already-locked
  -- candidate row's own eligible field -- no additional query needed.
  if p_shortlisted then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: shortlisting a candidate requires a non-empty reason' using errcode = 'check_violation';
    end if;
    v_action := case when v_candidate.eligible then 'Edit' else 'Override' end;
  else
    v_action := 'Edit';
  end if;

  -- ADVERSARIAL REVIEW FIX (design note 16b): permission is now evaluated BEFORE
  -- the parent sourcing_request is read at all -- the original ordering fetched
  -- v_request.status first (a plain, unlocked SELECT) and disclosed it via
  -- invalid_transition even to a caller who fails this very permission check,
  -- including a cross-tenant actor with zero role assignment in v_candidate's own
  -- tenant. Every sibling transition RPC in this migration already checks
  -- permission immediately after its own existence/lock check; this was the sole
  -- outlier.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'PRC', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing candidate % expected version % but found %', p_candidate_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;

  -- ADVERSARIAL REVIEW FIX (design note 16b): the parent row is now locked `for
  -- update` -- matching every sibling transition RPC's own "for update" shape --
  -- closing a real race where a concurrent submit_sourcing_shortlist/
  -- close_sourcing_request_no_source/cancel_sourcing_request (each of which locks
  -- this same row) could commit a status change between an unlocked read here and
  -- this function's own terminal UPDATE. Locked only now (after the candidate row
  -- is already locked, and only this one row) -- matching the lock order
  -- app.evaluate_sourcing_candidate_eligibility's own end-of-call recheck uses
  -- (candidate row(s) before the parent request row), so the two functions cannot
  -- deadlock against each other.
  select * into v_request from app.sourcing_requests where id = v_candidate.sourcing_request_id for update;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % -- candidates may only be shortlisted/un-shortlisted while open', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_candidates
  set shortlisted = p_shortlisted,
      shortlist_reason = case when p_shortlisted then p_reason else null end,
      shortlisted_by = case when p_shortlisted then p_actor_label else null end,
      shortlisted_at = case when p_shortlisted then now() else null end
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: sourcing candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'shortlist_sourcing_candidate',
    'app.sourcing_candidates', v_candidate.id, 'success', p_reason, null,
    jsonb_build_object('shortlisted', v_candidate.shortlisted, 'eligible', v_candidate.eligible)
  );

  return v_candidate;
end;
$$;

create or replace function app.submit_sourcing_request(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.source_type <> 'proactive' then
    raise exception 'invalid_transition: sourcing request % is source_type % -- only a proactive request may be submitted (costing/operational-sourced requests are created directly into open)', p_sourcing_request_id, v_request.source_type
      using errcode = 'check_violation';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: sourcing request % is % and cannot be submitted', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'open'
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'draft', 'open', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', null, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create or replace function app.submit_sourcing_shortlist(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_shortlisted_count integer;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and cannot submit a shortlist', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_shortlisted_count from app.sourcing_candidates where sourcing_request_id = p_sourcing_request_id and shortlisted = true;
  if v_shortlisted_count = 0 then
    raise exception 'no_candidates_shortlisted: sourcing request % has zero shortlisted candidates', p_sourcing_request_id using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'shortlisted', shortlist_locked_at = now()
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'open', 'shortlisted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_sourcing_shortlist',
    'app.sourcing_requests', v_request.id, 'success', null, null, jsonb_build_object('shortlisted_count', v_shortlisted_count)
  );

  return v_request;
end;
$$;

create or replace function app.submit_vendor_comparison_for_approval(
  p_comparison_id uuid,
  p_selected_offer_id uuid,
  p_selection_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found or not app.has_active_tenant_membership(v_comparison.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status <> 'recommended' then
    raise exception 'invalid_transition: vendor comparison % is % -- only a recommended comparison may be submitted', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_selected_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', p_selected_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: offer % is excluded and cannot be selected', p_selected_offer_id using errcode = 'check_violation';
  end if;

  if p_selected_offer_id is distinct from v_comparison.recommended_offer_id and (p_selection_reason is null or length(trim(p_selection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to select an offer other than the recommended one' using errcode = 'check_violation';
  end if;

  -- PRC-259: resolve governance routing before the single UPDATE below --
  -- p_comparison_id is already the entity's own stable primary key (this row is never
  -- re-submitted a second time, status='submitted' being terminal within PRC-258's own
  -- scope), so it is used verbatim as the idempotency key.
  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'vendor_selection', v_comparison.tenant_id, p_comparison_id, v_offer.normalized_amount, v_comparison.comparison_currency,
    jsonb_build_object('rfq_id', v_comparison.rfq_id, 'selected_offer_id', p_selected_offer_id),
    p_expected_version + 1, 'vendor_selection:' || p_comparison_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  update app.vendor_comparisons
  set status = 'submitted', selected_offer_id = p_selected_offer_id, selection_reason = p_selection_reason,
      submitted_at = now(), submitted_by = p_actor_label,
      approval_status = v_gov_approval_status, approval_request_id = v_gov_approval_request_id
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, 'recommended', 'submitted', p_selection_reason, p_selected_offer_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_comparison_for_approval',
    'app.vendor_comparisons', v_comparison.id, 'success', p_selection_reason, null, jsonb_build_object('selected_offer_id', p_selected_offer_id, 'approval_status', v_gov_approval_status)
  );

  return v_comparison;
end;
$$;
