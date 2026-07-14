# Prompt 227 — Capacity and Utilization

**Prompt ID:** `CG-S10-ATW-008`  
**Package document:** `CG-AABPP-ATW-227`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-227.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-008` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Transport Resources; Epic: Capacity Control; Capability: Capacity and Utilization; Feature slice: resource/time-window capacity, reservation, consumed/released quantity, overbook control and utilization analytics; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact resource capacity reservation and utilization across planned/assigned/dispatched legs using versioned UOM and compatibility rules.

## 5. Business value

Prevent overbooking and expose usable capacity for planning and management.

## 6. Source requirement

OPS-TMS-001..004 capacity/utilization slice; NFR-PERF. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-223..225; verified exact cargo/UOM data. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add resource/time-window capacity profile/version, reservation/allocation, consumed/released quantity by weight/volume/unit/pallet as configured, compatibility and utilization snapshots with exact decimals.

## 14. API impact

Shared REST/GraphQL availability, reserve, release, consume, recalculate and utilization read operations with idempotency/concurrency. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Capacity calendar/visualization in planning/dispatch plus utilization dashboard/detail with exact dimensions, conflicts and authorized override. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Resource/vendor cost and schedules are restricted; reservations enforce tenant/branch/service/record scope and cannot leak competitor/customer loads. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index resource/window/status; atomic bounded reservation writes, batch availability reads, no global realtime and query-budgeted utilization aggregates. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record capacity/rule version, source cargo/UOM, reservation before/after, consume/release, conflict, override/reason and plan/dispatch links. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Backfill active assignment reservations only from reconciled cargo/resource data; unresolved over-capacity remains blocked. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory capacity dimensions/UOM and assignment lifecycle.
- Define exact capacity/reservation/consume/release equations and compatibility.
- Implement transactional service/APIs and planning/dispatch views.
- Backfill/reconcile active reservations and utilization reports.
- Test overbooking, concurrency, UOM, access and target volume.

## 21. Main flow

Planning requests availability, system atomically reserves compatible exact capacity, dispatch consumes it, cancellation/replan releases it and utilization derives from the ledger-like reservation history.

## 22. Alternative flow

Reserve partial/split capacity, use configured tolerance with approval, or hold capacity for a bounded window that expires safely.

## 23. Exception flow

Block over-capacity, invalid conversion, incompatible cargo/resource, overlapping exclusive reservation, stale availability, double release/consume or unauthorized override. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Capacity is multi-dimensional where configured; passing one dimension cannot hide failure in another.
- Reservation/consume/release are idempotent and never direct summary edits.
- Tolerance/overbook policy is versioned, approved, explicit and audited.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Resource/window/status, cargo/UOM dimensions and compatibility are current.
- Reserved plus available equals configured usable capacity under exact rules.
- State transitions and releases reconcile to assignment/leg lifecycle.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Planners/dispatchers reserve within scope; managers approve tolerance; management sees authorized aggregates; vendor/customer details remain protected. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Weight/volume/pallet/unit dimensions, split loads, concurrent reserve, expiry/cancel/replan, tolerance, incompatible cargo, high volume and Tenant A/B. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Capacity/UOM/reservation/consume/release/equation property and concurrency tests.
- Planning/dispatch/leg API integration and idempotency tests.
- RLS/RBAC/field isolation, migration reconciliation, load/query-budget and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Cargo/service, fleet/driver, route/load, dispatch, milestones, cost/profitability and reporting. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Capacity dimension/UOM/equation/compatibility specification and conflict/reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Stop new reservations, reconcile active holds to assignments, release only proven orphan reservations and restore last valid capacity profile. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Concurrent actions cannot overbook beyond approved policy.
- Every utilization value traces to exact reservation history.
- Planning and dispatch see consistent capacity.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-228 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

