# Prompt 201 — Settlement

**Prompt ID:** `CG-S9-FIN-012`  
**Package document:** `CG-AABPP-FIN-201`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-201.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-012` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Procure to Pay; Epic: Payables Settlement; Capability: Vendor Settlement; Feature slice: payment instruction/record, AP allocation, partial settlement, approval and posting; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed settlement of AP open items with exact partial/multi-item allocation and source-linked cash/journal effects.

## 5. Business value

Give Finance auditable vendor-payment visibility and prevent duplicate or over-settlement.

## 6. Source requirement

FIN-AP-001..004; FIN-TAX-001..004; vendor-to-payment critical flow. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-199..200; use the published Finance account contract, which FIN-211 later extends with bank-statement control. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-202..218 and Step 11 vendor visibility. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add settlement root/reference/date/payee/bank/currency/rate/amount, AP allocation lines, fees/withholding, approval, canonical state, idempotency and posting/reversal links.

## 14. API impact

Shared REST/GraphQL prepare, validate, submit/approve, record-executed, post, reverse-request and read operations; external payment adapter only when explicitly scoped. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

AP settlement batch/detail with eligible items, exact allocations, bank/payment controls, approval timeline, execution status and reconciliation results. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Bank credentials/details are server-only/masked; separation of prepare/approve/execute/post; MFA for privileged approval; no autonomous AI or unapproved payment execution. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/payee/reference/date/status/bank; batch allocations transactionally and run heavy payment/export work asynchronously. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record payee/bank/source items, allocations, fees/tax, approval, external reference if any, idempotency, execution/posting and reversal. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import historical settlements only with bank evidence, AP allocation and subledger/GL reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect AP, bank, approval and payment adapter boundaries.
- Model settlement/allocation/execution state and exact constraints.
- Implement preparation, approval, execution-record, APIs and UX.
- Integrate AP balances, cash/bank, withholding, subledger/journal and reversal.
- Test duplicate/over-settlement, security, reconciliation and E2E.

## 21. Main flow

AP selects eligible items, prepares exact allocations and fees/tax, obtains approval, records controlled execution, and posts settlement once to reduce AP and cash/bank.

## 22. Alternative flow

Settle partially, combine compatible items/payee, retain an approved residual, or record a manual external bank execution reference.

## 23. Exception flow

Block duplicate instruction/reference, over-settlement, payee/bank/currency mismatch, changed open balance, approval conflict, locked period, failed execution ambiguity or unauthorized bank action. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Settlement amount equals AP allocations plus governed fees/tax/residual exactly.
- Execution/posting are distinct canonical states and retries cannot duplicate either.
- No provider action occurs without explicit adapter scope and human authorization.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Payee/bank/date/currency/rate/items/amount and approval are compatible.
- Every target AP item is current, open and within authorized scope.
- Posting preview balances AP, cash/bank, fee and withholding accounts.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

AP prepares; authorized approver approves; treasury/accounting records execution/posts; sensitive bank fields are least-privilege; vendor portal is out of scope. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Single/batch/partial settlements, fees/withholding, FX, changed AP balance, duplicate retry, execution timeout, locked period and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Allocation/fee/withholding/state/idempotency/concurrency tests.
- Approval/API parity/AP/cash/subledger/journal/reversal E2E tests.
- RLS/RBAC/MFA/field isolation, adapter-negative, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

AP/bill/aging, bank/cash, tax, journal, reports and Step 11 vendor contract. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Settlement state/data contract, separation-of-duties matrix, bank execution ambiguity and reversal/reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel pre-execution items, hold ambiguous executions for reconciliation, reverse posted settlement through governed flow and restore AP/cash/GL balances. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Eligible AP is settled exactly once and balances reconcile.
- Bank/payment authority is separated and auditable.
- Ambiguous external outcomes never trigger blind retry.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-202 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.
