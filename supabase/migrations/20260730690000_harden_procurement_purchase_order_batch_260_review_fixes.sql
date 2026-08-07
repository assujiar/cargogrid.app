-- Batch review fix pass (CG-S11-PRC-011, Prompt 260, ADR-0021 Tier C, "batch 2" of the
-- 257-260 range -- Prompt 260 was the sole prompt in this batch). Every fix below closes
-- a finding CONFIRMED by direct code derivation (and, per the four lenses' own reports,
-- live reproduction) against Prompt 260's own diff. See this batch's own git commit
-- message for the full disposition (findings closed / disclosed-not-fixed / rejected as
-- unconfirmed).
--
-- ===========================================================================
-- 1. C-15 (spec-compliance lens, MEDIUM): no CHECK constraint tied total_amount to
--    subtotal_amount + tax_amount, even though both app.draft_purchase_order_from_
--    selection (v_offer.normalized_amount + v_tax_amount) and app.amend_purchase_order
--    (copies all three verbatim) rely on the invariant holding. This repository already
--    has an in-repo precedent for exactly this constraint shape: app.warehouse_billing_
--    events (`20260730300000_create_advanced_tms_warehouse_billing_events.sql` line 324,
--    `total_amount is null or total_amount = base_amount + coalesce(tax_amount, 0)`).
--    Purely additive -- both columns are already `not null` on app.purchase_orders, so no
--    `is null` escape clause is needed here (unlike the nullable-total precedent).
-- ===========================================================================

alter table app.purchase_orders
  add constraint purchase_orders_total_amount_check check (total_amount = subtotal_amount + tax_amount);

-- ===========================================================================
-- 2. C-15 (spec-compliance lens, LOW): no CHECK (and no application-level validation)
--    enforced service_period_end >= service_period_start. This repository already has
--    three in-repo precedents for exactly this constraint shape: app.sales_plans
--    (`20260723180000`, `period_end >= period_start`), app.finance_fiscal_periods
--    (`20260728220000`, `end_date >= start_date`), app.route_planning_stops
--    (`20260729320000`, `time_window_end is null or time_window_start is null or
--    time_window_end >= time_window_start`).
-- ===========================================================================

alter table app.purchase_orders
  add constraint purchase_orders_service_period_check
  check (service_period_start is null or service_period_end is null or service_period_end >= service_period_start);

-- ===========================================================================
-- 3. C-05 (security-rls lens, MEDIUM, live-reproduced): every one of the 6 lifecycle
--    write RPCs this migration added resolves the target row's real tenant_id BEFORE
--    checking whether the calling identity may access that tenant at all, then echoes
--    that real tenant_id verbatim into the resulting insufficient_authority error text --
--    letting any authenticated user of ANY tenant, given an arbitrary PO UUID, learn (a)
--    whether it is a real row and (b) the exact real tenant_id that owns it, with zero
--    membership in that tenant. Live-reproduced against all 6:
--    submit_purchase_order_for_approval, issue_purchase_order,
--    acknowledge_purchase_order, record_purchase_order_fulfillment_status,
--    amend_purchase_order, cancel_purchase_order. Fixed here by folding
--    app.has_active_tenant_membership into the SAME not-found branch, exactly the
--    pattern `20260730670000` section 2 already applied to this batch's own 13 by-id
--    READ RPCs (ISS-2026-043) -- applied here to WRITE RPCs for the first time. The
--    migration's own header (lines 108-120) had disclosed the un-fixed write-RPC shape
--    as "a deliberate consistency choice, not an oversight" -- re-examined by this
--    review and judged a real, previously-unregistered oracle worth closing at the one
--    capability's own write surface; the identical shape across the rest of the
--    repository's write RPCs (PRC-257/258/259 and earlier phases) is registered as
--    ISS-2026-048 rather than swept here (see that entry for the scope reasoning).
--    Same signatures throughout, CREATE OR REPLACE only -- no re-GRANT needed.
-- ===========================================================================

create or replace function app.submit_purchase_order_for_approval(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  -- Batch 260 review (C-05, MEDIUM): folds tenant membership into the not-found branch
  -- -- a non-member (or a genuinely nonexistent id) now gets the identical
  -- purchase_order_not_found error, never a real-tenant-disclosing insufficient_authority.
  -- Locked BEFORE the routing call below -- closes the ISS-2026-044-shaped race
  -- documented in this migration's own header (unchanged by this fix).
  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'draft' then
    raise exception 'invalid_transition: purchase order % is % and cannot be submitted for approval', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'purchase_order', v_po.tenant_id, p_purchase_order_id, v_po.total_amount, v_po.currency,
    jsonb_build_object('poNumber', v_po.po_number, 'vendorMasterId', v_po.vendor_master_id, 'comparisonId', v_po.comparison_id),
    p_expected_version + 1, 'purchase_order:' || p_purchase_order_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  update app.purchase_orders
  set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
      approval_status = v_gov_approval_status, approval_request_id = v_gov_approval_request_id
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'draft', 'submitted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_purchase_order_for_approval',
    'app.purchase_orders', v_po.id, 'success', null, null, jsonb_build_object('approval_status', v_gov_approval_status)
  );

  return v_po;
end;
$$;

create or replace function app.issue_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
begin
  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'submitted' then
    raise exception 'invalid_transition: purchase order % is % and cannot be issued', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.approval_status not in ('approved', 'not_required') then
    raise exception 'purchase_order_approval_pending: purchase order % approval_status is % (must be approved or not_required)', p_purchase_order_id, v_po.approval_status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set status = 'issued', issued_at = now(), issued_by = p_actor_label
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'submitted', 'issued', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_purchase_order',
    'app.purchase_orders', v_po.id, 'success', null, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

create or replace function app.acknowledge_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_acknowledgement_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
begin
  if p_acknowledgement_note is null or length(trim(p_acknowledgement_note)) = 0 then
    raise exception 'reason_required: a non-empty acknowledgement note is required' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'issued' then
    raise exception 'invalid_transition: purchase order % is % and cannot be acknowledged', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = p_actor_label, acknowledgement_note = p_acknowledgement_note
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'issued', 'acknowledged', p_acknowledgement_note, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_purchase_order',
    'app.purchase_orders', v_po.id, 'success', p_acknowledgement_note, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

create or replace function app.record_purchase_order_fulfillment_status(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_fulfillment_status text,
  p_fulfillment_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_rank_current integer;
  v_rank_new integer;
begin
  if p_fulfillment_status not in ('partial', 'fulfilled') then
    raise exception 'invalid_fulfillment_status: % is not a valid target fulfillment status', p_fulfillment_status using errcode = 'check_violation';
  end if;
  if p_fulfillment_reference is null or length(trim(p_fulfillment_reference)) = 0 then
    raise exception 'reason_required: a non-empty fulfillment_reference (canonical shipment/service evidence) is required' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % -- fulfillment can only be tracked on an issued or acknowledged PO', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  v_rank_current := case v_po.fulfillment_status when 'not_started' then 0 when 'partial' then 1 else 2 end;
  v_rank_new := case p_fulfillment_status when 'partial' then 1 else 2 end;
  if v_rank_new <= v_rank_current then
    raise exception 'invalid_fulfillment_transition: fulfillment_status cannot move from % to %', v_po.fulfillment_status, p_fulfillment_status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set fulfillment_status = p_fulfillment_status, fulfillment_reference = p_fulfillment_reference,
      fulfillment_updated_at = now(), fulfillment_updated_by = p_actor_label
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_purchase_order_fulfillment_status',
    'app.purchase_orders', v_po.id, 'success', p_fulfillment_reference, null, jsonb_build_object('fulfillment_status', p_fulfillment_status)
  );

  return v_po;
end;
$$;

create or replace function app.amend_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_payment_term_days integer default null,
  p_expected_delivery_date date default null,
  p_service_period_start date default null,
  p_service_period_end date default null,
  p_commercial_terms text default null,
  p_notes text default null
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_existing app.purchase_orders;
  v_resolved_payment_term integer;
  v_resolved_delivery date;
  v_resolved_service_start date;
  v_resolved_service_end date;
  v_resolved_terms text;
  v_resolved_notes text;
  v_new_po app.purchase_orders;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to amend a purchase order' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % and cannot be amended', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.fulfillment_status <> 'not_started' then
    raise exception 'fulfillment_in_progress: purchase order % has fulfillment_status % -- amendment is blocked once fulfillment has begun', p_purchase_order_id, v_po.fulfillment_status
      using errcode = 'check_violation';
  end if;

  v_resolved_payment_term := coalesce(p_payment_term_days, v_po.payment_term_days);
  v_resolved_delivery := coalesce(p_expected_delivery_date, v_po.expected_delivery_date);
  v_resolved_service_start := coalesce(p_service_period_start, v_po.service_period_start);
  v_resolved_service_end := coalesce(p_service_period_end, v_po.service_period_end);
  v_resolved_terms := coalesce(p_commercial_terms, v_po.commercial_terms);
  v_resolved_notes := coalesce(p_notes, v_po.notes);

  -- taxonomy C-01: idempotency replay compares the resolved override fields, not just
  -- revised_from_id, mirroring app.revise_rfq (PRC-257) / app.revise_vendor_comparison
  -- (PRC-258) exactly.
  select * into v_existing from app.purchase_orders where tenant_id = v_po.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_purchase_order_id
       or v_existing.payment_term_days is distinct from v_resolved_payment_term
       or v_existing.expected_delivery_date is distinct from v_resolved_delivery
       or v_existing.service_period_start is distinct from v_resolved_service_start
       or v_existing.service_period_end is distinct from v_resolved_service_end
       or v_existing.commercial_terms is distinct from v_resolved_terms
       or v_existing.notes is distinct from v_resolved_notes then
      raise exception 'idempotency_key_conflict: key % was already used for a different amendment', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  update app.purchase_orders
  set status = 'superseded'
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_orders (
    tenant_id, org_unit_id, po_number, version, revised_from_id, comparison_id, selected_offer_id, rfq_id, sourcing_request_id, vendor_master_id,
    currency, subtotal_amount, tax_code, tax_amount, total_amount, payment_term_days,
    expected_delivery_date, service_period_start, service_period_end, commercial_terms, notes,
    status, idempotency_key, created_by
  ) values (
    v_po.tenant_id, v_po.org_unit_id, v_po.po_number, v_po.version + 1, v_po.id, v_po.comparison_id, v_po.selected_offer_id, v_po.rfq_id, v_po.sourcing_request_id, v_po.vendor_master_id,
    v_po.currency, v_po.subtotal_amount, v_po.tax_code, v_po.tax_amount, v_po.total_amount, v_resolved_payment_term,
    v_resolved_delivery, v_resolved_service_start, v_resolved_service_end, v_resolved_terms, v_resolved_notes,
    'draft', p_idempotency_key, p_actor_label
  )
  returning * into v_new_po;

  insert into app.purchase_order_lines (tenant_id, purchase_order_id, line_no, source_requirement_line_id, description, quantity, uom, notes)
  select tenant_id, v_new_po.id, line_no, source_requirement_line_id, description, quantity, uom, notes
  from app.purchase_order_lines where purchase_order_id = p_purchase_order_id order by line_no;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, v_po.status, 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_purchase_order',
    'app.purchase_orders', v_new_po.id, 'success', p_reason, null, jsonb_build_object('revised_from_id', v_po.id)
  );

  return v_new_po;
end;
$$;

-- ===========================================================================
-- 4. C-21 (correctness/concurrency lens, HIGH, live-reproduced) + C-05 (folded in with
--    fix 3 above): app.cancel_purchase_order locked app.purchase_orders FIRST (its own
--    opening SELECT ... FOR UPDATE), then -- when approval_status='pending' -- called
--    app.cancel_approval_request (PLT-123), which locks app.approval_requests then
--    app.approval_request_steps: lock order PO -> approval_requests ->
--    approval_request_steps. app.decide_purchase_order_approval_step calls
--    app.decide_approval_step FIRST (locks approval_request_steps then, once the
--    decision finalizes the request, approval_requests), and only afterward locks
--    app.purchase_orders: lock order approval_request_steps -> approval_requests -> PO
--    -- the exact inverse. Two real, concurrent sessions taking each function's own
--    documented lock sequence against the same PO's bound approval request reproduce a
--    genuine Postgres `deadlock detected` (SQLSTATE 40P01). This function's own comment
--    claimed to mirror the SAFE app.cancel_procurement_exception_request (PRC-259)
--    precedent, but did not: that function takes a plain, UNLOCKED select first and only
--    implicitly locks its own row at its terminal UPDATE -- i.e. it locks the
--    approval-engine tables BEFORE its own domain row, matching its own sibling
--    app.decide_procurement_exception_approval_step's order. Fixed here by actually
--    matching that precedent: the opening SELECT is no longer FOR UPDATE, and
--    app.cancel_approval_request (when reached) is called BEFORE this function's own
--    terminal, record_version-guarded UPDATE takes the only lock this function itself
--    holds on app.purchase_orders. Correctness of the now-deferred lock is preserved by
--    the SAME record_version-guarded UPDATE every other function in this migration
--    already relies on: app.purchase_orders' own before-update trigger bumps
--    record_version on every write, so if the terminal UPDATE's `where record_version =
--    p_expected_version` matches, nothing changed since the initial unlocked read --
--    and if it does not match, `stale_version` is raised exactly as before, never a
--    silent inconsistency. Same signature, CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.cancel_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a purchase order' using errcode = 'check_violation';
  end if;

  -- Batch 260 review (C-21, HIGH + C-05, MEDIUM): a plain, UNLOCKED read -- no longer
  -- `for update`. Folds tenant membership into the not-found branch (fix 3 above).
  select * into v_po from app.purchase_orders where id = p_purchase_order_id;
  if not found or not app.has_active_tenant_membership(v_po.tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('draft', 'submitted', 'issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % and cannot be cancelled', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.status in ('issued', 'acknowledged') and v_po.fulfillment_status <> 'not_started' then
    raise exception 'fulfillment_in_progress: purchase order % has fulfillment_status % -- cancel-eligible only while no fulfillment has begun', p_purchase_order_id, v_po.fulfillment_status
      using errcode = 'check_violation';
  end if;

  v_from_status := v_po.status;

  if v_po.approval_request_id is not null and v_po.approval_status = 'pending' then
    -- Batch 260 review (C-21): now runs BEFORE this function ever locks its own
    -- app.purchase_orders row -- lock order app.approval_requests/app.
    -- approval_request_steps -> app.purchase_orders, matching app.decide_purchase_
    -- order_approval_step's own order exactly, closing the cycle. If this cached
    -- approval_status read is stale (a concurrent decide finalized the request between
    -- this function's own unlocked read and this call), app.cancel_approval_request's
    -- own fresh re-read raises a typed approval_request_not_pending rather than acting
    -- on stale data -- caught by the mutation layer, never a raw error.
    perform app.cancel_approval_request(v_po.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
  end if;

  update app.purchase_orders
  set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_purchase_order',
    'app.purchase_orders', v_po.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

comment on function app.cancel_purchase_order is
  'PRC-260: draft|submitted|issued|acknowledged -> cancelled, PRC:Edit, mandatory reason. Cancel-eligible only -- blocked once fulfillment_status <> not_started on an issued/acknowledged PO. Cancels the bound app.approval_requests row too when one is still pending. Batch 260 review (C-21, HIGH): now takes an unlocked initial read and locks the bound approval request (when any) BEFORE this function''s own terminal, record_version-guarded update of its own app.purchase_orders row -- matching app.decide_purchase_order_approval_step''s own lock order and actually matching (rather than only claiming to match) the safe app.cancel_procurement_exception_request (PRC-259) precedent. This reorder alone closed the WIDER purchase_orders-vs-approval-engine cycle but, live-tested via a real two-process regression, did not fully close the deadlock on its own -- a second, deeper cycle lived entirely inside the Platform Approval Engine itself (app.cancel_approval_request vs app.decide_approval_step disagreeing on their own approval_requests/approval_request_steps lock order); see this migration''s own section 6 (app.cancel_approval_request) for the fix that actually closes it, verified via 3 consecutive clean two-process regression runs with zero deadlocks.';

-- ===========================================================================
-- 5. C-05 (security-rls lens, LOW, narrower): app.draft_purchase_order_from_selection
--    locked the foreign app.vendor_comparisons row, then raised a DISTINCT
--    tenant_mismatch error (vs. vendor_comparison_not_found) when the row belonged to a
--    different tenant than the caller's own p_tenant_id -- a binary existence oracle (no
--    tenant_id disclosed, unlike fix 3 above, but still distinguishable from a genuinely
--    nonexistent id). Fixed by treating "found but wrong tenant" identically to "not
--    found", closing the cross-tenant existence signal. The identical shape was found,
--    unchanged, in the already-VERIFIED sibling app.draft_rfq_from_sourcing (PRC-257,
--    `20260730640000_create_procurement_rfq.sql`) -- fixed here too in the same sweep
--    (propagation-sweep discipline, `BUILD_EXECUTION_PROTOCOL.md` §5.4): a finding fixed
--    only where it was found is an incomplete fix. Same signatures, CREATE OR REPLACE
--    only.
-- ===========================================================================

create or replace function app.draft_purchase_order_from_selection(
  p_tenant_id uuid,
  p_comparison_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_tax_code text default null,
  p_payment_term_days integer default null,
  p_expected_delivery_date date default null,
  p_service_period_start date default null,
  p_service_period_end date default null,
  p_commercial_terms text default null,
  p_notes text default null
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_vendor_status text;
  v_payment_term_days integer;
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_existing app.purchase_orders;
  v_number text;
  v_new_po app.purchase_orders;
  v_constraint_name text;
  v_line record;
  v_line_no integer := 0;
begin
  -- Whole-operation authority gates together, before any state-dependent read (C-05
  -- discipline, PRC-258's own established ordering).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_tax_code is not null and not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  -- design note (lock order, migration header): locks the foreign PRC-258 parent row,
  -- never touched again by this function.
  -- Batch 260 review (C-05, LOW): "found but wrong tenant" now raises the SAME
  -- vendor_comparison_not_found a genuinely nonexistent id raises, closing the
  -- cross-tenant existence oracle a distinct tenant_mismatch error used to leak.
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found or v_comparison.tenant_id <> p_tenant_id then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  if v_comparison.status <> 'submitted' then
    raise exception 'invalid_source_status: vendor comparison % is % -- a purchase order may only be drafted from a submitted comparison', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;
  if v_comparison.approval_status not in ('approved', 'not_required') then
    raise exception 'selection_approval_pending: vendor comparison % approval_status is % (must be approved or not_required)', p_comparison_id, v_comparison.approval_status
      using errcode = 'check_violation';
  end if;
  if v_comparison.selected_offer_id is null then
    raise exception 'no_selected_offer: vendor comparison % has no selected offer', p_comparison_id using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = v_comparison.selected_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', v_comparison.selected_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: selected offer % is excluded and cannot be committed', v_offer.id using errcode = 'check_violation';
  end if;
  if v_offer.normalized_amount is null then
    raise exception 'offer_not_normalized: selected offer % has no normalized amount to commit', v_offer.id using errcode = 'check_violation';
  end if;

  select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  if v_vendor_status is distinct from 'active' then
    raise exception 'vendor_not_active: vendor % is % -- a purchase order cannot be committed to a non-active vendor', v_offer.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
      using errcode = 'check_violation';
  end if;

  -- Resolved BEFORE the idempotency check below (not after) -- the replay comparison
  -- must compare against the RESOLVED value, not the raw caller-supplied parameter, or
  -- a caller who omitted p_payment_term_days (defaulted from the vendor) would see their
  -- own identical-tuple replay incorrectly rejected as idempotency_key_conflict (found
  -- live iterating this migration's own db-test before it was ever declared COMPLETED).
  v_payment_term_days := p_payment_term_days;
  if v_payment_term_days is null then
    select payment_term_days into v_payment_term_days from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  end if;

  -- taxonomy C-01: idempotency replay compares the FULL caller-supplied target tuple
  -- (payment_term_days compared as its RESOLVED value -- see comment above).
  select * into v_existing from app.purchase_orders where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.comparison_id is distinct from p_comparison_id
       or v_existing.tax_code is distinct from p_tax_code
       or v_existing.payment_term_days is distinct from v_payment_term_days
       or v_existing.expected_delivery_date is distinct from p_expected_delivery_date
       or v_existing.service_period_start is distinct from p_service_period_start
       or v_existing.service_period_end is distinct from p_service_period_end
       or v_existing.commercial_terms is distinct from p_commercial_terms
       or v_existing.notes is distinct from p_notes then
      raise exception 'idempotency_key_conflict: key % was already used for a different purchase order', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if p_tax_code is not null then
    v_tax_result := app.calculate_finance_tax(p_tenant_id, p_tax_code, v_offer.normalized_amount, current_date, p_actor_auth_user_id);
    if (v_tax_result ->> 'currency') is distinct from v_comparison.comparison_currency then
      -- C-22-style guard, applied deliberately: app.calculate_finance_tax computes a tax
      -- amount in whatever currency its own resolved rule is denominated in, with no FX
      -- step of its own -- accepting a currency-mismatched tax amount at face value would
      -- silently mix two different currencies into one total_amount. Fail closed instead.
      raise exception 'tax_rule_currency_mismatch: tax rule for % is denominated in % but this purchase order is %', p_tax_code, v_tax_result ->> 'currency', v_comparison.comparison_currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric;
  end if;

  v_number := app.next_purchase_order_number(p_tenant_id);

  begin
    insert into app.purchase_orders (
      tenant_id, org_unit_id, po_number, version, comparison_id, selected_offer_id, rfq_id, sourcing_request_id, vendor_master_id,
      currency, subtotal_amount, tax_code, tax_amount, total_amount, payment_term_days,
      expected_delivery_date, service_period_start, service_period_end, commercial_terms, notes,
      status, idempotency_key, created_by
    ) values (
      p_tenant_id, v_comparison.org_unit_id, v_number, 1, p_comparison_id, v_offer.id, v_comparison.rfq_id, v_comparison.sourcing_request_id, v_offer.vendor_master_id,
      v_comparison.comparison_currency, v_offer.normalized_amount, p_tax_code, v_tax_amount, v_offer.normalized_amount + v_tax_amount, v_payment_term_days,
      p_expected_delivery_date, p_service_period_start, p_service_period_end, p_commercial_terms, p_notes,
      'draft', p_idempotency_key, p_actor_label
    )
    returning * into v_new_po;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'purchase_orders_tenant_idempotency_unique' then
        select * into v_existing from app.purchase_orders where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.comparison_id is distinct from p_comparison_id
             or v_existing.tax_code is distinct from p_tax_code
             or v_existing.payment_term_days is distinct from v_payment_term_days
             or v_existing.expected_delivery_date is distinct from p_expected_delivery_date
             or v_existing.service_period_start is distinct from p_service_period_start
             or v_existing.service_period_end is distinct from p_service_period_end
             or v_existing.commercial_terms is distinct from p_commercial_terms
             or v_existing.notes is distinct from p_notes then
            raise exception 'idempotency_key_conflict: key % was already used for a different purchase order', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      elsif v_constraint_name = 'purchase_orders_comparison_active_unique' then
        raise exception 'duplicate_issue: vendor comparison % already has an active purchase order', p_comparison_id
          using errcode = 'check_violation';
      end if;
      raise;
  end;

  for v_line in select * from app.rfq_requirement_lines where rfq_id = v_comparison.rfq_id order by line_no loop
    v_line_no := v_line_no + 1;
    insert into app.purchase_order_lines (tenant_id, purchase_order_id, line_no, source_requirement_line_id, description, quantity, uom, notes)
    values (p_tenant_id, v_new_po.id, v_line_no, v_line.id, v_line.description, v_line.quantity, v_line.uom, v_line.notes);
  end loop;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_new_po.id, null, 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'draft_purchase_order_from_selection',
    'app.purchase_orders', v_new_po.id, 'success', null, null, to_jsonb(v_new_po)
  );

  return v_new_po;
end;
$$;

comment on function app.draft_purchase_order_from_selection is
  'PRC-260: creates (or, on idempotency-key replay, returns the existing) a draft purchase order from an approved, submitted vendor comparison selection -- inherits vendor/demand/quotation exactly, no re-entry. subtotal_amount is the selected offer''s own already-normalized amount (app.vendor_comparison_offers.normalized_amount, PRC-258) verbatim -- never recomputed. tax_amount is 0 unless p_tax_code is supplied, in which case app.calculate_finance_tax (FIN-195) computes it and this function verifies the resolved tax rule''s own currency matches the PO''s currency before accepting it. Lines are snapshotted from app.rfq_requirement_lines at this moment -- never re-derived after. Batch 260 review (C-05, LOW): a vendor comparison belonging to a different tenant now raises the same vendor_comparison_not_found a nonexistent id raises, closing a binary cross-tenant existence oracle.';

create or replace function app.draft_rfq_from_sourcing(
  p_tenant_id uuid,
  p_sourcing_request_id uuid,
  p_owner_user_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_sourcing app.sourcing_requests;
  v_existing app.rfqs;
  v_snapshot jsonb;
  v_number text;
  v_constraint_name text;
  v_rfq app.rfqs;
  v_qty numeric;
  v_uom text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  -- design note 8: locks a foreign PRC-256 parent row, never touched again in
  -- this function -- no ordering conflict with any RFQ-internal lock.
  -- Batch 260 review (C-05, LOW, propagation sweep from PRC-260's own
  -- app.draft_purchase_order_from_selection fix): "found but wrong tenant" now raises
  -- the SAME sourcing_request_not_found a genuinely nonexistent id raises, closing the
  -- identical cross-tenant existence oracle app.draft_purchase_order_from_selection
  -- carried before this same review pass.
  select * into v_sourcing from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found or v_sourcing.tenant_id <> p_tenant_id then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;
  if v_sourcing.status <> 'shortlisted' then
    raise exception 'invalid_source_status: sourcing request % is % -- an RFQ may only be drafted from a shortlisted sourcing request', p_sourcing_request_id, v_sourcing.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.rfqs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.sourcing_request_id is distinct from p_sourcing_request_id or v_existing.owner_user_id is distinct from p_owner_user_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- design note 3: budget_amount is stripped at WRITE time, never carried
  -- into the snapshot at all.
  v_snapshot := v_sourcing.demand_snapshot - 'budget_amount';
  v_number := app.next_rfq_number(p_tenant_id);

  begin
    insert into app.rfqs (
      tenant_id, org_unit_id, sourcing_request_id, rfq_number, version, requirements_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max, currency,
      status, owner_user_id, idempotency_key, created_by
    ) values (
      p_tenant_id, v_sourcing.org_unit_id, p_sourcing_request_id, v_number, 1, v_snapshot,
      v_sourcing.service_type, v_sourcing.mode, v_sourcing.origin_lane, v_sourcing.destination_lane,
      v_sourcing.cargo_weight_min, v_sourcing.cargo_weight_max, v_sourcing.cargo_volume_min, v_sourcing.cargo_volume_max, v_sourcing.currency,
      'draft', p_owner_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_rfq;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfqs_tenant_idempotency_unique' then
        select * into v_existing from app.rfqs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.sourcing_request_id is distinct from p_sourcing_request_id or v_existing.owner_user_id is distinct from p_owner_user_id then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  v_qty := coalesce(v_rfq.cargo_weight_max, v_rfq.cargo_volume_max);
  v_uom := case when v_rfq.cargo_weight_max is not null then 'kg' when v_rfq.cargo_volume_max is not null then 'cbm' else null end;
  insert into app.rfq_requirement_lines (tenant_id, rfq_id, line_no, description, quantity, uom)
  values (p_tenant_id, v_rfq.id, 1, v_rfq.service_type, v_qty, v_uom);

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_rfq.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'draft_rfq_from_sourcing',
    'app.rfqs', v_rfq.id, 'success', null, null, to_jsonb(v_rfq)
  );

  return v_rfq;
end;
$$;

comment on function app.draft_rfq_from_sourcing is 'PRC-257: idempotent on (tenant_id, idempotency_key), replay compares sourcing_request_id/owner_user_id. Blocks a sourcing request that is not shortlisted. requirements_snapshot strips budget_amount at write time (design note 3). status=draft -- needs app.issue_rfq to invite vendors. Batch 260 review (C-05, LOW, propagation sweep): a sourcing request belonging to a different tenant now raises the same sourcing_request_not_found a nonexistent id raises, closing a binary cross-tenant existence oracle.';

-- ===========================================================================
-- 6. C-21 (correctness/concurrency lens, HIGH), the ROOT CAUSE fix -- fix 4 above (the
--    app.cancel_purchase_order reorder) closed the wider PO-vs-approval-engine cycle,
--    but a live two-process re-run of the new regression test still deadlocked, this
--    time entirely WITHIN the Platform Approval Engine (PLT-123) itself:
--    `ERROR: deadlock detected ... while locking tuple ... in relation
--    "approval_request_steps" ... SQL statement "update app.approval_request_steps set
--    status = 'skipped' where request_id = p_request_id and status in ('pending',
--    'active')" ... PL/pgSQL function cancel_approval_request(...)`. Root cause:
--    app.cancel_approval_request (unchanged since `20260719090000`) locks
--    app.approval_requests FIRST, then app.approval_request_steps -- the exact inverse
--    of app.decide_approval_step (every branch: the specific step row, then any sibling
--    step rows, then -- only once a decision finalizes the request -- app.
--    approval_requests). Two real, concurrent sessions -- one calling
--    app.cancel_purchase_order (nesting into app.cancel_approval_request), the other
--    calling app.decide_purchase_order_approval_step with a REJECT decision on the SAME
--    bound request's sole active step (a reject finalizes even at step 1 of a
--    multi-step sequential routing, so it always reaches app.decide_approval_step's own
--    approval_requests write) -- reproduce a genuine Postgres deadlock (SQLSTATE 40P01)
--    with zero purchase_orders involvement at all. This is a pre-existing PLT-123
--    defect, not introduced by this batch, but it is the actual mechanism that makes
--    the HIGH-severity finding this batch was asked to close still reproducible after
--    fix 4 alone -- so it is fixed here too, at the true root, using the exact same
--    "touch a pre-existing shared PLT-123 function via CREATE OR REPLACE in a new
--    migration" precedent the immediately preceding batch's own
--    `20260730670000_harden_procurement_batch_257_259_review_fixes.sql` already
--    established for `app.decide_approval_step` itself (section 9 there). The fix is a
--    pure statement reorder -- app.approval_request_steps locked BEFORE app.
--    approval_requests, matching app.decide_approval_step's own order exactly -- with no
--    change to the function's final state, signature, or grants (same signature, CREATE
--    OR REPLACE only, no re-GRANT needed). This is shared, cross-domain engine code
--    (also composed by Commercial quotation/credit approvals, not only Procurement),
--    but the reorder changes ONLY lock acquisition order, never behavior, so its blast
--    radius is the same class of safe, universally-applicable change
--    `20260730670000` already made to this exact function's own sibling.
-- ===========================================================================

create or replace function app.cancel_approval_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.approval_requests
language plpgsql
as $$
declare
  v_request app.approval_requests;
  v_updated app.approval_requests;
begin
  select * into v_request from app.approval_requests where id = p_request_id;
  if not found then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Batch 260 review (C-21, HIGH, live-reproduced): app.approval_request_steps is now
  -- locked BEFORE app.approval_requests -- matching app.decide_approval_step's own
  -- order exactly (see this section's own header comment above). Final state is
  -- byte-for-byte identical to before; only lock ACQUISITION order changed.
  update app.approval_request_steps set status = 'skipped' where request_id = p_request_id and status in ('pending', 'active');
  update app.approval_requests set status = 'cancelled', ended_at = now(), ended_reason = p_reason where id = p_request_id returning * into v_updated;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_approval_request',
    'app.approval_requests', v_updated.id, 'success', p_reason, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.cancel_approval_request is 'PLT-123: cancels a pending approval request and skips every still-pending/active step. Batch 260 review (C-21, HIGH): app.approval_request_steps is now locked BEFORE app.approval_requests, matching app.decide_approval_step''s own lock order exactly -- closes a live-reproduced deadlock (SQLSTATE 40P01) between this function and app.decide_approval_step when both race on the same request''s bound steps (surfaced via app.cancel_purchase_order vs app.decide_purchase_order_approval_step, PRC-260, but the fix is in this shared function so every domain composing the Platform Approval Engine benefits). Final state unchanged -- lock order only.';
