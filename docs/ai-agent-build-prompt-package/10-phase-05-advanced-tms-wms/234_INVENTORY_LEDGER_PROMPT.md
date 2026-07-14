# Prompt 234 — Inventory Ledger

**Prompt ID:** `CG-S10-ATW-015`  
**Package document:** `CG-AABPP-ATW-234`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-234.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-015` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Inventory Control; Epic: Canonical Stock Truth; Capability: Inventory Movement Ledger and Derived Balances; Feature slice: movement event, dimensions, on-hand/available/reserved/held, reservation, correction and reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the canonical idempotent inventory movement ledger and derived balance/reservation model for all WMS stock changes.

## 5. Business value

Provide exact, explainable inventory truth and prevent silent balance mutation.

## 6. Source requirement

OPS-WMS-001..004 and OPS-CST-001..004 inventory integrity slice; INV-006; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-229..233; approved item/UOM/owner/status identity. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-235..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add inventory movement header/lines/source/type/time, warehouse/owner/item/location/lot/batch/serial/expiry/status/UOM dimensions, exact signed quantity, idempotency and correction chain; derive on-hand/available/reserved/held balances with constraints.

## 14. API impact

Shared REST/GraphQL movement-request, reserve/release/consume, transfer/adjustment-preview, ledger/balance/as-of and reconciliation operations; no normal direct balance CRUD. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Inventory balance/ledger explorer with source/movement/correction drill-down, exact dimensions, reservation/availability, as-of filters, cursor pagination and permission-safe export. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

RLS plus warehouse/customer-owner/field scope across movement/balance/export; normal roles cannot update/delete posted movements; RPD-022 absolute CRUD exception is explicitly warned and disclosed. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Cursor paginate ledger, tenant-aware composite indexes, atomic balance/reservation writes, bounded locks, async reconciliation/import and partition/materialize only after measured thresholds. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Ledger itself carries source/version/actor/time/idempotency/correction; record privileged attempts, exports, reconciliation and RPD-022 action evidence where available. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Opening inventory requires counted/source evidence, exact dimensional mapping, approved opening movements and before/after reconciliation; never backfill summary only. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory every stock-changing path and existing balance model.
- Define movement/dimension/UOM/reservation/balance/correction equations.
- Implement database/service/API/explorer and block direct balance writes.
- Integrate receiving/putaway/pick/outbound/count/adjustment/billing sources.
- Run property/concurrency/replay/migration/reconciliation/access/load tests.

## 21. Main flow

Authorized source submits idempotent movement; service validates dimensions/UOM/source/status and atomically appends lines plus updates derived balances; reads reconcile to movement history.

## 22. Alternative flow

Reserve/release stock, transfer between compatible locations/statuses, import approved opening movements or correct through linked adjustment/reversal.

## 23. Exception flow

Block insufficient/negative stock under policy, dimension/UOM mismatch, duplicate source/key, serial conflict, stale reservation, unbalanced transfer, locked location/status or unauthorized owner. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Every balance change has a source-linked ledger movement; normal roles never patch balance.
- On-hand, available, reserved and held equations are exact and dimension-complete.
- RPD-022 prevents an immutable-for-all claim; normal-role protections and best-effort evidence remain mandatory.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Tenant/warehouse/owner/item/location/control dimensions/UOM/source/status are valid.
- Movement signs and transfer/reservation equations balance exactly.
- Idempotency, serial uniqueness and concurrency locks prevent duplicate/negative effects.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

WMS services submit scoped movements; authorized staff view/adjust through workflow; customers see owner-scoped balance/ledger projections only; other-owner detail is denied. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Receipt/transfer/reserve/release/pick/ship/count/adjust movements, fractional UOM, held/damaged/expired, serial, concurrent depletion, duplicate retry, opening balance and Tenant A/B owners. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Movement/balance/reservation/UOM/negative-stock/serial/idempotency property and database tests.
- All WMS source integration, as-of/reconciliation, API parity and migration E2E tests.
- RLS/RBAC/customer-owner/export isolation, concurrency/deadlock, load/cursor and RPD-022 disclosure tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Every WMS capability, Finance warehouse billing/profitability, reports, future customer portal and audit/retention. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Inventory identity/movement/balance/reservation/UOM/correction specification and discrepancy/replay/migration/reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Stop affected writers, preserve ledger evidence, restore trusted service version and correct through governed movement; never delete keys or patch balances to force equality. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every derived balance exactly reconciles to ledger history.
- Retries/concurrency cannot duplicate or overdraw stock beyond policy.
- Normal-role direct balance/ledger mutation is impossible.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-235 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

