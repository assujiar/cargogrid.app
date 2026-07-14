# Template 59 — Integration Adapter

**Prompt ID:** `CG-S4-REUSE-007`  
**Package document:** `CG-AABPP-REUSE-059`  
**Version:** `0.5.0`  
**Intended use:** Implement one bounded custom third-party integration adapter.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

API and Integration.

## 4. Objective

Implement {{PROVIDER_INTEGRATION}} as a case-by-case adapter inside the shared codebase with secure credentials and recoverable synchronization.

## 5. Business value

Connect an external provider without tenant forks or a prohibited generic provider abstraction.

## 6. Source requirement

{{INTEGRATION_REQUIREMENT_IDS}}, {{PROVIDER_CONTRACT_VERSION}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Store tenant-scoped configuration, mappings, sync state, idempotency and delivery logs with RLS and retention.

## 14. API impact

Implement provider-specific request/response/webhook mapping with versioned internal contract and compatibility evidence.

## 15. UI/UX impact

Provide configuration/status/error/retry UX only if authorized; secrets are never readable after storage.

## 16. Security impact

Server-only credentials, encryption/secret manager, scoped access, signing verification, replay protection, SSRF/egress controls and rotation.

## 17. Performance impact

Use async jobs, bounded concurrency, provider rate limits, backoff/jitter, batching and timeouts.

## 18. Audit impact

Audit configuration, credential rotation, sync attempts, mapping changes, retries and privileged actions with redaction.

## 19. Data migration impact

Mapping/backfill must be idempotent and separately checkpointed; do not import real tenant samples into source.

## 20. Detailed implementation tasks

1. Verify provider documentation/version/sandbox and define bounded adapter ownership.
2. Implement credential/config, canonical mapping, request/webhook, idempotency, retry/DLQ and reconciliation.
3. Handle provider limits, partial success, duplicate/out-of-order events, schema drift and disablement.
4. Add contract fixtures, sandbox tests, monitoring, alerts, runbook and tenant onboarding steps.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized tenant sends/receives canonical data and reconciles provider acknowledgement exactly once.

## 22. Alternative flow

Polling/manual retry or supported optional provider behavior preserves canonical ownership.

## 23. Exception flow

Credential expiry, rate limit, timeout, invalid signature, mapping failure, duplicate/out-of-order event and provider outage are contained/recoverable.

## 24. Business rules

- One custom adapter per approved integration; no generic non-AI provider abstraction and no tenant code fork.
- CargoGrid canonical data remains authoritative according to the data-flow map.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Mapping, units/timezones/currency/status codes and version are explicit.
- Webhook signature/timestamp/replay and idempotency checks are mandatory.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Tenant admins configure only their integration; support access is time/purpose-bound and audited.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Synthetic sandbox tenant, redacted provider fixtures, valid/invalid signatures, duplicates, rate limits, partial responses and mapping edge cases. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Mapping/contract, credential/access, webhook signature/replay, idempotency, retry/DLQ and reconciliation tests.
- Sandbox E2E, cross-tenant, outage, schema-drift and performance tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Canonical flows, existing adapters, jobs, audit, rate limits and tenant isolation.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Sandbox contract and failure/recovery evidence pass with no secret leakage.
- Adapter is owned, observable, documented and isolated without generic abstraction.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
