# Prompt 402 — Penetration Test Evidence

**Prompt ID:** `CG-S16-RGL-012`  
**Package document:** `CG-AABPP-RGL-402`  
**Version:** `0.17.0`  
**Runtime build log:** `docs/build-log/release-go-live/RGL-402.md`

Do not begin until Prompt 391 marks this task `READY`, all variables are resolved, `FULL_SYSTEM_HARDENING_VERIFIED` matches the active checkpoint, and release authority confirms this task is inside Step 16 scope.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S16-RGL-012` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Step 16 — Release Candidate and Go-Live`; package `0.17.0`.

## 3. Workstream

Workstream: Security Control; Epic: Penetration Test Evidence; Capability: Penetration Test Evidence; Feature slice: Release/go-live gate for Penetration Test Evidence; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Verify penetration-test scope, findings, remediation evidence, retest status and residual risk for tenant, auth, access, file, injection, API, webhook and privileged paths.

## 5. Business value

Ensure security readiness evidence exists before GA, enterprise production or major public API launch.

## 6. Source requirement

Master Prompt Step 16 Penetration test evidence; Delivery Plan penetration test and security gate requirements.. Cite exact source sections, runtime evidence, approval records, decision/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, release candidate tag/commit, active environments, deployment target, schema/migration state, generated types/specs, feature flags, secrets references, runbooks, issue ledgers, known issues and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Step 15 closure report, release board authority, relevant runbooks and evidence. Confirm no unresolved critical/high tenant, security, financial, data loss, migration, backup/restore, DR, performance, accessibility or observability blocker exists unless this prompt explicitly records `NO_GO`.

## 9. Upstream dependencies

RGL-391 and verified hardening closure `FULL_SYSTEM_HARDENING_VERIFIED`. Every execution-index prerequisite must be `VERIFIED`, risk-accepted by allowed authority, or explicitly marked `NO_GO`.

## 10. Downstream impact

RGL-403, Step 17 final package validation, customer readiness, support readiness and production/rollback evidence. Identify affected schemas, services, REST/GraphQL/public API/webhooks, reports/dashboards, jobs/integrations/files, AI/automation, enterprise controls, tests, docs, runbooks and go/no-go gates.

## 11. Allowed files/folders

Use only exact Step 16 release/go-live, evidence, deployment, runbook, test, support, PIR and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files for bounded release evidence or defect correction and at most 1–3 additive migrations if the go/no-go record explicitly authorizes them.

## 12. Forbidden files/folders

New product features, scope expansion, tenant forks, applied-migration edits, destructive cleanup, permission/RLS/test weakening, fake pass evidence, undocumented production mutation, unrelated user-owned changes and any critical-action automation expansion. Production mutation, production data import, external GA claim and customer-facing launch action are forbidden in this prompt.

## 13. Database impact

Verify migrations, schema diff, RLS, constraints, indexes, seed/reference data, generated types and clean rebuild or upgrade evidence as applicable. Any authorized repair must be additive, reversible, source-domain safe and accompanied by migration/recovery/reconciliation evidence.

## 14. API impact

Verify REST/GraphQL/public API/webhook/export contracts, versioning, deprecation, rate limit, idempotency, signing and backward compatibility. Do not break external/customer/vendor contracts without approved versioning, communication and compatibility tests.

## 15. UI/UX impact

Verify critical internal, admin, customer, support and mobile/tablet workflows with loading/empty/error/denied/conflict/degraded states. Preserve accessibility, responsive online-first behavior, clear release messages and no fake success/dead action.

## 16. Security impact

Enforce tenant/RLS/RBAC/field/record/file/API/webhook/secret/MFA/session/support/AI policy in database/service as applicable. Protect service role, secrets, signed URLs, logs, release evidence, production credentials, support access and incident data. Preserve RPD-022 disclosure.

## 17. Performance impact

Verify p95, query count, payload size, job duration, queue depth, cache behavior, deployment warm-up and load profile where relevant. No `SELECT *`, browser-loaded full dataset, unbounded export/report/import/AI/API workload or unsafe cross-tenant cache.

## 18. Audit impact

Record actor, tenant/scope, environment, release candidate ID, commit, migration/version, approval, correlation/idempotency key, deployment/runbook step, before/after or event chain, denial/failure, rollback decision and evidence links. Evidence must be source-linked, redacted and privacy-safe.

## 19. Data migration impact

Verify migration/cutover data handling, snapshots, mapping, validation, duplicate control, reconciliation, rollback/rerun and tenant data protection where relevant. Do not put tenant-real data in source control or logs.

## 20. Detailed implementation tasks

1. Confirm task authority, checkpoint, release candidate identity and environment.
2. Reconcile prerequisite evidence from Step 15 and earlier phase closures.
3. Execute the gate-specific inspection, command, deployment, test or evidence review.
4. Capture failures with reproduction, severity, owner, customer impact and resume path.
5. Apply only authorized release-safe correction if required; otherwise mark blocker/no-go.
6. Re-run affected gates and update ledgers, runbooks, release notes and handoff.

## 21. Main flow

Execute Penetration Test Evidence against the approved release candidate at one checkpoint, collect evidence, classify failures, repair only authorized defects, and publish a clear pass/fail/no-go result.

## 22. Alternative flow

If the target environment/tool/provider is unavailable, stop risky actions, preserve evidence, classify the gate as blocked, record a retry window and resume from last trusted checkpoint.

## 23. Exception flow

If a tenant leak, financial corruption, security incident, migration failure, production instability, data loss, broken core E2E, failed backup/restore, failed rollback path or unauthorized scope change appears, stop promotion, open incident/blocker, notify the release authority and do not proceed to the next prompt.

## 24. Business rules

- No critical/high tenant/security/financial/data-loss defect may be accepted for production.
- No Sev-1/Sev-2 blocker may remain open at go/no-go.
- No release candidate may absorb new features after freeze.
- Production-ready, market-ready, GA and go-live labels require explicit gate evidence.
- RPD-022, RPD-036, RPD-016, RPD-021, RPD-023, RPD-025, RPD-032, RPD-033, RPD-038 and RPD-040 must remain disclosed where relevant.

## 25. Validation rules

Validate checkpoint consistency, environment identity, approval authority, command output, evidence completeness, severity classification, rollback path, data reconciliation, support readiness and next-step eligibility. Reject mixed-checkpoint evidence, stale screenshots, suppressed failures and undocumented assumptions.

## 26. Access rules

Use least privilege. Reauthorize tenant, role, field, record, file, support and production access on every risky action. Production access must be purpose-bound, time-bound, audited and approved.

## 27. Test data requirement

Use deterministic release fixtures, tenant-isolated UAT/staging data and approved migration samples. Real tenant data may be used only in authorized UAT/production migration paths with redaction, retention and access controls.

## 28. Tests to create/update

- Gate-specific automated or manual evidence checklist.
- Positive and negative tests for tenant/access/security/data/finance/API/file/job behavior as applicable.
- Smoke, regression, performance, migration, deployment or rollback tests required by this gate.
- Evidence that commands fail closed and no pass is fabricated.

## 29. Regression tests

Run affected regression suite plus critical E2E flows: lead to job, shipment to billing readiness, actual cost to AP settlement, invoice to journal, WMS inbound to outbound, portal visibility, loyalty liability, ticket SLA and Tenant A/B isolation.

## 30. Commands to run

Detect package manager and available scripts. Run relevant lint, typecheck, test, build, migration, seed, generated type/spec, security audit, e2e, smoke, performance, deployment or rollback commands for this gate. Record skipped commands only with concrete unavailable-script evidence.

## 31. Documentation to update

Update build status, task ledger, change manifest, error/known issues, release notes, deployment record, runbooks, support docs, go/no-go evidence, UAT/PIR records and handoff as applicable.

## 32. Rollback/recovery note

State last trusted checkpoint, rollback trigger, rollback owner, data reconciliation, migration forward/backward path, feature flag action, deployment reversal, communication plan, evidence preservation and exact resume step.

## 33. Acceptance criteria

- Penetration Test Evidence gate has complete evidence at one release candidate checkpoint.
- Failures are fixed with regression proof or block promotion with owner and resume path.
- No unauthorized feature, production, migration, tenant, security, finance or evidence shortcut is introduced.
- Required docs, ledgers, runbooks and release/go-live records are updated.

## 34. Definition of Done

Gate work is evidence-backed, reproducible, approved by required authority, documented and safe to resume; all mandatory commands/tests pass or explicitly block; residual risks are ranked and owned; no unsupported production-ready/market-ready/GA claim is made.

## 35. Completion report format

Report task/prompt IDs; checkpoint/environment; release candidate ID; changed files/migrations/contracts; commands and results; gate evidence; failures/fixes; tenant/access/security/finance/API/storage/performance/accessibility/observability/backup/DR/migration evidence as applicable; residual blockers; docs; rollback/resume; next go/no-go impact. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

If this task is `VERIFIED`, continue only to `RGL-403`. If blocked, resume this task or rollback according to the recorded recovery path.
