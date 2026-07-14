# Prompt 215 — Finance Integrated Verification

**Prompt ID:** `CG-S9-FIN-026`  
**Package document:** `CG-AABPP-FIN-215`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-215.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-026` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Verification; Epic: Phase 4 Critical Flow Evidence; Capability: Integrated Finance Verification; Feature slice: 24-capability reconciliation, FINTEST, E2E, isolation, posting integrity and boundary proof; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Independently verify all Finance capabilities at one repository/schema/environment checkpoint before hardening.

## 5. Business value

Detect cross-capability defects that isolated task tests miss and produce evidence fit for Finance closure.

## 6. Source requirement

All 24 Phase 4 capabilities; all 24 FIN anchors; `FINTEST-001..024`; critical Finance E2E flows. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..214 all `VERIFIED` at the same active checkpoint. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-216..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Read/verify only except separately authorized bounded repair tasks; inspect migrations, constraints, RLS, posting functions, locks, correction chains and reconciliation snapshots.

## 14. API impact

Verify REST/GraphQL parity, idempotency, error/access semantics, compatibility and source lineage across every Finance operation. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Run role-based journeys for Finance Admin/Manager, Accounting, Billing, AR, AP, Treasury, Management and denied actors with complete states/accessibility. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Verify tenant/customer/field/record isolation, MFA/support/impersonation, bank/tax/file security, normal-role posted protection and explicit RPD-022 limitations. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Run agreed target-volume dashboard/report/list/posting/reconciliation/import/export budgets and compare baseline. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Build a checkpointed evidence index linking requirement/capability/task/code/migration/contract/UI/test/result/issue/owner. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Perform clean rebuild/upgrade and posted-data-safe migration rehearsal with type generation and reconciled before/after totals. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Freeze and record one authoritative checkpoint/environment.
- Map 24 capabilities, 24 FIN anchors and FINTEST-001..024 to executable evidence.
- Run critical order-to-cash, procure-to-pay and source-to-GL E2E plus negative/failure tests.
- Reconcile AR/AP/subledger/GL/bank/profitability and test correction/lock/idempotency.
- Classify failures, create bounded repair tasks and rerun impacted suites.

## 21. Main flow

Verifier establishes checkpoint, executes full matrix, reconciles every critical flow and records pass/fail with reproducible commands and evidence.

## 22. Alternative flow

If environment dependency is unavailable, record exact blocked test and owner; no unexecuted mandatory gate may be counted as pass.

## 23. Exception flow

Any imbalance, duplicate posting, lock bypass, normal-role posted mutation, cross-tenant/customer leak, restricted-field leak, unreconciled material variance or falsified evidence is a critical blocker. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Verification is evidence-based; implementation claims and screenshots alone are insufficient.
- All mandatory scenarios run at one compatible checkpoint or explicitly block closure.
- A repair requires its own approved atomic task and regression rerun.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Coverage matrix has no orphan capability/requirement/FINTEST scenario.
- Source totals and journal effects reconcile exactly under policy.
- Test identities, datasets, commands and environment are reproducible.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Verifier has read/test authority only; production-like sensitive fixtures are protected; destructive/privileged tests use isolated authorized environments. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Full multi-tenant Finance fixture with invoice/receipt/allocation, bill/settlement, tax/FX, corrections, locks, retries, reconciliation breaks, restricted roles and target volumes. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- All FINTEST-001..024 and required unit/integration/API/database/migration/access/audit suites.
- Billing readiness→invoice/AR→receipt/allocation→journal and actual cost→bill/AP→settlement E2E.
- Tenant/customer/field isolation, performance/accessibility/browser, clean rebuild/upgrade and failure-injection.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Full Phase 1–4 contract/regression matrix and critical Commercial/Operations-to-Finance paths. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Integrated verification report, evidence index, requirement traceability, regression matrix, error/issue ledgers and exact rerun commands. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Do not mutate implementation during verification; return to last trusted checkpoint or authorize bounded repair, preserve failure evidence and resume at exact failed scenario. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- 24/24 capabilities, 24/24 anchors and 24/24 FINTEST mappings have evidence.
- All critical flows balance, lock, retry, reverse and reconcile correctly.
- Zero unresolved critical tenant/security/financial blocker remains before FIN-216.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-216 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

