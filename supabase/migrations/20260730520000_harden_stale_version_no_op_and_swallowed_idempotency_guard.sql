-- CG-S10-ATW-032 (post-Prompt-248 audit) — the silent-no-op half of the optimistic-
-- concurrency class, and the two idempotency guards this same audit had already written
-- but which its own exception handlers were swallowing.
--
-- ===========================================================================
-- 1. A version-predicated UPDATE that matches nothing must SAY so
-- ===========================================================================
--
-- `20260730480000` fixed the 64 functions that took `p_expected_version` and had NEITHER a
-- row lock NOR the version predicate on their own UPDATE — those were genuine lost updates.
-- Its header named the residual it deliberately did not take on: "the version predicate
-- alone would still need every one of the ... call sites to then handle the zero-rows-
-- updated case." This migration is that follow-up.
--
-- 74 functions carry `and record_version = p_expected_version` on their UPDATE, so the
-- write itself is safe — the loser matches no row and overwrites nothing. But none of them
-- checked whether the UPDATE had actually applied. Execution fell straight through with an
-- unset composite, and three things followed, all silent:
--
--   * `app.capture_audit_event(v_row.tenant_id, ...)` ran with a NULL tenant_id and wrote a
--     `success` row for a mutation that never happened — a fabricated audit record, on the
--     evidence trail, for the exact concurrency case an auditor would go looking for.
--   * The function returned an all-NULL composite. The TypeScript layer's own guard is
--     `if (!data || typeof data !== "object")`, and a composite of NULLs is an object, so the
--     caller got a raw ZodError or `invalid_response` — never the `stale_version` that is
--     already a first-class member of every domain's KNOWN_MUTATION_ERROR_CODES.
--   * Anything the function had already written in the same transaction before the UPDATE
--     — a history row, a transition record — committed anyway, describing a state change
--     that never took effect.
--
-- The repair is one `if not found then raise 'stale_version' ... end if` immediately after
-- each such UPDATE. It changes no successful path: on a winning call the UPDATE matches its
-- row and `found` is true. It converts the losing path from a silent fabrication into the
-- error the client already knows how to retry.
--
-- ===========================================================================
-- 2. Two idempotency guards that could never fire
-- ===========================================================================
--
-- `ATW-030`/`ATW-031` added idempotency target-mismatch guards to 55 functions, each raising
-- `idempotency_key_conflict` with `errcode = 'unique_violation'`. That is exactly the
-- condition an `exception when unique_violation` handler traps — so wherever such a guard
-- sits inside a block that has one, PL/pgSQL catches the guard's own raise and the handler
-- returns the mismatched row anyway. The guard is inert and the misattribution it was
-- written to stop still happens.
--
-- All 55 were swept structurally — block nesting parsed rather than grepped, because a
-- `raise exception` line contains the word "exception" and a naive scan mistakes it for a
-- block's exception SECTION (that mistake is what hid this in the first place). Two
-- functions have a guard lexically inside a handled block:
--
--   * `app.start_wms_receipt_session` — **already correct.** Its handler re-runs the
--     discriminator and re-raises, and an exception raised from inside a handler is not
--     re-caught by that handler, so the raise propagates. Left untouched.
--   * `app.ingest_milestone_event` — **genuinely inert.** Its handler re-selects by key and
--     returns immediately, with no re-check. A `DELIVERED` submission reusing an earlier
--     `DEPARTED_ORIGIN` key returned that earlier event with no error, the delivery was
--     silently discarded, and `app.recalculate_shipment_milestone_projection` never ran.
--
-- Only `ingest_milestone_event` is changed here, and it is changed the way its already-
-- correct sibling does it: re-apply the discriminator in the handler before returning.
--
-- Every body below is this checkpoint's `pg_get_functiondef` output with the stated block
-- inserted — no other logic is touched, and no already-applied migration file is edited.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

CREATE OR REPLACE FUNCTION app.acknowledge_exception(p_exception_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be acknowledged', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'acknowledged'
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: acknowledge_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
AS $function$
declare
  v_account app.finance_accounts;
  v_parent app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be activated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Approve', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if app.detect_finance_account_hierarchy_cycle(v_account.id, v_account.parent_account_id) then
    raise exception 'finance_account_hierarchy_cycle: activating account % would create or confirm a cyclic/over-deep hierarchy', p_account_id
      using errcode = 'check_violation';
  end if;

  if v_account.parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = v_account.parent_account_id;
    if v_parent.status = 'inactive' then
      raise exception 'finance_account_parent_inactive: parent account % is inactive', v_account.parent_account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.finance_accounts
  set status = 'active'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: activate_finance_account target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_finance_account',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
AS $function$
declare
  v_account app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be amended (use governed correction otherwise)', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Edit', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_accounts
  set name = coalesce(p_name, name), currency_restriction = p_currency_restriction
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: amend_finance_account_draft target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_finance_account_draft',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_overlap_count integer;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id for update;
  -- ATW-032: the overlapping-approved-window check below was an unlocked read with no
  -- exclusion constraint behind it, so two concurrent approvals for the same currency pair
  -- could both pass it and leave two overlapping approved rates -- after which every
  -- conversion for that pair depends on which row a query happens to pick. Locking the
  -- row being approved serialises approvals of the same rate.
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be approved', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Approve', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_overlap_count from app.finance_exchange_rates
    where id <> p_rate_id
      and status = 'approved'
      and coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rate.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rate_type = v_rate.rate_type
      and source_currency = v_rate.source_currency
      and target_currency = v_rate.target_currency
      and effective_from <= coalesce(v_rate.effective_to, 'infinity'::timestamptz)
      and coalesce(effective_to, 'infinity'::timestamptz) >= v_rate.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair'
      using errcode = 'check_violation';
  end if;

  update app.finance_exchange_rates
  set status = 'approved', approved_by = p_actor_label, approved_at = now()
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: approve_finance_exchange_rate target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_exchange_rate',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$
;

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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: approve_rate_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.approve_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed release-to-Finance decision -- OPS:Override.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'reviewed' then
    raise exception 'invalid_transition: billing event % is % -- only reviewed may be approved', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  -- Segregation of duties (mirrors ATW-020's own established self_approval_not_allowed
  -- pattern): the same identity that reviewed an event may not also approve it.
  if v_event.reviewed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % reviewed billing event % and may not also approve it', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  update app.warehouse_billing_events set
    status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by_label = p_actor_label, approved_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: approve_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: archive_prospect target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, null
  );

  return v_prospect;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.archive_sales_plan(p_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status = 'archived' then
    raise exception 'invalid_transition: sales plan % is already archived', p_plan_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.sales_plans
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: archive_sales_plan target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, null
  );

  return v_plan;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.assign_costing_request(p_request_id uuid, p_expected_version integer, p_assignee_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  select * into v_request from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be assigned', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set assignee_user_id = p_assignee_user_id,
      status = case when status = 'pending' then 'assigned' else status end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: assign_costing_request target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('assignee_user_id', p_assignee_user_id)
  );

  return v_request;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.assign_lead(p_lead_id uuid, p_expected_version integer, p_new_owner_user_id uuid, p_new_org_unit_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
  v_decision app.rbac_decision;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if v_lead.record_version <> p_expected_version then
    raise exception 'stale_version: lead % expected version % but found %', p_lead_id, p_expected_version, v_lead.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_lead.status = 'merged' then
    raise exception 'invalid_transition: lead % is merged and cannot be reassigned', p_lead_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lead.tenant_id, 'COM', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lead.tenant_id
      using errcode = 'insufficient_privilege';
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
  set owner_user_id = p_new_owner_user_id,
      org_unit_id = p_new_org_unit_id,
      assigned_at = now(),
      assigned_by = p_actor_label,
      last_activity_at = now(),
      record_version = record_version + 1
  where id = p_lead_id and record_version = p_expected_version
  returning * into v_lead;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: assign_lead target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_lead',
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_owner_user_id', p_new_owner_user_id, 'new_org_unit_id', p_new_org_unit_id)
  );

  return v_lead;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.calculate_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'draft' then
    raise exception 'already_calculated: billing event % is % -- use app.recalculate_warehouse_billing_event instead', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- as_of = the event's own activity_date, never now() (Prompt 241's own explicit rule).
  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: calculate_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null,
    jsonb_build_object('total_amount', v_event.total_amount, 'contract_id', v_event.contract_id, 'rate_component_id', v_event.rate_component_id)
  );

  return v_event;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_activity target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_activity',
    'app.activities', v_activity.id, 'success', null, null, null
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_costing_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: cancelling a costing request requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set status = 'cancelled', cancel_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_costing_request target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_request;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a scenario' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status in ('selected', 'cancelled') then
    raise exception 'scenario_not_mutable: scenario % is % and cannot be cancelled', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.route_planning_scenarios set status = 'cancelled' where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_scenario;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_shipment_leg(p_shipment_leg_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a leg' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and can only be cancelled while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs set leg_status = 'cancelled' where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_shipment_leg target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = v_leg.shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_leg;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a Shipment Order' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is already cancelled', p_shipment_order_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'cancelled'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.change_shipment_mode(p_shipment_order_id uuid, p_new_mode text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_new_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_new_mode using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'confirmed_mode_change_blocked: shipment order % is % -- mode may only change while draft', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_shipment.mode <> p_new_mode then
    delete from app.shipment_mode_profiles where shipment_order_id = p_shipment_order_id;
  end if;

  update app.shipment_orders
  set mode = p_new_mode
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: change_shipment_mode target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'change_shipment_mode',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('mode', p_new_mode)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.close_claim_case(p_case_id uuid, p_expected_version integer, p_exception_expected_version integer, p_closure_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_latest_handoff app.claim_settlement_readiness_handoffs;
  v_review app.claim_responsibility_reviews;
  v_closure_basis text;
  v_exception app.operational_exceptions;
  v_resolved app.operational_exceptions;
  v_updated app.claim_case_extensions;
begin
  if p_closure_note is null or length(trim(p_closure_note)) = 0 then
    raise exception 'claim_closure_note_required: a non-empty closure_note is required to close a claim case' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_already_closed: claim case % is already closed', p_case_id using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  -- Exact closure gate (disclosed precisely in the migration header, design point 8).
  -- Ordered by handoff_seq (a real identity column), never handed_off_at -- see
  -- app.claim_settlement_readiness_handoffs' own comment for why.
  select * into v_latest_handoff from app.claim_settlement_readiness_handoffs where claim_case_id = p_case_id order by handoff_seq desc limit 1;
  if found and v_latest_handoff.reconciliation_status = 'reconciled' then
    v_closure_basis := 'finance_reconciled';
  else
    select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
    if found and (v_review.status = 'denied' or (v_review.status in ('approved', 'amended') and coalesce(v_review.final_reserve_amount, 0) = 0)) then
      v_closure_basis := 'no_handoff_required';
    else
      raise exception 'claim_case_not_reconciled: claim case % is not yet finance-reconciled and does not qualify for the no-handoff-required closure path (a decided denial or a zero-reserve decision) -- hand off to Finance and obtain a reconciled outcome, or decide/deny the claim, before closing', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Drive the underlying app.operational_exceptions row through ITS OWN real
  -- resolve/close RPCs -- never a direct table write (see migration header).
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;
  if v_exception.status in ('open', 'acknowledged', 'reopened') then
    v_resolved := app.resolve_exception(v_exception.id, p_exception_expected_version, p_closure_note, p_actor_auth_user_id, p_actor_label);
    perform app.close_exception(v_resolved.id, v_resolved.record_version, p_actor_auth_user_id, p_actor_label);
  elsif v_exception.status = 'resolved' then
    perform app.close_exception(v_exception.id, p_exception_expected_version, p_actor_auth_user_id, p_actor_label);
  end if;
  -- status = 'closed' already -- no-op, its own closure precondition already holds.

  update app.claim_case_extensions
  set claim_stage = 'closed', closure_basis = v_closure_basis, closure_note = p_closure_note, closed_at = now(), closed_by = p_actor_label
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_claim_case target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_closure_note, null,
    jsonb_build_object('closure_basis', v_closure_basis)
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.close_exception(p_exception_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status <> 'resolved' then
    raise exception 'invalid_transition: exception % is % and cannot be closed', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'closed', closed_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied_count integer;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'soft_closed' then
    raise exception 'finance_period_not_soft_closed: period % is %, only a soft-closed period may be closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_unsatisfied_count from app.finance_period_close_checklist_items
    where period_id = p_period_id and required and not satisfied;
  if v_unsatisfied_count > 0 then
    raise exception 'finance_period_checklist_incomplete: period % has % unsatisfied required close-checklist item(s)', p_period_id, v_unsatisfied_count
      using errcode = 'check_violation';
  end if;

  update app.finance_fiscal_periods
  set status = 'closed', closed_at = now(), closed_by = p_actor_label
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'soft_closed', 'closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: complete_activity target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('outcome', p_outcome)
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_job_order(p_job_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
begin
  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status <> 'draft' then
    raise exception 'invalid_transition: job order % is % and cannot be confirmed', p_job_order_id, v_job_order.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.job_orders
  set status = 'confirmed'
  where id = p_job_order_id and record_version = p_expected_version
  returning * into v_job_order;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_job_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null, jsonb_build_object('status', v_job_order.status)
  );

  return v_job_order;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_shipment_leg_network(p_shipment_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_leg_count integer;
  v_max_sequence integer;
  v_distinct_sequence_count integer;
  v_unallocated_count integer;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*), max(sequence_no), count(distinct sequence_no)
    into v_leg_count, v_max_sequence, v_distinct_sequence_count
  from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled';

  if v_leg_count = 0 then
    raise exception 'network_empty: shipment order % has no active leg to confirm', p_shipment_order_id using errcode = 'check_violation';
  end if;

  if v_distinct_sequence_count <> v_leg_count or v_max_sequence <> v_leg_count then
    raise exception 'network_sequence_gap: shipment order % legs must form a contiguous 1..% sequence with no gap or duplicate', p_shipment_order_id, v_leg_count
      using errcode = 'check_violation';
  end if;

  select count(*) into v_unallocated_count
  from app.shipment_legs sl
  where sl.shipment_order_id = p_shipment_order_id and sl.leg_status <> 'cancelled'
    and not exists (select 1 from app.shipment_leg_cargo_allocations a where a.shipment_leg_id = sl.id);
  if v_unallocated_count > 0 then
    raise exception 'network_cargo_incomplete: % leg(s) of shipment order % have no cargo allocation', v_unallocated_count, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_orders set leg_network_status = 'confirmed' where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_shipment_leg_network target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_leg_network',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('leg_count', v_leg_count)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'invalid_transition: shipment order % is % and cannot be confirmed', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'confirmed'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('status', v_shipment.status)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
AS $function$
declare
  v_account app.finance_accounts;
  v_child_count integer;
  v_referenced_by_posting_map boolean := false;
  v_row record;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_account_deactivation_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'active' then
    raise exception 'finance_account_not_active: account % is %, only an active account may be deactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Delete', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Delete for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';
  if v_child_count > 0 then
    raise exception 'finance_account_has_active_children: account % has % active/draft child account(s) -- deactivate or reparent them first', p_account_id, v_child_count
      using errcode = 'check_violation';
  end if;

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (select 1 from jsonb_each(v_row.items) e where (e.value ->> 'accountCodeRef') = v_account.code) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;
  if v_referenced_by_posting_map then
    raise exception 'finance_account_referenced_by_posting_map: account % is referenced by a published posting map -- update the posting map first', p_account_id
      using errcode = 'check_violation';
  end if;

  update app.finance_accounts
  set status = 'inactive'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: deactivate_finance_account target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_finance_account',
    'app.finance_accounts', v_account.id, 'success', p_reason, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.decide_claim_responsibility(p_review_id uuid, p_expected_version integer, p_decision text, p_final_responsibility_party text, p_final_reserve_amount numeric, p_final_currency text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_responsibility_reviews
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_review app.claim_responsibility_reviews;
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_currency text;
  v_updated app.claim_responsibility_reviews;
begin
  select * into v_review from app.claim_responsibility_reviews where id = p_review_id;
  if not found then
    raise exception 'claim_responsibility_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_review.claim_case_id;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', v_case.id using errcode = 'check_violation';
  end if;

  -- A governed liability/reserve decision -- OPS:Override (OPS has no dedicated
  -- 'Approve' action; mirrors app.approve_warehouse_billing_event's own identical
  -- choice, ATW-022, see migration header).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, v_case.id using errcode = 'insufficient_privilege';
  end if;

  if v_review.status <> 'proposed' then
    raise exception 'invalid_transition: claim responsibility review % is % and cannot be decided', p_review_id, v_review.status using errcode = 'check_violation';
  end if;
  if v_review.record_version <> p_expected_version then
    raise exception 'stale_version: claim responsibility review % expected version % but found %', p_review_id, p_expected_version, v_review.record_version
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'denied', 'amended') then
    raise exception 'claim_invalid_decision: % is not one of approved/denied/amended', p_decision using errcode = 'check_violation';
  end if;

  -- Separation of duties -- the EXACT existing self_approval_not_allowed
  -- convention app.approve_warehouse_billing_event already established (ATW-022).
  if v_review.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed claim responsibility review % and may not also decide it', p_actor_auth_user_id, p_review_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision in ('approved', 'amended') then
    if p_final_responsibility_party is null or p_final_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
      raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_final_responsibility_party using errcode = 'check_violation';
    end if;
    if p_final_reserve_amount is null or p_final_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: final_reserve_amount is required and must not be negative for an approved/amended decision' using errcode = 'check_violation';
    end if;
    v_currency := coalesce(p_final_currency, v_review.proposed_currency);
    if v_currency is null or not app.validate_currency_code(v_currency) then
      raise exception 'invalid_currency: a valid final currency is required for an approved/amended decision' using errcode = 'check_violation';
    end if;
    -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
    -- header design note 5) -- closes the "propose zero, amend to a real positive
    -- number" bypass a propose-time-only gate would leave open.
    if p_final_reserve_amount > 0 and not exists (select 1 from app.claim_items where claim_case_id = v_case.id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = v_case.id)
    then
      raise exception 'claim_evidence_required: claim case % is being decided with a positive final reserve amount but has no itemized claim_items or linked evidence yet', v_case.id
        using errcode = 'check_violation';
    end if;
  else
    if p_final_responsibility_party is not null or p_final_reserve_amount is not null then
      raise exception 'claim_denied_decision_shape_invalid: a denied decision must not carry a final_responsibility_party/final_reserve_amount' using errcode = 'check_violation';
    end if;
    v_currency := null;
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'claim_decision_notes_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.claim_responsibility_reviews
  set status = p_decision,
      decided_by_auth_user_id = p_actor_auth_user_id,
      decided_by = p_actor_label,
      decided_at = now(),
      final_responsibility_party = case when p_decision in ('approved', 'amended') then p_final_responsibility_party else null end,
      final_reserve_amount = case when p_decision in ('approved', 'amended') then p_final_reserve_amount else null end,
      final_currency = case when p_decision in ('approved', 'amended') then v_currency else null end,
      decision_notes = p_decision_notes
  where id = p_review_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: decide_claim_responsibility target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.advance_claim_case_stage(v_case.id, 'decided');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_claim_responsibility',
    'app.claim_responsibility_reviews', v_updated.id, 'success', p_decision_notes,
    jsonb_build_object('status', v_review.status),
    jsonb_build_object('status', v_updated.status, 'final_responsibility_party', v_updated.final_responsibility_party, 'final_reserve_amount', v_updated.final_reserve_amount)
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.deregister_gps_device(p_device_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.gps_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_previous_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'deregister_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  -- OPS:Override, evaluated against the DEVICE'S OWN tenant (mirrors app.evaluate_
  -- permission's already-established supreme_admin exception, RPD-022 -- see this
  -- migration's own header design note 1(b)). A tenant's own OPS:Override holder may
  -- self-service-deregister their OWN device (the "legitimately-retired" case), but
  -- clearing a DIFFERENT tenant's spurious/malicious row (this finding's actual
  -- cross-tenant remediation target) always requires a real supreme_admin, since ordinary
  -- tenant-scoped role assignment structurally cannot span a tenant boundary.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_device.status = 'retired' then
    return v_device;
  end if;

  v_previous_status := v_device.status;

  update app.gps_devices
  set status = 'retired'
  where id = p_device_id and record_version = p_expected_version
  returning * into v_device;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: deregister_gps_device target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'deregister_gps_device',
    'app.gps_devices', v_device.id, 'success', p_reason, jsonb_build_object('status', v_previous_status), jsonb_build_object('status', 'retired')
  );

  return v_device;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
AS $function$
declare
  v_rate app.finance_exchange_rates;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id;
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be discarded', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Edit', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_exchange_rates
  set status = 'archived'
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: discard_finance_exchange_rate_draft target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_exchange_rate_draft',
    'app.finance_exchange_rates', v_rate.id, 'success', p_reason, null, to_jsonb(v_rate)
  );

  return v_rate;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: disqualify_prospect target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'disqualify_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_prospect;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.execute_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_job app.jobs;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status <> 'validated' then
    raise exception 'scenario_not_mutable: scenario % is % and can only execute from validated', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_job := app.enqueue_job(
    v_shipment.tenant_id, 'route_load_planning', jsonb_build_object('scenario_id', p_scenario_id), 0,
    p_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  update app.route_planning_scenarios
  set status = 'executing', job_id = v_job.job_id
  where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: execute_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id)
  );

  return v_scenario;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.hold_credit_profile(p_profile_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: holding a credit profile requires a non-empty reason' using errcode = 'not_null_violation';
  end if;

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found then
    raise exception 'credit_profile_not_found: %', p_profile_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: credit profile % expected version % but found %', p_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.status <> 'active' then
    raise exception 'invalid_transition: credit profile % is % and cannot be held', p_profile_id, v_profile.status
      using errcode = 'check_violation';
  end if;

  update app.credit_profiles
  set status = 'held', hold_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: hold_credit_profile target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', p_reason, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.hold_warehouse_billing_event(p_event_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot hold billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be held', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to hold a billing event' using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set status = 'on_hold', hold_reason = p_reason where id = p_event_id and record_version = p_expected_version returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: hold_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason, null, null
  );

  return v_event;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.override_billing_readiness(p_job_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  if not found then
    raise exception 'billing_readiness_not_evaluated: job order % has never been evaluated', p_job_order_id using errcode = 'no_data_found';
  end if;
  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: billing readiness evaluation % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'billing_readiness_override_reason_required: a non-empty reason is required to override a billing-readiness evaluation' using errcode = 'check_violation';
  end if;
  if v_current.effective_status = 'ready' then
    raise exception 'billing_readiness_override_not_needed: job order % is already effectively ready', p_job_order_id using errcode = 'check_violation';
  end if;

  update app.billing_readiness_evaluations
  set is_overridden = true, override_reason = p_reason, overridden_by_auth_user_id = p_actor_auth_user_id, overridden_by = p_actor_label, overridden_at = now(),
      override_revoked_reason = null, override_revoked_by = null, override_revoked_at = null
  where id = v_current.id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: override_billing_readiness target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_billing_readiness',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('evaluated_status', v_current.evaluated_status),
    jsonb_build_object('effective_status', v_updated.effective_status, 'override_reason', p_reason)
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.override_job_order_field(p_job_order_id uuid, p_expected_version integer, p_snapshot_column text, p_field_path text, p_new_value jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
  v_previous_value jsonb;
begin
  if p_snapshot_column not in ('customer_snapshot', 'cargo_service_snapshot') then
    raise exception 'invalid_snapshot_column: % is not an overridable snapshot', p_snapshot_column using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'override_reason_required: a non-empty reason is required to override a Job Order snapshot field' using errcode = 'check_violation';
  end if;

  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status = 'cancelled' then
    raise exception 'invalid_transition: job order % is cancelled and cannot be overridden', p_job_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_snapshot_column = 'customer_snapshot' then
    v_previous_value := v_job_order.customer_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set customer_snapshot = jsonb_set(customer_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: override_job_order_field target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    v_previous_value := v_job_order.cargo_service_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set cargo_service_snapshot = jsonb_set(cargo_service_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: override_job_order_field target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  insert into app.job_order_overrides (
    tenant_id, job_order_id, snapshot_column, field_path, previous_value, new_value, reason, overridden_by
  ) values (
    v_job_order.tenant_id, p_job_order_id, p_snapshot_column, p_field_path, v_previous_value, p_new_value, p_reason, p_actor_label
  );

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_job_order_field',
    'app.job_orders', v_job_order.id, 'success', null,
    jsonb_build_object('field_path', p_field_path, 'previous_value', v_previous_value),
    jsonb_build_object('field_path', p_field_path, 'new_value', p_new_value, 'reason', p_reason)
  );

  return v_job_order;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.override_margin_threshold(p_margin_calculation_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.margin_calculations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_calc app.margin_calculations;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: overriding a margin threshold requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_calc from app.margin_calculations where id = p_margin_calculation_id;
  if not found then
    raise exception 'margin_calculation_not_found: %', p_margin_calculation_id using errcode = 'no_data_found';
  end if;

  if v_calc.record_version <> p_expected_version then
    raise exception 'stale_version: margin calculation % expected version % but found %', p_margin_calculation_id, p_expected_version, v_calc.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_calc.threshold_outcome <> 'requires_approval' or v_calc.is_overridden then
    raise exception 'invalid_transition: margin calculation % is not an un-overridden requires_approval result', p_margin_calculation_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_calc.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_calc.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_calc.tenant_id, v_calc.owner_user_id, app.lead_record_scope_org_unit_ids(v_calc.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access margin calculation %', p_actor_auth_user_id, p_margin_calculation_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.margin_calculations
  set is_overridden = true, override_reason = p_reason, override_by = p_actor_label, override_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_margin_calculation_id and record_version = p_expected_version
  returning * into v_calc;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: override_margin_threshold target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_calc.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_margin_threshold',
    'app.margin_calculations', v_calc.id, 'success', p_reason, null, jsonb_build_object('threshold_outcome', v_calc.threshold_outcome)
  );

  return v_calc;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.propose_claim_responsibility(p_case_id uuid, p_proposed_responsibility_party text, p_proposed_reserve_amount numeric, p_proposed_currency text, p_proposed_rationale text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_responsibility_reviews
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_current app.claim_responsibility_reviews;
  v_review app.claim_responsibility_reviews;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  if p_proposed_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
    raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_proposed_responsibility_party using errcode = 'check_violation';
  end if;
  if p_proposed_rationale is null or length(trim(p_proposed_rationale)) = 0 then
    raise exception 'claim_rationale_required: a non-empty proposed_rationale is required' using errcode = 'check_violation';
  end if;
  if (p_proposed_reserve_amount is null) <> (p_proposed_currency is null) then
    raise exception 'claim_reserve_currency_shape_invalid: proposed_reserve_amount and proposed_currency must both be set or both be null' using errcode = 'check_violation';
  end if;
  if p_proposed_reserve_amount is not null then
    if p_proposed_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: proposed_reserve_amount must not be negative' using errcode = 'check_violation';
    end if;
    if not app.validate_currency_code(p_proposed_currency) then
      raise exception 'invalid_currency: % is not a registered, active currency', p_proposed_currency using errcode = 'check_violation';
    end if;
  end if;

  select * into v_current from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;

  -- Optimistic concurrency (Prompt 244 §25 "reject ... stale mutation"; see
  -- migration header design note 5) -- a live-reproduced lost update on an earlier
  -- draft with no version check at all is fixed here. Covers BOTH the in-place
  -- update branch below (the exact bug that was reproduced) and the start-a-new-
  -- version branch (the caller must prove it read the case's current state, decided
  -- or not, before proposing again).
  if found then
    if p_expected_version is null or v_current.record_version <> p_expected_version then
      raise exception 'stale_version: claim responsibility review % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
        using errcode = 'check_violation';
    end if;
  elsif p_expected_version is not null then
    raise exception 'stale_version: claim case % has no current responsibility review yet but expected_version % was supplied', p_case_id, p_expected_version
      using errcode = 'check_violation';
  end if;

  -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
  -- header design note 5) -- a positive proposed reserve requires at least one
  -- itemized claim_items row or linked evidence record on file; a genuinely
  -- zero/null reserve (no compensable loss) is exempt.
  if p_proposed_reserve_amount is not null and p_proposed_reserve_amount > 0 then
    if not exists (select 1 from app.claim_items where claim_case_id = p_case_id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = p_case_id)
    then
      raise exception 'claim_evidence_required: claim case % proposes a positive reserve amount but has no itemized claim_items or linked evidence yet', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  if found and v_current.status = 'proposed' then
    update app.claim_responsibility_reviews
    set proposed_responsibility_party = p_proposed_responsibility_party,
        proposed_reserve_amount = p_proposed_reserve_amount,
        proposed_currency = p_proposed_currency,
        proposed_rationale = p_proposed_rationale,
        proposed_by_auth_user_id = p_actor_auth_user_id,
        proposed_by = p_actor_label,
        proposed_at = now()
    where id = v_current.id and record_version = p_expected_version
    returning * into v_review;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: propose_claim_responsibility target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    if found then
      update app.claim_responsibility_reviews set is_current = false where id = v_current.id and record_version = p_expected_version;
    end if;
    insert into app.claim_responsibility_reviews (
      tenant_id, claim_case_id, version_number, proposed_responsibility_party, proposed_reserve_amount, proposed_currency,
      proposed_rationale, proposed_by_auth_user_id, proposed_by, supersedes_review_id, created_by
    ) values (
      v_case.tenant_id, p_case_id, coalesce(v_current.version_number, 0) + 1, p_proposed_responsibility_party, p_proposed_reserve_amount, p_proposed_currency,
      p_proposed_rationale, p_actor_auth_user_id, p_actor_label, v_current.id, p_actor_label
    )
    returning * into v_review;
  end if;

  perform app.advance_claim_case_stage(p_case_id, 'pending_decision');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_claim_responsibility',
    'app.claim_responsibility_reviews', v_review.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'proposed_responsibility_party', p_proposed_responsibility_party, 'proposed_reserve_amount', p_proposed_reserve_amount)
  );

  return v_review;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_customer_contract(p_contract_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_sibling app.customer_contracts;
  v_component_count integer;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and cannot be published', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.customer_contract_price_components where contract_id = p_contract_id;
  if v_component_count = 0 then
    raise exception 'no_price_components: contract % has no price components to publish', p_contract_id
      using errcode = 'check_violation';
  end if;

  for v_sibling in
    select * from app.customer_contracts
    where root_contract_id = v_contract.root_contract_id
      and id <> v_contract.id
      and status = 'published'
    order by id
    for update
  loop
    if v_sibling.effective_from < coalesce(v_contract.effective_to, 'infinity'::timestamptz)
       and v_contract.effective_from < coalesce(v_sibling.effective_to, 'infinity'::timestamptz) then
      raise exception 'overlapping_active_version: contract % [%, %) overlaps already-published version % [%, %)',
        p_contract_id, v_contract.effective_from, v_contract.effective_to, v_sibling.id, v_sibling.effective_from, v_sibling.effective_to
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.customer_contracts
  set status = 'published', updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_customer_contract target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', null, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_exception_sla_policy_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.exception_sla_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.exception_sla_policy_versions;
  v_superseded app.exception_sla_policy_versions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.exception_sla_policy_versions where id = p_version_id;
  if not found then
    raise exception 'exception_sla_policy_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: exception SLA policy % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: exception SLA policy % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if v_version.sla_hours is null then
    raise exception 'exception_invalid_sla_hours: a policy cannot publish without sla_hours set' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.exception_sla_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'exception_sla_policy_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.exception_sla_policy_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.exception_sla_policy_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_exception_sla_policy_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_exception_sla_policy_version',
    'app.exception_sla_policy_versions', v_version.id, 'success', null, null,
    jsonb_build_object('type', v_version.type, 'severity', v_version.severity, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_item_control_policy_version(p_policy_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_control_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_policy app.item_control_policy_versions;
  v_superseded app.item_control_policy_versions;
begin
  select * into v_policy from app.item_control_policy_versions where id = p_policy_version_id;
  if not found then
    raise exception 'policy_version_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_policy_version_id, p_expected_version, v_policy.record_version
      using errcode = 'check_violation';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is % and cannot be published', p_policy_version_id, v_policy.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.item_control_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_policy_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.item_master_id <> v_policy.item_master_id then
      raise exception 'invalid_supersede: superseded policy must share the same item_master_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded policy % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.item_control_policy_versions set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.item_control_policy_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_policy_version_id and record_version = p_expected_version
    returning * into v_policy;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_item_control_policy_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_policy_exists: item % already has a published control policy -- supply p_supersedes_version_id to replace it', v_policy.item_master_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_item_control_policy_version',
    'app.item_control_policy_versions', v_policy.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_policy;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_label_template_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
  v_superseded app.label_template_versions;
begin
  select * into v_version from app.label_template_versions where id = p_version_id;
  if not found then
    raise exception 'label_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: label template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: label template version % is % and cannot be published', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    -- `for update` (findings review LOW #7): locks the row between this read and the
    -- archive UPDATE below so a concurrent modification cannot slip in between them.
    select * into v_superseded from app.label_template_versions where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.template_id <> v_version.template_id then
      raise exception 'invalid_supersede: superseded version must share the same template_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded version % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.label_template_versions set status = 'archived' where id = p_supersedes_version_id and status = 'published';
  end if;

  begin
    update app.label_template_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id
    where id = p_version_id and record_version = p_expected_version
    returning * into v_version;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_label_template_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_template_version_exists: template % already has a published version -- supply p_supersedes_version_id to replace it', v_version.template_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_label_template_version',
    'app.label_template_versions', v_version.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_margin_rule_version(p_rule_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.margin_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.margin_rule_versions;
  v_superseded app.margin_rule_versions;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.margin_rule_versions where id = p_rule_version_id;
  if not found then
    raise exception 'margin_rule_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: margin rule % expected version % but found %', p_rule_version_id, p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rule.status <> 'draft' then
    raise exception 'invalid_transition: margin rule % is % and cannot be published', p_rule_version_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.margin_rule_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_rule_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_rule.tenant_id then
      raise exception 'invalid_supersede: superseded rule must share the same tenant'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded rule % is % (must be published)', p_supersedes_version_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
    update app.margin_rule_versions set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.margin_rule_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_rule_version_id and record_version = p_expected_version
    returning * into v_rule;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_margin_rule_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_rule_exists: tenant % already has a published margin rule -- supply p_supersedes_version_id to replace it', v_rule.tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_margin_rule_version',
    'app.margin_rule_versions', v_rule.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_rule;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_milestone_template_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.milestone_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.milestone_template_versions;
  v_superseded app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_element jsonb;
  v_seen text[] := array[]::text[];
  v_code text;
begin
  select * into v_version from app.milestone_template_versions where id = p_version_id;
  if not found then
    raise exception 'milestone_template_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: milestone template % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: milestone template % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_version.sequence) = 0 then
    raise exception 'milestone_invalid_sequence: a milestone template cannot publish with an empty sequence' using errcode = 'check_violation';
  end if;

  for v_element in select * from jsonb_array_elements(v_version.sequence) loop
    v_code := v_element ->> 'code';
    if not exists (select 1 from app.milestone_codes where code = v_code) then
      raise exception 'milestone_unknown_code: % is not a registered milestone code', v_code using errcode = 'check_violation';
    end if;
    if v_code = any (v_seen) then
      raise exception 'milestone_duplicate_code: % appears more than once in the sequence', v_code using errcode = 'check_violation';
    end if;
    v_seen := array_append(v_seen, v_code);
  end loop;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'milestone_template_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    -- ATW-032: the supersede target was previously resolved by id ALONE and then archived,
    -- while the authority check above is against the tenant of the version being PUBLISHED.
    -- A tenant admin could therefore pass another tenant's published template version id and
    -- archive it -- a cross-tenant write, and exactly the class CPD-004/INV-002 exist to
    -- prevent. The target must belong to the same tenant as the version being published.
    if v_superseded.tenant_id <> v_version.tenant_id then
      raise exception 'milestone_template_not_found: supersedes target % is not a template version of tenant %', p_supersedes_version_id, v_version.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.milestone_template_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_milestone_template_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_milestone_template_version',
    'app.milestone_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('mode', v_version.mode, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_quotation_approval_rule_version(p_rule_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotation_approval_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.quotation_approval_rules;
  v_superseded app.quotation_approval_rules;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.quotation_approval_rules where id = p_rule_version_id;
  if not found then
    raise exception 'quotation_approval_rule_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: quotation approval rule % expected version % but found %', p_rule_version_id, p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rule.status <> 'draft' then
    raise exception 'invalid_transition: quotation approval rule % is % and cannot be published', p_rule_version_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.quotation_approval_rules where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_rule_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_rule.tenant_id then
      raise exception 'invalid_supersede: superseded rule must share the same tenant'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded rule % is % (must be published)', p_supersedes_version_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
    update app.quotation_approval_rules set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.quotation_approval_rules
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_rule_version_id and record_version = p_expected_version
    returning * into v_rule;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_quotation_approval_rule_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_rule_exists: tenant % already has a published quotation approval rule -- supply p_supersedes_version_id to replace it', v_rule.tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_quotation_approval_rule_version',
    'app.quotation_approval_rules', v_rule.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_rule;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.publish_sales_plan(p_plan_id uuid, p_expected_version integer, p_supersedes_plan_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_plan app.sales_plans;
  v_superseded app.sales_plans;
  v_decision app.rbac_decision;
  v_overlap_count integer;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % and cannot be published', p_plan_id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_plan_id is not null then
    select * into v_superseded from app.sales_plans where id = p_supersedes_plan_id;
    if not found then
      raise exception 'superseded_plan_not_found: %', p_supersedes_plan_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_plan.tenant_id or v_superseded.org_unit_id is distinct from v_plan.org_unit_id then
      raise exception 'invalid_supersede: superseded plan must share tenant and organization scope'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded plan % is not published (is %)', p_supersedes_plan_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
  end if;

  select count(*) into v_overlap_count
  from app.sales_plans sp
  where sp.tenant_id = v_plan.tenant_id
    and sp.org_unit_id is not distinct from v_plan.org_unit_id
    and sp.status = 'published'
    and sp.id <> coalesce(p_supersedes_plan_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and sp.period_start <= v_plan.period_end
    and sp.period_end >= v_plan.period_start;

  if v_overlap_count > 0 then
    raise exception 'overlapping_plan: another published plan already covers an overlapping period for this organization scope'
      using errcode = 'check_violation';
  end if;

  if p_supersedes_plan_id is not null then
    update app.sales_plans
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_plan_id;
  end if;

  update app.sales_plans
  set status = 'published', supersedes_plan_id = p_supersedes_plan_id, updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_sales_plan target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, jsonb_build_object('supersedes_plan_id', p_supersedes_plan_id)
  );

  return v_plan;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.rebaseline_shipment_leg_schedule(p_shipment_leg_id uuid, p_new_planned_departure_at timestamp with time zone, p_new_planned_arrival_at timestamp with time zone, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_before jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to rebaseline a leg''s own schedule' using errcode = 'check_violation';
  end if;
  if p_new_planned_arrival_at <= p_new_planned_departure_at then
    raise exception 'invalid_schedule: new_planned_arrival_at must be after new_planned_departure_at' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_unstarted: leg % is %, only a planned (unstarted) leg may be rebaselined', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object('planned_departure_at', v_leg.planned_departure_at, 'planned_arrival_at', v_leg.planned_arrival_at);

  update app.shipment_legs
  set planned_departure_at = p_new_planned_departure_at, planned_arrival_at = p_new_planned_arrival_at
  where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: rebaseline_shipment_leg_schedule target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'rebaseline_shipment_leg_schedule',
    'app.shipment_legs', v_leg.id, 'success', null, v_before,
    jsonb_build_object('planned_departure_at', v_leg.planned_departure_at, 'planned_arrival_at', v_leg.planned_arrival_at, 'shipment_leg_id', p_shipment_leg_id, 'reason', p_reason)
  );

  return v_leg;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.recalculate_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_reason text, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
  v_before_total numeric;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed re-calculation -- OPS:Override, requiring a reason (Prompt 241 section
  -- 14's own "recalculate-with-version" distinct API surface).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be recalculated (use correct/reverse for approved/handed-off events)', p_event_id, v_event.status
      using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to recalculate a billing event' using errcode = 'check_violation';
  end if;

  v_before_total := v_event.total_amount;

  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  -- Re-runs the IDENTICAL calculation logic app.calculate_warehouse_billing_event uses
  -- (the shared internal function), IN PLACE on the same row -- legitimate pre-
  -- approval iteration, not a "silent amount rewrite after handoff" (nothing has been
  -- approved/handed off yet at pending_review/reviewed). A recalculation always
  -- resets any prior review to pending_review -- the reviewer must look again.
  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: recalculate_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason,
    jsonb_build_object('total_amount', v_before_total), jsonb_build_object('total_amount', v_event.total_amount)
  );

  return v_event;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reject_rate_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.release_credit_profile(p_profile_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found then
    raise exception 'credit_profile_not_found: %', p_profile_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: credit profile % expected version % but found %', p_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.status <> 'held' then
    raise exception 'invalid_transition: credit profile % is % and cannot be released', p_profile_id, v_profile.status
      using errcode = 'check_violation';
  end if;

  update app.credit_profiles
  set status = 'active', hold_reason = null, updated_at = now(), record_version = record_version + 1
  where id = p_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: release_credit_profile target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', null, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.release_warehouse_billing_event_hold(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot release billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'on_hold' then
    raise exception 'invalid_transition: billing event % is % -- only on_hold may be released', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- Always back to pending_review, never directly to reviewed/approved -- a held
  -- event must be looked at again from the start.
  update app.warehouse_billing_events set status = 'pending_review' where id = p_event_id and record_version = p_expected_version returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: release_warehouse_billing_event_hold target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_warehouse_billing_event_hold',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reopen_claim_case(p_case_id uuid, p_expected_version integer, p_exception_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_updated app.claim_case_extensions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening a claim case requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage <> 'closed' then
    raise exception 'invalid_transition: claim case % is % and cannot be reopened', p_case_id, v_case.claim_stage using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  -- Mirrors app.reopen_exception''s own actual OPS:Edit precedent exactly (not the
  -- registered-but-unused OPS:Reopen action -- see migration header) so the claim
  -- extension and the base exception it wraps share the same authorization tier.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  perform app.reopen_exception(v_case.operational_exception_id, p_exception_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);

  update app.claim_case_extensions
  set claim_stage = 'investigating', reopened_at = now(), reopened_by = p_actor_label, reopen_reason = p_reason
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_claim_case target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_reason, null, null
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reopen_exception(p_exception_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening an exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('resolved', 'closed') then
    raise exception 'invalid_transition: exception % is % and cannot be reopened', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'reopened', reopened_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_exception;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_reopen_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'closed' then
    raise exception 'finance_period_not_closed: period % is %, only a closed period may be reopened', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_fiscal_periods
  set status = 'open', closed_at = null, closed_by = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'closed', 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', p_reason, null, to_jsonb(v_period)
  );

  return v_period;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reschedule_activity target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('new_due_at', p_new_due_at)
  );

  return v_activity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.resolve_exception(p_exception_id uuid, p_expected_version integer, p_resolution_evidence text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_resolution_evidence is null or length(trim(p_resolution_evidence)) = 0 then
    raise exception 'evidence_required: resolving an exception requires non-empty resolution_evidence' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'acknowledged', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be resolved', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'resolved', resolution_evidence = p_resolution_evidence, resolved_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: resolve_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('resolution_evidence', p_resolution_evidence)
  );

  return v_exception;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.retire_customer_contract(p_contract_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: retiring a contract requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'published' then
    raise exception 'invalid_transition: contract % is % and only a published contract can be retired', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.customer_contracts
  set status = 'retired', retired_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: retire_customer_contract target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'retire_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', p_reason, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.review_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot review billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'pending_review' then
    raise exception 'invalid_transition: billing event % is % -- only pending_review may be reviewed', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set
    status = 'reviewed', reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by_label = p_actor_label, reviewed_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: review_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.revoke_billing_readiness_override(p_job_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  if not found then
    raise exception 'billing_readiness_not_evaluated: job order % has never been evaluated', p_job_order_id using errcode = 'no_data_found';
  end if;
  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: billing readiness evaluation % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_current.is_overridden then
    raise exception 'billing_readiness_not_overridden: job order % has no active override to revoke', p_job_order_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'billing_readiness_revoke_reason_required: a non-empty reason is required to revoke a billing-readiness override' using errcode = 'check_violation';
  end if;

  update app.billing_readiness_evaluations
  set is_overridden = false, override_revoked_reason = p_reason, override_revoked_by = p_actor_label, override_revoked_at = now()
  where id = v_current.id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: revoke_billing_readiness_override target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_billing_readiness_override',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('effective_status', 'ready'),
    jsonb_build_object('effective_status', v_updated.effective_status)
  );

  return v_updated;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_driver_mobile_tracking_consent(p_driver_profile_id uuid, p_consent boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.driver_operational_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.driver_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.driver_operational_profiles where id = p_driver_profile_id;
  if not found then
    raise exception 'driver_profile_not_found: %', p_driver_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: driver profile % expected version % but found %', p_driver_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_operational_profiles
  set mobile_tracking_consent = p_consent, mobile_tracking_consent_at = case when p_consent then now() else null end
  where id = p_driver_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: set_driver_mobile_tracking_consent target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_driver_mobile_tracking_consent',
    'app.driver_operational_profiles', v_profile.id, 'success', null, null, jsonb_build_object('consent', p_consent)
  );

  return v_profile;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_vehicle_tracking_eligibility(p_vehicle_profile_id uuid, p_mobile_eligible boolean, p_direct_device_eligible boolean, p_third_party_eligible boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_operational_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.vehicle_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.vehicle_operational_profiles where id = p_vehicle_profile_id;
  if not found then
    raise exception 'vehicle_profile_not_found: %', p_vehicle_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vehicle profile % expected version % but found %', p_vehicle_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.vehicle_operational_profiles
  set mobile_tracking_eligible = p_mobile_eligible, direct_device_tracking_eligible = p_direct_device_eligible, third_party_tracking_eligible = p_third_party_eligible
  where id = p_vehicle_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: set_vehicle_tracking_eligibility target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vehicle_tracking_eligibility',
    'app.vehicle_operational_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('mobile_tracking_eligible', p_mobile_eligible, 'direct_device_tracking_eligible', p_direct_device_eligible, 'third_party_tracking_eligible', p_third_party_eligible)
  );

  return v_profile;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'open' then
    raise exception 'finance_period_not_open: period % is %, only an open period may be soft-closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_fiscal_periods
  set status = 'soft_closed'
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: soft_close_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'open', 'soft_closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'soft_close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$
;

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
    where co.config_type_code = 'approval' and co.tenant_id = v_quotation.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

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
$function$
;

CREATE OR REPLACE FUNCTION app.transition_gps_device_status(p_device_id uuid, p_to_status text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.gps_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_device.status = 'stock' and p_to_status = 'assigned')
    or (v_device.status = 'assigned' and p_to_status = 'installed')
    or (v_device.status = 'installed' and p_to_status = 'active')
    or (v_device.status in ('active', 'offline') and p_to_status in ('active', 'offline', 'suspended', 'maintenance'))
    or (v_device.status in ('suspended', 'maintenance') and p_to_status = 'active')
    or (v_device.status <> 'retired' and p_to_status = 'retired');

  if not v_allowed then
    raise exception 'invalid_device_status_transition: device % cannot move from % to %', p_device_id, v_device.status, p_to_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.gps_devices set status = p_to_status where id = p_device_id and record_version = p_expected_version
  returning * into v_device;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_gps_device_status target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_gps_device_status',
    'app.gps_devices', v_device.id, 'success', null, jsonb_build_object('status', v_device.status), jsonb_build_object('status', p_to_status)
  );

  return v_device;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_lead_status target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, p_action_name,
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_status', p_new_status, 'reason', p_reason)
  );

  return v_lead;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.transition_opportunity_stage(p_opportunity_id uuid, p_expected_version integer, p_new_stage text, p_probability integer, p_close_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.opportunities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_default_probability integer;
  v_probability integer;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot change stage again', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  if p_new_stage not in ('qualifying', 'requirements_gathering', 'ready_for_costing', 'won', 'lost') then
    raise exception 'invalid_stage: % is not a canonical opportunity stage', p_new_stage using errcode = 'check_violation';
  end if;

  if p_new_stage in ('won', 'lost') and (p_close_reason is null or length(trim(p_close_reason)) = 0) then
    raise exception 'reason_required: closing an opportunity as % requires a non-empty reason', p_new_stage
      using errcode = 'not_null_violation';
  end if;

  -- Managers move/close by policy (Prompt 147 §26): closing to a terminal stage requires
  -- COM:Approve; any other forward/lateral stage move requires the ordinary COM:Edit.
  v_decision := app.evaluate_permission(
    p_actor_auth_user_id, v_opportunity.tenant_id, 'COM',
    case when p_new_stage in ('won', 'lost') then 'Approve' else 'Edit' end
  );
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks required COM permission (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_default_probability := case p_new_stage
    when 'qualifying' then 10
    when 'requirements_gathering' then 30
    when 'ready_for_costing' then 60
    when 'won' then 100
    when 'lost' then 0
  end;
  v_probability := coalesce(p_probability, v_default_probability);
  if v_probability < 0 or v_probability > 100 then
    raise exception 'invalid_probability: % is not between 0 and 100', v_probability using errcode = 'check_violation';
  end if;

  update app.opportunities
  set stage = p_new_stage,
      probability = v_probability,
      close_reason = case when p_new_stage in ('won', 'lost') then p_close_reason else close_reason end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_opportunity_stage target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, reason, changed_by)
  values (v_opportunity.tenant_id, v_opportunity.id, v_opportunity.stage, p_new_stage, v_probability, p_close_reason, p_actor_label);

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_opportunity_stage',
    'app.opportunities', v_opportunity.id, 'success', null, null,
    jsonb_build_object('to_stage', p_new_stage, 'probability', v_probability, 'close_reason', p_close_reason)
  );

  return v_opportunity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.transition_shipment_leg(p_shipment_leg_id uuid, p_to_status text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_leg.leg_status = 'planned' and p_to_status = 'dispatched')
    or (v_leg.leg_status = 'dispatched' and p_to_status = 'in_transit')
    or (v_leg.leg_status = 'in_transit' and p_to_status = 'arrived')
    or (v_leg.leg_status = 'arrived' and p_to_status = 'completed')
    or (v_leg.leg_status in ('planned', 'dispatched', 'in_transit', 'arrived') and p_to_status = 'cancelled');

  if not v_allowed then
    raise exception 'invalid_leg_status_transition: leg % cannot move from % to %', p_shipment_leg_id, v_leg.leg_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if v_leg.leg_status = 'planned' and p_to_status = 'dispatched' and v_shipment.leg_network_status <> 'confirmed' then
    raise exception 'network_not_confirmed: shipment order % leg network must be confirmed before any leg can dispatch', v_leg.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs
  set leg_status = p_to_status,
      actual_departure_at = case when p_to_status = 'dispatched' and actual_departure_at is null then now() else actual_departure_at end,
      actual_arrival_at = case when p_to_status = 'arrived' and actual_arrival_at is null then now() else actual_arrival_at end
  where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_shipment_leg target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, jsonb_build_object('leg_status', p_to_status), jsonb_build_object('leg_status', v_leg.leg_status)
  );

  return v_leg;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.transition_shipment_order(p_shipment_order_id uuid, p_to_status text, p_expected_version integer, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_transition app.shipment_status_transitions;
  v_from_status text;
  v_next_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_transition from app.shipment_status_transitions
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing_transition.to_status is distinct from p_to_status then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different status transition (transition to %, not to %)', p_idempotency_key, v_existing_transition.to_status, p_to_status
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_shipment.status;

  -- The canonical matrix. 'held'/'cancelled' branch off most active states; 'held'
  -- resumes only into its own recorded held_from_status; 'closed' may only reopen
  -- into 'delivered'/'epod' (Supreme-only, checked below), never further back.
  if v_from_status = 'held' then
    if p_to_status <> v_shipment.held_from_status and p_to_status <> 'cancelled' then
      raise exception 'invalid_transition: a held shipment order % may only resume into % or cancel', p_shipment_order_id, v_shipment.held_from_status
        using errcode = 'check_violation';
    end if;
  elsif v_from_status = 'closed' then
    if p_to_status not in ('delivered', 'epod') then
      raise exception 'invalid_transition: shipment order % is closed and may only reopen into delivered or epod', p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)'
        using errcode = 'insufficient_privilege';
    end if;
  elsif v_from_status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled, a terminal state', p_shipment_order_id using errcode = 'check_violation';
  elsif v_from_status = 'draft' and p_to_status in ('confirmed', 'cancelled') then
    null;
  elsif v_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit') and p_to_status in ('held', 'cancelled') then
    null;
  elsif v_from_status = 'confirmed' and p_to_status = 'planned' then
    null;
  elsif v_from_status = 'planned' and p_to_status = 'assigned' then
    null;
  elsif v_from_status = 'assigned' and p_to_status = 'dispatched' then
    null;
  elsif v_from_status = 'dispatched' and p_to_status = 'in_transit' then
    null;
  elsif v_from_status = 'in_transit' and p_to_status = 'delivered' then
    null;
  elsif v_from_status = 'delivered' and p_to_status in ('epod', 'cancelled') then
    null;
  elsif v_from_status = 'epod' and p_to_status = 'closed' then
    null;
  else
    raise exception 'invalid_transition: % -> % is not a legal Shipment Order transition', v_from_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if p_to_status in ('held', 'cancelled') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('delivered', 'epod', 'closed') and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: a non-empty evidence reference is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_next_status := p_to_status;

  begin
    insert into app.shipment_status_transitions (
      tenant_id, shipment_order_id, from_status, to_status, reason, evidence_ref, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, v_from_status, v_next_status, p_reason, p_evidence_ref, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
      return v_shipment;
  end;

  update app.shipment_orders
  set status = v_next_status,
      held_from_status = case when v_next_status = 'held' then v_from_status else null end
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null,
    jsonb_build_object('status', v_from_status),
    jsonb_build_object('status', v_next_status, 'reason', p_reason, 'evidence_ref', p_evidence_ref)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_opportunity(p_opportunity_id uuid, p_expected_version integer, p_name text, p_requirements jsonb, p_next_action text, p_next_action_due_at timestamp with time zone, p_value_amount numeric, p_value_currency text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.opportunities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot be edited', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_opportunity.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if (
    (p_value_amount is not null and p_value_amount is distinct from v_opportunity.value_amount)
    or (p_value_currency is not null and p_value_currency is distinct from v_opportunity.value_currency)
  ) and not app.has_view_selling_price(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View selling price required to set opportunity value', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.opportunities
  set name = coalesce(p_name, name),
      requirements = coalesce(p_requirements, requirements),
      next_action = coalesce(p_next_action, next_action),
      next_action_due_at = coalesce(p_next_action_due_at, next_action_due_at),
      value_amount = coalesce(p_value_amount, value_amount),
      value_currency = coalesce(p_value_currency, value_currency),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_opportunity target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_opportunity',
    'app.opportunities', v_opportunity.id, 'success', null, null, to_jsonb(v_opportunity)
  );

  return v_opportunity;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_pipeline_category(p_category_id uuid, p_expected_version integer, p_label text, p_sort_order integer, p_is_active boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.pipeline_categories
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_category app.pipeline_categories;
  v_decision app.rbac_decision;
begin
  select * into v_category from app.pipeline_categories where id = p_category_id;
  if not found then
    raise exception 'pipeline_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;

  if v_category.record_version <> p_expected_version then
    raise exception 'stale_version: pipeline category % expected version % but found %', p_category_id, p_expected_version, v_category.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_category.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.pipeline_categories
  set label = coalesce(p_label, label),
      sort_order = coalesce(p_sort_order, sort_order),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_category_id and record_version = p_expected_version
  returning * into v_category;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_pipeline_category target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_pipeline_category',
    'app.pipeline_categories', v_category.id, 'success', null, null, to_jsonb(v_category)
  );

  return v_category;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_quotation_terms(p_quotation_id uuid, p_expected_version integer, p_currency text, p_validity_from timestamp with time zone, p_validity_to timestamp with time zone, p_terms jsonb, p_contact_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_allowed_keys text[] := array['payment_terms', 'incoterm', 'notes'];
  v_key text;
  v_line_currency_mismatch boolean;
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
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
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

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_from is null or p_validity_to is null or p_validity_to <= p_validity_from then
    raise exception 'invalid_validity: validity_to must be after validity_from' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(coalesce(p_terms, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_terms: terms must be a JSON object' using errcode = 'check_violation';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_terms, '{}'::jsonb)) loop
    if not (v_key = any (v_allowed_keys)) then
      raise exception 'unknown_terms_key: % is not a whitelisted terms key', v_key using errcode = 'check_violation';
    end if;
  end loop;

  if p_contact_id is not null and not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = v_quotation.tenant_id) then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  select exists (
    select 1 from app.quotation_lines ql
    join app.margin_calculations mc on mc.id = ql.margin_calculation_id
    where ql.quotation_id = p_quotation_id and mc.sell_currency <> p_currency
  ) into v_line_currency_mismatch;

  if v_line_currency_mismatch then
    raise exception 'mixed_currency: quotation % has lines sourced from a different currency than %', p_quotation_id, p_currency
      using errcode = 'check_violation';
  end if;

  update app.quotations
  set currency = p_currency, validity_from = p_validity_from, validity_to = p_validity_to,
      terms = coalesce(p_terms, '{}'::jsonb), contact_id = p_contact_id,
      updated_at = now(), record_version = record_version + 1
  where id = p_quotation_id and record_version = p_expected_version
  returning * into v_quotation;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_quotation_terms target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_quotation_terms',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_sales_target(p_target_id uuid, p_expected_version integer, p_target_value integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_targets
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_target from app.sales_targets where id = p_target_id;
  if not found then
    raise exception 'sales_target_not_found: %', p_target_id using errcode = 'no_data_found';
  end if;

  if v_target.record_version <> p_expected_version then
    raise exception 'stale_version: sales target % expected version % but found %', p_target_id, p_expected_version, v_target.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;
  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % -- targets can only be edited while the plan is draft', v_plan.id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_target.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_target_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_target_value < 0 then
    raise exception 'invalid_target_value: target_value must be non-negative' using errcode = 'check_violation';
  end if;

  update app.sales_targets
  set target_value = p_target_value, updated_at = now(), record_version = record_version + 1
  where id = p_target_id and record_version = p_expected_version
  returning * into v_target;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_sales_target target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_target.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_sales_target',
    'app.sales_targets', v_target.id, 'success', null, null, jsonb_build_object('target_value', p_target_value)
  );

  return v_target;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_win_loss_reason(p_reason_id uuid, p_expected_version integer, p_label text, p_is_active boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.win_loss_reasons
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_reason app.win_loss_reasons;
  v_decision app.rbac_decision;
begin
  select * into v_reason from app.win_loss_reasons where id = p_reason_id;
  if not found then
    raise exception 'win_loss_reason_not_found: %', p_reason_id using errcode = 'no_data_found';
  end if;

  if v_reason.record_version <> p_expected_version then
    raise exception 'stale_version: win/loss reason % expected version % but found %', p_reason_id, p_expected_version, v_reason.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reason.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reason.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.win_loss_reasons
  set label = coalesce(p_label, label),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_reason_id and record_version = p_expected_version
  returning * into v_reason;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_win_loss_reason target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reason.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_win_loss_reason',
    'app.win_loss_reasons', v_reason.id, 'success', null, null, to_jsonb(v_reason)
  );

  return v_reason;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.validate_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop_count integer;
  v_max_sequence integer;
  v_distinct_sequence_count integer;
  v_constraint record;
  v_position record;
  v_snapshot jsonb;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status <> 'draft' then
    raise exception 'scenario_not_mutable: scenario % is % and can only be validated from draft', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*), max(stop_sequence), count(distinct stop_sequence)
    into v_stop_count, v_max_sequence, v_distinct_sequence_count
  from app.route_planning_stops where scenario_id = p_scenario_id;

  if v_stop_count < 2 then
    raise exception 'stops_insufficient: scenario % has % stop(s), at least 2 are required', p_scenario_id, v_stop_count
      using errcode = 'check_violation';
  end if;
  if v_distinct_sequence_count <> v_stop_count or v_max_sequence <> v_stop_count then
    raise exception 'stop_sequence_gap: scenario % stops must form a contiguous 1..% sequence with no gap or duplicate', p_scenario_id, v_stop_count
      using errcode = 'check_violation';
  end if;

  for v_constraint in select * from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_type = 'hard'
  loop
    if v_constraint.constraint_key = 'required_vehicle_master_id' then
      if not exists (
        select 1 from app.vehicle_operational_profiles
        where vehicle_master_id = (v_constraint.constraint_value ->> 'master_id')::uuid
          and tenant_id = v_scenario.tenant_id and status = 'active'
      ) then
        raise exception 'required_vehicle_not_found: % is not a known active vehicle operational profile for tenant %', v_constraint.constraint_value ->> 'master_id', v_scenario.tenant_id
          using errcode = 'no_data_found';
      end if;
    elsif v_constraint.constraint_key = 'required_driver_master_id' then
      if not exists (
        select 1 from app.driver_operational_profiles
        where driver_master_id = (v_constraint.constraint_value ->> 'master_id')::uuid
          and tenant_id = v_scenario.tenant_id and status = 'active'
      ) then
        raise exception 'required_driver_not_found: % is not a known active driver operational profile for tenant %', v_constraint.constraint_value ->> 'master_id', v_scenario.tenant_id
          using errcode = 'no_data_found';
      end if;
    end if;
  end loop;

  select * into v_position from app.get_canonical_position_for_planning(v_scenario.shipment_order_id);
  v_snapshot := jsonb_build_object(
    'tracking_status', v_position.tracking_status,
    'freshness_status', v_position.freshness_status,
    'accuracy_meters', v_position.accuracy_meters,
    'last_position_at', v_position.last_position_at,
    'authoritative_source_type', v_position.authoritative_source_type,
    'tracking_entitled', v_position.tracking_entitled,
    'is_usable', v_position.is_usable
  );

  update app.route_planning_scenarios
  set status = 'validated', canonical_position_snapshot = v_snapshot, canonical_position_captured_at = now()
  where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: validate_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'validate_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('stop_count', v_stop_count, 'position_usable', v_position.is_usable)
  );

  return v_scenario;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.withdraw_claim_item(p_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.claim_items;
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a claim item requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_item from app.claim_items where id = p_item_id;
  if not found then
    raise exception 'claim_item_not_found: %', p_item_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_item.claim_case_id;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim item %', p_actor_auth_user_id, p_item_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'active' then
    raise exception 'invalid_transition: claim item % is % and cannot be withdrawn', p_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: claim item % expected version % but found %', p_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.claim_items
  set status = 'withdrawn', withdrawn_at = now(), withdrawn_by = p_actor_label, withdrawal_reason = p_reason
  where id = p_item_id and record_version = p_expected_version
  returning * into v_item;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: withdraw_claim_item target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_claim_item',
    'app.claim_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: withdraw_rate_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.ingest_milestone_event(p_shipment_order_id uuid, p_milestone_code text, p_event_time timestamp with time zone, p_received_time timestamp with time zone, p_location jsonb, p_source text, p_reason text, p_corrects_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_source_class text DEFAULT NULL::text, p_source_confidence_score numeric DEFAULT NULL::numeric, p_source_freshness_status text DEFAULT NULL::text, p_source_candidate_id uuid DEFAULT NULL::uuid)
 RETURNS app.milestone_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_corrected app.milestone_events;
  v_next_seq integer;
  v_event app.milestone_events;
begin
  if p_source not in ('manual', 'api', 'webhook', 'import', 'system') then
    raise exception 'milestone_invalid_source: % is not one of manual/api/webhook/import/system', p_source using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.milestone_codes where code = p_milestone_code) then
    raise exception 'milestone_unknown_code: % is not a registered milestone code', p_milestone_code using errcode = 'check_violation';
  end if;
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'milestone_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'milestone_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'milestone_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and can no longer receive milestone events', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_corrects_event_id is not null then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a correction requires a non-empty reason' using errcode = 'check_violation';
    end if;
    select * into v_corrected from app.milestone_events where id = p_corrects_event_id and shipment_order_id = p_shipment_order_id;
    if not found then
      raise exception 'milestone_event_not_found: % is not a prior event on shipment order %', p_corrects_event_id, p_shipment_order_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_event.milestone_code is distinct from p_milestone_code then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different milestone event (milestone %, not %)', p_idempotency_key, v_event.milestone_code, p_milestone_code
        using errcode = 'unique_violation';
    end if;
    return v_event;
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq from app.milestone_events where shipment_order_id = p_shipment_order_id;

  insert into app.milestone_events (
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by,
    source_class, source_confidence_score, source_freshness_status, source_candidate_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_candidate_id
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id, 'source_class', p_source_class)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    -- ATW-032 (ISS-2026-034): the ATW-031 guard in the body above raises with
    -- errcode = 'unique_violation', which is exactly the condition THIS handler traps --
    -- so the guard was caught here and the mismatched row returned anyway, and the
    -- misattribution it was written to stop still happened. Re-applying the discriminator
    -- inside the handler is what makes it real: an exception raised from within a handler
    -- is not re-caught by that same handler, so this one propagates.
    if v_event.milestone_code is distinct from p_milestone_code then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different milestone event (milestone %, not %)', p_idempotency_key, v_event.milestone_code, p_milestone_code
        using errcode = 'unique_violation';
    end if;
    return v_event;
end;
$function$
;

-- Deliberately NO grant block. Every statement above is a `CREATE OR REPLACE FUNCTION` on an
-- already-existing function, and Postgres PRESERVES the existing ACL across a replace -- so
-- there is nothing to restore. The `revoke ... from public` below is kept for the
-- `ERR-2026-004` convention (it strips the default PUBLIC EXECUTE that a genuinely NEW
-- function would otherwise carry) and is a no-op here.
--
-- An earlier draft of this migration re-granted `authenticated, service_role` to all 74 as a
-- matter of course. That was wrong and the suite caught it: `app.transition_gps_device_status`
-- deliberately carries NO client grant, and
-- `scripts/db-tests/advanced-tms-device-installation-evidence.sql:323` asserts exactly that.
-- A blanket grant in a mechanical sweep is how an internal helper quietly becomes a public
-- API, so the sweep grants nothing instead.

revoke execute on all functions in schema app from public;
