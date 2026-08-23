-- Advanced TMS/WMS capability ATW-025 (CG-S10-ATW-025, Prompt 244, "Advanced Claim
-- and Incident Operations") -- an auditable operational claim/incident lifecycle
-- (intake, evidence, investigation, liability/reserve proposal-vs-decision, recovery,
-- Finance settlement handoff, reconciled closure) EXTENDING the Step 8 canonical case
-- root, without autonomous legal/insurance decisions and without duplicate financial
-- truth (Prompt 244 objective, verbatim).
--
-- ===========================================================================
-- Canonical root, extended never duplicated (Prompt 244 §24: "Extend the Step 8
-- canonical case; no duplicate claim/incident root or silent re-entry.")
-- ===========================================================================
-- `app.operational_exceptions` (OPS-174, `20260727150000_create_operations_
-- exception_escalation.sql`, VERIFIED) is the ONE case/incident root in this
-- repository -- id, tenant_id, shipment_order_id, milestone_event_id, type
-- (delay|hold|damage|loss|incident), severity, status, owner_user_id,
-- escalation_level, source, correlation_key, description, internal_notes,
-- damage_loss_details jsonb, claim_amount/claim_currency (disclosed by that
-- migration's own header as "non-authoritative estimates, never posted to any
-- ledger" -- exactly the boundary this task's own §24 repeats). Every table below is
-- a CHILD of an existing `app.operational_exceptions` row via a NEW, unique-
-- constrained `app.claim_case_extensions.operational_exception_id` column -- this
-- migration NEVER creates a base exception itself (`app.open_claim_case` takes an
-- EXISTING `operational_exception_id` as input, always calling `app.report_exception`
-- indirectly through the caller, never composing it) and NEVER writes directly to
-- `app.operational_exceptions` except through ITS OWN already-verified RPCs
-- (`app.resolve_exception`/`app.close_exception`/`app.reopen_exception`, called for
-- real from `app.close_claim_case`/`app.reopen_claim_case` below -- their own
-- validation is never bypassed).
--
-- ===========================================================================
-- Claim-eligible exception types (a disclosed scope judgment call)
-- ===========================================================================
-- The brief's own default reading was damage|loss|incident. Prompt 244 §27's own
-- test-data requirement explicitly names "Damage/loss/shortage/delay cases" --
-- 'delay' is named explicitly, so `app.open_claim_case` accepts type IN
-- ('damage','loss','incident','delay'). 'shortage' is NOT a real
-- `operational_exceptions.type` value (that CHECK-constrained enum is fixed at
-- delay|hold|damage|loss|incident, OPS-174's own migration, never edited here) --
-- a shortage is represented at the ITEM level instead, via `app.claim_items.
-- item_type`/`description` under a 'loss' or 'damage' exception, never as a
-- fabricated sixth base-exception type. 'hold' is excluded: it is not named
-- anywhere in §27's test-data list, and a hold represents an unresolved
-- operational BLOCK (customs/credit/etc.), not a completed adverse event with a
-- quantifiable loss/impact basis -- there is nothing yet to itemize a claim against
-- while a shipment is merely on hold. Attempting `app.open_claim_case` against a
-- 'hold' (or any other non-claim-eligible) exception raises
-- `claim_ineligible_exception_type`, live-reproduced in this migration's own db-test.
--
-- ===========================================================================
-- Design decisions disclosed against the brief's own REQUIRED DESIGN section
-- ===========================================================================
-- 1. `app.claim_case_extensions.claimant_account_id` is a literal FK to `app.
--    accounts` exactly as specified -- `app.accounts` (COM-155) is the canonical
--    CUSTOMER/account master, so this column is the natural identifier only for a
--    'customer' (or arguably 'internal', where it is expected null) claimant. For
--    claimant_type in (carrier|vendor|third_party), the natural real-world party
--    reference would be `app.master_records` (vendor/fleet), but the brief's own
--    fixed column list types this column against `app.accounts` specifically and
--    separately names `claimant_label text (for a non-account party)` -- read
--    literally: a carrier/vendor/third_party claimant is exactly the "non-account
--    party" case the brief anticipates, and uses `claimant_label` (plus
--    `contact_snapshot`) instead. Extending `claimant_account_id` into a polymorphic
--    reference across `app.accounts`/`app.master_records` is a real, disclosed
--    limitation this task does not attempt -- not silently worked around.
-- 2. `contact_snapshot` PII minimization is enforced structurally, not just by
--    convention: `app.validate_claim_contact_snapshot` (mirrors `app.
--    validate_warehouse_billing_tier_schedule`'s own function-in-a-CHECK precedent,
--    ATW-022) rejects any jsonb object whose keys are not a subset of
--    {name, phone, email} -- both as a real table CHECK and as an explicit early
--    RPC validation for a clear message, the same double-enforcement style ATW-022
--    already established.
-- 3. `app.claim_evidence_links` is a REAL validated polymorphic link (never a
--    literal FK per type, mirroring `app.files`' own record_type/record_id
--    convention exactly, per the brief). `app.link_claim_evidence` looks up the
--    real source row for each of the 6 fixed `evidence_type` values and rejects
--    anything not found/mismatched BEFORE inserting:
--    - shipment_leg / epod_capture: both carry a direct `shipment_order_id` column
--      (verified directly against `20260729290000_..._multi_leg_shipment.sql` and
--      `20260728100000_..._epod_capture_review.sql`) -- tenant_id AND
--      shipment_order_id must both match the case's own underlying exception.
--    - shipment_leg_custody_event: has NO `shipment_order_id` of its own (verified
--      directly) -- joins through `app.shipment_legs` to get both tenant_id and
--      shipment_order_id, then applies the identical two-column match.
--    - inventory_movement / wms_outbound_shipment: BOTH verified directly to carry
--      no `shipment_order_id` column at all (`app.inventory_movements` is
--      warehouse-scoped by design, ATW-015; `app.wms_outbound_shipments` is scoped
--      to `outbound_order_id`/`warehouse_id`/`owner_account_id`, ATW-019 -- neither
--      table has ever been linked to a Shipment Order in this repository). Their own
--      validation therefore cannot use a shipment_order_id match -- disclosed here
--      rather than fabricating one this repository's own real schema cannot support.
--      This is also why Prompt 244 §27's "package"/"receiving discrepancy" test-data
--      items are represented via `wms_outbound_shipment` (the package's own
--      containing shipment) and `inventory_movement` (a receiving-time adjustment
--      movement) respectively -- the brief's own fixed 6-value `evidence_type` enum
--      carries no dedicated wms_package/wms_receipt_line slot, so the closest real,
--      already-verified evidence source stands in for each, disclosed rather than
--      silently widening the enum.
--      A same-tenant/cross-customer gap here was caught by adversarial review and is
--      fixed to the extent this repository's own real schema allows (Prompt 244 §25
--      "reject tenant/customer/shipment/warehouse/owner/source/version mismatch"):
--      `app.wms_outbound_shipments` carries a real, always-populated `owner_account_id`
--      -- both `app.link_claim_evidence` and `app.add_claim_item` now additionally
--      require it to equal this claim case's own underlying shipment order's
--      `shipper_account_id` (also always populated), rejecting a same-tenant,
--      different-customer shipment with the same `claim_evidence_scope_mismatch`
--      used everywhere else in this function, live-reproduced fixed in this
--      migration's own db-test. `app.inventory_movements` (the HEADER row actually
--      validated) has no owner/customer column of its own at all -- ownership lives
--      one level down, on `app.inventory_movement_lines.owner_account_id`, and one
--      movement header can genuinely carry lines for more than one owner account (a
--      real warehouse-batch shape, not a per-claim concept) -- there is no single,
--      unambiguous column on the row this RPC validates to compare, so tenant_id
--      remains the only match for this one evidence type. This is a genuine,
--      disclosed schema-shape limitation, not an oversight left unfixed.
--    - file: reuses `app.files`/`app.authorize_file_access` DIRECTLY (PLT-128),
--      never a second file-security mechanism, per the brief's own explicit
--      instruction. Validates tenant_id AND record_type='shipment_order' AND
--      record_id=<the case's own shipment_order_id> (the identical convention
--      already used by `app.set_epod_evidence`/document-checklist/actual-cost
--      evidence -- reused, not reinvented) and REJECTS an unsafe/unscanned file
--      (`malware_scan_status <> 'clean'`) with a named `claim_evidence_file_unsafe`
--      error BEFORE the link is inserted (RPD-032's "unsafe files never satisfy"
--      rule, live-reproduced in this migration's own db-test) -- `metadata_view`
--      alone (the one access_type `app.authorize_file_access` does NOT gate on scan
--      status) would not catch this, so the explicit named check runs first; `app.
--      authorize_file_access` is still called afterward (access_type=
--      'metadata_view') purely to produce a real, additional `app.file_access_logs`
--      audit entry -- belt-and-suspenders reuse, not a second security mechanism.
--      The nested call needs no separate grant (the same "runs as the outer
--      SECURITY DEFINER function's own owner, which already holds implicit rights
--      to every object it created" reliance ATW-022's own header already disclosed
--      for `app.compute_warehouse_billing_breakdown`).
-- 4. Investigator-only evidence management (Prompt 244 §21 "investigator gathers
--    versioned evidence and itemized impact" / §26 "assigned investigators manage
--    evidence") reuses `app.operational_exceptions.owner_user_id` AS the
--    investigator role, exactly per the brief -- no second assignment column. This
--    is enforced uniformly across ALL FOUR evidence-management RPCs -- `app.
--    add_claim_item`, `app.withdraw_claim_item`, `app.link_claim_evidence`, AND
--    `app.record_claim_investigation_finding` -- the acting identity must equal the
--    underlying exception's own current owner_user_id (else `claim_not_investigator`)
--    in every one of them, live-reproduced (a non-owner rejected on all four).
--    Adversarial review caught an earlier draft that enforced this on
--    `record_claim_investigation_finding` alone while the other three checked only
--    OPS:Edit + record-scope -- corrected here for the uniform reading both §21 and
--    §26 support. `app.open_claim_case` itself deliberately stays OPS:Create +
--    record-scope only, never investigator-gated (it is what §26 separately calls
--    "Operations intake/triage" -- the case does not have an investigator to check
--    against yet at the moment it is opened; an owner is assigned afterward via the
--    already-existing, unedited `app.assign_exception_owner`, OPS-174).
-- 5. `app.claim_responsibility_reviews` carries both proposal and decision on ONE
--    row (mirrors `app.billing_readiness_evaluations`' own single-row
--    evaluate+override shape, OPS-181), versioned (version_number/is_current/
--    supersedes_review_id, the identical shape) so a fresh proposal cycle after a
--    governed reopen creates a new current row while the prior DECIDED row remains
--    full, un-overwritten history. `app.propose_claim_responsibility` updates the
--    SAME row in place ONLY while status='proposed' (no version churn -- nothing has
--    been decided yet); once decided, a further proposal call starts a new version.
--    `app.propose_claim_responsibility` takes its own real `p_expected_version`
--    (nullable -- null means "no current review exists for this case yet", the only
--    value that is valid on a case's first-ever proposal; otherwise it must exactly
--    equal the current review's own `record_version`) and enforces it with the same
--    `stale_version` errcode every sibling status-mutating RPC in this migration
--    already uses. Adversarial review live-reproduced a real lost update on an
--    earlier draft that had NO version check at all on this RPC's own in-place
--    UPDATE (two concurrent proposals on the same still-'proposed' row silently
--    clobbered one another -- no error, no trace, `record_version` still incremented
--    once, proving a real UPDATE fired and swallowed the loser's content) --
--    corrected here to close that gap for real, not merely documented around.
--    `app.propose_claim_responsibility`/`app.decide_claim_responsibility` also both
--    now enforce Prompt 244 §23's "block ... missing custody/quantity evidence"
--    exception-flow rule for real: proposing (or amending) a POSITIVE reserve amount
--    with zero `app.claim_items` and zero `app.claim_evidence_links` on file for the
--    case is rejected `claim_evidence_required`. This is deliberately conditional,
--    not universal -- a genuinely zero-reserve claim (this migration's own db-test
--    case3: a delay confirmed to have caused no quantifiable loss) legitimately has
--    nothing to itemize, and requiring evidence for it would fabricate a demand this
--    repository's own real data cannot support; a DENIED decision is the same "no
--    compensable loss recognized" shape and is also exempt. Gating both the
--    original propose AND the decide-time amend path closes the one bypass a
--    propose-only gate would leave open (proposing at reserve=0, then amending to a
--    real positive number at decide time with still nothing on file).
--    `app.decide_claim_responsibility` enforces separation of duties with the EXACT
--    existing `self_approval_not_allowed` phrasing/errcode `app.
--    approve_warehouse_billing_event` already established (ATW-022, confirmed by
--    direct grep before writing this migration's own copy): decided_by must not
--    equal proposed_by. A system-proposed row (`p_actor_label` a service-role/system
--    literal, e.g. 'system') still requires a real human `decided_by` -- nothing
--    here auto-transitions a proposal to approved (§24's own "system may
--    summarize/propose only" rule).
--    `final_currency` is ADDED beyond the brief's own literal column list (which
--    named only final_responsibility_party/final_reserve_amount/decision_notes) --
--    disclosed: every other money-shaped pair in this repository always carries its
--    own currency column (`operational_exceptions.claim_amount`/`claim_currency`,
--    `claim_recovery_records.recovered_amount`/`currency`, `claim_items.
--    declared_value`/`currency`) -- a bare `final_reserve_amount` with no currency
--    would be a genuine, avoidable ambiguity on an 'amended' decision. Defaults to
--    the proposal's own `proposed_currency` when the decision does not amend it.
-- 6. `app.claim_recovery_records` is strictly append-only -- no UPDATE path exists
--    anywhere in this migration; a correction is always a new row referencing the
--    original via `corrects_recovery_id` (mirrors ATW-022's own no-silent-amount-
--    rewrite convention, per the brief).
-- 6b. Three items from Prompt 244 §22/§23 are honestly disclosed here as NOT built
--    this checkpoint, the same explicit way design point 7 below already discloses
--    the settlement-readiness-override omission -- an earlier draft left these
--    three silent instead of disclosed, corrected on adversarial review:
--    - Case MERGE ("merge duplicates while retaining lineage") and SPLIT ("split
--      affected items"), §22. Genuinely out of this bounded task's design surface --
--      the brief's own required-RPC list (design points 1-9 above) names neither,
--      and a real merge/split needs its own lineage/re-parenting model (which of two
--      canonical `app.operational_exceptions` rows survives, how `app.claim_items`
--      re-attach, how two independent `app.claim_responsibility_reviews` chains
--      reconcile) that would exceed this migration's own additive-extension scope.
--      `claim_evidence_scope_mismatch` already prevents ACCIDENTAL duplicate
--      evidence attachment across cases (the narrower, in-scope half of §23's own
--      "duplicate case" exception), but detecting and merging a genuine DUPLICATE
--      CASE ROOT is not attempted here.
--    - "Request more evidence" (§22) has no dedicated RPC/status. The closest real,
--      already-shipped representation is `app.claim_investigation_findings.
--      evidence_sufficiency = 'insufficient'` (a real investigator-recorded signal
--      distinguishable from 'sufficient'/'pending') -- a genuine but soft analog,
--      not a request/notification workflow, disclosed as such rather than silently
--      implied.
--    - Retention/legal-hold conflict (§23) is not implemented. `app.files.
--      legal_hold` is a real, existing column (PLT-128) this migration could have
--      checked before `app.link_claim_evidence` accepts a file, but does not --
--      genuinely out of scope for this bounded task, left as a real gap for a future
--      checkpoint rather than a fabricated check.
-- 7. Finance handoff mirrors BOTH named precedents read directly before designing
--    this (`app.billing_readiness_evaluations`/`_handoffs`, OPS-181; `app.
--    warehouse_billing_events`'s own handoff/reconciliation pair, ATW-022):
--    `app.claim_settlement_readiness_evaluations` is versioned/is_current-exclusive
--    with REAL computed blockers (no_claim_items, no_approved_responsibility_
--    decision, no_finalized_reserve, no_recovery_records_yet -- this literal blocker
--    code is named directly in the brief's own text and implemented exactly:
--    it fires only when the current decision names any NON-internal responsible
--    party (carrier/vendor/customer/unknown -- i.e. `final_responsibility_party IS
--    DISTINCT FROM 'internal'`, not merely the three party values named in this
--    sentence's own earlier draft, corrected on adversarial review to literally
--    match the code) with a positive finalized reserve, and zero `app.
--    claim_recovery_records` rows exist yet for the case). Both `no_claim_items` and
--    `no_approved_responsibility_decision` are exercised by this migration's own
--    db-test (case3, evaluated immediately after opening, before any item/proposal
--    exists). `app.claim_settlement_readiness_evaluations`/`app.
--    claim_settlement_readiness_handoffs` are readable, beyond the raw RLS-scoped
--    SELECT every one of this migration's 8 new tables already carries as defense in
--    depth, through two dedicated OPS:View-gated read RPCs -- `app.
--    get_claim_settlement_readiness` (record-scoped, masks the evaluation's own
--    `evidence->>'finalReserveAmount'` for a caller lacking OPS:View cost, the exact
--    money-figure `app.mask_claim_responsibility_review_amounts` already masks
--    elsewhere in this same migration -- an earlier draft left this reserve amount
--    reachable unmasked via the raw table, caught on adversarial review) and `app.
--    list_claim_settlement_readiness_handoffs` (record-scoped, ordered by the same
--    `handoff_seq desc` `app.close_claim_case` itself relies on) -- see design point
--    9 below; both mirror ATW-022's own `app.get_warehouse_billing_event`/`app.
--    list_warehouse_billing_handoffs` precedent exactly. `app.
--    claim_settlement_readiness_handoffs` is append-only and idempotent on
--    (tenant_id, claim_case_id, idempotency_key), exactly per the brief.
--    `app.record_claim_finance_reconciliation_outcome` mirrors `app.
--    record_warehouse_billing_reconciliation_outcome` EXACTLY -- service_role ONLY
--    (no authenticated grant at all), idempotent-on-same-outcome, rejects a
--    conflicting second outcome -- "mechanism proven, live wiring deferred" the
--    identical disclosed way ATW-022 already stated, since no live Finance consumer
--    exists in this repository yet.
--    NO override RPC exists for claim settlement readiness (unlike OPS-181's own
--    `app.override_billing_readiness`) -- not named anywhere in the brief's required-
--    RPC list (§7/design point 7), and an override here would mean forcing a claim
--    into Finance handoff despite a genuinely missing human responsibility decision
--    -- materially different from OPS-181's own evidence-administrative-gate
--    override (which never bypasses a human decision). Disclosed as out of scope,
--    not silently added.
--    Zero writes to any Finance-schema table anywhere in this migration -- grepped
--    directly against the final file before shipping (`grep -in
--    "finance_invoice\|finance_accounts_receivable\|finance_accounts_payable\|
--    finance_journal" this migration`); the ONLY Finance-adjacent objects touched
--    are read-only reuse of `app.finance_currencies(code)` as a plain lookup FK
--    target (currency-code validity only, never an amount/rate/journal write) --
--    the exact same reuse class every prior ATW/OPS migration already uses.
-- 8. `app.close_claim_case`'s EXACT closure gate (disclosed precisely, per the
--    brief's own instruction): claim_stage must not already be 'closed', and
--    EITHER (a) the case's own MOST RECENT `app.claim_settlement_readiness_
--    handoffs` row (by `handoff_seq` -- a real identity column, NOT
--    `handed_off_at`: PostgreSQL's `now()` is fixed for an entire transaction, so
--    two handoffs created by separate calls inside the SAME transaction would
--    otherwise carry identical `handed_off_at` values, a real ambiguity this
--    migration's own db-test live-reproduced -- see `app.claim_settlement_
--    readiness_handoffs`' own comment) has reconciliation_status='reconciled'
--    (closure_basis='finance_reconciled'), OR (b) the case's own current `app.
--    claim_responsibility_reviews` row is decided (status IN ('approved','amended')
--    with `final_reserve_amount` null-or-zero, i.e. nothing was ever actually owed)
--    OR status='denied' (closure_basis='no_handoff_required') -- "withdrawn" is
--    represented as a 'denied' decision whose own `decision_notes` records the
--    withdrawal reason, since the brief's own required-RPC list (design points 1-9)
--    names no separate withdraw RPC and inventing one would exceed the specified
--    design surface; disclosed rather than silently added. Neither condition met
--    raises `claim_case_not_reconciled`. On success, `app.close_claim_case` drives
--    the underlying `app.operational_exceptions` row through ITS OWN real
--    `app.resolve_exception`/`app.close_exception` RPCs (never a direct table
--    write) -- open/acknowledged/reopened resolves-then-closes; already-resolved
--    closes only; already-closed is a no-op (the base exception's own closure
--    precondition is already satisfied). This means `app.close_claim_case`'s own
--    OPS:Close gate is necessary but not always SUFFICIENT: the acting identity
--    must also separately hold whatever `app.resolve_exception` (OPS:Edit) and
--    `app.close_exception` (OPS:Close) themselves require -- deliberate, proving
--    those two RPCs are invoked for real rather than bypassed, per the brief's own
--    explicit instruction. `app.reopen_claim_case` is a governed reopen (mandatory
--    reason) that resets `claim_stage` to 'investigating' (the brief's own fixed
--    8-value `claim_stage` enum has no dedicated 'reopened' state, unlike the base
--    exception -- 'investigating' is the natural "look at this again" landing
--    stage) and drives `app.reopen_exception` for real on the underlying exception;
--    closure_note/closure_basis/closed_at/closed_by are left untouched (full
--    history preserved, never overwritten, per the brief).
--    `claim_stage` itself is a DERIVED, forward-only progress marker driven by each
--    lifecycle RPC's own real action (open->intake, first item/evidence->
--    evidence_gathering, first investigation finding->investigating, first
--    proposal->pending_decision, a decision->decided, first recovery record->
--    recovering, handoff->finance_handoff, close->closed) -- there is no separate
--    free-text "set stage" RPC, since the brief's required-RPC list does not name
--    one and every named RPC already has a real, natural stage side effect. A stage
--    transition only ever advances except via the governed `app.reopen_claim_case`
--    (closed -> investigating) -- never moves backward silently, and a rejected
--    Finance reconciliation outcome does NOT retroactively revert claim_stage off
--    'finance_handoff' (a fresh evaluate+handoff cycle remains callable regardless;
--    the finer reconciliation state lives on the handoff row itself).
-- 9. Read RPCs are OPS:View-gated and record-scoped via ONE new shared helper,
--    `app.claim_case_record_scope_ok` (mirrors `app.actor_can_view_owner_scoped_row`
--    /`app.wms_pick_record_scope_ok`'s own "one predicate, many RLS policies AND
--    RPCs" reuse pattern) -- joins operational_exceptions -> shipment_orders and
--    calls `app.can_access_record`, the exact template `app.report_exception`'s own
--    record-scope check already uses. `app.list_claim_cases` is cursor-paginated
--    on (updated_at, id), the real `(p_cursor_updated_at, p_cursor_id)` convention
--    `app.list_customer_inventory_balances` (ATW-023) established, never OFFSET;
--    its filters (tenant/claim_stage/exception type+severity+status/shipment) are a
--    disclosed superset of the brief's literal "tenant/status/severity/shipment"
--    wording, since severity/type/status only exist on the underlying exception
--    (joined in, also returned as convenience columns to avoid an N+1 read) while
--    claim_stage is this extension's own added field -- both are genuinely useful,
--    neither is fabricated. Money-bearing read RPCs
--    (`list_claim_items`/`get_claim_responsibility_review`/
--    `list_claim_recovery_records`, and the two new settlement-readiness read RPCs
--    below) mask their own financial columns for a caller lacking `OPS:View cost`,
--    reusing `app.has_view_exception_cost` (OPS-174) DIRECTLY -- never a second,
--    redundant field-masking permission check -- mirroring `app.
--    mask_warehouse_billing_event_amounts`'s own per-row masking-function shape
--    (ATW-022). `app.get_claim_settlement_readiness`/`app.
--    list_claim_settlement_readiness_handoffs` (added on adversarial review -- see
--    design point 7 above for why) follow the identical OPS:View + record-scope +
--    cost-masking shape as every other read RPC in this list, never a special case.
--    No REST/GraphQL route or UI this checkpoint for the OPS-staff-facing surface
--    above (backend/contract-only) -- the identical disclosed boundary every
--    ATW-012 through ATW-024 checkpoint already used (full case-queue/timeline/
--    investigation-checklist UI is Prompt 244's own §15 ask, deferred here the same
--    way).
--    Separately, and disclosed honestly here after adversarial review corrected an
--    earlier draft's own mischaracterization: Prompt 244 §26's "customers see only
--    allowed case/status/evidence fields" is NOT implemented at ANY layer this
--    checkpoint -- every read RPC above gates on staff OPS:View only, with no
--    customer-facing read path at all. The earlier draft claimed this "matches"
--    ATW-023's own deferral -- it does not: ATW-023 (`20260730310000_..._customer_
--    inventory_access.sql`, verified directly before writing this correction) built
--    a full, real, non-OPS-gated customer-facing BACKEND CONTRACT (`app.
--    evaluate_customer_inventory_access` and a dozen `app.list/get_customer_*`
--    RPCs, its own dedicated deny-by-default authorization primitive, no staff RBAC
--    involved) and deferred ONLY the UI/REST-GraphQL surface on top of it. ATW-025
--    defers the ENTIRE customer path -- backend contract AND UI both -- a materially
--    WIDER deferral than ATW-023's, not the same one. This is a real, disclosed
--    scope boundary for this bounded task (most OPS-domain checkpoints before
--    ATW-023 introduced the first customer-facing contract precedent deferred the
--    entire customer path the same way ATW-025 does here), not a claim that nothing
--    was deferred -- but it is not ATW-023's own narrower precedent, and this
--    migration no longer says otherwise.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement
-- before its final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 0. Shared internal helpers.
-- ===========================================================================

create function app.validate_claim_contact_snapshot(p_snapshot jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
begin
  if p_snapshot is null then
    return true;
  end if;
  if jsonb_typeof(p_snapshot) <> 'object' then
    return false;
  end if;
  for v_key in select jsonb_object_keys(p_snapshot) loop
    if v_key not in ('name', 'phone', 'email') then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

comment on function app.validate_claim_contact_snapshot is
  'ATW-025: PII-minimization gate (Prompt 244 §16/§26) -- true iff p_snapshot is null or a jsonb object whose keys are a subset of {name, phone, email}, mirroring app.resource_assignments.resource_snapshot''s own {code,name}-only minimization precedent (OPS-172). Used both as a real table CHECK and re-checked explicitly in app.open_claim_case for a clear claim_invalid_contact_snapshot message.';

-- ONE shared record-scope predicate for every RLS policy AND every RPC below --
-- mirrors app.actor_can_view_owner_scoped_row/app.wms_pick_record_scope_ok's own
-- "one predicate, many callers" precedent (ATW-016/ATW-022). Works identically
-- whether p_operational_exception_id names an exception that already has a claim
-- case extension or not (app.open_claim_case calls this BEFORE the extension row
-- exists).
create function app.claim_case_record_scope_ok(p_auth_user_id uuid, p_tenant_id uuid, p_operational_exception_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.operational_exceptions oe
    join app.shipment_orders so on so.id = oe.shipment_order_id
    where oe.id = p_operational_exception_id
      and oe.tenant_id = p_tenant_id
      and app.can_access_record(p_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  );
$$;

comment on function app.claim_case_record_scope_ok is
  'ATW-025: the single record-scope predicate every claim/incident RLS policy and RPC below shares -- joins operational_exceptions -> shipment_orders and delegates to app.can_access_record, the exact template app.report_exception (OPS-174) already uses for the same underlying exception/shipment pair.';

-- ===========================================================================
-- 1. app.claim_case_extensions -- one row per operational_exceptions.id escalated
--    into advanced-claim scope. unique(operational_exception_id) makes "no
--    duplicate root or silent re-entry" a real DB constraint.
-- ===========================================================================

create table app.claim_case_extensions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  operational_exception_id uuid not null references app.operational_exceptions (id),
  claimant_type text not null,
  claimant_account_id uuid references app.accounts (id),
  claimant_label text,
  contact_snapshot jsonb,
  claim_stage text not null default 'intake',
  opened_by text,
  opened_at timestamptz not null default now(),
  closure_note text,
  closure_basis text,
  closed_at timestamptz,
  closed_by text,
  reopened_at timestamptz,
  reopened_by text,
  reopen_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claim_case_extensions_operational_exception_unique unique (operational_exception_id),
  constraint claim_case_extensions_claimant_type_check check (claimant_type in ('customer', 'carrier', 'vendor', 'third_party', 'internal')),
  constraint claim_case_extensions_claim_stage_check check (claim_stage in ('intake', 'evidence_gathering', 'investigating', 'pending_decision', 'decided', 'recovering', 'finance_handoff', 'closed')),
  constraint claim_case_extensions_contact_snapshot_check check (app.validate_claim_contact_snapshot(contact_snapshot)),
  constraint claim_case_extensions_claimant_identification_check check (
    claimant_type = 'internal' or claimant_account_id is not null or (claimant_label is not null and length(trim(claimant_label)) > 0)
  ),
  constraint claim_case_extensions_closure_basis_check check (closure_basis is null or closure_basis in ('finance_reconciled', 'no_handoff_required')),
  -- One-way implication only (never a full equality): a reopened case
  -- (claim_stage back to 'investigating') deliberately PRESERVES its own prior
  -- closure_note/closure_basis/closed_at/closed_by as history (per this
  -- migration's own "never overwritten by reopen" design) -- those columns stay
  -- non-null even while claim_stage is no longer 'closed'. Only the forward
  -- direction is a real invariant: whenever claim_stage IS 'closed', the four
  -- closure columns must be populated.
  constraint claim_case_extensions_closure_shape_check check (
    claim_stage <> 'closed' or (closed_at is not null and closure_basis is not null and closure_note is not null and closed_by is not null)
  ),
  constraint claim_case_extensions_reopen_shape_check check (
    reopened_at is null or (reopen_reason is not null and length(trim(reopen_reason)) > 0 and reopened_by is not null)
  )
);

comment on table app.claim_case_extensions is
  'ATW-025: a CHILD of an existing app.operational_exceptions row (OPS-174), never a second case root. unique(operational_exception_id) is the real DB constraint behind "no duplicate root or silent re-entry" -- app.open_claim_case is idempotent on this column. claim_stage is a derived, forward-only progress marker (see migration header) -- the only backward move is the governed app.reopen_claim_case (closed -> investigating), which never clears closure_note/closure_basis/closed_at/closed_by (full history preserved).';

create index claim_case_extensions_tenant_stage_idx on app.claim_case_extensions (tenant_id, claim_stage);
create index claim_case_extensions_tenant_updated_idx on app.claim_case_extensions (tenant_id, updated_at desc, id desc);
create index claim_case_extensions_claimant_account_idx on app.claim_case_extensions (claimant_account_id);

create function app.touch_claim_case_extensions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger claim_case_extensions_touch_row
  before update on app.claim_case_extensions
  for each row
  execute function app.touch_claim_case_extensions_row();

-- Small internal helper: advances claim_stage forward only, per the fixed ordering
-- below -- a no-op if p_target_stage is not strictly later than the case's own
-- current stage (never regresses silently; the sole governed regression is app.
-- reopen_claim_case, implemented directly, not through this helper).
create function app.advance_claim_case_stage(p_case_id uuid, p_target_stage text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_order text[] := array['intake', 'evidence_gathering', 'investigating', 'pending_decision', 'decided', 'recovering', 'finance_handoff', 'closed'];
  v_current text;
  v_current_rank integer;
  v_target_rank integer;
begin
  select claim_stage into v_current from app.claim_case_extensions where id = p_case_id;
  v_current_rank := array_position(v_order, v_current);
  v_target_rank := array_position(v_order, p_target_stage);
  if v_target_rank is not null and v_current_rank is not null and v_target_rank > v_current_rank then
    update app.claim_case_extensions set claim_stage = p_target_stage where id = p_case_id;
  end if;
end;
$$;

comment on function app.advance_claim_case_stage is
  'ATW-025: internal only (no grant) -- forward-only claim_stage progression per the migration header''s disclosed ordering. Never called for the closed stage itself (app.close_claim_case sets that directly, together with its own required closure_basis/closure_note/closed_at/closed_by shape).';

-- ===========================================================================
-- 2. app.claim_items -- itemized loss/damage/shortage lines (Prompt 244 §13).
--    Append-oriented: withdrawing an item is a status flip, never a delete.
-- ===========================================================================

create table app.claim_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  item_type text not null,
  linked_inventory_movement_id uuid references app.inventory_movements (id),
  linked_wms_outbound_shipment_id uuid references app.wms_outbound_shipments (id),
  item_master_id uuid references app.item_masters (id),
  declared_quantity numeric not null,
  uom_code text not null references app.uoms (code),
  declared_value numeric(14, 2),
  currency text references app.finance_currencies (code),
  description text not null,
  status text not null default 'active',
  withdrawn_at timestamptz,
  withdrawn_by text,
  withdrawal_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claim_items_item_type_check check (item_type in ('inventory', 'package', 'cargo_general')),
  constraint claim_items_status_check check (status in ('active', 'withdrawn')),
  constraint claim_items_declared_quantity_check check (declared_quantity > 0),
  constraint claim_items_declared_value_check check (declared_value is null or declared_value >= 0),
  constraint claim_items_value_currency_shape_check check ((declared_value is null) = (currency is null)),
  constraint claim_items_description_check check (length(trim(description)) > 0),
  constraint claim_items_withdrawal_shape_check check (
    (status = 'withdrawn') = (withdrawn_at is not null and withdrawal_reason is not null and length(trim(withdrawal_reason)) > 0)
  )
);

comment on table app.claim_items is
  'ATW-025: one itemized loss/damage/shortage line per row, optionally linked to a real evidence source (linked_inventory_movement_id/linked_wms_outbound_shipment_id/item_master_id, all optional per Prompt 244 §13). Append-oriented -- app.withdraw_claim_item is a status flip (active -> withdrawn), never a delete, mirroring this repository''s own never-delete-financial-adjacent-rows convention throughout.';

create index claim_items_tenant_case_idx on app.claim_items (tenant_id, claim_case_id);
create index claim_items_linked_movement_idx on app.claim_items (linked_inventory_movement_id);
create index claim_items_linked_shipment_idx on app.claim_items (linked_wms_outbound_shipment_id);

create function app.touch_claim_items_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger claim_items_touch_row
  before update on app.claim_items
  for each row
  execute function app.touch_claim_items_row();

-- ===========================================================================
-- 3. app.claim_evidence_links -- a real, validated polymorphic link (never a
--    literal FK per type, mirroring app.files' own record_type/record_id
--    convention). See migration header design note 3 for the exact per-type
--    validation this migration's own app.link_claim_evidence RPC performs.
-- ===========================================================================

create table app.claim_evidence_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  evidence_type text not null,
  evidence_id uuid not null,
  note text,
  added_by_auth_user_id uuid,
  added_by text,
  added_at timestamptz not null default now(),
  constraint claim_evidence_links_evidence_type_check check (
    evidence_type in ('shipment_leg', 'shipment_leg_custody_event', 'inventory_movement', 'wms_outbound_shipment', 'epod_capture', 'file')
  ),
  constraint claim_evidence_links_case_evidence_unique unique (claim_case_id, evidence_type, evidence_id)
);

comment on table app.claim_evidence_links is
  'ATW-025: append-only (no update/delete RPC anywhere in this migration). A real, VALIDATED polymorphic link -- app.link_claim_evidence resolves evidence_id against the correct real source table for evidence_type and rejects a not-found/tenant-or-shipment-mismatched/unsafe-file reference before insert (see migration header design note 3). unique(claim_case_id, evidence_type, evidence_id) prevents an identical duplicate link, a reasonable added guard beyond the brief''s own literal ask.';

create index claim_evidence_links_tenant_case_idx on app.claim_evidence_links (tenant_id, claim_case_id);
create index claim_evidence_links_evidence_idx on app.claim_evidence_links (evidence_type, evidence_id);

-- ===========================================================================
-- 4. app.claim_investigation_findings -- append-only investigation log.
-- ===========================================================================

create table app.claim_investigation_findings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  investigator_auth_user_id uuid not null,
  finding_text text not null,
  evidence_sufficiency text not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint claim_investigation_findings_finding_text_check check (length(trim(finding_text)) > 0),
  constraint claim_investigation_findings_evidence_sufficiency_check check (evidence_sufficiency in ('sufficient', 'insufficient', 'pending'))
);

comment on table app.claim_investigation_findings is
  'ATW-025: append-only investigation log -- no update/delete RPC. app.record_claim_investigation_finding requires investigator_auth_user_id to equal the case''s own underlying app.operational_exceptions.owner_user_id (the investigator role is reused directly from OPS-174''s own owner assignment, per Prompt 244''s own instruction -- no second, redundant assignment column).';

create index claim_investigation_findings_tenant_case_idx on app.claim_investigation_findings (tenant_id, claim_case_id, created_at);

-- ===========================================================================
-- 5. app.claim_responsibility_reviews -- ONE table carrying both the proposal
--    and the human decision (mirrors app.billing_readiness_evaluations' own
--    single-row evaluate+override shape). Versioned/is_current-exclusive.
-- ===========================================================================

create table app.claim_responsibility_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  proposed_responsibility_party text not null,
  proposed_reserve_amount numeric(14, 2),
  proposed_currency text references app.finance_currencies (code),
  proposed_rationale text not null,
  proposed_by_auth_user_id uuid not null,
  proposed_by text,
  proposed_at timestamptz not null default now(),
  status text not null default 'proposed',
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz,
  final_responsibility_party text,
  final_reserve_amount numeric(14, 2),
  final_currency text references app.finance_currencies (code),
  decision_notes text,
  supersedes_review_id uuid references app.claim_responsibility_reviews (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claim_responsibility_reviews_proposed_party_check check (proposed_responsibility_party in ('carrier', 'vendor', 'customer', 'internal', 'unknown')),
  constraint claim_responsibility_reviews_final_party_check check (final_responsibility_party is null or final_responsibility_party in ('carrier', 'vendor', 'customer', 'internal', 'unknown')),
  constraint claim_responsibility_reviews_status_check check (status in ('proposed', 'approved', 'denied', 'amended')),
  constraint claim_responsibility_reviews_proposed_reserve_check check (proposed_reserve_amount is null or proposed_reserve_amount >= 0),
  constraint claim_responsibility_reviews_final_reserve_check check (final_reserve_amount is null or final_reserve_amount >= 0),
  constraint claim_responsibility_reviews_reserve_currency_shape_check check ((proposed_reserve_amount is null) = (proposed_currency is null)),
  constraint claim_responsibility_reviews_rationale_check check (length(trim(proposed_rationale)) > 0),
  constraint claim_responsibility_reviews_decision_shape_check check (
    (status = 'proposed') = (decided_by_auth_user_id is null and decided_at is null)
  ),
  constraint claim_responsibility_reviews_final_shape_check check (
    (status in ('approved', 'amended')) = (final_responsibility_party is not null and final_reserve_amount is not null and final_currency is not null)
  ),
  constraint claim_responsibility_reviews_not_self_supersede check (supersedes_review_id is null or supersedes_review_id <> id)
);

comment on table app.claim_responsibility_reviews is
  'ATW-025: ONE row carries both the system/investigator PROPOSAL and the human DECISION (mirrors app.billing_readiness_evaluations'' own single-row evaluate+override shape, OPS-181). app.propose_claim_responsibility updates the SAME row in place only while status=''proposed''; once decided, a further proposal starts a NEW version (version_number/is_current/supersedes_review_id, the identical versioned shape). app.decide_claim_responsibility enforces decided_by <> proposed_by (self_approval_not_allowed, the exact app.approve_warehouse_billing_event convention, ATW-022) -- a system-proposed row still requires a real human decided_by.';

create unique index claim_responsibility_reviews_one_current_idx on app.claim_responsibility_reviews (claim_case_id) where is_current;
create index claim_responsibility_reviews_tenant_case_idx on app.claim_responsibility_reviews (tenant_id, claim_case_id);

create function app.touch_claim_responsibility_reviews_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger claim_responsibility_reviews_touch_row
  before update on app.claim_responsibility_reviews
  for each row
  execute function app.touch_claim_responsibility_reviews_row();

-- ===========================================================================
-- 6. app.claim_recovery_records -- append-only. A correction is a new row
--    referencing the original via corrects_recovery_id, never an in-place edit.
-- ===========================================================================

create table app.claim_recovery_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  recovered_from text not null,
  recovered_amount numeric(14, 2) not null,
  currency text not null references app.finance_currencies (code),
  recovered_at timestamptz not null default now(),
  reference text,
  corrects_recovery_id uuid references app.claim_recovery_records (id),
  recorded_by_auth_user_id uuid,
  recorded_by text,
  created_at timestamptz not null default now(),
  constraint claim_recovery_records_recovered_from_check check (recovered_from in ('carrier', 'vendor', 'customer', 'insurance')),
  constraint claim_recovery_records_amount_check check (recovered_amount > 0),
  constraint claim_recovery_records_no_self_correct check (corrects_recovery_id is null or corrects_recovery_id <> id)
);

comment on table app.claim_recovery_records is
  'ATW-025: append-only (no update/delete RPC anywhere in this migration) -- a correction is a new row referencing the original via corrects_recovery_id, never an in-place amount edit, mirroring this repository''s own no-silent-amount-rewrite convention from ATW-022.';

create index claim_recovery_records_tenant_case_idx on app.claim_recovery_records (tenant_id, claim_case_id, recovered_at);
create index claim_recovery_records_corrects_idx on app.claim_recovery_records (corrects_recovery_id);

-- ===========================================================================
-- 7. Finance handoff -- mirrors app.billing_readiness_evaluations/_handoffs
--    (OPS-181) and app.warehouse_billing_events/_handoffs (ATW-022).
-- ===========================================================================

create table app.claim_settlement_readiness_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  evaluated_status text not null,
  blockers jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  reevaluation_reason text,
  supersedes_evaluation_id uuid references app.claim_settlement_readiness_evaluations (id),
  evaluated_by_auth_user_id uuid not null,
  evaluated_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claim_settlement_readiness_evaluations_status_check check (evaluated_status in ('ready', 'not_ready')),
  constraint claim_settlement_readiness_evaluations_version_check check (version_number > 0),
  constraint claim_settlement_readiness_evaluations_not_self_supersede check (supersedes_evaluation_id is null or supersedes_evaluation_id <> id)
);

comment on table app.claim_settlement_readiness_evaluations is
  'ATW-025: versioned, is_current-exclusive claim Finance-settlement-readiness evaluation (mirrors app.billing_readiness_evaluations, OPS-181). blockers are real, computed, named codes (no_claim_items/no_approved_responsibility_decision/no_finalized_reserve/no_recovery_records_yet) -- never fabricated. Reserve/settlement readiness IS a Finance handoff signal only; this table posts nothing to any ledger.';

create unique index claim_settlement_readiness_evaluations_one_current_idx on app.claim_settlement_readiness_evaluations (claim_case_id) where is_current;
create index claim_settlement_readiness_evaluations_tenant_case_idx on app.claim_settlement_readiness_evaluations (tenant_id, claim_case_id);

create function app.touch_claim_settlement_readiness_evaluations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger claim_settlement_readiness_evaluations_touch_row
  before update on app.claim_settlement_readiness_evaluations
  for each row
  execute function app.touch_claim_settlement_readiness_evaluations_row();

create table app.claim_settlement_readiness_handoffs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  claim_case_id uuid not null references app.claim_case_extensions (id),
  evaluation_id uuid not null references app.claim_settlement_readiness_evaluations (id),
  idempotency_key text not null,
  handed_off_by_auth_user_id uuid not null,
  handed_off_by text,
  handed_off_at timestamptz not null default now(),
  handoff_seq bigint generated always as identity,
  reconciliation_status text,
  reconciliation_note text,
  reconciled_at timestamptz,
  updated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint claim_settlement_readiness_handoffs_tenant_case_idempotency_unique unique (tenant_id, claim_case_id, idempotency_key),
  constraint claim_settlement_readiness_handoffs_reconciliation_status_check check (reconciliation_status is null or reconciliation_status in ('reconciled', 'rejected')),
  constraint claim_settlement_readiness_handoffs_reconciliation_shape_check check (
    (reconciliation_status is null and reconciliation_note is null and reconciled_at is null)
    or (reconciliation_status is not null and reconciliation_note is not null and reconciled_at is not null)
  )
);

comment on table app.claim_settlement_readiness_handoffs is
  'ATW-025: one append-only, idempotent Finance-handoff record per successful app.handoff_claim_settlement_readiness call (mirrors app.warehouse_billing_handoffs, ATW-022, almost exactly). reconciliation_status/note/reconciled_at change exactly once, later, via the dedicated service_role-only app.record_claim_finance_reconciliation_outcome RPC -- no blanket touch trigger on this table; updated_at is set manually inside that one RPC only. Zero writes anywhere to any Finance-schema table -- see migration header design note 7. handoff_seq (a real identity column, never client-supplied) is the authoritative "most recent handoff" ordering app.close_claim_case relies on -- handed_off_at (default now()) is informational/business-display only and is NOT used for that decision: now() is fixed for the lifetime of one transaction in PostgreSQL, so two handoffs created via separate calls inside the SAME transaction (a real scenario this migration''s own db-test live-reproduced, e.g. a rejected handoff immediately followed by a corrected re-handoff) would otherwise carry IDENTICAL handed_off_at values, making "order by handed_off_at desc limit 1" genuinely ambiguous -- a real bug class, not a hypothetical one, fixed by this monotonic column instead.';

create index claim_settlement_readiness_handoffs_tenant_case_idx on app.claim_settlement_readiness_handoffs (tenant_id, claim_case_id, handoff_seq desc);

-- ===========================================================================
-- 8. Lifecycle RPCs.
-- ===========================================================================

-- app.open_claim_case -- idempotent on operational_exception_id (design point 1).
create function app.open_claim_case(
  p_operational_exception_id uuid,
  p_claimant_type text,
  p_claimant_account_id uuid,
  p_claimant_label text,
  p_contact_snapshot jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_case_extensions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_existing app.claim_case_extensions;
  v_case app.claim_case_extensions;
begin
  select * into v_exception from app.operational_exceptions where id = p_operational_exception_id;
  if not found then
    raise exception 'operational_exception_not_found: %', p_operational_exception_id using errcode = 'no_data_found';
  end if;

  if p_claimant_type not in ('customer', 'carrier', 'vendor', 'third_party', 'internal') then
    raise exception 'claim_invalid_claimant_type: % is not a supported claimant type', p_claimant_type using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_exception.tenant_id, v_exception.id) then
    raise exception 'insufficient_authority: identity % cannot access exception %', p_actor_auth_user_id, p_operational_exception_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above,
  -- never before (the established ATW-020/021/022 lesson). A resubmission whose own
  -- non-key content (claimant_type/claimant_account_id/claimant_label/
  -- contact_snapshot) differs from the original open is rejected as a real conflict
  -- rather than silently discarded and the stale original returned -- the same
  -- check-a-mismatch-and-raise pattern ATW-021's own app.create_label_printer
  -- already established (adversarial review caught an earlier draft that silently
  -- discarded a mismatched resubmission here).
  select * into v_existing from app.claim_case_extensions where operational_exception_id = p_operational_exception_id;
  if found then
    if v_existing.claimant_type <> p_claimant_type
      or v_existing.claimant_account_id is distinct from p_claimant_account_id
      or v_existing.claimant_label is distinct from p_claimant_label
      or v_existing.contact_snapshot is distinct from p_contact_snapshot
    then
      raise exception 'claim_case_open_conflict: exception % already has an open claim case with different claimant details', p_operational_exception_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_exception.type not in ('damage', 'loss', 'incident', 'delay') then
    raise exception 'claim_ineligible_exception_type: exception % is type % which is not eligible for a claim case', p_operational_exception_id, v_exception.type
      using errcode = 'check_violation';
  end if;

  if p_claimant_account_id is not null and not exists (select 1 from app.accounts where id = p_claimant_account_id and tenant_id = v_exception.tenant_id) then
    raise exception 'claim_claimant_account_not_found: % is not an account of tenant %', p_claimant_account_id, v_exception.tenant_id using errcode = 'no_data_found';
  end if;
  if p_claimant_type <> 'internal' and p_claimant_account_id is null and (p_claimant_label is null or length(trim(p_claimant_label)) = 0) then
    raise exception 'claim_claimant_identification_required: a non-internal claimant requires either claimant_account_id or a non-empty claimant_label' using errcode = 'check_violation';
  end if;
  if p_contact_snapshot is not null and not app.validate_claim_contact_snapshot(p_contact_snapshot) then
    raise exception 'claim_invalid_contact_snapshot: contact_snapshot must contain only name/phone/email keys' using errcode = 'check_violation';
  end if;

  begin
    insert into app.claim_case_extensions (
      tenant_id, operational_exception_id, claimant_type, claimant_account_id, claimant_label, contact_snapshot, opened_by, created_by
    ) values (
      v_exception.tenant_id, p_operational_exception_id, p_claimant_type, p_claimant_account_id, p_claimant_label, p_contact_snapshot, p_actor_label, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      -- A genuinely concurrent duplicate open lost the race -- apply the identical
      -- mismatch check as the early short-circuit above (a true race can reach this
      -- branch with content that was never compared against the winner).
      select * into v_case from app.claim_case_extensions where operational_exception_id = p_operational_exception_id;
      if v_case.claimant_type <> p_claimant_type
        or v_case.claimant_account_id is distinct from p_claimant_account_id
        or v_case.claimant_label is distinct from p_claimant_label
        or v_case.contact_snapshot is distinct from p_contact_snapshot
      then
        raise exception 'claim_case_open_conflict: exception % already has an open claim case with different claimant details', p_operational_exception_id
          using errcode = 'unique_violation';
      end if;
      return v_case;
  end;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'open_claim_case',
    'app.claim_case_extensions', v_case.id, 'success', null, null,
    jsonb_build_object('operational_exception_id', p_operational_exception_id, 'claimant_type', p_claimant_type)
  );

  return v_case;
end;
$$;

comment on function app.open_claim_case is
  'ATW-025: idempotent on operational_exception_id (unique constraint) -- a genuine retry (identical claimant_type/claimant_account_id/claimant_label/contact_snapshot) returns the existing row, never a second one; a resubmission whose own content differs is rejected claim_case_open_conflict rather than silently discarding the original (mirrors app.create_label_printer, ATW-021). Validates the exception exists, belongs to the caller''s own tenant/record-scope, and its own type is claim-eligible (damage|loss|incident|delay -- see migration header). Never creates the base exception itself.';

-- app.add_claim_item.
create function app.add_claim_item(
  p_case_id uuid,
  p_item_type text,
  p_linked_inventory_movement_id uuid,
  p_linked_wms_outbound_shipment_id uuid,
  p_item_master_id uuid,
  p_declared_quantity numeric,
  p_uom_code text,
  p_declared_value numeric,
  p_currency text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_item app.claim_items;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_item_type not in ('inventory', 'package', 'cargo_general') then
    raise exception 'claim_invalid_item_type: % is not a supported item type', p_item_type using errcode = 'check_violation';
  end if;
  if p_declared_quantity is null or p_declared_quantity <= 0 then
    raise exception 'claim_invalid_declared_quantity: declared_quantity must be positive' using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_uom_code) then
    raise exception 'invalid_uom_code: % is not a registered UOM code', p_uom_code using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'claim_item_description_required: a non-empty description is required' using errcode = 'check_violation';
  end if;
  if (p_declared_value is null) <> (p_currency is null) then
    raise exception 'claim_value_currency_shape_invalid: declared_value and currency must both be set or both be null' using errcode = 'check_violation';
  end if;
  if p_declared_value is not null then
    if p_declared_value < 0 then
      raise exception 'claim_invalid_declared_value: declared_value must not be negative' using errcode = 'check_violation';
    end if;
    if not app.validate_currency_code(p_currency) then
      raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
    end if;
  end if;

  if p_linked_inventory_movement_id is not null and not exists (
    select 1 from app.inventory_movements where id = p_linked_inventory_movement_id and tenant_id = v_case.tenant_id
  ) then
    raise exception 'claim_evidence_not_found: inventory_movement % not found in tenant %', p_linked_inventory_movement_id, v_case.tenant_id using errcode = 'no_data_found';
  end if;
  if p_linked_wms_outbound_shipment_id is not null then
    if not exists (select 1 from app.wms_outbound_shipments where id = p_linked_wms_outbound_shipment_id and tenant_id = v_case.tenant_id) then
      raise exception 'claim_evidence_not_found: wms_outbound_shipment % not found in tenant %', p_linked_wms_outbound_shipment_id, v_case.tenant_id using errcode = 'no_data_found';
    end if;
    -- Same-tenant/cross-customer check (see migration header design note 3):
    -- owner_account_id must match this claim case's own shipment order's
    -- shipper_account_id.
    if (select owner_account_id from app.wms_outbound_shipments where id = p_linked_wms_outbound_shipment_id)
      <> (select shipper_account_id from app.shipment_orders where id = v_exception.shipment_order_id)
    then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % belongs to a different customer account than this claim case''s own shipment order', p_linked_wms_outbound_shipment_id
        using errcode = 'check_violation';
    end if;
  end if;
  if p_item_master_id is not null and not exists (
    select 1 from app.item_masters where id = p_item_master_id and tenant_id = v_case.tenant_id
  ) then
    raise exception 'claim_evidence_not_found: item_master % not found in tenant %', p_item_master_id, v_case.tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.claim_items (
    tenant_id, claim_case_id, item_type, linked_inventory_movement_id, linked_wms_outbound_shipment_id, item_master_id,
    declared_quantity, uom_code, declared_value, currency, description, created_by
  ) values (
    v_case.tenant_id, p_case_id, p_item_type, p_linked_inventory_movement_id, p_linked_wms_outbound_shipment_id, p_item_master_id,
    p_declared_quantity, p_uom_code, p_declared_value, p_currency, p_description, p_actor_label
  )
  returning * into v_item;

  perform app.advance_claim_case_stage(p_case_id, 'evidence_gathering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_claim_item',
    'app.claim_items', v_item.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'item_type', p_item_type, 'declared_quantity', p_declared_quantity)
  );

  return v_item;
end;
$$;

-- app.withdraw_claim_item -- status flip, never a delete.
create function app.withdraw_claim_item(
  p_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_item app.claim_items;
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a claim item requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_item from app.claim_items where id = p_item_id;
  if not found then
    raise exception 'claim_item_not_found: %', p_item_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_item.claim_case_id;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim item %', p_actor_auth_user_id, p_item_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'active' then
    raise exception 'invalid_transition: claim item % is % and cannot be withdrawn', p_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: claim item % expected version % but found %', p_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.claim_items
  set status = 'withdrawn', withdrawn_at = now(), withdrawn_by = p_actor_label, withdrawal_reason = p_reason
  where id = p_item_id and record_version = p_expected_version
  returning * into v_item;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_claim_item',
    'app.claim_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$$;

-- app.link_claim_evidence -- validates evidence_id against its real source table
-- BEFORE inserting (see migration header design note 3).
create function app.link_claim_evidence(
  p_case_id uuid,
  p_evidence_type text,
  p_evidence_id uuid,
  p_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_evidence_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_leg app.shipment_legs;
  v_custody app.shipment_leg_custody_events;
  v_epod app.epod_captures;
  v_movement app.inventory_movements;
  v_shipment app.wms_outbound_shipments;
  v_file app.files;
  v_access_log app.file_access_logs;
  v_link app.claim_evidence_links;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_evidence_type not in ('shipment_leg', 'shipment_leg_custody_event', 'inventory_movement', 'wms_outbound_shipment', 'epod_capture', 'file') then
    raise exception 'claim_invalid_evidence_type: % is not a supported evidence type', p_evidence_type using errcode = 'check_violation';
  end if;

  if p_evidence_type = 'shipment_leg' then
    select * into v_leg from app.shipment_legs where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: shipment_leg % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_leg.tenant_id <> v_case.tenant_id or v_leg.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: shipment_leg % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'shipment_leg_custody_event' then
    select ce.* into v_custody from app.shipment_leg_custody_events ce where ce.id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: shipment_leg_custody_event % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    select * into v_leg from app.shipment_legs where id = v_custody.shipment_leg_id;
    if v_leg.tenant_id <> v_case.tenant_id or v_leg.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: shipment_leg_custody_event % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'epod_capture' then
    select * into v_epod from app.epod_captures where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: epod_capture % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_epod.tenant_id <> v_case.tenant_id or v_epod.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: epod_capture % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'inventory_movement' then
    -- app.inventory_movements carries no shipment_order_id (warehouse-scoped by
    -- design, ATW-015, verified directly) -- tenant match only (see migration header).
    select * into v_movement from app.inventory_movements where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: inventory_movement % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_movement.tenant_id <> v_case.tenant_id then
      raise exception 'claim_evidence_scope_mismatch: inventory_movement % does not belong to this claim case''s own tenant', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'wms_outbound_shipment' then
    -- app.wms_outbound_shipments carries no shipment_order_id either (verified
    -- directly, ATW-019) -- tenant AND owner_account_id match (see migration
    -- header design note 3: owner_account_id must equal this claim case's own
    -- shipment order's shipper_account_id, closing the same-tenant/cross-customer
    -- gap caught on adversarial review).
    select * into v_shipment from app.wms_outbound_shipments where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: wms_outbound_shipment % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_shipment.tenant_id <> v_case.tenant_id then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % does not belong to this claim case''s own tenant', p_evidence_id using errcode = 'check_violation';
    end if;
    if v_shipment.owner_account_id <> (select shipper_account_id from app.shipment_orders where id = v_exception.shipment_order_id) then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % belongs to a different customer account than this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'file' then
    select * into v_file from app.files where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: file % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_case.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: file % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'claim_evidence_file_unsafe: file % has scan status % -- only clean evidence may be linked to a claim', p_evidence_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
    -- Reuse app.authorize_file_access DIRECTLY for a real, additional file-access
    -- audit entry (never a second file-security mechanism) -- see migration header.
    v_access_log := app.authorize_file_access(p_evidence_id, 'metadata_view', p_actor_auth_user_id, p_case_id);
    if v_access_log.result = 'denied' then
      raise exception 'claim_evidence_file_access_denied: file % access denied (%)', p_evidence_id, v_access_log.reason using errcode = 'insufficient_privilege';
    end if;
  end if;

  begin
    insert into app.claim_evidence_links (tenant_id, claim_case_id, evidence_type, evidence_id, note, added_by_auth_user_id, added_by)
    values (v_case.tenant_id, p_case_id, p_evidence_type, p_evidence_id, p_note, p_actor_auth_user_id, p_actor_label)
    returning * into v_link;
  exception
    when unique_violation then
      -- Idempotent replay on the SAME (claim_case_id, evidence_type, evidence_id)
      -- tuple -- a resubmission whose own note differs from the original is
      -- rejected as a real conflict rather than silently discarded (mirrors app.
      -- create_label_printer, ATW-021; adversarial review caught an earlier draft
      -- that silently discarded a mismatched note here).
      select * into v_link from app.claim_evidence_links where claim_case_id = p_case_id and evidence_type = p_evidence_type and evidence_id = p_evidence_id;
      if v_link.note is distinct from p_note then
        raise exception 'claim_evidence_link_conflict: evidence % (%) is already linked to claim case % with a different note', p_evidence_id, p_evidence_type, p_case_id
          using errcode = 'unique_violation';
      end if;
      return v_link;
  end;

  perform app.advance_claim_case_stage(p_case_id, 'evidence_gathering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_claim_evidence',
    'app.claim_evidence_links', v_link.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evidence_type', p_evidence_type, 'evidence_id', p_evidence_id)
  );

  return v_link;
end;
$$;

comment on function app.link_claim_evidence is
  'ATW-025: the acting identity must be the case''s own assigned investigator (operational_exceptions.owner_user_id, claim_not_investigator otherwise -- see migration header design note 4). Validates evidence_id exists in the correct real source table AND belongs to the same tenant (and, where the source table actually carries a shipment_order_id, the same shipment order; wms_outbound_shipment additionally requires owner_account_id to match this case''s own shipment order''s shipper_account_id) before inserting -- never an unvalidated evidence_id. Rejects an unsafe/unscanned file (claim_evidence_file_unsafe) before ever reaching app.authorize_file_access. Idempotent on (claim_case_id, evidence_type, evidence_id) via the table''s own unique index -- a resubmission whose own note differs from the original is rejected claim_evidence_link_conflict rather than silently discarded.';

-- app.record_claim_investigation_finding -- reuses operational_exceptions.
-- owner_user_id as the investigator role (design point 4).
create function app.record_claim_investigation_finding(
  p_case_id uuid,
  p_finding_text text,
  p_evidence_sufficiency text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_investigation_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_finding app.claim_investigation_findings;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_finding_text is null or length(trim(p_finding_text)) = 0 then
    raise exception 'claim_finding_text_required: a non-empty finding_text is required' using errcode = 'check_violation';
  end if;
  if p_evidence_sufficiency not in ('sufficient', 'insufficient', 'pending') then
    raise exception 'claim_invalid_evidence_sufficiency: % is not a supported evidence_sufficiency value', p_evidence_sufficiency using errcode = 'check_violation';
  end if;

  insert into app.claim_investigation_findings (tenant_id, claim_case_id, investigator_auth_user_id, finding_text, evidence_sufficiency, created_by)
  values (v_case.tenant_id, p_case_id, p_actor_auth_user_id, p_finding_text, p_evidence_sufficiency, p_actor_label)
  returning * into v_finding;

  perform app.advance_claim_case_stage(p_case_id, 'investigating');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_claim_investigation_finding',
    'app.claim_investigation_findings', v_finding.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evidence_sufficiency', p_evidence_sufficiency)
  );

  return v_finding;
end;
$$;

-- app.propose_claim_responsibility -- creates/updates the proposal, only while
-- status='proposed'. p_expected_version: optimistic concurrency (see migration
-- header design note 5) -- null iff no current review exists yet for this case,
-- else must exactly equal the current review's own record_version.
create function app.propose_claim_responsibility(
  p_case_id uuid,
  p_proposed_responsibility_party text,
  p_proposed_reserve_amount numeric,
  p_proposed_currency text,
  p_proposed_rationale text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_responsibility_reviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_current app.claim_responsibility_reviews;
  v_review app.claim_responsibility_reviews;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  if p_proposed_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
    raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_proposed_responsibility_party using errcode = 'check_violation';
  end if;
  if p_proposed_rationale is null or length(trim(p_proposed_rationale)) = 0 then
    raise exception 'claim_rationale_required: a non-empty proposed_rationale is required' using errcode = 'check_violation';
  end if;
  if (p_proposed_reserve_amount is null) <> (p_proposed_currency is null) then
    raise exception 'claim_reserve_currency_shape_invalid: proposed_reserve_amount and proposed_currency must both be set or both be null' using errcode = 'check_violation';
  end if;
  if p_proposed_reserve_amount is not null then
    if p_proposed_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: proposed_reserve_amount must not be negative' using errcode = 'check_violation';
    end if;
    if not app.validate_currency_code(p_proposed_currency) then
      raise exception 'invalid_currency: % is not a registered, active currency', p_proposed_currency using errcode = 'check_violation';
    end if;
  end if;

  select * into v_current from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;

  -- Optimistic concurrency (Prompt 244 §25 "reject ... stale mutation"; see
  -- migration header design note 5) -- a live-reproduced lost update on an earlier
  -- draft with no version check at all is fixed here. Covers BOTH the in-place
  -- update branch below (the exact bug that was reproduced) and the start-a-new-
  -- version branch (the caller must prove it read the case's current state, decided
  -- or not, before proposing again).
  if found then
    if p_expected_version is null or v_current.record_version <> p_expected_version then
      raise exception 'stale_version: claim responsibility review % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
        using errcode = 'check_violation';
    end if;
  elsif p_expected_version is not null then
    raise exception 'stale_version: claim case % has no current responsibility review yet but expected_version % was supplied', p_case_id, p_expected_version
      using errcode = 'check_violation';
  end if;

  -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
  -- header design note 5) -- a positive proposed reserve requires at least one
  -- itemized claim_items row or linked evidence record on file; a genuinely
  -- zero/null reserve (no compensable loss) is exempt.
  if p_proposed_reserve_amount is not null and p_proposed_reserve_amount > 0 then
    if not exists (select 1 from app.claim_items where claim_case_id = p_case_id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = p_case_id)
    then
      raise exception 'claim_evidence_required: claim case % proposes a positive reserve amount but has no itemized claim_items or linked evidence yet', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  if found and v_current.status = 'proposed' then
    update app.claim_responsibility_reviews
    set proposed_responsibility_party = p_proposed_responsibility_party,
        proposed_reserve_amount = p_proposed_reserve_amount,
        proposed_currency = p_proposed_currency,
        proposed_rationale = p_proposed_rationale,
        proposed_by_auth_user_id = p_actor_auth_user_id,
        proposed_by = p_actor_label,
        proposed_at = now()
    where id = v_current.id and record_version = p_expected_version
    returning * into v_review;
  else
    if found then
      update app.claim_responsibility_reviews set is_current = false where id = v_current.id and record_version = p_expected_version;
    end if;
    insert into app.claim_responsibility_reviews (
      tenant_id, claim_case_id, version_number, proposed_responsibility_party, proposed_reserve_amount, proposed_currency,
      proposed_rationale, proposed_by_auth_user_id, proposed_by, supersedes_review_id, created_by
    ) values (
      v_case.tenant_id, p_case_id, coalesce(v_current.version_number, 0) + 1, p_proposed_responsibility_party, p_proposed_reserve_amount, p_proposed_currency,
      p_proposed_rationale, p_actor_auth_user_id, p_actor_label, v_current.id, p_actor_label
    )
    returning * into v_review;
  end if;

  perform app.advance_claim_case_stage(p_case_id, 'pending_decision');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_claim_responsibility',
    'app.claim_responsibility_reviews', v_review.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'proposed_responsibility_party', p_proposed_responsibility_party, 'proposed_reserve_amount', p_proposed_reserve_amount)
  );

  return v_review;
end;
$$;

comment on function app.propose_claim_responsibility is
  'ATW-025: updates the SAME row in place only while status=proposed; once decided, a further proposal starts a new version. p_expected_version enforces real optimistic concurrency (stale_version) -- null iff no current review exists yet, else must equal the current review''s own record_version (see migration header design note 5; adversarial review live-reproduced a lost update on an earlier draft that had no version check at all here). Rejects claim_evidence_required for a positive proposed reserve with zero claim_items/claim_evidence_links on file.';

-- app.decide_claim_responsibility -- separation of duties (design point 5).
create function app.decide_claim_responsibility(
  p_review_id uuid,
  p_expected_version integer,
  p_decision text,
  p_final_responsibility_party text,
  p_final_reserve_amount numeric,
  p_final_currency text,
  p_decision_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_responsibility_reviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_review app.claim_responsibility_reviews;
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_currency text;
  v_updated app.claim_responsibility_reviews;
begin
  select * into v_review from app.claim_responsibility_reviews where id = p_review_id;
  if not found then
    raise exception 'claim_responsibility_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_review.claim_case_id;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', v_case.id using errcode = 'check_violation';
  end if;

  -- A governed liability/reserve decision -- OPS:Override (OPS has no dedicated
  -- 'Approve' action; mirrors app.approve_warehouse_billing_event's own identical
  -- choice, ATW-022, see migration header).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, v_case.id using errcode = 'insufficient_privilege';
  end if;

  if v_review.status <> 'proposed' then
    raise exception 'invalid_transition: claim responsibility review % is % and cannot be decided', p_review_id, v_review.status using errcode = 'check_violation';
  end if;
  if v_review.record_version <> p_expected_version then
    raise exception 'stale_version: claim responsibility review % expected version % but found %', p_review_id, p_expected_version, v_review.record_version
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'denied', 'amended') then
    raise exception 'claim_invalid_decision: % is not one of approved/denied/amended', p_decision using errcode = 'check_violation';
  end if;

  -- Separation of duties -- the EXACT existing self_approval_not_allowed
  -- convention app.approve_warehouse_billing_event already established (ATW-022).
  if v_review.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed claim responsibility review % and may not also decide it', p_actor_auth_user_id, p_review_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision in ('approved', 'amended') then
    if p_final_responsibility_party is null or p_final_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
      raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_final_responsibility_party using errcode = 'check_violation';
    end if;
    if p_final_reserve_amount is null or p_final_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: final_reserve_amount is required and must not be negative for an approved/amended decision' using errcode = 'check_violation';
    end if;
    v_currency := coalesce(p_final_currency, v_review.proposed_currency);
    if v_currency is null or not app.validate_currency_code(v_currency) then
      raise exception 'invalid_currency: a valid final currency is required for an approved/amended decision' using errcode = 'check_violation';
    end if;
    -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
    -- header design note 5) -- closes the "propose zero, amend to a real positive
    -- number" bypass a propose-time-only gate would leave open.
    if p_final_reserve_amount > 0 and not exists (select 1 from app.claim_items where claim_case_id = v_case.id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = v_case.id)
    then
      raise exception 'claim_evidence_required: claim case % is being decided with a positive final reserve amount but has no itemized claim_items or linked evidence yet', v_case.id
        using errcode = 'check_violation';
    end if;
  else
    if p_final_responsibility_party is not null or p_final_reserve_amount is not null then
      raise exception 'claim_denied_decision_shape_invalid: a denied decision must not carry a final_responsibility_party/final_reserve_amount' using errcode = 'check_violation';
    end if;
    v_currency := null;
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'claim_decision_notes_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.claim_responsibility_reviews
  set status = p_decision,
      decided_by_auth_user_id = p_actor_auth_user_id,
      decided_by = p_actor_label,
      decided_at = now(),
      final_responsibility_party = case when p_decision in ('approved', 'amended') then p_final_responsibility_party else null end,
      final_reserve_amount = case when p_decision in ('approved', 'amended') then p_final_reserve_amount else null end,
      final_currency = case when p_decision in ('approved', 'amended') then v_currency else null end,
      decision_notes = p_decision_notes
  where id = p_review_id and record_version = p_expected_version
  returning * into v_updated;

  perform app.advance_claim_case_stage(v_case.id, 'decided');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_claim_responsibility',
    'app.claim_responsibility_reviews', v_updated.id, 'success', p_decision_notes,
    jsonb_build_object('status', v_review.status),
    jsonb_build_object('status', v_updated.status, 'final_responsibility_party', v_updated.final_responsibility_party, 'final_reserve_amount', v_updated.final_reserve_amount)
  );

  return v_updated;
end;
$$;

comment on function app.decide_claim_responsibility is
  'ATW-025: OPS:Override. status must be proposed. Enforces decided_by <> proposed_by (self_approval_not_allowed, the exact app.approve_warehouse_billing_event convention). A system-proposed row still requires a real human decided_by -- nothing here auto-transitions a proposal to approved. Rejects claim_evidence_required for an approved/amended decision naming a positive final_reserve_amount with zero claim_items/claim_evidence_links on file for the case (see migration header design note 5).';

-- app.record_claim_recovery -- append-only; requires a decided (approved/amended)
-- responsibility review to already exist.
create function app.record_claim_recovery(
  p_case_id uuid,
  p_recovered_from text,
  p_recovered_amount numeric,
  p_currency text,
  p_recovered_at timestamptz,
  p_reference text,
  p_corrects_recovery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_recovery_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_review app.claim_responsibility_reviews;
  v_original app.claim_recovery_records;
  v_record app.claim_recovery_records;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found or v_review.status not in ('approved', 'amended') then
    raise exception 'claim_recovery_requires_decision: claim case % has no approved/amended responsibility decision yet', p_case_id using errcode = 'check_violation';
  end if;

  if p_recovered_from not in ('carrier', 'vendor', 'customer', 'insurance') then
    raise exception 'claim_invalid_recovered_from: % is not a supported recovery source', p_recovered_from using errcode = 'check_violation';
  end if;
  if p_recovered_amount is null or p_recovered_amount <= 0 then
    raise exception 'claim_invalid_recovered_amount: recovered_amount must be positive' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;
  if p_corrects_recovery_id is not null then
    select * into v_original from app.claim_recovery_records where id = p_corrects_recovery_id;
    if not found or v_original.claim_case_id <> p_case_id then
      raise exception 'claim_recovery_not_found: corrects_recovery_id % does not reference a recovery record of this same claim case', p_corrects_recovery_id
        using errcode = 'no_data_found';
    end if;
  end if;

  insert into app.claim_recovery_records (
    tenant_id, claim_case_id, recovered_from, recovered_amount, currency, recovered_at, reference, corrects_recovery_id, recorded_by_auth_user_id, recorded_by
  ) values (
    v_case.tenant_id, p_case_id, p_recovered_from, p_recovered_amount, p_currency, coalesce(p_recovered_at, now()), p_reference, p_corrects_recovery_id, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_record;

  perform app.advance_claim_case_stage(p_case_id, 'recovering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_claim_recovery',
    'app.claim_recovery_records', v_record.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'recovered_from', p_recovered_from, 'recovered_amount', p_recovered_amount, 'corrects_recovery_id', p_corrects_recovery_id)
  );

  return v_record;
end;
$$;

-- ===========================================================================
-- 9. Finance settlement-readiness RPCs (design point 7).
-- ===========================================================================

create function app.evaluate_claim_settlement_readiness(
  p_case_id uuid,
  p_reevaluation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_settlement_readiness_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_existing app.claim_settlement_readiness_evaluations;
  v_has_existing boolean;
  v_blockers jsonb := '[]'::jsonb;
  v_item_count integer;
  v_review app.claim_responsibility_reviews;
  v_recovery_count integer;
  v_evaluated_status text;
  v_evidence jsonb;
  v_new app.claim_settlement_readiness_evaluations;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed and cannot be re-evaluated for settlement readiness', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  v_has_existing := found;
  if v_has_existing and (p_reevaluation_reason is null or length(trim(p_reevaluation_reason)) = 0) then
    raise exception 'claim_settlement_reevaluation_reason_required: a non-empty reason is required to reevaluate a claim case that already has a current settlement-readiness evaluation'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_item_count from app.claim_items where claim_case_id = p_case_id and status = 'active';
  if v_item_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_claim_items'));
  end if;

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found or v_review.status = 'proposed' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_approved_responsibility_decision'));
  elsif v_review.status = 'denied' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_finalized_reserve', 'reviewStatus', 'denied'));
  elsif v_review.status in ('approved', 'amended') then
    if v_review.final_reserve_amount is null then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_finalized_reserve', 'reviewStatus', v_review.status));
    elsif v_review.final_responsibility_party is distinct from 'internal' and v_review.final_reserve_amount > 0 then
      select count(*) into v_recovery_count from app.claim_recovery_records where claim_case_id = p_case_id;
      if v_recovery_count = 0 then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_recovery_records_yet', 'finalResponsibilityParty', v_review.final_responsibility_party));
      end if;
    end if;
  end if;

  v_evaluated_status := case when jsonb_array_length(v_blockers) = 0 then 'ready' else 'not_ready' end;
  v_evidence := jsonb_build_object(
    'claimItemCount', v_item_count,
    'currentReviewId', v_review.id,
    'currentReviewStatus', v_review.status,
    'finalResponsibilityParty', v_review.final_responsibility_party,
    'finalReserveAmount', v_review.final_reserve_amount
  );

  if v_has_existing then
    update app.claim_settlement_readiness_evaluations set is_current = false where id = v_existing.id;
  end if;

  insert into app.claim_settlement_readiness_evaluations (
    tenant_id, claim_case_id, version_number, evaluated_status, blockers, evidence,
    reevaluation_reason, supersedes_evaluation_id, evaluated_by_auth_user_id, evaluated_by, created_by
  ) values (
    v_case.tenant_id, p_case_id, coalesce(v_existing.version_number, 0) + 1, v_evaluated_status, v_blockers, v_evidence,
    p_reevaluation_reason, v_existing.id, p_actor_auth_user_id, p_actor_label, p_actor_label
  )
  returning * into v_new;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_claim_settlement_readiness',
    'app.claim_settlement_readiness_evaluations', v_new.id, 'success', p_reevaluation_reason, null,
    jsonb_build_object('evaluated_status', v_new.evaluated_status, 'blockers', v_new.blockers)
  );

  return v_new;
end;
$$;

comment on function app.evaluate_claim_settlement_readiness is
  'ATW-025: the one evidence-reading, versioning entry point (mirrors app.evaluate_billing_readiness, OPS-181). Real computed blockers only -- no_claim_items, no_approved_responsibility_decision, no_finalized_reserve, no_recovery_records_yet (fires only when the current decision names a non-internal responsible party with a positive finalized reserve and zero recovery records exist yet). Posts nothing to any Finance ledger.';

create function app.handoff_claim_settlement_readiness(
  p_case_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_settlement_readiness_handoffs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_current app.claim_settlement_readiness_evaluations;
  v_handoff app.claim_settlement_readiness_handoffs;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to hand off claim settlement readiness' using errcode = 'check_violation';
  end if;

  select * into v_current from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_settlement_not_evaluated: claim case % has never had a settlement-readiness evaluation', p_case_id using errcode = 'no_data_found';
  end if;
  if v_current.evaluated_status <> 'ready' then
    raise exception 'claim_settlement_not_ready: claim case % is not ready for Finance settlement handoff', p_case_id using errcode = 'check_violation';
  end if;

  begin
    insert into app.claim_settlement_readiness_handoffs (
      tenant_id, claim_case_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by
    ) values (
      v_case.tenant_id, p_case_id, v_current.id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_handoff from app.claim_settlement_readiness_handoffs
      where tenant_id = v_case.tenant_id and claim_case_id = p_case_id and idempotency_key = p_idempotency_key;
      return v_handoff;
  end;

  perform app.advance_claim_case_stage(p_case_id, 'finance_handoff');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_claim_settlement_readiness',
    'app.claim_settlement_readiness_handoffs', v_handoff.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evaluation_id', v_current.id, 'idempotency_key', p_idempotency_key)
  );

  return v_handoff;
end;
$$;

comment on function app.handoff_claim_settlement_readiness is
  'ATW-025: idempotent on (tenant_id, claim_case_id, idempotency_key) -- a genuine retry with the same key returns the exact same handoff row, never a duplicate. Requires the current evaluation''s evaluated_status=ready. Zero writes to any Finance-schema table.';

-- app.record_claim_finance_reconciliation_outcome -- service_role ONLY, mirrors
-- app.record_warehouse_billing_reconciliation_outcome exactly (ATW-022).
create function app.record_claim_finance_reconciliation_outcome(
  p_handoff_id uuid,
  p_status text,
  p_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_settlement_readiness_handoffs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.claim_settlement_readiness_handoffs;
begin
  if p_actor_label is null or length(trim(p_actor_label)) = 0 then
    raise exception 'invalid_actor_label: an actor label is required to record a reconciliation outcome' using errcode = 'check_violation';
  end if;
  if p_status not in ('reconciled', 'rejected') then
    raise exception 'invalid_status: % is not a recognized reconciliation outcome', p_status using errcode = 'check_violation';
  end if;
  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'invalid_note: a non-empty reconciliation note is required' using errcode = 'check_violation';
  end if;

  select * into v_handoff from app.claim_settlement_readiness_handoffs where id = p_handoff_id for update;
  if not found then
    raise exception 'claim_settlement_handoff_not_found: %', p_handoff_id using errcode = 'no_data_found';
  end if;

  if v_handoff.reconciliation_status is not null then
    if v_handoff.reconciliation_status = p_status then
      return v_handoff;
    end if;
    raise exception 'reconciliation_outcome_conflict: handoff % already has reconciliation_status % and cannot be changed to %', p_handoff_id, v_handoff.reconciliation_status, p_status
      using errcode = 'check_violation';
  end if;

  update app.claim_settlement_readiness_handoffs set
    reconciliation_status = p_status, reconciliation_note = p_note, reconciled_at = now(), updated_at = now()
  where id = p_handoff_id
  returning * into v_handoff;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_claim_finance_reconciliation_outcome',
    'app.claim_settlement_readiness_handoffs', v_handoff.id, 'success', p_note, null, jsonb_build_object('reconciliation_status', p_status)
  );

  return v_handoff;
end;
$$;

comment on function app.record_claim_finance_reconciliation_outcome is
  'ATW-025: service_role ONLY, no authenticated grant at all -- a Finance-side worker callback, mirroring app.record_warehouse_billing_reconciliation_outcome''s exact precedent (ATW-022): a real, callable interface with nothing calling it yet, since no live Finance consumer exists in this repository. Idempotent on a same-outcome replay; rejects a conflicting second outcome.';

-- ===========================================================================
-- 10. Closure/reopen (design point 8).
-- ===========================================================================

create function app.close_claim_case(
  p_case_id uuid,
  p_expected_version integer,
  p_exception_expected_version integer,
  p_closure_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_case_extensions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_latest_handoff app.claim_settlement_readiness_handoffs;
  v_review app.claim_responsibility_reviews;
  v_closure_basis text;
  v_exception app.operational_exceptions;
  v_resolved app.operational_exceptions;
  v_updated app.claim_case_extensions;
begin
  if p_closure_note is null or length(trim(p_closure_note)) = 0 then
    raise exception 'claim_closure_note_required: a non-empty closure_note is required to close a claim case' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_already_closed: claim case % is already closed', p_case_id using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  -- Exact closure gate (disclosed precisely in the migration header, design point 8).
  -- Ordered by handoff_seq (a real identity column), never handed_off_at -- see
  -- app.claim_settlement_readiness_handoffs' own comment for why.
  select * into v_latest_handoff from app.claim_settlement_readiness_handoffs where claim_case_id = p_case_id order by handoff_seq desc limit 1;
  if found and v_latest_handoff.reconciliation_status = 'reconciled' then
    v_closure_basis := 'finance_reconciled';
  else
    select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
    if found and (v_review.status = 'denied' or (v_review.status in ('approved', 'amended') and coalesce(v_review.final_reserve_amount, 0) = 0)) then
      v_closure_basis := 'no_handoff_required';
    else
      raise exception 'claim_case_not_reconciled: claim case % is not yet finance-reconciled and does not qualify for the no-handoff-required closure path (a decided denial or a zero-reserve decision) -- hand off to Finance and obtain a reconciled outcome, or decide/deny the claim, before closing', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Drive the underlying app.operational_exceptions row through ITS OWN real
  -- resolve/close RPCs -- never a direct table write (see migration header).
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;
  if v_exception.status in ('open', 'acknowledged', 'reopened') then
    v_resolved := app.resolve_exception(v_exception.id, p_exception_expected_version, p_closure_note, p_actor_auth_user_id, p_actor_label);
    perform app.close_exception(v_resolved.id, v_resolved.record_version, p_actor_auth_user_id, p_actor_label);
  elsif v_exception.status = 'resolved' then
    perform app.close_exception(v_exception.id, p_exception_expected_version, p_actor_auth_user_id, p_actor_label);
  end if;
  -- status = 'closed' already -- no-op, its own closure precondition already holds.

  update app.claim_case_extensions
  set claim_stage = 'closed', closure_basis = v_closure_basis, closure_note = p_closure_note, closed_at = now(), closed_by = p_actor_label
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_closure_note, null,
    jsonb_build_object('closure_basis', v_closure_basis)
  );

  return v_updated;
end;
$$;

comment on function app.close_claim_case is
  'ATW-025: closure gate (disclosed in full in the migration header) -- the case''s own most recent Finance handoff must be reconciled (closure_basis=finance_reconciled), OR the current responsibility decision must be denied or an approved/amended decision with a null-or-zero final_reserve_amount (closure_basis=no_handoff_required), else claim_case_not_reconciled. Drives the underlying app.operational_exceptions row through its own real app.resolve_exception/app.close_exception RPCs -- never a direct table write, never bypassing their own validation.';

create function app.reopen_claim_case(
  p_case_id uuid,
  p_expected_version integer,
  p_exception_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.claim_case_extensions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_updated app.claim_case_extensions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening a claim case requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage <> 'closed' then
    raise exception 'invalid_transition: claim case % is % and cannot be reopened', p_case_id, v_case.claim_stage using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  -- Mirrors app.reopen_exception''s own actual OPS:Edit precedent exactly (not the
  -- registered-but-unused OPS:Reopen action -- see migration header) so the claim
  -- extension and the base exception it wraps share the same authorization tier.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  perform app.reopen_exception(v_case.operational_exception_id, p_exception_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);

  update app.claim_case_extensions
  set claim_stage = 'investigating', reopened_at = now(), reopened_by = p_actor_label, reopen_reason = p_reason
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_reason, null, null
  );

  return v_updated;
end;
$$;

comment on function app.reopen_claim_case is
  'ATW-025: closed -> investigating only, mandatory reason. Drives app.reopen_exception for real on the underlying operational_exceptions row. closure_note/closure_basis/closed_at/closed_by are left untouched -- full history preserved, never overwritten, exactly mirroring app.reopen_exception''s own "resolution never deletes the underlying evidence" precedent.';

-- ===========================================================================
-- 11. Field-masking helpers for money-bearing reads (design point 9). Internal
--     only, no grant (called only from inside this migration''s own SECURITY
--     DEFINER read RPCs -- mirrors app.mask_warehouse_billing_event_amounts, ATW-022).
-- ===========================================================================

create function app.mask_claim_item_amounts(p_item app.claim_items, p_masked boolean)
returns app.claim_items
language plpgsql
immutable
as $$
declare
  v_item app.claim_items := p_item;
begin
  if p_masked then
    v_item.declared_value := null;
    v_item.currency := null;
  end if;
  return v_item;
end;
$$;

create function app.mask_claim_responsibility_review_amounts(p_review app.claim_responsibility_reviews, p_masked boolean)
returns app.claim_responsibility_reviews
language plpgsql
immutable
as $$
declare
  v_review app.claim_responsibility_reviews := p_review;
begin
  if p_masked then
    v_review.proposed_reserve_amount := null;
    v_review.proposed_currency := null;
    v_review.proposed_rationale := null;
    v_review.final_reserve_amount := null;
    v_review.final_currency := null;
    v_review.decision_notes := null;
  end if;
  return v_review;
end;
$$;

create function app.mask_claim_recovery_record_amounts(p_record app.claim_recovery_records, p_masked boolean)
returns app.claim_recovery_records
language plpgsql
immutable
as $$
declare
  v_record app.claim_recovery_records := p_record;
begin
  if p_masked then
    v_record.recovered_amount := null;
    v_record.currency := null;
  end if;
  return v_record;
end;
$$;

-- Added on adversarial review (see migration header design note 7): app.
-- evaluate_claim_settlement_readiness writes the SAME reserve amount app.
-- mask_claim_responsibility_review_amounts already masks elsewhere into this
-- table's own evidence jsonb column -- strips only the 'finalReserveAmount' key
-- (never the whole object) so claimItemCount/currentReviewId/
-- currentReviewStatus/finalResponsibilityParty (non-financial, useful to an
-- OPS:View-only reader) remain visible, mirroring this migration's own
-- selective-column masking philosophy exactly.
create function app.mask_claim_settlement_readiness_evaluation_amounts(p_evaluation app.claim_settlement_readiness_evaluations, p_masked boolean)
returns app.claim_settlement_readiness_evaluations
language plpgsql
immutable
as $$
declare
  v_evaluation app.claim_settlement_readiness_evaluations := p_evaluation;
begin
  if p_masked then
    v_evaluation.evidence := v_evaluation.evidence - 'finalReserveAmount';
  end if;
  return v_evaluation;
end;
$$;

-- ===========================================================================
-- 12. Read RPCs (design point 9). Selective columns via the row-typed masking
--     helpers above -- never SELECT *. All OPS:View-gated + record-scoped via
--     app.claim_case_record_scope_ok.
-- ===========================================================================

create function app.get_claim_case(p_case_id uuid, p_actor_auth_user_id uuid)
returns app.claim_case_extensions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  return v_case;
end;
$$;

-- Bounded, cursor-paginated (never OFFSET -- the real ATW-023 (p_cursor_updated_at,
-- p_cursor_id) convention). Filters are a disclosed superset of the brief's own
-- "tenant/status/severity/shipment" wording -- see migration header design note 9.
create function app.list_claim_cases(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_claim_stage_filter text default null,
  p_exception_type_filter text default null,
  p_exception_severity_filter text default null,
  p_exception_status_filter text default null,
  p_shipment_order_id_filter uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  operational_exception_id uuid,
  claimant_type text,
  claimant_account_id uuid,
  claimant_label text,
  claim_stage text,
  opened_by text,
  opened_at timestamptz,
  closure_basis text,
  closed_at timestamptz,
  record_version integer,
  updated_at timestamptz,
  exception_type text,
  exception_severity text,
  exception_status text,
  shipment_order_id uuid
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    cce.id, cce.tenant_id, cce.operational_exception_id, cce.claimant_type, cce.claimant_account_id, cce.claimant_label,
    cce.claim_stage, cce.opened_by, cce.opened_at, cce.closure_basis, cce.closed_at, cce.record_version, cce.updated_at,
    oe.type, oe.severity, oe.status, oe.shipment_order_id
  from app.claim_case_extensions cce
  join app.operational_exceptions oe on oe.id = cce.operational_exception_id
  where cce.tenant_id = p_tenant_id
    and (p_claim_stage_filter is null or cce.claim_stage = p_claim_stage_filter)
    and (p_exception_type_filter is null or oe.type = p_exception_type_filter)
    and (p_exception_severity_filter is null or oe.severity = p_exception_severity_filter)
    and (p_exception_status_filter is null or oe.status = p_exception_status_filter)
    and (p_shipment_order_id_filter is null or oe.shipment_order_id = p_shipment_order_id_filter)
    and app.claim_case_record_scope_ok(p_actor_auth_user_id, cce.tenant_id, cce.operational_exception_id)
    and (p_cursor_id is null or (cce.updated_at, cce.id) < (p_cursor_updated_at, p_cursor_id))
  order by cce.updated_at desc, cce.id desc
  limit v_limit;
end;
$$;

create function app.list_claim_items(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.claim_items
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select (app.mask_claim_item_amounts(i, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id))).*
  from app.claim_items i
  where i.claim_case_id = p_case_id
  order by i.created_at desc
  limit v_limit;
end;
$$;

create function app.list_claim_evidence(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.claim_evidence_links
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.claim_evidence_links where claim_case_id = p_case_id order by added_at desc limit v_limit;
end;
$$;

create function app.get_claim_investigation_history(p_case_id uuid, p_actor_auth_user_id uuid)
returns setof app.claim_investigation_findings
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.claim_investigation_findings where claim_case_id = p_case_id order by created_at asc;
end;
$$;

create function app.get_claim_responsibility_review(p_case_id uuid, p_actor_auth_user_id uuid)
returns app.claim_responsibility_reviews
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_review app.claim_responsibility_reviews;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_responsibility_review_not_found: claim case % has no responsibility review yet', p_case_id using errcode = 'no_data_found';
  end if;

  return app.mask_claim_responsibility_review_amounts(v_review, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id));
end;
$$;

create function app.list_claim_recovery_records(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.claim_recovery_records
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select (app.mask_claim_recovery_record_amounts(r, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id))).*
  from app.claim_recovery_records r
  where r.claim_case_id = p_case_id
  order by r.recovered_at desc
  limit v_limit;
end;
$$;

-- Added on adversarial review (see migration header design note 7): app.
-- claim_settlement_readiness_evaluations/_handoffs previously had NO dedicated
-- read RPC -- their only access path was the raw RLS-scoped SELECT every one of
-- this migration's 8 tables carries as defense in depth, with no OPS:View gate and
-- (for the evaluation's own embedded reserve amount) no cost masking, bypassing
-- the exact masking app.mask_claim_responsibility_review_amounts already enforces
-- elsewhere in this same migration for the identical dollar figure. Both mirror
-- ATW-022's own app.get_warehouse_billing_event/app.list_warehouse_billing_handoffs
-- precedent.
create function app.get_claim_settlement_readiness(p_case_id uuid, p_actor_auth_user_id uuid)
returns app.claim_settlement_readiness_evaluations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_evaluation app.claim_settlement_readiness_evaluations;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_evaluation from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_settlement_not_evaluated: claim case % has never had a settlement-readiness evaluation', p_case_id using errcode = 'no_data_found';
  end if;

  return app.mask_claim_settlement_readiness_evaluation_amounts(v_evaluation, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id));
end;
$$;

comment on function app.get_claim_settlement_readiness is
  'ATW-025: OPS:View + record-scope. Returns the CURRENT settlement-readiness evaluation only. evidence->>''finalReserveAmount'' is masked (key removed) for a caller lacking OPS:View cost -- see app.mask_claim_settlement_readiness_evaluation_amounts.';

create function app.list_claim_settlement_readiness_handoffs(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.claim_settlement_readiness_handoffs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.claim_settlement_readiness_handoffs where claim_case_id = p_case_id order by handoff_seq desc limit v_limit;
end;
$$;

comment on function app.list_claim_settlement_readiness_handoffs is
  'ATW-025: OPS:View + record-scope. Bounded (default 50, hard-capped 200), ordered by handoff_seq desc (the same authoritative "most recent handoff" ordering app.close_claim_case itself relies on, never handed_off_at). Carries no dollar amount of its own (evaluation_id/idempotency_key/reconciliation_status/note only) -- no masking helper needed.';

-- ===========================================================================
-- 13. RLS. Every policy shares app.claim_case_record_scope_ok.
-- ===========================================================================

alter table app.claim_case_extensions enable row level security;
alter table app.claim_items enable row level security;
alter table app.claim_evidence_links enable row level security;
alter table app.claim_investigation_findings enable row level security;
alter table app.claim_responsibility_reviews enable row level security;
alter table app.claim_recovery_records enable row level security;
alter table app.claim_settlement_readiness_evaluations enable row level security;
alter table app.claim_settlement_readiness_handoffs enable row level security;

create policy claim_case_extensions_select_scoped on app.claim_case_extensions
  for select to authenticated
  using (app.claim_case_record_scope_ok((select auth.uid()), tenant_id, operational_exception_id));

create policy claim_items_select_scoped on app.claim_items
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_items.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_evidence_links_select_scoped on app.claim_evidence_links
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_evidence_links.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_investigation_findings_select_scoped on app.claim_investigation_findings
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_investigation_findings.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_responsibility_reviews_select_scoped on app.claim_responsibility_reviews
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_responsibility_reviews.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_recovery_records_select_scoped on app.claim_recovery_records
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_recovery_records.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_settlement_readiness_evaluations_select_scoped on app.claim_settlement_readiness_evaluations
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_settlement_readiness_evaluations.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

create policy claim_settlement_readiness_handoffs_select_scoped on app.claim_settlement_readiness_handoffs
  for select to authenticated
  using (
    exists (
      select 1 from app.claim_case_extensions cce
      where cce.id = claim_settlement_readiness_handoffs.claim_case_id
        and app.claim_case_record_scope_ok((select auth.uid()), cce.tenant_id, cce.operational_exception_id)
    )
  );

-- ===========================================================================
-- 14. Grants. Per ERR-2026-004: explicit, directly-provable revoke of
--     PostgreSQL's PUBLIC-execute default, standalone, before any role-specific
--     grant.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on
  app.claim_case_extensions, app.claim_items, app.claim_evidence_links, app.claim_investigation_findings,
  app.claim_responsibility_reviews, app.claim_recovery_records, app.claim_settlement_readiness_evaluations, app.claim_settlement_readiness_handoffs
  to authenticated, service_role;
grant insert, update, delete on
  app.claim_case_extensions, app.claim_items, app.claim_evidence_links, app.claim_investigation_findings,
  app.claim_responsibility_reviews, app.claim_recovery_records, app.claim_settlement_readiness_evaluations, app.claim_settlement_readiness_handoffs
  to service_role;

-- Internal validation helper used inside a table CHECK constraint -- only a raw
-- service_role insert/update reaches it outside a SECURITY DEFINER RPC's own
-- owner-implicit rights (mirrors app.validate_warehouse_billing_tier_schedule's
-- own service_role-only posture, ATW-022).
grant execute on function app.validate_claim_contact_snapshot(jsonb) to service_role;

grant execute on function app.claim_case_record_scope_ok(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.open_claim_case(uuid, text, uuid, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.add_claim_item(uuid, text, uuid, uuid, uuid, numeric, text, numeric, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_claim_item(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.link_claim_evidence(uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_claim_investigation_finding(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.propose_claim_responsibility(uuid, text, numeric, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_claim_responsibility(uuid, integer, text, text, numeric, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_claim_recovery(uuid, text, numeric, text, timestamptz, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_claim_settlement_readiness(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.handoff_claim_settlement_readiness(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.close_claim_case(uuid, integer, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_claim_case(uuid, integer, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_claim_case(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_claim_cases(uuid, uuid, text, text, text, text, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_claim_items(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.list_claim_evidence(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_claim_investigation_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_claim_responsibility_review(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_claim_recovery_records(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_claim_settlement_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_claim_settlement_readiness_handoffs(uuid, uuid, integer) to authenticated, service_role;

-- service_role ONLY -- no authenticated grant at all (a Finance-side worker callback).
grant execute on function app.record_claim_finance_reconciliation_outcome(uuid, text, text, uuid, text) to service_role;
