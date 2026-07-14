# Prompt 299 — Customer Portal and Loyalty WBS Runtime Kickoff

**Prompt ID:** `CG-S13-CPL-001`  
**Package document:** `CG-AABPP-CPL-299`  
**Version:** `0.14.0`  
**Runtime build log:** `docs/build-log/phase-08/CPL-299.md`

Do not begin until `PHASE_7_VERIFIED` exists at the active repository/schema/environment checkpoint and the executor has read the current package manifest, confirmed decision register, source matrix, conflict register, coverage matrix and Step 12 closure evidence.

## Objective

Create the runtime WBS, dependency graph, execution index and evidence ledger for Phase 8 Customer Portal and Loyalty without implementing capability code inside this kickoff prompt.

## Required kickoff work

1. Freeze repository root, branch, HEAD, package manager, environment, database/schema state, migration state, feature flags and baseline test status.
2. Verify `PHASE_7_VERIFIED` and record the exact Step 12 closure artifact path/checkpoint. If absent, stop with `PHASE_8_BLOCKED`.
3. Build WBS tasks for Prompts 300–326 and mark only dependency-clean tasks `READY`.
4. Map all 24 capabilities and 36 anchors across `CPT-*` and `LYL-*`.
5. Record source-domain ownership: Platform, Commercial, Operations, WMS, Finance, Ticketing and Loyalty.
6. Create evidence ledgers for scope isolation, file scanning/signed URL, REST/GraphQL parity, loyalty ledger exactness, fraud/approval, liability reconciliation, performance and rollback.
7. Confirm no Step 14 AI/predictive/enterprise scope is scheduled in Phase 8.
8. Publish exact resume instructions and the first eligible prompt.

## Initial dependency order

1. CPL-300 Customer User Scope.
2. CPL-301 dashboard after scope.
3. CPL-302..315 portal flows after scope and relevant source-domain prerequisites.
4. CPL-316..323 loyalty flows after scope, Finance payment eligibility and customer master references.
5. CPL-324 integrated verification after all implementation prompts are `VERIFIED`.
6. CPL-325 hardening after integrated verification.
7. CPL-326 documentation handoff after hardening.
8. CPL-327 closure verification after documentation handoff.

## Required output

Write Phase 8 execution index, task ledger, anchor traceability, dependency map, test strategy, source-domain ownership matrix, environment baseline, risk register, rollback plan and exact next eligible prompt. Do not set the final Phase 8 closure flag.

