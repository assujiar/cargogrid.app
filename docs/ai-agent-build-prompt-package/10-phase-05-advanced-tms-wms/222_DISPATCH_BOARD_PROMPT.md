# Prompt 222 — Dispatch Board

**Prompt ID:** `CG-S10-ATW-003`  
**Package document:** `CG-AABPP-ATW-222`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-222.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-003` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Advanced Transportation; Epic: Dispatcher Control Tower; Capability: Advanced Dispatch Board; Feature slice: date/branch/resource queue, board-map-list, conflict-safe assignment, hold/reassign and live active-state updates; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend Phase 3 basic dispatch into a high-density permission-safe board for leg/trip assignment, readiness, hold, reassign and execution monitoring.

## 5. Business value

Let dispatchers coordinate many active movements quickly without double-booking resources or loading the whole dataset.

## 6. Source requirement

OPS-TMS-001..004 advanced dispatch; UX OPS-DSP-001; Delivery Phase 5 dispatch-performance gate. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221 and verified Phase 3 basic assignment/dispatch; later ATW-223/224/227 extensions must trigger impacted re-verification. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-223..228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add only needed dispatch queue/read model, assignment claim/version, hold/reassign reason and indexed active-window projections; canonical trip/leg/resource records remain authoritative.

## 14. API impact

Shared REST/GraphQL board-window, unassigned queue, readiness, assign/hold/reassign/dispatch operations with optimistic concurrency and idempotency. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Desktop board with table/map/board toggle, virtualized/paginated lanes, filters/saved views, conflict/readiness detail; tablet compact board and mobile task list, never a drag-only workflow. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Branch/service/resource/cost fields and actions follow scope; drag/drop cannot bypass server authorization; map data/customer locations are restricted. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Window and cursor based reads, selective subscriptions only for active filtered scope, batched lookups, virtualization and target-volume latency budgets. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record board filter/context, assignment before/after, readiness snapshot, conflict, override/hold/reassign/dispatch actor/reason and event correlation. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Adopt existing basic dispatch records without copying them; backfill only version/claim/read-model fields with reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Profile Phase 3 dispatch queries/actions and target workload.
- Define board window/read model, assignment claim and active realtime contract.
- Implement shared operations, REST/GraphQL and accessible board/map/list UX.
- Add conflict/readiness/hold/reassign and selective update handling.
- Run concurrency, isolation, realtime/load, accessibility and regression gates.

## 21. Main flow

Dispatcher opens an authorized date/branch window, reviews ready legs/trips and resource state, assigns or dispatches through a conflict-safe server action and sees scoped updates.

## 22. Alternative flow

Bulk assign only compatible items, hold with reason, reassign after impact check, or use keyboard/list actions instead of drag/drop.

## 23. Exception flow

Block stale board version, double-booking, not-ready leg, inactive/out-of-scope resource, capacity violation, unauthorized override, realtime gap or hidden partial failure. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Board is a projection; canonical assignments/states change only through shared services.
- Every assign/reassign/dispatch checks current readiness, resource availability and concurrency token.
- Realtime is filtered and selective; polling/revalidation provides safe recovery.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Leg/trip/resource/window/scope and readiness versions remain compatible at commit.
- Bulk operations report per-item result and never silently partially succeed.
- All actions have non-drag keyboard/mobile alternatives.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Dispatchers act within authorized branch/service/date/resource scopes; managers approve configured overrides; other users see only safe projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

High-volume active windows, unassigned/held/dispatched items, resource conflicts, stale boards, bulk partial errors, denied branches and Tenant A/B. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Read-model/readiness/claim/assignment/concurrency/idempotency tests.
- REST/GraphQL/board-map-list/selective-realtime and Phase 3 dispatch integration tests.
- RLS/RBAC/field/customer isolation, load/virtualization, accessibility/browser and degraded-update tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Phase 3 basic dispatch/assignment, milestones/exceptions, notifications, PostGIS/map and later fleet/planning/capacity contracts. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Dispatch-board query/action/realtime/access contract, keyboard/mobile guide and conflict/degraded-state runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable advanced board actions, fall back to verified basic dispatch service, reconcile outstanding claims/assignments and resume from exact failed window. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Board remains responsive at target volume.
- Concurrent users cannot double-assign or bypass readiness.
- Every visible action works with server authority and complete feedback.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-223 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

