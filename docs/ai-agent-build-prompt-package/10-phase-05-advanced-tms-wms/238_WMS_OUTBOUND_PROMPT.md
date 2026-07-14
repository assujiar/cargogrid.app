# Prompt 238 — WMS Outbound

**Prompt ID:** `CG-S10-ATW-019`  
**Package document:** `CG-AABPP-ATW-238`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-238.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-019` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Outbound Fulfillment; Capability: Outbound Order, Staging, Loading and Ship Confirmation; Feature slice: demand/source, allocation flow, staged packages, load/check, shipment handoff, ledger issue and billing event eligibility; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical outbound execution from authorized demand through pick/pack/stage/load/ship confirmation and exact inventory issue.

## 5. Business value

Complete warehouse fulfillment with traceable custody, stock reduction and shipment/Finance handoff.

## 6. Source requirement

OPS-WMS-001..004 and OPS-SHP-001..004 outbound slice; critical WMS E2E. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-231..237. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-239..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add outbound root/version/number, customer owner/source order/shipment, lines/UOM, allocation/pick/pack references, staging/dock/load/custody, canonical lifecycle, idempotent ship-confirm inventory movements and billing-event eligibility.

## 14. API impact

Shared REST/GraphQL prepare/create/import, validate/confirm demand, stage/load-check, ship-confirm, cancel-eligible and read-lineage operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Outbound queue/detail and scan-first stage/load tasks with source lines, package/load reconciliation, dock/vehicle/shipment, exceptions, custody and complete states. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/customer-owner/order/shipment/task scope; package/file/customer fields restricted; scan IDs never bypass authorization; no offline ship commit. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/warehouse/owner/status/date/source/shipment; batch/wave operations, cursor lists and atomic bounded ship confirmation. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source/version, allocation/pick/pack/package/load checks, dock/vehicle/custody, ship actor/time, inventory movement and billing eligibility. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map open outbound records only with demand/reservation/pick/package/inventory reconciliation; never backfill shipped status without evidence. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect outbound demand, shipment, pick/pack and billing contracts.
- Define outbound root/line/lifecycle/stage/load/custody/ship invariants.
- Implement services/APIs, queue/detail and scan tasks.
- Integrate inventory issue, Shipment leg/handoff and billing-event eligibility.
- Run quantity/custody/idempotency/scope/migration/E2E tests.

## 21. Main flow

Authorized demand creates outbound, stock is allocated/picked/packed, staff stages and verifies packages/load, confirms custody/ship once, and ledger issues stock while shipment/billing contracts receive source-linked events.

## 22. Alternative flow

Partially fulfill under policy, backorder short quantity, cross-dock compatible receipt, change dock/vehicle before confirm or cancel unallocated demand.

## 23. Exception flow

Block missing/extra package, wrong owner/order/shipment/dock/vehicle, unreconciled quantities, held stock, stale load, duplicate ship confirm, custody gap, locked/cancelled demand or network ambiguity. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Ship confirmation, custody event and inventory issue commit atomically/idempotently.
- Outbound quantity reconciles demand → allocation → pick → pack → load → issue.
- Warehouse billing eligibility is an event; invoice/journal posting remains Finance-owned.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Demand/source/warehouse/owner/item/UOM/packages/shipment and lifecycle are compatible.
- Loaded packages and issue quantities reconcile exactly.
- Custody/authorization/idempotency/version are current at ship confirm.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse staff execute assigned stage/load; supervisor approves partial/backorder/override; Operations receives shipment handoff; customers see only allowed status. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Full/partial/backorder/cross-dock outbound, package mismatch, held stock, multi-package load, duplicate retry, wrong dock/vehicle, network ambiguity and Tenant A/B owners. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Outbound lifecycle/quantity/package/load/custody/issue/idempotency database tests.
- Inbound→putaway→ledger→pick→pack→outbound critical E2E and shipment/billing contract tests.
- RLS/RBAC/customer-owner isolation, concurrency, migration, load and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Shipment/dispatch, all WMS tasks/ledger, documents/ePOD, Finance billing/readiness and future portal. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Outbound/lifecycle/quantity/custody/inventory/billing-event contract and mismatch/partial/network recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel only eligible uncommitted outbound, preserve confirmed issue/custody and correct through governed return/adjustment plus shipment/Finance reconciliation. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Outbound flow and inventory issue reconcile end to end.
- Retries cannot double-ship or double-issue.
- Shipment and Finance receive compatible source-linked events.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-239 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

