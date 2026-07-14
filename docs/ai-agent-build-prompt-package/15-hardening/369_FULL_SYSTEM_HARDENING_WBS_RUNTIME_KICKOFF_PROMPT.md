# Prompt 369 — Full-System Hardening WBS Runtime Kickoff

**Prompt ID:** `CG-S15-HDN-001`  
**Package document:** `CG-AABPP-HDN-369`  
**Version:** `0.16.0`  
**Runtime build log:** `docs/build-log/full-system-hardening/HDN-369.md`

Do not begin until `PHASE_9_VERIFIED` exists at the active repository/schema/environment checkpoint and the executor has read the current package manifest, confirmed decision register, source matrix, conflict register, coverage matrix and Step 14 closure evidence.

## Objective

Create the runtime WBS, dependency graph, execution index, hardening matrix and blocker ledger for full-system hardening without executing feature work inside this kickoff prompt.

## Required kickoff work

1. Freeze repository root, branch, HEAD, package manager, environment, database/schema state, migration state, feature flags and baseline test status.
2. Verify `PHASE_9_VERIFIED` and record the exact Step 14 closure artifact path/checkpoint. If absent, stop with `FULL_SYSTEM_HARDENING_BLOCKED`.
3. Build WBS tasks for Prompts 370–388 and mark only dependency-clean tasks `READY`.
4. Create hardening matrices for regression, transactional integrity, tenant isolation, RLS/RBAC, financial integrity, lineage, API compatibility, storage/signed URL, security, performance, accessibility, browser/device compatibility, observability, backup/restore, DR and migration rehearsal.
5. Create severity rules, release-blocker definitions, accepted-risk handling and exact remediation/resume format.
6. Confirm no Step 16 release/go-live work is performed in Step 15.
7. Publish exact next eligible prompt.

## Initial dependency order

1. HDN-370 full regression baseline.
2. HDN-371 cross-module integrity before finance/lineage/API hardening.
3. HDN-372 tenant isolation before HDN-373 RLS/RBAC and HDN-378 security.
4. HDN-374..377 integrity/API/storage gates.
5. HDN-378..382 security, performance, UX and observability gates.
6. HDN-383..385 backup/restore, DR and migration rehearsal gates.
7. HDN-386 integrated hardening verification.
8. HDN-387 blocker triage/remediation.
9. HDN-388 documentation handoff.
10. HDN-389 independent closure.

## Required output

Write execution index, hardening matrix, blocker ledger, test strategy, source-domain ownership evidence plan, severity policy, rollback plan, runbook checklist, Step 16 eligibility criteria and exact next eligible prompt. Do not set `FULL_SYSTEM_HARDENING_VERIFIED`.

