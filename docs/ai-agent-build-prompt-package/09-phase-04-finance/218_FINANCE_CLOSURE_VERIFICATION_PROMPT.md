# Prompt 218 — Finance Closure Verification

**Prompt ID:** `CG-S9-FIN-029`  
**Package document:** `CG-AABPP-FIN-218`  
**Version:** `0.10.0`  
**Runtime output:** `docs/build-log/phase-04/FINANCE_CLOSURE_REPORT.md`

Do not begin until Prompt 217 is `VERIFIED`, the active checkpoint still carries `PHASE_3_VERIFIED`, and all Finance capability, integrated-verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Phase 4 Finance runtime completeness, accounting integrity, tenant/customer/field security and readiness for Phase 5 Advanced TMS/WMS implementation.

## Required verification

1. Verify Prompts 191–217 at one repository/schema/environment checkpoint and reconcile every hierarchy/WBS/traceability/evidence link.
2. Confirm all 24 master Finance capabilities and all 24 anchors across `FIN-GL-001..004`, `FIN-AR-001..004`, `FIN-AP-001..004`, `FIN-TAX-001..004`, `FIN-CLS-001..004` and `FIN-PRF-001..004` have implementation, migration/contract/UI as relevant, tests, documentation and owner.
3. Prove verified `BillingReadinessHandoff` → accurate unique invoice → AR → receipt/allocation → subledger → balanced journal → aging/reconciliation.
4. Prove Operations actual cost/source → unique vendor bill → AP → settlement → cash/bank/subledger → balanced journal, while full Procurement/vendor/PO/advanced matching remains Step 11.
5. Prove exact decimal money, currency/rate/version/rounding/tax lineage and RPD-016 Indonesia-first current SME approval; no guessed legal rate or unsupported localization may activate.
6. Prove finance configuration, COA, fiscal period, minimum governed budget/accrual/revenue-cost-recognition/close dependencies, tax/account mappings and canonical states are versioned, compatible and source-snapshotted.
7. Prove debit equals credit, every posting is source-linked and idempotent, normal-role posted records reject direct mutation, corrections use linked reversal/adjustment, and database/service period locks govern UI/API/job/import paths.
8. Prove AR/AP/open-item/subledger/GL/bank and profitability totals reconcile; run and map all applicable `FINTEST-001..024` scenarios with no orphan.
9. Prove financial field/record policy parity across RLS/service, REST, GraphQL, UI, filter/sort/search, dashboards, reports, exports, jobs, caches, logs and support/impersonation.
10. Prove RPD-021 human approval before AI/OCR financial/legal posting; RPD-023 MFA for privileged Finance roles; RPD-025 ten-year Finance/tax retention; RPD-032 scan-before-file-access; RPD-033 REST/GraphQL parity; and RPD-038 case-specific integration/no tenant forks.
11. Confirm RPD-022 explicitly permits Supreme Admin absolute CRUD over journal/payment/audit/final records. Verify normal-role protection and best-effort warnings/evidence, but reject every tamper-proof, immutable-for-all or non-repudiation claim.
12. Prove RPD-014 Finance dashboards/reports meet live-OLTP access/query budgets, source reconciliation and asynchronous heavy-work controls.
13. Confirm Customer Portal invoice/payment/dispute UX remains Step 13; full Procurement/vendor lifecycle and PO/three-way matching remain Step 11; Phase 4 did not smuggle later-phase scope.
14. Confirm clean rebuild/upgrade, migration/type generation, CI, performance, accessibility/browser, observability, backup/recovery documentation and zero unresolved critical tenant/security/financial/data blocker.
15. Confirm no production, external-pilot, partial-GA or market-ready claim. Phase 4 is an internal gate; RPD-001/034/036 still require every major module and full validation before direct GA.

## Closure states

- `PHASE_4_VERIFIED`: every mandatory Finance runtime gate passes.
- `PHASE_4_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 5 is blocked.
- `PHASE_4_BLOCKED`: critical tenant/customer/access/security/accounting/tax/bank/file/lineage/schema/contract/evidence gate fails.
- `PHASE_4_ROLLED_BACK`: phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement/FINTEST checklist; checkpoint/schema/API/UI/access matrix; both critical Finance E2E flows; chart/period/config/tax/rate evidence; invoice/AR/receipt/allocation and bill/AP/settlement results; balance/idempotency/draft-post/lock/reversal/reconciliation proof; cash/bank/aging/profitability/report reconciliation; tenant/customer/field/file/security results; later-phase boundary audit; RPD-022 and legal/provider residual-risk disclosure; clean-build/migration/quality results; residual risks/issues; closure state/rationale; Phase 5 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_4_VERIFIED` only if all mandatory runtime checks pass. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 9 validation is `LANJUT STEP 10`.
