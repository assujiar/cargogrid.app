-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 1 of 5 of a representative repository-wide fix pass (Finance). See
-- docs/runtime/KNOWN_ISSUES.md's own ISS-2026-146 entry for the full disclosure history.
--
-- Root cause (as originally disclosed): many SECURITY DEFINER functions look a record
-- up by its own bare `id` (the caller does not yet know which tenant owns it), THEN
-- evaluate the actor's authority against the looked-up row's own real tenant_id, and on
-- denial raise 'insufficient_authority: ... for tenant %', interpolating that real,
-- genuine tenant_id -- disclosing it to a caller who has not yet been shown to have any
-- relationship to that tenant at all.
--
-- This migration (and its 4 sibling parts, same calendar batch, one per module) applies
-- the SAME already-established, already-precedented fix this repository has used twice
-- before for the identical defect class (ISS-2026-043, ISS-2026-048, ISS-2026-054 -- see
-- 20260730820000_harden_procurement_c05_tenant_disclosure_sweep_batch5.sql for the
-- origin of this exact pattern): fold `app.has_active_tenant_membership(<row>.tenant_id,
-- p_actor_auth_user_id)` into the SAME not-found branch the row-miss case already raises
-- (using the identical generic message and errcode='no_data_found' that a genuinely
-- nonexistent id already produces), so a caller with zero relationship to the record's
-- real tenant gets the identical error shape a nonexistent id would produce. Only a
-- confirmed member of that tenant ever reaches the specific insufficient_authority/
-- tenant_id-bearing line below it. No permission check is weakened -- the authority
-- check itself (evaluate_permission / check_*_authority) is completely unchanged; only
-- its ordering relative to a tenant-membership pre-check moved. errcode class is
-- unchanged for every already-legal caller (a same-tenant actor lacking specific role
-- authority still gets insufficient_privilege exactly as before); only a caller with NO
-- relationship to the tenant now gets no_data_found instead of
-- insufficient_privilege-with-a-real-UUID.
--
-- Five functions across these 5 parts (cancel_training_enrollment,
-- decide_training_enrollment, discard_finance_config_draft,
-- get_finance_config_version_items, set_finance_config_items) had no pre-existing "if
-- not found" guard on the specific SELECT that populates the disclosing row variable
-- (the row is reached via a FK-guaranteed-to-exist parent id, e.g.
-- v_enrollment.session_id / v_version.config_object_id, so the original author never
-- needed a not-found branch there) -- for these, a NEW guard was added immediately after
-- that SELECT, reusing the identical message/errcode shape the function's own sibling
-- not-found check already uses one statement above it (training_enrollment_not_found /
-- config_version_not_found), so the two failure paths remain byte-identical from the
-- caller's point of view.
--
-- Scope across all 5 parts: every genuinely at-risk (RISK_UNSCOPED_LOOKUP) occurrence
-- identified by scripts/security/classify-tenant-id-error-disclosure.ts within 12 source
-- files spanning Finance, HRIS, Procurement, Ticketing, and Platform Core (including the
-- exact 4 functions this entry's own Group 8 Tier C review live-reproduced against:
-- app.approve_dedicated_deployment_qualification, app.set_deployment_provisioning_
-- status, app.approve_region_assignment, app.set_scaling_recommendation_status, all in
-- Part 5, Platform Core) -- 120 distinct functions, 127 raise sites total. This is a
-- representative, not exhaustive, fix -- see docs/runtime/KNOWN_ISSUES.md's own
-- ISS-2026-146 entry for the full repository-wide count and the remainder still open.
--
-- Every function below is CREATE OR REPLACE against its CURRENT, live body (fetched
-- directly via pg_get_functiondef against the live project immediately before writing
-- this migration, not reconstructed from a possibly-stale local migration file) --
-- signatures are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_close_checklist_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_item app.finance_period_close_checklist_items;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.status = 'closed' then
    raise exception 'finance_period_closed: period % is closed -- checklist items on a closed period cannot be changed', p_period_id
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_period_close_checklist_items
  set satisfied = p_satisfied,
      satisfied_reason = p_reason,
      satisfied_by = case when p_satisfied then p_actor_label else null end,
      satisfied_at = case when p_satisfied then now() else null end
  where period_id = p_period_id and item_key = p_item_key
  returning * into v_item;

  if not found then
    raise exception 'finance_period_checklist_item_not_found: % on period %', p_item_key, p_period_id
      using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_finance_period_checklist_item',
    'app.finance_period_close_checklist_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
  v_batch app.finance_receipt_allocation_batches;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ar_open_items;
  v_total numeric := 0;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id for update;
  if not found or not app.has_active_tenant_membership(v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Edit', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_batch from app.finance_receipt_allocation_batches where tenant_id = v_receipt.tenant_id and receipt_id = p_receipt_id and idempotency_key = p_idempotency_key;
  if found then
    return v_receipt;
  end if;

  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_receipt_empty_allocation: at least one allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_receipt_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;
    v_total := v_total + v_amount;
  end loop;

  if v_total > v_receipt.unapplied_amount then
    raise exception 'finance_receipt_over_allocation: total allocation % exceeds unapplied amount % for receipt %', v_total, v_receipt.unapplied_amount, p_receipt_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_receipt_allocation_batches (tenant_id, receipt_id, idempotency_key, created_by)
  values (v_receipt.tenant_id, p_receipt_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'arOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;

    select * into v_open_item from app.finance_ar_open_items where id = v_open_item_id and tenant_id = v_receipt.tenant_id;
    if not found then
      raise exception 'finance_receipt_open_item_not_found: % is not a known AR open item for tenant %', v_open_item_id, v_receipt.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.customer_account_id <> v_receipt.customer_account_id then
      raise exception 'finance_receipt_customer_mismatch: AR open item % does not belong to receipt %''s own customer', v_open_item_id, p_receipt_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> v_receipt.currency then
      raise exception 'finance_receipt_currency_mismatch: AR open item % is % but receipt % is %', v_open_item_id, v_open_item.currency, p_receipt_id, v_receipt.currency
        using errcode = 'check_violation';
    end if;

    perform app.apply_finance_ar_allocation(v_open_item_id, v_amount, 'receipt', p_receipt_id, p_idempotency_key || ':' || v_open_item_id::text, p_actor_auth_user_id, p_actor_label);

    insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, created_by)
    values (v_receipt.tenant_id, p_receipt_id, v_batch.id, v_open_item_id, v_amount, p_actor_label);
  end loop;

  -- FIN-202: debit cash for the total received; credit AR control for the
  -- same total -- one control-account line for the whole batch, matching
  -- app.finance_receipt_allocations' own already-established per-item
  -- lineage rows for open-item-level detail.
  perform app.post_finance_subledger_batch(
    v_receipt.tenant_id, v_receipt.company_id, 'receipt_allocation', v_batch.id, v_receipt.receipt_date, v_receipt.currency,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'debit', 'amount', v_total),
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'credit', 'amount', v_total)
    ),
    p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipts set allocated_amount = allocated_amount + v_total where id = p_receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_receipt.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, jsonb_build_object('total', v_total, 'batchId', v_batch.id)
  );

  return v_receipt;
end;
$function$;

CREATE OR REPLACE FUNCTION app.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
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
$function$;

CREATE OR REPLACE FUNCTION app.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'settled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not settled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: settlement amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ap_over_settlement: settlement % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount + p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'settled', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'allocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not allocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: allocation amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ar_over_allocation: allocation % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount + p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'allocated', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if p_evidence_reference_file_id is null and (p_evidence_note is null or length(trim(p_evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: at least one of an evidence file or a non-empty evidence note is required'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set evidence_reference_file_id = coalesce(p_evidence_reference_file_id, evidence_reference_file_id),
        evidence_note = coalesce(p_evidence_note, evidence_note)
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_finance_tax_rule_evidence',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, jsonb_build_object('evidenceReferenceFileId', v_rule.evidence_reference_file_id)
  );

  return v_rule;
end;
$function$;

CREATE OR REPLACE FUNCTION app.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
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
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
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
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;
  if not app.has_active_tenant_membership(v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.discard_config_draft(p_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found or not app.has_active_tenant_membership(v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status not in ('draft', 'submitted') then
    raise exception 'finance_correction_not_cancellable: correction % is %, only a draft or submitted correction may be discarded', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections
    set status = 'discarded', discard_reason = p_reason, discarded_by = p_actor_label, discarded_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_correction_draft',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
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
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status not in ('draft', 'submitted') then
    raise exception 'finance_invoice_not_cancellable: invoice % is %, only a draft or submitted invoice may be discarded', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_invoice_draft',
    'app.finance_invoices', v_invoice.id, 'success', p_reason, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if v_journal.status not in ('draft', 'submitted') then
    raise exception 'finance_journal_not_cancellable: journal % is %, only a draft or submitted journal may be discarded', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions set status = 'archived', archived_reason = p_reason where id = p_rule_id returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_tax_rule_draft',
    'app.finance_tax_rule_versions', v_rule.id, 'success', p_reason, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status not in ('draft', 'submitted') then
    raise exception 'finance_vendor_bill_not_cancellable: bill % is %, only a draft or submitted bill may be discarded', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_vendor_bill_draft',
    'app.finance_vendor_bills', v_bill.id, 'success', p_reason, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
  v_child_count integer;
  v_referenced_by_posting_map boolean := false;
  v_row record;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_account_authority('View', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (
      select 1 from jsonb_each(v_row.items) e
      where (e.value ->> 'accountCodeRef') = v_account.code
    ) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;

  return jsonb_build_object(
    'accountId', v_account.id,
    'code', v_account.code,
    'activeChildAccountCount', v_child_count,
    'referencedByPublishedPostingMap', v_referenced_by_posting_map
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_item_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_item_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;
  if not app.has_active_tenant_membership(v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return coalesce(
    (select jsonb_object_agg(key, value) from app.config_items where config_version_id = p_version_id),
    '{}'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_correction_journal app.finance_journals;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found or not app.has_active_tenant_membership(v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('View', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if v_correction.correction_journal_id is not null then
    select * into v_correction_journal from app.finance_journals where id = v_correction.correction_journal_id;
  end if;

  return jsonb_build_object(
    'correction', to_jsonb(v_correction),
    'originalJournal', to_jsonb(v_original),
    'correctionJournal', case when v_correction.correction_journal_id is not null then to_jsonb(v_correction_journal) else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_invoice_lines
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('View', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_invoice_lines where invoice_id = p_invoice_id order by line_number asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied jsonb;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(item_key), '[]'::jsonb) into v_unsatisfied
  from app.finance_period_close_checklist_items
  where period_id = p_period_id and required and not satisfied;

  return jsonb_build_object(
    'periodId', p_period_id,
    'status', v_period.status,
    'ready', (v_unsatisfied = '[]'::jsonb),
    'unsatisfiedRequiredItems', v_unsatisfied
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_lock_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found or not app.has_active_tenant_membership(v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('View', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_period_lock_events where lock_id = p_lock_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_transitions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.finance_period_transitions where period_id = p_period_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_receipt_allocations
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found or not app.has_active_tenant_membership(v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_receipt_allocations where receipt_id = p_receipt_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_settlement_allocations
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('View', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_settlement_allocations where settlement_id = p_settlement_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_subledger_lines
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_batch app.finance_subledger_batches;
begin
  select * into v_batch from app.finance_subledger_batches where id = p_batch_id;
  if not found or not app.has_active_tenant_membership(v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_subledger_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_subledger_authority('View', v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_subledger_lines where batch_id = p_batch_id order by line_number asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_vendor_bill_lines
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('View', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_vendor_bill_lines where bill_id = p_bill_id order by line_number asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_reconciliation_exceptions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.finance_reconciliation_runs;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('View', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_reconciliation_exceptions where run_id = p_run_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found or not app.has_active_tenant_membership(v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Edit', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_matched_source_type not in ('receipt', 'settlement', 'manual') then
    raise exception 'finance_cash_invalid_match_source_type: % is not a supported match source type', p_matched_source_type
      using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'unmatched' then
    raise exception 'finance_cash_transaction_not_unmatched: transaction % is % not unmatched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'matched', matched_source_type = p_matched_source_type, matched_source_id = p_matched_source_id,
        matched_by = p_actor_label, matched_at = now(), unmatch_reason = null
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'match_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', null, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ap_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ar_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found or not app.has_active_tenant_membership(v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Edit', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_lock.status <> 'locked' then
    raise exception 'finance_period_lock_not_locked: lock % is % not locked', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopen_requested', reopen_reason = p_reason, reopen_requested_by = p_actor_label, reopen_requested_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopen_requested', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

CREATE OR REPLACE FUNCTION app.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.finance_reconciliation_exceptions;
begin
  select * into v_exception from app.finance_reconciliation_exceptions where id = p_exception_id for update;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_reconciliation_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_resolution_reason is null or length(trim(p_resolution_reason)) = 0 then
    raise exception 'finance_reconciliation_resolution_reason_required: a non-empty resolution reason is required' using errcode = 'check_violation';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'finance_reconciliation_exception_not_open: exception % is % not open', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_exceptions
    set status = 'resolved', resolution_reason = p_resolution_reason, resolved_by = p_actor_label, resolved_at = now()
    where id = p_exception_id
    returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_finance_reconciliation_exception',
    'app.finance_reconciliation_exceptions', v_exception.id, 'success', p_resolution_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_items
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found or not app.has_active_tenant_membership(v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = v_receipt.tenant_id
      and customer_account_id = v_receipt.customer_account_id
      and currency = v_receipt.currency
      and status <> 'paid'
      and not is_held
    order by due_date asc
    limit 200;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;
  if not app.has_active_tenant_membership(v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.set_config_items(p_version_id, p_items, p_actor_auth_user_id, p_actor_label);
end;
$function$;

CREATE OR REPLACE FUNCTION app.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
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
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found or not app.has_active_tenant_membership(v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'draft' then
    raise exception 'finance_correction_not_draft: correction % is % not draft', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_correction_for_approval',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'finance_invoice_not_draft: invoice % is % not draft', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_invoice_for_approval',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Edit', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'draft' then
    raise exception 'finance_settlement_not_draft: settlement % is % not draft', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_settlement_for_approval',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'draft' then
    raise exception 'finance_vendor_bill_not_draft: bill % is % not draft', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_vendor_bill_for_approval',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

