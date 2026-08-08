-- Batch 4 (264-265, CG-S11-PRC-015/016) Tier C review fix pass (ADR-0021,
-- BUILD_EXECUTION_PROTOCOL.md §5). Every fix below closes a finding CONFIRMED by
-- live reproduction (real disposable Postgres, forged/alternate-actor sessions, real
-- concurrent psql processes) against the batch's own combined diff by four parallel
-- adversarial lenses (spec-compliance; security/RLS/cost-masking; correctness/
-- concurrency; cross-prompt integration). See this batch's own fix commit message for
-- the full four-lens disposition (findings closed / disclosed-not-fixed / rejected as
-- unconfirmed).
--
-- Applied-migration discipline (AGENTS.md, mirrors 20260730690000/20260730730000's own
-- precedent for batches 260/3): every fix here is CREATE OR REPLACE FUNCTION (or a
-- targeted REVOKE/GRANT for the one table-grant fix) against the ORIGINAL, already-
-- applied 20260730740000/20260730750000/20260730760000 migrations -- never an edit to
-- those files themselves. Every fix below preserves its target's existing signature, so
-- CREATE OR REPLACE is safe throughout (Postgres preserves a function's existing ACLs
-- across a same-signature REPLACE) -- no DROP+CREATE, no re-grant needed anywhere in
-- this migration.
--
-- One finding (spec-compliance, MEDIUM, C-23: PRC-265's own build log discloses 11
-- other residual limitations in itemized detail but never names the spec's own fourth
-- alternative-flow item, a credit/correction invoice linked back to the original bill
-- it corrects) is disclosed, not fixed here -- implementing real credit/correction
-- linkage is a genuine new capability (a new column, a new validation route, new UI),
-- not a bounded bug fix this Tier C pass has a mandate to build unilaterally. Recorded
-- as ISS-2026-052 in docs/runtime/KNOWN_ISSUES.md instead.

-- ===========================================================================
-- 1. C-04 (concurrency lens, CRITICAL, live-reproduced): app.create_vendor_bill_match_
--    case's duplicate-fingerprint check is an unlocked check-then-act race. Two
--    concurrently submitted near-duplicate bills each see a snapshot that does not yet
--    include the other's uncommitted insert, so NEITHER is flagged as the other's
--    duplicate -- both commit as ordinary, unflagged cases, defeating the one fraud/
--    double-payment control this capability's own migration header advertises as a
--    headline feature. Fixed by serializing the whole "insert + check for a sibling
--    with the same fingerprint" sequence with a transaction-scoped advisory lock keyed
--    on (tenant_id, fingerprint), acquired BEFORE the insert -- the second racer then
--    blocks until the first commits, and its own duplicate check correctly sees the
--    first's now-committed row. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.create_vendor_bill_match_case(
  p_tenant_id uuid,
  p_bill_id uuid,
  p_purchase_order_id uuid,
  p_is_partial_invoice boolean,
  p_is_consolidated_invoice boolean,
  p_line_inputs jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bill_match_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.vendor_bill_match_cases;
  v_bill app.finance_vendor_bills;
  v_po app.purchase_orders;
  v_contract app.vendor_contracts;
  v_policy app.vendor_bill_match_tolerance_policies;
  v_case app.vendor_bill_match_cases;
  v_bill_line app.finance_vendor_bill_lines;
  v_line_input jsonb;
  v_line app.vendor_bill_match_lines;
  v_component app.shipment_actual_cost_components;
  v_fingerprint text;
  v_dup_case app.vendor_bill_match_cases;
  v_match_mode text;
  v_has_epod boolean := false;
  v_has_delivery_ms boolean := false;
  v_shipment_id uuid;
begin
  if not app.check_vendor_bill_match_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-01: idempotency replay compares the full target tuple, not just the key.
  select * into v_existing from app.vendor_bill_match_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.bill_id is distinct from p_bill_id
      or v_existing.purchase_order_id is distinct from p_purchase_order_id
      or v_existing.is_partial_invoice is distinct from coalesce(p_is_partial_invoice, false)
      or v_existing.is_consolidated_invoice is distinct from coalesce(p_is_consolidated_invoice, false)
    then
      raise exception 'idempotency_key_conflict: key % was already used for a different match case', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_bill from app.finance_vendor_bills where id = p_bill_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: % is not a known vendor bill for tenant %', p_bill_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'void' then
    raise exception 'finance_vendor_bill_void: bill % is void and cannot be matched', p_bill_id using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.vendor_bill_match_cases where bill_id = p_bill_id and is_current) then
    raise exception 'match_case_already_exists: bill % already has a current match case -- use re_evaluate_vendor_bill_match_case', p_bill_id
      using errcode = 'check_violation';
  end if;

  if p_line_inputs is null or jsonb_typeof(p_line_inputs) <> 'array' then
    raise exception 'line_inputs_required: p_line_inputs must be a jsonb array' using errcode = 'check_violation';
  end if;

  if p_purchase_order_id is not null then
    select * into v_po from app.purchase_orders where id = p_purchase_order_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'purchase_order_not_found: % is not a known purchase order for tenant %', p_purchase_order_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    if v_po.vendor_master_id <> v_bill.vendor_master_id then
      raise exception 'po_vendor_mismatch: purchase order % belongs to a different vendor than bill %', p_purchase_order_id, p_bill_id using errcode = 'check_violation';
    end if;
    if v_po.status not in ('issued', 'acknowledged') then
      raise exception 'po_not_committed: purchase order % is % -- only issued/acknowledged purchase orders are valid match evidence', p_purchase_order_id, v_po.status
        using errcode = 'check_violation';
    end if;
    if v_po.currency <> v_bill.currency then
      raise exception 'po_currency_mismatch: purchase order % is % but bill % is %', p_purchase_order_id, v_po.currency, p_bill_id, v_bill.currency
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_contract from app.resolve_effective_vendor_contract(p_tenant_id, v_bill.vendor_master_id, v_bill.bill_date::timestamptz, p_actor_auth_user_id);

  v_match_mode := case when v_po.id is not null then 'po_three_way' when v_contract.id is not null then 'contract_two_way' else 'non_po' end;

  select * into v_policy from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id and status = 'active';

  v_fingerprint := app.compute_vendor_bill_match_fingerprint(p_tenant_id, v_bill.vendor_master_id, v_bill.currency, v_bill.total_amount);

  -- C-04 (Tier C batch-4 fix, CRITICAL, live-reproduced as a genuine two-process race:
  -- two concurrently created bills with the same fingerprint each committed unflagged):
  -- serialize the whole "insert this case, then check for a sibling with the same
  -- fingerprint" sequence per (tenant, fingerprint) with a transaction-scoped advisory
  -- lock, acquired BEFORE the insert below. A racing caller for the SAME fingerprint
  -- blocks here until the first caller's transaction commits (or rolls back); its own
  -- duplicate check further down then correctly sees the first caller's already-
  -- committed row under READ COMMITTED, instead of racing past it unflagged. Different
  -- fingerprints hash to (almost certainly) different lock keys and never contend.
  perform pg_advisory_xact_lock(hashtext(p_tenant_id::text || ':' || v_fingerprint));

  -- Fulfillment evidence signal (ePOD / delivery milestone), best-effort: resolved via
  -- the first cost component's own assignment -> shipment_order chain when present.
  -- Never blocks evaluation on its own -- purely descriptive, per the migration header.
  select ra.shipment_order_id into v_shipment_id
  from app.shipment_actual_cost_components sacc
  join app.resource_assignments ra on ra.id = sacc.assignment_id
  where sacc.actual_cost_id = v_bill.actual_cost_id
  limit 1;
  if v_shipment_id is not null then
    v_has_epod := exists (select 1 from app.epod_captures e where e.shipment_order_id = v_shipment_id and e.status = 'completed');
    v_has_delivery_ms := exists (
      select 1 from app.milestone_events ev join app.milestone_codes mc on mc.code = ev.milestone_code
      where ev.shipment_order_id = v_shipment_id and mc.category = 'delivery'
    );
  end if;

  -- C-02: the race-recovery handler below must scope ONLY this insert, never the
  -- mismatch-conflict raise above (a live-reproduced Tier B finding this checkpoint's
  -- own db-test iteration caught: the outer function-wide `exception when unique_
  -- violation` would otherwise silently swallow that deliberate raise too, since both
  -- share the same errcode -- exactly the class taxonomy C-02 names).
  begin
    insert into app.vendor_bill_match_cases (
      tenant_id, bill_id, vendor_master_id, currency, match_mode, is_partial_invoice, is_consolidated_invoice,
      purchase_order_id, vendor_contract_id, tolerance_policy_id, tolerance_policy_version_no,
      quantity_tolerance_pct_snapshot, rate_tolerance_pct_snapshot, tax_tolerance_pct_snapshot, line_amount_tolerance_abs_snapshot, auto_clear_enabled_snapshot,
      has_epod_evidence, has_delivery_milestone_evidence, duplicate_fingerprint, evaluated_by, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_bill_id, v_bill.vendor_master_id, v_bill.currency, v_match_mode, coalesce(p_is_partial_invoice, false), coalesce(p_is_consolidated_invoice, false),
      p_purchase_order_id, v_contract.id, v_policy.id, v_policy.version_no,
      coalesce(v_policy.quantity_tolerance_pct, 0), coalesce(v_policy.rate_tolerance_pct, 0), coalesce(v_policy.tax_tolerance_pct, 0), coalesce(v_policy.line_amount_tolerance_abs, 0), coalesce(v_policy.auto_clear_enabled, false),
      v_has_epod, v_has_delivery_ms, v_fingerprint, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_bill_match_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  -- Duplicate check: another CURRENT case (different bill) with the same fingerprint,
  -- whose own bill_date falls within this policy's own duplicate_window_days. Now
  -- serialized against any concurrent racer for the same fingerprint by the advisory
  -- lock taken above.
  select mc.* into v_dup_case
  from app.vendor_bill_match_cases mc
  join app.finance_vendor_bills b on b.id = mc.bill_id
  where mc.tenant_id = p_tenant_id and mc.is_current and mc.id <> v_case.id and mc.duplicate_fingerprint = v_fingerprint
    and abs(b.bill_date - v_bill.bill_date) <= coalesce(v_policy.duplicate_window_days, 30)
  order by mc.created_at asc
  limit 1;
  if found then
    update app.vendor_bill_match_cases set is_duplicate_flagged = true, duplicate_of_case_id = v_dup_case.id where id = v_case.id;
  end if;

  for v_bill_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id order by line_number asc loop
    select value into v_line_input from jsonb_array_elements(p_line_inputs) as value
      where (value ->> 'billLineId')::uuid = v_bill_line.id
      limit 1;
    if v_line_input is null then
      raise exception 'vendor_stated_amount_required: bill line % has no vendor-stated amount supplied in p_line_inputs', v_bill_line.id using errcode = 'check_violation';
    end if;
    if v_line_input ->> 'vendorStatedAmount' is null then
      raise exception 'vendor_stated_amount_required: bill line % supplied a null vendorStatedAmount', v_bill_line.id using errcode = 'check_violation';
    end if;

    v_component := null;
    if v_bill_line.source_component_id is not null then
      select * into v_component from app.shipment_actual_cost_components where id = v_bill_line.source_component_id;
    end if;

    insert into app.vendor_bill_match_lines (
      tenant_id, match_case_id, bill_line_id, line_no, line_type,
      vendor_stated_quantity, vendor_stated_uom, vendor_stated_rate, vendor_stated_amount,
      actual_cost_component_id, evidence_quantity, evidence_uom, evidence_rate, evidence_amount, evidence_currency
    )
    values (
      p_tenant_id, v_case.id, v_bill_line.id, v_bill_line.line_number, v_bill_line.line_type,
      (v_line_input ->> 'vendorStatedQuantity')::numeric, v_line_input ->> 'vendorStatedUom', (v_line_input ->> 'vendorStatedRate')::numeric, (v_line_input ->> 'vendorStatedAmount')::numeric,
      v_component.id,
      case when v_component.id is not null then v_component.quantity else null end,
      case when v_component.id is not null then v_component.uom else null end,
      case when v_component.id is not null then v_component.rate else null end,
      case when v_bill_line.line_type = 'tax' then v_bill_line.amount when v_component.id is not null then v_component.amount else null end,
      case when v_component.id is not null then v_component.currency when v_bill_line.line_type = 'tax' then v_bill.currency else null end
    )
    returning * into v_line;

    v_line := app._score_vendor_bill_match_line(v_line, v_case);
    update app.vendor_bill_match_lines set
      quantity_variance_pct = v_line.quantity_variance_pct, rate_variance_pct = v_line.rate_variance_pct,
      amount_variance_amount = v_line.amount_variance_amount, amount_variance_pct = v_line.amount_variance_pct,
      uom_mismatch = v_line.uom_mismatch, currency_mismatch = v_line.currency_mismatch, line_status = v_line.line_status
    where id = v_line.id;
  end loop;

  v_case := app._reroll_vendor_bill_match_case(v_case.id);

  perform app._record_vendor_bill_match_event(p_tenant_id, v_case.id, 'case_created', jsonb_build_object('billId', p_bill_id, 'matchMode', v_match_mode, 'overallStatus', v_case.overall_status), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_bill_match_case', 'app.vendor_bill_match_cases', v_case.id, 'success', null, null, jsonb_build_object('billId', p_bill_id, 'overallStatus', v_case.overall_status));

  return v_case;
end;
$$;

comment on function app.create_vendor_bill_match_case is
  'PRC-265: PRC:Edit. Creates version 1 of a match case for a bill, auto-linking actual-cost evidence and, when supplied, validating a PO (tenant/vendor/status/currency) as additional evidence. Requires a non-null vendorStatedAmount for every bill line in p_line_inputs -- this is the real, independent line-level capture of what the vendor''s own invoice states (see migration header). Idempotent by (tenant_id, idempotency_key), full-tuple compared (C-01); the race-recovery handler is a SEPARATE catch clause from the pre-check''s own raise (C-02 safe). Tier C batch-4 fix: the duplicate-fingerprint check is now serialized with a pg_advisory_xact_lock keyed on (tenant_id, fingerprint) -- two concurrent near-duplicate submissions can no longer both slip through unflagged.';

-- ===========================================================================
-- 2. C-04 (concurrency lens, CRITICAL, live-reproduced) + NEW (integration lens,
--    MEDIUM, live-reproduced): app.re_evaluate_vendor_bill_match_case carried the SAME
--    unlocked duplicate-fingerprint race as app.create_vendor_bill_match_case above
--    (same fix: an advisory lock on (tenant_id, fingerprint) before the insert), AND
--    separately never re-queried app.epod_captures/app.milestone_events for
--    has_epod_evidence/has_delivery_milestone_evidence -- it copied v_prior's own
--    values forward verbatim, so a case re-evaluated after new delivery evidence
--    actually arrived kept showing stale "no ePOD"/"no delivery milestone" badges
--    indefinitely, contradicting this function's own C-15 comment ("re-verify the
--    bill's own current state at the actual point of commitment, never trust the
--    version 1 snapshot"). Fixed by re-running the identical epod/milestone lookup
--    app.create_vendor_bill_match_case already performs, against the freshly re-
--    fetched v_bill. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.re_evaluate_vendor_bill_match_case(
  p_match_case_id uuid,
  p_expected_version integer,
  p_purchase_order_id uuid,
  p_line_inputs jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bill_match_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prior app.vendor_bill_match_cases;
  v_bill app.finance_vendor_bills;
  v_po app.purchase_orders;
  v_contract app.vendor_contracts;
  v_policy app.vendor_bill_match_tolerance_policies;
  v_case app.vendor_bill_match_cases;
  v_bill_line app.finance_vendor_bill_lines;
  v_line_input jsonb;
  v_line app.vendor_bill_match_lines;
  v_component app.shipment_actual_cost_components;
  v_fingerprint text;
  v_dup_case_id uuid;
  v_match_mode text;
  v_has_epod boolean := false;
  v_has_delivery_ms boolean := false;
  v_shipment_id uuid;
begin
  -- C-04: lock the CURRENT version row before deciding anything from it.
  select * into v_prior from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_prior.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_prior.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_prior.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_prior.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_prior.is_current then
    raise exception 'invalid_transition: match case % is not the current version', p_match_case_id using errcode = 'check_violation';
  end if;
  if v_prior.overall_status in ('cancelled', 'disputed') then
    raise exception 'invalid_transition: match case % is % and cannot be re-evaluated -- resolve the open dispute or start a new case', p_match_case_id, v_prior.overall_status
      using errcode = 'check_violation';
  end if;

  -- C-15: re-verify the bill's own current state at the actual point of commitment,
  -- never trust the version 1 snapshot.
  select * into v_bill from app.finance_vendor_bills where id = v_prior.bill_id;
  if not found or v_bill.status = 'void' then
    raise exception 'finance_vendor_bill_void: bill % is void and cannot be re-evaluated', v_prior.bill_id using errcode = 'check_violation';
  end if;

  if p_line_inputs is null or jsonb_typeof(p_line_inputs) <> 'array' then
    raise exception 'line_inputs_required: p_line_inputs must be a jsonb array' using errcode = 'check_violation';
  end if;

  if p_purchase_order_id is not null then
    select * into v_po from app.purchase_orders where id = p_purchase_order_id and tenant_id = v_prior.tenant_id;
    if not found then
      raise exception 'purchase_order_not_found: % is not a known purchase order for tenant %', p_purchase_order_id, v_prior.tenant_id using errcode = 'no_data_found';
    end if;
    if v_po.vendor_master_id <> v_bill.vendor_master_id then
      raise exception 'po_vendor_mismatch: purchase order % belongs to a different vendor than bill %', p_purchase_order_id, v_prior.bill_id using errcode = 'check_violation';
    end if;
    if v_po.status not in ('issued', 'acknowledged') then
      raise exception 'po_not_committed: purchase order % is % -- only issued/acknowledged purchase orders are valid match evidence', p_purchase_order_id, v_po.status
        using errcode = 'check_violation';
    end if;
    if v_po.currency <> v_bill.currency then
      raise exception 'po_currency_mismatch: purchase order % is % but bill % is %', p_purchase_order_id, v_po.currency, v_prior.bill_id, v_bill.currency
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_contract from app.resolve_effective_vendor_contract(v_prior.tenant_id, v_bill.vendor_master_id, v_bill.bill_date::timestamptz, p_actor_auth_user_id);
  v_match_mode := case when v_po.id is not null then 'po_three_way' when v_contract.id is not null then 'contract_two_way' else 'non_po' end;
  select * into v_policy from app.vendor_bill_match_tolerance_policies where tenant_id = v_prior.tenant_id and status = 'active';
  v_fingerprint := app.compute_vendor_bill_match_fingerprint(v_prior.tenant_id, v_bill.vendor_master_id, v_bill.currency, v_bill.total_amount);

  -- C-04 (Tier C batch-4 fix, CRITICAL, live-reproduced): the identical duplicate-
  -- fingerprint race app.create_vendor_bill_match_case had, serialized the same way.
  perform pg_advisory_xact_lock(hashtext(v_prior.tenant_id::text || ':' || v_fingerprint));

  -- NEW (Tier C batch-4 fix, MEDIUM, live-reproduced): re-resolve fulfillment evidence
  -- fresh, exactly like app.create_vendor_bill_match_case does -- NEVER copy v_prior's
  -- own has_epod_evidence/has_delivery_milestone_evidence forward. A case re-evaluated
  -- after new delivery evidence actually arrived must reflect it, not keep showing a
  -- stale "no ePOD"/"no delivery milestone" badge indefinitely.
  select ra.shipment_order_id into v_shipment_id
  from app.shipment_actual_cost_components sacc
  join app.resource_assignments ra on ra.id = sacc.assignment_id
  where sacc.actual_cost_id = v_bill.actual_cost_id
  limit 1;
  if v_shipment_id is not null then
    v_has_epod := exists (select 1 from app.epod_captures e where e.shipment_order_id = v_shipment_id and e.status = 'completed');
    v_has_delivery_ms := exists (
      select 1 from app.milestone_events ev join app.milestone_codes mc on mc.code = ev.milestone_code
      where ev.shipment_order_id = v_shipment_id and mc.category = 'delivery'
    );
  end if;

  update app.vendor_bill_match_cases set is_current = false where id = v_prior.id;

  insert into app.vendor_bill_match_cases (
    tenant_id, bill_id, version_no, vendor_master_id, currency, match_mode, is_partial_invoice, is_consolidated_invoice,
    purchase_order_id, vendor_contract_id, tolerance_policy_id, tolerance_policy_version_no,
    quantity_tolerance_pct_snapshot, rate_tolerance_pct_snapshot, tax_tolerance_pct_snapshot, line_amount_tolerance_abs_snapshot, auto_clear_enabled_snapshot,
    has_epod_evidence, has_delivery_milestone_evidence, duplicate_fingerprint, evaluated_by, idempotency_key, created_by
  )
  values (
    v_prior.tenant_id, v_prior.bill_id, v_prior.version_no + 1, v_bill.vendor_master_id, v_bill.currency, v_match_mode, v_prior.is_partial_invoice, v_prior.is_consolidated_invoice,
    p_purchase_order_id, v_contract.id, v_policy.id, v_policy.version_no,
    coalesce(v_policy.quantity_tolerance_pct, 0), coalesce(v_policy.rate_tolerance_pct, 0), coalesce(v_policy.tax_tolerance_pct, 0), coalesce(v_policy.line_amount_tolerance_abs, 0), coalesce(v_policy.auto_clear_enabled, false),
    v_has_epod, v_has_delivery_ms, v_fingerprint, p_actor_label, v_prior.tenant_id::text || ':' || p_match_case_id::text || ':v' || (v_prior.version_no + 1)::text, p_actor_label
  )
  returning * into v_case;

  select mc.id into v_dup_case_id
  from app.vendor_bill_match_cases mc
  join app.finance_vendor_bills b on b.id = mc.bill_id
  where mc.tenant_id = v_prior.tenant_id and mc.is_current and mc.id <> v_case.id and mc.duplicate_fingerprint = v_fingerprint
    and abs(b.bill_date - v_bill.bill_date) <= coalesce(v_policy.duplicate_window_days, 30)
  order by mc.created_at asc
  limit 1;
  if found then
    update app.vendor_bill_match_cases set is_duplicate_flagged = true, duplicate_of_case_id = v_dup_case_id where id = v_case.id;
  end if;

  for v_bill_line in select * from app.finance_vendor_bill_lines where bill_id = v_prior.bill_id order by line_number asc loop
    select value into v_line_input from jsonb_array_elements(p_line_inputs) as value
      where (value ->> 'billLineId')::uuid = v_bill_line.id
      limit 1;
    if v_line_input is null or v_line_input ->> 'vendorStatedAmount' is null then
      raise exception 'vendor_stated_amount_required: bill line % has no vendor-stated amount supplied in p_line_inputs', v_bill_line.id using errcode = 'check_violation';
    end if;

    v_component := null;
    if v_bill_line.source_component_id is not null then
      select * into v_component from app.shipment_actual_cost_components where id = v_bill_line.source_component_id;
    end if;

    insert into app.vendor_bill_match_lines (
      tenant_id, match_case_id, bill_line_id, line_no, line_type,
      vendor_stated_quantity, vendor_stated_uom, vendor_stated_rate, vendor_stated_amount,
      actual_cost_component_id, evidence_quantity, evidence_uom, evidence_rate, evidence_amount, evidence_currency
    )
    values (
      v_prior.tenant_id, v_case.id, v_bill_line.id, v_bill_line.line_number, v_bill_line.line_type,
      (v_line_input ->> 'vendorStatedQuantity')::numeric, v_line_input ->> 'vendorStatedUom', (v_line_input ->> 'vendorStatedRate')::numeric, (v_line_input ->> 'vendorStatedAmount')::numeric,
      v_component.id,
      case when v_component.id is not null then v_component.quantity else null end,
      case when v_component.id is not null then v_component.uom else null end,
      case when v_component.id is not null then v_component.rate else null end,
      case when v_bill_line.line_type = 'tax' then v_bill_line.amount when v_component.id is not null then v_component.amount else null end,
      case when v_component.id is not null then v_component.currency when v_bill_line.line_type = 'tax' then v_bill.currency else null end
    )
    returning * into v_line;

    v_line := app._score_vendor_bill_match_line(v_line, v_case);
    update app.vendor_bill_match_lines set
      quantity_variance_pct = v_line.quantity_variance_pct, rate_variance_pct = v_line.rate_variance_pct,
      amount_variance_amount = v_line.amount_variance_amount, amount_variance_pct = v_line.amount_variance_pct,
      uom_mismatch = v_line.uom_mismatch, currency_mismatch = v_line.currency_mismatch, line_status = v_line.line_status
    where id = v_line.id;
  end loop;

  v_case := app._reroll_vendor_bill_match_case(v_case.id);

  perform app._record_vendor_bill_match_event(v_prior.tenant_id, v_case.id, 'case_re_evaluated', jsonb_build_object('versionNo', v_case.version_no, 'overallStatus', v_case.overall_status), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_prior.tenant_id, p_actor_auth_user_id, p_actor_label, 're_evaluate_vendor_bill_match_case', 'app.vendor_bill_match_cases', v_case.id, 'success', null, null, jsonb_build_object('versionNo', v_case.version_no, 'overallStatus', v_case.overall_status));

  return v_case;
end;
$$;

comment on function app.re_evaluate_vendor_bill_match_case is
  'PRC-265: PRC:Edit. Creates version N+1 of the SAME logical case (bill_id unchanged), never mutating version N''s own rows -- full source/version lineage retained (business rule). Deliberately carries NO idempotency_key parameter, mirroring app.amend_vendor_contract/app.renew_vendor_contract (PRC-261) exactly: p_expected_version is the replay guard for a version-creating call in this repository''s own established convention. Blocked while overall_status is disputed (resolve the dispute first) or cancelled. Tier C batch-4 fix: the duplicate-fingerprint check is now serialized (same advisory-lock fix as app.create_vendor_bill_match_case), and has_epod_evidence/has_delivery_milestone_evidence are now genuinely re-queried against app.epod_captures/app.milestone_events on every re-evaluation instead of copying the prior version''s own stale flags forward.';

-- ===========================================================================
-- 3. C-08 (security lens, HIGH, live-reproduced): app.get_vendor_bill_match_readiness
--    returned mc.total_variance_pct straight from the row with zero cost masking,
--    gated only on PRC:View OR FIN:View (mere existence permission), while every other
--    read RPC in this migration correctly nulls the same field for a caller lacking
--    PRC:View cost (app.mask_vendor_bill_match_case_cost_fields) and the base table's
--    own column-restricted grant excludes it entirely. Because this RPC is SECURITY
--    DEFINER, it bypassed both defenses -- a caller holding ONLY FIN:View (zero PRC
--    permission of any kind) could read the real value through this one RPC. Fixed by
--    masking total_variance_pct behind the same app.has_prc_view_cost gate every
--    sibling RPC already uses (see app.get_vendor_bill_match_reconciliation_status just
--    below it in the same file, which already did this correctly). Same signature,
--    CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.get_vendor_bill_match_readiness(p_bill_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  bill_id uuid, match_case_id uuid, overall_status text, readiness_status text, readiness_note text,
  is_duplicate_flagged boolean, total_variance_pct numeric, evaluated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_prc app.rbac_decision;
  v_fin app.rbac_decision;
  v_can_view_cost boolean;
begin
  -- Genuine, disclosed two-module OR-gate (migration header): either a Procurement
  -- viewer (who owns match evidence) or a Finance viewer (the readiness handoff's own
  -- intended reader) may read this. Neither module's own boundary is widened -- both
  -- checks are the SAME evaluate_permission this repository already uses everywhere
  -- else, just composed with OR instead of gating on one alone.
  v_prc := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  v_fin := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View');
  if not (v_prc.allowed or v_fin.allowed) then
    raise exception 'insufficient_authority: identity % lacks both PRC:View and FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-08 (Tier C batch-4 fix, HIGH, live-reproduced): total_variance_pct is cost-
  -- shaped, same as every other field app.mask_vendor_bill_match_case_cost_fields
  -- nulls elsewhere -- gate it on the SAME app.has_prc_view_cost check, never on the
  -- mere PRC:View-OR-FIN:View existence gate above (a FIN:View-only caller has zero
  -- PRC permission of any kind and must never see this).
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select mc.bill_id, mc.id, mc.overall_status, mc.readiness_status, mc.readiness_note, mc.is_duplicate_flagged,
    case when v_can_view_cost then mc.total_variance_pct else null end,
    mc.evaluated_at
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.bill_id = p_bill_id and mc.is_current;
end;
$$;

comment on function app.get_vendor_bill_match_readiness is
  'PRC-265: the real, callable, read-only "clean readiness handoff back to Finance" -- gated on PRC:View OR FIN:View. Never hooks, gates, or wraps app.approve_finance_vendor_bill/app.post_finance_vendor_bill (FIN-200) -- Finance''s own approver still decides when to post, exactly as FIN-200''s own already-disclosed non-blocking variance_status precedent. Returns zero rows (never raises) when no match case exists yet for the bill. Tier C batch-4 fix (C-08, HIGH): total_variance_pct is now masked behind app.has_prc_view_cost, matching every other cost-shaped field this capability already masks -- a FIN:View-only caller (zero PRC permission) no longer sees the real value through this one RPC.';

-- ===========================================================================
-- 4. C-11 (security lens, MEDIUM, live-reproduced): app.vendor_kpi_metric_values
--    carried a blanket, column-unrestricted `grant select ... to authenticated`, so any
--    tenant member -- including one holding literally zero permissions -- could read
--    source_evidence (and therefore contributing_source_ids) directly via a raw table
--    select, entirely bypassing both the PRC:View gate app.get_vendor_kpi_scorecard_
--    drilldown enforces and the PRC:View-cost mask app.mask_vendor_kpi_source_evidence
--    applies at that RPC. The very next migration in this same batch (20260730750000,
--    PRC-265) explicitly establishes column-restricted authenticated grants as this
--    repository's own defense-in-depth convention for exactly this class -- applied
--    here now for consistency. source_evidence is excluded entirely from authenticated
--    (every other, non-sensitive column stays visible); service_role (the RPCs' own
--    SECURITY DEFINER identity) keeps full-column select, already granted separately
--    and untouched by this fix. Not a function -- a targeted REVOKE + column-restricted
--    re-GRANT, no signature/ACL concerns.
-- ===========================================================================

revoke select on app.vendor_kpi_metric_values from authenticated;
grant select (
  id, tenant_id, vendor_master_id, kpi_definition_id, kpi_code, window_start, window_end,
  version_no, is_current, run_id, raw_numerator, raw_denominator, sample_size, computed_value,
  normalized_score, is_computable, computation_note, excluded_count, supersedes_metric_value_id,
  calculated_at, created_by, created_at
) on app.vendor_kpi_metric_values to authenticated;

-- ===========================================================================
-- 5. C-04 (concurrency lens, HIGH, live-reproduced): app.decide_vendor_kpi_manual_
--    adjustment locked and mutated the target scorecard's line + composite_score/band
--    without ever re-checking that scorecard was still the CURRENT/published one for
--    its (vendor, window). An ordinary recalculation cycle in between (app.calculate_
--    vendor_kpi_metrics + app.publish_vendor_kpi_scorecard running again for the same
--    window) supersedes the old scorecard -- the pending adjustment still points at it.
--    A later approval then silently rewrote the now-dead, superseded row while the
--    vendor's ACTUAL current scorecard (the one every other reader, including the
--    lifecycle-recommendation suspend/blacklist logic, actually reads) stayed
--    untouched, with zero error surfaced to the approver. This is the exact re-
--    validation-at-commitment-time gap app.decide_vendor_bill_match_exception_approval
--    (built in the same batch) already guards against for its own parent row. Fixed by
--    adding the identical guard here, immediately after the scorecard is locked. Same
--    signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.decide_vendor_kpi_manual_adjustment(p_adjustment_id uuid, p_expected_version integer, p_decision text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_adjustment app.vendor_kpi_manual_adjustments;
  v_scorecard app.vendor_kpi_scorecards;
  v_line app.vendor_kpi_scorecard_lines;
  v_new_composite numeric;
  v_weighted_sum numeric := 0;
  v_computable_weight numeric := 0;
  v_row record;
begin
  select * into v_adjustment from app.vendor_kpi_manual_adjustments where id = p_adjustment_id for update;
  if not found then
    raise exception 'vendor_kpi_manual_adjustment_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_adjustment.tenant_id, 'PRC', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_adjustment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_adjustment.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested manual adjustment % and may not also decide it', p_actor_auth_user_id, p_adjustment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_adjustment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI manual adjustment % expected version % but found %', p_adjustment_id, p_expected_version, v_adjustment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_adjustment.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor KPI manual adjustment % is % and cannot be decided', p_adjustment_id, v_adjustment.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_manual_adjustments
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = now(), decision_notes = p_decision_notes
  where id = p_adjustment_id and record_version = p_expected_version
  returning * into v_adjustment;
  if not found then
    raise exception 'stale_version: vendor KPI manual adjustment % target row was concurrently modified (expected version %)', p_adjustment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approved' then
    select * into v_scorecard from app.vendor_kpi_scorecards where id = v_adjustment.scorecard_id for update;

    -- C-04 (Tier C batch-4 fix, HIGH, live-reproduced): re-verify the scorecard is
    -- STILL the current, published one at the actual point of commitment -- never
    -- trust that it still is just because it was published when the adjustment was
    -- first requested. An ordinary recalculation cycle in between (app.calculate_
    -- vendor_kpi_metrics + app.publish_vendor_kpi_scorecard superseding it) must fail
    -- this loudly rather than silently rewrite a dead, superseded scorecard while the
    -- vendor's real current scorecard stays untouched. Mirrors app.decide_vendor_bill_
    -- match_exception_approval's own identical C-15 re-verification in the companion
    -- PRC-265 migration.
    if not v_scorecard.is_current or v_scorecard.status <> 'published' then
      raise exception 'stale_scorecard: vendor KPI scorecard % is no longer the current published scorecard for this vendor/window -- it was superseded by a later recalculation while this adjustment was pending. Request a fresh manual adjustment against the current scorecard instead', v_scorecard.id
        using errcode = 'check_violation';
    end if;

    update app.vendor_kpi_scorecard_lines
    set normalized_score = v_adjustment.adjusted_normalized_score,
      band = app._band_for_score(v_adjustment.adjusted_normalized_score, band_thresholds_snapshot),
      is_computable = true, adjusted = true
    where id = v_adjustment.scorecard_line_id
    returning * into v_line;

    for v_row in select weight_snapshot, normalized_score, is_computable from app.vendor_kpi_scorecard_lines where scorecard_id = v_scorecard.id loop
      if v_row.is_computable then
        v_computable_weight := v_computable_weight + v_row.weight_snapshot;
        v_weighted_sum := v_weighted_sum + (v_row.weight_snapshot * v_row.normalized_score);
      end if;
    end loop;
    v_new_composite := round(v_weighted_sum / nullif(v_computable_weight, 0), 2);

    update app.vendor_kpi_scorecards
    set composite_score = v_new_composite, band = app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb), computable_weight_total = v_computable_weight
    where id = v_scorecard.id and record_version = v_scorecard.record_version;
    if not found then
      raise exception 'stale_version: vendor KPI scorecard % was concurrently modified while applying an adjustment', v_scorecard.id using errcode = 'serialization_failure';
    end if;

    perform app.capture_audit_event(
      v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_vendor_kpi_manual_adjustment',
      'app.vendor_kpi_scorecards', v_scorecard.id, 'success', p_decision_notes,
      jsonb_build_object('composite_score', v_scorecard.composite_score, 'band', v_scorecard.band),
      jsonb_build_object('composite_score', v_new_composite, 'band', app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb))
    );
  end if;

  perform app.capture_audit_event(
    v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_kpi_manual_adjustment',
    'app.vendor_kpi_manual_adjustments', v_adjustment.id, 'success', p_decision_notes, null, jsonb_build_object('status', v_adjustment.status)
  );

  return v_adjustment;
end;
$$;

comment on function app.decide_vendor_kpi_manual_adjustment is
  'PRC-264: PRC:Approve (checker), self-approval blocked (requested_by <> decided_by). On approval, mutates the CURRENT published scorecard''s line + composite_score/band in place under a record_version guard (design note 8), never mints a redundant new scorecard version -- app.vendor_kpi_manual_adjustments itself is the permanent before/after evidence (original_normalized_score vs adjusted_normalized_score, plus this function''s own capture_audit_event before/after on the scorecard). Tier C batch-4 fix (C-04, HIGH): re-verifies the target scorecard is still is_current/published at the actual point of approval, raising stale_scorecard instead of silently rewriting a superseded scorecard nobody reads anymore.';

-- ===========================================================================
-- 6. NEW (integration lens, HIGH, live-reproduced): app._calc_vendor_kpi_invoice_
--    accuracy's numerator counted every case with overall_status = 'matched',
--    regardless of whether it reached that status cleanly or via an APPROVED exception
--    approval -- directly contradicting this migration's own written design ("a case
--    that needed exception approval, even if eventually approved, genuinely WAS
--    inaccurate at submission time, which is exactly what this KPI measures"), because
--    app.decide_vendor_bill_match_exception_approval sets the SAME overall_status =
--    'matched' on an approved exception as a clean, never-disputed match, and nothing
--    distinguished the two. Fixed by anti-joining app.vendor_bill_match_exception_
--    approvals for any approved row against the case -- a case that ever needed and
--    got an approved exception no longer counts as a clean match. Same signature (4
--    args, unchanged from 20260730760000's own DROP+CREATE), CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app._calc_vendor_kpi_invoice_accuracy(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    count(*) filter (
      where mc.overall_status = 'matched'
        and not exists (
          select 1 from app.vendor_bill_match_exception_approvals ea
          where ea.match_case_id = mc.id and ea.status = 'approved'
        )
    ),
    count(*),
    array_agg(mc.id)
  into v_num, v_den, v_ids
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.vendor_master_id = p_vendor_master_id and mc.is_current
    and mc.overall_status in ('matched', 'exception', 'blocked', 'disputed')
    and mc.evaluated_at >= p_window_start and mc.evaluated_at < p_window_end
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'invoice_accuracy' and d.source_id = mc.id and d.status = 'upheld');

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_evaluated_bills: no vendor bill match case for this vendor reached a decided outcome in the window' else null end;
  r.source_evidence := jsonb_build_object('evaluated', coalesce(v_den, 0), 'matched_clean', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_invoice_accuracy is
  'PRC-265 wiring (was PRC-264''s permanent is_computable=false stub, 0-argument form -- see 20260730760000''s own header for the DROP+CREATE reasoning). Denominator: current match cases (app.vendor_bill_match_cases, PRC-265) for this vendor that reached a real decided outcome (matched/exception/blocked/disputed, never still-pending) with evaluated_at in the window. Numerator: cases that reached matched WITHOUT ever needing an approved exception -- a case that needed exception approval, even if eventually approved, genuinely was inaccurate at submission and does not count (Tier C batch-4 fix, HIGH: the original numerator counted these as clean, contradicting this exact design intent). Excludes any case with an UPHELD app.vendor_kpi_source_disputes row (kpi_code=''invoice_accuracy''), the same generic exclusion mechanism every sibling calculator already uses.';

-- ===========================================================================
-- 7. C-20 (integration lens, MEDIUM, live-reproduced): app.map_vendor_bill_match_line
--    computes and persists real PO-line quantity/UOM cross-check evidence (po_line_
--    quantity_variance_pct, po_line_uom_mismatch), but nothing downstream ever
--    consulted either field -- app._reroll_vendor_bill_match_case's own aggregate
--    exception decision only ever looked at line_status and the PO HEADER total
--    variance, never the PO-line-level cross-check a staffer explicitly requested by
--    mapping a PO line. A staffer who mapped a PO line and got a genuine, real 100x-
--    order-of-magnitude UOM mismatch (kg vs ton, the batch''s own db-test fixture) got
--    zero effect on whether the case cleared. Fixed by folding both fields into the
--    same aggregate exception decision app._reroll_vendor_bill_match_case already
--    makes from the PO header total, using the SAME quantity_tolerance_pct_snapshot
--    tolerance the line-level quantity_variance_pct check already uses. contracted_
--    rate_amount is deliberately left alone -- this migration''s own comment on
--    app.map_vendor_bill_match_line already documents it as a best-effort,
--    deliberately non-blocking informational cross-check ("a tier-resolution failure
--    is caught and leaves the field NULL rather than blocking the mapping"), so
--    wiring it into the exception gate would be a genuine new tolerance-policy design
--    decision, not a bounded fix to an existing, already-decided one. Same signature,
--    CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app._reroll_vendor_bill_match_case(p_case_id uuid)
returns app.vendor_bill_match_cases
language plpgsql
as $$
declare
  v_case app.vendor_bill_match_cases;
  v_po app.purchase_orders;
  v_stated_sum numeric(14, 2);
  v_evidence_sum numeric(14, 2);
  v_any_exception boolean;
  v_any_missing boolean;
  v_any_currency_mismatch boolean;
  v_any_po_line_exception boolean;
  v_po_variance_pct numeric;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  select coalesce(sum(vendor_stated_amount), 0), coalesce(sum(evidence_amount), 0),
    bool_or(line_status = 'variance_exception'), bool_or(line_status = 'missing_evidence'), bool_or(line_status = 'currency_mismatch'),
    -- C-20 (Tier C batch-4 fix, MEDIUM, live-reproduced): the PO-line quantity/UOM
    -- cross-check app.map_vendor_bill_match_line computes was never consumed anywhere
    -- -- fold it into the same aggregate exception decision as every other line-level
    -- signal, using the case's own already-snapshotted quantity tolerance.
    bool_or(po_line_uom_mismatch or (po_line_quantity_variance_pct is not null and po_line_quantity_variance_pct > v_case.quantity_tolerance_pct_snapshot))
  into v_stated_sum, v_evidence_sum, v_any_exception, v_any_missing, v_any_currency_mismatch, v_any_po_line_exception
  from app.vendor_bill_match_lines where match_case_id = p_case_id;

  v_any_exception := v_any_exception or coalesce(v_any_po_line_exception, false);

  if v_case.purchase_order_id is not null then
    select * into v_po from app.purchase_orders where id = v_case.purchase_order_id;
    if found and v_po.total_amount is not null and v_po.total_amount > 0 then
      v_po_variance_pct := app._vendor_bill_match_pct_variance(v_stated_sum, v_po.total_amount);
      if v_po_variance_pct is not null and v_po_variance_pct > v_case.rate_tolerance_pct_snapshot then
        v_any_exception := true;
      end if;
    end if;
  end if;

  update app.vendor_bill_match_cases
  set total_vendor_stated_amount = v_stated_sum,
      total_evidence_amount = v_evidence_sum,
      total_variance_amount = round(abs(v_stated_sum - v_evidence_sum), 2),
      total_variance_pct = app._vendor_bill_match_pct_variance(v_stated_sum, v_evidence_sum),
      overall_status = case
        when v_any_currency_mismatch or v_case.is_duplicate_flagged or v_any_exception or v_any_missing then 'exception'
        when v_case.auto_clear_enabled_snapshot then 'matched'
        else 'pending'
      end,
      readiness_status = case
        when v_any_currency_mismatch or v_case.is_duplicate_flagged or v_any_exception or v_any_missing then 'not_ready'
        when v_case.auto_clear_enabled_snapshot then 'ready_for_finance'
        else 'not_ready'
      end,
      readiness_note = case
        when v_any_currency_mismatch then 'blocked: one or more lines carry a currency mismatch against evidence'
        when v_case.is_duplicate_flagged then 'blocked: probable duplicate invoice, requires exception approval to clear'
        when v_any_missing then 'blocked: one or more lines have no evidence to compare against'
        when coalesce(v_any_po_line_exception, false) then 'blocked: one or more lines carry a PO-line quantity/UOM mismatch exceeding the active tolerance policy'
        when v_any_exception then 'blocked: one or more lines (or the PO header total) exceed the active tolerance policy'
        when v_case.auto_clear_enabled_snapshot then 'auto-cleared within the active tolerance policy'
        else 'within tolerance -- awaiting explicit accept (auto-clear is not enabled by the active policy)'
      end,
      evaluated_at = now()
  where id = p_case_id
  returning * into v_case;

  return v_case;
end;
$$;

comment on function app._reroll_vendor_bill_match_case is
  'PRC-265: internal, no grant. Recomputes case-level rollups/overall_status/readiness_status purely from its own current lines plus the case''s own already-snapshotted tolerance/duplicate/PO fields -- never re-resolves the tolerance policy or duplicate flag itself (those are set once, at create/re_evaluate time). Caller must already be inside a transaction that has reason to call this (create/re_evaluate/map_line); it takes its OWN lock on the case row (C-04), consistent with every other function in this migration''s own "lock the case before deciding" discipline. Tier C batch-4 fix (C-20, MEDIUM): a line''s po_line_uom_mismatch/po_line_quantity_variance_pct (set by app.map_vendor_bill_match_line, previously computed but never consulted) now also drives the exception decision, gated by the same quantity_tolerance_pct_snapshot the line-level quantity check already uses.';
