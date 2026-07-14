# Prompt 80 — Phase 0 WBS and Runtime Kickoff

**Prompt ID:** `CG-S5-PH0-001`  
**Package document:** `CG-AABPP-PH0-080`  
**Version:** `0.6.0`  
**Runtime outputs:** `docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md`, `docs/build-log/phase-00/00_PHASE0_WBS.md`

## Objective

Validate the Phase 0 runtime gate, reconcile the repository-specific architecture/WBS evidence, and instantiate an atomic dependency-aware execution index for Prompts 81–102 without changing source code.

## Required tasks

1. Verify Prompt 34 and Prompt 51 runtime closure reports at the same active checkpoint.
2. Reconcile architecture WBS IDs with this package and create the full hierarchy required by the Master Prompt.
3. For every Prompt 81–101 assign task ID, workstream, epic, capability, feature slice, verification/hardening/docs relationship, owner, branch, allowed paths, dependencies, environment, tests, rollback and next prompt.
4. Inspect current worktree/branches/migrations/scripts and identify file/schema/environment collision risks.
5. Mark each task `READY` only when prerequisites and exact variables can be resolved; otherwise `BLOCKED` with evidence.
6. Define safe concurrency lanes, integration checkpoints, stale-evidence triggers and recovery order.
7. Update persistent context/status/task ledger and phase handoff; do not implement any foundation change.

## Required outputs

The execution index must contain prompt/task ID, hierarchy, status, dependencies, branch/checkpoint, allowed paths, outputs, baseline/final gates, owner, evidence and next action. The WBS must prove all 18 capability prompts plus verification, hardening, documentation and closure coverage.

## Completion gate

Complete only when one authoritative Phase 0 checkpoint and dependency graph exist, all variables for the first READY task are resolvable, no cycle/orphan/collision remains unowned, and no runtime source/config/data/environment change occurred.

**Next eligible prompt:** `CG-S5-PH0-002` only if PH0-081 is `READY`.
