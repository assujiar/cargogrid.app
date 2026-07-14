# Prompt 48 — Full Work Breakdown Structure

**Prompt ID:** `CG-S3-ARCH-013`  
**Package document:** `CG-AABPP-ARCH-048`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md`

## Objective and value

Build a complete dependency-aware WBS from Phase 0 through final validation, decomposed deeply enough for Step 4 reusable prompts and Steps 5–16 atomic phase packages.

## Preconditions

Prompts 36–47 are complete. Use all architecture outputs, 194 explicit requirements, gap requirements, business-rule/test catalogues, release train, technical-debt register, and preserved brownfield assets.

## Mandatory hierarchy

Every deliverable must be represented as:

`Parent phase → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

## Required tasks

1. Create stable IDs for phases, workstreams, epics, capabilities, feature slices, and tasks; preserve traceability through later package steps.
2. Cover Platform Core, Commercial, Operations, Finance, Advanced TMS/WMS, Procurement/Vendor, HRIS/Ticketing, Portal/Loyalty, Intelligence/Enterprise, hardening, release/go-live, runbooks, and final validation.
3. Add cross-cutting database, RLS/RBAC, configuration, API/integration/job, UX/design system, testing, performance, security, accessibility, DevOps, migration, documentation, support, and recovery work.
4. For each task record objective, source IDs, repository boundary, owner, upstream/downstream IDs, inputs/outputs, allowed/forbidden scope, data/API/UI/security/performance/audit/migration impact, tests, commands, evidence, rollback/recovery, and completion criteria.
5. Enforce atomic sizing: one feature slice, one module boundary, one branch, one clear objective, normally 1–3 migrations and 5–15 changed files. Split oversized tasks with explicit dependencies.
6. Include brownfield preservation/migration/retirement work only where supported by the approved strategy; prevent big-bang rewrites.
7. Flag ADR/legal/SME/contract/runtime-evidence gates and accepted risks without reopening ratified decisions.
8. Calculate completeness/duplicate/orphan/cycle checks and define the exact handoff into Steps 4–16.

## Required output

Include WBS conventions, complete hierarchical register, dependency edges, workstream/phase summaries, atomic-size exceptions, ADR/evidence gates, verification/hardening/documentation/closure coverage, orphan/duplicate/cycle report, and downstream package mapping.

## Completion gate

Complete only when every requirement/control has at least one delivery and verification owner, every task has dependencies and completion evidence, oversized work is split, cycles/orphans are zero or blocking, and no implementation is performed.
