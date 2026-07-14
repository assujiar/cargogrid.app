# Step 3 — Architecture and Execution Blueprint

**Document ID:** `CG-AABPP-ARCH-035`  
**Version:** `0.4.0`  
**Status:** `FINAL_FOR_STEP`  
**Runtime authorization:** Architecture analysis and repository-native planning documents only. No feature, refactor, migration, dependency, configuration, deployment, or production-data mutation.

## 1. Purpose

This package converts verified repository discovery and the CargoGrid product baseline into an implementation-ready architecture and execution blueprint. It controls boundaries, data flow, target structure, cross-cutting workstreams, release sequencing, traceability, and the risk-ranked critical path before reusable or phase implementation prompts are produced.

Package generation and runtime execution are separate:

- `PACKAGE_STEP_3_COMPLETE`: files 35–51 exist and pass package validation.
- `RUNTIME_ARCHITECTURE_NOT_EXECUTED`: prompts exist but were not run against verified discovery evidence.
- `RUNTIME_ARCHITECTURE_IN_PROGRESS`: one or more outputs exist but closure has not passed.
- `RUNTIME_ARCHITECTURE_VERIFIED`: Prompt 51 verified the full blueprint at one repository checkpoint.

## 2. Binding entry gate

Before Prompt 36, verify:

1. `docs/discovery/14_STEP2_CLOSURE_REPORT.md` exists and states `RUNTIME_DISCOVERY_VERIFIED`.
2. All Step 2 outputs reference one authoritative repository checkpoint.
3. `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` identifies the approved strategy and preserved assets.
4. Persistent context, status, task, error, issues, decision, and handoff records agree.
5. No unresolved critical discovery blocker prevents architecture planning.

If any condition fails, set runtime state `RUNTIME_ARCHITECTURE_BLOCKED`, record the exact missing evidence and resume prompt, then stop. Package-level completion never satisfies this runtime gate.

## 3. Binding sources

- Product Concept Brief and CPD-001..023.
- RPD-001..040, including RPD-022, RPD-031/034/036/037/038.
- Master Prompt Step 3 and §§5–21.
- Project Charter, Business Process/Product Requirements Blueprint, UX/Data/Access Design, Technical Architecture, and Delivery/Testing/Go-Live Plan.
- Step 0 controls, Step 1 governance, and verified Step 2 runtime evidence.

Do not reopen ratified product decisions. Architecture uncertainties become ADRs, evidence gaps, or blockers—not silent assumptions.

## 4. Execution order and outputs

| Order | Prompt | Runtime output |
|---:|---|---|
| 1 | `36_MODULE_DEPENDENCY_MAP_PROMPT.md` | `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` |
| 2 | `37_CANONICAL_DATA_FLOW_MAP_PROMPT.md` | `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md` |
| 3 | `38_DOMAIN_BOUNDARY_MAP_PROMPT.md` | `docs/architecture/03_DOMAIN_BOUNDARY_MAP.md` |
| 4 | `39_REPOSITORY_TARGET_STRUCTURE_PROMPT.md` | `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` |
| 5 | `40_DATABASE_SCHEMA_WORKSTREAM_PROMPT.md` | `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` |
| 6 | `41_RLS_RBAC_WORKSTREAM_PROMPT.md` | `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` |
| 7 | `42_CONFIGURATION_ENGINE_WORKSTREAM_PROMPT.md` | `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` |
| 8 | `43_API_INTEGRATION_WORKSTREAM_PROMPT.md` | `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` |
| 9 | `44_UX_DESIGN_SYSTEM_WORKSTREAM_PROMPT.md` | `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` |
| 10 | `45_TESTING_WORKSTREAM_PROMPT.md` | `docs/architecture/10_TESTING_WORKSTREAM.md` |
| 11 | `46_DEVOPS_WORKSTREAM_PROMPT.md` | `docs/architecture/11_DEVOPS_WORKSTREAM.md` |
| 12 | `47_RELEASE_TRAIN_PROMPT.md` | `docs/architecture/12_RELEASE_TRAIN.md` |
| 13 | `48_FULL_WORK_BREAKDOWN_STRUCTURE_PROMPT.md` | `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` |
| 14 | `49_REQUIREMENT_PHASE_TRACEABILITY_PROMPT.md` | `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` |
| 15 | `50_RISK_RANKED_CRITICAL_PATH_PROMPT.md` | `docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md` |
| 16 | `51_STEP3_CLOSURE_VERIFICATION_PROMPT.md` | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` |

## 5. Universal architecture rules

- Derive current-state facts from Step 2 evidence; never invent repository paths, versions, services, schemas, routes, or coverage.
- Distinguish `CURRENT`, `PRESERVE`, `TARGET`, `MIGRATE`, `RETIRE`, `ADR_REQUIRED`, and `UNKNOWN_BLOCKED`.
- Preserve shared multi-tenant codebase; no tenant fork.
- Enforce PostgreSQL/Supabase, tenant-aware schema/RLS, layered access, REST and GraphQL parity, PostgreSQL durable queue first, PostGIS from Platform Core, private malware-scanned files, and guarded live-OLTP dashboards.
- Supreme Admin literal absolute CRUD is a disclosed ratified risk; never claim immutable/tamper-proof audit or financial records.
- Non-AI third-party integrations are custom case-by-case inside shared codebase; do not introduce a generic provider abstraction contrary to RPD-038.
- Direct GA requires all modules, all internal gates, and zero critical defects; no external pilot is inserted.
- RPO/RTO are contractual; contract silence means best effort without guarantee.
- All diagrams must have a corresponding machine-reviewable table or list. Diagrams never replace exact ownership, dependency, access, and evidence records.
- Architecture tasks must remain small enough to become atomic prompts later: one feature slice, one module boundary, one branch, one objective, normally 1–3 migrations and 5–15 changed files.

## 6. Evidence and ADR standard

Every material assertion must cite a source requirement, ratified decision, Step 2 evidence ID, or approved ADR. ADR candidates include ID, question, options, constraint, recommendation, owner/approver, evidence needed, downstream effect, and blocking state. A recommendation is not an approved ADR.

Each output records repository checkpoint, inputs, assumptions, unresolved items, affected requirements, downstream consumers, validation method, and update triggers.

## 7. Allowed and forbidden work

Allowed: read-only repository inspection needed to reconcile verified evidence; write/update `docs/architecture/**` and persistent planning/status/ledger/handoff documents; run documentation validation.

Forbidden: application/test/config/migration/seed/lockfile/CI code changes; dependency operations; database/service/environment writes; deployment; feature flags; commits/push/PR; or correcting defects discovered during design.

## 8. Package completion

This directory is package-complete when all 17 Markdown files exist, are non-empty, use unique IDs `ARCH-035..051`, cover all 15 Master Prompt Step 3 deliverables, include runtime gates and completion criteria, and are represented in package controls.

The next package-generation command is `LANJUT STEP 4`. Runtime implementation remains forbidden until Prompt 51 is `RUNTIME_ARCHITECTURE_VERIFIED` and the later implementation step explicitly authorizes code.
