-- CG-S10-ATW-032 (post-Prompt-248 audit) — closes `ISS-2026-032`.
--
-- `ISS-2026-017` was closed at `ATW-031` by wiring `app.assert_actor_is_session_identity`
-- into `app.evaluate_permission` — one auditable choke point covering the 416 functions
-- that route their authority decision through it. That entry left a residual, opened as
-- `ISS-2026-032`: the functions that take `p_actor_auth_user_id` but never reach
-- `evaluate_permission`. It also prescribed the correct next step — "a classification
-- pass, not a blanket edit" — and estimated the residual at ~315 functions.
--
-- ===========================================================================
-- The classification pass
-- ===========================================================================
--
-- Run against the live post-migration catalogue, not by reading files:
--
--   * 761 functions in schema `app` take a `p_actor_auth_user_id` parameter.
--   * 566 of them reach `app.evaluate_permission` or `app.assert_actor_is_session_identity`
--     through the TRANSITIVE call graph (closure over `pg_get_functiondef` bodies), so
--     `ATW-031` already covers them.
--   * 195 do not. Of those, 119 hold no EXECUTE grant for `authenticated` at all
--     (`has_function_privilege`), so no client session can call them — bucket (b),
--     internal helpers, nothing to do.
--   * 76 remain. 43 of those are `STABLE`/`IMMUTABLE` — pure reads that perform no side
--     effect, where a forged actor changes nothing a caller could not already read.
--   * **33 are `VOLATILE`, granted to `authenticated`, and reach no actor check.** That is
--     bucket (a), the one `ISS-2026-032` says needs the assertion, and it is what this
--     migration fixes — 33 targeted edits rather than the ~315 blanket ones the issue
--     warned would be "~315 chances to get one wrong".
--
-- ===========================================================================
-- Why an authority check is not an identity check
-- ===========================================================================
--
-- Every one of the 33 already validates authority. The gap is that each asks "is the
-- CLAIMED actor allowed to do this?" and none asks "is the caller actually that actor?".
-- `app.approve_rate_version` is the clearest case: it gates on
-- `app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id)`, so any
-- authenticated session that knows a tenant_admin's UUID could pass it and approve a
-- vendor rate version as them. `app.mark_notification_read` compares
-- `recipient_auth_user_id <> p_actor_auth_user_id` — same shape, same hole.
--
-- ===========================================================================
-- Safety
-- ===========================================================================
--
-- `app.assert_actor_is_session_identity` is a no-op whenever `auth.uid()` is NULL, which
-- by construction covers `service_role`, superuser, the GPS gateway's ingest client and
-- every db-test. It engages only for a genuine `authenticated` session.
--
-- Nested calls were checked individually rather than assumed: five of the 33 are also
-- called by other `app` functions (`claim_finance_idempotency_key`,
-- `complete_finance_idempotency_claim` and `create_and_post_finance_system_journal` from
-- the Finance journal/subledger paths, `enqueue_job` from five enqueue wrappers, and
-- `transition_lead_status` from `qualify_lead`/`disqualify_lead`). Every one of those call
-- sites threads `p_actor_auth_user_id` straight through — none substitutes a system or
-- record-owner identity — so the assertion cannot fire on a legitimate nested call.
-- `auth.uid()` reads a request GUC and is unchanged by `SECURITY DEFINER` nesting, so an
-- inner call sees exactly what the outer one saw.
--
-- Each body below is this checkpoint's `pg_get_functiondef` output with one `perform`
-- inserted as the first statement after `begin` — no other logic is touched, and no
-- already-applied migration file is edited.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

CREATE OR REPLACE FUNCTION app.approve_rate_version(p_rate_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be approved', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.archive_prospect(p_prospect_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.prospects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_prospect app.prospects;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be archived', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'archived', archived_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, null
  );

  return v_prospect;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_activity(p_activity_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.activities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_activity app.activities;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be cancelled', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set status = 'cancelled', updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_activity',
    'app.activities', v_activity.id, 'success', null, null, null
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_request_fingerprint is null or length(trim(p_request_fingerprint)) = 0 then
    raise exception 'finance_idempotency_fingerprint_required: a non-empty request_fingerprint is required' using errcode = 'check_violation';
  end if;

  insert into app.finance_idempotency_claims (tenant_id, scope, idempotency_key, request_fingerprint, claimed_by)
  values (p_tenant_id, p_scope, p_idempotency_key, p_request_fingerprint, p_actor_label)
  on conflict (tenant_id, scope, idempotency_key) do nothing
  returning * into v_claim;

  if found then
    return v_claim;
  end if;

  select * into v_claim from app.finance_idempotency_claims where tenant_id = p_tenant_id and scope = p_scope and idempotency_key = p_idempotency_key;

  if v_claim.request_fingerprint <> p_request_fingerprint then
    raise exception 'finance_idempotency_fingerprint_conflict: idempotency key % (scope %) was already used with a different request', p_idempotency_key, p_scope
      using errcode = 'unique_violation';
  end if;

  return v_claim;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.complete_activity(p_activity_id uuid, p_expected_version integer, p_outcome text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.activities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_activity app.activities;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be completed', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set status = 'completed', completed_at = now(), outcome = p_outcome, updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('outcome', p_outcome)
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    return v_claim;
  end if;

  update app.finance_idempotency_claims
    set status = 'completed', result_entity_type = p_result_entity_type, result_entity_id = p_result_entity_id, completed_at = now()
    where id = p_claim_id
    returning * into v_claim;

  return v_claim;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text DEFAULT 'gl'::text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
AS $function$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_line_number integer := 0;
  v_total numeric(14, 2);
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_source_type not in ('subledger', 'correction') then
    raise exception 'finance_journal_unsupported_source_type: % is not a supported system journal source type', p_source_type
      using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', p_journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, p_journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, p_lock_scope);

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  insert into app.finance_journals (
    tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
    currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
  )
  values (
    p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension', v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_and_post_finance_system_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_rate_version(p_tenant_id uuid, p_vendor_code text, p_vendor_name text, p_service_type text, p_mode text, p_origin_lane text, p_destination_lane text, p_equipment_type text, p_cargo_weight_min numeric, p_cargo_weight_max numeric, p_cargo_volume_min numeric, p_cargo_volume_max numeric, p_currency text, p_base_amount numeric, p_minimum_amount numeric, p_surcharge_components jsonb, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_master_record_id uuid;
  v_prior app.vendor_rate_versions;
  v_new app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_prior from app.vendor_rate_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_prior.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_supersedes_version_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
    if v_prior.approval_status not in ('pending_approval', 'approved') then
      raise exception 'invalid_transition: rate version % is % and cannot be superseded', p_supersedes_version_id, v_prior.approval_status
        using errcode = 'check_violation';
    end if;
    -- A revision stays under the same vendor/lane identity as its source -- the master
    -- record is never re-resolved from p_vendor_code/p_vendor_name on this branch.
    v_master_record_id := v_prior.master_record_id;
  else
    -- Idempotent get-or-create of the vendor/lane identity row (PLT-120) -- a repeated
    -- call with the same code returns the existing master record, never a duplicate.
    select id into v_master_record_id from app.create_master_record(
      'vendor_rate', p_tenant_id, p_vendor_code, p_vendor_name, '[]'::jsonb, '{}'::jsonb, p_actor_auth_user_id, p_actor_label
    );
  end if;

  insert into app.vendor_rate_versions (
    tenant_id, master_record_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
    currency, base_amount, minimum_amount, surcharge_components,
    effective_from, effective_to, supersedes_version_id, created_by
  ) values (
    p_tenant_id, v_master_record_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_cargo_weight_min, p_cargo_weight_max, p_cargo_volume_min, p_cargo_volume_max,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_surcharge_components, '[]'::jsonb),
    coalesce(p_effective_from, now()), p_effective_to, p_supersedes_version_id, p_actor_label
  )
  returning * into v_new;

  if p_supersedes_version_id is not null then
    update app.vendor_rate_versions
    set approval_status = 'superseded', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_rate_version',
    'app.vendor_rate_versions', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.decide_credit_profile_approval_step(p_request_step_id uuid, p_decision text, p_reason text, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_profile app.credit_profiles;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'credit_profile' or v_request.entity_id is null then
    raise exception 'not_a_credit_profile_approval: approval request % is not a credit profile approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.credit_profiles
    set status = 'active', approved_limit_amount = requested_limit_amount, approved_by = p_actor_label, approved_at = now(),
        effective_from = now(), updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_profile;
  elsif v_updated_request.status = 'rejected' then
    update app.credit_profiles
    set status = 'rejected', rejected_reason = coalesce(p_reason, 'Rejected'), updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_profile;
  else
    select * into v_profile from app.credit_profiles where id = v_request.entity_id;
  end if;

  return v_profile;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.decide_quotation_approval_step(p_request_step_id uuid, p_decision text, p_actor_auth_user_id uuid, p_actor_label text, p_reason text DEFAULT NULL::text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_quotation app.quotations;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'quotation' or v_request.entity_id is null then
    raise exception 'not_a_quotation_approval: approval request % is not a quotation approval', v_request.id
      using errcode = 'check_violation';
  end if;

  -- The real decision, eligibility/self-approval/idempotency checks and all -- never
  -- re-implemented here (this migration's own header).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.quotations set approval_status = 'approved', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_quotation;
  elsif v_updated_request.status = 'rejected' then
    update app.quotations set approval_status = 'rejected', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_quotation;
  else
    -- Still pending (a sequential/threshold pattern with steps remaining) -- no sync needed.
    select * into v_quotation from app.quotations where id = v_request.entity_id;
  end if;

  return v_quotation;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.disqualify_lead(p_lead_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: disqualifying a lead requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  return app.transition_lead_status(
    p_lead_id, p_expected_version, 'disqualified',
    array['new', 'contacted', 'qualified'], p_reason, p_actor_auth_user_id, p_actor_label, 'disqualify_lead'
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION app.disqualify_prospect(p_prospect_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.prospects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_prospect app.prospects;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: disqualifying a prospect requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be disqualified', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'disqualified', disqualify_reason = p_reason, disqualified_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'disqualify_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_prospect;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.export_customer_inventory_snapshot(p_tenant_id uuid, p_actor_auth_user_id uuid, p_warehouse_id uuid DEFAULT NULL::uuid, p_item_master_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 500, p_actor_label text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, warehouse_id uuid, owner_account_id uuid, item_master_id uuid, location_id uuid, lot_number text, serial_number text, status text, on_hand numeric, reserved numeric, held numeric, available numeric, record_version integer, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scope uuid[];
  v_limit integer;
  v_matched_count integer;
  v_result_count integer;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 500), 1), 1000);

  select count(*) into v_matched_count
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id);
  v_result_count := least(v_matched_count, v_limit);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'export_customer_inventory_snapshot',
    'app.inventory_balances', null, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'item_master_id', p_item_master_id, 'limit', v_limit, 'result_count', v_result_count)
  );

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    raise exception 'finance_idempotency_claim_already_completed: claim % already completed, cannot mark failed', p_claim_id
      using errcode = 'check_violation';
  end if;

  update app.finance_idempotency_claims set status = 'failed', error_message = p_error_message where id = p_claim_id returning * into v_claim;

  return v_claim;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_transaction_lineage(p_job_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_handoff app.job_order_handoffs;
  v_shipment record;
  v_epod app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_milestone app.shipment_milestone_projections;
  v_profitability app.job_profitability_snapshots;
  v_billing app.billing_readiness_evaluations;
  v_shipments jsonb := '[]'::jsonb;
  v_accessible_shipment_ids uuid[] := '{}';
  v_edges jsonb;
  v_manifest jsonb;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_handoff from app.job_order_handoffs where id = v_job.source_handoff_id;

  for v_shipment in select * from app.shipment_orders where job_order_id = p_job_order_id order by created_at loop
    if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      continue;
    end if;

    v_accessible_shipment_ids := v_accessible_shipment_ids || v_shipment.id;

    select * into v_epod from app.epod_captures where shipment_order_id = v_shipment.id and is_latest_version;
    select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment.id and is_current;
    select * into v_milestone from app.shipment_milestone_projections where shipment_order_id = v_shipment.id;

    v_shipments := v_shipments || jsonb_build_object(
      'shipmentOrderId', v_shipment.id,
      'shipmentNumber', v_shipment.shipment_number,
      'status', v_shipment.status,
      'milestone', case when v_milestone.shipment_order_id is not null then jsonb_build_object(
        'lastMilestoneCode', v_milestone.last_milestone_code,
        'isDelayed', v_milestone.is_delayed,
        'currentEta', v_milestone.current_eta
      ) else null end,
      'epod', case when v_epod.id is not null then jsonb_build_object(
        'epodCaptureId', v_epod.id, 'status', v_epod.status, 'versionNumber', v_epod.version_number
      ) else null end,
      'actualCost', case when v_cost.id is not null then jsonb_build_object(
        'shipmentActualCostId', v_cost.id, 'status', v_cost.status, 'versionNumber', v_cost.version_number
      ) else null end
    );
  end loop;

  select * into v_profitability from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  select * into v_billing from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'relationType', e.relation_type, 'sourceType', e.source_type, 'sourceId', e.source_id,
    'targetType', e.target_type, 'targetId', e.target_id, 'sourceVersionHash', e.source_version_hash,
    'isOverride', e.is_override, 'overrideReason', e.override_reason, 'createdAt', e.created_at
  ) order by e.created_at), '[]'::jsonb)
  into v_edges
  from app.transaction_lineage_edges e
  where e.tenant_id = v_job.tenant_id
    and (
      (e.relation_type in ('quote_to_job', 'job_to_profitability', 'job_to_billing_readiness') and (e.source_id = p_job_order_id or e.target_id = p_job_order_id))
      or (e.relation_type = 'job_to_shipment' and e.source_id = p_job_order_id and e.target_id = any (v_accessible_shipment_ids))
      or (e.relation_type in ('shipment_to_epod', 'shipment_to_cost') and e.source_id = any (v_accessible_shipment_ids))
    );

  v_manifest := jsonb_build_object(
    'jobOrderId', v_job.id,
    'jobNumber', v_job.job_number,
    'sourceHandoffId', v_job.source_handoff_id,
    'sourceQuotationId', case when v_handoff.id is not null then v_handoff.quotation_id else null end,
    'sourcePayloadHash', case when v_handoff.id is not null then v_handoff.payload_hash else null end,
    'shipments', v_shipments,
    'profitability', case when v_profitability.id is not null then jsonb_build_object(
      'jobProfitabilitySnapshotId', v_profitability.id, 'status', v_profitability.status, 'versionNumber', v_profitability.version_number
    ) else null end,
    'billingReadiness', case when v_billing.id is not null then jsonb_build_object(
      'billingReadinessEvaluationId', v_billing.id, 'effectiveStatus', v_billing.effective_status, 'versionNumber', v_billing.version_number
    ) else null end,
    'edges', v_edges
  );

  return v_manifest;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.link_lead_to_existing_prospect(p_lead_id uuid, p_prospect_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.prospects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
  v_prospect app.prospects;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_lead.tenant_id <> v_prospect.tenant_id then
    raise exception 'cross_tenant_link_denied: lead and prospect belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_lead.status <> 'qualified' then
    raise exception 'invalid_transition: lead % is % and cannot link to a prospect (must be qualified)', p_lead_id, v_lead.status
      using errcode = 'check_violation';
  end if;

  if v_prospect.status = 'merged' then
    raise exception 'invalid_link: prospect % is merged and cannot accept a new lead link', p_prospect_id
      using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id, app.lead_record_scope_org_unit_ids(v_lead.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both the lead and the prospect', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = 'converted', converted_at = now(), converted_prospect_id = v_prospect.id, last_activity_at = now(), record_version = record_version + 1
  where id = p_lead_id;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_lead_to_existing_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('lead_id', p_lead_id)
  );

  return v_prospect;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_api_keys_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text, rate_limit_per_minute integer, expires_at timestamp with time zone, last_used_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view API keys for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select k.id, k.tenant_id, k.name, k.key_prefix, k.scopes, k.status, k.rate_limit_per_minute, k.expires_at, k.last_used_at, k.created_at, k.updated_at
  from app.api_keys k
  where k.tenant_id = p_tenant_id
  order by k.created_at desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_webhook_endpoints_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(id uuid, tenant_id uuid, url text, status text, consecutive_failure_count integer, auto_disabled_at timestamp with time zone, disabled_reason text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view webhook endpoints for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.id, e.tenant_id, e.url, e.status, e.consecutive_failure_count, e.auto_disabled_at, e.disabled_reason, e.created_at, e.updated_at
  from app.webhook_endpoints e
  where e.tenant_id = p_tenant_id
  order by e.created_at desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.mark_notification_read(p_notification_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.notifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_notification app.notifications;
  v_updated app.notifications;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_notification from app.notifications where id = p_notification_id;
  if not found then
    raise exception 'notification_not_found: no notification %', p_notification_id
      using errcode = 'no_data_found';
  end if;
  if p_actor_auth_user_id <> v_notification.recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not mark another identity''s notification read', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.notifications set read_at = coalesce(read_at, now()) where id = p_notification_id returning * into v_updated;

  perform app.capture_audit_event(
    v_notification.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_notification_read',
    'app.notifications', v_updated.id, 'success', null, to_jsonb(v_notification), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.merge_leads(p_survivor_lead_id uuid, p_duplicate_lead_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_survivor app.leads;
  v_duplicate app.leads;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_survivor_lead_id = p_duplicate_lead_id then
    raise exception 'invalid_merge: a lead cannot be merged into itself' using errcode = 'check_violation';
  end if;

  select * into v_survivor from app.leads where id = p_survivor_lead_id;
  select * into v_duplicate from app.leads where id = p_duplicate_lead_id;
  if v_survivor.id is null or v_duplicate.id is null then
    raise exception 'lead_not_found: survivor % or duplicate %', p_survivor_lead_id, p_duplicate_lead_id
      using errcode = 'no_data_found';
  end if;

  if v_survivor.tenant_id <> v_duplicate.tenant_id then
    raise exception 'cross_tenant_merge_denied: survivor and duplicate belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_duplicate.status = 'merged' then
    raise exception 'invalid_merge: lead % is already merged', p_duplicate_lead_id using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_survivor.tenant_id, v_survivor.owner_user_id,
      app.lead_record_scope_org_unit_ids(v_survivor.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_duplicate.tenant_id, v_duplicate.owner_user_id,
      app.lead_record_scope_org_unit_ids(v_duplicate.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both leads being merged', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = 'merged', merged_into_id = p_survivor_lead_id, merged_at = now(), merged_by = p_actor_label,
      last_activity_at = now(), record_version = record_version + 1
  where id = p_duplicate_lead_id
  returning * into v_duplicate;

  update app.leads set last_activity_at = now() where id = p_survivor_lead_id returning * into v_survivor;

  perform app.capture_audit_event(
    v_survivor.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_leads',
    'app.leads', v_duplicate.id, 'success', null, null,
    jsonb_build_object('survivor_lead_id', p_survivor_lead_id, 'duplicate_lead_id', p_duplicate_lead_id)
  );

  return v_survivor;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.merge_prospects(p_survivor_prospect_id uuid, p_duplicate_prospect_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.prospects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_survivor app.prospects;
  v_duplicate app.prospects;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_survivor_prospect_id = p_duplicate_prospect_id then
    raise exception 'invalid_merge: a prospect cannot be merged into itself' using errcode = 'check_violation';
  end if;

  select * into v_survivor from app.prospects where id = p_survivor_prospect_id;
  select * into v_duplicate from app.prospects where id = p_duplicate_prospect_id;
  if v_survivor.id is null or v_duplicate.id is null then
    raise exception 'prospect_not_found: survivor % or duplicate %', p_survivor_prospect_id, p_duplicate_prospect_id
      using errcode = 'no_data_found';
  end if;

  if v_survivor.tenant_id <> v_duplicate.tenant_id then
    raise exception 'cross_tenant_merge_denied: survivor and duplicate belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_duplicate.status = 'merged' then
    raise exception 'invalid_merge: prospect % is already merged', p_duplicate_prospect_id using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_survivor.tenant_id, v_survivor.owner_user_id, app.lead_record_scope_org_unit_ids(v_survivor.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_duplicate.tenant_id, v_duplicate.owner_user_id, app.lead_record_scope_org_unit_ids(v_duplicate.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both prospects being merged', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'merged', merged_into_id = p_survivor_prospect_id, merged_at = now(), merged_by = p_actor_label, updated_at = now(), record_version = record_version + 1
  where id = p_duplicate_prospect_id
  returning * into v_duplicate;

  update app.prospects set updated_at = now() where id = p_survivor_prospect_id returning * into v_survivor;

  perform app.capture_audit_event(
    v_survivor.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_prospects',
    'app.prospects', v_duplicate.id, 'success', null, null,
    jsonb_build_object('survivor_prospect_id', p_survivor_prospect_id, 'duplicate_prospect_id', p_duplicate_prospect_id)
  );

  return v_survivor;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.preview_import_job(p_job_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(total_rows integer, valid_rows integer, invalid_rows integer, pending_rows integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.jobs;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not (v_job.requested_by_auth_user_id = p_actor_auth_user_id or app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id)) then
    raise exception 'job_actor_unauthorized: identity % may not preview job %', p_actor_auth_user_id, p_job_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    coalesce(v_job.total_rows, 0),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'valid'),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'invalid'),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'pending');
end;
$function$
;

CREATE OR REPLACE FUNCTION app.qualify_lead(p_lead_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  return app.transition_lead_status(
    p_lead_id, p_expected_version, 'qualified',
    array['new', 'contacted'], null, p_actor_auth_user_id, p_actor_label, 'qualify_lead'
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_customer_inventory_access_denial(p_tenant_id uuid, p_actor_auth_user_id uuid, p_resource_type text, p_resource_id uuid, p_actor_label text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- ATW-032 (ISS-2026-033): A WRITE: it inserts an audit record. Ungated, any logged-in user could forge denial
  -- audit entries into any other tenant's audit trail.
  -- The guard reads auth.uid() directly, so no signature or caller changes, and it is a
  -- no-op for service_role/superuser/db-tests/nested definer calls.
  perform app.assert_session_identity_in_tenant(p_tenant_id);
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'customer_inventory_access_denied',
    p_resource_type, p_resource_id, 'failure', null, null, null
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_report_run(p_tenant_id uuid, p_report_type_code text, p_parameters jsonb, p_row_count integer, p_masked_columns text[], p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.report_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_type app.report_types;
  v_run app.report_runs;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and can no longer be run', p_report_type_code using errcode = 'check_violation';
  end if;

  if not (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_row_count, 0) < 0 then
    raise exception 'report_invalid_row_count: row_count must not be negative' using errcode = 'check_violation';
  end if;

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, row_count, masked_columns,
    requested_by_auth_user_id, created_by, completed_at
  ) values (
    p_tenant_id, p_report_type_code, 'preview', 'completed', coalesce(p_parameters, '{}'::jsonb), p_row_count, coalesce(p_masked_columns, '{}'),
    p_actor_auth_user_id, p_actor_label, now()
  )
  returning * into v_run;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_report_run',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'run_type', 'preview', 'row_count', p_row_count)
  );

  return v_run;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.register_report_type(p_code text, p_name text, p_description text, p_source_function text, p_actor_auth_user_id uuid, p_registered_by text)
 RETURNS app.report_types
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_existing app.report_types;
  v_type app.report_types;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a report type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.report_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.report_types (code, name, description, source_function, registered_by)
  values (p_code, p_name, p_description, p_source_function, p_registered_by)
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_report_type',
    'app.report_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reject_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: rejecting a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be rejected', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'rejected', rejected_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reschedule_activity(p_activity_id uuid, p_expected_version integer, p_new_due_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.activities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_activity app.activities;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be rescheduled', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set due_at = p_new_due_at, updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('new_due_at', p_new_due_at)
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.retire_report_type(p_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.report_types
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_type app.report_types;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may retire a report type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.report_types where code = p_code;
  if not found then
    raise exception 'report_type_unknown: %', p_code using errcode = 'no_data_found';
  end if;

  update app.report_types set status = 'retired' where code = p_code
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'retire_report_type',
    'app.report_types', null, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_type;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.score_lead(p_lead_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
  v_scored record;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_scored from app.compute_lead_score(v_lead);

  update app.leads
  set score = v_scored.score, score_explanation = v_scored.explanation, last_activity_at = now()
  where id = p_lead_id
  returning * into v_lead;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, null, 'score_lead',
    'app.leads', v_lead.id, 'success', null, null, jsonb_build_object('score', v_lead.score, 'score_version', v_lead.score_version)
  );

  return v_lead;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.transition_lead_status(p_lead_id uuid, p_expected_version integer, p_new_status text, p_allowed_from_statuses text[], p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_action_name text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if v_lead.record_version <> p_expected_version then
    raise exception 'stale_version: lead % expected version % but found %', p_lead_id, p_expected_version, v_lead.record_version
      using errcode = 'serialization_failure';
  end if;

  if not (v_lead.status = any(p_allowed_from_statuses)) then
    raise exception 'invalid_transition: lead % is % and cannot become %', p_lead_id, v_lead.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = p_new_status,
      disqualify_reason = case when p_new_status = 'disqualified' then p_reason else disqualify_reason end,
      qualified_at = case when p_new_status = 'qualified' then now() else qualified_at end,
      disqualified_at = case when p_new_status = 'disqualified' then now() else disqualified_at end,
      last_activity_at = now(),
      record_version = record_version + 1
  where id = p_lead_id and record_version = p_expected_version
  returning * into v_lead;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, p_action_name,
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_status', p_new_status, 'reason', p_reason)
  );

  return v_lead;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.withdraw_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'approved' then
    raise exception 'invalid_transition: rate version % is % and only an approved rate can be withdrawn', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'withdrawn', withdrawn_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

revoke execute on all functions in schema app from public;

grant execute on function app.approve_rate_version(p_rate_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.archive_prospect(p_prospect_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.cancel_activity(p_activity_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.complete_activity(p_activity_id uuid, p_expected_version integer, p_outcome text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text) to authenticated, service_role;
grant execute on function app.create_rate_version(p_tenant_id uuid, p_vendor_code text, p_vendor_name text, p_service_type text, p_mode text, p_origin_lane text, p_destination_lane text, p_equipment_type text, p_cargo_weight_min numeric, p_cargo_weight_max numeric, p_cargo_volume_min numeric, p_cargo_volume_max numeric, p_currency text, p_base_amount numeric, p_minimum_amount numeric, p_surcharge_components jsonb, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.decide_credit_profile_approval_step(p_request_step_id uuid, p_decision text, p_reason text, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.decide_quotation_approval_step(p_request_step_id uuid, p_decision text, p_actor_auth_user_id uuid, p_actor_label text, p_reason text) to authenticated, service_role;
grant execute on function app.disqualify_lead(p_lead_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.disqualify_prospect(p_prospect_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.export_customer_inventory_snapshot(p_tenant_id uuid, p_actor_auth_user_id uuid, p_warehouse_id uuid, p_item_master_id uuid, p_limit integer, p_actor_label text) to authenticated, service_role;
grant execute on function app.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.get_transaction_lineage(p_job_order_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.link_lead_to_existing_prospect(p_lead_id uuid, p_prospect_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.list_api_keys_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.list_webhook_endpoints_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.mark_notification_read(p_notification_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.merge_leads(p_survivor_lead_id uuid, p_duplicate_lead_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.merge_prospects(p_survivor_prospect_id uuid, p_duplicate_prospect_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.preview_import_job(p_job_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.qualify_lead(p_lead_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.record_customer_inventory_access_denial(p_tenant_id uuid, p_actor_auth_user_id uuid, p_resource_type text, p_resource_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.record_report_run(p_tenant_id uuid, p_report_type_code text, p_parameters jsonb, p_row_count integer, p_masked_columns text[], p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.register_report_type(p_code text, p_name text, p_description text, p_source_function text, p_actor_auth_user_id uuid, p_registered_by text) to authenticated, service_role;
grant execute on function app.reject_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.reschedule_activity(p_activity_id uuid, p_expected_version integer, p_new_due_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.retire_report_type(p_code text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
grant execute on function app.score_lead(p_lead_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.transition_lead_status(p_lead_id uuid, p_expected_version integer, p_new_status text, p_allowed_from_statuses text[], p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_action_name text) to authenticated, service_role;
grant execute on function app.withdraw_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
