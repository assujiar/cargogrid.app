# Prompt 104 — Platform Core WBS and Runtime Kickoff

**Prompt ID:** `CG-S6-PLT-001`  
**Package document:** `CG-AABPP-PLT-104`  
**Version:** `0.7.0`  
**Runtime outputs:** `docs/build-log/phase-01/00_PLATFORM_CORE_EXECUTION_INDEX.md`, `docs/build-log/phase-01/00_PLATFORM_CORE_WBS.md`

## Objective

Validate `PHASE_0_VERIFIED`, reconcile architecture/WBS/traceability with the active repository, and instantiate atomic Platform Core tasks for Prompts 105–140 without changing runtime source.

## Required tasks

1. Reconfirm Step 2, Step 3 and Phase 0 closure reports at one active checkpoint.
2. Reconcile 32 capability profiles with repository modules, preserved assets, schema ownership, API/UI boundaries and approved ADRs.
3. Split any profile exceeding one feature slice/module/branch/objective or normally 1–3 migrations/5–15 files into child tasks with explicit dependencies.
4. Assign every task hierarchy IDs, branch, owner, exact allowed/forbidden paths, migrations, API/UI/access/audit/performance impacts, tests, commands, rollback and next prompt.
5. Build safe concurrency lanes and integration checkpoints; detect schema/contract/file/flag/test collisions, cycles and orphan requirements.
6. Mark only fully resolved tasks `READY`; record blockers/assumptions/evidence and exact resume action.
7. Update context/status/task/change/traceability/handoff records; do not implement Platform Core.

## Completion gate

Complete only when all 32 capabilities and verification/hardening/docs/closure are represented in the hierarchy, every dependency/requirement has ownership, no cycle/orphan/collision is unowned, and PLT-105 can be instantiated from repository evidence.

**Next eligible prompt:** `CG-S6-PLT-002` only when PLT-105 is `READY`.
