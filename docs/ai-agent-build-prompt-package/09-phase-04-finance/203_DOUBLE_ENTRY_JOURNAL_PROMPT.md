# Prompt 203 — Double-Entry Journal

**Prompt ID:** `CG-S9-FIN-014`  
**Package document:** `CG-AABPP-FIN-203`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-203.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-014` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: General Ledger Posting; Capability: Double-Entry Journal; Feature slice: journal header/line, debit-credit balance, source/dimension validation, approval and posting; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical double-entry journal creation and posting with debit-equals-credit constraints, exact source lineage and shared posting service.

## 5. Business value

Establish accounting correctness for every Finance transaction and authorized manual journal.

## 6. Source requirement

FIN-GL-001..004; INV-005/011; financial integrity guardrails. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..202. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-204..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add journal root/version/batch/source/period/currency, exact debit/credit lines, accounts/dimensions, canonical draft/approved/posted/reversed state, idempotency and database-enforced balance/post eligibility.

## 14. API impact

Shared REST/GraphQL preview, create-authorized-manual, validate, submit/approve, post and read-lineage operations; source services use the same posting boundary. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Accounting journal list/editor/detail with balanced totals, line/dimension validation, source links, approval/posting timeline and protected posted state. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Separate prepare/approve/post; restrict manual journals, sensitive dimensions and fields; MFA for privileged approvers; normal roles cannot bypass service/database posting constraints. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/period/date/status/source/account; cursor paginate lines and post bounded batches with lock/order discipline. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record exact lines, source/config versions, preview hash, approvals, idempotency, posting result, correction chain and privileged attempts. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Opening journals require explicit source/import batch, balance validation, period authority and trial-balance reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect accounting rules, source events and existing journal schema.
- Define exact journal/line/state/balance/dimension constraints.
- Implement shared preview/post service, APIs and internal UX.
- Integrate subledger/manual paths, approvals, locks and idempotency.
- Run balance, access, reconciliation, migration and E2E gates.

## 21. Main flow

Authorized source or Accounting user prepares a journal, service validates period/accounts/dimensions and exact balance, required approval completes, then the journal posts once and updates GL.

## 22. Alternative flow

Save/modify draft, upload a staged balanced batch, or submit an authorized manual adjustment with full reason/source.

## 23. Exception flow

Block debit-credit mismatch, missing/inactive account, invalid dimension/currency, closed period, stale preview, duplicate request, approval conflict or unauthorized manual posting. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Total debit equals total credit exactly at required currency and balancing dimensions.
- Posted lines retain source/config/period/account/dimension snapshots.
- Every posting uses one shared service and idempotency boundary; no direct table mutation for normal roles.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- At least two valid lines and exact nonzero balanced amounts.
- Accounts/dimensions/period/currency/source and approval are eligible.
- Preview hash and source versions remain unchanged at commit.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Accounting prepares allowed manual journals; configured approver approves; posting authority is separate; source services use scoped server credentials; other roles see only permitted projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Balanced/unbalanced journals, multi-line/dimension/currency, inactive/control accounts, stale preview, duplicate retry, locked period, concurrent posting and cross-tenant actors. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Exact balance/account/dimension/state/database constraint tests.
- Manual/source/subledger/API parity/approval/idempotency/posting E2E tests.
- RLS/RBAC/MFA/field isolation, concurrency/deadlock, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

COA/period/config/currency/tax, all source subledgers, GL reports, exports and audit. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Journal/line/state schema, shared posting contract, balance/dimension specification and failed-post recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Discard eligible draft, safely retry unchanged request, or reverse posted journal via FIN-206; never edit posted normal-role lines. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Unbalanced or ineligible journal cannot post.
- Every valid posting occurs once and is source-reconstructible.
- Manual and system journals share identical integrity controls.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-204 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

