# Prompt 220 — Advanced TMS/WMS WBS and Runtime Kickoff

**Prompt ID:** `CG-S10-ATW-001`  
**Package document:** `CG-AABPP-ATW-220`  
**Version:** `0.11.0`  
**Runtime output:** `docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 5 hierarchy, dependency graph, atomic task ledger and execution index without implementing Advanced TMS/WMS capabilities.

## Mandatory entry gate

Stop with `PHASE_5_BLOCKED` unless one active checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED`, `PHASE_1_VERIFIED`, `PHASE_2_VERIFIED`, `PHASE_3_VERIFIED` and `PHASE_4_VERIFIED`. Reconcile repository/branch/HEAD/worktree ownership, schema/migrations, canonical shipment/Operations/Finance contracts, PostGIS/integration/job/file/access primitives, environment, baselines, unresolved errors/issues and handoff before planning.

## Required work

1. Read every persistent governance/context/status/task/change/decision/assumption/error/issues/handoff artifact and all Phase 5 sources.
2. Inspect actual repository modules, schemas, migrations, RLS/RBAC/field policy, APIs/routes, PostGIS, jobs, files, tests, docs and commands. Never infer paths from this package.
3. Map the 24 capability catalogue and all advanced slices of the 24 `OPS-*` anchors to workstream → epic → capability → feature slice → atomic implementation/verification/hardening/documentation/closure tasks.
4. Split schema/migration, policy, service, REST/GraphQL, responsive scan/task UX, integration/job, tests and documentation work into bounded tasks with explicit dependencies and one owner.
5. Resolve collisions, cycles and orphans. Record an ADR/blocker when shipment leg ownership, resource identity, route/optimizer semantics, telemetry adapter, warehouse/customer/SKU/location model, UOM/negative stock, inventory locking, billing event or claim authority is ambiguous.
6. Map the critical WMS E2E, `OPS-WMS-US-001`, advanced transport scenarios, inventory reconciliation, scan/task, dispatch/load, integration and high-volume gates to implementation or verification tasks.
7. Prove the Phase 3 roots are extended rather than duplicated and Phase 4 Finance contracts remain backward-compatible; plan explicit data migration and reconciliation for every schema evolution.
8. Keep full vendor/PO/compliance/rate lifecycle in Step 11, HR employee/payroll depth in Step 12, full Customer Portal in Step 13 and AI/predictive/enterprise depth in Step 14.
9. Mark only dependency-clean tasks `READY`; all others remain `NOT_STARTED` or `BLOCKED` with exact prerequisites.

## Required execution-index columns

`task_id`, `parent_prompt`, `workstream`, `epic`, `capability`, `feature_slice`, `atomic_objective`, `source_ids`, `upstream`, `downstream`, `allowed_paths`, `forbidden_paths`, `migration_ids`, `api_contracts`, `access_controls`, `inventory_or_transport_invariants`, `tests`, `commands`, `evidence`, `rollback`, `owner`, `status`, `resume_point`.

## Phase 5 planning gates

- A multi-leg task cannot be `READY` until the canonical Shipment Order/leg/handoff/status model and Phase 3 migration/compatibility path are proven.
- Dispatch/planning tasks require current resource, location, capacity, PostGIS and human-override contracts; never promise an unverified optimum.
- A telemetry adapter is case-specific under RPD-038 and needs event-order/replay/privacy/retention/load evidence.
- No stock-changing WMS task becomes `READY` before exact UOM, inventory identity, ledger movement, reservation, concurrency, idempotency and customer-owner isolation invariants are approved.
- Customer inventory access requires database/backend customer scope; route parameters or UI filters are insufficient.
- Warehouse billing may emit only a Finance-compatible handoff and cannot bypass invoice/posting/period/field controls.
- Native/offline sync, full Procurement, HRIS, Customer Portal and AI/enterprise automation remain outside this phase.

## Completion gate

Mark kickoff `VERIFIED` only when the execution index has complete coverage, no cycle/orphan/collision, exact repository paths and commands, resolved ownership boundaries, explicit runtime/evidence gates and a deterministic next eligible atomic task. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do that.
