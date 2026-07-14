# Phase 6 — Procurement and Vendor Management Prompt Package

**Document ID:** `CG-AABPP-PRC-249`  
**Version:** `0.12.0`  
**Status:** `FINAL_FOR_STEP`

## 1. Purpose

This directory extends the single canonical vendor/rate foundation from Commercial, the shipment/resource/actual-cost lineage from Operations and Advanced TMS/WMS, and the vendor-bill/AP contracts from Finance into a complete Procurement and Vendor Management domain. Package completion is not runtime implementation.

It covers all 17 minimum master-prompt capabilities and all 20 anchors in `PRC-VND-001..004`, `PRC-ASM-001..004`, `PRC-RTE-001..004`, `PRC-SRC-001..004` and `PRC-POI-001..004`.

## 2. Runtime entry gate

Prompt 250 must stop with `PHASE_6_BLOCKED` unless the same active checkpoint proves:

- `RUNTIME_DISCOVERY_VERIFIED`;
- `RUNTIME_ARCHITECTURE_VERIFIED`;
- `PHASE_0_VERIFIED` through `PHASE_5_VERIFIED`.

The kickoff must reconcile repository/branch/HEAD/worktree ownership; schema/migrations; canonical vendor/service/rate ownership; customer/opportunity/costing source; shipment/leg/resource/actual-cost/ePOD lineage; Phase 5 capacity/assignment contracts; Finance vendor-bill/AP/posting interfaces; file, approval, notification, job, API and access primitives; environment; baselines; and unresolved ledgers before any Phase 6 task becomes `READY`.

## 3. Required hierarchy and atomicity

Prompt 250 creates repository-specific workstreams, epics, capabilities, feature slices and atomic tasks. Prompts 251–270 are capability envelopes that must be instantiated as one approved atomic task with exact files, migrations, contracts, tests, evidence and rollback boundaries.

No task may combine unrelated vendor identity, compliance, financial-field security, rates, sourcing, operational assignment, purchasing, invoice matching, portal, reporting and refactor work merely for convenience.

## 4. Capability catalogue and dependency order

| Order | Prompt | Capability | Primary anchor |
|---:|---|---|---|
| 1 | 251 | Vendor registration and onboarding | PRC-VND-001..004 |
| 2 | 252 | Vendor assessment | PRC-ASM-001..004 |
| 3 | 253 | Compliance and document expiry | PRC-ASM/VND-001..004 |
| 4 | 254 | Vendor banking and tax security | PRC-VND/ASM; Finance contract |
| 5 | 255 | Vendor rate and pricelist | PRC-RTE-001..004 |
| 6 | 256 | Sourcing | PRC-SRC-001..004 |
| 7 | 257 | Procurement RFQ | PRC-SRC/RTE-001..004 |
| 8 | 258 | Vendor comparison | PRC-RTE/SRC-001..004 |
| 9 | 259 | Procurement approval | all PRC families |
| 10 | 260 | Purchase order | PRC-POI-001..004 |
| 11 | 261 | Vendor contract | PRC-POI/VND-001..004 |
| 12 | 262 | Vendor capacity and availability | PRC-SRC-001..004 |
| 13 | 263 | Vendor assignment | PRC-SRC/POI; OPS-TMS contract |
| 14 | 264 | Vendor performance | PRC-POI/ASM-001..004 |
| 15 | 265 | Vendor invoice matching | PRC-POI-001..004; FIN-AP contract |
| 16 | 266 | Procurement dashboard and reports | all PRC families |
| 17 | 267 | Optional vendor portal | PRC-VND/RTE/SRC/POI; BP-A08 |
| 18 | 268 | Integrated verification | all Phase 6 capabilities |
| 19 | 269 | Procurement integrity/security/financial hardening | evidence-ranked blocker repair |
| 20 | 270 | Documentation and handoff | Phase 7/8/9 contracts |
| 21 | 271 | Independent closure | `PHASE_6_VERIFIED` gate |

## 5. Binding vendor identity and governance rules

- Extend the single canonical vendor/service/rate foundation adopted in Phase 2. Do not create a second vendor master, rate store, service/coverage truth or vendor-specific tenant fork.
- Vendor identity is tenant-scoped and may include legal/tax/contact/address, category, services, coverage, fleet/warehouse references, payment term, bank accounts, compliance, lifecycle and source lineage. Fuzzy duplicate review never auto-merges legal entities.
- Self-registration and the external vendor surface are tenant-configurable under BP-A08, never globally public by default. Invitation/intake tokens are scoped, expiring and non-authoritative; onboarding approval creates or links the canonical vendor.
- Do not invent a fifth access layer. External vendor identity/scope must use an approved Platform membership/portal-surface ADR and remain isolated from Layer 4 customer data. If that runtime ownership is unresolved, block the vendor-portal task while internal procurement continues.
- Vendor activation, suspension, blacklist, reactivation and archive follow canonical states, reason, evidence, approval and downstream impact checks. Tenant labels may vary; canonical semantics do not.
- Vendor-owned fleet, driver, warehouse and capacity references do not duplicate Phase 5 operational roots. Employee truth, attendance and payroll remain Step 12.

## 6. Binding compliance, rate and sourcing rules

- Vendor documents are private, classified and malware-scanned before release; access uses short-lived signed URLs, field/record scope and download audit. Expiry, legal hold and RPD-025 retention are explicit.
- Tax, bank, payment-term and beneficial/legal identity fields are masked and purpose-bound. Sensitive changes require maker-checker approval, current authorization, privileged MFA where applicable, before/after evidence and downstream hold/reverification.
- Statutory or provider verification uses current dated Finance/legal SME evidence. RPD-016 prevents guessed tax behavior; RPD-038 requires case-specific bank, e-sign or compliance adapters in the shared product codebase.
- Rates/pricelists retain vendor, service, mode, route/zone/distance, fleet/container, weight/volume tier, currency, tax, surcharge, minimum charge, UOM, validity, quotation/source and approval versions. Exact decimal/conversion/rounding rules apply.
- RPD-040 protects the applied source/config/rate version on active costing, shipment, PO and invoice-match records. Reprice or migration is explicit, authorized and auditable.
- Sourcing, RFQ, comparison and recommendation are decision support. Criteria, exclusions, normalization and score/version must be explainable; an authorized human selects/approves the vendor. AI recommendation depth remains Step 14.
- Vendor eligibility requires the configured intersection of active status, service/coverage, compliance, contract/rate validity, capacity/availability, risk/blacklist and operational constraints. Overrides require reason, approval, expiry and evidence.

## 7. Binding purchasing, Operations and Finance boundaries

- Purchase orders and vendor contracts are versioned commitments with exact quantity/UOM, value/currency/tax/rounding, source request/RFQ/quote/rate, service/coverage/SLA, approval, effective period and amendment/cancellation lineage.
- An approved PO or contract does not post a journal, create AP, execute settlement or change cash. Finance remains owner of vendor bill, AP, posting, period lock, reversal, settlement and reconciliation.
- Vendor assignment extends Phase 3/5 shipment/resource contracts and preserves shipment/leg/task, selected vendor/rate/contract/capacity, override and acceptance lineage. Procurement governs eligibility; Operations governs execution/custody/status.
- Vendor invoice matching extends the canonical Phase 4 vendor bill. It may reconcile invoice → PO/contract → shipment/leg/service receipt/ePOD → actual cost → rate/tax/payment-term evidence, but must not create a duplicate invoice/AP root.
- Matching supports configured two-, three- or multi-source rules, tolerances, partials, duplicates, disputes and approvals. A match result is a source-linked Finance input; only Finance may post or pay.
- Performance metrics come from versioned operational, compliance, sourcing, claim, customer complaint and Finance evidence. Formulas, windows, exclusions and manual adjustments are governed and explainable.

## 8. Cross-cutting controls and boundaries

- REST and GraphQL ship together from shared services with equivalent authentication, authorization, field policy, rate limit, idempotency, audit and version governance under RPD-033.
- Large vendor/rate imports, RFQ invitations, comparisons, expiry evaluation, scorecards, reports and match batches use PostgreSQL durable jobs with chunking, retry, DLQ, cancellation and reconciliation.
- High-volume lists use selective queries, server filtering/sort/search, cursor pagination, tenant-aware indexes and RPD-014 live-OLTP budgets. Materialized views/replicas are introduced only after measured thresholds.
- Responsive online-first PWA is the baseline under RPD-004. No native/offline sync, client-only commitment or fake success.
- RPD-022 grants Supreme Admin absolute CRUD, including vendor/compliance/PO/match/audit records. Do not claim immutability/tamper proof; preserve normal-role controls and disclose residual risk.
- Full HRIS/Ticketing remains Step 12, Customer Portal/Loyalty Step 13 and predictive/AI/enterprise depth Step 14. No external pilot, partial-GA, production-ready or market-ready claim is allowed.

## 9. Mandatory Phase 6 evidence

The runtime phase must preserve at least: canonical vendor/rate ownership and no-reentry lineage; duplicate/legal identity review; onboarding/document/assessment/compliance approval; bank/tax masking and change control; exact rate/tier/surcharge/validity snapshots; sourcing/RFQ/comparison/approval; PO/contract/amendment; capacity/assignment/acceptance; vendor performance source reconciliation; invoice match/tolerance/dispute/Finance handoff; optional portal isolation; REST/GraphQL parity; clean build/migration/CI; target-volume performance; and residual-risk ownership.

The critical UAT flow `Vendor Registration → Mandatory Document Verification → Assessment/Approval → Rate → RFQ/Comparison → PO/Contract → Vendor Assignment → Actual Cost/ePOD → Vendor Invoice Match → AP Handoff`, Delivery-plan `PRC-VND-US-001`, and `FINTEST-016` are mandatory inputs to Prompt 268 and closure.

## 10. Runtime states

`PHASE_6_NOT_STARTED`, `PHASE_6_IN_PROGRESS`, `PHASE_6_BLOCKED`, `PHASE_6_PARTIALLY_COMPLETE`, `PHASE_6_VERIFIED`, `PHASE_6_ROLLED_BACK`.

Only Prompt 271 may set `PHASE_6_VERIFIED`.

## 11. Package completion

This package is complete when files 249–271 exist, Prompts 251–270 contain all 36 mandatory fields, controls/coverage/status/manifest are updated, structural/dependency/scope validation pass, and the exact next package-generation command is `LANJUT STEP 12`.
