# Prompt 236 — WMS Picking

**Prompt ID:** `CG-S10-ATW-017`  
**Package document:** `CG-AABPP-ATW-236`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-236.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-017` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Order Fulfillment; Capability: Reservation, Wave and Picking; Feature slice: outbound demand, allocation/reservation, pick task/wave, scan, short/substitute, confirmation and ledger movement; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact reservation and scan-confirmed picking from eligible inventory for outbound demand, including partial, short and governed substitution.

## 5. Business value

Fulfill orders accurately while preventing double allocation and stock-location errors.

## 6. Source requirement

OPS-WMS-001..004 picking slice; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-234..235 and confirmed outbound demand contract. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-237..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add outbound allocation/reservation, pick wave/task/line/sequence, source inventory dimensions, requested/allocated/picked/short/substituted exact quantities, claim/status and ledger movement references.

## 14. API impact

Shared REST/GraphQL allocate/generate-wave-async, claim/read task, scan/validate, short/substitute-request, confirm/release operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Scan-first online pick queue/task with route/bin sequence, item/control dimensions, requested/remaining qty, exception actions, progress and large accessible controls. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/owner/order/task/location scope per action; scans do not authorize; customer data minimized; no offline stock commit. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Batch allocation/wave generation, indexed task queues, atomic reservations, cursor lines and route sequence without per-bin queries. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record demand/source/reservation, allocation rule/version, task claim, scans, exact quantities, short/substitute approval, actor/device/time and ledger IDs. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map open allocations/tasks only after balance/reservation reconciliation; never synthesize picked stock. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect outbound demand, inventory availability/reservation and allocation rules.
- Define allocation/wave/task/claim/scan/short/substitution/movement invariants.
- Implement async generation, service/APIs and scan-first UX.
- Integrate ledger, lot/serial/FEFO, packing and exceptions.
- Run double-allocation, concurrency, scope, load and E2E tests.

## 21. Main flow

System allocates/reserves eligible stock, generates pick tasks, staff claims/scans exact location/item/control IDs/quantity, confirms once and ledger transfers stock to picked/staging status.

## 22. Alternative flow

Pick partially, record short, request approved substitute, release/reallocate reservation or batch compatible lines into a wave.

## 23. Exception flow

Block insufficient/stale stock, wrong location/item/lot/serial/owner, expired/held stock, concurrent reservation, over-pick, unapproved substitute, duplicate commit or network ambiguity. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Reservation prevents double allocation and remains reconciled to outbound demand.
- Picked quantity cannot exceed current allocated quantity without governed exception.
- Task completion derives from exact line balances and confirmed movements.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Demand/status/owner/item/UOM/control dimensions and source inventory are compatible.
- Reservation/claim/version/idempotency are current.
- Short/substitution follows published policy and approval.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Assigned pickers execute; supervisors release/reassign/approve exceptions; customers see only permitted fulfillment status. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Single/wave picks, partial/short/substitute, FIFO/FEFO/serial, concurrent allocation, wrong scans, network retry, high volume and cross-owner users. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Allocation/reservation/task/quantity/short/substitute/idempotency/concurrency tests.
- Outbound demand/ledger/control-dimension/packing/API scan E2E tests.
- RLS/RBAC/customer-owner isolation, async/load, degraded UX and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Inventory ledger, lot/serial/expiry, location, outbound, labels, billing and future customer access. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Picking allocation/wave/task/reservation/movement contract and short/substitute/network recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Release only unpicked reservations/tasks, preserve confirmed movements and correct stock through governed ledger flow with demand reconciliation. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Concurrent orders cannot double-allocate stock.
- Every pick is scan/source/ledger traceable.
- Short/substitute cases are explicit and approved.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-237 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

