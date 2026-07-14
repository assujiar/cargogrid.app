# Prompt 47 — Release Train

**Prompt ID:** `CG-S3-ARCH-012`  
**Package document:** `CG-AABPP-ARCH-047`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/12_RELEASE_TRAIN.md`

## Objective and value

Translate architecture and workstream dependencies into an internal delivery/release train that produces testable increments while preserving the requirement that first production GA contains all major modules.

## Preconditions

Prompts 36–46 are complete. Use the module dependency map, workstream backlogs, phase model, delivery/test/go-live plan, and verified repository capacity evidence. Do not invent calendar commitments or external pilot stages.

## Required tasks

1. Define Phase 0–9 internal increments, Full-System Hardening, Release Candidate/Go-Live, and Final Package Validation boundaries.
2. Map each increment to capabilities, prerequisites, database/API/UI/security/test/DevOps outputs, entry/exit gates, demo/evidence, rollback/recovery, and downstream consumers.
3. Reconcile cross-phase splits: vendor-rate lookup versus full procurement, basic versus advanced TMS, WMS ownership, Customer Portal basic versus full, Finance linkage, and platform-engine adoption.
4. Define integration points, stabilization windows, schema/API compatibility windows, release-branch/freeze policy, environment promotion, and evidence retention.
5. Allow internal feature flags and progressive technical exposure without relabeling an external pilot; production first release remains direct GA only after all modules and gates.
6. Define defect thresholds, no-new-feature window, zero Sev-1/critical requirement, go/no-go authority, rollback triggers, hypercare, and post-implementation review.
7. Identify capacity/resource assumptions as assumptions—not commitments—and provide dependency-based sequencing when dates are unavailable.
8. Produce a release-train table and compact dependency/timeline visualization with explicit critical gates.

## Required output

Include release principles, train/increment table, dependency milestones, cross-phase ownership, integration/stabilization gates, environment/promotion path, quality/security/data/finance gates, freeze/go-no-go/rollback/hypercare rules, assumptions, risks, and update triggers.

## Completion gate

Complete only when every parent phase has entry/exit evidence, no external pilot is inserted, all modules precede GA, cross-phase handoffs are unambiguous, and dates are absent or evidence-based.
