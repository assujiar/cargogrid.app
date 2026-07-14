# Phase 4 — Finance MVP Prompt Package

**Document ID:** `CG-AABPP-FIN-189`  
**Version:** `0.10.0`  
**Status:** `FINAL_FOR_STEP`

## 1. Purpose

This directory converts verified Operations billing evidence and actual cost into controlled billing, receivables, payables, cash and double-entry accounting. It covers the 24 master-prompt Finance MVP capabilities and all 24 anchors in `FIN-GL-001..004`, `FIN-AR-001..004`, `FIN-AP-001..004`, `FIN-TAX-001..004`, `FIN-CLS-001..004` and `FIN-PRF-001..004`.

Package completion is not runtime implementation. Every prompt must be instantiated against one authoritative repository checkpoint and independently verified.

## 2. Runtime entry gate

Prompt 190 must stop with `PHASE_4_BLOCKED` unless the same active checkpoint proves:

- `RUNTIME_DISCOVERY_VERIFIED`;
- `RUNTIME_ARCHITECTURE_VERIFIED`;
- `PHASE_0_VERIFIED`;
- `PHASE_1_VERIFIED`;
- `PHASE_2_VERIFIED`;
- `PHASE_3_VERIFIED`.

The kickoff must reconcile repository, branch, HEAD, worktree ownership, schema/migration state, Platform/Commercial/Operations contracts, `BillingReadinessHandoff`, actual-cost evidence, environment, baseline and unresolved ledgers before any Finance task becomes `READY`.

## 3. Required hierarchy and atomicity

Prompt 190 creates repository-specific workstreams, epics, capabilities, feature slices and atomic tasks. Prompts 191–217 are capability envelopes that must be instantiated as one approved atomic task with exact files, migrations, tests, evidence and rollback boundaries.

No task may combine unrelated schema, access, posting, UX, migration and refactor work merely for convenience. Cross-capability changes require explicit dependencies and separately verifiable ledger entries.

## 4. Capability catalogue and dependency order

| Order | Prompt | Capability | Primary anchor |
|---:|---|---|---|
| 1 | 191 | Finance configuration | FIN-GL/CLS/TAX configuration slices |
| 2 | 192 | Chart of accounts | FIN-GL-001..004 |
| 3 | 193 | Fiscal period | FIN-CLS-001..004 |
| 4 | 194 | Currency and exchange rate | FIN-TAX/GL |
| 5 | 195 | Tax baseline | FIN-TAX-001..004 |
| 6 | 196 | Accounts receivable | FIN-AR-001..004 |
| 7 | 197 | Invoice | FIN-AR-001..004 |
| 8 | 198 | Receipt and payment allocation | FIN-AR/TAX |
| 9 | 199 | Accounts payable | FIN-AP-001..004 |
| 10 | 200 | Vendor bill | FIN-AP-001..004 |
| 11 | 201 | Settlement | FIN-AP/TAX |
| 12 | 202 | Subledger | FIN-GL/AR/AP |
| 13 | 203 | Double-entry journal | FIN-GL-001..004 |
| 14 | 204 | Posted-journal integrity | FIN-GL-001..004 |
| 15 | 205 | Draft-versus-posted state | FIN-GL/AR/AP |
| 16 | 206 | Reversal and adjustment | FIN-GL-001..004 |
| 17 | 207 | Period lock | FIN-CLS-001..004 |
| 18 | 208 | Idempotent posting | FIN-GL/AR/AP |
| 19 | 209 | Reconciliation | FIN-TAX/GL/AR/AP |
| 20 | 210 | Aging | FIN-AR/AP |
| 21 | 211 | Cash and bank | FIN-TAX-001..004 |
| 22 | 212 | Job/customer/service profitability | FIN-PRF-001..004; OPS-CST finance depth |
| 23 | 213 | Finance dashboard and reports | all six FIN families |
| 24 | 214 | Financial field-level security | all six FIN families |
| 25 | 215 | Integrated verification | all Phase 4 capabilities |
| 26 | 216 | Finance integrity and security hardening | evidence-ranked blocker repair |
| 27 | 217 | Documentation and handoff | Phase 5/6/8 contracts |
| 28 | 218 | Independent closure | `PHASE_4_VERIFIED` gate |

## 5. Binding Finance rules

- Consume the versioned Operations `BillingReadinessHandoff` and actual-cost/source manifest without re-entering customer, job, shipment, ePOD, document, charge, rate, currency or cost data. Overrides require authority, reason and audit.
- Money uses exact decimal types, explicit currency, versioned rounding and deterministic calculation order. Floating point is forbidden for persisted or compared financial amounts.
- Every posting is source-linked, balanced, idempotent, period-aware and reconstructible. Debit must equal credit per journal and required balancing dimension.
- Draft records may be edited under workflow and concurrency controls. For normal roles, posted invoices, bills, allocations, settlements and journals cannot be silently edited or deleted; correction uses governed reversal, adjustment, credit/debit note or re-posting.
- RPD-022 is an explicit exception: Supreme Admin has absolute CRUD, including journal, payment, audit and final records. Therefore CargoGrid must never claim tamper-proof or absolute immutability. Every available preventive, warning, reason, evidence and alert control must still be applied.
- Period lock is enforced in the database/service posting boundary, not only in the UI. Governed reopen/unlock requires permission, approval, reason, scope and audit.
- Posting, invoice generation, payment allocation, settlement, import and retry paths require stable idempotency keys and collision-safe uniqueness.
- Subledger-to-GL, AR-to-invoice/receipt, AP-to-bill/settlement and bank-to-cash reconciliation must be explainable to source/version level.
- Tax is Indonesia-first and configurable under RPD-016. PPN/VAT and withholding behavior, rates, documents and effective dates must be verified by current legal/finance/tax SMEs before activation; prompts must not invent legal rates or advice.
- Finance configuration includes the minimum governed budget, accrual, revenue/cost-recognition and close dependencies required by `FIN-CLS-001..004`; unsupported depth must be blocked and recorded, not silently simulated.
- Vendor Bill may reference verified Operations vendor/resource and actual cost. Full vendor onboarding, PO/contract lifecycle, advanced three-way matching and sourcing remain Step 11.
- Customer invoice/payment visibility and disputes inside the full Customer Portal remain Step 13; Phase 4 exposes governed contracts and internal Finance UX only.
- Bank, payment gateway, e-invoice and tax integrations are case-specific shared-product adapters under RPD-038. No tenant source fork and no unapproved provider abstraction.
- AI/OCR may assist extraction under RPD-021 but cannot autonomously approve or post invoices, bills, payments, tax or journals.
- Dashboard/report queries obey RPD-014: permission-safe live OLTP reads, timeouts, pagination, caching, query budgets and read replicas only when measured scale requires them.
- REST and GraphQL are delivered together from shared services with equivalent authentication, authorization, field policy, idempotency, rate limit, audit and version governance.
- Finance/tax records follow the ten-year retention baseline in RPD-025, subject to legal hold and approved deletion governance; RPD-022 residual risk remains disclosed.
- No external pilot, partial-GA or production-ready claim is allowed. Phase 4 is an internal delivery gate; direct GA still requires all modules and RPD-036 full validation.

## 6. Mandatory Finance evidence

The runtime phase must preserve at least: source/version lineage; exact money and exchange-rate evidence; tax-rule/version/SME approval; chart/period/posting configuration; balanced journal proof; draft/post lifecycle; lock/reopen evidence; idempotency replay; reversal chain; AR/AP aging; receipt/allocation and settlement reconciliation; bank reconciliation; profitability reconciliation; RLS/RBAC/field/record negative tests; RPD-022 disclosure; clean migration/build/CI; and residual-risk ownership.

All applicable `FINTEST-001..024` scenarios from the Delivery plan are mandatory inputs to Prompt 215 and closure.

## 7. Runtime states

`PHASE_4_NOT_STARTED`, `PHASE_4_IN_PROGRESS`, `PHASE_4_BLOCKED`, `PHASE_4_PARTIALLY_COMPLETE`, `PHASE_4_VERIFIED`, `PHASE_4_ROLLED_BACK`.

Only Prompt 218 may set `PHASE_4_VERIFIED`.

## 8. Package completion

This package is complete when files 189–218 exist, Prompts 191–217 contain all 36 mandatory fields, controls/coverage/status/manifest are updated, structural and scope validation pass, and the exact next package-generation command is `LANJUT STEP 10`.
