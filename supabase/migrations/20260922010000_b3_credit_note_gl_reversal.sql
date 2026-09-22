-- CG-AUDIT-2026-09-02 B3 correction: credit notes post a real GL reversal.
--
-- A dedicated adversarial re-sweep of already-shipped backlog items (not
-- only DEFERRED_LARGE rows -- the same "verify before trusting a prior
-- pass" discipline applied to this session's own prior B3 work) found
-- `20260919020000_b3_finance_credit_note.sql`'s own scoping disclosure
-- ("carries no GL journal line -- FIN-202/203's own scope") was based on
-- `app.finance_ar_open_items`'/`app.finance_receipts`' own table comments,
-- which are STALE -- they pre-date the FIN-202 subledger retrofit
-- (`20260729160000_create_finance_subledger.sql`, later widened by
-- `20260907120000_validate_finance_company_org_unit_iss_b8.sql`) that
-- CREATE OR REPLACEd `app.issue_finance_invoice`, `app.allocate_finance_
-- receipt`, `app.post_finance_vendor_bill` and `app.post_finance_
-- settlement` so EACH now posts a real, balanced `app.finance_subledger_
-- batches` row (and, through it, a real `app.finance_journals`/`finance_
-- journal_lines` entry) via the shared `app.post_finance_subledger_batch`
-- primitive. Every source type that posts to `app.finance_ar_open_items`/
-- `app.finance_ap_open_items` today ALSO posts a matching GL journal entry
-- -- except the `credit_note` source type B3 itself just added, which was
-- the one exception to an otherwise-universal pattern. Those two table
-- comments are re-stated below to disambiguate: the OPEN ITEM ROW itself
-- carries no direct GL-journal foreign key (true, and still true after
-- this fix -- the link lives on `app.finance_subledger_batches`, keyed by
-- `source_type`/`source_id`, exactly like `app.finance_invoices` already
-- carries no such column either), never "no GL posting happens."
--
-- This is a live correctness bug, not an inert gap: `app.get_finance_
-- trial_balance` (B2a, `20260918000000_b2a_finance_trial_balance.sql`,
-- shipped the day before B3) sums posted `app.finance_journal_lines`
-- directly. Since `app.issue_finance_credit_note` posted zero subledger/
-- journal lines, revenue and tax-payable GL balances stayed permanently
-- overstated by every credited amount, and the AR control account never
-- reflected the credit -- an already-shipped, already-consumed financial
-- report was silently wrong the moment any credit note existed. No test
-- caught this: `scripts/db-tests/finance-accounts-receivable.sql`'s B3
-- assertions only checked the AR-open-item side; `scripts/db-tests/
-- finance-trial-balance.sql` never referenced credit notes at all.
--
-- Fix: widen `app.finance_subledger_batches_source_type_check` and `app.
-- post_finance_subledger_batch`'s own source-type list (CREATE OR REPLACE,
-- same signature -- grants preserved, explicit SECURITY DEFINER/search_
-- path restated per this repository's own established gotcha) to admit
-- `credit_note`, mapped to the same `ar` period-lock scope as `invoice`/
-- `receipt_allocation` (a credit note is inherently an AR-side
-- transaction). `app.issue_finance_credit_note` (CREATE OR REPLACE, same
-- signature -- `server/mutations/finance-credit-note.ts`'s own RPC call
-- needs zero change) now builds a proportional reversal against the
-- credited invoice's own already-approved, immutable `app.finance_
-- invoice_lines` (the exact same account-resolution logic `app.issue_
-- finance_invoice` itself already uses, mirrored not reinvented) and posts
-- it through the same `app.post_finance_subledger_batch` primitive `app.
-- issue_finance_invoice` uses. This does not touch Indonesian tax policy
-- or require new SME evidence -- it only reverses an amount already
-- computed and approved for the original invoice, in exact proportion to
-- the amount credited.
--
-- Exact-balance design note: a credit ratio applied independently to
-- several tax lines can accumulate a few cents of rounding drift. Rather
-- than distribute that drift across every line, this reversal treats the
-- revenue line as the balancing plug -- every tax line is rounded to 2dp
-- independently (immaterial on its own), and the revenue debit is DERIVED
-- as exactly `(credited_amount + reversed_withholding_credits) -
-- reversed_added_tax_debits`, guaranteeing `app.post_finance_subledger_
-- batch`'s own debit=credit check always holds exactly, never approximately.
-- For a FULL credit (ratio = 1), this reduces algebraically to exactly the
-- invoice's own original `subtotal_amount`, with zero rounding artifact --
-- verified by this migration's own db-test coverage below.
--
-- Deliberately unchanged, still correctly out of this bounded core's own
-- scope: partial/milestone billing (a real billing-model product decision)
-- and any "apply this credit to a future invoice" allocation flow. B3
-- stays PARTIAL, not DONE.

-- ===========================================================================
-- 1. Widen app.finance_subledger_batches to admit credit_note.
-- ===========================================================================

alter table app.finance_subledger_batches
  drop constraint finance_subledger_batches_source_type_check;

alter table app.finance_subledger_batches
  add constraint finance_subledger_batches_source_type_check
  check (source_type in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance', 'credit_note'));

-- ===========================================================================
-- 2. Widen app.post_finance_subledger_batch (FIN-202) -- the ALREADY-
--    EXISTING shared posting primitive app.issue_finance_invoice/app.
--    allocate_finance_receipt/app.post_finance_vendor_bill/app.post_
--    finance_settlement already use -- to accept credit_note as a sixth
--    source type, mapped to the same 'ar' period-lock scope as invoice/
--    receipt_allocation. CREATE OR REPLACE, same signature and return
--    type -- every other line is a mechanical, unmodified copy of
--    20260907120000's own definition (the latest), including its own
--    `security definer`/`set search_path` clauses, so no line is retyped
--    and none can drift -- the same discipline that migration's own header
--    already established for its own predecessor.
-- ===========================================================================

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
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance', 'credit_note') then
    -- CG-AUDIT-2026-09-02 B3 correction: 'credit_note' added. This is the
    -- ONLY change to this function's body besides the v_lock_scope case
    -- below; every other line is a mechanical, script-extracted copy of
    -- 20260907120000's own definition, so no line is retyped and none can
    -- drift.
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
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

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

  -- CG-AUDIT-2026-09-02 B3 correction: 'credit_note' added to the 'ar'
  -- bucket alongside 'invoice'/'receipt_allocation' -- a credit note is
  -- inherently an AR-side transaction, using the same period-lock scope
  -- its own underlying AR open item already uses.
  v_lock_scope := case when p_source_type in ('invoice', 'receipt_allocation', 'credit_note') then 'ar' when p_source_type in ('vendor_bill', 'settlement') then 'ap' else 'gl' end;
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
$function$;

-- ===========================================================================
-- 2b. Widen app.validate_finance_subledger_batch_source (ISS-2026-206,
--     20260831310000) -- its own else-branch deliberately raises for any
--     source_type the CHECK constraint admits but this guard doesn't yet
--     know, exactly so that step 1's widening above would fail loudly here
--     instead of silently reopening the fabricated-source-id gap that
--     migration closed (the exact same class of guard, and the exact same
--     omission, that this session's own original B3 migration had to catch
--     and fix for app.finance_ar_open_items' own sibling guard,
--     app.validate_finance_open_item_source/ISS-2026-319 -- caught here on
--     this fix's own first quick-iteration run). A credit_note's own
--     source_id is app.finance_credit_notes.id -- by the time app.issue_
--     finance_credit_note (step 3 below) posts the subledger batch, it has
--     already inserted and holds a real v_credit_note row with that id, so
--     this lineage check resolves correctly. CREATE OR REPLACE, same
--     signature -- the existing trigger keeps pointing at it.
-- ===========================================================================

create or replace function app.validate_finance_subledger_batch_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'invoice' then
    if not exists (select 1 from app.finance_invoices where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_invoices row for source_type invoice', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'receipt_allocation' then
    -- The allocation BATCH, not app.finance_receipt_allocations -- see 20260831310000's own header note.
    if not exists (select 1 from app.finance_receipt_allocation_batches where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_receipt_allocation_batches row for source_type receipt_allocation', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'vendor_bill' then
    if not exists (select 1 from app.finance_vendor_bills where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_vendor_bills row for source_type vendor_bill', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'settlement' then
    if not exists (select 1 from app.finance_settlements where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_settlements row for source_type settlement', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'opening_balance' then
    if not exists (select 1 from app.finance_ar_open_items where id = NEW.source_id)
       and not exists (select 1 from app.finance_ap_open_items where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_ar_open_items or app.finance_ap_open_items row for source_type opening_balance', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'credit_note' then
    if not exists (select 1 from app.finance_credit_notes where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_credit_notes row for source_type credit_note', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  else
    -- Unreachable while the table's own CHECK constraint holds. Present so that widening that
    -- constraint without widening this function fails loudly at the first insert of the new
    -- type, instead of silently reopening the gap this migration closes.
    raise exception 'finance_subledger_unvalidated_source_type: % has no lineage rule in app.validate_finance_subledger_batch_source -- widen the guard alongside the CHECK constraint', NEW.source_type
      using errcode = 'check_violation';
  end if;

  return NEW;
end;
$$;

-- ===========================================================================
-- 3. Widen app.issue_finance_credit_note -- posts a real, proportional GL
--    reversal after posting the negative AR open item, mirroring app.
--    issue_finance_invoice's own tax-line account-resolution logic exactly.
--    CREATE OR REPLACE, same signature and return type -- grants preserved,
--    public.issue_finance_credit_note wrapper and server/mutations/
--    finance-credit-note.ts both need zero change.
-- ===========================================================================

create or replace function app.issue_finance_credit_note(
  p_tenant_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_reason text,
  p_credit_date date,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_credit_notes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
  v_invoice_ar_item app.finance_ar_open_items;
  v_existing app.finance_credit_notes;
  v_credit_note app.finance_credit_notes;
  v_ar_item app.finance_ar_open_items;
  v_prior_credited numeric;
  v_ratio numeric;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
  v_tax_code app.finance_tax_codes;
  v_line_amount numeric(14, 2);
  v_withholding_credit_total numeric(14, 2) := 0;
  v_added_tax_debit_total numeric(14, 2) := 0;
  v_revenue_debit numeric(14, 2);
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ar_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'finance_credit_note_idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_credit_note_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_credit_note_invalid_amount: amount must be positive, got %', p_amount using errcode = 'check_violation';
  end if;
  if p_credit_date is null then
    raise exception 'finance_credit_note_credit_date_required: a credit date is required' using errcode = 'check_violation';
  end if;

  -- Idempotent: a retried call for the same key returns the existing
  -- credit note rather than re-posting a second AR reduction.
  select * into v_existing from app.finance_credit_notes where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_invoice from app.finance_invoices where id = p_invoice_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: % is not a known invoice for tenant %', p_invoice_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status <> 'issued' then
    raise exception 'finance_credit_note_invoice_not_issued: invoice % is % not issued -- only an issued invoice may be credited', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  select * into v_invoice_ar_item from app.finance_ar_open_items
    where tenant_id = p_tenant_id and source_document_type = 'invoice' and source_document_id = p_invoice_id;
  if not found then
    raise exception 'finance_credit_note_ar_item_not_found: invoice % has no AR open item to credit against', p_invoice_id using errcode = 'no_data_found';
  end if;

  -- Never let cumulative credits on the SAME invoice exceed what was ever
  -- billed -- a repeat credit on an already-credited invoice is real and
  -- allowed (a second billing error on the same invoice), but the sum
  -- must stay bounded by the invoice's own original AR amount.
  select coalesce(sum(amount), 0) into v_prior_credited from app.finance_credit_notes where tenant_id = p_tenant_id and invoice_id = p_invoice_id;
  if v_prior_credited + p_amount > v_invoice_ar_item.original_amount then
    raise exception 'finance_credit_note_exceeds_invoice: crediting % would bring cumulative credits on invoice % to % which exceeds its own original AR amount %', p_amount, p_invoice_id, v_prior_credited + p_amount, v_invoice_ar_item.original_amount
      using errcode = 'check_violation';
  end if;

  insert into app.finance_credit_notes (
    tenant_id, company_id, invoice_id, customer_account_id, currency, amount, reason, idempotency_key, issued_by
  ) values (
    p_tenant_id, v_invoice.company_id, v_invoice.id, v_invoice.customer_account_id, v_invoice.currency, p_amount, p_reason, p_idempotency_key, p_actor_label
  )
  returning * into v_credit_note;

  -- CG-AUDIT-2026-09-02 B3: p_credit_date is a caller-supplied business
  -- date (mirroring app.issue_finance_invoice's own p_issue_date), never
  -- current_date -- the acting Finance user picks which open fiscal period
  -- this credit posts against, same as every other posting entry point in
  -- this module.
  v_ar_item := app.post_finance_ar_open_item(
    p_tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'credit_note', v_credit_note.id,
    v_invoice.currency, -p_amount, p_credit_date, p_credit_date, p_actor_auth_user_id, p_actor_label
  );

  -- CG-AUDIT-2026-09-02 B3 correction: a real, proportional GL reversal --
  -- see this migration's own header for the exact-balance design note.
  -- v_ratio is the fraction of the invoice's own original (net-collectible)
  -- AR amount being reversed by THIS credit note; always in (0, 1] since
  -- the cap check above already guarantees p_amount <= v_invoice_ar_item.
  -- original_amount. ar_control's own credit line is fixed at exactly
  -- p_amount (never ratio-derived); revenue is the balancing plug (see
  -- header) so the batch always balances exactly, never approximately.
  v_ratio := p_amount / v_invoice_ar_item.original_amount;

  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'credit', 'amount', p_amount, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );

  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    v_tax_code := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id;
    end if;
    if v_tax_line.tax_code_id is not null then
      select * into v_tax_code from app.finance_tax_codes where id = v_tax_line.tax_code_id;
    end if;

    v_line_amount := round(v_ratio * v_tax_line.amount, 2);
    if v_line_amount <= 0 then
      continue;
    end if;

    -- Mirrors app.issue_finance_invoice's own account-resolution exactly,
    -- with direction flipped (this reverses the original posting): a
    -- withholding-type tax line was originally DEBITED (a receivable to
    -- CargoGrid), so its reversal is a CREDIT; an added tax line was
    -- originally CREDITED (a payable), so its reversal is a DEBIT.
    if v_tax_code.id is not null and v_tax_code.tax_type = 'withholding' then
      if v_tax_rule.id is not null and v_tax_rule.recoverable_account_id is not null then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'credit', 'amount', v_line_amount));
      else
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'withholding_tax_receivable_default', 'direction', 'credit', 'amount', v_line_amount));
      end if;
      v_withholding_credit_total := v_withholding_credit_total + v_line_amount;
    else
      if v_tax_rule.id is not null and v_tax_rule.output_account_id is not null then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'debit', 'amount', v_line_amount));
      else
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'debit', 'amount', v_line_amount));
      end if;
      v_added_tax_debit_total := v_added_tax_debit_total + v_line_amount;
    end if;
  end loop;

  -- Revenue is the balancing plug (this migration's own header): derived,
  -- never ratio-computed directly, so the batch balances exactly even
  -- after independent per-tax-line rounding. At a full credit (ratio=1)
  -- this is algebraically exact to the invoice's own subtotal_amount --
  -- verified by this migration's own db-test coverage.
  v_revenue_debit := (p_amount + v_withholding_credit_total) - v_added_tax_debit_total;
  if v_revenue_debit < 0 then
    raise exception 'finance_credit_note_gl_reversal_imbalance: computed a negative revenue reversal (%) for invoice % -- its own tax lines do not support crediting %', v_revenue_debit, p_invoice_id, p_amount
      using errcode = 'check_violation';
  elsif v_revenue_debit > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'debit', 'amount', v_revenue_debit));
  end if;

  perform app.post_finance_subledger_batch(
    p_tenant_id, v_invoice.company_id, 'credit_note', v_credit_note.id, p_credit_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_credit_notes set ar_open_item_id = v_ar_item.id where id = v_credit_note.id
  returning * into v_credit_note;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_credit_note',
    'app.finance_credit_notes', v_credit_note.id, 'success', p_reason, null, to_jsonb(v_credit_note)
  );

  return v_credit_note;
end;
$$;

comment on function app.issue_finance_credit_note is
  'CG-AUDIT-2026-09-02 B3 (corrected): FIN:Edit-gated, idempotent, mandatory-reason credit note against an already-ISSUED invoice. Caps cumulative credits on the same invoice at its own original AR amount (never over-credited). Posts a real, negative app.finance_ar_open_items row via app.post_finance_ar_open_item (the same shared primitive app.issue_finance_invoice itself uses) -- correctly reduces the customer''s aggregate net AR exposure (app.get_finance_ar_exposure_summary, B4). ALSO posts a real, balanced GL reversal via app.post_finance_subledger_batch (the same shared primitive every other AR/AP source type already uses), proportional to the credited fraction of the invoice''s own original AR amount, mirroring app.issue_finance_invoice''s own tax-line account resolution with directions flipped -- revenue and tax-payable/recoverable balances now correctly reflect every credit note, closing the gap the original B3 migration''s own scoping disclosure incorrectly left open. Builds no "apply this credit to a future invoice" allocation flow -- the credit stands as an independent, real reduction to the customer''s AR balance.';

-- ===========================================================================
-- 4. Disambiguate the pre-FIN-202-retrofit table comments this fix's own
--    header explains were stale -- documentation only, no schema change.
-- ===========================================================================

comment on table app.finance_ar_open_items is
  'FIN-196: one idempotent AR open item per source document (unique on tenant/source_document_type/source_document_id). open_amount is a generated column (original_amount - allocated_amount), never independently mutable. status is a pure function of balance, computed only by app.apply_finance_ar_allocation/app.reverse_finance_ar_allocation. is_held is orthogonal to status. This row itself carries no direct GL-journal reference (no gl_journal_id column here) -- the real GL entry, when one exists, lives on app.finance_subledger_batches keyed by (source_type, source_id), the same indirection app.finance_invoices itself already uses. Every source_document_type that reaches this table via a real posting entry point (invoice via app.issue_finance_invoice, opening_balance via the import commit adapter, credit_note via app.issue_finance_credit_note since CG-AUDIT-2026-09-02 B3''s own correction) posts a matching subledger batch -- this is NOT an "AR posts, GL does not" boundary.';

comment on table app.finance_receipts is
  'FIN-198: one captured customer receipt. unapplied_amount is a generated column (amount - allocated_amount), never independently mutable -- any remainder after allocation is simply left unapplied. This row itself carries no direct GL-journal reference -- app.allocate_finance_receipt posts a real subledger batch (source_type=receipt_allocation) through app.post_finance_subledger_batch, the same indirection every other subledger source type uses.';

-- ===========================================================================
-- 5. No grant changes -- both widened functions keep their exact prior
--    signature and return type, so CREATE OR REPLACE preserves every
--    existing grant automatically (server/mutations/finance-credit-note.ts
--    and public.issue_finance_credit_note both need zero change).
-- ===========================================================================
