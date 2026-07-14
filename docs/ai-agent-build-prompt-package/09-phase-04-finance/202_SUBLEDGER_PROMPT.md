# Prompt 202 — Subledger

**Prompt ID:** `CG-S9-FIN-013`  
**Package document:** `CG-AABPP-FIN-202`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-202.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-013` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: Source Ledger Control; Capability: AR/AP and Source Subledgers; Feature slice: source event, debit/credit lines, open-item link, posting batch and GL control-account handoff; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical source subledgers that translate invoice, receipt, vendor-bill, settlement and approved adjustments into reconcilable accounting events.

## 5. Business value

Keep operational Finance records and GL linked without manual re-entry or opaque summary postings.

## 6. Source requirement

FIN-GL-001..004, FIN-AR-001..004, FIN-AP-001..004; data lineage guardrails. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-192..201. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-203..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add immutable-for-normal-roles subledger event/batch/line/source/version, account/dimension/currency/amount, AR/AP open-item link, canonical state, idempotency and GL journal reference.

## 14. API impact

Shared REST/GraphQL preview, post-request, read/source-lineage and reconciliation-query operations; no arbitrary normal-user subledger editing. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Accounting source-ledger explorer with filters, exact source/journal/open-item drill-down, debit/credit preview, exception state and reconciliation status. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Financial fields restricted; source and account/dimension scope checked at database/service; normal roles cannot mutate posted subledger events; RPD-022 exception disclosed. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/source/type/date/state/account/open-item; cursor paginate lines and batch-post with bounded transactions. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source/config versions, generated lines, rule mapping, idempotency, posting actor/result, journal link, correction chain and RPD-022 privileged action evidence. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Opening subledger import requires source mapping where available, control-account totals and GL reconciliation; unexplained differences are blockers. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory source events and accounting mappings.
- Define canonical subledger event/batch/line and control-account contracts.
- Implement rule-driven preview/post service, APIs and explorer.
- Connect AR/AP and journal idempotently with lineage.
- Run balance, reconciliation, isolation, migration and performance tests.

## 21. Main flow

An approved source emits an idempotent subledger request; service resolves captured policy/accounts/dimensions, previews balanced source lines, posts a batch and links one GL journal.

## 22. Alternative flow

Hold an event for missing mapping, post an approved grouped batch preserving item lineage, or process an opening balance migration.

## 23. Exception flow

Block missing/inactive account, dimension/currency mismatch, unbalanced mapping, duplicate source, locked period, stale config, cross-company source or orphaned journal. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Every posted subledger line traces to one source/version and one journal/correction chain.
- AR/AP control-account totals must reconcile to corresponding subledger balances.
- Normal users cannot create arbitrary source events or edit posted lines.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Source status/config/period/accounts/dimensions/currency are posting-eligible.
- Debit and credit preview balances per required scope.
- Idempotency and unique source rules prevent duplicate batch/journal.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Accounting reads and resolves exceptions; source services submit governed requests; approvers handle mapped exceptions; non-Finance roles receive only approved projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Invoice/receipt/bill/settlement events, grouped batches, missing mappings, duplicate retries, multi-currency/dimension, locked periods, opening balances and cross-tenant attempts. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Mapping/balance/source/idempotency/control-account constraint tests.
- AR/AP/source/journal API and E2E lineage/reconciliation tests.
- RLS/RBAC/field isolation, concurrency, migration, performance and RPD-022 disclosure tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Invoice/AR/receipt/AP/bill/settlement, COA/period/rate/tax/config and reporting. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Subledger event/line schema, posting-map contract, source-to-GL lineage and exception/reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Stop new consumption, replay only safe idempotent requests, reverse posted effects through linked correction and reconcile source/subledger/GL before resume. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Each source produces at most one intended subledger effect.
- Every batch balances and links to AR/AP and GL.
- Control-account reconciliation is explainable to source/version.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-203 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

