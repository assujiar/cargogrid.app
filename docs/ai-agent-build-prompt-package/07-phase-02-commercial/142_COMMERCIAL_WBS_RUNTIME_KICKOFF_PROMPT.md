# Prompt 142 — Commercial WBS and Runtime Kickoff

**Prompt ID:** `CG-S7-COM-001`  
**Package document:** `CG-AABPP-COM-142`  
**Version:** `0.8.0`  
**Runtime output:** `docs/build-log/phase-02/COMMERCIAL_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 2 hierarchy, dependency graph, atomic task ledger and execution index without implementing Commercial capabilities.

## Mandatory entry gate

Stop with `PHASE_2_BLOCKED` unless one active checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED` and `PHASE_1_VERIFIED`. Reconcile repository/branch/HEAD/worktree ownership, schema/migrations, Platform Core services/contracts, environment, baselines, unresolved errors/issues and handoff before planning.

## Required work

1. Map all twenty source requirements and every Prompt 143–165 to exact source, runtime architecture, module boundary, owner, feature slice, task, dependency and evidence path.
2. Instantiate the full Phase → workstream → epic → capability → feature slice → atomic implementation/verification/hardening/documentation/closure hierarchy.
3. Inspect existing Commercial code, schema, routes, REST/GraphQL contracts, UI, tests, jobs, files, audit, access and configuration; adopt verified work and create gap tasks instead of duplicating it.
4. Resolve the basic vendor/service/rate lookup ownership through a runtime ADR. Keep full onboarding, sourcing, procurement RFQ, PO and vendor lifecycle in Phase 6.
5. Define canonical identities and transitions for lead, prospect, account, contact, opportunity, costing request, rate snapshot, quote/version, acceptance, customer, contract/pricing and credit control.
6. Define the accepted-quote-to-Job-Order handoff contract, idempotency key, snapshot, lineage and Phase 3 ownership without implementing Job Order here.
7. Build dependency/collision/cycle/orphan checks; split tasks above the verified 1–3 migration or 5–15 file boundary.
8. Assign test data, positive/negative/regression/access/financial/concurrency evidence, rollback, documentation and exact next prompt to every task.
9. Mark only dependency-satisfied tasks `READY`; preserve `BLOCKED`, `FAILED`, `PARTIAL`, `ROLLED_BACK` and resume paths honestly.

## Hard gates

- No Commercial feature implementation, migration application, external call, deployment or shared-environment mutation in this kickoff.
- No unverified `PHASE_1_VERIFIED`, unresolved repository identity, ambiguous migration ownership, duplicate vendor/rate domain, floating-point money or client-only authorization.
- No task may claim runtime completion from package files.
- RPD-022, direct-GA, live-OLTP reporting, private-file scanning and no-reentry accepted risks/controls remain visible.

## Required output

Write checkpoint and gate evidence; hierarchy/WBS; task and dependency tables; source/decision/contract traceability; repository path/migration/API/UI/test ownership; vendor/rate ADR reference; Job Order handoff boundary; collision/concurrency plan; readiness states; risk/error/issue/resume entries; and the exact first eligible prompt.

**Next eligible prompt:** `CG-S7-COM-002` only when COM-143 is `READY`.
