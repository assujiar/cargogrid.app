# Prompt 213 — Finance Dashboard and Reports

**Prompt ID:** `CG-S9-FIN-024`  
**Package document:** `CG-AABPP-FIN-213`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-213.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-024` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Financial Analytics; Epic: Controlled Finance Visibility; Capability: Finance Dashboard and Reports; Feature slice: billing, AR/AP, cash, close, tax, trial balance/statements, budget/actual and profitability; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement permission-safe live Finance dashboards and governed reports covering billing, AR/AP aging, cash, close, reconciliation, tax, profitability and Finance-MVP statements.

## 5. Business value

Give Finance and management actionable, reconcilable visibility without spreadsheet reassembly.

## 6. Source requirement

FIN-GL/AR/AP/TAX/CLS/PRF-004; RPD-014; 12 named report categories where applicable. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..212. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-214..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add only required read views/query functions, report definitions/schedules/export jobs and reproducible checkpoint metadata; basic trial balance, P&L/balance-sheet views and budget/accrual/recognition/close status must remain source-reconciled.

## 14. API impact

Shared REST/GraphQL dashboard widgets, report metadata/run/status/result and drill-down contracts with identical access and query budgets. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance dashboard with billing readiness/invoice, AR/AP aging, cash, reconciliation/close and profitability; report catalogue/detail with filters, saved views, async export and source freshness. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Every metric, row, drill-down and export enforces tenant/company/branch/customer and financial field policy; suppress inference-prone aggregates and mask bank/tax data. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

RPD-014 live OLTP controls: read-only selective queries, timeouts, pagination, caching, explicit query budgets and read replicas only when measured scale justifies them; heavy reports async. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record report/widget/version/filter/checkpoint, generation/schedule/export/download actor, field policy, outcome and source freshness. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Reconcile any existing report formulas/definitions to canonical source metrics; do not carry forward opaque or manually patched totals. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Finance personas, metrics/reports and source queries.
- Define governed metric/report contracts, formulas and access projections.
- Implement dashboards, catalogue, APIs, async export/schedule and drill-down.
- Add query budgets, freshness/reconciliation and report audit.
- Run formula, access, performance, accessibility and source-reconciliation tests.

## 21. Main flow

Authorized user opens the Finance dashboard, sees permission-safe current metrics with freshness, drills to source, runs a parameterized report and receives an audited async export.

## 22. Alternative flow

Use saved view, schedule an approved report, compare periods/budget/actual or run an as-of statement at a reproducible checkpoint.

## 23. Exception flow

Fail visibly for timeout, stale/unreconciled source, denied field/drill-down, invalid period/currency, export failure or formula mismatch; never show partial numbers as complete. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Dashboard/report totals reconcile to canonical source and disclose as-of/freshness/basis.
- Budget, accrual, recognition and statement views expose only implemented governed Finance-MVP semantics.
- No report/export/search path may weaken field/record policy or claim final GA readiness.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Filters, period/as-of, currency/basis and source checkpoint are valid.
- Summary, drill-down and export totals match within explicit approved rounding.
- Every query meets budget or uses safe asynchronous execution.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance roles get task-specific details; management gets approved aggregates; other domains receive only contracted projections; Customer Portal Finance views remain Step 13. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

All financial states, balanced/discrepant data, multiple scopes/currencies/periods, restricted margin/bank/tax fields, large volumes, slow query/export and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Metric/formula/as-of/statement/budget-actual/summary-detail reconciliation tests.
- REST/GraphQL/dashboard/report/schedule/export/drill-down integration tests.
- RLS/RBAC/field/aggregate-inference/export isolation, load/query-budget, accessibility/browser and failure-state tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

All Finance capabilities, RPD-014 controls, generic reporting/export/job framework and future portal/enterprise consumers. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Finance KPI/report catalogue, formula/source/access/freshness registry, query-budget and failed-report/export runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable faulty widget/report definition, restore prior version and regenerate from source checkpoint; never patch published totals manually. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Metrics and reports reconcile to source and disclose basis/freshness.
- Restricted data stays protected in every surface/export.
- Query budgets and asynchronous fallback pass target-volume tests.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-214 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

