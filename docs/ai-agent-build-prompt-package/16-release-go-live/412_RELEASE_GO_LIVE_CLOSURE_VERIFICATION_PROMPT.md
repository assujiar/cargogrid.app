# Prompt 412 — Release Go-Live Closure Verification

**Prompt ID:** `CG-S16-RGL-022`  
**Package document:** `CG-AABPP-RGL-412`  
**Version:** `0.17.0`  
**Runtime output:** `docs/build-log/release-go-live/RELEASE_GO_LIVE_CLOSURE_REPORT.md`

Do not begin until Prompt 411 is `VERIFIED`, the active checkpoint still carries `FULL_SYSTEM_HARDENING_VERIFIED`, and all Step 16 release/go-live, deployment, validation, rollback/hypercare/PIR and handoff evidence is available for independent review.

## Objective

Independently verify release candidate freeze, no-new-feature discipline, defect triage, CI, clean rebuild, migration/seed validation, staging/UAT/prod deployment, smoke/security/performance evidence, go/no-go decision, post-deployment validation, rollback decision, hypercare, PIR and Step 17 final validation eligibility.

## Required verification

1. Verify Prompts 391–411 at one release candidate lineage and reconcile every WBS, dependency, approval and evidence link.
2. Confirm the release candidate was frozen and no feature scope entered after freeze.
3. Confirm defect triage has no unresolved Sev-1/Sev-2, critical/high tenant, security, finance, data loss, migration, rollback or production-readiness blocker.
4. Confirm full CI gate passed without suppressing lint, typecheck, tests, build, migrations, generated types/specs, audits or release checks.
5. Confirm clean database rebuild and upgrade path work from trusted migrations and seed/reference data.
6. Confirm migration validation and seed validation are complete, redacted and reproducible.
7. Confirm staging and UAT deployments used the approved candidate, environment, secrets references, feature flags and observability.
8. Confirm UAT acceptance exists for critical lead-to-cash, shipment-to-billing, finance, WMS, portal, loyalty, ticket and tenant isolation flows.
9. Confirm smoke test passed after each required deployment/cutover step.
10. Confirm penetration test evidence is in scope, retested and does not leave critical/high open findings.
11. Confirm performance evidence passes agreed budgets or blocks go-live.
12. Confirm go/no-go report records evidence, residual risks, approvals, no-go criteria and decision authority.
13. Confirm production deployment, if executed, followed the approved change window, backup, migration, feature flag, monitoring and communication plan.
14. Confirm post-deployment validation covers health, data, tenant, finance, API, files, jobs, observability and user-visible workflows.
15. Confirm rollback decision tree and actual rollback readiness are documented, tested and authority-bound.
16. Confirm hypercare plan is active or complete with support tiers, SLA, monitoring, known issues, incident/RCA process and customer communication.
17. Confirm PIR captures delivery, quality, data, performance, adoption, support, incidents and improvement backlog when applicable.
18. Confirm production-ready, market-ready and GA claims are only made if all source-defined gates are satisfied.
19. Confirm no tenant-real data entered source control and no secret/signed URL/provider credential leaked into evidence.
20. Confirm final package validation can proceed to Step 17 with exact evidence index and no hidden blocker.

## Closure states

- `RELEASE_GO_LIVE_VERIFIED`: every mandatory release/go-live gate passes and no unresolved critical/high blocker remains.
- `RELEASE_GO_LIVE_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Step 17 is blocked until accepted or repaired.
- `RELEASE_GO_LIVE_NO_GO`: release or production go-live must not proceed.
- `RELEASE_GO_LIVE_BLOCKED`: a mandatory release, UAT, deployment, rollback, support or approval gate is missing or unsafe.
- `RELEASE_GO_LIVE_ROLLED_BACK`: the system returned to a trusted checkpoint and must resume.

## Required output

Write release/go-live closure report; release candidate identity; environment and deployment evidence; CI/build/migration/seed reports; UAT acceptance; smoke/security/performance evidence; go/no-go decision; production/post-deployment validation; rollback readiness; hypercare/PIR status; support readiness; residual risks; documentation/runbook index; Step 17 eligibility; exact resume/next prompt.

## Completion gate

Set `RELEASE_GO_LIVE_VERIFIED` only if every mandatory release/go-live check passes and no unresolved critical/high blocker remains. This is the final runtime gate before Step 17 package validation. For package generation, the exact next command after Step 16 validation is `LANJUT STEP 17`.
