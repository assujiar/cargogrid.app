# Prompt 165 — Commercial Closure Verification

**Prompt ID:** `CG-S7-COM-024`  
**Package document:** `CG-AABPP-COM-165`  
**Version:** `0.8.0`  
**Runtime output:** `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md`

Do not begin until Prompt 164 is `VERIFIED`, the active checkpoint still carries `PHASE_1_VERIFIED`, and all Commercial capability, verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Commercial runtime completeness, tenant/security/financial/data integrity and readiness for Phase 3 Operations implementation.

## Required verification

1. Verify Prompts 143–164 at one repository/schema/environment checkpoint and reconcile every hierarchy/WBS/traceability/evidence link.
2. Confirm all 19 capabilities and all 20 `COM-*-001..004` requirements have implementation, migration/contract/UI as relevant, positive/negative/regression evidence, documentation and owner.
3. Prove lead → prospect → contact/activity/CRM → opportunity → costing → rate lookup → margin → quotation/version → approval → customer acceptance → customer/account/contract/credit flow.
4. Prove customer, contact, address, cargo, service, rate and quote data is referenced or governed-snapshotted without silent re-entry; every override is permissioned, reasoned and audited.
5. Prove exact money/rounding/currency, restricted cost/margin/discount/credit fields, quote locks, acceptance actor/version evidence and duplicate-safe conversion.
6. Prove the canonical basic vendor/service/rate foundation is single-owned and Phase 6-extensible; full procurement scope is absent.
7. Prove the versioned idempotent `JobOrderDraftInput` handoff, complete source/version lineage, retry recovery and no duplicate downstream intent while Job Order ownership remains Phase 3.
8. Prove Commercial dashboard/report reconciliation, RPD-014 live-query budgets, private scanned exports/documents, REST/GraphQL parity and cross-tenant/access negative matrices.
9. Confirm clean rebuild/upgrade, migrations/RLS/seeds/types, CI, performance, accessibility, observability, documentation/runbooks and no critical blocker.
10. Confirm RPD-022, RPD-001, RPD-034 and RPD-036 disclosures: no tamper-proof claim, no pilot/partial-GA claim and no runtime/production status inflation.

## Closure states

- `PHASE_2_VERIFIED`: every mandatory Commercial runtime gate passes.
- `PHASE_2_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 3 is blocked.
- `PHASE_2_BLOCKED`: critical tenant/access/security/financial/data/lineage/schema/contract/evidence gate fails.
- `PHASE_2_ROLLED_BACK`: phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; critical Commercial E2E evidence; money/approval/acceptance/conversion/no-reentry/lineage results; vendor/rate ownership and Job Order handoff compatibility; dashboard/report reconciliation; accepted-risk disclosure; clean-build/migration/quality results; forbidden-scope audit; residual risks/issues; closure state/rationale; Phase 3 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_2_VERIFIED` only if all mandatory runtime checks pass. This is not production/market/GA status. For package generation, the exact next command after Step 7 validation is `LANJUT STEP 8`.
