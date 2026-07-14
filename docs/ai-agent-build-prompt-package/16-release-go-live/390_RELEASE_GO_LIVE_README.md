# Step 16 — Release Candidate and Go-Live Prompt Package

**Package version:** `0.17.0`  
**Package document:** `CG-AABPP-RGL-390`  
**Directory:** `16-release-go-live/`  
**Runtime prerequisite:** `FULL_SYSTEM_HARDENING_VERIFIED`  
**Next phase unlocked by runtime closure:** Step 17 only after Prompt 412 verifies release/go-live closure.

This package decomposes Step 16 into atomic AI-agent release, deployment, go-live, hypercare and post-implementation review prompts. It does not add product features and does not claim runtime implementation. Its purpose is to prove that a hardened CargoGrid release candidate can be frozen, verified, deployed, validated, supported and reviewed without hiding blockers.

## Included source scope

Step 16 minimum scope:

- Release Candidate freeze.
- No-new-feature rule.
- Defect triage.
- Full CI gate.
- Clean database rebuild.
- Migration validation.
- Seed validation.
- Staging deployment.
- UAT deployment.
- Smoke test.
- Penetration test evidence.
- Performance evidence.
- Go/no-go report.
- Production deployment.
- Post-deployment validation.
- Rollback decision.
- Hypercare.
- Post-implementation review.

## Non-negotiable gates

- No go-live without `FULL_SYSTEM_HARDENING_VERIFIED`.
- No new feature after RC freeze.
- No production deployment without recorded go decision.
- No critical/high tenant isolation, security, financial, data loss, migration or rollback blocker.
- No disabled RLS/RBAC/test/security/financial control to pass a gate.
- No production-ready, market-ready or GA claim without Prompt 412 closure evidence.
- No tenant-real data in source control.
- Rollback path, support readiness, UAT acceptance, monitoring and runbooks must be available before production release.

## Execution order

1. Execute Prompt 391 to create the Step 16 WBS, release execution index and gate ledger.
2. Execute Prompts 392–409 in dependency order unless the execution index records a stricter order.
3. Execute Prompt 410 for integrated release/go-live verification.
4. Execute Prompt 411 for documentation, runbook, release note and Step 17 handoff.
5. Execute Prompt 412 for independent closure.

## Runtime states

- `NOT_STARTED`: prompt exists but no repository task has begun.
- `READY`: WBS and prerequisites are satisfied.
- `IN_PROGRESS`: execution has started.
- `BLOCKED`: a prerequisite, environment, evidence, security, data, finance, migration, deployment, support or approval gate is missing.
- `FAILED`: execution produced an invalid or unsafe result.
- `VERIFIED`: evidence proves completion.
- `NO_GO`: release/go-live must not proceed.
- `ROLLED_BACK`: deployment or candidate state returned to a trusted checkpoint.

## Package boundary

Step 16 may prepare and execute release/go-live runtime prompts only after hardening runtime closure. Step 16 package generation is not release execution, production deployment, UAT acceptance, production-ready status, market-ready status or GA.

## Next command after package validation

`LANJUT STEP 17`
