# Prompt 391 — Release Go-Live WBS Runtime Kickoff

**Prompt ID:** `CG-S16-RGL-001`  
**Package document:** `CG-AABPP-RGL-391`  
**Version:** `0.17.0`  
**Runtime output:** `docs/build-log/release-go-live/00_RELEASE_GO_LIVE_EXECUTION_INDEX.md`

Do not begin unless `FULL_SYSTEM_HARDENING_VERIFIED` exists at the active checkpoint and Step 16 has explicit runtime authority.

## Objective

Create the repository-specific Step 16 release/go-live WBS, execution index, release candidate identity, environment matrix, approval ledger, blocker ledger, rollout plan and rollback/resume path.

## Required actions

1. Confirm active repository, branch, HEAD, release candidate tag/commit, hardening closure evidence and authority.
2. Confirm no unresolved critical/high hardening, tenant, RLS/RBAC, security, financial, API, storage, performance, accessibility, observability, backup/restore, DR or migration blocker exists.
3. Build a WBS for Prompts 392–412 with owner, dependency, environment, evidence path, approval gate and rollback path.
4. Define release states: `RC_FROZEN`, `UAT_READY`, `UAT_ACCEPTED`, `GO_DECIDED`, `PRODUCTION_DEPLOYED`, `POST_DEPLOYMENT_VALIDATED`, `HYPERCARE_ACTIVE`, `PIR_COMPLETE`, `RELEASE_GO_LIVE_VERIFIED`, `NO_GO`, `ROLLED_BACK`.
5. Define environment gates for staging, UAT and production, including secrets references, migrations, seeds, feature flags, observability, backup, support and communication.
6. Define defect severity and no-go policy for Sev-1/Sev-2, critical/high tenant, security, finance, data loss, migration, rollback, performance, accessibility and support readiness issues.
7. Confirm no new feature, scope expansion, native/offline-sync claim, unsupported GA claim or market-ready claim is allowed in Step 16.
8. Write execution index, gate matrix, defect ledger, UAT evidence plan, go/no-go approval plan, deployment/cutover plan, rollback decision tree, hypercare plan, PIR plan and Step 17 eligibility criteria.

## Required output

Write `docs/build-log/release-go-live/00_RELEASE_GO_LIVE_EXECUTION_INDEX.md`, release WBS, dependency graph, environment matrix, gate ledger, defect ledger, approval matrix, communication plan, rollback plan, support/hypercare plan, PIR plan and exact next eligible prompt. Do not set `RELEASE_GO_LIVE_VERIFIED`.

## Completion gate

Mark only authorized, dependency-clean tasks as `READY`. If any mandatory prerequisite is missing, mark Step 16 `BLOCKED` and stop. Exact next prompt after successful kickoff is Prompt 392.
