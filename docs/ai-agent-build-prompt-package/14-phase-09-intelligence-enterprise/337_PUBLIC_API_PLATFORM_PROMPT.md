# Prompt 337 — Public API Platform

**Prompt ID:** `CG-S14-IAE-009`  
**Package document:** `CG-AABPP-IAE-337`  
**Version:** `0.15.0`  
**Runtime build log:** `docs/build-log/phase-09/IAE-337.md`

Do not begin until Prompt 329 marks this task `READY`, all variables are resolved, and `PHASE_8_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S14-IAE-009` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 9 — Intelligence, Automation, and Enterprise Expansion`; package `0.15.0`.

## 3. Workstream

Workstream: API Ecosystem; Epic: Public API; Capability: Public API; Feature slice: External API gateway semantics, keys, scopes, rate limits, versioning and compatibility; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the governed public API layer over approved CargoGrid domain contracts with strict versioning, rate limits and idempotency.

## 5. Business value

Enable enterprise integrations without exposing internal implementation or creating duplicate business logic.

## 6. Source requirement

Phase 9 Public API; NFR-API-001; Delivery public API compatibility and penetration gate.. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 8 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/RLS/access/AI-governance/API/integration/Finance/legal/security/performance/enterprise-boundary conflict.

## 9. Upstream dependencies

Platform API-key primitives and REST/GraphQL parity contracts from prior phases.. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

IAE-338..341 and release/hardening gates.. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, AI provider boundary, reports/dashboards, public API/webhooks, enterprise IAM/deployment/monitoring, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 9 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate source-domain roots, autonomous AI critical actions, provider secrets in client/logs, tenant forks, applied-migration edits, destructive cleanup, Step 15–16 full release/hardening work, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

API application/client/key/scope/rate-policy/version/deprecation/idempotency/audit records. Preserve canonical domain ownership, tenant_id, source/config/model/provider versions, idempotency, audit, retention and rollback-safe additive migrations.

## 14. API impact

API key lifecycle, external REST/GraphQL endpoint wrappers, version negotiation, error contract and usage metering. REST and GraphQL must share authentication, authorization, field policy, idempotency, audit, version and compatibility semantics.

## 15. UI/UX impact

API developer console with keys, scopes, docs, rate usage, webhooks, deprecation notices and audit. Include keyboard/focus/labels, responsive online-first behavior, loading/empty/error/denied/stale/degraded/conflict states, human-review states for AI/automation and no dead action.

## 16. Security impact

Enforce tenant/RLS/RBAC/field/record/file/API-key/webhook/signature/IP/MFA/session/support policy in database/service as applicable, not UI only. Protect secrets, AI prompts/outputs, provider payloads and enterprise evidence. Preserve RPD-022 residual-risk disclosure.

## 17. Performance impact

Use selective projections, server filter/sort/search, cursor pagination, materialized views/read models where justified, async jobs/queues/backpressure for heavy work and measured evidence. No `SELECT *`, global realtime fanout, browser-loaded full dataset, unbounded AI/report/API workload or unsafe cross-tenant cache.

## 18. Audit impact

Record actor, tenant/scope, source/config/model/provider version, correlation/idempotency key, input/output hash where useful, before/after or event chain, approval/human decision, file/API/webhook access, denial, cost/usage and privileged/support evidence. Evidence must be source-linked and privacy-safe.

## 19. Data migration impact

Use additive or expand-and-contract migrations; never edit applied migrations. Adopt existing Platform, Commercial, Operations, WMS, Procurement, Finance, HRIS, Ticketing, Customer Portal and Loyalty references through explicit mapping; rehearse backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Define public API resource allowlist, scopes and versioning policy.
- Implement API client/key lifecycle and rate/idempotency controls.
- Wrap domain services without duplicating logic.
- Build developer console and generated docs/specs.
- Test auth, rate limit, idempotency, compatibility and abuse cases.

## 21. Main flow

Tenant creates an API client with scoped key, calls a versioned endpoint and receives consistent errors/rate/idempotency behavior.

## 22. Alternative flow

A breaking change is introduced under a new API version with deprecation path for older clients.

## 23. Exception flow

Block unauthorized scope, missing source version, unsafe AI/automation action, provider failure, webhook spoofing, duplicate API retry, unscanned file, stale analytics, incompatible schema, secret leakage, SSO lockout, unsupported enterprise claim or later-phase scope creep; preserve safe state and exact resume. Record blocker/error/issue, owner and safe resume; never hide or bypass failure.

## 24. Business rules

- Public API cannot bypass RLS/RBAC/domain service policies.
- Every mutation supports idempotency where retries can occur.
- Breaking changes require version/deprecation plan.
- Usage is metered for visibility and commercial controls.
- Secrets/API keys are hashed or protected and never shown after creation except one-time display if implemented.
- RPD-004 responsive online-first PWA remains the supported client model; no native/offline-sync claim.
- RPD-011 shared database/shared schema with RLS remains default; dedicated instance is a paid Enterprise option only.
- RPD-013 APAC is default region; dedicated region/hosting is a contractual Enterprise option.
- RPD-017 Enterprise IAM order is OIDC, then SAML, then SCIM unless a signed contract changes priority.
- RPD-021 OpenAI multimodal is the default AI/OCR provider boundary; human approval is mandatory before financial/legal posting or critical status changes.
- RPD-022 Supreme Admin absolute CRUD is accepted residual risk; never claim immutable-for-all or tamper-proof behavior.

## 25. Validation rules

Validate tenant/scope, role/field/record policy, source/config/model/provider version, idempotency, concurrency, approval, usage/cost meter, retention, compatibility, performance budget and downstream reconciliation before mutation. Reject cross-tenant references, stale updates, untrusted prompt/document instructions and unsafe inferred access.

## 26. Access rules

Supreme Admin, tenant admins, internal users, customer users, support users, API clients, webhook endpoints, automation jobs and AI/service accounts each require explicit least-privilege policy. Support/impersonation and enterprise admin actions are case-, purpose- and time-bound with MFA/current authorization.

## 27. Test data requirement

Tenant A/B, enterprise tenant, shared and dedicated deployment fixtures, multiple roles, API clients, webhook endpoints, failed providers, AI request/evidence cases, reports/dashboards, integrations, SSO/SCIM identities, high-volume events, secrets redaction, revoked users, malicious payloads and target-volume fixtures. Include deterministic IDs, allowed/denied roles and source/config/model versions.

## 28. Tests to create/update

- Public API unit/service/database/API/contract/job/UI tests.
- Tenant/RLS/RBAC/field/file/API/webhook/AI/enterprise isolation and negative tests.
- REST/GraphQL parity, idempotency, concurrency, version/compatibility and audit tests.
- Provider failure, retry/DLQ, backpressure, cost-meter and secret-redaction tests where applicable.
- Responsive browser/accessibility and no-dead-action tests.
- Migration/rollback/performance/security smoke coverage proportional to risk.

## 29. Regression tests

Re-run critical Platform, Commercial, Operations, Advanced TMS/WMS, Procurement, Finance, HRIS/Ticketing and Customer Portal/Loyalty tests touched by this task, especially source-domain ownership, API/webhook, jobs, files, audit, reporting, AI governance and enterprise access suites.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/job/browser/accessibility/security/build; add migration/type generation, API spec generation, webhook replay, AI eval, load/performance, backup/restore, failure-recovery and reconciliation commands as relevant. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Update Phase 9 build log, source-domain ownership notes, AI/automation/API/integration/enterprise runbooks, API specs, webhook event docs, report/dashboard metric docs, security/retention/DR docs, traceability, dependency, rollback and handoff artifacts relevant to Public API.

## 32. Rollback/recovery note

Disable affected Phase 9 feature flag, pause jobs/integrations/API clients/AI provider path, preserve source-domain truth, revert compatible code/policies and reconcile queued jobs/events/reports/AI outputs before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Public API works with canonical source-domain ownership and no duplicate truth.
- Tenant/access/field/file/API/webhook/AI/enterprise controls are enforced across database/service/API/UI/jobs/exports.
- Human governance, idempotency, audit, performance, migration, rollback and documentation gates pass.
- Source/config/model/provider versions and downstream reconciliation evidence are recorded.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI/job → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types/specs, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/AI/API/integration/enterprise blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts/specs; source/config/model/provider decisions; implementation; commands and baseline/after results; tenant/access/API/webhook/AI/integration/security/performance evidence; idempotency/concurrency/reconciliation/cost-meter evidence; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean IAE prompt after this task is `VERIFIED`. Do not set the final Phase 9 closure flag; only Prompt 367 may do so.

