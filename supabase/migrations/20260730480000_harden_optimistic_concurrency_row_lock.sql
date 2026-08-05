-- CG-S10-ATW-032 (post-Prompt-248 audit) — lost update on 64 optimistic-concurrency paths.
--
-- The repository's standard optimistic-concurrency shape is:
--
--   select * into v_row from app.<table> where id = p_id;      -- UNLOCKED read
--   if v_row.record_version <> p_expected_version then
--     raise exception 'stale_version: ...';
--   end if;
--   ...
--   update app.<table> set ... where id = p_id;                 -- no version predicate
--
-- The version itself is maintained correctly — every one of these tables carries a
-- `BEFORE UPDATE ... FOR EACH ROW` touch trigger that does
-- `new.record_version := old.record_version + 1` — so the value the check reads is real.
-- The defect is that nothing holds the row between the check and the write.
--
-- Two concurrent callers both read version 1, both pass the check, and both UPDATE by id.
-- The first commits (version -> 2), the second commits (version -> 3) and silently
-- overwrites it. Neither caller is told anything. On `app.review_epod_capture` that is one
-- reviewer's delivery decision overwriting another's; on `app.decide_actual_cost` it is one
-- approver's cost decision overwriting another's; on the Finance `approve_*`/`post_*`
-- family it is an approval or posting decision lost after the fact.
--
-- ===========================================================================
-- Scope: 64 of 111, and why the other 47 are already correct
-- ===========================================================================
--
-- 111 functions take `p_expected_version` and issue an UPDATE without repeating the
-- version predicate. 47 of those already `select ... for update`, which holds the row from
-- the check through to commit and makes the pattern sound — those are NOT touched.
-- The 64 repaired here are exactly the ones with neither the lock nor the predicate.
--
-- ===========================================================================
-- Repair: lock the row at the check, rather than re-checking at the write
-- ===========================================================================
--
-- Each guarded `select * into ... where ...` immediately preceding the version comparison
-- gains `for update`. Chosen over adding `record_version = p_expected_version` to each
-- UPDATE because:
--
--   * it matches what 47 sibling functions in this same codebase already do, so it makes
--     the family uniform instead of introducing a second convention;
--   * the version predicate alone would still need every one of the 64 call sites to then
--     handle the zero-rows-updated case and raise `stale_version` — 64 further chances to
--     get one wrong, where the lock makes the EXISTING check correct with no new control
--     flow at all;
--   * it also closes the check-then-act window for the other invariants these functions
--     evaluate between the read and the write (status matrices, quantity aggregates), not
--     just the version.
--
-- Deadlock risk is unchanged in kind: these are single-row locks taken on the function's
-- own target row, in the same order as the 47 functions that already do this.
--
-- Every body below is its own live `pg_get_functiondef` output with ONLY that one `for
-- update` added. No other statement, signature, volatility, security attribute,
-- search_path, grant or comment changes.
--
-- Found by the `ATW-031` audit fan-out (claimed against `review_epod_capture` and
-- `decide_actual_cost`), then confirmed and generalised by direct inspection: the claim was
-- real, and the class was 32x larger than the two functions it named.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

CREATE OR REPLACE FUNCTION app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'submitted' then
    raise exception 'finance_correction_not_submitted: correction % is % not submitted', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'submitted' then
    raise exception 'finance_invoice_not_submitted: invoice % is % not submitted', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'submitted' then
    raise exception 'finance_journal_not_submitted: journal % is % not submitted', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_lock.status <> 'reopen_requested' then
    raise exception 'finance_period_lock_not_reopen_requested: lock % is % not reopen_requested', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;
  if p_window_hours is null or p_window_hours <= 0 or p_window_hours > 720 then
    raise exception 'finance_period_reopen_window_invalid: % is not a valid reopen window (1-720 hours)', p_window_hours
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopened', reopen_approved_by = p_actor_label, reopened_at = now(), reopen_window_expires_at = now() + make_interval(hours => p_window_hours)
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopened', v_lock.reopen_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'submitted' then
    raise exception 'finance_settlement_not_submitted: settlement % is % not submitted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
  v_overlap_count integer;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Approve', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rule.tenant_id
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
  if v_rule.is_example_fixture then
    raise exception 'finance_tax_rule_example_fixture_not_activatable: rule % is a seeded illustrative example and can never be approved -- create a fresh evidence-backed draft', p_rule_id
      using errcode = 'check_violation';
  end if;
  if v_rule.evidence_reference_file_id is null and (v_rule.evidence_note is null or length(trim(v_rule.evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: rule % has no attached SME evidence', p_rule_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_overlap_count
    from app.finance_tax_rule_versions r
    where r.tax_code_id = v_rule.tax_code_id
      and coalesce(r.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rule.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and r.status = 'approved'
      and r.id <> v_rule.id
      and r.effective_from <= coalesce(v_rule.effective_to, 'infinity'::date)
      and coalesce(r.effective_to, 'infinity'::date) >= v_rule.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_tax_rule_overlap: an approved rule for this tax code and scope already covers an overlapping effective window'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set status = 'approved', approved_by = p_actor_label, approved_at = now()
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_tax_rule',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'submitted' then
    raise exception 'finance_vendor_bill_not_submitted: bill % is % not submitted', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, jsonb_build_object('varianceStatus', v_bill.variance_status), to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

CREATE OR REPLACE FUNCTION app.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.cancel_wms_inbound(p_inbound_order_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status = 'cancelled' then
    return v_order;
  end if;

  if exists (select 1 from app.wms_receipt_sessions where inbound_order_id = p_inbound_order_id and status <> 'cancelled') then
    raise exception 'has_receipt_progress: inbound order % has an active or completed receipt session -- cancel or reconcile it first', p_inbound_order_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel an inbound order' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set status = 'cancelled', cancelled_reason = p_reason where id = p_inbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', p_reason, null, null
  );

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE plpgsql
AS $function$
declare
  v_run app.finance_reconciliation_runs;
  v_open_exceptions integer;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id for update;
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: run % expected version % but found %', p_run_id, p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_reconciliation_certify_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_run.status = 'certified' then
    return v_run;
  end if;

  select count(*) into v_open_exceptions from app.finance_reconciliation_exceptions where run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'finance_reconciliation_unexplained_variance: run % has % unresolved exception(s)', p_run_id, v_open_exceptions
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_runs
    set status = 'certified', certify_reason = p_reason, certified_by = p_actor_label, certified_at = now()
    where id = p_run_id
    returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'certify_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', p_reason, null, to_jsonb(v_run)
  );

  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION app.confirm_wms_inbound(p_inbound_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_readiness app.wms_inbound_readiness;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status <> 'scheduled' then
    raise exception 'invalid_transition: % must be scheduled to confirm, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;

  v_readiness := app.get_wms_inbound_readiness(p_inbound_order_id, p_actor_auth_user_id);
  if not v_readiness.ready then
    raise exception 'inbound_not_ready: % is not ready to confirm (has_lines=%, warehouse_active=%, owner_active=%, invalid_line_count=%)',
      p_inbound_order_id, v_readiness.has_lines, v_readiness.warehouse_active, v_readiness.owner_active, v_readiness.invalid_line_count
      using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set status = 'confirmed' where id = p_inbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', null, null, null
  );

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.consume_vehicle_capacity_reservation(p_reservation_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id for update;
  if not found then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'check_violation';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: reservation % is % -- only a held reservation may be consumed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vehicle_capacity_reservations set status = 'consumed' where id = p_reservation_id
    returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'consume_vehicle_capacity_reservation',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null, jsonb_build_object('shipment_leg_id', v_reservation.shipment_leg_id)
  );

  return v_reservation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decide_actual_cost(p_actual_cost_id uuid, p_decision text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.shipment_actual_costs;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'actual_cost_invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id for update;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'submitted' then
    raise exception 'invalid_transition: actual cost % is % and cannot be decided', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'actual_cost_rejection_reason_required: a reason is required to reject' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs
  set status = p_decision,
      approved_by_auth_user_id = case when p_decision = 'approved' then p_actor_auth_user_id else null end,
      approved_at = case when p_decision = 'approved' then now() else null end,
      rejection_reason = case when p_decision = 'rejected' then p_reason else null end
  where id = p_actual_cost_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
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
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
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
  if v_settlement.status not in ('draft', 'submitted') then
    raise exception 'finance_settlement_not_cancellable: settlement % is %, only a draft or submitted settlement may be discarded', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_settlement_draft',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
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
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'approved' then
    raise exception 'finance_settlement_not_approved: settlement % is % not approved', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements
    set status = 'executed', execution_reference = p_execution_reference, executed_by = p_actor_label, executed_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_invoice.total_amount, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the full total; credit revenue for the
  -- subtotal; credit each tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured).
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_invoice.total_amount, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and output_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_invoices
    set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
        posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
    where id = p_invoice_id
    returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

CREATE OR REPLACE FUNCTION app.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.move_org_unit(p_id uuid, p_new_parent_id uuid, p_expected_version integer, p_requested_by text)
 RETURNS app.org_units
 LANGUAGE plpgsql
AS $function$
declare
  v_current app.org_units;
  v_updated app.org_units;
  v_old_path_prefix uuid[];
  v_new_path_prefix uuid[];
  v_depth_delta integer;
begin
  select * into v_current from app.org_units where id = p_id for update;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  v_old_path_prefix := v_current.path || v_current.id;

  update app.org_units
  set parent_id = p_new_parent_id
  where id = p_id
  returning * into v_updated;

  v_new_path_prefix := v_updated.path || v_updated.id;
  v_depth_delta := v_updated.depth - v_current.depth;

  -- Cascade: every descendant's path had v_old_path_prefix as a leading segment;
  -- splice in the new prefix in its place and shift depth by the same delta. Bounded by
  -- this node's actual descendant count, not a recursive per-row walk.
  update app.org_units d
  set path = v_new_path_prefix || d.path[array_length(v_old_path_prefix, 1) + 1 : array_length(d.path, 1)],
      depth = d.depth + v_depth_delta
  where d.path @> array[p_id];

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_parent_id, after_parent_id, requested_by)
  values (p_id, v_current.tenant_id, 'move', v_current.parent_id, p_new_parent_id, p_requested_by);

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.move_warehouse_location(p_location_id uuid, p_new_parent_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_current app.warehouse_locations;
  v_updated app.warehouse_locations;
  v_warehouse app.warehouses;
  v_old_path_prefix uuid[];
  v_new_path_prefix uuid[];
  v_depth_delta integer;
begin
  select * into v_current from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_current.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_current.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_current.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_current.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot move location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'draft' then
    raise exception 'location_not_draft: % is % -- only a draft (empty, unused) location may be moved', p_location_id, v_current.status
      using errcode = 'check_violation';
  end if;

  v_old_path_prefix := v_current.path || v_current.id;

  update app.warehouse_locations
  set parent_id = p_new_parent_id
  where id = p_location_id
  returning * into v_updated;

  v_new_path_prefix := v_updated.path || v_updated.id;
  v_depth_delta := v_updated.depth - v_current.depth;

  update app.warehouse_locations d
  set path = v_new_path_prefix || d.path[array_length(v_old_path_prefix, 1) + 1 : array_length(d.path, 1)],
      depth = d.depth + v_depth_delta
  where d.path @> array[p_location_id];

  perform app.capture_audit_event(
    v_current.tenant_id, p_actor_auth_user_id, p_actor_label, 'move_warehouse_location',
    'app.warehouse_locations', v_updated.id, 'success', null,
    jsonb_build_object('parent_id', v_current.parent_id), jsonb_build_object('parent_id', p_new_parent_id)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.override_route_planning_selection(p_scenario_id uuid, p_candidate_plan_id uuid, p_override_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_selected_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_candidate app.route_planning_candidate_plans;
  v_prior app.route_planning_selected_plans;
  v_selection app.route_planning_selected_plans;
begin
  if p_override_reason is null or length(trim(p_override_reason)) = 0 then
    raise exception 'override_reason_required: a non-empty reason is required to override a selection' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id for update;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status not in ('ready', 'selected') then
    raise exception 'scenario_not_selectable: scenario % is % and has no candidates to select from', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.route_planning_candidate_plans where id = p_candidate_plan_id and scenario_id = p_scenario_id;
  if not found then
    raise exception 'candidate_not_found: % is not a candidate of scenario %', p_candidate_plan_id, p_scenario_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Update-before-insert ordering (see app.select_route_planning_plan's own
  -- identical comment above -- the same transient partial-unique-index violation
  -- applies here).
  select * into v_prior from app.route_planning_selected_plans where scenario_id = p_scenario_id and is_current;
  if v_prior.id is not null then
    update app.route_planning_selected_plans set is_current = false where id = v_prior.id;
  end if;

  insert into app.route_planning_selected_plans (tenant_id, scenario_id, candidate_plan_id, is_override, override_reason, selected_by)
  values (v_scenario.tenant_id, p_scenario_id, p_candidate_plan_id, true, p_override_reason, p_actor_label)
  returning * into v_selection;

  if v_prior.id is not null then
    update app.route_planning_selected_plans set superseded_by_id = v_selection.id where id = v_prior.id;
  end if;

  update app.route_planning_scenarios set status = 'selected' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_route_planning_selection',
    'app.route_planning_selected_plans', v_selection.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'candidate_plan_id', p_candidate_plan_id, 'override_reason', p_override_reason, 'was_feasible', v_candidate.feasible)
  );

  return v_selection;
end;
$function$;

CREATE OR REPLACE FUNCTION app.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
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
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_journal app.finance_journals;
  v_batch app.finance_subledger_batches;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if v_correction.status = 'posted' then
    return v_correction;
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'approved' then
    raise exception 'finance_correction_not_approved: correction % is % not approved', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if not found or v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is no longer posted', v_correction.original_journal_id
      using errcode = 'check_violation';
  end if;

  if v_correction.correction_type = 'reversal' then
    for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original.id order by line_number asc loop
      v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
    end loop;
  else
    v_lines := v_correction.adjustment_lines;
  end if;

  select * into v_journal from app.create_and_post_finance_system_journal(
    v_correction.tenant_id, v_correction.company_id, 'correction', v_correction.id, v_correction.correction_date,
    v_original.currency, v_lines, p_actor_auth_user_id, p_actor_label, 'gl'
  );

  if v_correction.correction_type = 'reversal' and v_original.source_type = 'subledger' then
    update app.finance_subledger_batches set status = 'reversed' where gl_journal_id = v_original.id and status = 'posted' returning * into v_batch;
  end if;

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
AS $function$
declare
  v_journal app.finance_journals;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_lines jsonb;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'approved' then
    raise exception 'finance_journal_not_approved: journal % is % not approved', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direction', direction, 'amount', amount)), '[]'::jsonb)
    into v_lines
    from app.finance_journal_lines where journal_id = p_journal_id;
  perform app.validate_finance_journal_line_balance(v_lines);

  select * into v_period from app.resolve_finance_period_for_date(v_journal.tenant_id, v_journal.company_id, v_journal.journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', v_journal.journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_journal.journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(v_journal.tenant_id, v_journal.company_id, v_period.period_id, 'gl');

  v_year := extract(year from v_journal.journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_journal.tenant_id, v_journal.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_journals
    set status = 'posted', journal_number = v_number, posting_period_id = v_period.period_id, posted_by = p_actor_label, posted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_allocation app.finance_settlement_allocations;
  v_lines jsonb;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'executed' then
    raise exception 'finance_settlement_not_executed: settlement % is % not executed', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.apply_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, 'settlement', v_settlement.id,
      v_settlement.idempotency_key || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- FIN-202: debit AP control for the allocated total (plus a governed fee
  -- expense debit when a fee applies); credit cash for the full total.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'debit', 'amount', v_settlement.allocated_amount)
  );
  if v_settlement.fee_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'debit', 'amount', v_settlement.fee_amount));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'credit', 'amount', v_settlement.total_amount));

  perform app.post_finance_subledger_batch(
    v_settlement.tenant_id, v_settlement.company_id, 'settlement', v_settlement.id, v_settlement.settlement_date, v_settlement.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  v_year := extract(year from v_settlement.settlement_date)::integer;
  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_settlement.tenant_id, v_settlement.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'SETL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_settlements
    set status = 'posted', settlement_number = v_number, posting_period_id = v_period.period_id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
AS $function$
declare
  v_bill app.finance_vendor_bills;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ap_item app.finance_ap_open_items;
  v_lines jsonb;
  v_tax_line app.finance_vendor_bill_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'finance_vendor_bill_not_approved: bill % is % not approved', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_bill.tenant_id, v_bill.company_id, v_bill.bill_date);
  if not found then
    raise exception 'finance_vendor_bill_period_not_found: no fiscal period covers %', v_bill.bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_vendor_bill_period_not_open: fiscal period % for % is not open', v_period.period_code, v_bill.bill_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from v_bill.bill_date)::integer;
  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_bill.tenant_id, v_bill.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'BILL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  select * into v_ap_item from app.post_finance_ap_open_item(
    v_bill.tenant_id, v_bill.company_id, v_bill.vendor_master_id, 'vendor_bill', v_bill.id,
    v_bill.currency, v_bill.total_amount, v_bill.bill_date, v_bill.due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit expense for the subtotal; debit each tax line's own
  -- governed recoverable account (or the input_tax_default posting-map key
  -- when none is configured); credit AP control for the full total.
  v_lines := '[]'::jsonb;
  if v_bill.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', v_bill.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and recoverable_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'input_tax_default', 'direction', 'debit', 'amount', v_tax_line.amount));
    end if;
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_bill.total_amount, 'openItemType', 'ap_open_item', 'openItemId', v_ap_item.id));

  perform app.post_finance_subledger_batch(
    v_bill.tenant_id, v_bill.company_id, 'vendor_bill', v_bill.id, v_bill.bill_date, v_bill.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_vendor_bills
    set status = 'posted', bill_number = v_number, posting_period_id = v_period.period_id, ap_open_item_id = v_ap_item.id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_bill_id
    returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_document_requirement_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.document_requirement_definitions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.document_requirement_definitions;
  v_superseded app.document_requirement_definitions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.document_requirement_definitions where id = p_version_id for update;
  if not found then
    raise exception 'document_requirement_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'concurrent_modification: document requirement % has moved from expected version % to %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: document requirement % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_superseded
  from app.document_requirement_definitions
  where tenant_id = v_version.tenant_id and status = 'published'
    and coalesce(mode, '') = coalesce(v_version.mode, '') and coalesce(service_type, '') = coalesce(v_version.service_type, '')
    and applicable_status = v_version.applicable_status and party = v_version.party and document_type_code = v_version.document_type_code;
  if found then
    update app.document_requirement_definitions set status = 'archived' where id = v_superseded.id;
  end if;

  update app.document_requirement_definitions
  set status = 'published', supersedes_version_id = v_superseded.id
  where id = p_version_id
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_document_requirement_version',
    'app.document_requirement_definitions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reassign_user_org_unit(p_id uuid, p_new_org_unit_id uuid, p_expected_version integer, p_requested_by text)
 RETURNS app.users
 LANGUAGE plpgsql
AS $function$
declare
  v_current app.users;
  v_updated app.users;
  v_org app.org_units;
begin
  select * into v_current from app.users where id = p_id for update;
  if not found then
    raise exception 'user_not_found: no user %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'user_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  if p_new_org_unit_id is not null then
    select * into v_org from app.org_units where id = p_new_org_unit_id;
    if not found or v_org.tenant_id <> v_current.tenant_id then
      raise exception 'cross_tenant_org_unit: org unit % does not belong to tenant %', p_new_org_unit_id, v_current.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.users set org_unit_id = p_new_org_unit_id where id = p_id returning * into v_updated;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, requested_by)
  values (p_id, v_current.tenant_id, 'org_reassign', p_requested_by);

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ap_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ar_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.release_vehicle_capacity_reservation(p_reservation_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to release a capacity reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id for update;
  if not found then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'check_violation';
  end if;
  if v_reservation.status = 'released' then
    raise exception 'invalid_transition: reservation % is already released', p_reservation_id using errcode = 'check_violation';
  end if;

  update app.vehicle_capacity_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id
    returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_vehicle_capacity_reservation',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', v_reservation.shipment_leg_id, 'reason', p_reason)
  );

  return v_reservation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if v_lock.status = 'locked' then
    return v_lock;
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.finance_period_locks
    set status = 'locked', relocked_by = p_actor_label, relocked_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'relocked', null, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'relock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

CREATE OR REPLACE FUNCTION app.rename_org_unit(p_id uuid, p_new_name text, p_expected_version integer, p_requested_by text)
 RETURNS app.org_units
 LANGUAGE plpgsql
AS $function$
declare
  v_current app.org_units;
  v_updated app.org_units;
begin
  select * into v_current from app.org_units where id = p_id for update;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  update app.org_units set name = p_new_name where id = p_id returning * into v_updated;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_name, after_name, requested_by)
  values (p_id, v_current.tenant_id, 'rename', v_current.name, p_new_name, p_requested_by);

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.reschedule_wms_inbound_appointment(p_inbound_order_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status not in ('scheduled', 'confirmed') then
    raise exception 'invalid_transition: % must be scheduled or confirmed to reschedule, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;
  if p_window_start is null or p_window_end is null or p_window_end <= p_window_start then
    raise exception 'invalid_appointment_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set
    appointment_window_start = p_window_start,
    appointment_window_end = p_window_end,
    expected_date = p_window_start::date
  where id = p_inbound_order_id
  returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_wms_inbound_appointment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('window_start', p_window_start, 'window_end', p_window_end)
  );

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_exceptions
 LANGUAGE plpgsql
AS $function$
declare
  v_exception app.finance_reconciliation_exceptions;
begin
  select * into v_exception from app.finance_reconciliation_exceptions where id = p_exception_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.review_epod_capture(p_capture_id uuid, p_decision text, p_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  if p_decision not in ('approved', 'revision_requested') then
    raise exception 'epod_invalid_decision: % is not one of approved/revision_requested', p_decision using errcode = 'check_violation';
  end if;

  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'submitted' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be reviewed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'revision_requested' and (p_notes is null or length(trim(p_notes)) = 0) then
    raise exception 'epod_revision_reason_required: notes are required when requesting a revision' using errcode = 'check_violation';
  end if;

  update app.epod_captures
  set status = p_decision, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now(), review_notes = p_notes
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revoke_warehouse_customer_eligibility(p_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_customer_eligibility
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_row app.warehouse_customer_eligibility;
  v_warehouse app.warehouses;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke warehouse customer eligibility' using errcode = 'check_violation';
  end if;

  select * into v_row from app.warehouse_customer_eligibility where id = p_id;
  if not found then
    raise exception 'eligibility_not_found: %', p_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_row.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_row.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, v_row.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: eligibility % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'check_violation';
  end if;
  if v_row.status = 'revoked' then
    raise exception 'invalid_transition: eligibility % is already revoked', p_id using errcode = 'check_violation';
  end if;

  update app.warehouse_customer_eligibility set status = 'revoked', revoked_at = now(), revoked_reason = p_reason where id = p_id returning * into v_row;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_warehouse_customer_eligibility',
    'app.warehouse_customer_eligibility', v_row.id, 'success', p_reason, null,
    jsonb_build_object('warehouse_id', v_row.warehouse_id, 'customer_account_id', v_row.customer_account_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.schedule_wms_inbound_appointment(p_inbound_order_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_line_count integer;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'invalid_transition: % must be draft to schedule an appointment, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;
  if p_window_start is null or p_window_end is null or p_window_end <= p_window_start then
    raise exception 'invalid_appointment_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  select count(*) into v_line_count from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id;
  if v_line_count = 0 then
    raise exception 'no_lines: % has no lines -- add at least one line before scheduling', p_inbound_order_id using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set
    appointment_window_start = p_window_start,
    appointment_window_end = p_window_end,
    expected_date = p_window_start::date,
    status = 'scheduled'
  where id = p_inbound_order_id
  returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'schedule_wms_inbound_appointment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('window_start', p_window_start, 'window_end', p_window_end)
  );

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.select_route_planning_plan(p_scenario_id uuid, p_candidate_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_selected_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_candidate app.route_planning_candidate_plans;
  v_prior app.route_planning_selected_plans;
  v_selection app.route_planning_selected_plans;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id for update;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status not in ('ready', 'selected') then
    raise exception 'scenario_not_selectable: scenario % is % and has no candidates to select from', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.route_planning_candidate_plans where id = p_candidate_plan_id and scenario_id = p_scenario_id;
  if not found then
    raise exception 'candidate_not_found: % is not a candidate of scenario %', p_candidate_plan_id, p_scenario_id using errcode = 'no_data_found';
  end if;

  if not v_candidate.feasible then
    raise exception 'candidate_infeasible: candidate % is infeasible and requires app.override_route_planning_selection', p_candidate_plan_id
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

  -- Update-before-insert ordering (app.reassign_resource's own precedent, OPS-172,
  -- also followed by app.assign_device_to_vehicle, ATW-223): inserting the new
  -- is_current row before marking the prior one false would transiently double-book
  -- the partial unique index route_planning_selected_plans_current_scenario_unique.
  select * into v_prior from app.route_planning_selected_plans where scenario_id = p_scenario_id and is_current;
  if v_prior.id is not null then
    update app.route_planning_selected_plans set is_current = false where id = v_prior.id;
  end if;

  insert into app.route_planning_selected_plans (tenant_id, scenario_id, candidate_plan_id, selected_by)
  values (v_scenario.tenant_id, p_scenario_id, p_candidate_plan_id, p_actor_label)
  returning * into v_selection;

  if v_prior.id is not null then
    update app.route_planning_selected_plans set superseded_by_id = v_selection.id where id = v_prior.id;
  end if;

  update app.route_planning_scenarios set status = 'selected' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_route_planning_plan',
    'app.route_planning_selected_plans', v_selection.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'candidate_plan_id', p_candidate_plan_id)
  );

  return v_selection;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_item_master_status(p_item_master_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_masters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid item master status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_item from app.item_masters where id = p_item_master_id for update;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if v_item.status = p_new_status then
    return v_item;
  end if;
  if p_new_status = 'inactive' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a reason is required to deactivate an item master' using errcode = 'check_violation';
  end if;

  update app.item_masters set status = p_new_status where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_item_master_status',
    'app.item_masters', v_item.id, 'success', p_reason, null,
    jsonb_build_object('new_status', p_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_org_unit_status(p_id uuid, p_new_status text, p_expected_version integer, p_reason text, p_requested_by text)
 RETURNS app.org_units
 LANGUAGE plpgsql
AS $function$
declare
  v_current app.org_units;
  v_updated app.org_units;
  v_active_children integer;
begin
  select * into v_current from app.org_units where id = p_id for update;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  if v_current.status = p_new_status then
    return v_current;
  end if;

  if p_new_status = 'inactive' then
    select count(*) into v_active_children
    from app.org_units
    where parent_id = p_id and status = 'active';

    if v_active_children > 0 then
      raise exception 'org_unit_has_active_children: % cannot be deactivated while % active child/children exist', p_id, v_active_children
        using errcode = 'check_violation';
    end if;
  end if;

  update app.org_units set status = p_new_status where id = p_id returning * into v_updated;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_status, after_status, reason, requested_by)
  values (p_id, v_current.tenant_id, 'status_change', v_current.status, p_new_status, p_reason, p_requested_by);

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_warehouse_location_status(p_location_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_active_child_count integer;
begin
  if p_new_status not in ('draft', 'active', 'inactive') then
    raise exception 'invalid_status: % is not a valid location status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if v_location.status = p_new_status then
    return v_location;
  end if;

  if p_new_status = 'active' and v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot activate a location under it', v_location.warehouse_id using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a location' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_child_count from app.warehouse_locations where parent_id = p_location_id and status in ('draft', 'active');
    if v_active_child_count > 0 then
      raise exception 'location_has_active_children: % cannot be deactivated while % draft/active child location(s) exist', p_location_id, v_active_child_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_locations set status = p_new_status where id = p_location_id returning * into v_location;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_location_status',
    'app.warehouse_locations', v_location.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_location;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_warehouse_status(p_warehouse_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_active_zone_count integer;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid warehouse status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id for update;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if v_warehouse.status = p_new_status then
    return v_warehouse;
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a warehouse' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_zone_count from app.warehouse_zones where warehouse_id = p_warehouse_id and status in ('active', 'on_hold');
    if v_active_zone_count > 0 then
      raise exception 'warehouse_has_active_zones: % cannot be deactivated while % active/on-hold zone(s) exist', p_warehouse_id, v_active_zone_count
        using errcode = 'check_violation';
    end if;
    select count(*) into v_active_location_count
      from app.warehouse_locations where warehouse_id = p_warehouse_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'warehouse_has_active_locations: % cannot be deactivated while % draft/active location(s) exist (including zoneless root-level locations)', p_warehouse_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouses set status = p_new_status where id = p_warehouse_id returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_status',
    'app.warehouses', v_warehouse.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_warehouse;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_warehouse_zone_status(p_zone_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_zones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive', 'on_hold') then
    raise exception 'invalid_status: % is not a valid zone status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if v_zone.status = p_new_status then
    return v_zone;
  end if;
  if p_new_status in ('inactive', 'on_hold') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to set a zone to %', p_new_status using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    select count(*) into v_active_location_count
      from app.warehouse_locations where zone_id = p_zone_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'zone_has_active_locations: % cannot be deactivated while % draft/active location(s) exist under it', p_zone_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_zones set status = p_new_status where id = p_zone_id returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_zone_status',
    'app.warehouse_zones', v_zone.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_zone;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_actual_cost(p_actual_cost_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_component_count integer;
  v_updated app.shipment_actual_costs;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id for update;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot be submitted', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id;
  if v_component_count = 0 then
    raise exception 'actual_cost_no_components: at least one cost component is required before submission' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs set status = 'submitted' where id = p_actual_cost_id returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_epod_capture(p_capture_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_photo_id uuid;
  v_scan_status text;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be submitted', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if v_capture.receiver_name is null or length(trim(v_capture.receiver_name)) = 0 then
    raise exception 'epod_missing_receiver: a receiver name is required before submission' using errcode = 'check_violation';
  end if;
  if v_capture.signature_file_id is null and array_length(v_capture.photo_file_ids, 1) is null then
    raise exception 'epod_missing_evidence: at least one of a signature or a photo is required before submission' using errcode = 'check_violation';
  end if;

  if v_capture.signature_file_id is not null then
    select malware_scan_status into v_scan_status from app.files where id = v_capture.signature_file_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: signature file % has scan status % -- only clean evidence may be submitted', v_capture.signature_file_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end if;
  foreach v_photo_id in array v_capture.photo_file_ids loop
    select malware_scan_status into v_scan_status from app.files where id = v_photo_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: photo file % has scan status % -- only clean evidence may be submitted', v_photo_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.epod_captures
  set status = 'submitted'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
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
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
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

  update app.finance_journals set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_journal_for_approval',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
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
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Approve', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_cash_unmatch_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'matched' then
    raise exception 'finance_cash_transaction_not_matched: transaction % is % not matched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'unmatched', matched_source_type = null, matched_source_id = null, matched_by = null, matched_at = null, unmatch_reason = p_reason
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'unmatch_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', p_reason, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_item_master(p_item_master_id uuid, p_name text, p_description text, p_lot_controlled boolean, p_serial_controlled boolean, p_expiry_controlled boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_masters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where id = p_item_master_id for update;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  update app.item_masters set
    name = p_name,
    description = p_description,
    lot_controlled = coalesce(p_lot_controlled, false),
    serial_controlled = coalesce(p_serial_controlled, false),
    expiry_controlled = coalesce(p_expiry_controlled, false)
  where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_item_master',
    'app.item_masters', v_item.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'lot_controlled', v_item.lot_controlled, 'serial_controlled', v_item.serial_controlled, 'expiry_controlled', v_item.expiry_controlled)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_master_record(p_record_id uuid, p_expected_version integer, p_name text, p_aliases jsonb, p_attributes jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.master_records
 LANGUAGE plpgsql
AS $function$
declare
  v_before app.master_records;
  v_after app.master_records;
begin
  select * into v_before from app.master_records where id = p_record_id for update;
  if not found then
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

CREATE OR REPLACE FUNCTION app.update_warehouse(p_warehouse_id uuid, p_name text, p_site_address text, p_timezone text, p_site_geojson jsonb, p_service_type_eligibility text[], p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id for update;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  update app.warehouses set
    name = p_name,
    site_address = p_site_address,
    timezone = p_timezone,
    site_geog = v_geog,
    service_type_eligibility = coalesce(p_service_type_eligibility, '{}'::text[])
  where id = p_warehouse_id
  returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'timezone', p_timezone)
  );

  return v_warehouse;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_warehouse_location(p_location_id uuid, p_name text, p_sequence integer, p_capacity_value numeric, p_capacity_uom text, p_environment jsonb, p_restrictions jsonb, p_barcode text, p_pick_enabled boolean, p_putaway_enabled boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_capacity_value is not null and p_capacity_value < 0 then
    raise exception 'invalid_capacity: capacity_value must not be negative' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  begin
    update app.warehouse_locations set
      name = p_name,
      sequence = coalesce(p_sequence, 0),
      capacity_value = p_capacity_value,
      capacity_uom = p_capacity_uom,
      environment = coalesce(p_environment, '{}'::jsonb),
      restrictions = coalesce(p_restrictions, '{}'::jsonb),
      barcode = p_barcode,
      pick_enabled = coalesce(p_pick_enabled, false),
      putaway_enabled = coalesce(p_putaway_enabled, false)
    where id = p_location_id
    returning * into v_location;
  exception
    when unique_violation then
      raise exception 'duplicate_barcode: barcode % is already assigned within this tenant', p_barcode using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_location',
    'app.warehouse_locations', v_location.id, 'success', null, null, jsonb_build_object('name', p_name, 'barcode', p_barcode)
  );

  return v_location;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_warehouse_zone(p_zone_id uuid, p_name text, p_environment jsonb, p_capacity_value numeric, p_capacity_uom text, p_restrictions jsonb, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_zones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
begin
  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_effective_from is not null and p_effective_to is not null and p_effective_to <= p_effective_from then
    raise exception 'invalid_effective_window: effective_to must be after effective_from' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  update app.warehouse_zones set
    name = p_name,
    environment = coalesce(p_environment, '{}'::jsonb),
    capacity_value = p_capacity_value,
    capacity_uom = p_capacity_uom,
    restrictions = coalesce(p_restrictions, '{}'::jsonb),
    effective_from = p_effective_from,
    effective_to = p_effective_to
  where id = p_zone_id
  returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_zone',
    'app.warehouse_zones', v_zone.id, 'success', null, null, jsonb_build_object('name', p_name)
  );

  return v_zone;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_wms_inbound_order_line(p_line_id uuid, p_expected_quantity numeric, p_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_order_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_inbound_order_lines;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_inbound_order_lines where id = p_line_id;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_order from app.wms_inbound_orders where id = v_line.inbound_order_id;
  if v_order.status <> 'draft' then
    raise exception 'inbound_not_draft: % is not draft -- lines may only change while draft', v_order.id using errcode = 'check_violation';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, v_order.id using errcode = 'insufficient_privilege';
  end if;

  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version
      using errcode = 'check_violation';
  end if;
  if p_expected_quantity is null or p_expected_quantity <= 0 then
    raise exception 'invalid_quantity: expected_quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_order_lines set expected_quantity = p_expected_quantity, notes = p_notes
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_wms_inbound_order_line',
    'app.wms_inbound_order_lines', v_line.id, 'success', null, null,
    jsonb_build_object('expected_quantity', p_expected_quantity)
  );

  return v_line;
end;
$function$;


revoke execute on all functions in schema app from public;

-- Re-granted exactly as each function already was. CREATE OR REPLACE preserves grants;
-- restated for this migration self-contained auditability, deliberately not widened.
grant execute on function app.approve_finance_correction(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_invoice(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_journal(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_period_reopen(uuid,integer,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_settlement(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_tax_rule(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_vendor_bill(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.attach_finance_tax_rule_evidence(uuid,integer,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.cancel_wms_inbound(uuid,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.certify_finance_reconciliation_run(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.confirm_wms_inbound(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.consume_vehicle_capacity_reservation(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.decide_actual_cost(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_correction_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_invoice_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_journal_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_settlement_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_tax_rule_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.discard_finance_vendor_bill_draft(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.execute_finance_settlement(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.issue_finance_invoice(uuid,integer,date,uuid,text) to authenticated, service_role;
grant execute on function app.match_finance_bank_transaction(uuid,integer,text,uuid,uuid,text) to authenticated, service_role;
grant execute on function app.move_org_unit(uuid,uuid,integer,text) to service_role;
grant execute on function app.move_warehouse_location(uuid,uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.override_route_planning_selection(uuid,uuid,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.place_finance_ap_hold(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.place_finance_ar_hold(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.post_finance_correction(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.post_finance_journal(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.post_finance_settlement(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.post_finance_vendor_bill(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.publish_document_requirement_version(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.reassign_user_org_unit(uuid,uuid,integer,text) to service_role;
grant execute on function app.release_finance_ap_hold(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.release_finance_ar_hold(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.release_vehicle_capacity_reservation(uuid,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.relock_finance_period(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.rename_org_unit(uuid,text,integer,text) to service_role;
grant execute on function app.request_finance_period_reopen(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.reschedule_wms_inbound_appointment(uuid,timestamp with time zone,timestamp with time zone,integer,uuid,text) to authenticated, service_role;
grant execute on function app.resolve_finance_reconciliation_exception(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.review_epod_capture(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.revoke_warehouse_customer_eligibility(uuid,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.schedule_wms_inbound_appointment(uuid,timestamp with time zone,timestamp with time zone,integer,uuid,text) to authenticated, service_role;
grant execute on function app.select_route_planning_plan(uuid,uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.set_item_master_status(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.set_org_unit_status(uuid,text,integer,text,text) to service_role;
grant execute on function app.set_warehouse_location_status(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.set_warehouse_status(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.set_warehouse_zone_status(uuid,text,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_actual_cost(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_epod_capture(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_finance_correction_for_approval(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_finance_invoice_for_approval(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_finance_journal_for_approval(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_finance_settlement_for_approval(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.submit_finance_vendor_bill_for_approval(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.unmatch_finance_bank_transaction(uuid,integer,text,uuid,text) to authenticated, service_role;
grant execute on function app.update_item_master(uuid,text,text,boolean,boolean,boolean,integer,uuid,text) to authenticated, service_role;
grant execute on function app.update_master_record(uuid,integer,text,jsonb,jsonb,uuid,text) to service_role;
grant execute on function app.update_warehouse(uuid,text,text,text,jsonb,text[],integer,uuid,text) to authenticated, service_role;
grant execute on function app.update_warehouse_location(uuid,text,integer,numeric,text,jsonb,jsonb,text,boolean,boolean,integer,uuid,text) to authenticated, service_role;
grant execute on function app.update_warehouse_zone(uuid,text,jsonb,numeric,text,jsonb,timestamp with time zone,timestamp with time zone,integer,uuid,text) to authenticated, service_role;
grant execute on function app.update_wms_inbound_order_line(uuid,numeric,text,integer,uuid,text) to authenticated, service_role;
