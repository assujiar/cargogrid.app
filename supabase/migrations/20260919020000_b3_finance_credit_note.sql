-- CG-AUDIT-2026-09-02 B3 (bounded core): "No credit notes; one issued
-- invoice per job order, hard-capped" -- carried as one undivided
-- DEFERRED_LARGE item ("needs a billing-model decision (partial/milestone
-- billing) before schema work") and never itself independently re-verified
-- since.
--
-- A dedicated research pass, the same "verify before trusting a deferred
-- label" discipline that found B7's/B2a's/E6's/B4's/A2b's/E3's/C1's own
-- real bounded cores, found B3 bundles two genuinely separable claims:
--
--   * "One issued invoice per job order, hard-capped" is confirmed
--     accurate at the JOB-ORDER level -- `finance_invoices_job_order_
--     issued_unique` (a real, unique, partial index, `20260811200000_
--     harden_financial_integrity_tierc_fixes.sql`) plus an application-
--     level pre-check in `app.issue_finance_invoice` both enforce it, and
--     every issued invoice bills the job's full `revenue_snapshot` total --
--     no partial/portion parameter exists anywhere. Genuine partial/
--     milestone billing needs a real product decision about the billing
--     model this session cannot make unilaterally. Stays DEFERRED_LARGE,
--     untouched by this migration.
--
--   * "No credit notes" is confirmed true, and turns out WORSE than "all-
--     or-nothing void": there is no way to correct an issued invoice AT
--     ALL today, not even a full void. `app.discard_finance_invoice_draft`
--     only accepts status in ('draft','submitted'); no `app.void_finance_
--     invoice` exists anywhere (confirmed by grep). `app.finance_ar_open_
--     items` structurally forbids a negative/credit row (`original_amount
--     > 0`). The only correction mechanisms that exist operate at
--     different layers entirely: `app.reverse_finance_ar_allocation`
--     unwinds a PAYMENT allocation, never the invoice's own original_
--     amount; FIN-206's `app.finance_journal_corrections` operates purely
--     at the GL-journal level and its own design notes explicitly disclose
--     it does NOT retroactively touch the AR/AP open item's own balance.
--     This half is structurally independent of the job-order/partial-
--     billing question -- a credit note is a NEW row/table referencing an
--     already-issued invoice, never mutating `finance_invoices.job_order_
--     id`/`billing_readiness_handoff_id` cardinality or the generated
--     `total_amount` column -- and there is already a working precedent
--     for AR-collectible diverging from an invoice's own face value
--     (`20260907130000_fix_withholding_tax_deducted_not_added_iss_b5.sql`:
--     `app.issue_finance_invoice` already posts the AR open item at
--     `total_amount - withholding_tax_amount`, not the raw total).
--
-- Fix: `app.finance_credit_notes` -- a new, append-only header/lineage
-- table, one row per issued credit note, referencing the invoice it
-- credits. `app.issue_finance_credit_note` (idempotent, FIN:Edit-gated,
-- mandatory reason) validates the target invoice is genuinely `issued`,
-- caps the cumulative credited amount against that invoice's own original
-- AR amount (never letting credits exceed what was ever billed, tracked
-- across repeat credits on the same invoice), and posts a real, negative
-- AR open item via the ALREADY-EXISTING, already-tested `app.post_finance_
-- ar_open_item` (FIN-196/B8) -- widened (CREATE OR REPLACE, same
-- signature) to accept `credit_note` as a third source-document type with
-- its own negative-amount rule, mirroring how E3's own fix reused the
-- single shared `app.post_inventory_movement` primitive rather than
-- inventing a second posting path. `app.finance_ar_open_items`' own CHECK
-- constraints are widened in step (source_document_type, the original_
-- amount sign rule, and allocated_amount pinned to exactly 0 for a credit_
-- note row, since this bounded core does not build an "apply this credit
-- to a future invoice" allocation flow). `app.search_finance_ar_
-- candidates_for_receipt` (FIN-198) is narrowed to exclude a credit_note
-- row from receipt-allocation candidates -- a customer cash receipt has no
-- sensible meaning "applied against" a standing credit balance.
--
-- Deliberately, disclosedly out of this bounded core's own scope: a GL
-- journal entry reversing revenue/tax for the credited amount. This
-- mirrors, not deviates from, this exact module's own already-established
-- scoping precedent -- `app.finance_ar_open_items`' own header states
-- "Carries no GL journal line -- FIN-202/203's own scope" and `app.
-- finance_receipts` carries the identical disclosure -- a credit note's
-- own AR-side effect (reducing the customer's net collectible balance,
-- correctly reflected in B4's own already-generalized per-currency
-- exposure-summary aggregation with zero further change needed there) is
-- real and closes the audit's own literal complaint ("no credit notes");
-- proportional revenue/tax GL reversal is a genuinely separate, larger
-- accounting-correctness undertaking, the same class of decision B6b's own
-- internal-cost-to-GL gap was correctly left open rather than solved with
-- a governance-bypassing shortcut. Also out of scope: any "apply this
-- credit to a future invoice" UI/allocation flow -- the credit stands as
-- an independent reduction to the customer's aggregate AR exposure, which
-- is itself real, correct, and immediately useful.
--
-- Two self-caught bugs during this migration's own db-test verification
-- pass (scripts/db-tests/finance-accounts-receivable.sql, scripts/db-tests/
-- finance-receipt-allocation.sql, scripts/db-tests/public-api-wrapper-
-- regression.sql), fixed before this migration ever reached the full
-- pnpm run db:test suite:
--   1. Step 3b below (widening app.validate_finance_open_item_source,
--      ISS-2026-319) was missing from the first draft -- its own else-
--      branch deliberately raises for any source_document_type the CHECK
--      constraint admits but the guard doesn't yet know, so app.issue_
--      finance_credit_note failed on every call until this was added.
--   2. app.issue_finance_credit_note originally posted with current_date
--      instead of a caller-supplied p_credit_date (mirroring app.issue_
--      finance_invoice's own p_issue_date) -- caught the moment the db-
--      test ran against a fiscal calendar that does not cover today's
--      real wall-clock date, exactly the class of bug an explicit date
--      parameter exists to prevent. Also, this migration's own CREATE OR
--      REPLACE of app.search_finance_ar_candidates_for_receipt (step 5)
--      initially omitted the pre-existing SECURITY DEFINER/search_path/
--      has_active_tenant_membership check the live function already
--      carried (20260902100000) -- CREATE OR REPLACE does not preserve
--      those unless restated, so omitting them is a silent downgrade to
--      SECURITY INVOKER, caught by public-api-wrapper-regression.sql's
--      own definer/invoker-mismatch assertion before this ever shipped.

-- ===========================================================================
-- 1. app.finance_credit_notes -- append-only header/lineage record
-- ===========================================================================

create table app.finance_credit_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  invoice_id uuid not null references app.finance_invoices (id),
  customer_account_id uuid not null references app.accounts (id),
  currency text not null,
  amount numeric(14, 2) not null,
  reason text not null,
  ar_open_item_id uuid references app.finance_ar_open_items (id),
  idempotency_key text not null,
  issued_by text,
  issued_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint finance_credit_notes_amount_check check (amount > 0),
  constraint finance_credit_notes_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_credit_notes_reason_check check (length(trim(reason)) > 0),
  constraint finance_credit_notes_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.finance_credit_notes is
  'CG-AUDIT-2026-09-02 B3: one append-only, idempotent credit note per successful app.issue_finance_credit_note call -- always references an already-issued app.finance_invoices row it reduces. Carries no GL journal line, mirroring app.finance_ar_open_items''/app.finance_receipts'' own identical disclosed scoping. ar_open_item_id back-references the real, negative app.finance_ar_open_items row this credit note posted.';

create index finance_credit_notes_tenant_invoice_idx on app.finance_credit_notes (tenant_id, invoice_id);
create index finance_credit_notes_tenant_customer_idx on app.finance_credit_notes (tenant_id, customer_account_id);

-- ===========================================================================
-- 2. Widen app.finance_ar_open_items to admit a credit_note row -- a real
--    negative balance, never blended with the positive-only invoice/
--    opening_balance rows it already carries.
-- ===========================================================================

alter table app.finance_ar_open_items drop constraint finance_ar_open_items_source_type_check;
alter table app.finance_ar_open_items add constraint finance_ar_open_items_source_type_check
  check (source_document_type in ('invoice', 'opening_balance', 'credit_note'));

alter table app.finance_ar_open_items drop constraint finance_ar_open_items_original_amount_check;
alter table app.finance_ar_open_items add constraint finance_ar_open_items_original_amount_check
  check (
    (source_document_type = 'credit_note' and original_amount < 0)
    or (source_document_type <> 'credit_note' and original_amount > 0)
  );

-- A credit_note row is never itself allocated against in this bounded
-- core (design note above) -- allocated_amount is pinned to exactly 0,
-- never the general 0..original_amount range the positive rows use.
alter table app.finance_ar_open_items drop constraint finance_ar_open_items_allocated_amount_check;
alter table app.finance_ar_open_items add constraint finance_ar_open_items_allocated_amount_check
  check (
    (source_document_type = 'credit_note' and allocated_amount = 0)
    or (source_document_type <> 'credit_note' and allocated_amount >= 0 and allocated_amount <= original_amount)
  );

-- ===========================================================================
-- 3. Widen app.post_finance_ar_open_item (FIN-196/B8) -- the ALREADY-
--    EXISTING shared posting primitive app.issue_finance_invoice and the
--    opening-balance import adapter already use -- to accept credit_note
--    as a third source type with its own negative-amount rule. CREATE OR
--    REPLACE, same signature and return type -- existing grants preserved
--    automatically, every existing caller (invoice issuance, opening-
--    balance import) completely unaffected (their own source types keep
--    the identical positive-only rule).
-- ===========================================================================

create or replace function app.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_ar_open_items
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_item app.finance_ar_open_items;
  v_customer app.accounts;
  v_period record;
  v_required_action text;
begin
  if p_source_document_type not in ('invoice', 'opening_balance', 'credit_note') then
    raise exception 'finance_ar_unsupported_source_type: % is not a supported AR source document type', p_source_document_type
      using errcode = 'check_violation';
  end if;
  v_required_action := case when p_source_document_type = 'opening_balance' then 'Approve' else 'Edit' end;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ar_authority(v_required_action, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:% for tenant %', p_actor_auth_user_id, v_required_action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  -- Idempotent: a retried call for the same source document returns the
  -- existing open item rather than raising a duplicate error.
  select * into v_item from app.finance_ar_open_items
    where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
  if found then
    return v_item;
  end if;

  select * into v_customer from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_ar_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_ar_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  -- CG-AUDIT-2026-09-02 B3: a credit_note posts a real NEGATIVE AR balance
  -- (a reduction of what the customer owes) -- every other source type
  -- keeps the original positive-only rule, unchanged.
  if p_source_document_type = 'credit_note' then
    if p_original_amount is null or p_original_amount >= 0 then
      raise exception 'finance_ar_invalid_amount: a credit note''s own original amount must be negative, got %', p_original_amount
        using errcode = 'check_violation';
    end if;
  else
    if p_original_amount is null or p_original_amount <= 0 then
      raise exception 'finance_ar_invalid_amount: original amount must be positive, got %', p_original_amount
        using errcode = 'check_violation';
    end if;
  end if;

  if p_due_date < p_invoice_date then
    raise exception 'finance_ar_invalid_due_date: due date % is before invoice date %', p_due_date, p_invoice_date
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_invoice_date);
  if not found then
    raise exception 'finance_ar_period_not_found: no fiscal period covers %', p_invoice_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_ar_period_not_open: fiscal period % for % is not open', v_period.period_code, p_invoice_date
      using errcode = 'check_violation';
  end if;

  insert into app.finance_ar_open_items (
    tenant_id, company_id, customer_account_id, source_document_type, source_document_id,
    currency, original_amount, invoice_date, due_date, posting_period_id, created_by
  ) values (
    p_tenant_id, p_company_id, p_customer_account_id, p_source_document_type, p_source_document_id,
    p_currency, p_original_amount, p_invoice_date, p_due_date, v_period.period_id, p_actor_label
  )
  returning * into v_item;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_ar_open_item',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$
;

-- ===========================================================================
-- 3b. Widen app.validate_finance_open_item_source (ISS-2026-319,
--     20260901060000) -- its own else-branch deliberately raises
--     finance_open_item_unvalidated_source_type for any source_document_type
--     the CHECK constraint admits but this guard doesn't yet know, exactly
--     so that step 2's widening above would fail loudly here instead of
--     silently reopening the fabricated-source-id gap that migration closed.
--     A credit_note's own source_document_id is app.finance_credit_notes.id
--     -- by the time app.issue_finance_credit_note (below) inserts the AR
--     open item, it has already inserted and holds a real v_credit_note row
--     with that id, so this lineage check resolves correctly. CREATE OR
--     REPLACE, same signature -- both existing triggers keep pointing at it.
-- ===========================================================================

create or replace function app.validate_finance_open_item_source()
returns trigger
language plpgsql
as $$
begin
  if TG_TABLE_NAME = 'finance_ar_open_items' then
    if NEW.source_document_type = 'invoice' then
      if not exists (select 1 from app.finance_invoices where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.finance_invoices row for source_document_type invoice', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    elsif NEW.source_document_type = 'opening_balance' then
      if not exists (select 1 from app.import_staging_rows where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.import_staging_rows row for source_document_type opening_balance', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    elsif NEW.source_document_type = 'credit_note' then
      if not exists (select 1 from app.finance_credit_notes where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.finance_credit_notes row for source_document_type credit_note', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    else
      raise exception 'finance_open_item_unvalidated_source_type: % has no lineage rule for app.finance_ar_open_items in app.validate_finance_open_item_source -- widen the guard alongside the CHECK constraint', NEW.source_document_type
        using errcode = 'check_violation';
    end if;
  elsif TG_TABLE_NAME = 'finance_ap_open_items' then
    if NEW.source_document_type = 'vendor_bill' then
      if not exists (select 1 from app.finance_vendor_bills where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.finance_vendor_bills row for source_document_type vendor_bill', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    elsif NEW.source_document_type = 'opening_balance' then
      if not exists (select 1 from app.import_staging_rows where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.import_staging_rows row for source_document_type opening_balance', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    else
      raise exception 'finance_open_item_unvalidated_source_type: % has no lineage rule for app.finance_ap_open_items in app.validate_finance_open_item_source -- widen the guard alongside the CHECK constraint', NEW.source_document_type
        using errcode = 'check_violation';
    end if;
  end if;

  return NEW;
end;
$$;

-- ===========================================================================
-- 4. app.issue_finance_credit_note -- the new, bounded entry point
-- ===========================================================================

create function app.issue_finance_credit_note(
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
  'CG-AUDIT-2026-09-02 B3: FIN:Edit-gated, idempotent, mandatory-reason credit note against an already-ISSUED invoice. Caps cumulative credits on the same invoice at its own original AR amount (never over-credited). Posts a real, negative app.finance_ar_open_items row via app.post_finance_ar_open_item (the same shared primitive app.issue_finance_invoice itself uses) -- correctly reduces the customer''s aggregate net AR exposure (app.get_finance_ar_exposure_summary, B4) with zero further change needed there. Deliberately posts no GL journal entry (disclosed, mirrors app.finance_ar_open_items''/app.finance_receipts'' own identical scoping) and builds no "apply this credit to a future invoice" allocation flow -- the credit stands as an independent, real reduction to the customer''s AR balance.';

-- ===========================================================================
-- 5. Narrow app.search_finance_ar_candidates_for_receipt (FIN-198) -- a
--    customer cash receipt has no sensible meaning "applied against" a
--    standing credit balance. CREATE OR REPLACE, same signature.
-- ===========================================================================

create or replace function app.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_ar_open_items
language plpgsql
stable security definer
set search_path to 'app', 'pg_temp'
as $$
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
      -- CG-AUDIT-2026-09-02 B3: a standing credit balance is never a
      -- receipt-allocation candidate -- only genuinely positive, owed
      -- amounts are.
      and original_amount > 0
    order by due_date asc
    limit 200;
end;
$$;

-- ===========================================================================
-- 6. Grants -- per ERR-2026-004, explicit revoke before the real grant.
-- ===========================================================================

revoke execute on function app.issue_finance_credit_note(uuid, uuid, numeric, text, date, text, uuid, text) from public;
grant execute on function app.issue_finance_credit_note(uuid, uuid, numeric, text, date, text, uuid, text) to authenticated, service_role;

alter table app.finance_credit_notes enable row level security;
grant select, insert, update, delete on app.finance_credit_notes to service_role;

-- ===========================================================================
-- 7. RGL-394 Option-2 public.* wrapper
-- ===========================================================================

create function public.issue_finance_credit_note(p_tenant_id uuid, p_invoice_id uuid, p_amount numeric, p_reason text, p_credit_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_credit_notes
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.issue_finance_credit_note(p_tenant_id, p_invoice_id, p_amount, p_reason, p_credit_date, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.issue_finance_credit_note(p_tenant_id uuid, p_invoice_id uuid, p_amount numeric, p_reason text, p_credit_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.issue_finance_credit_note with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ERR-2026-004: a fresh CREATE FUNCTION in schema public silently inherits the
-- platform-level "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
-- GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role" rule --
-- revoking from public alone does not undo the anon/authenticated/service_role
-- portion of that default. Explicit, directly-provable revoke of all four
-- before the real, narrower re-grant below.
revoke execute on function public.issue_finance_credit_note(p_tenant_id uuid, p_invoice_id uuid, p_amount numeric, p_reason text, p_credit_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.issue_finance_credit_note(p_tenant_id uuid, p_invoice_id uuid, p_amount numeric, p_reason text, p_credit_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
