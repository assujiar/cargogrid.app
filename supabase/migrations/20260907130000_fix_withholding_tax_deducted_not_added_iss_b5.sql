-- CG-AUDIT-2026-09-02 B5 (independent launch-readiness audit, finding B5): PPH21/PPH23/
-- PPH4_2 are seeded with finance_tax_codes.tax_type = 'withholding' (a real, pre-existing
-- classification, unused by any code path until this migration), but app.
-- calculate_finance_tax returns base*rate as a plain positive amount with no branch on
-- tax_type at all, and app.prepare_finance_invoice_from_readiness writes that amount
-- straight into finance_invoices.tax_amount, which app.finance_invoices.total_amount
-- (generated always as subtotal_amount + tax_amount) then ADDS to the customer's own
-- billed total -- and app.issue_finance_invoice's own FIN-202 GL posting CREDITS that
-- same amount to a tax-payable liability account. Both are backwards for a genuine
-- withholding tax: the paying customer withholds that amount at source and remits it
-- DIRECTLY to the tax authority on CargoGrid's behalf -- CargoGrid never collects it in
-- cash, and it is not a liability CargoGrid owes; it is a creditable/recoverable asset
-- (the customer's own bukti potong certificate lets CargoGrid offset it against its own
-- income tax liability later), economically identical in nature to the input-VAT credit
-- app.post_finance_vendor_bill's own recoverable_account_id-debit branch already models
-- correctly on the AP side (20260729160000_create_finance_subledger.sql) -- this migration
-- gives the AR/customer-invoice side the same treatment, never invented from scratch.
--
-- Fix, in three parts:
--
-- 1. app.calculate_finance_tax now discloses the resolved rule's own tax_type (from
--    app.finance_tax_codes, via tax_code_id) in its returned jsonb as `taxType`, so a
--    caller can tell an added tax (vat/other) from a withheld one without re-deriving it.
--
-- 2. app.prepare_finance_invoice_from_readiness still computes the SAME positive
--    magnitude and still records a real 'tax' invoice line for it either way (the
--    document must disclose the true withheld/added amount) -- but for a withholding
--    tax_type, that magnitude is written into a NEW finance_invoices.withholding_tax_amount
--    column instead of tax_amount, so total_amount (subtotal_amount + tax_amount) is left
--    untouched by it -- exactly the "deducted, not added" behavior the audit asks for. The
--    new column is additive (default 0, backfills every existing row unchanged) and never
--    touches an applied migration.
--
-- 3. app.issue_finance_invoice now posts the AR open item and its own AR-control debit
--    line for total_amount MINUS withholding_tax_amount (the real cash CargoGrid will
--    actually collect), and, for each invoice tax line whose own tax_code resolves to
--    tax_type='withholding', DEBITS (never credits) the tax rule's own governed
--    recoverable_account_id, or the withholding_tax_receivable_default posting-map key
--    when none is configured -- mirroring the existing output_account_id/
--    tax_payable_default fallback shape exactly, just on the debit side. Every
--    non-withholding tax line's own posting is completely unchanged. The journal still
--    balances: debits (AR net-of-withholding + withholding-receivable) equal credits
--    (revenue + any added tax), both summing to total_amount.

alter table app.finance_invoices add column withholding_tax_amount numeric(14, 2) not null default 0;
alter table app.finance_invoices add constraint finance_invoices_withholding_tax_check check (withholding_tax_amount >= 0);

comment on column app.finance_invoices.withholding_tax_amount is
  'CG-AUDIT-2026-09-02 B5: the portion of this invoice''s value that a withholding-type tax code (finance_tax_codes.tax_type = ''withholding'', e.g. PPH21/PPH23/PPH4_2) deducts at source -- withheld by the customer and remitted directly to the tax authority, never collected by CargoGrid in cash. Deliberately excluded from tax_amount (and therefore from total_amount = subtotal_amount + tax_amount, unchanged): the invoice''s own face/total value is not reduced by a withholding tax, only the cash actually collectible is -- app.issue_finance_invoice''s own AR-control debit and AR open item amount are total_amount minus this column, and the journal''s balancing debit lands on the tax rule''s own recoverable_account_id (or the withholding_tax_receivable_default posting-map key), a creditable asset, never a liability credit.';

create or replace function app.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_rule app.finance_tax_rule_versions;
  v_code app.finance_tax_codes;
  v_mode text;
  v_precision integer;
  v_raw numeric;
  v_tax_amount numeric;
  v_rounding_row record;
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_base_amount is null or p_base_amount < 0 then
    raise exception 'finance_tax_rule_invalid_base_amount: base amount must be non-negative, got %', p_base_amount
      using errcode = 'check_violation';
  end if;

  select * into v_rule from app.resolve_finance_tax_rule(p_tenant_id, p_tax_code, coalesce(p_as_of, current_date));
  if not found then
    raise exception 'finance_tax_rule_missing: no approved tax rule for % covers %', p_tax_code, coalesce(p_as_of, current_date)
      using errcode = 'no_data_found';
  end if;

  -- CG-AUDIT-2026-09-02 B5: tax_code_id is a NOT NULL FK already resolved by
  -- resolve_finance_tax_rule's own join -- guaranteed to exist, no found-check needed.
  select * into v_code from app.finance_tax_codes where id = v_rule.tax_code_id;

  v_raw := case when v_rule.rate_basis = 'percentage' then p_base_amount * v_rule.rate_value else v_rule.rate_value end;

  v_mode := 'round_half_up';
  v_precision := 2;
  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'tax_calculation' then
      v_mode := coalesce(v_rounding_row.items -> 'tax_calculation' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'tax_calculation' ->> 'precision')::integer, v_precision);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
    end if;
  end loop;

  v_tax_amount := app.apply_finance_rounding(v_raw, v_precision, v_mode);

  return jsonb_build_object(
    'baseAmount', p_base_amount,
    'taxCode', p_tax_code,
    'taxType', v_code.tax_type,
    'ruleVersionId', v_rule.id,
    'rateBasis', v_rule.rate_basis,
    'rateValue', v_rule.rate_value,
    'currency', v_rule.currency,
    'taxAmount', v_tax_amount,
    'roundingMode', v_mode,
    'effectiveFrom', v_rule.effective_from,
    'effectiveTo', v_rule.effective_to
  );
end;
$function$;

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
  v_tax_type text;
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
  -- own line-level tax_pct. subtotalAmount is the quotation's own PRE-DISCOUNT gross
  -- (v_quotation.subtotal_amount); Tier C finding 1: the genuine pre-tax NET base every
  -- line's own tax was actually computed on is subtotalAmount minus discountAmount, not
  -- subtotalAmount alone -- both are always present alongside totalAmount, since this is
  -- the sole construction path for a job order's own revenue snapshot
  -- (20260724340000_create_commercial_job_order_lineage.sql's own 'pricing' object).
  v_subtotal := (v_job.revenue_snapshot ->> 'subtotalAmount')::numeric(14, 2) - coalesce((v_job.revenue_snapshot ->> 'discountAmount')::numeric(14, 2), 0);
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
    v_tax_type := v_tax_result ->> 'taxType';
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
      currency, subtotal_amount, tax_amount, withholding_tax_amount, payment_term_days, created_by
    )
    values (
      p_tenant_id, v_job.org_unit_id, v_job.account_id, v_job.id, p_billing_readiness_handoff_id,
      v_currency, v_subtotal,
      -- CG-AUDIT-2026-09-02 B5: a withholding-type tax_code (PPH21/PPH23/PPH4_2) is
      -- deducted at source by the customer, never added to what CargoGrid bills -- so it
      -- is recorded as withholding_tax_amount, NOT tax_amount, and total_amount
      -- (generated as subtotal_amount + tax_amount) is left untouched by it. Only a
      -- vat/exempt/other tax_code still adds to tax_amount, exactly as before.
      case when v_tax_type = 'withholding' then 0 else v_tax_amount end,
      case when v_tax_type = 'withholding' then v_tax_amount else 0 end,
      coalesce(p_payment_term_days, 30), p_actor_label
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
    values (
      v_invoice.id, 2, 'tax',
      p_tax_code || ' tax' || case when v_tax_type = 'withholding' then ' (withheld by customer, not billed)' else '' end,
      v_tax_amount, v_tax_code_id, v_tax_rule_version_id
    );
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_invoice_from_readiness',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

create or replace function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_invoices
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
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
  v_tax_code app.finance_tax_codes;
  v_net_collectible numeric(14, 2);
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
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
  -- most one invoice at a time -- backed by finance_invoices_job_order_issued_unique
  -- (Tier C fix), not merely this application-level pre-check. Draft/submitted/approved
  -- invoices from a legitimate re-handoff (OPS-181) remain freely creatable and discardable
  -- (see the migration header); this is the actual AR/GL posting boundary, so it is the one
  -- place a second full-amount bill for the same job's revenue must be refused.
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

  -- CG-AUDIT-2026-09-02 B5: the amount actually collectible in cash is total_amount
  -- LESS any withholding_tax_amount -- the customer withholds that portion at source and
  -- remits it directly to the tax authority, so it is never a real AR balance CargoGrid
  -- can collect or age. See this fix's own migration header.
  v_net_collectible := v_invoice.total_amount - v_invoice.withholding_tax_amount;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_net_collectible, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the net amount actually collectible (CG-AUDIT-2026-09-02
  -- B5: total_amount minus withholding_tax_amount); credit revenue for the subtotal;
  -- credit each ADDED (non-withholding) tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured); DEBIT each WITHHELD tax
  -- line's own governed recoverable account (or the withholding_tax_receivable_default
  -- posting-map key) -- a creditable asset to CargoGrid, never a payable, mirroring app.
  -- post_finance_vendor_bill's own established recoverable_account_id-debit pattern for
  -- input tax credits on the AP side. The journal still balances: net-collectible AR debit
  -- plus the withholding-receivable debit sums to total_amount, exactly matching revenue
  -- credit plus any added-tax credit.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_net_collectible, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    v_tax_code := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id;
    end if;
    if v_tax_line.tax_code_id is not null then
      select * into v_tax_code from app.finance_tax_codes where id = v_tax_line.tax_code_id;
    end if;
    -- CG-AUDIT-2026-09-02 B5 (found while writing this fix's own regression test, not
    -- previously exercised by any test before it -- every prior fixture left both
    -- output_account_id and recoverable_account_id unconfigured): a plpgsql row variable's
    -- own `IS NOT NULL` is true only when EVERY field of the row is non-null (SQL composite-
    -- type semantics), never merely "was a row found". app.finance_tax_rule_versions and
    -- app.finance_tax_codes both carry other nullable columns (e.g. currency) that are null
    -- on an ordinary fetched row, so `v_tax_rule is not null` / `v_tax_code is not null`
    -- would silently read as false even when the SELECT above found a real row -- checking
    -- each row's own guaranteed-NOT-NULL primary key column instead is the correct,
    -- established idiom (mirrors every `if not found then` check elsewhere in this
    -- codebase, just phrased for a value read after the block that set it rather than
    -- immediately after the SELECT itself).
    if v_tax_code.id is not null and v_tax_code.tax_type = 'withholding' then
      if v_tax_rule.id is not null and v_tax_rule.recoverable_account_id is not null then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
      else
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'withholding_tax_receivable_default', 'direction', 'debit', 'amount', v_tax_line.amount));
      end if;
    elsif v_tax_rule.id is not null and v_tax_rule.output_account_id is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- HDN-374 Tier C finding 2: a genuine race between the exists() pre-check above and this
  -- update (two concurrent issue_finance_invoice calls for two DIFFERENT invoices on the
  -- SAME job order, each already past its own exists() check before either commits) is
  -- caught here by finance_invoices_job_order_issued_unique -- the loser's own update
  -- raises unique_violation instead of silently succeeding; re-raised as the same named
  -- exception the non-concurrent pre-check above already gives, never a raw unique_violation.
  begin
    update app.finance_invoices
      set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
          posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
      where id = p_invoice_id
      returning * into v_invoice;
  exception
    when unique_violation then
      raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;
