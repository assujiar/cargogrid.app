-- CG-AUDIT-2026-09-02 E1 (repeat-order contract-lineage half): app.customer_contracts
-- itself documents that source_quotation_id is set only on a contract's own
-- originating (version 1) row -- a renewal/amendment carries a reason instead.
-- app.build_job_order_draft_payload's contract lookup only ever matched on that
-- exact source_quotation_id, so any repeat order for an already-contracted
-- account -- app.convert_quotation_to_account's own documented "linked_existing"
-- path for a brand-new quotation against an existing account, or a clone via
-- app.clone_quotation -- always resolved the job order's contract snapshot to
-- null, even with a real published, in-force contract for that account.
--
-- Every dollar amount on the job order/invoice was always correct regardless
-- (it comes straight from the quotation's own accepted price lines, never from
-- the contract snapshot), so this is not a financial-correctness bug like B8 --
-- but the contract linkage is real governance/traceability data (which
-- contract/pricelist version was actually in force when a job order was
-- created), and AGENTS.md is explicit that "critical transactions retain the
-- applied version." Silently losing that linkage on every repeat order is a
-- genuine data-lineage gap the audit's E1 finding correctly flagged.
--
-- Fix: when the exact source_quotation_id match misses, fall back to the same
-- published/effective-window resolution app.get_effective_customer_price
-- (COM-156) already uses for exactly this account -- additive only, so the
-- already-working version-1 case (which may legitimately still be draft/
-- unpublished at handoff time) is untouched.
--
-- This function has never been redefined since its original creation
-- (supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql)
-- -- confirmed by grepping every migration for its name before writing this
-- file -- so the body below, mechanically copied from that migration with only
-- the one intended block inserted (verified via a diff against the original),
-- is genuinely the current definition, not a guess.

create or replace function app.build_job_order_draft_payload(p_quotation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_opportunity app.opportunities;
  v_conversion app.account_conversions;
  v_account app.accounts;
  v_contact app.contacts;
  v_decision app.quotation_customer_decisions;
  v_contract app.customer_contracts;
  v_credit_snapshot app.credit_check_snapshots;
  v_lines jsonb;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  select * into v_opportunity from app.opportunities where id = v_quotation.opportunity_id;
  select * into v_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if not found then
    raise exception 'account_not_converted: quotation % has not been converted to an account', p_quotation_id using errcode = 'check_violation';
  end if;
  select * into v_account from app.accounts where id = v_conversion.account_id;
  select * into v_decision from app.quotation_customer_decisions where quotation_id = p_quotation_id;
  if v_quotation.contact_id is not null then
    select * into v_contact from app.contacts where id = v_quotation.contact_id;
  end if;
  select * into v_contract from app.customer_contracts where source_quotation_id = p_quotation_id order by created_at desc limit 1;
  if not found then
    -- COM-160 gap (CG-AUDIT-2026-09-02 E1): source_quotation_id is set only on a
    -- contract's own originating (version 1) row (this table's own comment), so a
    -- repeat/clone quotation later converted against the SAME already-contracted
    -- account (app.convert_quotation_to_account's own "linked_existing" path)
    -- always resolved contract to null here, even with a real published contract
    -- in force. Falls back to the same published/effective-window resolution
    -- app.get_effective_customer_price already uses (COM-156), so a repeat
    -- order's job order snapshot correctly retains which contract/pricelist
    -- version was actually in force at handoff time.
    select * into v_contract
    from app.customer_contracts
    where account_id = v_account.id
      and status = 'published'
      and effective_from <= now()
      and (effective_to is null or effective_to > now())
    order by effective_from desc
    limit 1;
  end if;
  select * into v_credit_snapshot from app.credit_check_snapshots where account_id = v_account.id order by checked_at desc limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'lineNo', l.line_no, 'lineType', l.line_type, 'description', l.description,
      'quantity', l.quantity, 'unitPrice', l.unit_price, 'discountPct', l.discount_pct,
      'taxPct', l.tax_pct, 'lineGrossAmount', l.line_gross_amount, 'lineDiscountAmount', l.line_discount_amount,
      'lineTaxAmount', l.line_tax_amount, 'lineTotal', l.line_total
    ) order by l.line_no
  ), '[]'::jsonb) into v_lines
  from app.quotation_lines l
  where l.quotation_id = p_quotation_id;

  return jsonb_build_object(
    'schemaVersion', 1,
    'source', jsonb_build_object(
      'quotationId', v_quotation.id, 'quoteNumber', v_quotation.quote_number, 'versionNumber', v_quotation.version_number,
      'opportunityId', v_quotation.opportunity_id, 'prospectId', v_quotation.prospect_id, 'accountConversionId', v_conversion.id
    ),
    'customer', jsonb_build_object(
      'accountId', v_account.id, 'customerSnapshot', v_quotation.customer_snapshot,
      'contactId', v_contact.id, 'contactName', v_contact.full_name, 'contactEmail', v_contact.email, 'contactPhone', v_contact.phone
    ),
    'cargoService', coalesce(v_opportunity.requirements, '{}'::jsonb),
    'pricing', jsonb_build_object(
      'currency', v_quotation.currency, 'subtotalAmount', v_quotation.subtotal_amount, 'discountAmount', v_quotation.discount_amount,
      'taxAmount', v_quotation.tax_amount, 'totalAmount', v_quotation.total_amount, 'lines', v_lines
    ),
    'contract', case when v_contract.id is not null then jsonb_build_object('customerContractId', v_contract.id, 'rootContractId', v_contract.root_contract_id, 'versionNumber', v_contract.version_number, 'status', v_contract.status) else null end,
    'credit', case when v_credit_snapshot.id is not null then jsonb_build_object('outcome', v_credit_snapshot.outcome, 'checkedAt', v_credit_snapshot.checked_at) else null end,
    'acceptance', jsonb_build_object('decidedByName', v_decision.decided_by_name, 'decidedAt', v_decision.decided_at, 'decision', v_decision.decision)
  );
end;
$$;

comment on function app.build_job_order_draft_payload is
  'COM-160: deterministic snapshot assembly -- every field traces to exactly one canonical Commercial source (see this migration''s own header). Contains real, unmasked pricing (Operations needs it) -- credit deliberately carries only outcome/checked_at, never a dollar limit, so no monetary figure needing masking exists inside the credit portion at all. Contract resolution (CG-AUDIT-2026-09-02 E1, this migration): tries the exact source_quotation_id match first (the only-ever-correct answer for a contract''s own originating quotation), then falls back to the account''s currently-published, in-force contract (mirrors app.get_effective_customer_price''s own resolution) so a repeat order against an already-contracted account still retains real contract lineage.';
