# Prompt 206 — Reversal and Adjustment

**Prompt ID:** `CG-S9-FIN-017`  
**Package document:** `CG-AABPP-FIN-206`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-206.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-017` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: Governed Financial Correction; Capability: Reversal and Adjustment; Feature slice: linked correction request, approval, reversal journal, adjustment and chain reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed reversal and adjustment that corrects posted financial effects through new linked records without rewriting normal-role history.

## 5. Business value

Allow accountable error correction while preserving source, balance, period and reconciliation integrity.

## 6. Source requirement

FIN-GL-001..004; FIN-AR/AP; INV-005; financial correction guardrail. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-203..205. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-207..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add correction request/type/reason/evidence, original/correction chain, reversal/adjustment journal references, approval, target period and unique anti-duplicate constraints.

## 14. API impact

Shared REST/GraphQL prepare-reversal, prepare-adjustment, validate-impact, submit/approve, post and read-chain operations. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Correction wizard from posted source with immutable original preview, impact on AR/AP/cash/tax/profitability, reason/evidence, target period, approval and chain timeline. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict correction initiation/approval/post separately; high-value/sensitive actions require MFA and evidence; private attachments scanned/signed. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Resolve correction chain and impact with indexed references; prevent recursive/cyclic chains and bound previews. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record original hash/version, correction reason/evidence, calculated lines, affected open items, period, approvals, posting and reconciliation result. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map existing credit/debit/reversal records to chains; unresolved orphan corrections block migration completion. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory existing correction patterns and source impacts.
- Define reversal/adjustment chain, constraints and accounting semantics.
- Implement impact preview, approval/post service, APIs and wizard.
- Integrate AR/AP/cash/tax/profitability and period rules.
- Test balance, duplicate, lock, access, migration and reconciliation.

## 21. Main flow

Authorized user starts from a posted record, selects valid correction type, supplies reason/evidence, previews exact impacts, obtains approval and posts a linked balanced correction in an eligible period.

## 22. Alternative flow

Reverse fully, adjust only approved dimensions/amounts through a new journal, or schedule correction into the current open period when original is locked.

## 23. Exception flow

Block duplicate reversal, excessive adjustment, cycle/orphan, missing evidence, locked target period, stale original/correction, tax inconsistency or unauthorized self-approval. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Original posted record remains unchanged for normal roles.
- One full reversal per eligible effect; further change follows explicit adjustment chain rules.
- Correction period/date and tax treatment are governed and source-reconcilable.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Original is posted, not already fully reversed and within authorized scope.
- Impact preview balances and all affected open-item/cash/tax states reconcile.
- Reason/evidence/approval/target period satisfy policy.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Authorized Accounting initiates; independent approver approves; posting authority executes; affected business users receive only approved notifications/projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Full/partial correction, locked original/current period, duplicate requests, stale chain, AR/AP/payment/tax impacts, high-value approval and cross-tenant actors. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Correction-chain/duplicate/cycle/balance/period constraint tests.
- Invoice/bill/payment/subledger/journal/AR/AP/tax impact E2E tests.
- RLS/RBAC/MFA/separation/file/audit, idempotency, concurrency, migration and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

All posted Finance records, aging, reconciliation, profitability, reports and retention. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Correction taxonomy, accounting impact matrix, approval/evidence and locked-period correction runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel eligible draft correction, retry unchanged approved posting idempotently or create a governed correcting chain; never mutate the original. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Correction creates balanced linked records only once.
- Original normal-role history remains unchanged.
- All downstream balances and reports reconcile after correction.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-207 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

