# Prompt 231 — WMS Inbound

**Prompt ID:** `CG-S10-ATW-012`  
**Package document:** `CG-AABPP-ATW-231`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-231.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-012` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Inbound Order Control; Capability: Warehouse Inbound Order; Feature slice: expected receipt/ASN, customer owner, source shipment/PO reference, lines, appointment, readiness and lifecycle; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical warehouse inbound orders that inherit customer/SKU/shipment/source data and drive receiving without redundant entry.

## 5. Business value

Give warehouses controlled expectations, appointments and ownership before goods arrive.

## 6. Source requirement

OPS-WMS-001..004 inbound slice; OPS-WMS-US-001; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-229..230; verified customer/item/master and shipment contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-232..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add inbound root/version/number, warehouse/customer owner/source shipment or future PO reference, expected date/appointment, line item/UOM/lot requirements, document/checklist, canonical state and idempotency constraints.

## 14. API impact

Shared REST/GraphQL prepare-from-source, create/import, validate, schedule, confirm, read and cancel-eligible operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Inbound queue/editor/detail with inherited source lines, appointment/calendar, owner/warehouse, receiving readiness, document/checklist, exception and complete responsive states. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/customer-owner/branch scope and item/source fields enforced; private source documents scanned/signed; future PO/vendor fields remain contract references only. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/warehouse/owner/status/expected date/source/number; cursor paginate and stage large imports asynchronously. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source/version mapping, expected line changes, appointment, readiness, actor/approval, idempotency and downstream receiving links. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map existing inbound/ASN records with warehouse/owner/item/source reconciliation and duplicate report. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory shipment/order/item/customer source contracts and existing inbound data.
- Define inbound root/version/line/source/appointment/readiness/lifecycle.
- Implement idempotent preparation/import, services, APIs and inbound UX.
- Integrate documents, receiving tasks, notifications and future PO reference boundary.
- Test no-reentry, duplicate, ownership, migration and load.

## 21. Main flow

Authorized user prepares inbound from a source shipment/request, system inherits owner/items/quantities/documents, schedules appointment, validates readiness and confirms it for receiving.

## 22. Alternative flow

Create approved manual inbound with source reason, import staged lines, reschedule appointment or cancel an unreceived order.

## 23. Exception flow

Block duplicate source, missing/ambiguous owner/item/UOM, invalid warehouse/appointment, stale source, unauthorized customer scope, unsafe document or cancellation after receipt. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Inbound references canonical customer/item/shipment; manual re-entry requires governed exception.
- Expected quantity is not on-hand inventory; stock changes only through receiving ledger movements.
- Future PO/vendor linkage does not implement Step 11 lifecycle.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Warehouse/owner/source/items/UOM/expected quantities/dates and requirements are compatible.
- Source/version and idempotency prevent duplicate inbound.
- Confirmed inbound has complete receiving readiness.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse planners create/schedule within facility/owner scope; staff read assigned receipts; customers receive only allowed status after ATW-242/Step13. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Shipment-linked/manual/import inbound, multiple owners/items/UOM, appointments, duplicate retry, missing docs, reschedule/cancel and cross-customer/tenant actors. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Inbound source/line/UOM/lifecycle/readiness/idempotency database tests.
- REST/GraphQL/import/document/receiving-task and shipment integration tests.
- RLS/RBAC/customer-owner isolation, migration, concurrency, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Shipment order, customer/item masters, documents, notifications, future PO and downstream WMS/Finance contracts. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Inbound/ASN data/source/lifecycle/readiness contract and duplicate/appointment/cancellation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel only unreceived drafts/confirmed items under policy, restore source mapping and reconcile any created receiving tasks. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Inbound is unique, source-linked and owner-scoped.
- Expected stock never changes balances.
- Receiving receives complete authorized instructions.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-232 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

