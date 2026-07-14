# Prompt 378 — Security Hardening

**Prompt ID:** `CG-S15-HDN-010`  
**Package document:** `CG-AABPP-HDN-378`  
**Version:** `0.16.0`  
**Runtime build log:** `docs/build-log/full-system-hardening/HDN-378.md`

Do not begin until Prompt 369 marks this task `READY`, all variables are resolved, and `PHASE_9_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S15-HDN-010` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Step 15 — Full-System Hardening`; package `0.16.0`.

## 3. Workstream

Workstream: Security Assurance; Epic: Application Security; Capability: Security Hardening; Feature slice: OWASP-style abuse, dependency, secret, injection and incident readiness; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Harden application, API, database, storage, jobs, integrations and AI surfaces against common and business-specific attacks.

## 5. Business value

Reduce exploitable security risk before release candidate work.

## 6. Source requirement

Master Prompt Step 15 Security hardening; Security Guardrails; Delivery penetration test requirement.. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 9 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant isolation, security, financial integrity, data lineage, API compatibility, storage, performance, accessibility, observability, backup/restore, DR, migration or release-boundary conflict.

## 9. Upstream dependencies

HDN-372..377 and Phase 9 enterprise security evidence.. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HDN-386 and Step 16 penetration/release gates.. Identify affected schemas, services, REST/GraphQL/public API/webhooks, reports/dashboards, jobs/integrations/files, AI/automation, enterprise controls, tests, docs and release candidate gates.

## 11. Allowed files/folders

Use only exact Step 15 hardening, verification, repair, test, evidence, runbook and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files for bounded repair and at most 1–3 additive migrations if absolutely required.

## 12. Forbidden files/folders

New product features, release/go-live Step 16 work, tenant forks, applied-migration edits, destructive cleanup, production mutation, permission/RLS/test weakening, fake pass evidence, unrelated user-owned changes and any critical-action automation expansion.

## 13. Database impact

Inspect grants, policies, functions, extensions, secrets references, audit, security events and privileged paths. Any repair must be additive, reversible, source-domain safe and accompanied by migration/recovery evidence.

## 14. API impact

Test auth/session, CSRF, XSS, SQL injection, IDOR, SSRF, open redirect, rate limit, API key, webhook, file upload and prompt injection paths. Do not break REST/GraphQL/public API/webhook/export contracts without approved versioning/deprecation and compatibility tests.

## 15. UI/UX impact

Verify secure UX for sessions, MFA, impersonation, denied states, sensitive exports and security warnings. Preserve responsive online-first behavior, accessibility, complete states and no fake success/dead action.

## 16. Security impact

Enforce tenant/RLS/RBAC/field/record/file/API/webhook/secret/MFA/session/support/AI policy in database/service as applicable, not UI only. Protect service role, secrets, signed URLs, logs, AI prompts/outputs, provider payloads and evidence. Preserve RPD-022 disclosure.

## 17. Performance impact

Measure or verify p95, query count, payload size, job duration, queue depth, cache behavior and load profile where relevant. No `SELECT *`, global realtime fanout, browser-loaded full dataset, unbounded export/report/import/AI/API workload or unsafe cross-tenant cache.

## 18. Audit impact

Record actor, tenant/scope, source/config/model/provider version, correlation/idempotency key, before/after or event chain, approval/human decision, denial, privileged/support access, file/API/webhook access and evidence links. Evidence must be source-linked, redacted and privacy-safe.

## 19. Data migration impact

Use additive or expand-and-contract migrations only; never edit applied migrations. Verify clean install, upgrade path, rollback, restore and reconciliation impact for any repair. Do not fabricate historical data.

## 20. Detailed implementation tasks

- Run dependency/security scans available in repository.
- Run abuse tests for auth/session/access/API/file/integration/AI paths.
- Verify service-role/secrets are server-only and logs are redacted.
- Test incident response, key rotation and privileged access audit.
- Remediate or block every critical/high security issue.

## 21. Main flow

Security hardening executes abuse suites, repairs bounded vulnerabilities and produces a ranked evidence-backed security report.

## 22. Alternative flow

An issue requires external pen test or provider fix; record blocker, mitigation, owner and no-go impact.

## 23. Exception flow

On critical/high failure, stop affected release path, preserve evidence, classify severity, assign owner and create exact bounded remediation/resume. Do not hide, downgrade, suppress, disable or work around a gate without root-cause evidence and authorized acceptance.

## 24. Business rules

- No release with critical tenant isolation or security defect.
- Secrets never appear in client, logs, exports, AI prompts or error messages.
- Dependency vulnerabilities are ranked with actual exploitability and remediation.
- Prompt injection is treated as hostile input.
- Incident/key rotation runbooks must exist before release.
- No release may proceed with critical/high tenant isolation, security, financial integrity, privacy, source-domain, migration, backup/restore or DR blocker.
- RPD-022 Supreme Admin absolute CRUD remains accepted residual risk; never claim immutable-for-all or tamper-proof behavior.
- RPD-021 requires human approval before AI/OCR legal, financial, payroll, payment, tax or critical status effects.
- RPD-023 requires MFA/current authorization for privileged, export, API key, support, financial, payroll, AI approval and security actions.
- RPD-025 retention and legal hold override must be tested across database, files, logs, reports, exports, AI evidence and audit.

## 25. Validation rules

Validate checkpoint compatibility, deterministic fixtures, allowed/denied roles, source versions, idempotency, concurrency, compatibility, access policy, performance budget, backup/restore or migration evidence where applicable, and expected versus actual results. Reject mixed-checkpoint evidence and undocumented assumptions.

## 26. Access rules

Use least-privileged roles for Supreme Admin, User Admin, internal hierarchy, Customer User, support user, API client, webhook endpoint, automation job and AI/service account tests. Privileged/Supreme tests are isolated, reasoned, redacted and explicitly marked as residual-risk evidence.

## 27. Test data requirement

Tenant A/B, multiple companies/branches/departments/teams/customers/sites/vendors/employees/support/API clients, critical financial records, shipments, inventory, documents, tickets, loyalty ledgers, AI evidence, integrations, reports, exports, malicious payloads, revoked users, stale sessions, concurrent retries and target-volume fixtures.

## 28. Tests to create/update

- Security Hardening automated/manual hardening tests.
- Positive and negative tenant/access/field/file/API/job/report/export cases.
- Critical E2E, idempotency, concurrency, retry/DLQ and rollback/recovery tests where applicable.
- Regression test proving each repaired defect cannot recur.
- Browser/accessibility/performance/security/migration evidence proportional to risk.
- Persistent evidence and exact reproduction for failures.

## 29. Regression tests

Re-run every critical suite touched by repairs across Platform, Commercial, Operations, Advanced TMS/WMS, Procurement, Finance, HRIS/Ticketing, Customer Portal/Loyalty and Intelligence/Enterprise. Compare baseline before/after and record pre-existing failures separately.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/job/browser/accessibility/security/build plus relevant migration, Supabase, API spec, webhook replay, AI eval, load/performance, backup/restore, DR and migration rehearsal commands. Never disable or suppress a gate.

## 31. Documentation to update

Update full-system hardening build log, test/evidence matrix, blocker register, issue/error ledger, change manifest, traceability, source-domain ownership, security/performance/accessibility/DR/migration runbooks and exact release-candidate handoff artifacts relevant to Security Hardening.

## 32. Rollback/recovery note

For any repair, define feature flag/rollback, migration down/forward strategy, data reconciliation, job/API/webhook replay handling, file cleanup, evidence preservation and exact resume. State last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Security Hardening hardening gate passes or has explicit release-blocking issue with owner and reproduction.
- No critical/high tenant isolation, security, financial integrity, privacy, API compatibility, source-domain, backup/restore, DR or migration blocker remains unowned.
- Tests, evidence, docs and rollback are updated at one compatible checkpoint.
- Repairs are bounded, regression-tested and do not weaken controls.
- Step 16 eligibility impact is explicit.

## 34. Definition of Done

Hardening work is complete, evidence-backed, reproducible and documented; mandatory gates run without suppression; residual issues are ranked and owned; rollback/resume is safe; no unsupported production/pilot/GA claim is made.

## 35. Completion report format

Report task/prompt IDs; checkpoint/environment; changed files/migrations/contracts; commands and results; hardening matrix; failures/fixes; tenant/access/security/finance/API/storage/performance/accessibility/observability/backup/DR/migration evidence as applicable; residual blockers; docs; rollback/resume; Step 16 go/no-go impact. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean HDN prompt after this task is `VERIFIED`. Do not set the final hardening closure flag; only Prompt 389 may set `FULL_SYSTEM_HARDENING_VERIFIED`.

