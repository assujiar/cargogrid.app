# Phase 4 → Phase 5/6/8/9 Downstream Contracts

**Produced by:** `CG-S9-FIN-028` (Prompt 217 — Finance Documentation and Handoff), per Prompt 217 §20 task 4: "Define Step 10/11/13 contracts and explicit deferred boundaries" (package-step numbering `10`/`11`/`13` = phase-directory `10-phase-05-advanced-tms-wms`/`11-phase-06-procurement-vendor`/`13-phase-08-customer-portal-loyalty`, i.e. Phase 5/Phase 6/Phase 8 in this repository's own phase numbering; Phase 9 — Intelligence/Enterprise — is added here too since it is the other real future consumer of Finance's own Dashboard/Reports layer, disclosed rather than silently omitted).

**Scope note:** unlike Commercial's own single `JOB_ORDER_HANDOFF_CONTRACT.md` (one immutable snapshot, one downstream consumer) or Operations' own three-surface `OPERATIONS_DOWNSTREAM_CONTRACTS.md`, Finance's relationship to later phases is **asymmetric** — one real schema-extension boundary (Phase 6), one real but deliberately-unbuilt visibility contract (Phase 8), and two phases with **no current dependency relationship at all** (Phase 5, Phase 9), disclosed explicitly rather than each silently omitted.

---

## 1. Phase 6 (Procurement/Vendor) — Vendor Bill and AP extension boundary

**Source of truth:** `supabase/migrations/20260729140000_create_finance_vendor_bill.sql` (`FIN-200`) and `supabase/migrations/20260729130000_create_finance_accounts_payable.sql` (`FIN-199`). This document explains and exemplifies that contract; it does not redefine it — if this document and the migration/contract file ever disagree, the migration/contract file is authoritative.

### 1.1 What already exists (extend in place, do not fork)

- **`app.finance_vendor_bills`/`app.finance_vendor_bill_lines`** (`FIN-200`) — a governed draft→submitted→approved→posted→void vendor bill, one-to-one with a real, approved Operations actual-cost record (`app.shipment_actual_costs`, `OPS-178`) and a real vendor reference. `vendor_master_id uuid not null references app.master_records (id)` with `master_type_code = 'vendor'` — **vendor identity reuses Platform Core's own generic Master Data registry (`app.master_records`, `PLT-1xx`), never a Finance-specific or Procurement-specific vendor table.** Phase 6 should extend `app.master_records` (a new `master_type_code`-scoped detail table if vendor-specific fields are needed) rather than create a competing vendor entity.
- **`app.finance_ap_open_items`** (`FIN-199`) — the AP mirror of `FIN-196`'s own AR open items; `post_finance_ap_open_item`, `apply_finance_ap_settlement`/`reverse_finance_ap_settlement`, `place_finance_ap_hold`/`release_finance_ap_hold`, `get_finance_ap_exposure_summary`.
- **`app.finance_settlements`** (`FIN-201`) — the AP payment-execution lifecycle (prepare → submit → approve → execute → post), posting a real subledger batch (debit AP-control, credit cash) via the identical `app.post_finance_subledger_batch` (`FIN-202`) primitive every source-document capability shares.
- **AP aging** (`FIN-210`) — `app.get_finance_aging_summary(..., 'ap', ...)` already works against real AP data; this checkpoint's own integrated-verification fixture (`FIN-215`) deliberately left AP untouched and confirmed the widget reports an honest, non-fabricated *empty* result for a tenant with none — Phase 6's first real vendor bill will populate it with zero further Finance-side change needed.

### 1.2 What Phase 6 must build fresh (no existing table to extend)

- **Purchase order / requisition** — no `app.purchase_orders` or equivalent exists anywhere in this repository. `app.finance_vendor_bills` originates only from an already-approved Operations actual cost, never from a pre-commitment document; a real procurement workflow (PO → goods/service receipt → three-way match → bill) is entirely Phase 6's own design.
- **Three-way match** — `FIN-200`'s own variance check (`variance_status`: `within_tolerance`/`requires_approval`) compares the vendor-stated bill amount against the linked actual-cost total only — a two-way match (bill vs. cost), never a three-way match against a purchase order, since no PO exists. Phase 6 needing true three-way match must design a new comparison, not extend this one.
- **Vendor-specific master data (payment terms defaults, bank details, tax registration)** — `app.master_records` carries only the generic entity shape every master-type shares (`PLT-1xx`); no vendor-specific detail table exists. Phase 6 owns designing this extension.

### 1.3 Disclosed gap: no Finance-native job-costed vendor spend view

`FIN-212`'s own Job/Customer/Service Profitability reads cost exclusively from Operations' own governed actual-cost evidence (`OPS-178`), **never** from `app.finance_vendor_bills` — `app.finance_vendor_bills` carries no Job Order/Shipment Order linkage of its own (only `actual_cost_id`/`shipment_order_id`, one level removed). A future "vendor spend by job" report would need to join through the actual-cost record, not query vendor bills directly. Disclosed as a real, current bound, not a defect.

---

## 2. Phase 8 (Customer Portal) — Invoice and payment visibility contract (deliberately deferred, not built)

**Source of truth:** every Finance capability's own §15/§26 ("Customer Portal Finance views remain Step 13") and `FIN-214`'s own `docs/standards/FINANCE_FIELD_POLICY_MATRIX.md` §5 ("no Customer Portal exists yet ... this document cannot audit parity for a surface that has not been built").

### 2.1 What exists that Phase 8 will eventually read

- **`app.finance_invoices`** (`FIN-197`) — a customer's own issued invoices are already `customer_account_id`-scoped and status-lifecycled (`draft`→`issued`→`void`); a future customer-facing view would read only `status='issued'` rows for the requesting customer's own `customer_account_id`.
- **`app.finance_ar_open_items`** (`FIN-196`) — a customer's own outstanding balance/payment status per invoice.
- **`app.finance_receipts`/`app.finance_receipt_allocations`** (`FIN-198`) — a customer's own payment history against their invoices.

### 2.2 What Phase 8 must build — no shortcut exists

**No RLS policy, RPC, or contract in this repository currently authorizes a `customer_user` layer to read any Finance table or function.** Every Finance RPC checks `FIN:View`/`FIN:Edit`/`FIN:Approve`/`FIN:View margin`/`FIN:Export` — all internal-tenant-user permission actions; none of them is reachable by a Customer Portal identity today, and none should be extended to allow it without a dedicated field-projection layer. Phase 8 must design and build:

1. A **customer-scoped read RPC** (mirroring Operations' own `app.lookup_public_shipment_tracking`, `OPS-180` — the one precedent for a deliberately narrow, sanitized, public/customer-facing projection over internal data) that returns only invoice number, amount, currency, status, issue/due date, and payment status — never internal cost/margin/journal/bank data, never a raw `finance_invoices`/`finance_ar_open_items` row.
2. A **customer-identity-to-`customer_account_id` binding** — no such binding exists anywhere yet (Commercial's own `app.accounts` is the internal-tenant-user-facing customer record; nothing links it to a `customer_user` auth identity).
3. A `FINANCE_REGISTRY`-equivalent classification pass for whatever new customer-facing fields this view introduces, per the adoption gate `FIN-214` established (`scripts/data-classification/check-registry.ts`).

### 2.3 Explicit non-goal

This document does **not** propose a schema or API for the Phase 8 view above — Prompt 217 §22's own "mark an unsupported feature explicitly deferred with owner/phase/contract; do not fabricate completion" applies directly. Everything in §2.2 is a named requirement, not a preview of Phase 8's own design.

---

## 3. Phase 5 (Advanced TMS/WMS) — no direct dependency (disclosed boundary)

Finance has **no direct dependency relationship with Phase 5** in either direction. Phase 5 extends Operations' own Shipment Order/mode-profile/resource-assignment tables (per `OPERATIONS_DOWNSTREAM_CONTRACTS.md` §2) — it does not touch invoicing, AR/AP, GL, or any Finance table. Finance's own cost input (`OPS-178`'s actual cost) is Phase 5-adjacent only insofar as Phase 5 may eventually add new cost-generating activity (multi-leg routing, warehouse operations) that flows into the *same* `app.shipment_actual_costs` table Finance already reads from — no new Finance-side contract is needed for that; Finance already reads whatever `OPS-178`'s own table contains, regardless of which Operations/Phase-5 capability wrote it. Disclosed explicitly here so a future agent does not assume a missing contract document represents an oversight.

## 4. Phase 9 (Intelligence/Enterprise) — future consumer, no contract built yet

Finance's own Dashboard and Reports layer (`FIN-213`) — six governed widgets, a shared `report_types` catalogue, an async export path — is the natural future data source for cross-domain analytics/BI a Phase 9 Intelligence/Enterprise capability would build. **No such consumer exists yet, and no contract has been designed for one.** `FIN-213`'s own reports already reuse the identical shared `report_types`/`report_runs` infrastructure Commercial (`COM-159`) and Operations (`OPS-183`) also register their own codes into — a future Phase 9 aggregation layer reading across all three registered code sets would need no new Finance-side table, only its own read logic. Disclosed as a real, plausible future dependency, not a built one.
