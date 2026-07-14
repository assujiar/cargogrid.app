# Prompt 210 — Aging

**Prompt ID:** `CG-S9-FIN-021`  
**Package document:** `CG-AABPP-FIN-210`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-210.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-021` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Financial Control; Epic: Exposure and Due Management; Capability: AR and AP Aging; Feature slice: as-of open balance, due bucket, currency, dispute/hold and drill-down; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact as-of AR/AP aging with versioned bucket definitions and source-reconcilable open balances.

## 5. Business value

Give Finance and management reliable collection/payment priorities, DSO visibility inputs and overdue exposure.

## 6. Source requirement

FIN-AR-004, FIN-AP-004; master Phase 4 aging requirement. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-196, FIN-198..201, FIN-206, FIN-209. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-213..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add/version aging bucket configuration and optional reproducible snapshots; derive balances from source/open-item/allocation/correction events, never editable summary balances.

## 14. API impact

Shared REST/GraphQL aging summary/detail/as-of/export operations with server filters, pagination and field projections. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

AR/AP aging dashboard/table with configurable approved buckets, as-of date, company/branch/customer/vendor/currency filters, drill-down to source and permission-safe export. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Customer/vendor/balance/cost fields follow record/field policy; cross-customer and bank detail leakage are prohibited. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Use indexed as-of/open-item queries, bounded aggregates/materialized snapshot only with freshness lineage, timeouts, caching and async export. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record bucket/config version, as-of/source checkpoint, filters, generation/export actor and drill-down access; underlying balance changes remain source-audited. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Validate opening dates/due dates/allocations and reconcile aging totals to AR/AP and GL before enabling reports. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect open-item event/date and reporting models.
- Define as-of/bucket/currency/status/dispute/hold semantics.
- Implement query/read model, APIs, dashboard/detail and export.
- Integrate corrections, allocations, reconciliation and access projections.
- Test exact totals, boundaries, scale, migration and isolation.

## 21. Main flow

User selects AR or AP as-of context, service derives authorized open balances into versioned buckets, displays totals and permits source drill-down/export.

## 22. Alternative flow

Compare periods, group by approved dimension, use transaction or functional currency view, or exclude/include disputed/held items explicitly.

## 23. Exception flow

Block/report stale or incomplete source checkpoint, invalid bucket overlap/gap, missing due date policy, unreconciled opening data, timeout without safe async fallback or unauthorized drill-down. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Aging is derived, not manually editable.
- Bucket boundaries and date basis are explicit, non-overlapping and versioned.
- Summary equals authorized detail and reconciles to AR/AP control totals.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- As-of date/period/currency and bucket version are valid.
- Open balance includes only effects effective by as-of under correction/allocation rules.
- Totals match source detail and reconciliation checkpoint.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

AR/AP staff see scoped detail; management sees allowed aggregates; exports/drill-down enforce the same field/record policy; customer portal aging waits for Step 13. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Current/overdue/boundary items, partial allocations before/after as-of, reversals, disputes/holds, FX, multiple scopes, large volumes and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- As-of/open-balance/bucket-boundary/currency/summary-detail tests.
- AR/AP/allocation/settlement/correction/reconciliation integration tests.
- RLS/RBAC/field/export isolation, query-budget/load, async export and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

AR/AP open items, fiscal dates, currency, corrections, reconciliation, dashboards and future portal contracts. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Aging basis/bucket/config specification, reconciliation guide and performance/export runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable faulty read model, restore last trusted query/snapshot version and regenerate from source events; never patch summary balances. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Aging totals are exact, reproducible and source-reconciled.
- Boundary/as-of/correction cases classify correctly.
- Unauthorized users cannot infer restricted exposure.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-211 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

