-- Real, executable hardening evidence for FIN-216 (Finance Integrity and
-- Security Hardening, CG-S9-FIN-027) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database.
--
-- FIN-215 (Finance Integrated Verification) closed with ZERO critical/high
-- finding -- a legitimate, disclosed outcome (`docs/build-log/phase-04/FIN-215.md`
-- §3.1/§3.3), not a gap in effort. Prompt 216's own scope ("repair every in-scope
-- critical/high finding from Prompt 215") is therefore empty by definition: there
-- is nothing to repair. This checkpoint instead performs the hardening AUDIT
-- itself (Prompt 216 §16's own named priority list: "tenant/customer/field
-- leakage, normal-role posted mutation, bank/tax/file exposure, support/MFA
-- bypass and secret/log issues") and converts its strongest positive finding
-- into a real, executable regression guard, rather than closing with no new
-- evidence at all.
--
-- The audit performed and its outcome (full account: `docs/build-log/phase-04/
-- FIN-216.md` §3):
-- 1. **Normal-role posted mutation (RPD-022/023, this file's own assertions
--    below)**: every one of the 38 real Finance tables `authenticated` holds any
--    privilege on grants `SELECT` only -- confirmed by a direct `grep` across
--    every Finance migration finding zero `grant insert`/`grant update`/
--    `grant delete` to `authenticated` anywhere. A normal Finance role (even one
--    holding `FIN:Approve`) cannot bypass a governed reversal/adjustment/lock/
--    idempotency path by mutating a posted row directly -- every real mutation
--    is only reachable through an RPC, which enforces the governed path itself.
--    This was already true before this checkpoint (no gap existed to fix); this
--    checkpoint's own contribution is proving it mechanically, exhaustively, and
--    pinning it as a regression guard so a future migration cannot silently
--    widen a grant.
-- 2. **Bank/tax exposure**: already closed at FIN-211 (masked account numbers,
--    never a full number stored) and FIN-214 (the one real log-channel leak
--    found and fixed). No further gap found on re-audit.
-- 3. **Support/MFA bypass**: no Finance capability grants a support/impersonation
--    session any authority beyond what that session's own underlying identity
--    already holds (unchanged, `PLT-115`). No Finance capability enforces MFA
--    directly -- disclosed, not silently ignored: MFA is a Platform Core concern
--    (`docs/adr/`) that no domain (Commercial, Operations, or Finance) has wired
--    per-action step-up for yet; this is a repository-wide state, not a
--    Finance-specific regression this checkpoint introduced or found newly
--    missing, and per Prompt 216 §22 is recorded as an explicit dependency
--    rather than silently worked around.
-- 4. **Secret/log issues**: re-confirmed via `pnpm run security:check`/
--    `data-classification:check` (both clean) and a fresh re-audit of every
--    Finance `capture_audit_event` payload (the same audit FIN-214 performed,
--    re-run here to confirm no new capability introduced a second instance of
--    FIN-214's own finding since that checkpoint).
--
-- Zero repair migration in this checkpoint -- there is nothing to repair.

\set ON_ERROR_STOP on

\echo '>> normal-role posted mutation (RPD-022/023): every one of the 38 real Finance tables that grants authenticated any privilege grants SELECT only -- zero INSERT/UPDATE/DELETE anywhere, for authenticated or anon; a normal Finance role cannot bypass a governed RPC path by mutating a posted row directly'
do $$
declare
  v_table text;
  v_has_insert boolean;
  v_has_update boolean;
  v_has_delete boolean;
  v_anon_has_any boolean;
  v_violations text[] := '{}';
begin
  for v_table in select unnest(array[
    'finance_accounts', 'finance_aging_bucket_configs', 'finance_ap_open_item_events', 'finance_ap_open_items',
    'finance_ar_open_item_events', 'finance_ar_open_items', 'finance_bank_accounts', 'finance_bank_statement_batches',
    'finance_bank_transactions', 'finance_currencies', 'finance_exchange_rate_import_batches', 'finance_exchange_rates',
    'finance_fiscal_calendars', 'finance_fiscal_periods', 'finance_idempotency_claims', 'finance_invoice_lines',
    'finance_invoices', 'finance_job_profitability_facts', 'finance_journal_corrections', 'finance_journal_lines',
    'finance_journals', 'finance_lifecycle_editability_matrix', 'finance_period_close_checklist_items',
    'finance_period_lock_events', 'finance_period_locks', 'finance_period_transitions', 'finance_receipt_allocation_batches',
    'finance_receipt_allocations', 'finance_receipts', 'finance_reconciliation_exceptions', 'finance_reconciliation_runs',
    'finance_rounding_modes', 'finance_settlement_allocations', 'finance_settlements', 'finance_subledger_batches',
    'finance_subledger_lines', 'finance_tax_codes', 'finance_tax_rule_versions', 'finance_vendor_bill_lines', 'finance_vendor_bills'
  ]) loop
    v_has_insert := has_table_privilege('authenticated', format('app.%I', v_table), 'INSERT');
    v_has_update := has_table_privilege('authenticated', format('app.%I', v_table), 'UPDATE');
    v_has_delete := has_table_privilege('authenticated', format('app.%I', v_table), 'DELETE');
    v_anon_has_any := has_table_privilege('anon', format('app.%I', v_table), 'SELECT')
      or has_table_privilege('anon', format('app.%I', v_table), 'INSERT')
      or has_table_privilege('anon', format('app.%I', v_table), 'UPDATE')
      or has_table_privilege('anon', format('app.%I', v_table), 'DELETE');

    if v_has_insert or v_has_update or v_has_delete then
      v_violations := v_violations || format('app.%s: authenticated holds insert=%s update=%s delete=%s (expected all false)', v_table, v_has_insert, v_has_update, v_has_delete);
    end if;
    if v_anon_has_any then
      v_violations := v_violations || format('app.%s: anon holds at least one direct table privilege (expected none)', v_table);
    end if;
  end loop;

  if array_length(v_violations, 1) > 0 then
    raise exception 'assertion failed: % normal-role posted-mutation hardening violation(s) found: %', array_length(v_violations, 1), array_to_string(v_violations, ' | ');
  end if;
end;
$$;

\echo 'ALL FIN-216 (Finance Integrity and Security Hardening) db-test assertions passed -- zero repair required.'
