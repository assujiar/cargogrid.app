-- HDN-374 Tier C (Financial Integrity Audit, `CG-S15-HDN-006`) -- four independent adversarial
-- review lenses ran against the committed checkpoint (`e4744dd`, `20260811000000_harden_
-- financial_integrity_invoicing_and_idempotency.sql`) and, together with a separate lens's own
-- `app.lock_finance_period` completeness gap already fixed at `20260811100000_harden_finance_
-- period_lock_idempotency_race.sql`, found 3 more real, live-forced High-severity defects. Full
-- disposition: `docs/build-log/full-system-hardening/HDN-374.md` §13.
--
-- ===========================================================================
-- Tier C finding 1 -- Finding 1's own fix drops the quote's own discount, overbilling by the
-- discount amount (High)
-- ===========================================================================
--
-- `app.quotations.subtotal_amount` (surfaced into `revenue_snapshot.subtotalAmount`) is
-- `sum(quotation_lines.line_gross_amount)` -- the raw, PRE-DISCOUNT gross
-- (`app.recalculate_quotation_totals`, `20260724210000_create_commercial_quotation_
-- builder.sql`). `discount_amount` (`revenue_snapshot.discountAmount`) is the separate
-- `sum(line_discount_amount)`. The genuine pre-tax NET base every line's own tax was actually
-- computed on (`v_net := v_gross - v_discount`, then `v_tax := v_net * tax_pct/100`,
-- `20260724240000_create_commercial_quotation_versioning.sql:462-465`) is `subtotalAmount -
-- discountAmount`, not `subtotalAmount` alone. The prior fix (`20260811000000`) read
-- `subtotalAmount` unchanged by discount -- correct only when `discount_pct = 0` (the
-- checkpoint's own regression fixture); for any discounted quote it silently overbills by
-- exactly the discount amount, compounding further once `p_tax_code` computes tax on the
-- inflated base.
--
-- **Live-forced** (Tier C Lens A): a quote line with gross=1,000,000, discount_pct=8
-- (discount=80,000, true pre-tax base=920,000) invoiced to `subtotal_amount=1,000,000.00`
-- instead of `920,000.00` -- an 80,000 overbill before tax is even applied.
--
-- **Fix**: read `discountAmount` alongside `subtotalAmount` and subtract it. `discountAmount`
-- is always present (line-level `coalesce(p_discount_pct, 0)` then header-level
-- `coalesce(sum(...), 0)`), so a discount-free quote's own `discountAmount` is `0` and this
-- change is a no-op for the checkpoint's own already-passing regression fixture.
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

-- ===========================================================================
-- Tier C finding 2 -- Finding 2's own `app.issue_finance_invoice` guard has no backing
-- constraint and does not survive genuine concurrency (High)
-- ===========================================================================
--
-- The `exists()` check `20260811000000` added to `app.issue_finance_invoice` is a plain
-- SELECT with no lock and no backing unique index -- a textbook TOCTOU gap. **Live-forced**
-- (Tier C Lens A): two approved (not-yet-issued) invoices from two distinct handoffs on one
-- job order, issued via two genuinely concurrent sessions (synchronized on real lock
-- contention over `finance_invoice_number_counters`) -- BOTH reached `issued`, doubling the
-- bill exactly as `ISS-2026-195` itself describes, disproving the guard's own claim to close
-- it.
--
-- **Fix**: a real backing partial unique index, `finance_invoices_job_order_issued_unique on
-- (tenant_id, job_order_id) where status = 'issued'` -- structurally impossible for two
-- invoices on one job order to both be `issued` no matter how many sessions race, mirroring
-- every other guard this checkpoint's own migration already backs with a real constraint
-- rather than a bare application-level check. `app.issue_finance_invoice`'s own `update ...
-- set status = 'issued'` is wrapped in the same `begin ... exception when unique_violation`
-- pattern, re-raising the SAME named `finance_invoice_job_order_already_issued` exception the
-- non-concurrent path already raises, rather than a raw `unique_violation` reaching the
-- caller. The `exists()` pre-check is kept (a normal, non-racing caller gets the clear named
-- error immediately, without waiting for a constraint violation).
create unique index finance_invoices_job_order_issued_unique on app.finance_invoices (tenant_id, job_order_id) where status = 'issued';

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
$function$
;

-- ===========================================================================
-- Tier C finding 3 -- app.request_finance_settlement_reversal bypasses fiscal period lock
-- entirely (High)
-- ===========================================================================
--
-- `app.request_finance_settlement_reversal` (the sole governed path to reverse a posted AP
-- settlement, composing `app.reverse_finance_ap_settlement`) has NO fiscal-period-lock check
-- anywhere in its own body or call graph, unlike `app.post_finance_settlement`, which
-- correctly refuses to post when `resolve_finance_period_for_date(...).posting_eligible` is
-- false. **Live-forced** (Tier C Lens D): a posted settlement in a period subsequently
-- LOCKED was still successfully reversed by an ordinary FIN:Approve holder, dropping the AP
-- open item back to `open` while its own already-posted GL journal remained untouched --
-- exactly the "period lock cannot be bypassed by normal roles" business rule (Prompt 374
-- §24) failing live.
--
-- **Fix, bounded to this checkpoint's own charter**: deny the reversal when the ORIGINAL
-- settlement's own posting period (`v_settlement.settlement_date`) is locked, mirroring
-- `post_finance_settlement`'s own established check pattern exactly. This closes the
-- period-lock bypass itself. **Separately registered, not fixed here**: this function never
-- posts a reversing GL journal at all (only the AP subledger's own `settled_amount`/`status`
-- are mutated) -- composing a correct automatic reversal journal is a larger design decision
-- (account mapping, whether reversal should be automatic vs. a separate governed step
-- mirroring `app.prepare_finance_journal_reversal`) outside a bounded-repair checkpoint's own
-- scope; registered `ISS-2026-199`/`HDN-BLK-016`, owner `HDN-386`.
create or replace function app.request_finance_settlement_reversal(
  p_settlement_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $function$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
  v_period record;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_settlement_reversal_reason_required: a non-empty reason is required to reverse a posted settlement'
      using errcode = 'check_violation';
  end if;
  if v_settlement.status <> 'posted' then
    raise exception 'finance_settlement_not_posted: settlement % is % not posted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 Tier C finding 3: mirrors app.post_finance_settlement's own period-lock check --
  -- a reversal is a financial mutation against the settlement's own original posting period
  -- and must not bypass that period being locked, the same as any other posting.
  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_reversal_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_reversal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.reverse_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, p_reason, 'settlement', v_settlement.id,
      'reversal:' || v_settlement.id::text || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
    update app.finance_settlement_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = v_allocation.id;
  end loop;

  update app.finance_settlements set status = 'reversed', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_settlement_reversal',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$
;

revoke execute on all functions in schema app from public;
