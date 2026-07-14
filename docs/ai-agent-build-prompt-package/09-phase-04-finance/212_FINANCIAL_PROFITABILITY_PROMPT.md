# Prompt 212 — Job, Customer and Service Profitability

**Prompt ID:** `CG-S9-FIN-023`  
**Package document:** `CG-AABPP-FIN-212`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-212.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-023` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Financial Analytics; Epic: Source-Reconciled Profitability; Capability: Job, Customer, Service and Branch Profitability; Feature slice: recognized/billed revenue, actual/posted cost, allocation, variance, margin and drill-down; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Finance-grade profitability by job, customer, service and branch using source-linked revenue, cost and governed allocation rather than editable summary figures.

## 5. Business value

Give management reliable margin and variance insight tied to accounting truth.

## 6. Source requirement

FIN-PRF-001..004; OPS-CST-001..004 Finance depth; BR-FIN-PRF. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..211; Operations actual-cost/basic-profitability evidence. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-213..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add versioned allocation rules and reproducible profitability facts/snapshots with job/customer/service/branch, revenue/cost source lines, currency/rate, recognized/billed/posted classification, allocation and reconciliation references.

## 14. API impact

Shared REST/GraphQL profitability summary/detail/as-of/variance/export operations with field-safe aggregation and exact source drill-down. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Management/Finance profitability views with job/customer/service/branch filters, estimated-versus-actual-versus-posted/recognized comparison, margin/variance, source drill-down and permission-safe export. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Margin, cost, rate and allocation are highly restricted; aggregate suppression prevents inference; customer users cannot see internal profitability. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Use indexed source facts, bounded aggregates, caching/materialization only with checkpoint/freshness lineage, server pagination and async exports. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record allocation/config/as-of/source versions, calculation inputs/outputs, manual allocation approvals, generation/export actor and drill-down access. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map historical revenue/cost/allocation sources and reconcile to Operations actual cost and GL; unexplained profitability differences are blockers. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Operations estimates/actuals and Finance revenue/cost sources.
- Define recognition/billing/posting basis, allocation and exact formulas.
- Implement source model/query service, APIs and profitability UX.
- Integrate variance, reconciliation and field-safe aggregation/export.
- Test formulas, lineage, access, scale and migration.

## 21. Main flow

Authorized user selects as-of/basis, system gathers source-linked revenue and cost, applies approved allocation versions, computes exact profitability and permits drill-down to transaction/journal evidence.

## 22. Alternative flow

Compare estimated/actual/billed/recognized/posted bases, group by approved dimension, or run an approved allocation scenario clearly labeled non-posting.

## 23. Exception flow

Block/flag missing source, mixed currency without rate, unreconciled ledger, stale allocation version, unallocated material balance, negative/inconsistent sign or unauthorized margin inference. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Profitability basis is explicit; operational estimate and accounting P&L are never conflated.
- Revenue/cost derives from source/subledger/GL under captured policy; summary cannot be edited.
- Allocation rules are versioned, approved, exact and reversible through new versions.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- All source lines map to authorized job/customer/service/branch and compatible currency/basis.
- Revenue minus cost equals profit and margin handles zero/negative bases deterministically.
- Totals reconcile to chosen source/ledger/as-of checkpoint.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Management/Finance sees authorized margin detail; Operations sees only approved operational views; Commercial access follows policy; customer users see no internal cost/margin. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Profitable/loss/zero-revenue jobs, shared costs, multi-currency, partial billing/recognition, reversals, unallocated variance, multiple branches and unauthorized actors. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Revenue/cost/allocation/profit/margin/variance/as-of exact formula tests.
- Operations→invoice/bill/subledger/GL/reconciliation lineage E2E tests.
- RLS/RBAC/field/aggregate-inference/export isolation, performance, migration and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Operations cost/basic profitability, invoice/AR, bill/AP, journal/corrections, currency and reports. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Profitability basis/formula/allocation/source dictionary, operational-versus-accounting interpretation and reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable faulty read model/allocation version, restore prior approved rule and regenerate from source; correct accounting sources only through governed Finance flows. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Profitability is exact, basis-labeled and source-reconciled.
- Job/customer/service/branch drill-down matches authorized totals.
- Restricted cost/margin cannot leak through aggregates or exports.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-213 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

