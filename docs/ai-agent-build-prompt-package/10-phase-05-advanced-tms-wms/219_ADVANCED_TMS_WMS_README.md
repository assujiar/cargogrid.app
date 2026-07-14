# Phase 5 — Advanced TMS and WMS Prompt Package

**Document ID:** `CG-AABPP-ATW-219`  
**Version:** `0.11.0`  
**Status:** `FINAL_FOR_STEP`

## 1. Purpose

This directory extends the verified Phase 3 shipment backbone and Phase 4 Finance contracts into high-volume multi-leg/multimodal transportation and complete warehouse execution. It covers all 23 minimum master-prompt capabilities plus the source-required Advanced Claim/Incident capability deferred from Phase 3.

Together with Step 8, it completes the advanced slices of all 24 anchors in `OPS-SHP-001..004`, `OPS-TMS-001..004`, `OPS-WMS-001..004`, `OPS-TRK-001..004`, `OPS-DOC-001..004` and `OPS-CST-001..004`. Package completion is not runtime implementation.

## 2. Runtime entry gate

Prompt 220 must stop with `PHASE_5_BLOCKED` unless the same active checkpoint proves:

- `RUNTIME_DISCOVERY_VERIFIED`;
- `RUNTIME_ARCHITECTURE_VERIFIED`;
- `PHASE_0_VERIFIED`;
- `PHASE_1_VERIFIED`;
- `PHASE_2_VERIFIED`;
- `PHASE_3_VERIFIED`;
- `PHASE_4_VERIFIED`.

The kickoff must reconcile repository/branch/HEAD/worktree ownership, schema/migration state, canonical Job Order/Shipment Order/milestone/ePOD/cost/billing-readiness contracts, Finance invoice/AP/posting interfaces, master/location/PostGIS foundations, environment, baselines and unresolved ledgers before any Phase 5 task becomes `READY`.

## 3. Required hierarchy and atomicity

Prompt 220 creates repository-specific workstreams, epics, capabilities, feature slices and atomic tasks. Prompts 221–247 are capability envelopes that must be instantiated as one approved atomic task with exact files, migrations, contracts, tests, evidence and rollback boundaries.

No task may combine unrelated transportation planning, asset/resource, integration, warehouse master, inventory ledger, task workflow, billing, portal, performance and refactor work merely for convenience.

## 4. Capability catalogue and dependency order

| Order | Prompt | Capability | Primary anchor |
|---:|---|---|---|
| 1 | 221 | Multi-leg and multimodal shipment | OPS-SHP/TMS-001..004 |
| 2 | 222 | Dispatch board | OPS-TMS-001..004 |
| 3 | 223 | Fleet and driver | OPS-TMS-001..004; Phase 6/7 boundary |
| 4 | 224 | Route and load planning | OPS-TMS-001..004 |
| 5 | 225 | First-, middle- and last-mile orchestration | OPS-SHP/TMS/TRK |
| 6 | 226 | GPS and telematics integration | OPS-TMS/TRK; RPD-038 |
| 7 | 227 | Capacity and utilization | OPS-TMS-001..004 |
| 8 | 228 | Advanced milestone and exception | OPS-TRK-001..004 |
| 9 | 229 | Warehouse and zone | OPS-WMS-001..004 |
| 10 | 230 | Bin and racking | OPS-WMS-001..004 |
| 11 | 231 | Inbound | OPS-WMS-001..004 |
| 12 | 232 | Receiving | OPS-WMS-001..004 |
| 13 | 233 | Putaway | OPS-WMS-001..004 |
| 14 | 234 | Inventory ledger | OPS-WMS/CST-001..004 |
| 15 | 235 | Lot, batch, serial and expiry | OPS-WMS-001..004 |
| 16 | 236 | Picking | OPS-WMS-001..004 |
| 17 | 237 | Packing | OPS-WMS-001..004 |
| 18 | 238 | Outbound | OPS-WMS/SHP-001..004 |
| 19 | 239 | Cycle count and adjustment | OPS-WMS/CST-001..004 |
| 20 | 240 | Label and barcode | OPS-WMS-001..004 |
| 21 | 241 | Warehouse billing | OPS-WMS/CST; Finance contract |
| 22 | 242 | Customer inventory access baseline | OPS-WMS; CPT-WHS Step 13 contract |
| 23 | 243 | High-volume operation controls | all advanced OPS families |
| 24 | 244 | Advanced claim and incident | OPS-DOC-001..004 |
| 25 | 245 | Integrated verification | all Phase 5 capabilities |
| 26 | 246 | TMS/WMS integrity and security hardening | evidence-ranked blocker repair |
| 27 | 247 | Documentation and handoff | Phase 6/8/9 contracts |
| 28 | 248 | Independent closure | `PHASE_5_VERIFIED` gate |

## 5. Binding Advanced TMS rules

- Extend the verified Phase 3 `JobOrder`, `ShipmentOrder`, lifecycle, assignment, milestone, exception, document/ePOD, actual-cost and billing-readiness roots. Do not create duplicate advanced roots or re-enter customer/cargo/service/source data.
- A shipment may contain ordered pickup, transfer, linehaul and delivery legs across land, air and sea. Each leg preserves mode, handoff, schedule, parties, location, cargo allocation, status, source and chain lineage while the Shipment Order remains canonical.
- Planning and optimization are decision support. Algorithms and heuristics must be versioned, constraint-aware, explainable and human-reviewable; no false optimality claim or autonomous AI operational commitment.
- Dispatch, capacity, route/load and milestone transitions use concurrency control, stable idempotency keys and canonical events. Duplicate, late and out-of-order telemetry never silently rewrites operational truth.
- PostGIS may provide location/distance/geofence primitives under RPD-015. Maps/GPS/telematics adapters are case-specific shared-product integrations under RPD-038; no tenant fork and no universal provider abstraction.
- Fleet/driver operational resources must reference available canonical identities. Full vendor onboarding/compliance/contract/rate lifecycle remains Step 11; employee HR records, attendance and payroll remain Step 12.
- Mobile execution remains responsive online-first PWA under RPD-004. Native apps and offline synchronization are not required; a warehouse/driver action is not committed without authoritative server acknowledgement.

## 6. Binding WMS and inventory rules

- Inventory identity includes tenant, company, warehouse, customer/owner, SKU/item, location and—when configured—lot/batch/serial/expiry/status/UOM dimensions.
- Every stock-changing event uses an idempotent inventory ledger movement. Normal roles cannot directly edit on-hand/available/reserved balances or delete ledger rows; correction uses governed adjustment/reversal movements.
- RPD-022 gives Supreme Admin absolute CRUD, including inventory and audit records. CargoGrid must not claim immutable/tamper-proof inventory; apply best available warnings, reasons, evidence and alerts while disclosing the residual risk.
- Quantity uses exact decimal UOM rules. Conversion, rounding, catch-weight if supported, reservation, allocation, availability, negative-stock and tolerance policies are versioned and auditable.
- Receiving → QC/hold → putaway → available → allocated → picked → packed → staged → loaded/shipped is canonical and source-linked. Cross-dock, partial, short, over, damage and exception flows remain explicit.
- FIFO/FEFO/lot/serial rules are configuration-driven and never inferred when data is absent. Expired/held/damaged stock cannot become available through UI-only bypass.
- Label/barcode identifiers are tenant/owner/SKU/location-aware, collision-safe and traceable; scans validate current task, location, item, lot/serial and quantity before committing.
- Customer inventory access is backend/database scoped to assigned company/account/site/warehouse/owner. Step 10 supplies the secure read contract and bounded inventory view; full Customer Portal experience remains Step 13.
- Warehouse billing emits a versioned, idempotent, source-reconciled Finance billing event/readiness handoff. It does not create or mutate invoice/AR/AP/journal directly.

## 7. Cross-cutting controls and boundaries

- Files/photos/claim evidence are private, malware-scanned before availability and served by short-lived signed URL under record/customer scope.
- REST and GraphQL ship together from shared services with equivalent authentication, authorization, field policy, rate limit, idempotency, audit and version governance.
- Realtime is limited to justified active dispatch/task/inventory signals. No global shipment or warehouse subscription.
- Large import/export, wave/task generation, planning, telemetry ingestion, label generation, inventory reconciliation and billing batches use the PostgreSQL durable job framework with chunking, retry, DLQ, cancellation and evidence.
- High-volume lists and ledgers use selective queries, server filtering/sort/search, cursor pagination and tenant-aware indexes. RPD-014 reporting controls and target-volume query/load tests are mandatory.
- Full Procurement/vendor lifecycle remains Step 11; HRIS/employee depth Step 12; full Customer Portal Step 13; predictive/AI automation and enterprise integration depth Step 14.
- No external pilot, partial-GA, production-ready or market-ready claim is allowed. Phase 5 is an internal gate; RPD-001/034/036 still require all modules and full validation before direct GA.

## 8. Mandatory Phase 5 evidence

The runtime phase must preserve at least: canonical root/leg/handoff lineage; planning constraints/version/override; capacity and dispatch concurrency; telemetry source/order/replay evidence; warehouse/location hierarchy; inbound/receiving/putaway/pick/pack/outbound task chain; exact inventory movement/balance/reservation equations; lot/serial/expiry and FIFO/FEFO evidence; scan/label integrity; cycle-count/adjustment approval; warehouse billing-to-Finance lineage; customer inventory isolation; claim/file controls; clean rebuild/migration/CI; target-volume performance; and residual-risk ownership.

The critical UAT flow `WMS Inbound → Putaway → Inventory Ledger → Pick → Pack → Outbound`, the Delivery-plan `OPS-WMS-US-001` scenario and Phase 5 WMS/TMS scan/task/ledger/load/integration gates are mandatory inputs to Prompt 245 and closure.

## 9. Runtime states

`PHASE_5_NOT_STARTED`, `PHASE_5_IN_PROGRESS`, `PHASE_5_BLOCKED`, `PHASE_5_PARTIALLY_COMPLETE`, `PHASE_5_VERIFIED`, `PHASE_5_ROLLED_BACK`.

Only Prompt 248 may set `PHASE_5_VERIFIED`.

## 10. Package completion

This package is complete when files 219–248 exist, Prompts 221–247 contain all 36 mandatory fields, controls/coverage/status/manifest are updated, structural/dependency/scope validation pass, and the exact next package-generation command is `LANJUT STEP 11`.
