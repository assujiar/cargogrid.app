# Prompt 233 — WMS Putaway

**Prompt ID:** `CG-S10-ATW-014`  
**Package document:** `CG-AABPP-ATW-233`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-233.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-014` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Directed Storage; Capability: Putaway Task and Movement; Feature slice: source stock, destination eligibility, strategy suggestion, scan confirmation, partial/exception and ledger move; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement directed, human-confirmed putaway from receiving/hold locations into eligible storage locations through exact ledger movements.

## 5. Business value

Place stock accurately and efficiently while preserving location, owner, lot/serial and condition integrity.

## 6. Source requirement

OPS-WMS-001..004 putaway slice; OPS-WMS-US-001; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-230..232. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-234..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add putaway task/line/source movement, suggested/actual destination, strategy/version, exact quantity/UOM, owner/item/control dimensions, status/claim and inventory transfer movement references.

## 14. API impact

Shared REST/GraphQL generate-async, claim/read task, suggest/validate destination, scan-confirm, exception, release/reassign operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Scan-first online putaway queue/task with source/destination/item/qty, capacity/environment warnings, suggestion rationale, partial completion and manual authorized override. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/zone/location/owner/task scope checked; secure zones restricted; scans do not authorize; no offline movement commit. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Generate tasks asynchronously in batches, index status/assignee/location/owner, batch eligibility/capacity lookup and avoid per-bin queries. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source receipt/movement, strategy/rule version, suggestion, actual scans, quantity, assignee/device/time, override/reason and transfer movement IDs. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map open putaway tasks only with receipt/source/balance reconciliation; do not move stock during schema migration. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect receiving stock/location capacity and putaway policies.
- Define task/claim/suggestion/eligibility/transfer movement invariants.
- Implement generator/service/APIs and scan-first UX.
- Integrate capacity, lot/serial/status, exception and ledger.
- Test partial, conflict, retry, scope, migration and load.

## 21. Main flow

System generates task from received stock, staff claims it, validates/scans source/item/destination, confirms exact quantity and ledger atomically transfers stock.

## 22. Alternative flow

Put away partially, split across eligible bins, use authorized alternate destination with reason or hold/reassign task.

## 23. Exception flow

Block wrong/blocked/full/incompatible destination, owner/item/lot/serial mismatch, insufficient source balance, concurrent claim, duplicate scan/commit or network ambiguity. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Putaway suggestion is decision support; server validation of actual destination is authoritative.
- Source decrease equals destination increase in one balanced inventory transfer movement.
- Task completion derives from exact remaining quantity, not manual status.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Source stock exists and is available for putaway under owner/status/UOM dimensions.
- Destination is active, eligible, capacity-compatible and in authorized warehouse.
- Claim/version/idempotency and quantity balance are current.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Assigned staff execute; supervisors override/reassign; customers may view aggregate status only; restricted location data follows policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Single/split/partial putaway, full/incompatible bins, secure zone, concurrent claims, insufficient stock, repeated scan, network retry and cross-owner users. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Task/claim/destination/capacity/quantity/transfer equation tests.
- Receiving/location/ledger/lot/serial/API scan E2E tests.
- RLS/RBAC/customer-owner/restricted-zone isolation, async/load, degraded UX and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Warehouse topology, receiving, inventory ledger, label/barcode, task framework and downstream picking. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Putaway strategy/task/eligibility/transfer contract and conflict/partial/network recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Release uncommitted task, preserve confirmed movements, correct stock only with governed adjustment/transfer reversal and reconcile task-to-ledger. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every confirmed putaway is a balanced traceable movement.
- Concurrent/duplicate actions cannot misplace stock.
- Destination restrictions and customer ownership remain intact.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-234 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

