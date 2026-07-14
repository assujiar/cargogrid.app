# Prompt 32 — Greenfield/Brownfield Decision

**Prompt ID:** `CG-S2-DISC-012`  
**Package document:** `CG-AABPP-DISC-032`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md`

## Objective

Make an evidence-backed repository strategy classification before architecture planning, while protecting reusable assets and preventing an unjustified rewrite.

## Preconditions and guardrails

Prompts 21–31 are complete at one checkpoint. This task is analysis only. Do not scaffold, migrate, delete, rewrite, upgrade, or change dependencies. Product decisions remain governed by the Step 0 registers.

## Allowed classifications

- `GREENFIELD`: no material implementation exists; establish within the current repository/workspace.
- `BROWNFIELD_EXTEND`: foundation is credible and should be extended incrementally.
- `BROWNFIELD_REHABILITATE`: preserve the system while resolving bounded foundational blockers first.
- `BROWNFIELD_MIGRATE`: evidence supports a controlled incremental migration with explicit coexistence/rollback.
- `UNKNOWN_BLOCKED`: evidence is insufficient, inconsistent, unsafe, or the checkpoint is not authoritative.

## Required tasks

1. Build an evidence matrix covering repository history/topology, implemented capability, fixed-stack fit, dependency health, database/migration state, tenant/security controls, routes/APIs, tests/build, performance, UX/accessibility, placeholders, and technical debt.
2. Assess asset value, correctness, coverage, operability, extensibility, migration cost, rewrite risk, data continuity, and non-regression risk.
3. Compare all plausible classifications with benefits, costs, risks, assumptions, and disqualifiers.
4. Select one classification or `UNKNOWN_BLOCKED`; state confidence and dissenting evidence.
5. List assets to preserve, boundaries needing isolation, prohibited broad rewrites, and conditions under which the decision must be revisited.
6. Define Step 3 entry conditions, mandatory ADR topics, sequencing constraints, and evidence gaps without producing the architecture itself.

## Required output

Write `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` containing checkpoint, decision, confidence, evidence matrix, alternatives, rationale, preserved assets, migration/coexistence implications where applicable, prohibited actions, unresolved evidence, revisit triggers, and Step 3 entry/exit implications.

## Completion gate

Complete only when the classification is supported by cited discovery evidence, no broad rewrite is implicitly authorized, uncertainty is explicit, and all critical blockers have owners or a blocking status.
