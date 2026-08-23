-- HDN-374 (Step 15, Prompt 374, Financial Integrity Audit, `CG-S15-HDN-006`) -- four
-- independent parallel investigation lenses (revenue chain; cost/AP chain; period lock/
-- reversal/concurrency/rounding; loyalty liability/payroll/tax/statutory), each required
-- to live-force its own findings on disposable databases rather than accept a code read
-- as proof. Cost/AP chain, payment/journal reconciliation, period lock, reversal,
-- correction, rounding, tax snapshotting, payroll-handoff aggregation, and the RPD-016
-- statutory gates all held clean. Two live-forced revenue-chain defects, a completed
-- concurrency sweep, and one loyalty-liability sweep defect (finding 4) are fixed here.
--
-- ===========================================================================
-- Finding 1 -- quote-level tax silently double-applied at invoicing (High)
-- ===========================================================================
--
-- `app.job_orders.revenue_snapshot` (populated once, at job-order creation, from the
-- originating quotation -- `20260724340000_create_commercial_job_order_lineage.sql`'s own
-- `'pricing'` object) always carries BOTH `subtotalAmount` (pre-tax) and `totalAmount`
-- (tax-inclusive, `v_quotation.total_amount`) whenever the quotation itself applied a
-- line-level `tax_pct`. `app.prepare_finance_invoice_from_readiness` read `totalAmount`
-- and treated it as the invoice's own pre-tax subtotal -- so when the caller also passes
-- `p_tax_code` (the normal path; every db-test fixture exercising this function does),
-- `app.calculate_finance_tax` applies the SAME tax rate a second time on top of an amount
-- that already includes it once.
--
-- **Live-forced**: a quote (qty=3, unit_price=333333.33, `tax_pct`=11) produced
-- `subtotal=999999.99 tax=110000.00 total=1109999.99`; `revenue_snapshot.totalAmount` (the
-- already-tax-inclusive 1,109,999.99) was carried into the invoice as its subtotal, PPN
-- 11% applied again on top, yielding `subtotal_amount=1109999.99 tax_amount=122100.00
-- total_amount=1232099.99` -- a real ~11% overcharge (122,100.00) on this fixture, versus
-- the correct 1,109,999.99. The resulting journal is internally balanced (AR = REV + TAX)
-- so the ledger is self-consistent but wrong -- it books and bills a fabricated extra tax
-- liability. Downstream, `app.calculate_finance_job_profitability` (which correctly sums
-- `subtotal_amount` across every issued invoice) faithfully propagates the inflated
-- figure into the job's reported margin.
--
-- **Fix**: read `subtotalAmount` (the genuine pre-tax figure the quotation itself already
-- computed) instead of `totalAmount`. No other part of the tax-calculation or
-- fixed-amount-currency-mismatch logic changes -- it already correctly assumed its input
-- was a pre-tax base.
--
-- ===========================================================================
-- Finding 2 -- no guard against a second full-amount invoice reaching `issued` for the
-- same job order (High)
-- ===========================================================================
--
-- `app.prepare_finance_invoice_from_readiness`'s own idempotency check only replays the
-- SAME `billing_readiness_handoff_id`; nothing checks whether the job order already has
-- an issued invoice from a DIFFERENT handoff. `app.handoff_billing_readiness` takes only
-- `job_order_id` and `p_idempotency_key` -- no portion/amount parameter exists anywhere in
-- this codebase's schema -- so a second call with a fresh idempotency key creates a second
-- handoff, and preparing an invoice from it re-reads the job's own FULL `revenue_snapshot`
-- total again. **Live-forced**: a single job with real revenue 3,000,000 was invoiced
-- twice via two handoffs, both landing `issued`, 3,000,000 each -- 6,000,000 billed for
-- 3,000,000 of work, with no special access and no readiness re-evaluation required.
--
-- **Scope correction found while live-force verifying the first fix draft**: this
-- checkpoint's first attempt gated `app.prepare_finance_invoice_from_readiness` itself
-- (deny a second DRAFT for a job order that already has an active invoice). That directly
-- contradicts `20260728140000_create_operations_billing_readiness.sql`'s own disclosed
-- design ("Multiple handoffs may exist for one Job Order over time ... this migration
-- does not forbid a legitimate re-handoff after a later reevaluation", OPS-181) and broke
-- `finance-invoice.sql`'s own existing discard-boundary fixture, which prepares a SECOND
-- draft invoice from a second, later handoff on the same job order and discards it -- a
-- sanctioned flow, not the bug. The real harm the live-forced reproduction demonstrated is
-- two invoices both reaching `issued` (the one status that actually posts to AR/GL,
-- `app.issue_finance_invoice`) for the same job, not a second draft existing.
--
-- This codebase has no working partial-invoicing feature to preserve (confirmed: no
-- amount/portion parameter on the handoff RPC, no per-invoice remaining-balance tracking
-- on `job_orders`) -- building one would be a new product feature, outside this audit
-- checkpoint's own charter. The bounded repair is a guard, not a feature, moved to the
-- actual posting boundary: `app.issue_finance_invoice` now denies issuing an invoice for a
-- job order that already has a DIFFERENT invoice in `issued` status, mirroring the exact
-- business rule this schema's own `finance_invoices_handoff_active_unique` index already
-- enforces one level down (one active invoice per handoff). Draft/submitted/approved
-- invoices remain freely creatable and discardable per the existing sanctioned re-handoff
-- flow -- only the second `issued` (the actual AR/GL posting event) is blocked. A prior
-- invoice that was discarded while still draft (`app.discard_finance_invoice_draft`, void
-- status) does not block a fresh one; this codebase has no path to void an invoice that
-- already reached `issued` (`app.discard_finance_invoice_draft` itself refuses a non-draft
-- invoice with `finance_invoice_not_cancellable`), so this guard's own scope never needs
-- to special-case a voided-after-issued invoice.
--
-- ===========================================================================
-- Finding 3 -- 10 Finance functions share `HDN-BLK-010`'s unguarded check-then-insert race
-- (Medium, closes `HDN-BLK-010`'s own Finance-domain scope plus 4 more this checkpoint's
-- own wider sweep found)
-- ===========================================================================
--
-- `HDN-371`/`HDN-373` already registered (`HDN-BLK-010`/`ISS-2026-162`) 6 Finance/HRIS-
-- Payroll functions sharing this shape and named this checkpoint as owner:
-- `app.prepare_finance_invoice_from_readiness`, `app.prepare_finance_journal_adjustment`,
-- `app.prepare_finance_journal_reversal`, `app.prepare_finance_payroll_disbursement_
-- handoff_from_payroll_run`, `app.prepare_finance_settlement`, `app.prepare_finance_
-- vendor_bill_from_actual_cost`. Re-verified live: all 6 still lack the exception handler,
-- and a genuine two-process race against 2 of them (`prepare_finance_journal_reversal`,
-- `prepare_finance_payroll_disbursement_handoff_from_payroll_run`) reproduced exactly the
-- registered failure -- a raw `duplicate key value violates unique constraint` surfacing
-- to the losing concurrent caller, not the graceful "here is the already-created record"
-- every other function in this codebase gives a legitimate concurrent retry.
--
-- This checkpoint's own independent, wider sweep (not limited to the `prepare_/convert_/
-- link_/create_from_` name-prefix scope `HDN-371`'s original sweep used) found **4 more**
-- Finance functions sharing the identical shape, missed because they use different verbs:
-- `app.post_finance_subledger_batch` (the core GL-posting primitive, called transitively
-- by AR receipt allocation, AP settlement posting, and invoice/vendor-bill subledger
-- posting -- live-forced), `app.create_and_post_finance_system_journal`, `app.import_
-- finance_bank_statement`, `app.stage_finance_exchange_rate_import` (all three code-
-- verified: exact shape, confirmed real backing unique constraint, matching `HDN-371`'s
-- own precedent of one representative live proof per mechanism rather than live-forcing
-- every single instance).
--
-- **Fix, identical pattern, mirroring this codebase's own already-proven reference
-- implementation** (`app.prepare_wms_outbound_from_shipment`, `20260730230000_create_
-- advanced_tms_wms_outbound_order.sql`, "design note 9(a)"): wrap each function's own
-- insert in `begin ... exception when unique_violation then <re-select the same
-- idempotency predicate the function's own pre-check already uses>; if found then return
-- it; else re-raise ... end`. No function's own authority check, validation, or business
-- logic is touched -- only the insert gains a race-safe recovery path. For the two
-- functions whose idempotency key can collide for two DIFFERENT reasons (`app.prepare_
-- finance_journal_reversal`'s idempotency-key collision vs. its separate "one active
-- reversal per original journal" partial-unique-index collision), the exception handler
-- distinguishes them, preserving the existing named exception for the second case rather
-- than surfacing either as a raw `unique_violation`.
--
-- **Bonus, same function, same migration**: `app.prepare_finance_payroll_disbursement_
-- handoff_from_payroll_run`'s own idempotency short-circuit (`select ... from app.
-- payroll_finance_handoff_batches where payroll_run_id = p_run_id`) has no `tenant_id`
-- predicate at all -- a disclosed defense-in-depth gap `HDN-371` already flagged for this
-- exact function. Added here alongside the race fix on the same statement, since
-- `payroll_run_id` is already globally unique in practice (backed by `payroll_finance_
-- handoff_batches_run_unique`) so this is a narrowing, not a behavior change.
--
-- ===========================================================================
-- Finding 4 -- app.run_loyalty_expiry_sweep's own p_as_of parameter is silently ignored
-- (Medium)
-- ===========================================================================
--
-- `app.run_loyalty_expiry_sweep(p_tenant_id, p_as_of, ...)` computes `v_as_of :=
-- coalesce(p_as_of, clock_timestamp())` and records it in the job's own payload/run_label
-- for evidence purposes -- but never actually passes it to either primitive it composes.
-- `app.expire_loyalty_point_lots`/`app.expire_loyalty_benefit_entitlements` each hardcode
-- their own scan predicate to `expires_at <= clock_timestamp()` and accept no as-of
-- argument at all. **Live-forced**: a lot/entitlement due to expire tomorrow was swept
-- with `p_as_of` set to the day after tomorrow -- the sweep silently used the REAL current
-- time instead, leaving both untouched; the job's own payload nonetheless recorded
-- `as_of` as the requested future timestamp, misrepresenting what was actually evaluated.
-- A caller relying on `p_as_of` for a backdated/as-of-a-specific-instant run (the
-- documented purpose of accepting the parameter at all) gets silently wrong behavior.
--
-- **Fix**: both primitives gain a new trailing `p_as_of timestamptz default null`
-- parameter (default preserves every existing direct caller's own current-time
-- behavior unchanged); each now scans `expires_at <= coalesce(p_as_of, clock_timestamp())`.
-- `app.run_loyalty_expiry_sweep` passes its own already-computed `v_as_of` through to
-- both calls. Existing 3-arg direct callers (this codebase's own db-tests included)
-- continue to work unchanged since the new parameter is optional.
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-374.md` §6.

create or replace function app.prepare_finance_invoice_from_readiness(p_tenant_id uuid, p_billing_readiness_handoff_id uuid, p_payment_term_days integer, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_invoices
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_invoice app.finance_invoices;
  v_handoff app.billing_readiness_handoffs;
  v_job app.job_orders;
  v_subtotal numeric(14, 2);
  v_currency text;
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_invoice_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032: this replay lookup had NO status predicate, so once a draft was
  -- discarded (status = 'void', a terminal state no writer on this table leads
  -- out of) every later call returned that voided row as though it were a live
  -- draft, and the total finance_invoices_handoff_unique made preparing a
  -- replacement impossible. FIN-197's own header states the opposite intent --
  -- a discarded draft "never burns a number". The uniqueness rule is now
  -- partial (finance_invoices_handoff_active_unique, above); this predicate is
  -- the other half: a voided invoice is not a replay target.
  select * into v_invoice from app.finance_invoices where tenant_id = p_tenant_id and billing_readiness_handoff_id = p_billing_readiness_handoff_id and status <> 'void';
  if found then
    return v_invoice;
  end if;

  select * into v_handoff from app.billing_readiness_handoffs where id = p_billing_readiness_handoff_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_handoff_not_found: % is not a known BillingReadinessHandoff for tenant %', p_billing_readiness_handoff_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_job from app.job_orders where id = v_handoff.job_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_job_order_not_found: % is not a known Job Order for tenant %', v_handoff.job_order_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_currency := v_job.revenue_snapshot ->> 'currency';
  -- HDN-374 (Financial Integrity Audit) finding 1: revenue_snapshot.totalAmount is the
  -- quotation's own TAX-INCLUSIVE total (v_quotation.total_amount); reading it here and
  -- then applying p_tax_code's rate again below double-taxes any quote that carried its
  -- own line-level tax_pct. subtotalAmount is the genuine pre-tax figure the quotation
  -- itself already computed (v_quotation.subtotal_amount) -- always present alongside
  -- totalAmount, since this is the sole construction path for a job order's own revenue
  -- snapshot (20260724340000_create_commercial_job_order_lineage.sql's own 'pricing'
  -- object).
  v_subtotal := (v_job.revenue_snapshot ->> 'subtotalAmount')::numeric(14, 2);
  if v_currency is null or v_subtotal is null then
    raise exception 'finance_invoice_revenue_snapshot_incomplete: job order % has no usable revenue snapshot', v_job.id
      using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(v_currency) then
    raise exception 'finance_invoice_unsupported_currency: % is not a registered, active currency', v_currency
      using errcode = 'check_violation';
  end if;
  if v_subtotal <= 0 then
    raise exception 'finance_invoice_invalid_subtotal: revenue snapshot total % must be positive', v_subtotal
      using errcode = 'check_violation';
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, current_date, p_actor_auth_user_id) into v_tax_result;
    -- ATW-032: a fixed_amount rule is denominated -- FIN-195's own
    -- finance_tax_rule_versions_fixed_amount_currency_check guarantees it
    -- always carries a currency, and calculate_finance_tax returns both that
    -- currency and the rate basis. This call site previously read only
    -- taxAmount/ruleVersionId, so a fixed IDR duty landed unconverted on a USD
    -- invoice. Refused rather than auto-converted: choosing an FX rate and an
    -- as-of/rate-type policy is not this call site's decision to make, and a
    -- silently converted statutory duty is worse than a refused one. A
    -- percentage rule is unaffected -- its result is denominated in the base
    -- amount's own currency by construction.
    if (v_tax_result ->> 'rateBasis') = 'fixed_amount' and coalesce(v_tax_result ->> 'currency', '') <> v_currency then
      raise exception 'finance_tax_rule_currency_mismatch: tax code % resolves to a fixed_amount rule denominated in %, which cannot be applied to a % invoice', p_tax_code, coalesce(v_tax_result ->> 'currency', '(none)'), v_currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own scope for this function): a genuine race
  -- between the replay lookup above and this insert (two concurrent callers for the same
  -- handoff both pass it before either commits) is resolved by re-selecting and returning
  -- the winner, mirroring app.prepare_wms_outbound_from_shipment's own proven pattern.
  -- Backed by finance_invoices_handoff_active_unique.
  begin
    insert into app.finance_invoices (
      tenant_id, company_id, customer_account_id, job_order_id, billing_readiness_handoff_id,
      currency, subtotal_amount, tax_amount, payment_term_days, created_by
    )
    values (
      p_tenant_id, v_job.org_unit_id, v_job.account_id, v_job.id, p_billing_readiness_handoff_id,
      v_currency, v_subtotal, v_tax_amount, coalesce(p_payment_term_days, 30), p_actor_label
    )
    returning * into v_invoice;
  exception
    when unique_violation then
      select * into v_invoice from app.finance_invoices where tenant_id = p_tenant_id and billing_readiness_handoff_id = p_billing_readiness_handoff_id and status <> 'void';
      if found then
        return v_invoice;
      end if;
      raise;
  end;

  insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount)
  values (v_invoice.id, 1, 'charge', 'Freight and service charges per Job Order ' || v_job.job_number, v_subtotal);

  if v_tax_amount > 0 then
    insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_invoice.id, 2, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_invoice_from_readiness',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;

create or replace function app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text DEFAULT 'gl'::text)
returns app.finance_journals
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
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
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- HDN-373 Tier C fix: either level is a legitimate caller (app.post_finance_subledger_batch
  -- and app.allocate_finance_receipt both require only FIN:Edit at their own front door;
  -- app.post_finance_correction requires FIN:Approve, which this OR already admits).
  -- Still denies an actor holding neither -- ISS-2026-183's own original concern.
  if not (app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id)
          or app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit or FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
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

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert (two concurrent callers preparing the same
  -- source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_journals_idempotency_unique.
  begin
    insert into app.finance_journals (
      tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
      currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
    )
    values (
      p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
      p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
    )
    returning * into v_journal;
  exception
    when unique_violation then
      select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_journal;
      end if;
      raise;
  end;

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

create or replace function app.post_finance_subledger_batch(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_posting_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_subledger_batches
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_batch app.finance_subledger_batches;
  v_period record;
  v_line jsonb;
  v_line_number integer := 0;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_journal_lines jsonb := '[]'::jsonb;
  v_journal app.finance_journals;
  v_lock_scope text;
begin
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement') then
    raise exception 'finance_subledger_unsupported_source_type: % is not a supported subledger source type', p_source_type
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_subledger_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_posting_date);
  if not found then
    raise exception 'finance_subledger_period_not_found: no fiscal period covers %', p_posting_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_subledger_period_not_open: fiscal period % for % is not open', v_period.period_code, p_posting_date
      using errcode = 'check_violation';
  end if;

  v_lock_scope := case when p_source_type in ('invoice', 'receipt_allocation') then 'ar' when p_source_type in ('vendor_bill', 'settlement') then 'ap' else 'gl' end;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, v_lock_scope);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;
    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;
  end loop;

  if v_debit_total <> v_credit_total then
    raise exception 'finance_subledger_unbalanced_batch: debit total % does not equal credit total % for source % %', v_debit_total, v_credit_total, p_source_type, p_source_id
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (new instance, not in HDN-BLK-010's original scope): a genuine
  -- race between the select above and this insert (two concurrent callers posting the
  -- same source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_subledger_batches_source_unique. Caught here, before any
  -- finance_subledger_lines row is written, so the losing caller leaves no partial state.
  begin
    insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
    values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_batch;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_subledger_inactive_mapped_account: account % is not active (status=%)', v_account.code, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_subledger_not_postable_mapped_account: account % is not postable (control account)', v_account.code
          using errcode = 'check_violation';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    insert into app.finance_subledger_lines (batch_id, tenant_id, line_number, account_id, posting_map_key, direction, amount, open_item_type, open_item_id)
    values (
      v_batch.id, p_tenant_id, v_line_number, v_account.id, v_key, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'openItemType', nullif(v_line ->> 'openItemId', '')::uuid
    );

    v_journal_lines := v_journal_lines || jsonb_build_array(jsonb_build_object('accountId', v_account.id, 'direction', v_line ->> 'direction', 'amount', (v_line ->> 'amount')::numeric));
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_subledger_batch',
    'app.finance_subledger_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'totalAmount', v_debit_total)
  );

  select * into v_journal from app.create_and_post_finance_system_journal(
    p_tenant_id, p_company_id, 'subledger', v_batch.id, p_posting_date, p_currency, v_journal_lines, p_actor_auth_user_id, p_actor_label, v_lock_scope
  );
  update app.finance_subledger_batches set gl_journal_id = v_journal.id where id = v_batch.id returning * into v_batch;

  return v_batch;
end;
$function$
;

create or replace function app.prepare_finance_journal_adjustment(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_adjustment_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_journal_corrections
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'adjustment' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type adjustment)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_journal_line_balance(p_adjustment_lines);

  for v_line in select * from jsonb_array_elements(p_adjustment_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not active/postable', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and re-applying the
  -- same conflict check, never a raw unique_violation on a legitimate concurrent retry.
  -- Backed by finance_journal_corrections_idempotency_unique.
  begin
    insert into app.finance_journal_corrections (
      tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines, idempotency_key, created_by
    )
    values (p_tenant_id, p_company_id, p_original_journal_id, 'adjustment', p_correction_date, p_reason, p_evidence_ref, p_adjustment_lines, p_idempotency_key, p_actor_label)
    returning * into v_correction;
  exception
    when unique_violation then
      select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'adjustment' or v_correction.company_id is distinct from p_company_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type adjustment)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
            using errcode = 'unique_violation';
        end if;
        return v_correction;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_adjustment',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;

create or replace function app.prepare_finance_journal_reversal(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_journal_corrections
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'reversal' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type reversal)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from app.finance_journal_corrections
    where tenant_id = p_tenant_id and original_journal_id = p_original_journal_id
      and correction_type = 'reversal' and status <> 'discarded'
  ) then
    raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): this insert can race
  -- on TWO distinct unique constraints -- finance_journal_corrections_idempotency_unique
  -- (a genuine concurrent retry with the same key: re-select and return) or the partial
  -- unique index backing "one active reversal per original journal" (two DIFFERENT
  -- idempotency keys racing to reverse the SAME original journal concurrently: a genuine
  -- conflict, not a replay -- surfaced as the same named exception the pre-check above
  -- already raises for the non-concurrent case, never a raw unique_violation).
  begin
    insert into app.finance_journal_corrections (
      tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, idempotency_key, created_by
    )
    values (p_tenant_id, p_company_id, p_original_journal_id, 'reversal', p_correction_date, p_reason, p_evidence_ref, p_idempotency_key, p_actor_label)
    returning * into v_correction;
  exception
    when unique_violation then
      select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'reversal' or v_correction.company_id is distinct from p_company_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type reversal)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
            using errcode = 'unique_violation';
        end if;
        return v_correction;
      end if;
      raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_reversal',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;

create or replace function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_run app.payroll_runs;
  v_existing app.payroll_finance_handoff_batches;
  v_batch app.payroll_finance_handoff_batches;
  v_gross numeric(14, 2);
  v_deductions numeric(14, 2);
  v_tax numeric(14, 2);
  v_benefit numeric(14, 2);
  v_reimb numeric(14, 2);
  v_loan numeric(14, 2);
  v_net numeric(14, 2);
  v_count integer;
begin
  -- Payroll's OWN authority (HRS:Approve) generates the handoff -- this is
  -- still Payroll acting on its own finalized data, never a Finance action.
  if not app.check_payroll_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.payroll_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if v_run.status <> 'finalized' then
    raise exception 'payroll_run_not_finalized: run % is % -- only a finalized run may generate a Finance handoff', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (defense-in-depth narrowing, disclosed alongside HDN-371's own
  -- finding for this function): payroll_run_id is already globally unique in practice
  -- (backed by payroll_finance_handoff_batches_run_unique) so adding tenant_id here is a
  -- narrowing, not a behavior change -- but it means this lookup can no longer be
  -- satisfied by a row belonging to a different tenant under any future relaxation of
  -- that constraint.
  select * into v_existing from app.payroll_finance_handoff_batches where payroll_run_id = p_run_id and tenant_id = p_tenant_id;
  if found then
    return v_existing;
  end if;

  select
    coalesce(sum(gross_earnings), 0), coalesce(sum(total_deductions), 0), coalesce(sum(total_tax), 0),
    coalesce(sum(total_benefit_employer_cost), 0), coalesce(sum(total_reimbursement), 0), coalesce(sum(total_loan_repayment), 0),
    coalesce(sum(net_pay), 0), count(*)
  into v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count
  from app.payroll_run_employee_results where payroll_run_id = p_run_id;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and returning the
  -- winner. Backed by payroll_finance_handoff_batches_run_unique.
  begin
    insert into app.payroll_finance_handoff_batches (
      tenant_id, payroll_run_id, payroll_period_id, currency, gross_earnings_total, total_deductions_total, total_tax_total,
      total_benefit_employer_cost_total, total_reimbursement_total, total_loan_repayment_total, net_pay_total, employee_count, generated_by
    ) values (
      p_tenant_id, p_run_id, v_run.payroll_period_id, v_run.currency, v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count, p_actor_label
    )
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.payroll_finance_handoff_batches where payroll_run_id = p_run_id and tenant_id = p_tenant_id;
      if found then
        return v_batch;
      end if;
      raise;
  end;

  insert into app.payroll_finance_handoff_gl_lines (handoff_batch_id, tenant_id, line_type, gl_mapping_category, amount, currency)
  select v_batch.id, p_tenant_id, l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), sum(l.amount), l.currency
  from app.payroll_calculation_lines l
  left join app.payroll_components c on c.id = l.component_id
  where l.payroll_run_id = p_run_id
  group by l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), l.currency;

  insert into app.payroll_finance_handoff_payment_instructions (handoff_batch_id, tenant_id, employee_id, net_pay_amount, currency, bank_reference_masked)
  select v_batch.id, p_tenant_id, r.employee_id, r.net_pay, r.currency, null
  from app.payroll_run_employee_results r
  where r.payroll_run_id = p_run_id;

  -- Tier C fix (propagation sweep): net_pay_total is a whole-run aggregate,
  -- not a single employee's compensation, but it is still a real financial
  -- figure correlatable via payroll_run_id -- dropped from the audit
  -- after_value for the same reason as every other money-bearing site above.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_payroll_disbursement_handoff_from_payroll_run',
    'app.payroll_finance_handoff_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('payroll_run_id', p_run_id, 'employee_count', v_count)
  );

  return v_batch;
end;
$function$
;

create or replace function app.prepare_finance_settlement(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_payment_reference text, p_bank_account_label text, p_currency text, p_settlement_date date, p_allocations jsonb, p_fee_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_settlements
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_settlement app.finance_settlements;
  v_vendor app.master_records;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ap_open_items;
  v_total numeric := 0;
  v_fee numeric := coalesce(p_fee_amount, 0);
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_settlement_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_settlement.company_id is distinct from p_company_id or v_settlement.vendor_master_id is distinct from p_vendor_master_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different settlement (company %/vendor %, not company %/vendor %)', p_idempotency_key, v_settlement.company_id, v_settlement.vendor_master_id, p_company_id, p_vendor_master_id
        using errcode = 'unique_violation';
    end if;
    return v_settlement;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_settlement_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_settlement_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'finance_settlement_invalid_fee: fee amount must not be negative, got %', v_fee
      using errcode = 'check_violation';
  end if;
  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_settlement_empty_allocation: at least one AP allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'apOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_settlement_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;

    select * into v_open_item from app.finance_ap_open_items where id = v_open_item_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_settlement_open_item_not_found: % is not a known AP open item for tenant %', v_open_item_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.vendor_master_id <> p_vendor_master_id then
      raise exception 'finance_settlement_vendor_mismatch: AP open item % does not belong to vendor %', v_open_item_id, p_vendor_master_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> p_currency then
      raise exception 'finance_settlement_currency_mismatch: AP open item % is % but settlement is %', v_open_item_id, v_open_item.currency, p_currency
        using errcode = 'check_violation';
    end if;
    if v_open_item.is_held then
      raise exception 'finance_settlement_open_item_held: AP open item % is held and cannot be settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.status = 'settled' then
      raise exception 'finance_settlement_open_item_already_settled: AP open item % is already fully settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_amount > v_open_item.open_amount then
      raise exception 'finance_settlement_over_allocation: allocation % exceeds open amount % for AP open item %', v_amount, v_open_item.open_amount, v_open_item_id
        using errcode = 'check_violation';
    end if;

    v_total := v_total + v_amount;
  end loop;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and re-applying the
  -- same conflict check. Backed by finance_settlements_idempotency_unique.
  begin
    insert into app.finance_settlements (
      tenant_id, company_id, vendor_master_id, payment_reference, bank_account_label,
      currency, allocated_amount, fee_amount, settlement_date, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_company_id, p_vendor_master_id, p_payment_reference, p_bank_account_label,
      p_currency, v_total, v_fee, p_settlement_date, p_idempotency_key, p_actor_label
    )
    returning * into v_settlement;
  exception
    when unique_violation then
      select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_settlement.company_id is distinct from p_company_id or v_settlement.vendor_master_id is distinct from p_vendor_master_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different settlement (company %/vendor %, not company %/vendor %)', p_idempotency_key, v_settlement.company_id, v_settlement.vendor_master_id, p_company_id, p_vendor_master_id
            using errcode = 'unique_violation';
        end if;
        return v_settlement;
      end if;
      raise;
  end;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    insert into app.finance_settlement_allocations (tenant_id, settlement_id, ap_open_item_id, amount)
    values (p_tenant_id, v_settlement.id, (v_item ->> 'apOpenItemId')::uuid, (v_item ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$
;

create or replace function app.prepare_finance_vendor_bill_from_actual_cost(p_tenant_id uuid, p_actual_cost_id uuid, p_vendor_master_id uuid, p_vendor_reference text, p_bill_date date, p_payment_term_days integer, p_vendor_stated_amount numeric, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_vendor_bills
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_bill app.finance_vendor_bills;
  v_cost app.shipment_actual_costs;
  v_vendor app.master_records;
  v_subtotal numeric(14, 2);
  v_line_number integer := 0;
  v_component app.shipment_actual_cost_components;
  v_variance numeric(14, 2) := 0;
  v_variance_status text := 'within_tolerance';
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032: same defect and same fix as prepare_finance_invoice_from_readiness
  -- above -- verified independently against this table's own writers rather than
  -- assumed symmetric. discard_finance_vendor_bill_draft writes a terminal
  -- 'void', and submit_/approve_/post_finance_vendor_bill each guard on
  -- draft/submitted/approved, so nothing leads out of void: without this
  -- predicate a discarded bill was handed back to every later caller, and the
  -- total unique constraint (now partial) blocked any replacement.
  select * into v_bill from app.finance_vendor_bills where tenant_id = p_tenant_id and actual_cost_id = p_actual_cost_id and vendor_master_id = p_vendor_master_id and status <> 'void';
  if found then
    return v_bill;
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_vendor_bill_actual_cost_not_found: % is not a known actual cost for tenant %', p_actual_cost_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_cost.status <> 'approved' or not v_cost.is_current then
    raise exception 'finance_vendor_bill_actual_cost_not_approved: actual cost % is not the current approved version', p_actual_cost_id
      using errcode = 'check_violation';
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_vendor_bill_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select coalesce(sum(amount), 0) into v_subtotal
    from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id;
  if v_subtotal <= 0 then
    raise exception 'finance_vendor_bill_no_matching_components: no vendor-sourced cost component for vendor % on actual cost %', p_vendor_master_id, p_actual_cost_id
      using errcode = 'no_data_found';
  end if;

  if p_vendor_stated_amount is not null then
    v_variance := abs(p_vendor_stated_amount - v_subtotal);
    if v_variance > 1.00 then
      v_variance_status := 'requires_approval';
    end if;
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, coalesce(p_bill_date, current_date), p_actor_auth_user_id) into v_tax_result;
    -- ATW-032: see prepare_finance_invoice_from_readiness. The document currency
    -- here is the actual cost's own currency (v_cost.currency) -- the same value
    -- written to finance_vendor_bills.currency by the INSERT below -- so the
    -- comparison is against the currency the tax amount will actually be summed
    -- into, not against a separately resolved one.
    if (v_tax_result ->> 'rateBasis') = 'fixed_amount' and coalesce(v_tax_result ->> 'currency', '') <> v_cost.currency then
      raise exception 'finance_tax_rule_currency_mismatch: tax code % resolves to a fixed_amount rule denominated in %, which cannot be applied to a % vendor bill', p_tax_code, coalesce(v_tax_result ->> 'currency', '(none)'), v_cost.currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and returning the
  -- winner. Backed by finance_vendor_bills_actual_cost_vendor_active_unique.
  begin
    insert into app.finance_vendor_bills (
      tenant_id, company_id, vendor_master_id, vendor_reference, shipment_order_id, actual_cost_id,
      currency, subtotal_amount, tax_amount, vendor_stated_amount, variance_amount, variance_status,
      payment_term_days, bill_date, due_date, created_by
    )
    select
      p_tenant_id, so.org_unit_id, p_vendor_master_id, p_vendor_reference, v_cost.shipment_order_id, p_actual_cost_id,
      v_cost.currency, v_subtotal, v_tax_amount, p_vendor_stated_amount, v_variance, v_variance_status,
      coalesce(p_payment_term_days, 30), p_bill_date, p_bill_date + (coalesce(p_payment_term_days, 30) || ' days')::interval, p_actor_label
    from app.shipment_orders so where so.id = v_cost.shipment_order_id
    returning * into v_bill;
  exception
    when unique_violation then
      select * into v_bill from app.finance_vendor_bills where tenant_id = p_tenant_id and actual_cost_id = p_actual_cost_id and vendor_master_id = p_vendor_master_id and status <> 'void';
      if found then
        return v_bill;
      end if;
      raise;
  end;

  for v_component in
    select * from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id
    order by created_at asc
  loop
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, source_component_id)
    values (v_bill.id, v_line_number, 'cost', coalesce(v_component.description, v_component.category), v_component.amount, v_component.id);
  end loop;

  if v_tax_amount > 0 then
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_bill.id, v_line_number, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_vendor_bill_from_actual_cost',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$
;

create or replace function app.import_finance_bank_statement(p_tenant_id uuid, p_bank_account_id uuid, p_source_reference text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_bank_statement_batches
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_batch app.finance_bank_statement_batches;
  v_account app.finance_bank_accounts;
  v_line jsonb;
  v_hash text;
  v_inserted integer := 0;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_source_reference is null or length(trim(p_source_reference)) = 0 then
    raise exception 'finance_cash_source_reference_required: a non-empty source_reference is required' using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: % is not a known bank account for tenant %', p_bank_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_batch from app.finance_bank_statement_batches where tenant_id = p_tenant_id and bank_account_id = p_bank_account_id and source_reference = p_source_reference;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_cash_empty_statement: at least one line is required' using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (new instance, not in HDN-BLK-010's original scope): a genuine
  -- race between the select above and this insert is resolved by re-selecting and
  -- returning the winner. Backed by finance_bank_statement_batches_unique.
  begin
    insert into app.finance_bank_statement_batches (tenant_id, bank_account_id, source_reference, imported_by)
    values (p_tenant_id, p_bank_account_id, p_source_reference, p_actor_label)
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.finance_bank_statement_batches where tenant_id = p_tenant_id and bank_account_id = p_bank_account_id and source_reference = p_source_reference;
      if found then
        return v_batch;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if v_line ->> 'direction' not in ('debit', 'credit') then
      raise exception 'finance_cash_invalid_direction: % is not debit or credit', v_line ->> 'direction' using errcode = 'check_violation';
    end if;
    if (v_line ->> 'amount')::numeric <= 0 then
      raise exception 'finance_cash_invalid_amount: line amount must be positive, got %', v_line ->> 'amount' using errcode = 'check_violation';
    end if;

    v_hash := md5(p_bank_account_id::text || '|' || (v_line ->> 'transactionDate') || '|' || (v_line ->> 'direction') || '|' || (v_line ->> 'amount') || '|' || coalesce(v_line ->> 'reference', ''));

    insert into app.finance_bank_transactions (batch_id, tenant_id, bank_account_id, transaction_date, direction, amount, reference, description, line_hash)
    values (
      v_batch.id, p_tenant_id, p_bank_account_id, (v_line ->> 'transactionDate')::date, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'reference', v_line ->> 'description', v_hash
    )
    on conflict (bank_account_id, line_hash) do nothing;

    if found then
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  update app.finance_bank_statement_batches set line_count = v_inserted where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_finance_bank_statement',
    'app.finance_bank_statement_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceReference', p_source_reference, 'submittedLineCount', jsonb_array_length(p_lines), 'insertedLineCount', v_inserted)
  );

  return v_batch;
end;
$function$
;

create or replace function app.stage_finance_exchange_rate_import(p_tenant_id uuid, p_idempotency_key text, p_rows jsonb, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_exchange_rate_import_batches
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_batch app.finance_exchange_rate_import_batches;
  v_row jsonb;
  v_count integer := 0;
begin
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_exchange_rate_import_batches
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_batch.row_count is distinct from coalesce(jsonb_array_length(p_rows), 0) then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different exchange rate import batch (row count %, not %)', p_idempotency_key, v_batch.row_count, coalesce(jsonb_array_length(p_rows), 0)
        using errcode = 'unique_violation';
    end if;
    return v_batch;
  end if;

  -- HDN-374 finding 3 (new instance, not in HDN-BLK-010's original scope): a genuine
  -- race between the select above and this insert is resolved by re-selecting and
  -- re-applying the same conflict check. Backed by
  -- finance_exchange_rate_import_batches_tenant_key_unique.
  begin
    insert into app.finance_exchange_rate_import_batches (tenant_id, idempotency_key, created_by)
    values (p_tenant_id, p_idempotency_key, p_actor_label)
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.finance_exchange_rate_import_batches
        where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and idempotency_key = p_idempotency_key;
      if found then
        if v_batch.row_count is distinct from coalesce(jsonb_array_length(p_rows), 0) then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different exchange rate import batch (row count %, not %)', p_idempotency_key, v_batch.row_count, coalesce(jsonb_array_length(p_rows), 0)
            using errcode = 'unique_violation';
        end if;
        return v_batch;
      end if;
      raise;
  end;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into app.finance_exchange_rates (
      tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, import_batch_id, created_by
    )
    values (
      p_tenant_id,
      coalesce(v_row ->> 'rate_type', 'spot'),
      v_row ->> 'source_currency',
      v_row ->> 'target_currency',
      (v_row ->> 'rate')::numeric,
      coalesce(v_row ->> 'source', 'import'),
      (v_row ->> 'effective_from')::timestamptz,
      (v_row ->> 'effective_to')::timestamptz,
      v_batch.id,
      p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.finance_exchange_rate_import_batches set row_count = v_count where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'stage_finance_exchange_rate_import',
    'app.finance_exchange_rate_import_batches', v_batch.id, 'success', null, null, jsonb_build_object('row_count', v_count)
  );

  return v_batch;
end;
$function$
;

-- HDN-374 finding 2 (see header): the only change from the current effective definition
-- (20260730480000_harden_optimistic_concurrency_row_lock.sql) is the new job-order-level
-- issued-invoice guard inserted below, in its own commented block. Language/security mode
-- is left exactly as-is (SECURITY INVOKER, no explicit search_path) -- changing that is
-- outside this finding's own scope.
create or replace function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_invoices
language plpgsql
as $function$
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

  -- HDN-374 (Financial Integrity Audit) finding 2: a job order may reach `issued` for at
  -- most one invoice at a time. Draft/submitted/approved invoices from a legitimate
  -- re-handoff (OPS-181) remain freely creatable and discardable (see the migration
  -- header); this is the actual AR/GL posting boundary, so it is the one place a second
  -- full-amount bill for the same job's revenue must be refused. Live-forced without this
  -- guard: two handoffs on one job both reached `issued`, doubling the bill.
  if exists (
    select 1 from app.finance_invoices
    where tenant_id = v_invoice.tenant_id and job_order_id = v_invoice.job_order_id
      and id <> v_invoice.id and status = 'issued'
  ) then
    raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
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
$function$
;

-- HDN-374 finding 4 (see header): app.expire_loyalty_point_lots/app.expire_loyalty_
-- benefit_entitlements each gain a new trailing p_as_of parameter -- a different
-- parameter LIST than the existing 3-arg signatures, so the old overloads are dropped
-- first (CREATE OR REPLACE cannot change a function's own argument list) and the new
-- 4-arg versions re-created with the identical grants/comments, default null preserving
-- every existing direct caller's own real-clock behavior.
drop function if exists app.expire_loyalty_point_lots(uuid, uuid, text);

create function app.expire_loyalty_point_lots(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_as_of timestamptz default null
)
returns setof app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_lot record;
  v_entry app.loyalty_point_ledger_entries;
  v_idem text;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_lot in
    select * from app.loyalty_point_lots
    where tenant_id = p_tenant_id and status = 'active' and remaining_amount > 0 and expires_at <= v_as_of
    order by expires_at asc, id asc
  loop
    begin
      v_idem := 'lot-expiry:' || v_lot.id::text;
      v_entry := app.post_loyalty_point_ledger_entry(
        p_tenant_id, v_lot.loyalty_account_id, 'expiry', -v_lot.remaining_amount, v_lot.id,
        'point_lot_expiry', v_lot.id, v_idem, null, null,
        p_actor_auth_user_id, p_actor_label
      );
      return next v_entry;
    exception
      when others then
        -- A concurrent expire run or a concurrent consumption may have
        -- already touched this lot between this scan's own snapshot and
        -- this iteration reaching it (design decision 8) -- skip it; a
        -- future call safely picks up whatever, if anything, is still due.
        continue;
    end;
  end loop;

  return;
end;
$$;

comment on function app.expire_loyalty_point_lots is
  'CPL-318: idempotent per lot by construction -- a lot already fully expired no longer matches this function''s own scan predicate on re-run, a safe no-op. Each lot is independently fault-isolated (design decision 8) so one lot racing against a concurrent operation never aborts an otherwise-successful batch for every other due lot. HDN-374 finding 4: p_as_of (default null, meaning real clock_timestamp()) lets a caller evaluate the scan as of a specific instant instead of always the real current time -- app.run_loyalty_expiry_sweep now actually passes its own p_as_of through here.';

grant execute on function app.expire_loyalty_point_lots(uuid, uuid, text, timestamptz) to authenticated, service_role;

drop function if exists app.expire_loyalty_benefit_entitlements(uuid, uuid, text);

create function app.expire_loyalty_benefit_entitlements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_as_of timestamptz default null
)
returns setof app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row record;
  v_updated app.loyalty_benefit_entitlements;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Only status='issued' entitlements are in scope -- a held entitlement
  -- (status='held') must be released (or reversed) by staff first; expiry
  -- must never silently clear an open fraud-hold investigation (disclosed
  -- boundary, mirrors CPL-318's own status='active'-only lot expiry scan).
  for v_row in
    select * from app.loyalty_benefit_entitlements
    where tenant_id = p_tenant_id and status = 'issued' and expires_at is not null and expires_at <= v_as_of
    order by expires_at asc, id asc
  loop
    begin
      update app.loyalty_benefit_entitlements
        set status = 'expired'
        where id = v_row.id and status = 'issued'
        returning * into v_updated;
      if found then
        insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
        values (p_tenant_id, v_updated.id, 'expired', v_updated.value_amount, null, p_actor_auth_user_id, p_actor_label);
        return next v_updated;
      end if;
    exception
      when others then
        -- A concurrent operation may have already touched this row between
        -- this scan's own snapshot and this iteration reaching it -- skip
        -- it; a future call safely picks up whatever, if anything, is still
        -- genuinely due (mirrors CPL-318 design decision 8).
        continue;
    end;
  end loop;

  return;
end;
$$;

comment on function app.expire_loyalty_benefit_entitlements is
  'CPL-319: idempotent per row by construction -- an already-expired entitlement no longer matches this scan''s own predicate on re-run, a safe no-op. Each row is independently fault-isolated so one row racing against a concurrent operation never aborts an otherwise-successful batch for every other due row. On-demand/staff-triggered only in this checkpoint (ISS-2026-129), mirroring ISS-2026-126/127/128''s own identical, already-accepted precedent. HDN-374 finding 4: p_as_of (default null, meaning real clock_timestamp()) lets a caller evaluate the scan as of a specific instant instead of always the real current time -- app.run_loyalty_expiry_sweep now actually passes its own p_as_of through here.';

grant execute on function app.expire_loyalty_benefit_entitlements(uuid, uuid, text, timestamptz) to authenticated, service_role;

-- HDN-374 finding 4: the only change from the current effective definition
-- (20260801240000_create_customer_portal_loyalty_expiry_fraud_prevention.sql) is
-- threading v_as_of through to both calls below instead of silently discarding it.
create or replace function app.run_loyalty_expiry_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_run_label text default null
)
returns table (
  job_id uuid,
  status text,
  run_label text,
  lots_expired_count integer,
  entitlements_expired_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_run_label text;
  v_job app.jobs;
  v_worker_id text;
  v_lots_count integer := 0;
  v_entitlements_count integer := 0;
  v_final app.jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_expiry_sweep', jsonb_build_object('as_of', v_as_of, 'run_label', v_run_label),
    0, 'loyalty_expiry_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-expiry-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Composes the two already-real, already-idempotent, tenant-wide expiry
    -- primitives (CPL-318/319) -- never reimplements either's own scan/
    -- posting logic. Real counts, from each function's own actually-
    -- returned row set. HDN-374 finding 4: v_as_of is now actually passed
    -- through -- previously silently discarded, so the sweep always used
    -- the real current time regardless of what p_as_of requested.
    select count(*) into v_lots_count from app.expire_loyalty_point_lots(p_tenant_id, p_actor_auth_user_id, p_actor_label, v_as_of);
    select count(*) into v_entitlements_count from app.expire_loyalty_benefit_entitlements(p_tenant_id, p_actor_auth_user_id, p_actor_label, v_as_of);

    -- Design decision 1: real counts recorded ON THE COMPLETED JOB ROW
    -- itself, via the job's own already-jsonb, already-not-null payload
    -- column, extended additively. Table-aliased (`j`) -- this function's
    -- own RETURNS TABLE clause implicitly declares job_id/status as
    -- PL/pgSQL variables in scope, the exact CPL-317-style ambiguous-column
    -- defect class, live-caught during this checkpoint's own smoke test
    -- before this file was finalized.
    update app.jobs j
    set payload = j.payload || jsonb_build_object('lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_expiry_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count)
    );
  else
    -- A replay of an already-processed (or already in-flight, per decision
    -- 1's own live-proven serialize-then-no-op race outcome) period -- a
    -- safe no-op, returning whatever the ORIGINAL run's own payload holds.
    v_final := v_job;
    v_lots_count := coalesce((v_final.payload->>'lots_expired_count')::integer, 0);
    v_entitlements_count := coalesce((v_final.payload->>'entitlements_expired_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  lots_expired_count := v_lots_count;
  entitlements_expired_count := v_entitlements_count;
  return next;
end;
$$;

revoke execute on all functions in schema app from public;
