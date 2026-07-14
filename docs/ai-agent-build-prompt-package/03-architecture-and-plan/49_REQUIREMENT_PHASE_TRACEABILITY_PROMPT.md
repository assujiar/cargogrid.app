# Prompt 49 — Requirement-to-Phase Traceability

**Prompt ID:** `CG-S3-ARCH-014`  
**Package document:** `CG-AABPP-ARCH-049`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md`

## Objective and value

Prove that every CargoGrid decision, explicit requirement, generated gap control, catalogue item, accepted risk, and release obligation is assigned to delivery, verification, hardening, and closure work.

## Preconditions

Prompt 48 and all earlier Step 3 outputs are complete. Use source IDs and WBS IDs without renumbering or collapsing them into untraceable prose.

## Required tasks

1. Trace CPD-001..023, RPD-001..040, all 184 functional and 10 explicit NFR IDs, package gap IDs, and source assumptions/conflict closure routes.
2. Trace 24 business rules, 13 approval patterns, 14 approval use cases, 24 transitions, 16 exception types, report categories, NFR areas, 20 E2E UAT, 18 tenant isolation, and 24 financial scenarios.
3. For each item record source, canonical statement, parent phase, workstream/epic/capability/feature/task IDs, architecture artifacts, tests/evidence, hardening/release gates, owner, and status.
4. Represent cross-phase scope with one primary owner and explicit prerequisite/extension links; do not duplicate or silently drop requirements.
5. Mark `COVERED`, `PARTIAL_BLOCKED`, `EXTERNAL_VERIFICATION`, `ACCEPTED_RISK`, or `NOT_COVERED`. `COVERED` requires both delivery and verification owners.
6. Detect orphan requirements, WBS tasks without sources, duplicated/conflicting ownership, late security/finance/data controls, and requirements deferred beyond GA.
7. Preserve RPD-022 risk disclosure, direct-GA all-module gate, contract-silent recovery semantics, and custom-integration policy in traceability.
8. Produce coverage totals by source/domain/phase/state and exact closure tasks for every gap.

## Required output

Include traceability schema, full matrix, cross-phase links, accepted-risk overlay, external/SME/contract verification, orphan/duplicate/conflict analysis, coverage totals, blocker list, and update/validation rules.

## Completion gate

Complete only when nothing is `NOT_COVERED`, every partial/external item has owner and gate, every WBS task has a legitimate source, and totals reconcile with Step 0 inventories.
