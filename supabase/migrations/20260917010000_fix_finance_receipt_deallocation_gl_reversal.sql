-- CG-AUDIT-2026-09-02 B6 (scoped to its narrowest real slice, "B6a" per this session's
-- own remediation backlog): app.request_finance_receipt_deallocation reversed the AR
-- subledger's own allocated_amount/status but never posted a reversing GL journal,
-- permanently desyncing the GL from the AR subledger on every receipt deallocation --
-- the exact mirror-image of the AP-side bug already fixed pre-audit by
-- 20260826030000_harden_finance_settlement_reversal_gl_journal_and_reachability.sql
-- (RGL-BLK-009, "financial mis-posting"), which was never applied to the AR side.
--
-- Confirmed via a dedicated recon pass (this session): app.reverse_finance_ar_allocation
-- (the low-level AR-subledger mutator) has been redefined three times since creation
-- (20260810700000, 20260831270000, 20260903132000) for SECURITY DEFINER hardening and
-- IP-allowlist wiring only -- never for a GL-reversal fix. Its ONLY caller anywhere in
-- this codebase is app.request_finance_receipt_deallocation, so the fix belongs there,
-- mirroring exactly where the AP fix landed (app.request_finance_settlement_reversal,
-- not app.reverse_finance_ap_settlement itself).
--
-- One real wrinkle vs. the AP precedent, resolved here: app.post_finance_settlement
-- posts ONE subledger batch/GL journal per WHOLE settlement (1:1, so reversing a
-- settlement reverses its one journal in full). app.allocate_finance_receipt instead
-- posts ONE subledger batch/GL journal per ALLOCATE CALL
-- (source_type='receipt_allocation', source_id = the app.finance_receipt_allocation_
-- batches row id), which can cover SEVERAL AR open items -- i.e. several
-- app.finance_receipt_allocations rows -- in one call, while
-- app.request_finance_receipt_deallocation reverses exactly ONE allocation row at a
-- time. Reversing that shared journal in full (the AP function's own technique) would
-- misstate every OTHER still-applied allocation from the same batch. Fixed by building
-- the reversal from the original journal's own 2 lines (cash debit / AR-control
-- credit) with each line's direction flipped but its amount replaced by
-- v_allocation.amount (never the original, possibly-larger, whole-batch amount) --
-- landing on the exact same 2 accounts the original posting did (never re-resolving a
-- posting-map key, the same principle the AP precedent's own comment states), scoped
-- to only this one allocation's own share. The original batch's own status is
-- deliberately left 'posted' (never flipped to 'reversed', unlike the AP/settlement
-- case) since other allocations from the same batch may still stand -- the reversal's
-- correctness lives entirely in the new balanced correction journal, which is the
-- actual GL source of truth; app.finance_subledger_batches is a lineage/traceability
-- record, not itself read by any balance computation in this codebase.
--
-- Same correction-ledger mechanics the AP precedent already established: a
-- app.finance_journal_corrections row (correction_type='reversal', status 'posted'
-- immediately -- this whole action is a single FIN:Approve-gated atomic call, not a
-- separate maker-checker workflow) posted via app.create_and_post_finance_system_journal
-- (source_type='correction', lock_scope='ar'), dated on the ORIGINAL receipt's own
-- receipt_date (the same date already period-checked below), never current_date, for
-- the identical reason the AP fix gives: the reversal lands in the same period as the
-- entry it reverses, deterministically. Idempotency key 'receipt_dealloc:<allocation
-- id>' mirrors 'settlement_reversal:<settlement id>' exactly. No new idempotency gap:
-- this function has no p_idempotency_key param and never needed one -- a second call
-- against the same p_allocation_id is already refused by the unchanged
-- v_allocation.status <> 'applied' guard (the row lock above it serializes concurrent
-- callers), the identical strategy app.request_finance_settlement_reversal's own
-- v_settlement.status <> 'posted' guard already uses.
--
-- Every other line of this function's own body (authority gate, IP allowlist, reason
-- validation, the app.reverse_finance_ar_allocation call, the allocation/receipt
-- updates, the closing audit event) is unchanged from the live definition in
-- 20260903132000_harden_tenant_id_disclosure_finance_residual.sql.

create or replace function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_allocation app.finance_receipt_allocations;
  v_receipt app.finance_receipts;
  v_batch app.finance_subledger_batches;
  v_original_journal app.finance_journals;
  v_period record;
  v_reversal_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_correction app.finance_journal_corrections;
  v_reversal_journal app.finance_journals;
begin
  select * into v_allocation from app.finance_receipt_allocations where id = p_allocation_id for update;
  if not found or not app.has_active_tenant_membership(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_receipt_allocation_not_found: %', p_allocation_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Approve', v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_allocation.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_allocation.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_receipt_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if v_allocation.status <> 'applied' then
    raise exception 'finance_receipt_allocation_not_applied: allocation % is % not applied', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  select * into v_receipt from app.finance_receipts where id = v_allocation.receipt_id for update;

  -- B6a: locate the receipt-allocation batch's own posted GL journal (one per
  -- app.allocate_finance_receipt call, never per individual allocation line).
  select * into v_batch from app.finance_subledger_batches where tenant_id = v_allocation.tenant_id and source_type = 'receipt_allocation' and source_id = v_allocation.batch_id;
  if not found or v_batch.gl_journal_id is null then
    raise exception 'finance_receipt_deallocation_batch_not_found: allocation % has no posted subledger batch/GL journal to reverse -- data integrity anomaly', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  select * into v_original_journal from app.finance_journals where id = v_batch.gl_journal_id;
  if not found or v_original_journal.status <> 'posted' then
    raise exception 'finance_receipt_deallocation_journal_not_posted: journal % for allocation % is not posted', v_batch.gl_journal_id, p_allocation_id
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_allocation.tenant_id, v_receipt.company_id, v_receipt.receipt_date);
  if not found then
    raise exception 'finance_receipt_deallocation_period_not_found: no fiscal period covers %', v_receipt.receipt_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_receipt_deallocation_period_not_open: fiscal period % for % is not open', v_period.period_code, v_receipt.receipt_date
      using errcode = 'check_violation';
  end if;

  -- B6a: flip each of the original journal's own 2 lines (cash debit / AR-control
  -- credit), landing on the exact same accounts, but for THIS allocation's own amount
  -- only -- never the original, possibly-larger, whole-batch total.
  for v_line in select direction, account_id, dimension from app.finance_journal_lines where journal_id = v_original_journal.id order by line_number asc loop
    v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
    v_reversal_lines := v_reversal_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_allocation.amount, 'dimension', v_line.dimension));
  end loop;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines,
    status, idempotency_key, submitted_by, submitted_at, approved_by, approved_at, created_by
  )
  values (
    v_allocation.tenant_id, v_receipt.company_id, v_original_journal.id, 'reversal', v_receipt.receipt_date, p_reason, null, null,
    'approved', 'receipt_dealloc:' || v_allocation.id::text, p_actor_label, now(), p_actor_label, now(), p_actor_label
  )
  returning * into v_correction;

  select * into v_reversal_journal from app.create_and_post_finance_system_journal(
    v_allocation.tenant_id, v_receipt.company_id, 'correction', v_correction.id, v_receipt.receipt_date,
    v_original_journal.currency, v_reversal_lines, p_actor_auth_user_id, p_actor_label, 'ar'
  );

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_reversal_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = v_correction.id;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  perform app.reverse_finance_ar_allocation(
    v_allocation.ar_open_item_id, v_allocation.amount, p_reason, 'receipt', v_allocation.receipt_id,
    'dealloc:' || v_allocation.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipt_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = p_allocation_id;

  update app.finance_receipts set allocated_amount = allocated_amount - v_allocation.amount where id = v_allocation.receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_receipt_deallocation',
    'app.finance_receipt_allocations', v_allocation.id, 'success', p_reason, null, jsonb_build_object('amount', v_allocation.amount)
  );

  return v_receipt;
end;
$function$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.request_finance_receipt_deallocation(uuid, text, uuid, text, text) to authenticated, service_role;
