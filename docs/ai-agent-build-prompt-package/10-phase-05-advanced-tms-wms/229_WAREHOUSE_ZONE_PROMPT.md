# Prompt 229 — Warehouse and Zone

**Prompt ID:** `CG-S10-ATW-010`  
**Package document:** `CG-AABPP-ATW-229`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-229.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-010` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Foundation; Epic: Facility Topology; Capability: Warehouse and Zone Master; Feature slice: facility, owner/service eligibility, zone type, environment/capacity, operational status and hierarchy; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/company warehouse and zone masters with versioned topology, operational eligibility and customer/owner scope.

## 5. Business value

Provide the controlled facility foundation required for every WMS task and inventory location.

## 6. Source requirement

OPS-WMS-001..004; UX warehouse/zone master; CPD-022. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-220; verified Platform master/config/access and location/PostGIS foundations. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-230..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add warehouse code/name/company/site/address/timezone/status/service/customer eligibility and zone code/type/environment/capacity/restriction/status with tenant-aware hierarchy and effective lifecycle.

## 14. API impact

Shared REST/GraphQL create, validate, list/read topology, activate/deactivate, eligibility and dependency-impact operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Warehouse Admin facility/zone list, topology editor, service/customer eligibility, operating calendar/status, capacity/environment and dependency view. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/customer/branch scope enforced in database/service; sensitive security/layout fields restricted; deactivation cannot orphan active inventory/tasks. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/site/status/code and warehouse/zone/type/status; paginate facilities and load topology selectively. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record topology/eligibility/environment/status/effective changes, actor/approval/reason and impacted bins/inventory/tasks/billing. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map existing warehouse/location references explicitly and reconcile customer owner, inventory and active task dependencies. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory warehouse/location masters and scope relationships.
- Define facility/zone topology, eligibility, environment/capacity and lifecycle.
- Implement additive schema/services/APIs and admin UX.
- Integrate access, downstream bin/task/inventory contracts and migration.
- Test hierarchy, deactivation, isolation, scale and evidence.

## 21. Main flow

Warehouse Admin creates facility and zones, configures operational restrictions/eligibility, validates topology/dependencies and activates them for WMS use.

## 22. Alternative flow

Schedule future zone, temporarily hold/restrict a zone or deactivate an empty unused zone after impact review.

## 23. Exception flow

Block duplicate code, cross-warehouse link, invalid timezone/site, incompatible environment/service, deactivation with stock/tasks, stale topology or unauthorized customer scope. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Warehouse and zone are canonical masters, not copied into each order.
- Customer/owner eligibility is explicit and cannot broaden access by itself.
- Active inventory/task dependencies prevent destructive normal-role topology changes.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Code/site/company/timezone/status and zone type/restrictions are valid.
- Hierarchy belongs to one tenant/warehouse and is acyclic.
- Activation/deactivation impact is reconciled to bins, inventory, tasks and billing.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse Admin maintains; managers/users see assigned facility/zone; customer access is owner/scoped and read-only through ATW-242 contract. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Multiple warehouses/companies/timezones, ambient/cold/secure zones, customer eligibility, active-stock deactivation, duplicate codes and cross-tenant actors. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Hierarchy/lifecycle/eligibility/environment/dependency database tests.
- REST/GraphQL/admin UX and downstream bin/inventory/task integration tests.
- RLS/RBAC/customer isolation, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Platform location/master/config, shipment sites, Finance dimensions and future WMS/portal capabilities. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Warehouse/zone topology/data/access dictionary, lifecycle/eligibility and safe-deactivation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Deactivate only unused additions, restore prior topology resolver and reconcile all active references before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every WMS location starts from an authorized active warehouse/zone.
- Topology changes cannot orphan stock or tasks.
- Customer and tenant isolation pass negative tests.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-230 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

