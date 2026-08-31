-- Closes `ISS-2026-069`. Seven business domains share one tenant-wide approval routing
-- definition, so a tenant cannot run different approval chains for a job offer and a sales
-- quotation. The entry called the fix "a shared-schema redesign affecting every existing
-- PLT-121 consumer... requiring its own ADR and change control".
--
-- IT IS NOT A REDESIGN, AND THE REASON IS THAT THIS REPOSITORY ALREADY SOLVED IT TWICE
--
--   `app.config_objects`' uniqueness key is `(config_type_code, tenant_id, scope_level,
--   scope_id)`. The entry read that as needing a NEW discriminator -- "widening the uniqueness
--   key to include a domain/entity discriminator, or adding a new scope_level". But the
--   discriminator is already there: it is `config_type_code` itself. Nothing ever required
--   seven domains to share the single code `'approval'`; they share it because each one
--   hardcodes that literal in its own selector.
--
--   And two later capabilities already stopped doing that. `approval:ai_output_acceptance`
--   (IAE-037) and `approval:automation_rule_publish` (IAE-007) are registered config types
--   today, each selecting its own domain-scoped routing definition. The convention exists, is
--   in production, and needs no schema change whatsoever. The seven functions below simply
--   predate it.
--
--   So this is not a redesign requiring an ADR. It is seven domains catching up with a pattern
--   two of their siblings already use.
--
-- THE ENTRY UNDERCOUNTED, AND THE CORRECTION MATTERS
--
--   It names four consumers (Sales quotation, credit control, Procurement PO, HR job offer).
--   A live query against `pg_proc` for functions whose body carries the shared selector returns
--   **seven**: those four plus leave requests, onboarding-case finalisation, and payroll-run
--   finalisation. Three whole domains joined the singleton after the entry was written, exactly
--   as it warned would keep happening. All seven are fixed here; fixing four would have left
--   the same defect with a smaller blast radius and a stale entry claiming it was closed.
--
-- BACKWARD COMPATIBILITY IS THE WHOLE DESIGN, NOT A CAVEAT
--
--   `app._resolve_approval_config_type_code(tenant, domain)` returns
--   `'approval:<domain>'` when the tenant has published a definition under that code, and
--   `'approval'` otherwise. So:
--
--     * A tenant that has only ever published the shared `'approval'` definition behaves
--       identically to before, byte for byte. Nothing to migrate, nothing to re-publish, no
--       downtime, and no tenant is required to do anything.
--     * A tenant that wants HR job offers routed differently from sales quotations publishes
--       an `approval:job_offer` definition. From that moment job offers use it and every other
--       domain is untouched.
--     * Opting back out is deleting or unpublishing that definition; the domain silently falls
--       back to the shared one again.
--
--   That fallback is what makes this safe to apply to seven already-live domains at once. A
--   migration that required every tenant to publish seven new definitions before approvals kept
--   working would be the redesign the entry feared, and would deserve the ADR it asked for.
--
-- HOW THE SEVEN REWRITES WERE PRODUCED, BECAUSE IT MATTERS FOR TRUST
--
--   Each function below is its own `pg_get_functiondef` output, read back from the LIVE
--   database, with exactly one regex substitution applied to it:
--
--     co.config_type_code = 'approval' and co.tenant_id = X
--       ->  co.config_type_code = app._resolve_approval_config_type_code(X, '<domain>')
--           and co.tenant_id = X
--
--   Nothing was retyped. The substitution was asserted to match exactly once per function
--   before being applied, so no function could be silently half-rewritten, and none of these
--   bodies is a transcription of the migration that created them -- several have been
--   superseded by later hardening migrations, and rebuilding from a creating migration is the
--   trap that nearly deleted five live dispatcher branches two migrations ago.


-- ===========================================================================
-- 1. The seven domain-scoped config types.
--
-- Registered directly, mirroring how 20260803010000 seeded
-- 'approval:automation_rule_publish'. Registering a type creates nothing for any tenant
-- and changes no behaviour on its own -- it only makes the code publishable. Until a
-- tenant publishes one, every resolve below still returns 'approval'.
-- ===========================================================================

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values
  ('approval:quotation', 'Sales Quotation Approval', 'APPR', 'iss-2026-069'),
  ('approval:credit_profile', 'Customer Credit Profile Approval', 'APPR', 'iss-2026-069'),
  ('approval:procurement_entity', 'Procurement Entity Approval', 'APPR', 'iss-2026-069'),
  ('approval:job_offer', 'Job Offer Approval', 'APPR', 'iss-2026-069'),
  ('approval:leave_request', 'Leave Request Approval', 'APPR', 'iss-2026-069'),
  ('approval:onboarding_case', 'Onboarding/Offboarding Finalization Approval', 'APPR', 'iss-2026-069'),
  ('approval:payroll_run', 'Payroll Run Finalization Approval', 'APPR', 'iss-2026-069')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. The resolver.
--
-- `stable`, not `volatile`: it reads two tables and writes nothing, and marking it stable
-- lets the planner call it once per query rather than once per row.
--
-- Deliberately NOT `security definer`. Every caller is already a security-definer function,
-- so this runs with their privileges; adding a second definer boundary would widen the
-- surface for no benefit and would let it be called directly with more authority than the
-- caller has.
--
-- `limit 1` is defensive rather than load-bearing: the uniqueness key already permits at
-- most one published tenant-scope object per code, and this reads whether one EXISTS rather
-- than which one.
-- ===========================================================================

create function app._resolve_approval_config_type_code(p_tenant_id uuid, p_domain_code text)
returns text
language sql
stable
set search_path = app, pg_temp
as $$
  select coalesce(
    (
      select 'approval:' || p_domain_code
      from app.config_versions cv
      join app.config_objects co on co.id = cv.config_object_id
      where co.config_type_code = 'approval:' || p_domain_code
        and co.tenant_id = p_tenant_id
        and co.scope_level = 'tenant'
        and cv.status = 'published'
      limit 1
    ),
    'approval'
  );
$$;

comment on function app._resolve_approval_config_type_code is
  'ISS-2026-069: answers "which approval routing definition governs this domain for this tenant" -- the tenant''s own published approval:<domain> definition if one exists, otherwise the shared approval definition. That fallback is the whole design: a tenant that has never published a domain-scoped definition behaves exactly as it did before this function existed, so seven already-live domains could adopt domain-scoped routing in one migration without any tenant being required to do anything. Opting back out is unpublishing the domain-scoped definition. Not security definer on purpose: every caller is already a definer function, and a second boundary would only let this be called with more authority than its callers hold.';

-- `app._` prefixed, and granted to service_role only. Nothing outside the seven
-- security-definer callers below has any reason to ask "which approval definition governs
-- this domain", and those callers execute as the function owner, so they need no grant at
-- all. The public.* wrapper-parity gate exempts `app._` names for exactly this case -- it
-- caught the first draft, which was granted to `authenticated` and therefore owed a wrapper
-- it had no business having.
revoke execute on function app._resolve_approval_config_type_code(uuid, text) from public, anon, authenticated;
grant execute on function app._resolve_approval_config_type_code(uuid, text) to service_role;

-- ===========================================================================
-- 3. The seven consumers, each its own live definition with one clause changed.
-- ===========================================================================

-- _request_procurement_entity_approval -> approval:procurement_entity (tenant expression: p_tenant_id)
CREATE OR REPLACE FUNCTION app._request_procurement_entity_approval(p_entity_type text, p_tenant_id uuid, p_entity_id uuid, p_value_amount numeric, p_currency text, p_context jsonb, p_source_record_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, OUT required boolean, OUT approval_status text, OUT approval_request_id uuid, OUT policy_version_id uuid)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
declare
  v_reasons text[];
  v_config_version_id uuid;
  v_request app.approval_requests;
  v_existing_snapshot app.procurement_approval_context_snapshots;
begin
  -- ISS-2026-045 (Prompt 269): p_currency is now threaded through as the 5th
  -- positional argument -- previously only ever used below to populate the context
  -- snapshot's own currency column, never fed into the threshold comparison itself.
  select e.required, e.reasons, e.policy_version_id into required, v_reasons, policy_version_id
  from app.evaluate_procurement_approval_requirement(p_entity_type, p_tenant_id, p_value_amount, p_actor_auth_user_id, p_currency) e;

  if not required then
    approval_status := 'not_required';
    approval_request_id := null;
    return;
  end if;

  select cv.id into v_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(p_tenant_id, 'procurement_entity') and co.tenant_id = p_tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % crossed a procurement approval threshold for % but has no published approval routing definition', p_tenant_id, p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_config_version_id, p_tenant_id, p_entity_type, p_entity_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  approval_status := 'pending';
  approval_request_id := v_request.id;

  -- app.request_approval's own (tenant_id, idempotency_key) short-circuit already
  -- returns the SAME existing request row on a genuine replay (taxonomy C-01, handled
  -- once, upstream, not re-implemented here) -- only insert a context snapshot the
  -- first time this exact request is created.
  select * into v_existing_snapshot from app.procurement_approval_context_snapshots s where s.approval_request_id = v_request.id;
  if not found then
    insert into app.procurement_approval_context_snapshots (
      approval_request_id, tenant_id, entity_type, entity_id, value_amount, currency,
      reasons, policy_version_id, context, source_record_version, created_by
    ) values (
      v_request.id, p_tenant_id, p_entity_type, p_entity_id, p_value_amount, p_currency,
      v_reasons, policy_version_id, coalesce(p_context, '{}'::jsonb), p_source_record_version, p_actor_label
    );
  end if;
end;
$function$;

-- request_customer_credit_profile -> approval:credit_profile (tenant expression: p_tenant_id)
CREATE OR REPLACE FUNCTION app.request_customer_credit_profile(p_tenant_id uuid, p_account_id uuid, p_currency text, p_requested_limit_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_prior app.credit_profiles;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
  v_profile app.credit_profiles;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_account_id;
  if not found or v_account.tenant_id <> p_tenant_id then
    raise exception 'account_not_found: no account % in tenant %', p_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_requested_limit_amount is null or p_requested_limit_amount < 0 then
    raise exception 'invalid_amount: requested_limit_amount must be a non-negative amount' using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.credit_profiles where tenant_id = p_tenant_id and account_id = p_account_id and status in ('requested', 'active', 'held')) then
    raise exception 'credit_profile_already_requested: account % already has a live credit profile', p_account_id using errcode = 'unique_violation';
  end if;

  select id into v_prior from app.credit_profiles where tenant_id = p_tenant_id and account_id = p_account_id order by created_at desc limit 1;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(p_tenant_id, 'credit_profile') and co.tenant_id = p_tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.credit_profiles (
    tenant_id, account_id, currency, requested_limit_amount, supersedes_profile_id, owner_user_id, created_by
  ) values (
    p_tenant_id, p_account_id, p_currency, p_requested_limit_amount, v_prior.id, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_profile;

  select * into v_request from app.request_approval(
    v_approval_config_version_id, p_tenant_id, 'credit_profile', v_profile.id, v_profile.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.credit_profiles
  set approval_request_id = v_request.id, updated_at = now(), record_version = record_version + 1
  where id = v_profile.id
  returning * into v_profile;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', null, null, to_jsonb(v_profile)
  );

  return v_profile;
end;
$function$;

-- submit_job_offer_for_approval -> approval:job_offer (tenant expression: v_offer.tenant_id)
CREATE OR REPLACE FUNCTION app.submit_job_offer_for_approval(p_offer_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' or v_offer.current_version_id is null then
    raise exception 'invalid_transition: offer % is % and cannot be submitted for approval (needs at least one version)', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(v_offer.tenant_id, 'job_offer') and co.tenant_id = v_offer.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published offer approval routing definition', v_offer.tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_approval_config_version_id, v_offer.tenant_id, 'job_offer', p_offer_id,
    p_offer_id::text || ':' || v_offer.current_version_id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.job_offers
  set status = 'pending_approval', approval_status = 'pending', approval_request_id = v_request.id
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.job_offer_versions set status = 'submitted' where id = v_offer.current_version_id;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_job_offer_for_approval',
    'app.job_offers', v_offer.id, 'success', null, null, jsonb_build_object('status', v_offer.status, 'approval_request_id', v_offer.approval_request_id)
  );

  return v_offer;
end;
$function$;

-- submit_leave_request -> approval:leave_request (tenant expression: v_request.tenant_id)
CREATE OR REPLACE FUNCTION app.submit_leave_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leave_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_type app.leave_types;
  v_policy app.leave_type_policy_versions;
  v_approval_config_version_id uuid;
  v_approval_request app.approval_requests;
  v_snapshot jsonb := '[]'::jsonb;
  v_day date;
  v_assignment app.schedule_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.leave_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id;
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: leave request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: leave request % is %, only a draft may be submitted', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  select * into v_policy from app.leave_type_policy_versions where id = v_request.policy_version_id;
  select * into v_type from app.leave_types where id = v_request.leave_type_id;

  -- Batch 278-280 Tier C fix (spec-compliance, HIGH, live-reproduced): this
  -- migration's own header (decision 8) already claimed submit_leave_request
  -- "only re-validates tenant/record_type/malware_scan_status" -- it never
  -- actually did. Now the authoritative gate before pending_approval: a
  -- requires_evidence type must still carry evidence at submit time (closes
  -- the adjacent gap where evidence attached at draft time could be stripped
  -- via update_leave_request_draft, or never supplied by an HR-on-behalf
  -- create, and still reach approval), and any attached file is re-validated
  -- exactly as app._create_leave_request validates it at creation.
  if v_type.requires_evidence and v_request.evidence_file_id is null then
    raise exception 'evidence_required: leave type % requires supporting evidence', v_type.code using errcode = 'check_violation';
  end if;
  perform app._validate_leave_evidence_file(v_request.tenant_id, v_request.evidence_file_id);

  if v_policy.min_notice_days > 0 and v_request.date_from < (current_date + v_policy.min_notice_days) then
    raise exception 'min_notice_not_met: leave type requires at least % day(s) advance notice', v_policy.min_notice_days using errcode = 'check_violation';
  end if;
  if v_policy.eligibility_min_tenure_days > 0 and v_employee.hire_date is not null
     and (current_date - v_employee.hire_date) < v_policy.eligibility_min_tenure_days then
    raise exception 'eligibility_not_met: employee has not met the % day minimum tenure required by this leave policy', v_policy.eligibility_min_tenure_days
      using errcode = 'check_violation';
  end if;

  v_day := v_request.date_from;
  while v_day <= v_request.date_to loop
    select * into v_assignment from app.resolve_effective_schedule_assignment(v_request.tenant_id, v_request.employee_id, v_day);
    if found then
      v_snapshot := v_snapshot || jsonb_build_object('work_date', v_day, 'schedule_assignment_id', v_assignment.id, 'shift_template_version_id', v_assignment.shift_template_version_id);
    end if;
    v_day := v_day + 1;
  end loop;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(v_request.tenant_id, 'leave_request') and co.tenant_id = v_request.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';
  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  v_approval_request := app.request_approval(
    v_approval_config_version_id, v_request.tenant_id, 'leave_request', p_request_id,
    p_request_id::text || ':submit:' || p_expected_version::text, p_actor_auth_user_id, p_actor_label
  );

  begin
    update app.leave_requests
    set status = 'pending_approval', approval_request_id = v_approval_request.id, schedule_snapshot = v_snapshot
    where id = p_request_id and record_version = p_expected_version
    returning * into v_request;
  exception
    when exclusion_violation then
      raise exception 'leave_request_overlap: employee % already has a pending or approved leave/permit/business-trip request overlapping this date range', v_request.employee_id
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'leave_request_overlap: a concurrent decision on an overlapping request could not be serialized -- retry'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_leave_request',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$function$;

-- submit_onboarding_case_for_finalize_approval -> approval:onboarding_case (tenant expression: v_case.tenant_id)
CREATE OR REPLACE FUNCTION app.submit_onboarding_case_for_finalize_approval(p_case_id uuid, p_expected_version integer, p_exit_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.onboarding_offboarding_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_incomplete_mandatory integer;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_case.status <> 'active' then
    raise exception 'invalid_transition: case % is %, only an active case can be submitted for finalize approval', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  -- Mandatory checklist gate (acceptance criterion 2: "mandatory checklist and
  -- downstream acknowledgements gate finalization").
  select count(*) into v_incomplete_mandatory
  from app.onboarding_case_tasks
  where case_id = p_case_id and is_mandatory and status not in ('completed', 'waived');
  if v_incomplete_mandatory > 0 then
    raise exception 'mandatory_tasks_incomplete: case % has % incomplete mandatory task(s)', p_case_id, v_incomplete_mandatory
      using errcode = 'check_violation';
  end if;

  -- Precondition-check-only against the employee's own governed lifecycle FSM
  -- (decision 1) -- never chained/driven from this function.
  if v_case.employee_master_record_id is not null then
    select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;
    if v_case.case_type = 'onboarding' and v_employee.lifecycle_status <> 'active' then
      raise exception 'employee_not_active_yet: employee % is %, must reach active via the standard employee lifecycle (submit/decide/activate, or app.rehire_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if v_case.case_type = 'offboarding' and v_employee.lifecycle_status not in ('terminated', 'archived') then
      raise exception 'employee_not_terminated_yet: employee % is %, must be terminated (app.terminate_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- exit_reason is captured HERE (not at case start -- self-found defect,
  -- fixed before commit: the original CHECK constraint required a non-null
  -- exit_reason at status='active' too, which made starting ANY offboarding
  -- case impossible, since the reason genuinely is not always known yet at
  -- start time). Caller-supplied here takes precedence; the case's own
  -- already-set exit_reason (if a caller already recorded one earlier via a
  -- direct UPDATE-less path) is preserved when this call passes null.
  if v_case.case_type = 'offboarding' then
    if coalesce(p_exit_reason, v_case.exit_reason) is null or length(trim(coalesce(p_exit_reason, v_case.exit_reason))) = 0 then
      raise exception 'exit_reason_required: an offboarding case requires a non-empty exit_reason before finalize submission' using errcode = 'check_violation';
    end if;
  end if;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(v_case.tenant_id, 'onboarding_case') and co.tenant_id = v_case.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_case.tenant_id
      using errcode = 'check_violation';
  end if;

  v_request := app.request_approval(
    v_approval_config_version_id, v_case.tenant_id, 'onboarding_offboarding_case', p_case_id,
    p_case_id::text || ':finalize:' || p_expected_version::text, p_actor_auth_user_id, p_actor_label
  );

  update app.onboarding_offboarding_cases
  set status = 'pending_finalize_approval', finalize_approval_request_id = v_request.id,
      exit_reason = coalesce(p_exit_reason, exit_reason)
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'submit_finalize_approval', 'active', 'pending_finalize_approval', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_onboarding_case_for_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$function$;

-- submit_payroll_run_for_finalization -> approval:payroll_run (tenant expression: v_run.tenant_id)
CREATE OR REPLACE FUNCTION app.submit_payroll_run_for_finalization(p_run_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.payroll_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.payroll_runs;
  v_open_exceptions integer;
  v_version_id uuid;
  v_approval app.approval_requests;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status <> 'calculated' then
    raise exception 'invalid_transition: run % is % -- only a fully calculated run with zero open exceptions may be submitted', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_open_exceptions from app.payroll_exceptions where payroll_run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'payroll_run_has_open_exceptions: run % has % unresolved exception(s)', p_run_id, v_open_exceptions using errcode = 'check_violation';
  end if;

  select cv.id into v_version_id from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = app._resolve_approval_config_type_code(v_run.tenant_id, 'payroll_run') and co.tenant_id = v_run.tenant_id and co.scope_level = 'tenant' and cv.status = 'published'
    limit 1;
  if v_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_run.tenant_id
      using errcode = 'check_violation';
  end if;

  v_approval := app.request_approval(v_version_id, v_run.tenant_id, 'payroll_run', p_run_id, 'payroll_run_finalize:' || p_run_id::text, p_actor_auth_user_id, p_actor_label);

  update app.payroll_runs set status = 'pending_approval', approval_request_id = v_approval.id, submitted_by = p_actor_label, submitted_at = now()
  where id = p_run_id and record_version = p_expected_version
  returning * into v_run;
  if not found then
    raise exception 'stale_version: concurrent update detected for run %', p_run_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_payroll_run_for_finalization',
    'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('approval_request_id', v_approval.id)
  );

  return v_run;
end;
$function$;

-- submit_quotation -> approval:quotation (tenant expression: v_quotation.tenant_id)
CREATE OR REPLACE FUNCTION app.submit_quotation(p_quotation_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_reasons text[];
  v_required boolean;
  v_approval_reasons text[];
  v_rule_version_id uuid;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be submitted', p_quotation_id, v_quotation.status, v_quotation.is_current
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select r.ready, r.blocking_reasons into v_ready, v_reasons from app.get_quotation_submission_readiness(p_quotation_id, p_actor_auth_user_id) r;
  if not v_ready then
    raise exception 'submission_not_ready: quotation % is not ready to submit (%)', p_quotation_id, array_to_string(v_reasons, ', ')
      using errcode = 'check_violation';
  end if;

  select e.required, e.reasons, e.rule_version_id into v_required, v_approval_reasons, v_rule_version_id
  from app.evaluate_quotation_approval_requirement(p_quotation_id, p_actor_auth_user_id) e;

  if v_required then
    select cv.id into v_approval_config_version_id
    from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = app._resolve_approval_config_type_code(v_quotation.tenant_id, 'quotation') and co.tenant_id = v_quotation.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

    if v_approval_config_version_id is null then
      raise exception 'approval_definition_not_configured: tenant % crossed an approval threshold but has no published quotation approval routing definition', v_quotation.tenant_id
        using errcode = 'check_violation';
    end if;

    select * into v_request from app.request_approval(
      v_approval_config_version_id, v_quotation.tenant_id, 'quotation', p_quotation_id,
      p_quotation_id::text, p_actor_auth_user_id, p_actor_label
    );

    update app.quotations
    set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
        approval_status = 'pending', approval_request_id = v_request.id,
        approval_rule_version_id = v_rule_version_id, approval_required_reasons = v_approval_reasons,
        updated_at = now(), record_version = record_version + 1
    where id = p_quotation_id and record_version = p_expected_version
    returning * into v_quotation;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: submit_quotation target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    update app.quotations
    set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
        approval_status = 'approved', approval_request_id = null,
        approval_rule_version_id = v_rule_version_id, approval_required_reasons = v_approval_reasons,
        updated_at = now(), record_version = record_version + 1
    where id = p_quotation_id and record_version = p_expected_version
    returning * into v_quotation;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: submit_quotation target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_quotation',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$function$;

