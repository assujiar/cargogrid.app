# Prompt 188 — Operations Closure Verification

**Prompt ID:** `CG-S8-OPS-022`  
**Package document:** `CG-AABPP-OPS-188`  
**Version:** `0.9.0`  
**Runtime output:** `docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md`

Do not begin until Prompt 187 is `VERIFIED`, the active checkpoint still carries `PHASE_2_VERIFIED`, and all Operations capability, verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Operations MVP runtime completeness, tenant/customer/security/financial/data integrity and readiness for Phase 4 Finance implementation.

## Required verification

1. Verify Prompts 168–187 at one repository/schema/environment checkpoint and reconcile every hierarchy/WBS/traceability/evidence link.
2. Confirm all 17 capabilities and all twenty Phase 3 anchors across `OPS-SHP`, `OPS-TMS`, `OPS-TRK`, `OPS-DOC` and `OPS-CST` have implementation, migration/contract/UI as relevant, tests, documentation and owner.
3. Prove accepted quote → idempotent Job Order → Shipment Order/lifecycle → land/air/sea baseline → assignment/basic dispatch → milestone/exception → documents/ePOD → actual cost/profitability → billing readiness.
4. Prove customer, contact, address, cargo, service, rate, quote, price and credit data is referenced or governed-snapshotted without silent re-entry; every override is permissioned, reasoned and audited.
5. Prove canonical lifecycle/event history, event time versus received time, duplicate/out-of-order handling, assignment conflicts and deterministic readiness gates.
6. Prove private malware-scanned files, online-first ePOD photo/signature/receiver/geolocation/timestamp, review/revision, customer isolation and signed access.
7. Prove exact actual cost and operational profitability with source/version lineage and restricted field policy; confirm no vendor bill/AP/GL/tax/payment posting exists.
8. Prove minimal public/customer tracking resists enumeration and cross-customer access; confirm full Customer Portal is absent.
9. Prove live dashboard/report reconciliation, RPD-014 query budgets, REST/GraphQL parity and the versioned idempotent Phase 4 billing-readiness handoff.
10. Confirm `OPS-WMS-001..004` and full WMS, multi-leg/multimodal, advanced dispatch/route/load/capacity, GPS/telematics, full claims, full vendor/fleet/driver lifecycle or other Step 10/11/13 capability remain excluded from Phase 3.
11. Confirm clean rebuild/upgrade, migrations/RLS/seeds/types, CI, performance, accessibility, observability, documentation/runbooks and no critical blocker.
12. Confirm RPD-004, RPD-022, RPD-001, RPD-034 and RPD-036 disclosures: online-first PWA, no tamper-proof claim, no pilot/partial-GA claim and no runtime/production status inflation.

## Closure states

- `PHASE_3_VERIFIED`: every mandatory Operations runtime gate passes.
- `PHASE_3_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 4 is blocked.
- `PHASE_3_BLOCKED`: critical tenant/customer/access/security/financial/data/file/lineage/schema/contract/evidence gate fails.
- `PHASE_3_ROLLED_BACK`: phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; critical quote-to-billing-readiness E2E evidence; lifecycle/milestone/exception/dispatch results; ePOD/file/customer tracking security; cost/profitability and billing-readiness reconciliation; forbidden advanced-scope audit; accepted-risk disclosure; clean-build/migration/quality results; residual risks/issues; closure state/rationale; Phase 4 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_3_VERIFIED` only if all mandatory runtime checks pass. This is not production/market/GA status. For package generation, the exact next command after Step 8 validation is `LANJUT STEP 9`.
