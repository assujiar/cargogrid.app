# Prompt 365 — Intelligence, Automation and Enterprise Security AI Hardening

**Prompt ID:** `CG-S14-IAE-037`  
**Package document:** `CG-AABPP-IAE-365`  
**Version:** `0.15.0`  
**Runtime build log:** `docs/build-log/phase-09/IAE-365.md`

Do not begin until all upstream tasks required by the execution index are `VERIFIED` and `PHASE_8_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S14-IAE-037` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 9 — Intelligence, Automation, and Enterprise Expansion`; package `0.15.0`.

## 3. Workstream

Workstream: Integrated Verification, Hardening, Documentation and Closure; Epic: Phase 9 Evidence Closure; Capability: Intelligence, Automation and Enterprise Security AI Hardening; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Harden Phase 9 security, AI governance, API/webhook compatibility, integration idempotency, enterprise IAM, monitoring, retention and deployment controls after integrated verification.

## 5. Business value

Reduce the most dangerous Phase 9 risks before closure: data leakage, autonomous AI action, broken API/webhook compatibility, provider failure and enterprise security gaps.

## 6. Source requirement

All Phase 9 master prompt requirements; Product Brief §10/§16; BPR NFR-SEC/AUD/REL/API/PERF and integration/performance rules; Technical Architecture/Security/Integration; Delivery Phase 9. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 8 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/RLS/access/AI/API/integration/Finance/legal/security/performance/enterprise-boundary conflict.

## 9. Upstream dependencies

IAE-364 VERIFIED. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

IAE-366..367. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, reports/dashboards, API/webhooks, AI providers, enterprise IAM/deployment/monitoring, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 9 security, AI, integration, enterprise hardening, test, evidence paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate source roots, autonomous critical AI action, tenant forks, applied-migration edits, destructive cleanup, production mutation, Step 15–16 full release work and hidden test/permission weakening.

## 13. Database impact

No planned feature schema except minimal registered defect repair. Inspect migrations, constraints, RLS, report/dashboard/analytics, automation, integration, API/webhook, AI governance, enterprise IAM, audit, monitoring, retention, deployment/DR/support tables and source ownership.

## 14. API impact

Verify or document REST/GraphQL parity, public API compatibility, webhook signing/versioning, authentication, authorization, field projection, idempotency, errors, cursor behavior, jobs/webhooks and domain handoffs across every Phase 9 service. Do not add unplanned endpoints.

## 15. UI/UX impact

Verify or document report/dashboard/API/integration/AI review/enterprise admin journeys, all states, accessibility, browser/responsive online-first behavior, human-governed AI states and no fake/dead action.

## 16. Security impact

Run or document tenant/access/API/webhook/OAuth/SSO/MFA/IP/file/report/export/cache/AI/prompt-injection/provider-secret/support abuse tests. Preserve RLS/RBAC, server-only secrets, private files, signed URLs, field policy, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Measure or document target-volume reports, dashboards, analytics refresh, scheduled reports, automation, API, webhooks, integrations, AI jobs, monitoring, retention/archive and DR tasks with declared environment/dataset/concurrency. Record no-regression threshold and workload isolation.

## 18. Audit impact

Verify or document actor/source/config/model/provider/scope/correlation/idempotency/before-after/event-chain evidence, human decision, sensitive-access minimization, denial logging and reconciliation retrieval.

## 19. Data migration impact

Verify or document clean install and Phase 8→9 upgrade, type/spec generation, seed privacy, rollback/forward recovery, analytics/report/API/webhook/AI/enterprise-control reconciliation and no applied-history edits.

## 20. Detailed implementation tasks

- Attack API keys, OAuth/SSO/session, webhooks, provider callbacks, reports/exports, caches, saved views and dashboard widgets for access leakage.
- Attack AI prompts, untrusted documents, OCR outputs, automation rules and risk signals for autonomous critical action or prompt injection.
- Stress queue/backpressure/retry/DLQ/idempotency across API, webhooks, reports, scheduled jobs, integrations and AI jobs.
- Harden enterprise IAM, MFA, IP restriction, advanced audit, monitoring, retention, data residency, DR and support access controls.
- Rerun targeted regression and document residual risks with owner/resume.

## 21. Main flow

Hardening attacks and repairs the highest-risk Phase 9 paths, then reruns targeted evidence before handoff.

## 22. Alternative flow

Parallelize truly non-overlapping test or documentation suites against the same build/schema/data profile, then reconcile to one final checkpoint before verdict.

## 23. Exception flow

On flaky, environment, provider, source mismatch or pre-existing failure, prove classification with reruns and baseline evidence; never suppress. On AI autonomy, data leak, API/webhook compatibility break, secret leak, SSO lockout, financial/legal unsafe action or DR/retention failure, stop affected flow, preserve evidence and follow incident/rollback procedure.

## 24. Business rules

- Evidence must come from one identified compatible checkpoint; mixed-commit results are invalid.
- All 34 capabilities require code/contract/spec/UI/job as applicable, tests, docs and owner or explicit blocker.
- Critical AI governance, API/webhook, tenant isolation, report/export, provider secret, enterprise IAM, retention, DR or Finance/legal failure blocks closure.
- Package completion is not runtime implementation or evidence.
- No production, pilot, GA or market-ready claim.
- RPD-004 responsive online-first PWA remains the supported client model; no native/offline-sync claim.
- RPD-011 shared database/shared schema with RLS remains default; dedicated instance is a paid Enterprise option only.
- RPD-013 APAC is default region; dedicated region/hosting is a contractual Enterprise option.
- RPD-017 Enterprise IAM order is OIDC, then SAML, then SCIM unless a signed contract changes priority.
- RPD-021 OpenAI multimodal is the default AI/OCR provider boundary; human approval is mandatory before financial/legal posting or critical status changes.
- RPD-022 Supreme Admin absolute CRUD is accepted residual risk; never claim immutable-for-all or tamper-proof behavior.
- RPD-023 MFA/current authorization for privileged, AI-approval, integration, API key, SSO, export and support actions.
- RPD-025 retention: finance/tax 10 years, audit/security 7 years, operational contract+90, legal hold override.
- RPD-028 includes 20 GB storage; AI/OCR, messaging, maps, e-sign and third-party services are billed at actual provider cost +20% with customer-visible metering.
- RPD-033 REST/GraphQL parity remains mandatory.
- RPD-038 non-AI integrations are case-specific shared-code adapters, not tenant forks.
- RPD-040 critical records retain applied configuration/source versions.

## 25. Validation rules

Validate checkpoint compatibility, requirement-to-evidence completeness, deterministic fixtures, expected versus actual, source/downstream totals, API/webhook compatibility, AI evaluation, provider failure classification and defect severity/ownership.

## 26. Access rules

Use least-privileged test roles for fixed principal layers plus API clients, webhook endpoints, AI/service accounts, support users and enterprise admins; privileged/Supreme tests are isolated, reasoned and redacted. Evidence storage itself is access-controlled.

## 27. Test data requirement

Multi-tenant shared/dedicated fixtures covering reports, dashboards, analytics, automation, public/customer/vendor APIs, webhooks, n8n, integrations, AI/OCR/prediction/optimization/risk/forecasting, SSO/OAuth/SAML/SCIM, MFA, IP, audit, monitoring, retention/archive, dedicated/region/scale/DR/support, malicious payloads, retries/races and target volumes.

## 28. Tests to create/update

- 34-capability traceability and critical-flow suite.
- Report/dashboard/export/cache/analytics workload isolation matrix.
- API/webhook/idempotency/rate-limit/version/deprecation/replay suite.
- Integration provider failure, retry, DLQ, secret redaction and no-tenant-fork suite.
- AI governance, prompt injection, human approval, evaluation and cost-meter suite.
- Enterprise IAM/MFA/IP/audit/monitoring/retention/deployment/DR/support suite.
- Responsive browser/WCAG and declared target-volume performance suite.

## 29. Regression tests

Run all critical Platform, Commercial, Operations, Advanced TMS/WMS, Procurement, Finance, HRIS/Ticketing and Customer Portal/Loyalty tests touched by API, reports, jobs, files, audit, AI, integrations, monitoring, retention, deployment or enterprise access contracts.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/job/browser/accessibility/security/build gates plus relevant migration, API spec, webhook replay, AI eval, load/performance, backup/restore, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Integrated evidence index, traceability matrix, API specs, webhook docs, AI governance/evaluation records, integration runbooks, enterprise IAM/monitoring/retention/deployment/DR/support reports, performance profile, migration/recovery report, defect register and IAE-365 build log.

## 32. Rollback/recovery note

If work mutates test state, reset only through supported fixtures/transactions; for defects restore last trusted checkpoint, preserve evidence and give exact bounded resume. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every Phase 9 capability has current source-to-runtime evidence or explicit blocker.
- AI, automation, API/webhook, integration and enterprise controls prove human governance, compatibility, idempotency and access safety.
- Tenant/field/file/API/job/migration/performance gates execute without suppression.
- No unresolved critical/high blocker may advance; findings are ranked and owned.
- Evidence is reconciled at one compatible checkpoint with no fabricated pass.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts/specs, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical tenant/security/AI/API/integration/enterprise blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts/specs; commands/results; capability/finding matrix; tenant/access/API/webhook/AI/integration/security/performance/enterprise evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release IAE-366 after this task is `VERIFIED`. Do not set the final Phase 9 closure flag; only Prompt 367 may do so.

