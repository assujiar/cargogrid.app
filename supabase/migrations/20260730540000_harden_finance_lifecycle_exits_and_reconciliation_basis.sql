-- CG-S10-ATW-032 (post-Prompt-248 finance audit) — five verified findings across the
-- order-to-cash / procure-to-pay lifecycle and the Financial Close reconciliation basis.
-- Every one was re-derived from the live post-migration catalogue and from the ratified
-- Finance capability headers (FIN-195/197/200/201/209) before being treated as a defect,
-- and each function replaced below was re-read from `pg_get_functiondef` immediately
-- before it was edited rather than retyped from a remembered shape.
--
-- 1. **A discarded invoice draft permanently wedged its own billing-readiness handoff.**
--    `FIN-197`'s own header states the design intent plainly — numbering is "assigned only
--    at issue time (never at draft time, so a discarded draft never burns a number)" — i.e.
--    discarding a draft is meant to be non-destructive. It was not. Three facts combined:
--    `app.finance_invoices` carried a TOTAL `unique (tenant_id, billing_readiness_handoff_id)`
--    (`finance_invoices_handoff_unique`); `app.discard_finance_invoice_draft` sets
--    `status = 'void'` and leaves the row in place; and `void` is ABSORBING — every other
--    status writer on the table guards on a specific prior status
--    (`submit_` on `draft`, `approve_` on `submitted`, `issue_` on `approved`), so no edge
--    leads out of `void`. The voided row therefore occupied the handoff's only slot forever.
--    `app.prepare_finance_invoice_from_readiness`'s replay lookup made this terminal rather
--    than merely awkward: it matched on `(tenant_id, billing_readiness_handoff_id)` with NO
--    status predicate, so a retry did not fail with a constraint violation the caller could
--    read — it silently RETURNED the voided invoice as though it were a live draft. An
--    operator who discarded a draft entered in error could never invoice that handoff again,
--    and `app.handoff_billing_readiness` is not a re-runnable escape hatch: a second handoff
--    is a distinct row representing a distinct re-evaluation, not a correction of the first.
--    Fixed on both sides of the same rule, because either alone is insufficient: the total
--    constraint is replaced by a partial unique index excluding voided rows (the uniqueness
--    invariant that was actually intended — one LIVE invoice per handoff, not one row ever),
--    and the replay lookup gains `and status <> 'void'` so it can no longer hand a voided
--    row back to a caller asking for a workable draft. The partial-index shape is this
--    repository's own existing idiom for exactly this distinction — `finance_invoices`
--    already carries `finance_invoices_tenant_number_unique ... where invoice_number is not
--    null`, and `finance_vendor_bills` two more of the same form.
--
--    The identical shape existed on `app.finance_vendor_bills` /
--    `finance_vendor_bills_actual_cost_vendor_unique` /
--    `app.prepare_finance_vendor_bill_from_actual_cost`, and the vendor-bill void path was
--    checked independently rather than assumed symmetric: `app.discard_finance_vendor_bill_draft`
--    writes the same terminal `void`, and `submit_`/`approve_`/`post_finance_vendor_bill`
--    each guard on `draft`/`submitted`/`approved` respectively, so `void` is absorbing there
--    too. Same treatment applied. No FK anywhere references either constraint (both
--    line tables reference the primary key), so replacing them is safe.
--
-- 2. **A settlement whose AP open item was consumed by a competitor was stuck in `executed`
--    forever.** `executed` is not a paperwork state — `app.execute_finance_settlement`
--    records `execution_reference`/`executed_by`/`executed_at`, meaning a real payment
--    instruction has left the bank. From there the ONLY outgoing edge is
--    `app.post_finance_settlement` (`status <> 'executed'` rejects everything else), and
--    that edge calls `app.apply_finance_ap_settlement` per allocation, which raises
--    `finance_ap_over_settlement` unconditionally once `p_amount > open_amount`. Two
--    settlements prepared against the same AP open item are permitted — allocations are
--    validated at prepare time, not held — so the loser of that race is a settlement that
--    can never post (the AP item is already consumed), can never reverse
--    (`request_finance_settlement_reversal` requires `posted`), and could never be discarded
--    (`discard_finance_settlement_draft` guarded `status not in ('draft','submitted')`).
--    It sat in `executed` permanently, contradicting `FIN-201`'s own lifecycle claim and
--    leaving a real bank payment with no governed disposition in the system of record.
--    No schema change is needed: `finance_settlements_status_check` already admits `void`.
--    Fixed by widening `app.discard_finance_settlement_draft` to accept `executed` — but
--    ONLY under conditions proportionate to what `executed` means. For that status alone the
--    function now additionally requires `FIN:Approve` (via this domain's own real authority
--    helper `app.check_finance_settlement_authority`, the same 'Approve' gate
--    `execute_`/`post_`/`request_..._reversal` each use) and a non-empty reason, mirroring
--    `request_finance_settlement_reversal`'s own reason requirement for the other
--    post-execution correction path. `execution_reference`, `executed_by` and `executed_at`
--    are deliberately left untouched by the UPDATE so the evidence that a payment really
--    left the bank survives the void, and the audit event is emitted under a distinct
--    action (`void_finance_executed_settlement`) so a reviewer can never mistake this for an
--    ordinary draft discard. The pre-execution statuses keep their original `FIN:Edit`-only
--    behaviour unchanged; in particular `approved` remains non-discardable.
--
-- 3. **Reconciliation compared two different as-of bases, so any mid-period run reported a
--    false variance.** In `app.execute_finance_reconciliation_run` the GL control side is
--    bounded by whole fiscal periods (`fp.end_date <= p_as_of_date`) — a real and correctly
--    disclosed constraint, since `app.finance_subledger_batches` carries no business
--    posting-date column at all (only `posted_at`, a wall-clock insert timestamp, and
--    `posting_period_id`), so the period's `end_date` is the finest business-date bound the
--    GL side can support. The subledger side, however, was bounded by the DOCUMENT date
--    (`invoice_date` for AR, `bill_date` for AP). Those two bounds only agree when
--    `p_as_of_date` happens to fall on a period end. At `p_as_of_date = 2026-06-15`, an
--    invoice dated 2026-06-05 sitting in period 2026-06 (ending 2026-06-30) is counted on
--    the source side and its own GL batch excluded from the control side — a variance
--    reported against no real discrepancy. That is not cosmetic: the variance auto-writes a
--    `finance_reconciliation_exceptions` row, and `app.certify_finance_reconciliation_run`
--    then refuses to certify with `finance_reconciliation_unexplained_variance` until a human
--    resolves a fabricated exception with a fabricated explanation — precisely the
--    "explainable balances / no silent close on unreconciled data" property `FIN-209`'s own
--    header names as the capability's purpose, inverted into noise. The as-of input is
--    unconstrained in the shipped UI (`reconciliation-forms.tsx` renders a bare
--    `<input type="date" required>` with no min/max and no period-end restriction) and the
--    server action passes it through, so a mid-period date is an ordinary user action, not
--    an exotic one.
--    Fixed by putting BOTH sides on the one basis the GL side can actually support: the
--    function first resolves `v_basis_cutoff`, the last fiscal period `end_date` that has
--    fully elapsed on or before `p_as_of_date`, and bounds the control side and the source
--    side by that single date. Deliberately NOT fixed the other way round (loosening the GL
--    side to the document date) because the data to do so does not exist — inventing a
--    business date for a GL batch would be a fabrication, not a fix. The requested
--    `p_as_of_date` is still what is persisted in `finance_reconciliation_runs.as_of_date`
--    (that column is the user's question, not the engine's internal basis); the basis
--    actually used is surfaced in the exception description and in the audit payload
--    (`comparisonBasisCutoff`) so certification evidence records it rather than hiding it.
--    The no-elapsed-period case is handled explicitly: when no fiscal period has ended on or
--    before `p_as_of_date` the function raises `finance_reconciliation_no_elapsed_period`
--    rather than comparing 0 against 0, declaring itself within tolerance, and offering a
--    vacuously certifiable run as close evidence.
--
-- 4. **`execute_finance_reconciliation_run` stored `p_company_id` but never filtered by it.**
--    The parameter appeared exactly once in the whole body — in the INSERT that tags the run
--    row. All three queried tables carry `company_id` (`finance_subledger_batches`,
--    `finance_ar_open_items`, `finance_ap_open_items`); `app.list_finance_reconciliation_runs`
--    filters runs by it; and the architecturally sibling `app.get_finance_aging_report`
--    genuinely applies `and (p_company_id is null or i.company_id = p_company_id)` on the
--    very same open-item tables. A run row labelled "company A" carrying tenant-wide totals
--    is not a harmless mislabel — it is certification evidence asserting something it never
--    measured. Fixed by applying the same `(p_company_id is null or <table>.company_id =
--    p_company_id)` predicate `get_finance_aging_report` already uses, on the control side
--    and on both source sides, plus on the fiscal-period scan that derives the basis cutoff
--    in finding 3 (so a company-scoped run is bounded by that company's own calendar, per
--    `app.resolve_finance_period_for_date`'s own company convention).
--    Stated honestly: this is LATENT for every UI user today. `executeFinanceReconciliationRunAction`
--    never sets `companyId`, and the contract defaults it to `null`, so the shipped path
--    always requested the tenant-wide totals it actually got. It materializes only for a
--    direct RPC caller (or any future UI that adds a company selector) — which is exactly
--    when a wrong answer would be trusted, and is why it is fixed now rather than deferred.
--
-- 5. **Fixed-amount tax rules were applied without checking the rule's own currency.**
--    `finance_tax_rule_versions_fixed_amount_currency_check` exists specifically so that a
--    `rate_basis = 'fixed_amount'` rule can never be created without a `currency` — the
--    schema already asserts that a fixed duty is denominated, not dimensionless.
--    `app.calculate_finance_tax` faithfully returns both facts (`'rateBasis'` and
--    `'currency'`, confirmed against the live function body, not assumed). Both consumers
--    then discarded them: `app.prepare_finance_invoice_from_readiness` and
--    `app.prepare_finance_vendor_bill_from_actual_cost` read only `taxAmount` and
--    `ruleVersionId`. A fixed IDR duty resolved for a USD document was therefore written
--    verbatim into `tax_amount` on a USD invoice and summed into a USD total — a
--    magnitude-scale error, unconverted and unflagged. Multi-currency is a real posture in
--    this system, not a hypothetical: five currencies are seeded (EUR/IDR/JPY/SGD/USD) and
--    `app.convert_finance_amount` exists; and `RPD-016` keeps these rules tenant-configurable
--    (`app.create_finance_tax_rule_draft` -> `app.approve_finance_tax_rule`), which is what
--    makes a mismatched rule reachable by ordinary configuration rather than only by seed.
--    Fixed by raising a named `finance_tax_rule_currency_mismatch` in each preparer when the
--    resolved rule's basis is `fixed_amount` and its currency differs from the document's own
--    currency (`revenue_snapshot ->> 'currency'` for the invoice, `shipment_actual_costs.currency`
--    for the vendor bill). Deliberately a refusal, not an auto-conversion: converting here
--    would need an FX rate and an as-of/rate-type policy this call site has no governed basis
--    to choose, and silently converting a statutory duty is a worse failure than refusing to
--    apply it. `percentage` rules are untouched — their result is denominated in the base
--    amount's own currency by construction, so the rule's `currency` is not a claim about the
--    output there.
--
-- ===========================================================================
-- Notes on scope, and on what this migration deliberately does not do
-- ===========================================================================
--
-- * Findings 1 and 5 both land in `app.prepare_finance_invoice_from_readiness` and
--   `app.prepare_finance_vendor_bill_from_actual_cost`; each of those functions is replaced
--   exactly ONCE below, carrying both changes, rather than twice.
-- * `app.discard_finance_invoice_draft` / `app.discard_finance_vendor_bill_draft` are NOT
--   replaced. Their behaviour is correct — a discarded draft SHOULD become `void` and stay
--   there. Finding 1 was never that voiding is wrong; it was that a total uniqueness rule and
--   a status-blind replay lookup made `void` mean "this handoff is retired" instead of "this
--   attempt is retired". The fix belongs in the constraint and the lookup, not in the discard.
-- * No `ISS-2026-0xx` identifier is cited in the inline comments below: the highest allocated
--   id in `docs/runtime/KNOWN_ISSUES.md` is `ISS-2026-035`, and no id has been allocated for
--   this batch yet. Citing an unallocated one would create a dangling reference; the
--   checkpoint tag `ATW-032` is used instead.
-- * `scripts/db-tests/finance-reconciliation.sql`'s own "as-of-date bounding" scenario asserts
--   `source_total = 500` for a run as of 2026-06-25 against open items dated 2026-06-20 and
--   2026-07-20 — which is precisely finding 3's defect expressed as an expectation (that same
--   run's control side reads 0, so it was already producing the false variance described
--   above). That scenario is updated in the same change set to assert the corrected shared
--   basis; the two other callers of this function in `db:test`
--   (`finance-dashboard.sql`, `finance-integrated-verification.sql`) both run as of
--   2026-07-31, a real period end, and are unaffected by construction.
--
-- Schema: two total UNIQUE constraints are replaced by partial unique indexes of the same
-- columns excluding voided rows (finding 1). No column, policy, RLS rule or grant is touched,
-- and no already-applied migration file is edited. Five `CREATE OR REPLACE FUNCTION`, each on
-- the byte-identical signature and reproducing the existing LANGUAGE/SECURITY attributes
-- exactly as `pg_get_functiondef` prints them.
--
-- No grant block: `CREATE OR REPLACE` preserves an existing ACL, so there is nothing to
-- restore, and a blanket re-grant in a mechanical sweep is how an internal helper quietly
-- becomes a public API.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public`.

-- ===========================================================================
-- Finding 1 (schema half): one LIVE invoice per handoff / one LIVE bill per
-- (actual cost, vendor) -- not one row ever.
-- ===========================================================================

alter table app.finance_invoices drop constraint finance_invoices_handoff_unique;

create unique index finance_invoices_handoff_active_unique
  on app.finance_invoices (tenant_id, billing_readiness_handoff_id)
  where status <> 'void';

comment on index app.finance_invoices_handoff_active_unique is
  'ATW-032: replaces the total finance_invoices_handoff_unique. FIN-197 intends one invoice per BillingReadinessHandoff; a VOIDED invoice is a retired attempt, not a retired handoff, and must not occupy the slot forever (void is absorbing -- no status writer on this table leads out of it).';

alter table app.finance_vendor_bills drop constraint finance_vendor_bills_actual_cost_vendor_unique;

create unique index finance_vendor_bills_actual_cost_vendor_active_unique
  on app.finance_vendor_bills (tenant_id, actual_cost_id, vendor_master_id)
  where status <> 'void';

comment on index app.finance_vendor_bills_actual_cost_vendor_active_unique is
  'ATW-032: replaces the total finance_vendor_bills_actual_cost_vendor_unique, for the same reason as finance_invoices_handoff_active_unique -- discard_finance_vendor_bill_draft writes a terminal void, and submit_/approve_/post_finance_vendor_bill each guard on a specific prior status, so void is absorbing here too.';

-- ===========================================================================
-- Findings 1 + 5: the two preparers.
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.prepare_finance_invoice_from_readiness(p_tenant_id uuid, p_billing_readiness_handoff_id uuid, p_payment_term_days integer, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
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
  v_subtotal := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);
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

  insert into app.finance_invoices (
    tenant_id, company_id, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, subtotal_amount, tax_amount, payment_term_days, created_by
  )
  values (
    p_tenant_id, v_job.org_unit_id, v_job.account_id, v_job.id, p_billing_readiness_handoff_id,
    v_currency, v_subtotal, v_tax_amount, coalesce(p_payment_term_days, 30), p_actor_label
  )
  returning * into v_invoice;

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

CREATE OR REPLACE FUNCTION app.prepare_finance_vendor_bill_from_actual_cost(p_tenant_id uuid, p_actual_cost_id uuid, p_vendor_master_id uuid, p_vendor_reference text, p_bill_date date, p_payment_term_days integer, p_vendor_stated_amount numeric, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
AS $function$
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

-- ===========================================================================
-- Finding 2: a governed exit from `executed` for a settlement that can never post.
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
  v_was_executed boolean;
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
  -- ATW-032: 'executed' had no outgoing edge other than post_finance_settlement,
  -- and that edge fails unconditionally with finance_ap_over_settlement once a
  -- competing settlement has consumed the same AP open item. Such a settlement
  -- could not post, could not reverse (that path requires 'posted') and could not
  -- be discarded -- a real bank payment left permanently without a governed
  -- disposition. finance_settlements_status_check already admits 'void', so this
  -- needs no schema change; it needs an authorized, evidenced exit.
  -- 'approved' is deliberately NOT admitted: execute_finance_settlement is the
  -- correct next step from there and it is not blocked.
  if v_settlement.status not in ('draft', 'submitted', 'executed') then
    raise exception 'finance_settlement_not_cancellable: settlement % is %, only a draft, submitted or executed settlement may be discarded', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  v_was_executed := (v_settlement.status = 'executed');

  -- ATW-032: voiding an EXECUTED settlement is an approval-grade act, not an
  -- editing one -- a payment instruction has already left the bank
  -- (execution_reference/executed_by/executed_at are set). It is therefore held
  -- to the same FIN:Approve gate execute_/post_/request_..._reversal each apply,
  -- and to the same non-empty-reason requirement request_finance_settlement_reversal
  -- already imposes on the other post-execution correction path. The
  -- pre-execution statuses keep their original FIN:Edit-only behaviour exactly.
  if v_was_executed then
    if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant % -- voiding an executed settlement requires approval authority, not edit authority', p_actor_auth_user_id, v_settlement.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'finance_settlement_void_reason_required: a non-empty reason is required to void an executed settlement'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ATW-032: execution_reference, executed_by and executed_at are deliberately
  -- left untouched -- the evidence that a real payment left the bank must survive
  -- the void, not be erased by it.
  update app.finance_settlements set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  -- ATW-032: a distinct action so a reviewer reading the audit trail can never
  -- mistake the voiding of a real executed payment for an ordinary draft discard.
  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label,
    case when v_was_executed then 'void_finance_executed_settlement' else 'discard_finance_settlement_draft' end,
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$
;

-- ===========================================================================
-- Findings 3 + 4: one comparison basis, and a company scope that is honoured.
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE plpgsql
AS $function$
declare
  v_run app.finance_reconciliation_runs;
  v_control_account app.finance_accounts;
  v_control_total numeric(14, 2) := 0;
  v_source_total numeric(14, 2) := 0;
  v_within boolean;
  v_source_document_type text;
  v_basis_cutoff date;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_scope not in ('ar', 'ap') then
    raise exception 'finance_reconciliation_invalid_scope: % is not a supported reconciliation scope', p_scope
      using errcode = 'check_violation';
  end if;
  if p_tolerance_amount is null or p_tolerance_amount < 0 then
    raise exception 'finance_reconciliation_invalid_tolerance: % must be a non-negative amount', p_tolerance_amount
      using errcode = 'check_violation';
  end if;

  v_control_account := app.resolve_finance_posting_map_account(p_tenant_id, p_scope || '_control');
  v_source_document_type := case when p_scope = 'ar' then 'invoice' else 'vendor_bill' end;

  -- ATW-032: ONE comparison basis for both sides. The GL side can only be
  -- bounded by whole fiscal periods -- app.finance_subledger_batches carries no
  -- business posting-date column at all (only posted_at, a wall-clock insert
  -- timestamp, and posting_period_id), a real constraint this function's
  -- original comment already disclosed. The source side was bounded by the
  -- document date instead, so the two agreed ONLY when p_as_of_date happened to
  -- land on a period end; every other as-of date counted documents on the source
  -- side whose own GL batches sat in a not-yet-elapsed period and were excluded
  -- from the control side. That fabricated variance auto-opened a
  -- finance_reconciliation_exceptions row and blocked
  -- certify_finance_reconciliation_run with finance_reconciliation_unexplained_variance.
  -- The cutoff is therefore the last fiscal period end that has fully elapsed on
  -- or before p_as_of_date, and BOTH sides are bounded by it. The GL side is
  -- unchanged in meaning by this (no period ends strictly between v_basis_cutoff
  -- and p_as_of_date, by construction of the max) -- it is written against the
  -- cutoff so that the shared basis is explicit rather than coincidental.
  -- Company scope (ATW-032, finding 4) is applied here too, so a company-scoped
  -- run is bounded by that company's own calendar -- the same company convention
  -- app.resolve_finance_period_for_date applies when it resolves a posting period.
  select max(fp.end_date) into v_basis_cutoff
    from app.finance_fiscal_periods fp
    where fp.tenant_id = p_tenant_id
      and (p_company_id is null or fp.company_id = p_company_id)
      and fp.end_date <= p_as_of_date;

  -- ATW-032: handled explicitly rather than silently. With no elapsed period the
  -- control side is necessarily zero, so a naive comparison would report 0 vs 0,
  -- declare itself within tolerance, and offer a vacuously certifiable run as
  -- Financial Close evidence -- the exact "silent close on unreconciled data"
  -- FIN-209 exists to prevent.
  if v_basis_cutoff is null then
    raise exception 'finance_reconciliation_no_elapsed_period: no fiscal period has fully ended on or before % for this scope, so there is no basis on which the GL control side can be compared', p_as_of_date
      using errcode = 'no_data_found';
  end if;

  -- ATW-032 (finding 4): p_company_id was stored on the run row and never used
  -- to filter anything, so a run tagged with one company reported tenant-wide
  -- totals. app.get_finance_aging_report -- the architecturally identical sibling
  -- over the same open-item tables -- already applies exactly this predicate.
  select coalesce(sum(case when p_scope = 'ar' then (case when l.direction = 'debit' then l.amount else -l.amount end) else (case when l.direction = 'credit' then l.amount else -l.amount end) end), 0)
    into v_control_total
    from app.finance_subledger_lines l
    join app.finance_subledger_batches b on b.id = l.batch_id
    join app.finance_fiscal_periods fp on fp.id = b.posting_period_id
    where b.tenant_id = p_tenant_id
      and (p_company_id is null or b.company_id = p_company_id)
      and l.account_id = v_control_account.id
      and fp.end_date <= v_basis_cutoff;

  -- ATW-032: the source (open-item) side is bounded by each domain's own real
  -- business date column (invoice_date for AR, bill_date for AP, never created_at)
  -- as before -- but now against the SAME elapsed-period cutoff the control side
  -- uses, not against the raw requested as-of date.
  if p_scope = 'ar' then
    select coalesce(sum(i.open_amount), 0) into v_source_total
      from app.finance_ar_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.source_document_type = v_source_document_type
        and i.invoice_date <= v_basis_cutoff;
  else
    select coalesce(sum(i.open_amount), 0) into v_source_total
      from app.finance_ap_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.source_document_type = v_source_document_type
        and i.bill_date <= v_basis_cutoff;
  end if;

  v_within := abs(v_control_total - v_source_total) <= p_tolerance_amount;

  -- ATW-032: as_of_date still records what the caller ASKED for; v_basis_cutoff
  -- is the basis the engine could actually answer on, and is disclosed in the
  -- exception description and the audit payload rather than hidden.
  insert into app.finance_reconciliation_runs (tenant_id, company_id, scope, as_of_date, tolerance_amount, control_total, source_total, is_within_tolerance, prepared_by)
  values (p_tenant_id, p_company_id, p_scope, p_as_of_date, p_tolerance_amount, v_control_total, v_source_total, v_within, p_actor_label)
  returning * into v_run;

  if not v_within then
    insert into app.finance_reconciliation_exceptions (run_id, tenant_id, description, expected_amount, actual_amount)
    values (v_run.id, p_tenant_id, format('%s control account (%s) balance does not match open-item total within tolerance %s (comparison basis: fiscal periods ending on or before %s)', upper(p_scope), v_control_account.code, p_tolerance_amount, v_basis_cutoff), v_source_total, v_control_total);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', null, null,
    to_jsonb(v_run) || jsonb_build_object('comparisonBasisCutoff', v_basis_cutoff)
  );

  return v_run;
end;
$function$
;

revoke execute on all functions in schema app from public;
