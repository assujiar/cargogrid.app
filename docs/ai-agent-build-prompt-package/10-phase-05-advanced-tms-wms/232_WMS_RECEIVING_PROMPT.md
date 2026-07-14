# Prompt 232 — WMS Receiving

**Prompt ID:** `CG-S10-ATW-013`  
**Package document:** `CG-AABPP-ATW-232`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-232.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-013` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Physical Receipt Control; Capability: Receiving, QC and Discrepancy; Feature slice: scan/count, actual quantity, condition, QC/hold, over/short/damage, evidence and inventory movement; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement server-acknowledged receiving that validates inbound lines, captures actual quantity/condition and creates exact inventory ledger movements into receiving/hold status.

## 5. Business value

Establish trustworthy physical receipt and discrepancy evidence at the warehouse door.

## 6. Source requirement

OPS-WMS-001..004 receiving slice; OPS-WMS-US-001; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-231 and active warehouse/location/item/UOM controls. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-233..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add receipt session/task/line, scanned item/location/lot/serial input, expected/actual/accepted/rejected/over/short/damaged exact quantities, QC/hold/status, evidence and idempotent inventory-movement references.

## 14. API impact

Shared REST/GraphQL start/read task, scan/validate, record count/condition, submit discrepancy, approve exception and confirm receipt operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Scan-first responsive online PWA receiving task with large actions, manual fallback, expected-versus-actual, QC/hold, photo/document evidence, progress and authoritative success/error states. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Task/warehouse/owner/item scope checked per scan; files private/scanned/signed; barcode is not authorization; no offline inventory commit. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Batch/scan endpoints are indexed and bounded, repeated scans idempotent, task lines cursor-paginated and large receipt imports/jobs chunked. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record task/source, every scan/count/condition, expected/actual variance, QC/hold, evidence, actor/device/time, approval and ledger movement IDs. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Migrate open receipts only with source/task/movement reconciliation; never backfill balances directly. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect inbound, item/UOM/barcode, file and ledger contracts.
- Define receipt task/session/line/discrepancy/QC and movement invariants.
- Implement scan/confirm service, APIs and online-first task UX.
- Integrate ledger, lot/serial, putaway, exceptions and notifications.
- Run duplicate scan, variance, isolation, migration and E2E tests.

## 21. Main flow

Assigned staff starts receipt, scans/validates source and items, records exact accepted/rejected condition, resolves required approval, confirms once and system posts receiving/hold ledger movements.

## 22. Alternative flow

Enter manual code with reason, receive partially, accept approved overage, reject/damage/hold goods or pause/resume online task.

## 23. Exception flow

Block wrong warehouse/owner/item/location, duplicate serial/scan, invalid UOM, unapproved overage, negative/overflow quantity, unsafe file, stale task or network result ambiguity. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Receipt confirmation and inventory movement commit atomically and idempotently.
- Over/short/damage/hold are explicit outcomes, never hidden quantity edits.
- Online-first task requires authoritative server result before showing stock committed.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Inbound/task/line/owner/item/UOM/location/status and user assignment are current.
- Actual accepted/rejected/variance equation balances exactly.
- Lot/serial/expiry requirements are satisfied before relevant movement.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Assigned warehouse staff execute; supervisor approves configured discrepancy/QC; customers see only permitted receipt summary, not internal notes/other owners. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Exact/partial/over/short/damage/hold receipts, repeated scans, serial duplicates, UOM variants, network retry, malicious file and cross-owner/tenant users. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Receipt equation/QC/discrepancy/idempotency/atomic-movement database tests.
- Scan/manual/file/API/inbound/ledger/putaway integration and critical E2E tests.
- RLS/RBAC/customer-owner/file isolation, concurrency, performance, online-degraded and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Inbound, barcode/label, inventory ledger, lot/serial/expiry, notifications, audit and future billing. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Receiving/QC/discrepancy/movement contract and ambiguous scan/network/variance recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Do not delete confirmed receipt; reverse through governed inventory movements, restore task state only if no commit occurred and reconcile receipt-to-ledger. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Confirmed quantities and conditions reconcile exactly.
- Retries/scans cannot duplicate inventory.
- Owner/warehouse/task security is enforced on every action.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-233 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

