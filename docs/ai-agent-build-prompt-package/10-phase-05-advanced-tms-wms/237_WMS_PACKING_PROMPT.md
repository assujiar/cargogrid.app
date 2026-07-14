# Prompt 237 — WMS Packing

**Prompt ID:** `CG-S10-ATW-018`  
**Package document:** `CG-AABPP-ATW-237`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-237.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-018` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Shipment Preparation; Capability: Packing, Package and QC; Feature slice: picked-line verification, package/container hierarchy, quantity, dimensions/weight, materials, QC, seal and readiness; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement scan-verified packing that groups picked inventory into traceable packages with measured attributes, QC and outbound readiness.

## 5. Business value

Ensure shipment packages contain the correct owner/items/quantities and carry reliable handling data.

## 6. Source requirement

OPS-WMS-001..004 packing slice; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-236; label/barcode contract later extended by ATW-240. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-238, ATW-240..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add packing session/task, package/container hierarchy, packed inventory references, exact quantity/UOM, measured weight/dimensions, material, seal, QC/status and source pick/outbound links.

## 14. API impact

Shared REST/GraphQL start/read task, create package, scan/add/remove-before-confirm, measure, QC, seal, confirm/reopen-request operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Scan-first online packing station with picked-versus-packed reconciliation, package tree, weight/dimension inputs, QC/checklist, seal, preview and error states. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Owner/order/task scope, package/customer data and restricted contents enforced; evidence/photos private/scanned/signed; barcode does not authorize. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Batch package line operations, indexed task/status/order, bounded scans and async document/label generation. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source picks, every add/remove scan, package/measurements/material/seal/QC, actor/station/time, approval and readiness. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map open packages only with pick/outbound/quantity reconciliation; never mark packed from summary alone. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect picked inventory, outbound/package and label/document contracts.
- Define packing session/package hierarchy/reconciliation/QC/readiness.
- Implement services/APIs and packing-station UX.
- Integrate ledger status, labels, outbound, exceptions and files.
- Test contents, measurement, retry, scope and E2E.

## 21. Main flow

Packer starts assigned task, scans picked stock into packages, verifies exact contents, records measurements/QC/seal, confirms once and creates outbound-ready package evidence.

## 22. Alternative flow

Split across packages, nest containers, remove before confirm, hold failed QC or request governed reopen before outbound loading.

## 23. Exception flow

Block wrong owner/order/item/control dimension, over/duplicate pack, missing measurement/QC/seal, confirmed-package edit, stale task, unsafe evidence or network ambiguity. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Packed quantities reconcile exactly to confirmed picks minus governed exceptions.
- Package identity and hierarchy are stable and cannot cycle.
- Confirmed package changes require governed reopen/repack with audit, not silent edit.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Task/pick/outbound/owner/item/control dimensions and quantities are compatible.
- Package hierarchy, measurements, QC and seal satisfy service rules.
- Idempotency/version prevents duplicate confirm or contents.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Assigned packers execute; supervisors hold/reopen/approve exception; customers see only allowed package/shipment data. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Single/multiple/nested packages, partial pack, wrong/duplicate scan, measurement/QC/seal failure, reopen, network retry and cross-owner users. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Package hierarchy/content/quantity/measurement/QC/state/idempotency tests.
- Pick/ledger/label/outbound/file/API scan E2E tests.
- RLS/RBAC/customer-owner/file isolation, concurrency, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Picking, inventory status, label/barcode, shipment cargo, outbound, ePOD and billing. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Packing/package/QC/readiness data contract and mismatch/reopen/network recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Discard unconfirmed package changes, preserve confirmed evidence and use governed reopen/repack with inventory/outbound reconciliation. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Confirmed package contents reconcile to picks.
- No duplicate/wrong-owner item can be packed.
- Outbound receives complete measurable traceable packages.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-238 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

