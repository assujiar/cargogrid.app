# Prompt 230 — Bin and Racking

**Prompt ID:** `CG-S10-ATW-011`  
**Package document:** `CG-AABPP-ATW-230`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-230.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-011` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Foundation; Epic: Location Topology; Capability: Flexible Rack, Bin and Location Hierarchy; Feature slice: location path/type/capacity/environment/status, scan identity and stock/task dependency; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a flexible warehouse location hierarchy for rack, shelf, floor, staging, dock and bin positions without forcing one physical layout.

## 5. Business value

Give WMS precise, scannable locations for putaway, inventory, picking and outbound control.

## 6. Source requirement

OPS-WMS-001..004; UX rack/bin master and warehouse data dictionary. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-229. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-231..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add flexible location node/code/type/parent/path/sequence, zone, capacity/UOM, environment/restriction, barcode identity, pick/putaway flags, status and tenant-aware hierarchy/dependency constraints.

## 14. API impact

Shared REST/GraphQL create, validate, tree/list/read, move-draft, activate/deactivate and dependency-impact operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Warehouse topology tree/map/table editor with location type/capacity/restriction, printable code, dependency view, keyboard support and safe activation/deactivation. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/zone scope enforced; secure/restricted areas and customer eligibility are field/record protected; barcode IDs never authorize by themselves. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Use materialized path/ltree or repository-approved indexed hierarchy, bounded depth and selective subtree loading; no full warehouse tree in browser. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record location hierarchy/path/type/capacity/restriction/status/barcode changes, actor/approval/reason and stock/task impact. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map existing free-text locations explicitly, preserve source values, prevent duplicate codes and reconcile every stock/task reference. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory current location representations and physical variants.
- Define flexible hierarchy, path, types, capacity/restriction and lifecycle.
- Implement schema/services/APIs and topology UX.
- Integrate scan identity and downstream receiving/putaway/inventory/pick contracts.
- Test hierarchy, dependency, migration, scope and scale.

## 21. Main flow

Warehouse Admin creates typed location nodes under an active warehouse/zone, validates hierarchy/capacity/restrictions, assigns collision-safe scan identity and activates them.

## 22. Alternative flow

Use floor/staging/dock location without rack, schedule a new area, or relocate an empty unused draft node with impact preview.

## 23. Exception flow

Block cycle, duplicate path/code/barcode, cross-warehouse parent, incompatible zone/environment, deactivation/move with stock/tasks or unauthorized restricted-area access. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Rack is optional; canonical location hierarchy supports real facility layouts.
- A barcode resolves a candidate location but server context/permission/task still validates the action.
- Normal-role topology cannot move/delete locations holding stock or active tasks.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Node/parent/warehouse/zone/type/path/code/status and capacity are consistent.
- Hierarchy is acyclic, depth-bounded and tenant-scoped.
- Barcode identity is unique within governed scope and non-secret.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse Admin maintains; staff scan/read assigned operational locations; customer users receive inventory location detail only if policy permits. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Rack/shelf/bin, floor/staging/dock, mixed hierarchy, cycles, duplicate codes/barcodes, active stock/task deactivation, secure zones and Tenant A/B. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Hierarchy/path/type/capacity/barcode/lifecycle/database dependency tests.
- REST/GraphQL/topology UX and WMS downstream contract tests.
- RLS/RBAC/customer/restricted-zone isolation, migration, load and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Warehouse/zone, master numbering, files/labels, future inventory/task/customer access. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Flexible location topology/type/path/barcode data dictionary and safe relocation/deactivation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Deactivate unused additions, restore prior hierarchy resolver and reconcile all mapped stock/task references before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every operational location is uniquely scannable and hierarchy-valid.
- Layout flexibility does not weaken scope or dependency controls.
- No active stock/task becomes orphaned.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-231 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

