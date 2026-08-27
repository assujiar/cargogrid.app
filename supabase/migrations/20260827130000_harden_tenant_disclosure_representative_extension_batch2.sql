-- Track B Batch 2, ISS-2026-043 and ISS-2026-048 (docs/runtime/KNOWN_ISSUES.md): a
-- repository-wide pattern -- a by-id lookup resolves the target row's real tenant_id
-- BEFORE checking whether the calling identity has any relationship to that tenant at
-- all, then echoes that real tenant_id verbatim into the resulting insufficient_authority
-- error text. 043/048 already fixed this for the 13 by-id read RPCs and ~32 by-id write
-- RPCs their own originating migrations introduced (a `has_active_tenant_membership`
-- check folded into the SAME not-found branch a missing id already produces -- the
-- established pattern, e.g. app.get_rfq in 20260730670000_harden_procurement_batch_
-- 257_259_review_fixes.sql, and independently re-applied at a wrapper level for
-- app.decide_automation_rule_publish_approval in 20260803030000_harden_intelligence_
-- batch2_tier_c_review_fixes.sql). Both issues explicitly disclose the class as
-- repository-wide (~300+ functions by a heuristic scan) and out of scope for a single
-- bounded migration.
--
-- This migration extends the fix to 7 more representative, verified, currently-open
-- instances -- a deliberately cross-domain sample (Procurement/Sourcing, Commercial
-- rate-lookup, the shared Platform Approval Engine twice over, Advanced TMS/WMS,
-- Finance, and a PII-reveal RPC) chosen because 5 of them live in the SAME migrations
-- that already fixed 043's/048's own enumerated function lists, yet were themselves
-- missed by those very fixes -- concrete proof the class needs a second pass, not proof
-- it has been swept. The full repository-wide sweep remains explicitly out of scope and
-- stays open under 043/048; this is the same "fix a small, named, representative subset;
-- disclose the rest" treatment ISS-2026-054's own 15-function batch and ISS-2026-167
-- (Track B Batch 1) both already established as this repository's own precedent for a
-- class too large for one bounded pass.
--
-- Fixing app.decide_approval_step (Part G below) also closes the second half of
-- ISS-2026-049 as a side effect: that issue's own text names two gaps, (1) each
-- decide_*_approval_step wrapper checking entity_type before authority (still open --
-- LOW severity, the review's own explicit "disclose, not partially fix" choice, unchanged
-- by this migration), and (2) the shared app.decide_approval_step itself echoing the
-- real tenant_id in its own insufficient_authority error (closed here, at the single
-- choke point every decide_*_approval_step wrapper composes).

-- ===========================================================================
-- Part A: app.get_sourcing_request -- fold tenant-membership into not-found
-- ===========================================================================
-- Verbatim current body from 20260730630000_create_procurement_sourcing.sql, with
-- exactly the initial lookup changed.
create or replace function app.get_sourcing_request(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns app.sourcing_requests_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.sourcing_requests_directory;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    r.id, r.tenant_id, r.org_unit_id, r.source_type, r.source_costing_request_id, r.source_shipment_order_id,
    -- ADVERSARIAL REVIEW FIX (design note 16a): mask demand_snapshot's own
    -- budget_amount key exactly like the typed column two lines below -- otherwise
    -- a cost-masked caller reads the real amount straight through the snapshot.
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.demand_snapshot else r.demand_snapshot - 'budget_amount' end,
    r.service_type, r.mode, r.origin_lane, r.destination_lane, r.cargo_weight_min, r.cargo_weight_max, r.cargo_volume_min, r.cargo_volume_max,
    r.requested_pickup_at, r.requested_delivery_at, r.currency,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.budget_amount else null end,
    not app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id),
    r.status, r.owner_user_id, r.sla_due_at, r.closed_reason, r.shortlist_locked_at, r.record_version, r.created_by, r.created_at, r.updated_at
  into v_row
  from app.sourcing_requests r
  where r.id = p_sourcing_request_id;

  return v_row;
end;
$$;

comment on function app.get_sourcing_request is 'CG-S11-PRC-007 (Prompt 256): by-id read, masks cost fields behind PRC:View cost. ISS-2026-043 extension fix (Track B Batch 2): the initial lookup now folds app.has_active_tenant_membership into the same not-found branch a missing id already produces -- a genuine stranger to the request''s tenant no longer learns its real tenant_id via a tenant-echoing insufficient_authority error.';

-- ===========================================================================
-- Part B: app.select_vendor_rate -- fold tenant-membership into the initial
-- costing_request lookup's not-found branch
-- ===========================================================================
-- Verbatim current body from 20260730670000_harden_procurement_batch_257_259_review_
-- fixes.sql, with exactly the initial costing_request lookup changed. The later
-- `tenant_mismatch` branch (rate version belongs to a different tenant than the
-- caller's OWN already-authorized costing request) is unaffected -- it echoes only the
-- caller's own already-known tenant_id, never a foreign one, so it carries no oracle risk
-- (the same reasoning Track B Batch 1 applied to a same-tenant-member-lacking-authority
-- case for app.revoke_api_key).
create or replace function app.select_vendor_rate(
  p_costing_request_id uuid,
  p_rate_version_id uuid,
  p_is_adhoc boolean,
  p_adhoc_currency text,
  p_adhoc_amount numeric,
  p_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_weight numeric default null,
  p_volume numeric default null,
  p_quantity numeric default null
)
returns app.rate_selections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_decision_prc_cost app.rbac_decision;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc record;
  v_amount numeric;
  v_snapshot jsonb;
begin
  select * into v_request from app.costing_requests where id = p_costing_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'costing_request_not_found: %', p_costing_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a rate selection', p_costing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to select a rate', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_costing_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_is_adhoc then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'reason_required: an ad-hoc rate selection requires a non-empty override reason'
        using errcode = 'not_null_violation';
    end if;
    if p_adhoc_currency is null or p_adhoc_currency !~ '^[A-Z]{3}$' or p_adhoc_amount is null or p_adhoc_amount < 0 then
      raise exception 'invalid_adhoc_rate: an ad-hoc selection requires a valid 3-letter currency and a non-negative amount'
        using errcode = 'check_violation';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, null, true, p_adhoc_currency, p_adhoc_amount,
      jsonb_build_object('is_adhoc', true, 'currency', p_adhoc_currency, 'amount', p_adhoc_amount, 'override_reason', p_override_reason),
      p_override_reason, p_actor_label
    )
    returning * into v_selection;
  else
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_request.tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_request.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_rate.approval_status <> 'approved' and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
      raise exception 'reason_required: selecting a % (not approved) rate version requires a non-empty override reason', v_rate.approval_status
        using errcode = 'not_null_violation';
    end if;

    -- PRC-255 addition: when tier-matching inputs are supplied, snapshot the exact
    -- tier-matched calculation (RPD-040) via the SAME private helper app.calculate_
    -- vendor_rate itself calls -- omitting them (every pre-PRC-255 caller)
    -- reproduces COM-149's original flat base_amount behavior unchanged.
    --
    -- SECURITY FIX (post-review): computing a tier-matched amount embeds the
    -- SAME sensitive tier cost breakdown (matched_tier_id, matched_tier_amount,
    -- tier_component, ...) that app.calculate_vendor_rate/app.vendor_rate_tiers_
    -- directory correctly gate behind PRC:View cost (design note 2/ADR-0020's own
    -- directed reuse of that gate for this checkpoint's new sensitive-field
    -- class). The pre-existing COM:Edit + COM:View cost gate above is COM-149's
    -- own unchanged authority for the flat-base_amount case, but it is NOT
    -- sufficient authority for the tier-derived case -- a Commercial-side actor
    -- holding only COM:View cost (no PRC permissions at all) could otherwise
    -- supply p_weight/p_volume/p_quantity and receive the full negotiated
    -- vendor-tier cost structure in the returned snapshot, bypassing the separate
    -- PRC:View cost boundary this migration's own design intends. So: PRC:View
    -- cost is required IN ADDITION to the unchanged COM gates, but ONLY on this
    -- branch (tier inputs supplied) -- every pre-PRC-255 caller (all three null)
    -- never reaches this check and is completely unaffected.
    if p_weight is not null or p_volume is not null or p_quantity is not null then
      v_decision_prc_cost := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'View cost');
      if not v_decision_prc_cost.allowed then
        raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) required to compute/snapshot a tier-matched rate amount', p_actor_auth_user_id, v_decision_prc_cost.reason
          using errcode = 'insufficient_privilege';
      end if;
      select * into v_calc from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity);
      v_amount := v_calc.computed_amount;
      -- Batch 257-259 review (C-08, HIGH): strip the two PRC-259 governance
      -- columns app.vendor_rate_versions was widened with -- to_jsonb(v_rate)
      -- would otherwise silently carry them into a snapshot this function's own
      -- COM-only authority model never re-checks against PRC:View.
      v_snapshot := (to_jsonb(v_rate) - 'governance_approval_status' - 'governance_approval_request_id') || jsonb_build_object('calculation', to_jsonb(v_calc));
    else
      v_amount := v_rate.base_amount;
      v_snapshot := to_jsonb(v_rate) - 'governance_approval_status' - 'governance_approval_request_id';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, v_rate.id, false, v_rate.currency, v_amount, v_snapshot, p_override_reason, p_actor_label
    )
    returning * into v_selection;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_vendor_rate',
    'app.rate_selections', v_selection.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_costing_request_id, 'is_adhoc', v_selection.is_adhoc, 'rate_version_id', v_selection.rate_version_id)
  );

  return v_selection;
end;
$$;

comment on function app.select_vendor_rate is 'COM-149, widened PRC-255: three new optional trailing parameters (p_weight, p_volume, p_quantity). Every pre-PRC-255 caller (all null) reproduces the original flat base_amount snapshot unchanged and needs only the unchanged COM:Edit + COM:View cost gate; supplying any of them additionally REQUIRES PRC:View cost. Batch 257-259 review (C-08, HIGH): the snapshot strips governance_approval_status/governance_approval_request_id at write time on both branches. ISS-2026-043 extension fix (Track B Batch 2): the initial costing_request lookup now folds app.has_active_tenant_membership into the same not-found branch a missing id already produces.';

-- ===========================================================================
-- Part C: app.cancel_approval_request -- fold tenant-membership into not-found
-- ===========================================================================
-- Verbatim current body from 20260730690000_harden_procurement_purchase_order_batch_
-- 260_review_fixes.sql, with exactly the authority-check branch changed.
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

  -- ISS-2026-048 extension fix (Track B Batch 2): a genuine stranger to
  -- v_request.tenant_id (zero membership, not Supreme Admin -- exactly what
  -- app.check_approval_request_authority already tests) now gets the same
  -- not-found error a nonexistent request id produces, never learning this
  -- request's real tenant_id via a tenant-echoing insufficient_authority error.
  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
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

comment on function app.cancel_approval_request is 'PLT-123: cancels a pending approval request and skips every still-pending/active step. Batch 260 review (C-21, HIGH): app.approval_request_steps is now locked BEFORE app.approval_requests, matching app.decide_approval_step''s own lock order exactly. ISS-2026-048 extension fix (Track B Batch 2): a genuine stranger to the request''s tenant now gets the same not-found error a nonexistent id produces, never a tenant-echoing insufficient_authority error.';

-- ===========================================================================
-- Part D: app.get_wms_inbound_order -- fold tenant-membership into not-found
-- ===========================================================================
-- Verbatim current body from 20260730180000_create_advanced_tms_wms_inbound.sql, with
-- exactly the initial lookup changed. app.list_wms_inbound_order_lines delegates to this
-- function, so it is covered by the same fix without its own edit.
create or replace function app.get_wms_inbound_order(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns app.wms_inbound_orders
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;

  return v_order;
end;
$$;

comment on function app.get_wms_inbound_order is 'ATW-016A: by-id read, OPS:View + org-unit-scope gated. ISS-2026-043 extension fix (Track B Batch 2): the initial lookup now folds app.has_active_tenant_membership into the same not-found branch a missing id already produces.';

-- ===========================================================================
-- Part E: app.approve_finance_invoice -- fold tenant-membership into not-found
-- ===========================================================================
-- Verbatim current body from 20260810700000_harden_finance_authority_chain_security_
-- definer.sql (the latest of 2 prior redefinitions, NOT the original 20260729110000_
-- create_finance_invoice.sql body -- checked exhaustively, case-insensitive, across
-- every migration before drafting, after an earlier draft of this specific function was
-- caught by this batch's own db-tests wrapper-security-mode regression check: it had
-- silently dropped this later migration's own SECURITY DEFINER + SET search_path (the
-- Finance Authority Chain hardening) and its FOR UPDATE row lock, which a bare
-- CREATE OR REPLACE with unspecified SECURITY silently resets to INVOKER, the Postgres
-- default -- caught before this migration was applied anywhere, not after), with
-- exactly the initial lookup changed.
create or replace function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_invoices
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'submitted' then
    raise exception 'finance_invoice_not_submitted: invoice % is % not submitted', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

comment on function app.approve_finance_invoice is 'FIN-197: FIN:Approve-gated invoice approval, optimistic-concurrency guarded (row locked FOR UPDATE, not merely a version-compared UPDATE). Finance Authority Chain hardening: SECURITY DEFINER with SET search_path. ISS-2026-048 extension fix (Track B Batch 2): the initial lookup now folds app.has_active_tenant_membership into the same not-found branch a missing id already produces.';

-- ===========================================================================
-- Part F: app.reveal_vendor_bank_account_number -- fold tenant-membership into
-- not-found
-- ===========================================================================
-- Verbatim current body from 20260730610000_create_procurement_vendor_financial_
-- security.sql, with exactly the initial lookup changed. Scope note: this closes only
-- the tenant-id-disclosure oracle on the lookup itself -- ISS-2026-037's own separate,
-- larger, disclosed gap (a denied reveal attempt is never durably audited, because the
-- raise here rolls back any audit insert attempted first) is unrelated and unchanged by
-- this migration.
create or replace function app.reveal_vendor_bank_account_number(
  p_account_id uuid, p_reveal_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (account_number text, account_holder_name text, bank_name text, currency text, purpose text, status text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_account app.vendor_bank_accounts;
  v_plaintext text;
begin
  if p_reveal_reason is null or length(trim(p_reveal_reason)) = 0 then
    raise exception 'reveal_reason_required: a non-empty, purpose-bound reason is required to reveal a bank account number' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if not app.has_prc_view_personal_data(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View personal data for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_plaintext := app._decrypt_vendor_financial_value(v_account.account_number_encrypted);

  -- Design notes 6, 9: the audit row NEVER carries the plaintext or the ciphertext --
  -- only the fact of the reveal, the reveal reason, and the already-public last4 form.
  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'reveal_vendor_bank_account_number',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reveal_reason, null,
    jsonb_build_object('account_last4', v_account.account_number_last4, 'reveal_reason', p_reveal_reason),
    p_correlation_id
  );

  return query select v_plaintext, v_account.account_holder_name, v_account.bank_name, v_account.currency, v_account.purpose, v_account.status;
end;
$$;

comment on function app.reveal_vendor_bank_account_number is 'PRC-254 design note 6: the ONLY path that ever decrypts app.vendor_bank_accounts.account_number_encrypted. Gated on app.has_prc_view_personal_data, a non-empty purpose-bound reveal reason, and MFA reauth freshness. Every successful call is unconditionally audited -- never a silent decrypt. ISS-2026-043 extension fix (Track B Batch 2): the initial lookup now folds app.has_active_tenant_membership into the same not-found branch a missing id already produces -- a genuine stranger no longer learns this account''s real tenant_id via a tenant-echoing insufficient_authority error. ISS-2026-037''s own separate, disclosed denial-audit gap is unrelated and unchanged.';

-- ===========================================================================
-- Part G: app.decide_approval_step -- fold tenant-membership into not-found,
-- closing ISS-2026-049's own second half as a side effect
-- ===========================================================================
-- Verbatim current body from 20260730670000_harden_procurement_batch_257_259_review_
-- fixes.sql, with exactly the authority-check branch changed -- mirrors the identical
-- fix already independently applied one checkpoint earlier at the wrapper level
-- (app.decide_automation_rule_publish_approval, IAE-007 Tier C finding 3, see this
-- migration's own header). A real member of the request's tenant who simply is not an
-- eligible approver still gets a specific, more useful error from the
-- is_eligible_approval_approver check a few lines below -- not a leak, they already
-- belong there (the same reasoning Track B Batch 1 applied to app.revoke_api_key).
create or replace function app.decide_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_allow_self_approval boolean;
  v_updated_step app.approval_request_steps;
  v_next_step_id uuid;
  v_remaining_active integer;
  v_approved_step_count integer;
  v_total_step_count integer;
  v_threshold_required_steps integer;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'approval_invalid_decision: decision % must be approved or rejected', p_decision
      using errcode = 'check_violation';
  end if;

  -- Batch 257-259 review (C-18-adjacent, MEDIUM): a reject requires a real
  -- reason at the RPC layer itself, not only in a calling Server Action --
  -- closes the identical, previously-undisclosed gap in every domain that
  -- composes this shared engine function (quotation/credit/procurement).
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject an approval step' using errcode = 'check_violation';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;

  -- ISS-2026-049 fix, second half (Track B Batch 2): a genuine stranger to
  -- v_request.tenant_id now gets the same not-found error a nonexistent step id
  -- produces, never learning this step's real tenant_id via a tenant-echoing
  -- insufficient_authority error. Also closes ISS-2026-043/048's own class at this
  -- shared engine choke point, for every decide_*_approval_step wrapper that does
  -- not already carry its own pre-check.
  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be decided', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_step.status <> 'active' then
    raise exception 'approval_step_not_active: step % is %, only an active step can be decided', p_request_step_id, v_step.status
      using errcode = 'check_violation';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_allow_self_approval
  from app.config_items where config_version_id = v_request.config_version_id and key = 'allow_self_approval';
  if not coalesce(v_allow_self_approval, false) and v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'approval_self_approval_denied: identity % requested this approval and self-approval is not allowed', p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  if not app.is_eligible_approval_approver(v_step, v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an eligible approver for step %', p_actor_auth_user_id, p_request_step_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.approval_decisions (request_step_id, actor_auth_user_id, actor_label, decision, reason)
    values (p_request_step_id, p_actor_auth_user_id, p_actor_label, p_decision, p_reason);
  exception
    when unique_violation then
      raise exception 'approval_decision_already_recorded: identity % has already decided step %', p_actor_auth_user_id, p_request_step_id
        using errcode = 'unique_violation';
  end;

  if p_decision = 'rejected' then
    update app.approval_request_steps set status = 'rejected' where id = p_request_step_id and status = 'active' returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;
    update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active') and id <> p_request_step_id;
    update app.approval_requests set status = 'rejected', ended_at = now(), ended_reason = p_reason where id = v_request.id;
  else
    update app.approval_request_steps
    set approvals_count = approvals_count + 1,
        status = case when approvals_count + 1 >= required_approvals then 'approved' else 'active' end
    where id = p_request_step_id and status = 'active'
    returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;

    if v_updated_step.status = 'approved' then
      if v_request.pattern = 'sequential' then
        select id into v_next_step_id from app.approval_request_steps where request_id = v_request.id and step_order = v_updated_step.step_order + 1;
        if found then
          update app.approval_request_steps set status = 'active' where id = v_next_step_id;
        else
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all sequential steps approved' where id = v_request.id;
        end if;
      elsif v_request.pattern = 'parallel' then
        select count(*) into v_remaining_active from app.approval_request_steps where request_id = v_request.id and status not in ('approved', 'skipped');
        if v_remaining_active = 0 then
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all parallel steps approved' where id = v_request.id;
        end if;
      else -- threshold
        select count(*) into v_approved_step_count from app.approval_request_steps where request_id = v_request.id and status = 'approved';
        select count(*) into v_total_step_count from app.approval_request_steps where request_id = v_request.id;
        select (value #>> '{}')::integer into v_threshold_required_steps from app.config_items where config_version_id = v_request.config_version_id and key = 'threshold_required_steps';
        if v_approved_step_count >= v_threshold_required_steps then
          update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active');
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = format('threshold %s of %s steps approved', v_threshold_required_steps, v_total_step_count) where id = v_request.id;
        end if;
      end if;
    end if;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', p_reason, to_jsonb(v_step), to_jsonb(v_updated_step)
  );

  select * into v_updated_step from app.approval_request_steps where id = p_request_step_id;
  return v_updated_step;
end;
$$;

comment on function app.decide_approval_step is 'PLT-123: the core decision engine (Prompt 123 §20 task 3/§21/§22/§25). Real optimistic concurrency and no-duplicate-decision protection come from two structural guarantees: the atomic UPDATE ... WHERE status = ''active'' below, and approval_decisions'' own unique(request_step_id, actor_auth_user_id). Batch 257-259 review (C-18-adjacent, MEDIUM): a reject now requires a non-empty p_reason at this shared choke point. ISS-2026-049 fix, second half (Track B Batch 2): a genuine stranger to the request''s tenant now gets the same not-found error a nonexistent step id produces, never a tenant-echoing insufficient_authority error -- also closes ISS-2026-043/048''s own class at this shared engine choke point. ISS-2026-049''s own first half (entity_type checked before authority in each decide_*_approval_step wrapper) is unrelated and stays open.';

grant execute on function app.decide_approval_step(uuid, text, uuid, text, text) to service_role;
