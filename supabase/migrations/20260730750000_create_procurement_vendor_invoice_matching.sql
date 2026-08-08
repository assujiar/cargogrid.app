-- Procurement capability PRC-265 (Vendor Invoice Matching, CG-S11-PRC-016).
-- Extends the canonical Phase 4 vendor bill (app.finance_vendor_bills, FIN-200) with a
-- Procurement-owned match-case workflow: configurable line-level matching against
-- PO/contract/actual-cost/rate/tax evidence, tolerance-based auto-clear,
-- duplicate-invoice-fingerprint detection, dispute and exception-approval workflow, and
-- a read-only readiness handoff back to Finance -- WITHOUT a second AP/bill table,
-- WITHOUT posting any journal, and WITHOUT touching Finance's own posting/payment/
-- period-lock/reversal/settlement functions (business rule 24; §16).
--
-- ===========================================================================
-- What already exists vs. what this migration adds (disclosed, not guessed)
-- ===========================================================================
--
-- `app.finance_vendor_bills`/`app.finance_vendor_bill_lines` (FIN-200,
-- 20260729140000_create_finance_vendor_bill.sql) already carry a BOUNDED, HEADER-LEVEL
-- match: `prepare_finance_vendor_bill_from_actual_cost` sums the vendor's own approved
-- `app.shipment_actual_cost_components` (OPS-178) verbatim into `subtotal_amount`, and
-- an OPTIONAL `vendor_stated_amount` (a human-read figure off the vendor's own paper/
-- PDF bill) is compared against that subtotal at HEADER granularity only, with a fixed
-- 1.00-minor-unit tolerance and a non-blocking `variance_status` disclosed to the
-- approver. Prompt 200's own migration header explicitly named this a bounded MVP and
-- named "PO/contract/three-way and vendor lifecycle depth" as Step 11 scope -- i.e.
-- THIS prompt.
--
-- The critical, load-bearing consequence: because `finance_vendor_bill_lines.amount`
-- is auto-derived FROM the actual-cost component (never independently vendor-typed),
-- there is NO existing column anywhere that records what the vendor's own real invoice
-- states at LINE granularity -- only the header-level `vendor_stated_amount`. This
-- migration's own `app.vendor_bill_match_lines` is where that real, independent capture
-- finally happens (`vendor_stated_quantity`/`_uom`/`_rate`/`_amount`, one row per bill
-- line, staff-transcribed off the vendor's own document -- the same "internal capture,
-- no vendor portal" pattern every other Phase 6 vendor-facing surface already uses,
-- Prompt 200 §16's own disclosed "AI/OCR extraction assistance... not built by this
-- migration" boundary carried forward unchanged). This is genuinely NEW evidence this
-- capability owns -- never a duplicate of AP truth, which remains
-- `finance_vendor_bills.subtotal_amount`/`total_amount`/`status`, completely untouched
-- by every function in this migration (zero INSERT/UPDATE/DELETE anywhere in this file
-- touches any `app.finance_*` table -- confirmed by direct grep before commit).
--
-- ===========================================================================
-- Evidence sources, and how each is actually used (§13)
-- ===========================================================================
--
-- * **Actual cost (primary, always available when the bill line has one).**
--   `app.finance_vendor_bill_lines.source_component_id` already links every cost line
--   to its `app.shipment_actual_cost_components` row (OPS-178) -- quantity/uom/rate/
--   amount/currency read directly from there, never re-typed.
-- * **PO (`app.purchase_orders`/`app.purchase_order_lines`, PRC-260), optional.**
--   No structural FK exists anywhere from a shipment or an actual cost to a PO (POs
--   track fulfillment via a descriptive `fulfillment_reference`, by PRC-260's own
--   disclosed design, never a live join target) -- so a PO is explicitly, manually
--   attached by the caller (`p_purchase_order_id` at case-create time,
--   `p_po_line_id` at per-line map time), then RE-VALIDATED (tenant/vendor/status/
--   currency), never trusted blindly. PRC-260's own migration header already disclosed
--   `app.purchase_order_lines` carries NO per-line unit price (a bounded, disclosed
--   PRC-260 scope boundary this migration inherits, not reintroduces) -- so PO evidence
--   contributes QUANTITY/UOM at line grain and TOTAL AMOUNT at header (case) grain only,
--   never a per-line PO rate. Disclosed again in §9 of the build log, not silently
--   worked around.
-- * **Vendor contract (`app.vendor_contracts`/`app.resolve_effective_vendor_contract`,
--   PRC-261), optional, auto-resolved.** Read at case-evaluate time (never cached
--   across evaluations) via the one deterministic resolution point PRC-261 built
--   explicitly for this prompt to consume -- snapshot-only (`vendor_contract_id`,
--   version_no), used to select `match_mode` and, when the contract carries a
--   `rate_version_id`, as the rate-evidence source below.
-- * **Rate (`app.vendor_rate_versions`/`app.vendor_rate_tiers`, COM-149/PRC-255),
--   best-effort, optional.** `app.calculate_vendor_rate` (PRC-255) is invoked ONLY when
--   a match line is explicitly mapped to a `rate_version_id` AND carries a known
--   evidence quantity -- populates `contracted_rate_amount` as an informational
--   cross-check, never a blocking requirement (many lines legitimately have no
--   weight/volume-tiered rate to compare against). Wrapped so a tier-resolution failure
--   never blocks the rest of the evaluation (§4 Tier B walk explains why).
-- * **Tax.** Deliberately NOT a second tax-recomputation path. A bill's own tax LINE
--   (`finance_vendor_bill_lines.line_type = 'tax'`, already FIN-200/FIN-195-computed
--   via `app.calculate_finance_tax`) is matched through the exact SAME generic
--   per-line engine as a cost line, just scored against `tax_tolerance_pct` instead of
--   `rate_tolerance_pct` -- one engine, two tolerance dimensions, never a duplicate tax
--   engine.
-- * **Service receipt / ePOD.** No dedicated "service receipt" table exists anywhere in
--   this repository (confirmed by direct schema search) -- `app.epod_captures`
--   (OPS-177, completion evidence) and `app.milestone_events` (OPS-173, pickup/
--   delivery-category events) are the real fulfillment-evidence tables. Read-only, at
--   case-evaluate time: `has_epod_evidence`/`has_delivery_milestone_evidence` on the
--   case row record whether the underlying shipment (via
--   `app.shipment_actual_cost_components.assignment_id` ->
--   `app.resource_assignments.shipment_order_id`, when resolvable) has a `completed`
--   ePOD and/or a delivery-category milestone event -- a real, disclosed "was the
--   service actually rendered" signal alongside quantity/rate matching, never a second
--   milestone/tracking projection.
--
-- ===========================================================================
-- Tolerance policy and auto-clear (business rule: "Within-tolerance auto-clear may be
-- configured only after human-approved policy")
-- ===========================================================================
--
-- `app.vendor_bill_match_tolerance_policies` is a tenant-wide, versioned governance
-- object (draft -> active -> archived, at most one active row per tenant, mirroring
-- `app.publish_vendor_kpi_definition`'s own supersede-on-publish shape). `auto_clear_
-- enabled` is the explicit human decision gate: a case whose every line and header
-- check falls within the active policy's own percentage/absolute tolerances is set
-- `matched`/`ready_for_finance` automatically ONLY when the active policy has this bit
-- set; otherwise it stays `pending`, requiring an explicit human
-- `accept_vendor_bill_match_within_tolerance` call. When NO policy is active at all,
-- the case uses a hardcoded zero-tolerance, `auto_clear_enabled=false` default (any
-- variance at all routes to exception; nothing auto-clears) -- disclosed on the case row
-- itself via a null `tolerance_policy_id`, never silently treated as "always pass."
--
-- ===========================================================================
-- Currency (taxonomy C-22) -- never compared across currencies, ever
-- ===========================================================================
--
-- Every evidence source's own currency is validated against the bill's own currency
-- (the case's `currency` column, a direct snapshot of `finance_vendor_bills.currency`,
-- never re-derived) BEFORE any numeric variance is computed. A PO whose currency
-- differs is rejected outright at attach time (`po_currency_mismatch`, hard block, not
-- a flag -- currency is a structural precondition, not a tolerance dimension). A line
-- whose actual-cost-component currency differs is flagged `currency_mismatch = true`,
-- its variance fields left NULL (never computed against a mismatched-currency amount),
-- and the case is forced to `exception` regardless of the active policy's own
-- percentages -- this repository has no FX-conversion decision for this comparison
-- (the same unresolved architectural question `ISS-2026-045`/PRC-264's own
-- `rate_competitiveness` fix already declined to make unilaterally), so a currency
-- mismatch is always routed to a human, never silently converted or silently ignored.
--
-- ===========================================================================
-- Duplicate-invoice-fingerprint detection (business rule: "Block duplicate invoice/
-- fingerprint")
-- ===========================================================================
--
-- `finance_vendor_bills` already structurally blocks an EXACT duplicate
-- `vendor_reference` for the same vendor (`finance_vendor_bills_tenant_vendor_
-- reference_unique`) -- this migration's own fingerprint exists to catch the NEAR
-- duplicate a data-entry variant would slip past: the SAME vendor, SAME currency, SAME
-- total amount, submitted again within the active policy's own `duplicate_window_days`,
-- REGARDLESS of reference text (a blank, corrected, or reformatted reference). A flagged
-- case is forced to `exception` (never silently auto-cleared, matching the
-- currency-mismatch treatment above) and requires a human decision through the SAME
-- exception-approval workflow every other over-tolerance case uses -- "system
-- recommends, human decides," the identical governance style PRC-264's own lifecycle
-- recommendation surface already established, not a novel mechanism.
--
-- ===========================================================================
-- Lock order (taxonomy C-04/C-21), stated once and followed by every function below
-- ===========================================================================
--
-- `app.vendor_bill_match_cases` (the parent) is ALWAYS locked `for update` before any
-- child-table row (`vendor_bill_match_lines`/`_disputes`/`_exception_approvals`) in the
-- same transaction. `app.map_vendor_bill_match_line`, `app.resolve_vendor_bill_match_
-- dispute`, and `app.decide_vendor_bill_match_exception_approval` are the three
-- functions that touch both a case and one of its own child rows -- each first performs
-- an UNLOCKED existence read of the child row (needed only to resolve its own owning
-- `match_case_id`; nothing is decided from that unlocked read), THEN locks the parent
-- case row, THEN re-reads/locks the child row `for update` under that lock and makes
-- every real decision from that second, locked read -- mirroring PRC-256's own
-- established "peek unlocked to find the parent, then lock parent-first" shape for the
-- identical structural reason (the child's own id is required to find its parent, but
-- the parent must still be locked first). No two functions in this migration disagree
-- on this order, so no new C-21-shaped deadlock is possible within this file.
-- `create_vendor_bill_match_case` takes no lock (a brand-new row; a genuine concurrent
-- double-create is caught by `vendor_bill_match_cases_one_current_idx` and translated
-- from a raw `unique_violation` into a typed `match_case_already_exists`, mirroring
-- `app.raise_vendor_kpi_source_dispute`'s own identical nested-exception shape, C-02
-- safe since the pre-check's own raise and this recovery block are different call
-- sites). `re_evaluate_vendor_bill_match_case`/`accept_vendor_bill_match_within_
-- tolerance`/`cancel_vendor_bill_match_case` lock exactly the one case row they act on.
--
-- ===========================================================================
-- Finance-only posting boundary, and readiness as read-only exposure
-- ===========================================================================
--
-- No function in this migration writes to `app.finance_vendor_bills`,
-- `app.finance_vendor_bill_lines`, `app.finance_ap_open_items`, or any other
-- `app.finance_*` table -- confirmed by direct grep before commit (zero INSERT/UPDATE/
-- DELETE against any `finance_*` relation anywhere in this file). `approve_finance_
-- vendor_bill`/`post_finance_vendor_bill` (FIN-200) are NOT touched, gated, or wrapped
-- by anything here -- Finance's own approver still decides when to approve/post,
-- exactly as FIN-200's own header already discloses ("disclosed to the approver...
-- does not by itself block approval," the identical precedent this capability's own
-- `readiness_status` follows). `app.get_vendor_bill_match_readiness` is the one new,
-- real, callable read a Finance approver (or the UI) can consult before deciding --
-- gated on PRC:View OR FIN:View (either module's own viewer may read it; a genuine,
-- disclosed two-module OR-gate, not a weakening of either module's own boundary) --
-- never a hook, trigger, or gate on Finance's own posting path itself. This mirrors
-- PRC-260's own already-disclosed design note verbatim: "Invoice-match readiness is
-- read-only exposure, not a match engine."
--
-- ===========================================================================
-- Scope boundaries, disclosed rather than left implicit (C-23 discipline)
-- ===========================================================================
--
-- * No REST/GraphQL surface, no notification/job wiring -- identical reasoning to every
--   prior Phase 6 checkpoint's own disclosed boundary.
-- * No vendor-portal identity for dispute response -- staff-recorded on the vendor's own
--   behalf, the same already-accepted PRC-257/258/261/262/263/264 precedent.
-- * No AI/OCR line-item extraction -- `vendor_stated_*` fields are staff-transcribed,
--   the same Prompt 200 §16 boundary this migration inherits rather than reintroduces.
-- * No FX conversion for cross-currency evidence -- hard-blocked at PO attach, flagged
--   and routed to a human at line level, the same unresolved architectural question
--   `ISS-2026-045` already declined to decide unilaterally for a different entity type.
-- * No integration with Finance's own generic reconciliation engine (`FIN-207`,
--   `app.finance_reconciliations`) -- `app.get_vendor_bill_match_reconciliation_status`
--   is this capability's OWN Procurement-side aggregate summary of match-case outcomes
--   (a distinct concept from FIN-207's ledger-balance reconciliation), a deliberate
--   choice to avoid touching Finance's own reconciliation schema/entity-type surface,
--   not an oversight.
-- * No automatic scheduler/job triggers re-evaluation -- `re_evaluate_vendor_bill_match_
--   case` is a real, callable, human/UI-triggered action; nothing calls it
--   automatically, the same `ISS-2026-015` boundary (no scheduler/worker runtime exists
--   anywhere in this repository) every prior capability with a recompute-shaped
--   operation has already disclosed.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
-- its final grants, the standing per-migration convention since `PLT-118`.

-- ===========================================================================
-- 1. app.vendor_bill_match_tolerance_policies
-- ===========================================================================

create table app.vendor_bill_match_tolerance_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  version_no integer not null default 1,
  status text not null default 'draft',
  name text not null,
  quantity_tolerance_pct numeric(6, 3) not null default 0,
  rate_tolerance_pct numeric(6, 3) not null default 0,
  tax_tolerance_pct numeric(6, 3) not null default 0,
  line_amount_tolerance_abs numeric(14, 2) not null default 0,
  auto_clear_enabled boolean not null default false,
  duplicate_window_days integer not null default 30,
  notes text,
  idempotency_key text not null,
  approved_by text,
  approved_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_bill_match_tolerance_policies_status_check check (status in ('draft', 'active', 'archived')),
  constraint vendor_bill_match_tolerance_policies_name_check check (length(trim(name)) > 0),
  constraint vendor_bill_match_tolerance_policies_qty_pct_check check (quantity_tolerance_pct >= 0 and quantity_tolerance_pct <= 100),
  constraint vendor_bill_match_tolerance_policies_rate_pct_check check (rate_tolerance_pct >= 0 and rate_tolerance_pct <= 100),
  constraint vendor_bill_match_tolerance_policies_tax_pct_check check (tax_tolerance_pct >= 0 and tax_tolerance_pct <= 100),
  constraint vendor_bill_match_tolerance_policies_abs_check check (line_amount_tolerance_abs >= 0),
  constraint vendor_bill_match_tolerance_policies_window_check check (duplicate_window_days > 0),
  constraint vendor_bill_match_tolerance_policies_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.vendor_bill_match_tolerance_policies is
  'PRC-265: tenant-wide, versioned tolerance policy governing auto-clear. At most one active row per tenant (vendor_bill_match_tolerance_policies_one_active_idx). auto_clear_enabled is the explicit human decision gate business rule "auto-clear only after human-approved policy" requires -- without it, every case within tolerance still requires an explicit accept_vendor_bill_match_within_tolerance call.';

create unique index vendor_bill_match_tolerance_policies_one_active_idx on app.vendor_bill_match_tolerance_policies (tenant_id) where status = 'active';
create index vendor_bill_match_tolerance_policies_tenant_status_idx on app.vendor_bill_match_tolerance_policies (tenant_id, status);

create function app.touch_vendor_bill_match_tolerance_policies_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_bill_match_tolerance_policies_touch_row
  before update on app.vendor_bill_match_tolerance_policies
  for each row
  execute function app.touch_vendor_bill_match_tolerance_policies_row();

-- ===========================================================================
-- 2. app.vendor_bill_match_cases -- root+version-collapsed, mirrors app.vendor_contracts
--    (PRC-261): version_no increments on app.re_evaluate_vendor_bill_match_case, prior
--    version's own is_current flips to false; overall_status/readiness_status are
--    mutated IN PLACE on the current version row by accept/dispute/resolve/decide,
--    mirroring vendor_contracts' own dual amend-vs-suspend shape exactly.
-- ===========================================================================

create table app.vendor_bill_match_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  bill_id uuid not null references app.finance_vendor_bills (id),
  version_no integer not null default 1,
  is_current boolean not null default true,
  vendor_master_id uuid not null references app.master_records (id),
  currency text not null,
  match_mode text not null,
  is_partial_invoice boolean not null default false,
  is_consolidated_invoice boolean not null default false,
  purchase_order_id uuid references app.purchase_orders (id),
  vendor_contract_id uuid references app.vendor_contracts (id),
  tolerance_policy_id uuid references app.vendor_bill_match_tolerance_policies (id),
  tolerance_policy_version_no integer,
  quantity_tolerance_pct_snapshot numeric(6, 3) not null default 0,
  rate_tolerance_pct_snapshot numeric(6, 3) not null default 0,
  tax_tolerance_pct_snapshot numeric(6, 3) not null default 0,
  line_amount_tolerance_abs_snapshot numeric(14, 2) not null default 0,
  auto_clear_enabled_snapshot boolean not null default false,
  total_vendor_stated_amount numeric(14, 2) not null default 0,
  total_evidence_amount numeric(14, 2) not null default 0,
  total_variance_amount numeric(14, 2) not null default 0,
  total_variance_pct numeric(9, 4),
  has_epod_evidence boolean not null default false,
  has_delivery_milestone_evidence boolean not null default false,
  duplicate_fingerprint text not null,
  is_duplicate_flagged boolean not null default false,
  duplicate_of_case_id uuid references app.vendor_bill_match_cases (id),
  overall_status text not null default 'pending',
  readiness_status text not null default 'not_ready',
  readiness_note text,
  cancel_reason text,
  evaluated_by text,
  evaluated_at timestamptz not null default now(),
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_bill_match_cases_version_check check (version_no > 0),
  constraint vendor_bill_match_cases_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint vendor_bill_match_cases_match_mode_check check (match_mode in ('po_three_way', 'contract_two_way', 'non_po')),
  constraint vendor_bill_match_cases_overall_status_check check (overall_status in ('pending', 'matched', 'exception', 'disputed', 'blocked', 'cancelled')),
  constraint vendor_bill_match_cases_readiness_status_check check (readiness_status in ('not_ready', 'ready_for_finance', 'blocked')),
  constraint vendor_bill_match_cases_variance_amount_check check (total_variance_amount >= 0),
  constraint vendor_bill_match_cases_cancel_reason_check check (overall_status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)),
  constraint vendor_bill_match_cases_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.vendor_bill_match_cases is
  'PRC-265: one match case per finance vendor bill (bill_id), root+version-collapsed like app.vendor_contracts -- vendor_bill_match_cases_one_current_idx enforces at most one is_current row per bill_id. Never a second AP/bill table -- reads app.finance_vendor_bills, writes nothing there.';

create unique index vendor_bill_match_cases_one_current_idx on app.vendor_bill_match_cases (bill_id) where is_current;
create index vendor_bill_match_cases_tenant_status_idx on app.vendor_bill_match_cases (tenant_id, overall_status);
create index vendor_bill_match_cases_tenant_readiness_idx on app.vendor_bill_match_cases (tenant_id, readiness_status);
create index vendor_bill_match_cases_tenant_vendor_idx on app.vendor_bill_match_cases (tenant_id, vendor_master_id);
create index vendor_bill_match_cases_fingerprint_idx on app.vendor_bill_match_cases (tenant_id, duplicate_fingerprint) where is_current;
create index vendor_bill_match_cases_bill_idx on app.vendor_bill_match_cases (bill_id);

create function app.touch_vendor_bill_match_cases_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_bill_match_cases_touch_row
  before update on app.vendor_bill_match_cases
  for each row
  execute function app.touch_vendor_bill_match_cases_row();

-- ===========================================================================
-- 3. app.vendor_bill_match_lines -- one row per app.finance_vendor_bill_lines row,
--    within one match case version. Never reused across versions -- re_evaluate always
--    inserts brand-new line rows against the new version_no (full lineage retained,
--    business rule "retain every source/version").
-- ===========================================================================

create table app.vendor_bill_match_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  match_case_id uuid not null references app.vendor_bill_match_cases (id),
  bill_line_id uuid not null references app.finance_vendor_bill_lines (id),
  line_no integer not null,
  line_type text not null,
  vendor_stated_quantity numeric(14, 4),
  vendor_stated_uom text,
  vendor_stated_rate numeric(14, 4),
  vendor_stated_amount numeric(14, 2) not null,
  actual_cost_component_id uuid references app.shipment_actual_cost_components (id),
  po_line_id uuid references app.purchase_order_lines (id),
  rate_version_id uuid references app.vendor_rate_versions (id),
  evidence_quantity numeric(14, 4),
  evidence_uom text,
  evidence_rate numeric(14, 4),
  evidence_amount numeric(14, 2),
  evidence_currency text,
  contracted_rate_amount numeric(14, 2),
  contracted_rate_currency text,
  currency_mismatch boolean not null default false,
  quantity_variance_pct numeric(9, 4),
  rate_variance_pct numeric(9, 4),
  amount_variance_amount numeric(14, 2),
  amount_variance_pct numeric(9, 4),
  uom_mismatch boolean not null default false,
  po_line_quantity_variance_pct numeric(9, 4),
  po_line_uom_mismatch boolean not null default false,
  line_status text not null default 'missing_evidence',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint vendor_bill_match_lines_line_no_check check (line_no > 0),
  constraint vendor_bill_match_lines_line_type_check check (line_type in ('cost', 'tax')),
  constraint vendor_bill_match_lines_vendor_stated_amount_check check (vendor_stated_amount >= 0),
  constraint vendor_bill_match_lines_status_check check (line_status in ('matched', 'variance_within_tolerance', 'variance_exception', 'missing_evidence', 'currency_mismatch')),
  constraint vendor_bill_match_lines_unique unique (match_case_id, bill_line_id)
);

comment on table app.vendor_bill_match_lines is
  'PRC-265: vendor_stated_* is the real, independently-captured line-level figure off the vendor''s own invoice document (never existed anywhere before this migration -- see the header). evidence_* is read from app.shipment_actual_cost_components (primary) at case-evaluate time; po_line_id/rate_version_id are optional manual overrides set via app.map_vendor_bill_match_line, re-validated (tenant/vendor scope) before linking, never trusted blindly.';

create index vendor_bill_match_lines_case_idx on app.vendor_bill_match_lines (match_case_id);
create index vendor_bill_match_lines_tenant_idx on app.vendor_bill_match_lines (tenant_id);

create function app.touch_vendor_bill_match_lines_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_bill_match_lines_touch_row
  before update on app.vendor_bill_match_lines
  for each row
  execute function app.touch_vendor_bill_match_lines_row();

-- ===========================================================================
-- 4. app.vendor_bill_match_disputes -- staff-recorded on the vendor's own behalf (no
--    vendor-portal identity exists anywhere in this repository, the same already-
--    accepted PRC-257/258/261/262/263/264 precedent).
-- ===========================================================================

create table app.vendor_bill_match_disputes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  match_case_id uuid not null references app.vendor_bill_match_cases (id),
  match_line_id uuid references app.vendor_bill_match_lines (id),
  reason text not null,
  disputed_amount numeric(14, 2),
  status text not null default 'open',
  raised_by_auth_user_id uuid not null,
  raised_by text,
  vendor_response text,
  vendor_response_at timestamptz,
  vendor_response_file_id uuid references app.files (id),
  resolved_by_auth_user_id uuid,
  resolution_note text,
  resolved_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_bill_match_disputes_reason_check check (length(trim(reason)) > 0),
  constraint vendor_bill_match_disputes_status_check check (status in ('open', 'upheld', 'rejected', 'withdrawn')),
  constraint vendor_bill_match_disputes_disputed_amount_check check (disputed_amount is null or disputed_amount >= 0),
  constraint vendor_bill_match_disputes_resolution_check check (status = 'open' or (resolution_note is not null and length(trim(resolution_note)) > 0))
);

comment on table app.vendor_bill_match_disputes is
  'PRC-265: a dispute against a match case''s own variance determination (distinct concept from app.vendor_kpi_source_disputes, which disputes a KPI SCORE''s use of a source -- this table disputes whether the MATCH itself is correct). At most one open dispute per (match_case_id, match_line_id) via vendor_bill_match_disputes_one_open_idx.';

create unique index vendor_bill_match_disputes_one_open_idx on app.vendor_bill_match_disputes (match_case_id, coalesce(match_line_id, '00000000-0000-0000-0000-000000000000'::uuid)) where status = 'open';
create index vendor_bill_match_disputes_case_idx on app.vendor_bill_match_disputes (match_case_id);
create index vendor_bill_match_disputes_tenant_status_idx on app.vendor_bill_match_disputes (tenant_id, status);

create function app.touch_vendor_bill_match_disputes_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_bill_match_disputes_touch_row
  before update on app.vendor_bill_match_disputes
  for each row
  execute function app.touch_vendor_bill_match_disputes_row();

-- ===========================================================================
-- 5. app.vendor_bill_match_exception_approvals -- maker-checker for over-tolerance
--    (or duplicate-flagged, or currency-mismatched) cases. Self-approval blocked
--    (taxonomy C-18) -- the requester may never also decide their own request.
-- ===========================================================================

create table app.vendor_bill_match_exception_approvals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  match_case_id uuid not null references app.vendor_bill_match_cases (id),
  reason text not null,
  variance_amount numeric(14, 2),
  variance_pct numeric(9, 4),
  includes_duplicate_flag boolean not null default false,
  status text not null default 'pending',
  requested_by_auth_user_id uuid not null,
  requested_by text,
  decided_by_auth_user_id uuid,
  decision_note text,
  decided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_bill_match_exception_approvals_reason_check check (length(trim(reason)) > 0),
  constraint vendor_bill_match_exception_approvals_status_check check (status in ('pending', 'approved', 'rejected')),
  constraint vendor_bill_match_exception_approvals_decision_check check (status = 'pending' or (decision_note is not null and length(trim(decision_note)) > 0))
);

comment on table app.vendor_bill_match_exception_approvals is
  'PRC-265: maker-checker for a case blocked by over-tolerance variance, a duplicate-fingerprint flag, or a currency mismatch. At most one pending request per match_case_id (vendor_bill_match_exception_approvals_one_pending_idx). self_approval_not_allowed blocks the requester from also deciding, mirroring app.decide_vendor_kpi_source_dispute (PRC-264) exactly.';

create unique index vendor_bill_match_exception_approvals_one_pending_idx on app.vendor_bill_match_exception_approvals (match_case_id) where status = 'pending';
create index vendor_bill_match_exception_approvals_case_idx on app.vendor_bill_match_exception_approvals (match_case_id);
create index vendor_bill_match_exception_approvals_tenant_status_idx on app.vendor_bill_match_exception_approvals (tenant_id, status);

create function app.touch_vendor_bill_match_exception_approvals_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_bill_match_exception_approvals_touch_row
  before update on app.vendor_bill_match_exception_approvals
  for each row
  execute function app.touch_vendor_bill_match_exception_approvals_row();

-- ===========================================================================
-- 6. app.vendor_bill_match_events -- append-only lifecycle history, mirrors
--    app.purchase_order_events/app.vendor_comparison_events exactly.
-- ===========================================================================

create table app.vendor_bill_match_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  match_case_id uuid not null references app.vendor_bill_match_cases (id),
  event_type text not null,
  event_data jsonb not null default '{}'::jsonb,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default now()
);

comment on table app.vendor_bill_match_events is 'PRC-265: append-only match-case lifecycle history, never updated or deleted.';

create index vendor_bill_match_events_case_idx on app.vendor_bill_match_events (match_case_id, created_at);

create function app._record_vendor_bill_match_event(p_tenant_id uuid, p_match_case_id uuid, p_event_type text, p_event_data jsonb, p_actor_auth_user_id uuid, p_actor_label text)
returns void
language sql
as $$
  insert into app.vendor_bill_match_events (tenant_id, match_case_id, event_type, event_data, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_match_case_id, p_event_type, coalesce(p_event_data, '{}'::jsonb), p_actor_auth_user_id, p_actor_label);
$$;

comment on function app._record_vendor_bill_match_event is 'PRC-265: internal only -- no grant. Every lifecycle-changing function in this migration calls this exactly once per transition.';

-- ===========================================================================
-- 7. Shared helpers -- authority wrapper, cost masking, fingerprint, pct variance.
-- ===========================================================================

create function app.check_vendor_bill_match_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', p_action)).allowed;
$$;

comment on function app.check_vendor_bill_match_authority is
  'PRC-265: PRC:Edit gates create/re-evaluate/map/accept/raise-dispute/respond/request-exception; PRC:Approve gates resolve-dispute/decide-exception; PRC:Override gates cancel; PRC:View gates read. Mirrors app.check_finance_vendor_bill_authority (FIN-200) exactly.';

create function app.mask_vendor_bill_match_case_cost_fields(p_row app.vendor_bill_match_cases, p_can_view_cost boolean)
returns app.vendor_bill_match_cases
language plpgsql
immutable
as $$
begin
  if not p_can_view_cost then
    p_row.total_vendor_stated_amount := null;
    p_row.total_evidence_amount := null;
    p_row.total_variance_amount := null;
    p_row.total_variance_pct := null;
  end if;
  return p_row;
end;
$$;

comment on function app.mask_vendor_bill_match_case_cost_fields is
  'PRC-265: nulls the four cost-shaped rollup fields when the caller lacks PRC:View cost, mirroring app.mask_vendor_contract_cost_fields (PRC-261) exactly. Applied in every read RPC''s own projection, never a raw table grant.';

create function app.mask_vendor_bill_match_line_cost_fields(p_row app.vendor_bill_match_lines, p_can_view_cost boolean)
returns app.vendor_bill_match_lines
language plpgsql
immutable
as $$
begin
  if not p_can_view_cost then
    p_row.vendor_stated_rate := null;
    p_row.vendor_stated_amount := null;
    p_row.evidence_rate := null;
    p_row.evidence_amount := null;
    p_row.contracted_rate_amount := null;
    p_row.amount_variance_amount := null;
    p_row.amount_variance_pct := null;
    p_row.rate_variance_pct := null;
  end if;
  return p_row;
end;
$$;

comment on function app.mask_vendor_bill_match_line_cost_fields is 'PRC-265: line-level sibling of app.mask_vendor_bill_match_case_cost_fields -- quantity/uom/status are never cost-shaped and stay visible.';

create function app.mask_vendor_bill_match_dispute_cost_fields(p_row app.vendor_bill_match_disputes, p_can_view_cost boolean)
returns app.vendor_bill_match_disputes
language plpgsql
immutable
as $$
begin
  if not p_can_view_cost then
    p_row.disputed_amount := null;
  end if;
  return p_row;
end;
$$;

comment on function app.mask_vendor_bill_match_dispute_cost_fields is 'PRC-265: disputed_amount is the one cost-shaped field on a dispute row -- masked for a caller without PRC:View cost, same discipline as the case/line siblings.';

create function app.mask_vendor_bill_match_exception_approval_cost_fields(p_row app.vendor_bill_match_exception_approvals, p_can_view_cost boolean)
returns app.vendor_bill_match_exception_approvals
language plpgsql
immutable
as $$
begin
  if not p_can_view_cost then
    p_row.variance_amount := null;
    p_row.variance_pct := null;
  end if;
  return p_row;
end;
$$;

comment on function app.mask_vendor_bill_match_exception_approval_cost_fields is 'PRC-265: variance_amount/variance_pct are the cost-shaped fields on an exception-approval row -- masked for a caller without PRC:View cost.';

create function app.compute_vendor_bill_match_fingerprint(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_total_amount numeric)
returns text
language sql
immutable
as $$
  select md5(p_tenant_id::text || '|' || p_vendor_master_id::text || '|' || p_currency || '|' || round(p_total_amount, 2)::text);
$$;

comment on function app.compute_vendor_bill_match_fingerprint is
  'PRC-265: deliberately excludes vendor_reference and bill_date (finance_vendor_bills_tenant_vendor_reference_unique already blocks an EXACT reference duplicate; this fingerprint exists to catch a NEAR duplicate -- same vendor/currency/amount, different or blank reference). The duplicate check itself additionally filters by the active policy''s own duplicate_window_days against bill_date -- not baked into the fingerprint text.';

create function app._vendor_bill_match_pct_variance(p_stated numeric, p_evidence numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_stated is null or p_evidence is null then null
    when p_stated = 0 and p_evidence = 0 then 0
    else round(abs(p_stated - p_evidence) / nullif(abs(p_evidence), 0) * 100, 4)
  end;
$$;

comment on function app._vendor_bill_match_pct_variance is 'PRC-265: shared percentage-variance formula, division-by-zero safe (nullif). Returns NULL, never an error, when either side is unknown or the evidence side is exactly zero while stated is non-zero (a genuine, disclosed 100%+ mismatch is represented by a large-but-finite value only when evidence is non-zero; a zero-evidence/non-zero-stated pair is left NULL and the line is scored missing_evidence-adjacent by the caller, never divided by zero).';

-- ===========================================================================
-- 8. Tolerance policy CRUD.
-- ===========================================================================

create function app.create_vendor_bill_match_tolerance_policy_draft(
  p_tenant_id uuid, p_name text, p_quantity_tolerance_pct numeric, p_rate_tolerance_pct numeric, p_tax_tolerance_pct numeric,
  p_line_amount_tolerance_abs numeric, p_auto_clear_enabled boolean, p_duplicate_window_days integer, p_notes text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_bill_match_tolerance_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.vendor_bill_match_tolerance_policies;
  v_policy app.vendor_bill_match_tolerance_policies;
  v_next_version integer;
begin
  if not app.check_vendor_bill_match_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.name is distinct from p_name
      or v_existing.quantity_tolerance_pct is distinct from p_quantity_tolerance_pct
      or v_existing.rate_tolerance_pct is distinct from p_rate_tolerance_pct
      or v_existing.tax_tolerance_pct is distinct from p_tax_tolerance_pct
      or v_existing.line_amount_tolerance_abs is distinct from p_line_amount_tolerance_abs
      or v_existing.auto_clear_enabled is distinct from p_auto_clear_enabled
      or v_existing.duplicate_window_days is distinct from p_duplicate_window_days
    then
      raise exception 'idempotency_key_conflict: key % was already used for a different tolerance policy draft', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'reason_required: a non-empty policy name is required' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next_version from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id;

  begin
    insert into app.vendor_bill_match_tolerance_policies (
      tenant_id, version_no, name, quantity_tolerance_pct, rate_tolerance_pct, tax_tolerance_pct,
      line_amount_tolerance_abs, auto_clear_enabled, duplicate_window_days, notes, idempotency_key, created_by
    )
    values (
      p_tenant_id, v_next_version, p_name, coalesce(p_quantity_tolerance_pct, 0), coalesce(p_rate_tolerance_pct, 0), coalesce(p_tax_tolerance_pct, 0),
      coalesce(p_line_amount_tolerance_abs, 0), coalesce(p_auto_clear_enabled, false), coalesce(p_duplicate_window_days, 30), p_notes, p_idempotency_key, p_actor_label
    )
    returning * into v_policy;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_bill_match_tolerance_policy_draft', 'app.vendor_bill_match_tolerance_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy));
  return v_policy;
end;
$$;

comment on function app.create_vendor_bill_match_tolerance_policy_draft is
  'PRC-265: PRC:Edit. Idempotency replay compares the full target tuple (taxonomy C-01); the race-recovery exception handler is nested to scope ONLY the INSERT statement, never the pre-check''s own deliberate raise (taxonomy C-02).';

create function app.update_vendor_bill_match_tolerance_policy_draft(
  p_policy_id uuid, p_expected_version integer, p_name text, p_quantity_tolerance_pct numeric, p_rate_tolerance_pct numeric,
  p_tax_tolerance_pct numeric, p_line_amount_tolerance_abs numeric, p_auto_clear_enabled boolean, p_duplicate_window_days integer, p_notes text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_bill_match_tolerance_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.vendor_bill_match_tolerance_policies;
begin
  select * into v_policy from app.vendor_bill_match_tolerance_policies where id = p_policy_id for update;
  if not found then
    raise exception 'vendor_bill_match_tolerance_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: tolerance policy % expected version % but found %', p_policy_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: tolerance policy % is % and cannot be edited', p_policy_id, v_policy.status
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'reason_required: a non-empty policy name is required' using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_tolerance_policies
  set name = p_name, quantity_tolerance_pct = coalesce(p_quantity_tolerance_pct, 0), rate_tolerance_pct = coalesce(p_rate_tolerance_pct, 0),
      tax_tolerance_pct = coalesce(p_tax_tolerance_pct, 0), line_amount_tolerance_abs = coalesce(p_line_amount_tolerance_abs, 0),
      auto_clear_enabled = coalesce(p_auto_clear_enabled, false), duplicate_window_days = coalesce(p_duplicate_window_days, 30), notes = p_notes
  where id = p_policy_id and record_version = p_expected_version
  returning * into v_policy;
  if not found then
    raise exception 'stale_version: tolerance policy % target row was concurrently modified (expected version %)', p_policy_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_bill_match_tolerance_policy_draft', 'app.vendor_bill_match_tolerance_policies', v_policy.id, 'success', null, null, '{}'::jsonb);
  return v_policy;
end;
$$;

create function app.activate_vendor_bill_match_tolerance_policy(p_policy_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_tolerance_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.vendor_bill_match_tolerance_policies;
  v_prior app.vendor_bill_match_tolerance_policies;
begin
  select * into v_policy from app.vendor_bill_match_tolerance_policies where id = p_policy_id for update;
  if not found then
    raise exception 'vendor_bill_match_tolerance_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: tolerance policy % expected version % but found %', p_policy_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: tolerance policy % is % and cannot be activated', p_policy_id, v_policy.status
      using errcode = 'check_violation';
  end if;

  -- C-04: lock any currently-active row of this tenant before superseding it, same
  -- table lock order as this function's own only self-referential mutation (no other
  -- table is locked here, so no C-21 ordering question arises).
  select * into v_prior from app.vendor_bill_match_tolerance_policies where tenant_id = v_policy.tenant_id and status = 'active' for update;
  if found then
    update app.vendor_bill_match_tolerance_policies set status = 'archived' where id = v_prior.id and record_version = v_prior.record_version;
    if not found then
      raise exception 'stale_version: active tolerance policy % was concurrently modified', v_prior.id using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_bill_match_tolerance_policies set status = 'active', approved_by = p_actor_label, approved_at = now()
  where id = p_policy_id and record_version = p_expected_version
  returning * into v_policy;
  if not found then
    raise exception 'stale_version: tolerance policy % target row was concurrently modified (expected version %)', p_policy_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_bill_match_tolerance_policy', 'app.vendor_bill_match_tolerance_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy));
  return v_policy;
end;
$$;

comment on function app.activate_vendor_bill_match_tolerance_policy is
  'PRC-265: PRC:Approve, the "human-approved policy" business rule''s own real gate. Supersedes any prior active row for the tenant (locked before mutation, C-04). Self-approval is NOT blocked here (mirrors app.publish_vendor_kpi_definition''s own identical, already-disclosed precedent -- ISS-2026-038 -- not a fresh gap).';

create function app.get_active_vendor_bill_match_tolerance_policy(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_bill_match_tolerance_policies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.vendor_bill_match_tolerance_policies;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_policy from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id and status = 'active';
  return v_policy;
end;
$$;

comment on function app.get_active_vendor_bill_match_tolerance_policy is 'PRC-265: returns NULL (never raises) when no policy is active -- mirrors app.resolve_effective_vendor_contract''s own "distinguish no-row from not-authorized" shape.';

create function app.list_vendor_bill_match_tolerance_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_tolerance_policies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.vendor_bill_match_tolerance_policies where tenant_id = p_tenant_id order by version_no desc;
end;
$$;

-- ===========================================================================
-- 9. Internal: recompute one line's evidence/variance, and re-roll a case's own
--    aggregate status from its current lines. Internal only -- no grant.
-- ===========================================================================

create function app._score_vendor_bill_match_line(p_line app.vendor_bill_match_lines, p_case app.vendor_bill_match_cases)
returns app.vendor_bill_match_lines
language plpgsql
as $$
declare
  v_tol_pct numeric;
begin
  v_tol_pct := case when p_line.line_type = 'tax' then p_case.tax_tolerance_pct_snapshot else p_case.rate_tolerance_pct_snapshot end;

  if p_line.evidence_amount is null then
    p_line.line_status := 'missing_evidence';
    return p_line;
  end if;
  if p_line.evidence_currency is not null and p_line.evidence_currency <> p_case.currency then
    p_line.currency_mismatch := true;
    p_line.line_status := 'currency_mismatch';
    p_line.quantity_variance_pct := null;
    p_line.rate_variance_pct := null;
    p_line.amount_variance_amount := null;
    p_line.amount_variance_pct := null;
    return p_line;
  end if;

  p_line.quantity_variance_pct := app._vendor_bill_match_pct_variance(p_line.vendor_stated_quantity, p_line.evidence_quantity);
  p_line.rate_variance_pct := app._vendor_bill_match_pct_variance(p_line.vendor_stated_rate, p_line.evidence_rate);
  p_line.amount_variance_amount := round(abs(p_line.vendor_stated_amount - p_line.evidence_amount), 2);
  p_line.amount_variance_pct := app._vendor_bill_match_pct_variance(p_line.vendor_stated_amount, p_line.evidence_amount);
  p_line.uom_mismatch := p_line.vendor_stated_uom is not null and p_line.evidence_uom is not null and lower(trim(p_line.vendor_stated_uom)) <> lower(trim(p_line.evidence_uom));

  if p_line.uom_mismatch
    or (p_line.quantity_variance_pct is not null and p_line.quantity_variance_pct > p_case.quantity_tolerance_pct_snapshot)
    or (p_line.rate_variance_pct is not null and p_line.rate_variance_pct > v_tol_pct)
    or (p_line.amount_variance_amount > p_case.line_amount_tolerance_abs_snapshot
        and (p_line.amount_variance_pct is null or p_line.amount_variance_pct > v_tol_pct))
  then
    p_line.line_status := 'variance_exception';
  elsif p_line.amount_variance_amount > 0 or coalesce(p_line.quantity_variance_pct, 0) > 0 or coalesce(p_line.rate_variance_pct, 0) > 0 then
    p_line.line_status := 'variance_within_tolerance';
  else
    p_line.line_status := 'matched';
  end if;

  return p_line;
end;
$$;

comment on function app._score_vendor_bill_match_line is
  'PRC-265: internal, no grant. The one place a line''s variance/status is decided -- amount variance is over tolerance when it exceeds BOTH the absolute buffer AND the percentage tolerance (a small absolute rounding difference under the abs buffer is never itself an exception even if the pct looks large on a tiny base). Tax lines are scored against tax_tolerance_pct_snapshot in place of rate_tolerance_pct_snapshot -- one engine, two tolerance dimensions (see migration header).';

create function app._reroll_vendor_bill_match_case(p_case_id uuid)
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
  v_po_variance_pct numeric;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  select coalesce(sum(vendor_stated_amount), 0), coalesce(sum(evidence_amount), 0),
    bool_or(line_status = 'variance_exception'), bool_or(line_status = 'missing_evidence'), bool_or(line_status = 'currency_mismatch')
  into v_stated_sum, v_evidence_sum, v_any_exception, v_any_missing, v_any_currency_mismatch
  from app.vendor_bill_match_lines where match_case_id = p_case_id;

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
  'PRC-265: internal, no grant. Recomputes case-level rollups/overall_status/readiness_status purely from its own current lines plus the case''s own already-snapshotted tolerance/duplicate/PO fields -- never re-resolves the tolerance policy or duplicate flag itself (those are set once, at create/re_evaluate time). Caller must already be inside a transaction that has reason to call this (create/re_evaluate/map_line); it takes its OWN lock on the case row (C-04), consistent with every other function in this migration''s own "lock the case before deciding" discipline.';

-- ===========================================================================
-- 10. app.create_vendor_bill_match_case
-- ===========================================================================

create function app.create_vendor_bill_match_case(
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
  -- whose own bill_date falls within this policy's own duplicate_window_days.
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
  'PRC-265: PRC:Edit. Creates version 1 of a match case for a bill, auto-linking actual-cost evidence and, when supplied, validating a PO (tenant/vendor/status/currency) as additional evidence. Requires a non-null vendorStatedAmount for every bill line in p_line_inputs -- this is the real, independent line-level capture of what the vendor''s own invoice states (see migration header). Idempotent by (tenant_id, idempotency_key), full-tuple compared (C-01); the race-recovery handler is a SEPARATE catch clause from the pre-check''s own raise (C-02 safe).';

-- ===========================================================================
-- 11. app.re_evaluate_vendor_bill_match_case
-- ===========================================================================

create function app.re_evaluate_vendor_bill_match_case(
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
    v_prior.has_epod_evidence, v_prior.has_delivery_milestone_evidence, v_fingerprint, p_actor_label, v_prior.tenant_id::text || ':' || p_match_case_id::text || ':v' || (v_prior.version_no + 1)::text, p_actor_label
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
  'PRC-265: PRC:Edit. Creates version N+1 of the SAME logical case (bill_id unchanged), never mutating version N''s own rows -- full source/version lineage retained (business rule). Deliberately carries NO idempotency_key parameter, mirroring app.amend_vendor_contract/app.renew_vendor_contract (PRC-261) exactly: p_expected_version is the replay guard for a version-creating call in this repository''s own established convention. Blocked while overall_status is disputed (resolve the dispute first) or cancelled.';

-- ===========================================================================
-- 12. app.map_vendor_bill_match_line
-- ===========================================================================

create function app.map_vendor_bill_match_line(
  p_match_line_id uuid,
  p_expected_case_version integer,
  p_po_line_id uuid,
  p_rate_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bill_match_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_peek app.vendor_bill_match_lines;
  v_case app.vendor_bill_match_cases;
  v_line app.vendor_bill_match_lines;
  v_po_line app.purchase_order_lines;
  v_rate app.vendor_rate_versions;
  v_computed record;
begin
  -- Lock order (migration header): unlocked peek to resolve the owning case, THEN lock
  -- the parent case, THEN lock/re-validate this child row.
  select * into v_peek from app.vendor_bill_match_lines where id = p_match_line_id;
  if not found then
    raise exception 'vendor_bill_match_line_not_found: %', p_match_line_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_case_version then
    raise exception 'stale_version: match case % expected version % but found %', v_case.id, p_expected_case_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_case.is_current or v_case.overall_status not in ('pending', 'exception') then
    raise exception 'invalid_transition: match case % is % and its lines can no longer be mapped', v_case.id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.vendor_bill_match_lines where id = p_match_line_id for update;

  if p_po_line_id is not null then
    select * into v_po_line from app.purchase_order_lines where id = p_po_line_id and tenant_id = v_case.tenant_id;
    if not found or v_po_line.purchase_order_id <> v_case.purchase_order_id then
      raise exception 'po_line_scope_mismatch: purchase order line % does not belong to this case''s own purchase order', p_po_line_id using errcode = 'check_violation';
    end if;
    v_line.po_line_id := p_po_line_id;
    v_line.po_line_quantity_variance_pct := app._vendor_bill_match_pct_variance(v_line.vendor_stated_quantity, v_po_line.quantity);
    v_line.po_line_uom_mismatch := v_po_line.uom is not null and v_line.vendor_stated_uom is not null and lower(trim(v_po_line.uom)) <> lower(trim(v_line.vendor_stated_uom));
  end if;

  if p_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id and tenant_id = v_case.tenant_id;
    if not found or v_rate.vendor_master_id is distinct from v_case.vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to this case''s own vendor', p_rate_version_id using errcode = 'check_violation';
    end if;
    v_line.rate_version_id := p_rate_version_id;
    if v_line.evidence_quantity is not null and v_rate.currency = v_case.currency then
      begin
        select computed_amount, currency into v_computed from app.calculate_vendor_rate(p_rate_version_id, null, null, v_line.evidence_quantity, p_actor_auth_user_id);
        v_line.contracted_rate_amount := v_computed.computed_amount;
        v_line.contracted_rate_currency := v_computed.currency;
      exception
        when others then
          -- Best-effort only (migration header): a tier-resolution failure (e.g. no
          -- tier covers this quantity) never blocks the rest of the mapping.
          v_line.contracted_rate_amount := null;
          v_line.contracted_rate_currency := null;
      end;
    end if;
  end if;

  update app.vendor_bill_match_lines
  set po_line_id = v_line.po_line_id, po_line_quantity_variance_pct = v_line.po_line_quantity_variance_pct, po_line_uom_mismatch = v_line.po_line_uom_mismatch,
      rate_version_id = v_line.rate_version_id, contracted_rate_amount = v_line.contracted_rate_amount, contracted_rate_currency = v_line.contracted_rate_currency
  where id = p_match_line_id
  returning * into v_line;

  perform app._reroll_vendor_bill_match_case(v_case.id);

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'line_mapped', jsonb_build_object('matchLineId', p_match_line_id, 'poLineId', p_po_line_id, 'rateVersionId', p_rate_version_id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'map_vendor_bill_match_line', 'app.vendor_bill_match_lines', v_line.id, 'success', null, null, '{}'::jsonb);

  return v_line;
end;
$$;

comment on function app.map_vendor_bill_match_line is
  'PRC-265: PRC:Edit. Attaches optional PO-line (quantity/UOM only -- PRC-260''s own disclosed no-per-line-price boundary) and/or rate-version evidence to one line, re-validating tenant/vendor scope before linking (never trusted blindly). contracted_rate_amount is a best-effort informational cross-check via app.calculate_vendor_rate (PRC-255) -- a tier-resolution failure is caught and leaves the field NULL rather than blocking the mapping. Re-rolls the owning case''s own aggregate status after mapping.';

-- ===========================================================================
-- 13. app.accept_vendor_bill_match_within_tolerance
-- ===========================================================================

create function app.accept_vendor_bill_match_within_tolerance(p_match_case_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.vendor_bill_match_cases;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_case.is_current then
    raise exception 'invalid_transition: match case % is not the current version', p_match_case_id using errcode = 'check_violation';
  end if;
  -- C-15: re-verify at the actual point of commitment -- overall_status must genuinely
  -- be 'pending' (computed within-tolerance by app._reroll_vendor_bill_match_case) right
  -- now, never trusted from an earlier read the caller might be acting on.
  if v_case.overall_status <> 'pending' then
    raise exception 'invalid_transition: match case % is % -- only a case within tolerance and awaiting explicit accept may be accepted', p_match_case_id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = 'matched', readiness_status = 'ready_for_finance', readiness_note = 'accepted within tolerance by ' || coalesce(p_actor_label, p_actor_auth_user_id::text), evaluated_by = p_actor_label, evaluated_at = now()
  where id = p_match_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: match case % target row was concurrently modified (expected version %)', p_match_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'accepted_within_tolerance', '{}'::jsonb, p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_bill_match_within_tolerance', 'app.vendor_bill_match_cases', v_case.id, 'success', null, null, to_jsonb(v_case));

  return v_case;
end;
$$;

-- ===========================================================================
-- 14. Disputes.
-- ===========================================================================

create function app.raise_vendor_bill_match_dispute(p_match_case_id uuid, p_match_line_id uuid, p_reason text, p_disputed_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.vendor_bill_match_cases;
  v_dispute app.vendor_bill_match_disputes;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to raise a vendor bill match dispute' using errcode = 'check_violation';
  end if;
  if not v_case.is_current or v_case.overall_status in ('cancelled', 'disputed') then
    raise exception 'invalid_transition: match case % is % and cannot be disputed', p_match_case_id, v_case.overall_status using errcode = 'check_violation';
  end if;
  if p_match_line_id is not null and not exists (select 1 from app.vendor_bill_match_lines where id = p_match_line_id and match_case_id = p_match_case_id) then
    raise exception 'vendor_bill_match_line_not_found: % does not belong to match case %', p_match_line_id, p_match_case_id using errcode = 'no_data_found';
  end if;

  update app.vendor_bill_match_cases set overall_status = 'disputed', readiness_status = 'not_ready', readiness_note = 'dispute raised: ' || p_reason where id = p_match_case_id;

  begin
    insert into app.vendor_bill_match_disputes (tenant_id, match_case_id, match_line_id, reason, disputed_amount, raised_by_auth_user_id, raised_by, created_by)
    values (v_case.tenant_id, p_match_case_id, p_match_line_id, p_reason, p_disputed_amount, p_actor_auth_user_id, p_actor_label, p_actor_label)
    returning * into v_dispute;
  exception
    when unique_violation then
      raise exception 'dispute_already_open: match case % (line %) already has an open dispute', p_match_case_id, p_match_line_id using errcode = 'unique_violation';
  end;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, p_match_case_id, 'dispute_raised', jsonb_build_object('disputeId', v_dispute.id, 'matchLineId', p_match_line_id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_bill_match_dispute', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', p_reason, null, jsonb_build_object('matchCaseId', p_match_case_id));

  return v_dispute;
end;
$$;

comment on function app.raise_vendor_bill_match_dispute is
  'PRC-265: PRC:Edit, staff-recorded on the vendor''s own behalf (no vendor-portal identity exists, same accepted precedent). Moves the case to disputed immediately. At most one open dispute per (case, line) -- a genuine unique_violation race is translated to a typed error, mirroring app.raise_vendor_kpi_source_dispute (PRC-264) exactly, C-02 safe (separate catch clause from any pre-check raise).';

create function app.record_vendor_bill_match_dispute_response(p_dispute_id uuid, p_expected_version integer, p_vendor_response text, p_vendor_response_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_dispute app.vendor_bill_match_disputes;
  v_file app.files;
begin
  select * into v_dispute from app.vendor_bill_match_disputes where id = p_dispute_id for update;
  if not found then
    raise exception 'vendor_bill_match_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_dispute.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_dispute.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'open' then
    raise exception 'invalid_transition: dispute % is % and can no longer take a response', p_dispute_id, v_dispute.status using errcode = 'check_violation';
  end if;
  if p_vendor_response is null or length(trim(p_vendor_response)) = 0 then
    raise exception 'reason_required: a non-empty response is required' using errcode = 'check_violation';
  end if;

  if p_vendor_response_file_id is not null then
    select * into v_file from app.files where id = p_vendor_response_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_vendor_response_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_dispute.tenant_id or v_file.record_type <> 'vendor_bill_match_dispute' or v_file.record_id <> p_dispute_id then
      raise exception 'dispute_evidence_file_mismatch: file % does not belong to dispute % in tenant %', p_vendor_response_file_id, p_dispute_id, v_dispute.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'dispute_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', p_vendor_response_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.vendor_bill_match_disputes
  set vendor_response = p_vendor_response, vendor_response_at = now(), vendor_response_file_id = coalesce(p_vendor_response_file_id, vendor_response_file_id)
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_dispute.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_vendor_bill_match_dispute_response', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', null, null, '{}'::jsonb);
  return v_dispute;
end;
$$;

comment on function app.record_vendor_bill_match_dispute_response is
  'PRC-265: PRC:Edit, staff-recorded (§26 "vendor may respond ... [recorded by staff]"). Re-validates any evidence file (tenant/record_type/record_id/malware_scan_status=clean, taxonomy C-10) before linking, mirroring app.record_vendor_contract_signature (PRC-261) exactly.';

create function app.resolve_vendor_bill_match_dispute(p_dispute_id uuid, p_expected_version integer, p_decision text, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_peek app.vendor_bill_match_disputes;
  v_case app.vendor_bill_match_cases;
  v_dispute app.vendor_bill_match_disputes;
begin
  -- Lock order: unlocked peek to resolve the owning case, THEN lock the case, THEN
  -- lock/re-validate this dispute row (migration header).
  select * into v_peek from app.vendor_bill_match_disputes where id = p_dispute_id;
  if not found then
    raise exception 'vendor_bill_match_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_dispute from app.vendor_bill_match_disputes where id = p_dispute_id for update;

  -- Taxonomy C-18: self-approval blocked -- the raiser may never also resolve their own
  -- dispute.
  if v_dispute.raised_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % raised dispute % and may not also resolve it', p_actor_auth_user_id, p_dispute_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'open' then
    raise exception 'invalid_transition: dispute % is % and cannot be resolved again', p_dispute_id, v_dispute.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('upheld', 'rejected', 'withdrawn') then
    raise exception 'invalid_decision: % is not one of upheld/rejected/withdrawn', p_decision using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a non-empty resolution note is required' using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_disputes
  set status = p_decision, resolution_note = p_resolution_note, resolved_by_auth_user_id = p_actor_auth_user_id, resolved_at = now()
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  -- Any resolution returns the case to pending -- a fresh accept/exception-approval
  -- decision is always required afterward, never silently re-cleared.
  update app.vendor_bill_match_cases
  set overall_status = 'pending', readiness_status = 'not_ready', readiness_note = 'dispute ' || p_decision || ' -- awaiting a fresh accept or exception-approval decision'
  where id = v_case.id;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'dispute_resolved', jsonb_build_object('disputeId', p_dispute_id, 'decision', p_decision), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_vendor_bill_match_dispute', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', p_resolution_note, null, jsonb_build_object('decision', p_decision));

  return v_dispute;
end;
$$;

comment on function app.resolve_vendor_bill_match_dispute is
  'PRC-265: PRC:Approve. Self-approval blocked (taxonomy C-18) -- the raiser may never also decide. Every resolution (upheld/rejected/withdrawn) returns the case to pending, requiring a fresh accept/exception-approval decision -- never silently re-clears to matched.';

-- ===========================================================================
-- 15. Exception approvals.
-- ===========================================================================

create function app.request_vendor_bill_match_exception_approval(p_match_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_exception_approvals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.vendor_bill_match_cases;
  v_approval app.vendor_bill_match_exception_approvals;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request an exception approval' using errcode = 'check_violation';
  end if;
  if v_case.overall_status <> 'exception' then
    raise exception 'invalid_transition: match case % is % -- exception approval may only be requested for a case in exception', p_match_case_id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_bill_match_exception_approvals (tenant_id, match_case_id, reason, variance_amount, variance_pct, includes_duplicate_flag, requested_by_auth_user_id, requested_by, created_by)
    values (v_case.tenant_id, p_match_case_id, p_reason, v_case.total_variance_amount, v_case.total_variance_pct, v_case.is_duplicate_flagged, p_actor_auth_user_id, p_actor_label, p_actor_label)
    returning * into v_approval;
  exception
    when unique_violation then
      raise exception 'exception_approval_already_pending: match case % already has a pending exception approval request', p_match_case_id using errcode = 'unique_violation';
  end;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, p_match_case_id, 'exception_approval_requested', jsonb_build_object('approvalId', v_approval.id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_bill_match_exception_approval', 'app.vendor_bill_match_exception_approvals', v_approval.id, 'success', p_reason, null, jsonb_build_object('matchCaseId', p_match_case_id));

  return v_approval;
end;
$$;

create function app.decide_vendor_bill_match_exception_approval(p_approval_id uuid, p_expected_version integer, p_decision text, p_decision_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_exception_approvals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_peek app.vendor_bill_match_exception_approvals;
  v_case app.vendor_bill_match_cases;
  v_approval app.vendor_bill_match_exception_approvals;
  v_bill app.finance_vendor_bills;
begin
  -- Lock order: unlocked peek to resolve the owning case, THEN lock the case, THEN
  -- lock/re-validate this approval row (migration header).
  select * into v_peek from app.vendor_bill_match_exception_approvals where id = p_approval_id;
  if not found then
    raise exception 'vendor_bill_match_exception_approval_not_found: %', p_approval_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_approval from app.vendor_bill_match_exception_approvals where id = p_approval_id for update;

  -- Taxonomy C-18: self-approval blocked.
  if v_approval.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested exception approval % and may not also decide it', p_actor_auth_user_id, p_approval_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_approval.record_version <> p_expected_version then
    raise exception 'stale_version: exception approval % expected version % but found %', p_approval_id, p_expected_version, v_approval.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_approval.status <> 'pending' then
    raise exception 'invalid_transition: exception approval % is % and cannot be decided again', p_approval_id, v_approval.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_note is null or length(trim(p_decision_note)) = 0 then
    raise exception 'reason_required: a non-empty decision note is required' using errcode = 'check_violation';
  end if;
  -- C-15: re-verify the case is still genuinely in exception right now, and the bill
  -- itself is still not void, at the actual point of commitment.
  if v_case.overall_status <> 'exception' then
    raise exception 'invalid_transition: match case % is no longer in exception (now %) -- this request is stale', v_case.id, v_case.overall_status
      using errcode = 'check_violation';
  end if;
  select * into v_bill from app.finance_vendor_bills where id = v_case.bill_id;
  if not found or v_bill.status = 'void' then
    raise exception 'finance_vendor_bill_void: bill % is void -- this exception approval can no longer be decided', v_case.bill_id using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_exception_approvals
  set status = p_decision, decision_note = p_decision_note, decided_by_auth_user_id = p_actor_auth_user_id, decided_at = now()
  where id = p_approval_id and record_version = p_expected_version
  returning * into v_approval;
  if not found then
    raise exception 'stale_version: exception approval % target row was concurrently modified (expected version %)', p_approval_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = case when p_decision = 'approved' then 'matched' else 'blocked' end,
      readiness_status = case when p_decision = 'approved' then 'ready_for_finance' else 'blocked' end,
      readiness_note = case when p_decision = 'approved' then 'exception approved: ' || p_decision_note else 'exception rejected: ' || p_decision_note end
  where id = v_case.id;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'exception_approval_decided', jsonb_build_object('approvalId', p_approval_id, 'decision', p_decision), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_bill_match_exception_approval', 'app.vendor_bill_match_exception_approvals', v_approval.id, 'success', p_decision_note, null, jsonb_build_object('decision', p_decision));

  return v_approval;
end;
$$;

comment on function app.decide_vendor_bill_match_exception_approval is
  'PRC-265: PRC:Approve. Self-approval blocked (taxonomy C-18). Re-verifies the case is still genuinely in exception AND the bill is still not void at the actual point of commitment (taxonomy C-15), never trusting the request-time snapshot alone. Approved -> case matched/ready_for_finance (Finance''s own approve/post remain untouched, unblocked to proceed at Finance''s own discretion); rejected -> case blocked.';

-- ===========================================================================
-- 16. app.cancel_vendor_bill_match_case
-- ===========================================================================

create function app.cancel_vendor_bill_match_case(p_match_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bill_match_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.vendor_bill_match_cases;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Override', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Override for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a match case' using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_case.overall_status in ('cancelled', 'matched') then
    raise exception 'invalid_transition: match case % is % and cannot be cancelled', p_match_case_id, v_case.overall_status using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = 'cancelled', readiness_status = 'blocked', cancel_reason = p_reason
  where id = p_match_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: match case % target row was concurrently modified (expected version %)', p_match_case_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'case_cancelled', jsonb_build_object('reason', p_reason), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_bill_match_case', 'app.vendor_bill_match_cases', v_case.id, 'success', p_reason, null, to_jsonb(v_case));

  return v_case;
end;
$$;

comment on function app.cancel_vendor_bill_match_case is 'PRC-265: PRC:Override. Administrative stop (e.g. the underlying bill was voided by Finance, or the case was opened in error) -- rollback/recovery note §32''s own "stop new evaluations" surface. A cancelled case is terminal; app.create_vendor_bill_match_case still refuses while ANY current case exists for the bill, so a fresh match requires a brand-new bill.';

-- ===========================================================================
-- 17. Read RPCs.
-- ===========================================================================

create function app.get_vendor_bill_match_case(p_match_case_id uuid, p_bill_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_bill_match_cases
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_case app.vendor_bill_match_cases;
begin
  if p_match_case_id is not null then
    select tenant_id into v_tenant_id from app.vendor_bill_match_cases where id = p_match_case_id;
  elsif p_bill_id is not null then
    select tenant_id into v_tenant_id from app.vendor_bill_match_cases where bill_id = p_bill_id and is_current;
  else
    raise exception 'match_case_lookup_required: one of p_match_case_id/p_bill_id is required' using errcode = 'check_violation';
  end if;

  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: no match case found for the given lookup' using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('View', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_match_case_id is not null then
    select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id;
  else
    select * into v_case from app.vendor_bill_match_cases where bill_id = p_bill_id and is_current;
  end if;

  return app.mask_vendor_bill_match_case_cost_fields(v_case, app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id));
end;
$$;

comment on function app.get_vendor_bill_match_case is 'PRC-265: taxonomy C-05 -- not-found and cross-tenant fold into the identical vendor_bill_match_case_not_found error before evaluate_permission runs. Pass exactly one of p_match_case_id (a specific version) or p_bill_id (the current version).';

create function app.list_vendor_bill_match_cases(p_tenant_id uuid, p_vendor_master_id uuid, p_overall_status text, p_readiness_status text, p_actor_auth_user_id uuid, p_limit integer)
returns setof app.vendor_bill_match_cases
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select (app.mask_vendor_bill_match_case_cost_fields(mc, v_can_view_cost)).*
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.is_current
    and (p_vendor_master_id is null or mc.vendor_master_id = p_vendor_master_id)
    and (p_overall_status is null or mc.overall_status = p_overall_status)
    and (p_readiness_status is null or mc.readiness_status = p_readiness_status)
  order by mc.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

create function app.list_vendor_bill_match_case_versions(p_bill_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_cases
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select (app.mask_vendor_bill_match_case_cost_fields(mc, v_can_view_cost)).*
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.bill_id = p_bill_id
  order by mc.version_no desc;
end;
$$;

create function app.list_vendor_bill_match_lines(p_match_case_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_can_view_cost boolean;
begin
  select tenant_id into v_tenant_id from app.vendor_bill_match_cases where id = p_match_case_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;
  if not app.check_vendor_bill_match_authority('View', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id);

  return query
  select (app.mask_vendor_bill_match_line_cost_fields(l, v_can_view_cost)).*
  from app.vendor_bill_match_lines l
  where l.match_case_id = p_match_case_id
  order by l.line_no asc;
end;
$$;

create function app.list_vendor_bill_match_case_events(p_match_case_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_bill_match_cases where id = p_match_case_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;
  if not app.check_vendor_bill_match_authority('View', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.vendor_bill_match_events where match_case_id = p_match_case_id order by created_at asc;
end;
$$;

create function app.list_vendor_bill_match_disputes(p_match_case_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_disputes
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_bill_match_cases where id = p_match_case_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;
  if not app.check_vendor_bill_match_authority('View', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select (app.mask_vendor_bill_match_dispute_cost_fields(d, app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id))).*
  from app.vendor_bill_match_disputes d
  where d.match_case_id = p_match_case_id
  order by d.created_at desc;
end;
$$;

create function app.list_vendor_bill_match_exception_approvals(p_match_case_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_bill_match_exception_approvals
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_bill_match_cases where id = p_match_case_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;
  if not app.check_vendor_bill_match_authority('View', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select (app.mask_vendor_bill_match_exception_approval_cost_fields(a, app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id))).*
  from app.vendor_bill_match_exception_approvals a
  where a.match_case_id = p_match_case_id
  order by a.created_at desc;
end;
$$;

create function app.get_vendor_bill_match_readiness(p_bill_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
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

  return query
  select mc.bill_id, mc.id, mc.overall_status, mc.readiness_status, mc.readiness_note, mc.is_duplicate_flagged, mc.total_variance_pct, mc.evaluated_at
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.bill_id = p_bill_id and mc.is_current;
end;
$$;

comment on function app.get_vendor_bill_match_readiness is
  'PRC-265: the real, callable, read-only "clean readiness handoff back to Finance" -- gated on PRC:View OR FIN:View. Never hooks, gates, or wraps app.approve_finance_vendor_bill/app.post_finance_vendor_bill (FIN-200) -- Finance''s own approver still decides when to post, exactly as FIN-200''s own already-disclosed non-blocking variance_status precedent. Returns zero rows (never raises) when no match case exists yet for the bill.';

create function app.get_vendor_bill_match_reconciliation_status(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  overall_status text, readiness_status text, case_count bigint, total_variance_amount numeric, oldest_pending_evaluated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select mc.overall_status, mc.readiness_status, count(*)::bigint,
    case when v_can_view_cost then sum(mc.total_variance_amount) else null end,
    min(mc.evaluated_at) filter (where mc.overall_status = 'pending')
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.is_current
  group by mc.overall_status, mc.readiness_status
  order by mc.overall_status, mc.readiness_status;
end;
$$;

comment on function app.get_vendor_bill_match_reconciliation_status is
  'PRC-265: this capability''s OWN Procurement-side aggregate summary of match-case outcomes -- deliberately NOT integrated with Finance''s own generic reconciliation engine (FIN-207, app.finance_reconciliations), a distinct ledger-balance concept, to avoid touching Finance''s own reconciliation entity-type surface (see migration header).';

-- ===========================================================================
-- 18. RLS + grants.
-- ===========================================================================

alter table app.vendor_bill_match_tolerance_policies enable row level security;
alter table app.vendor_bill_match_cases enable row level security;
alter table app.vendor_bill_match_lines enable row level security;
alter table app.vendor_bill_match_disputes enable row level security;
alter table app.vendor_bill_match_exception_approvals enable row level security;
alter table app.vendor_bill_match_events enable row level security;

-- ISS-2026-010/CG-S10-ATW-032 default-deny: every new SELECT policy narrows plain
-- tenant membership with `not app.actor_holds_customer_user_layer(tenant_id)` from the
-- first draft (this capability is Finance/Procurement-sensitive vendor-bill match
-- evidence, exactly the class that standing repository-wide gate exists to keep a
-- customer-portal-layer principal away from) -- applied here, never deferred to a later
-- hardening pass.
create policy vendor_bill_match_tolerance_policies_select_scoped on app.vendor_bill_match_tolerance_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_bill_match_cases_select_scoped on app.vendor_bill_match_cases
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_bill_match_lines_select_scoped on app.vendor_bill_match_lines
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_bill_match_disputes_select_scoped on app.vendor_bill_match_disputes
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_bill_match_exception_approvals_select_scoped on app.vendor_bill_match_exception_approvals
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_bill_match_events_select_scoped on app.vendor_bill_match_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.vendor_bill_match_tolerance_policies to authenticated, service_role;
-- C-11 defense in depth (batch 257-259's own established fix pattern, applied here from
-- the start rather than needing a future hardening pass): `authenticated`'s direct table
-- grant is column-restricted to exclude every cost-shaped field
-- app.mask_vendor_bill_match_case_cost_fields/_line_cost_fields nulls at the RPC layer --
-- a raw `select *` can never bypass the PRC:View cost gate. service_role (the RPCs' own
-- SECURITY DEFINER identity) retains full-column select.
grant select (
  id, tenant_id, bill_id, version_no, is_current, vendor_master_id, currency, match_mode, is_partial_invoice, is_consolidated_invoice,
  purchase_order_id, vendor_contract_id, tolerance_policy_id, tolerance_policy_version_no,
  quantity_tolerance_pct_snapshot, rate_tolerance_pct_snapshot, tax_tolerance_pct_snapshot, line_amount_tolerance_abs_snapshot, auto_clear_enabled_snapshot,
  has_epod_evidence, has_delivery_milestone_evidence, duplicate_fingerprint, is_duplicate_flagged, duplicate_of_case_id,
  overall_status, readiness_status, readiness_note, cancel_reason, evaluated_by, evaluated_at,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.vendor_bill_match_cases to authenticated;
grant select on app.vendor_bill_match_cases to service_role;
grant select (
  id, tenant_id, match_case_id, bill_line_id, line_no, line_type, vendor_stated_quantity, vendor_stated_uom,
  actual_cost_component_id, po_line_id, rate_version_id, evidence_quantity, evidence_uom, evidence_currency, contracted_rate_currency,
  currency_mismatch, quantity_variance_pct, uom_mismatch, po_line_quantity_variance_pct, po_line_uom_mismatch,
  line_status, notes, created_at, updated_at, record_version
) on app.vendor_bill_match_lines to authenticated;
grant select on app.vendor_bill_match_lines to service_role;
grant select (
  id, tenant_id, match_case_id, match_line_id, reason, status, raised_by_auth_user_id, raised_by,
  vendor_response, vendor_response_at, vendor_response_file_id, resolved_by_auth_user_id, resolution_note, resolved_at,
  record_version, created_by, created_at, updated_at
) on app.vendor_bill_match_disputes to authenticated;
grant select on app.vendor_bill_match_disputes to service_role;
grant select (
  id, tenant_id, match_case_id, reason, includes_duplicate_flag, status, requested_by_auth_user_id, requested_by,
  decided_by_auth_user_id, decision_note, decided_at, record_version, created_by, created_at, updated_at
) on app.vendor_bill_match_exception_approvals to authenticated;
grant select on app.vendor_bill_match_exception_approvals to service_role;
grant select on app.vendor_bill_match_events to authenticated, service_role;
grant insert, update on app.vendor_bill_match_tolerance_policies to service_role;
grant insert, update on app.vendor_bill_match_cases to service_role;
grant insert, update on app.vendor_bill_match_lines to service_role;
grant insert, update on app.vendor_bill_match_disputes to service_role;
grant insert, update on app.vendor_bill_match_exception_approvals to service_role;
grant insert on app.vendor_bill_match_events to service_role;

grant execute on function app.touch_vendor_bill_match_tolerance_policies_row() to service_role;
grant execute on function app.touch_vendor_bill_match_cases_row() to service_role;
grant execute on function app.touch_vendor_bill_match_lines_row() to service_role;
grant execute on function app.touch_vendor_bill_match_disputes_row() to service_role;
grant execute on function app.touch_vendor_bill_match_exception_approvals_row() to service_role;
grant execute on function app._record_vendor_bill_match_event(uuid, uuid, text, jsonb, uuid, text) to service_role;
grant execute on function app.check_vendor_bill_match_authority(text, uuid, uuid) to service_role;
grant execute on function app.mask_vendor_bill_match_case_cost_fields(app.vendor_bill_match_cases, boolean) to service_role;
grant execute on function app.mask_vendor_bill_match_line_cost_fields(app.vendor_bill_match_lines, boolean) to service_role;
grant execute on function app.mask_vendor_bill_match_dispute_cost_fields(app.vendor_bill_match_disputes, boolean) to service_role;
grant execute on function app.mask_vendor_bill_match_exception_approval_cost_fields(app.vendor_bill_match_exception_approvals, boolean) to service_role;
grant execute on function app.compute_vendor_bill_match_fingerprint(uuid, uuid, text, numeric) to service_role;
grant execute on function app._vendor_bill_match_pct_variance(numeric, numeric) to service_role;
grant execute on function app._score_vendor_bill_match_line(app.vendor_bill_match_lines, app.vendor_bill_match_cases) to service_role;
grant execute on function app._reroll_vendor_bill_match_case(uuid) to service_role;

grant execute on function app.create_vendor_bill_match_tolerance_policy_draft(uuid, text, numeric, numeric, numeric, numeric, boolean, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_bill_match_tolerance_policy_draft(uuid, integer, text, numeric, numeric, numeric, numeric, boolean, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.activate_vendor_bill_match_tolerance_policy(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_active_vendor_bill_match_tolerance_policy(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_tolerance_policies(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_vendor_bill_match_case(uuid, uuid, uuid, boolean, boolean, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.re_evaluate_vendor_bill_match_case(uuid, integer, uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.map_vendor_bill_match_line(uuid, integer, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.accept_vendor_bill_match_within_tolerance(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.raise_vendor_bill_match_dispute(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.record_vendor_bill_match_dispute_response(uuid, integer, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_vendor_bill_match_dispute(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.request_vendor_bill_match_exception_approval(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_bill_match_exception_approval(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_vendor_bill_match_case(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_bill_match_case(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_cases(uuid, uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_case_versions(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_case_events(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_disputes(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bill_match_exception_approvals(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_bill_match_readiness(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_bill_match_reconciliation_status(uuid, uuid) to authenticated, service_role;
