# Prompt 167 — Operations WBS and Runtime Kickoff

**Prompt ID:** `CG-S8-OPS-001`  
**Package document:** `CG-AABPP-OPS-167`  
**Version:** `0.9.0`  
**Runtime output:** `docs/build-log/phase-03/OPERATIONS_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 3 hierarchy, dependency graph, atomic task ledger and execution index without implementing Operations capabilities.

## Mandatory entry gate

Stop with `PHASE_3_BLOCKED` unless one active checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED`, `PHASE_1_VERIFIED` and `PHASE_2_VERIFIED`. Reconcile repository/branch/HEAD/worktree ownership, schema/migrations, Platform/Commercial contracts, `JobOrderDraftInput`, environment, baselines, unresolved errors/issues and handoff before planning.

## Required work

1. Map all twenty Phase 3 source requirement anchors and every Prompt 168–188 to exact source, runtime architecture, module boundary, owner, feature slice, task, dependency and evidence path.
2. Instantiate the full Phase → workstream → epic → capability → feature slice → atomic implementation/verification/hardening/documentation/closure hierarchy.
3. Inspect existing Operations code, schema, routes, REST/GraphQL contracts, UI, tests, jobs, files, audit, access and configuration; adopt verified work and create gap tasks instead of duplicating it.
4. Verify Commercial `JobOrderDraftInput` version/fixtures/idempotency and map every customer/contact/address/cargo/service/rate/quote/price/credit field to Job Order lineage.
5. Encode Phase 3/5 boundaries: single-mode/single-leg land/air/sea, simple assignment/dispatch, basic milestone/exception/ePOD/cost only; exclude advanced TMS and full WMS.
6. Encode Phase 3/8 boundary: minimal public/customer tracking and ePOD visibility only; exclude the full Customer Portal.
7. Define canonical identities and transitions for Job Order, Shipment Order, shipment lifecycle, assignment, milestone/exception, document/ePOD, cost/profitability and billing readiness.
8. Build dependency/collision/cycle/orphan checks; split tasks above the verified 1–3 migration or 5–15 file boundary.
9. Assign test data, positive/negative/regression/access/financial/concurrency/file/performance evidence, rollback, documentation and exact next prompt to every task.
10. Mark only dependency-satisfied tasks `READY`; preserve `BLOCKED`, `FAILED`, `PARTIAL`, `ROLLED_BACK` and resume paths honestly.

## Hard gates

- No Operations feature implementation, migration application, external call, deployment or shared-environment mutation in this kickoff.
- No unverified `PHASE_2_VERIFIED`, unresolved repository identity, ambiguous migration ownership, duplicate Commercial data, full WMS/advanced TMS/full portal scope, floating-point money or client-only authorization.
- No task may claim runtime completion from package files.
- RPD-004, RPD-014, RPD-022, RPD-032, direct-GA and no-reentry controls remain visible.

## Required output

Write checkpoint and gate evidence; hierarchy/WBS; task/dependency tables; source/decision/contract traceability; repository path/migration/API/UI/test ownership; `JobOrderDraftInput` compatibility; TMS/WMS/portal/Finance boundaries; collision/concurrency plan; readiness states; risk/error/issue/resume entries; and the exact first eligible prompt.

**Next eligible prompt:** `CG-S8-OPS-002` only when OPS-168 is `READY`.
