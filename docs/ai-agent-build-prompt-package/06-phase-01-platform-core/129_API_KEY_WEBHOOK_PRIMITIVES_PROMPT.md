# Prompt 129 — API Key and Webhook Primitives

**Prompt ID:** `CG-S6-PLT-026`  
**Package document:** `CG-AABPP-PLT-129`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-129.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-026` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: API and Integration; Epic: Machine Integration Security; Capability: API keys and webhooks; Feature slice: Scoped credential lifecycle and signed delivery primitives; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-scoped hashed API key lifecycle and signed webhook endpoint/delivery primitives.

## 5. Business value

Enable future integrations securely with rotation, revocation, replay protection, retry and audit.

## 6. Source requirement

PKG-PLT-KEY-001; PLT-MDM-001..004; API/integration architecture; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

API key/webhook schema/migrations/service/auth/delivery/tests/docs/runbook. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Live third-party endpoints without authority, plaintext keys, generic provider integration hub. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Hashed key metadata/scopes/tenant/status/expiry and webhook endpoint/secret refs/events/deliveries/attempts with RLS/indexes.

## 14. API impact

Create-once-display/rotate/revoke/list key and endpoint/test/disable/status contracts; webhook version/signing/idempotency.

## 15. UI/UX impact

Admin view models/states later; secrets never re-displayed.

## 16. Security impact

Hash keys, server secret refs, least scopes, expiry/rate, signature/timestamp/replay, URL/SSRF controls and rotation.

## 17. Performance impact

Key lookup constant/indexed; webhook async batching/rate/backoff/DLQ.

## 18. Audit impact

Credential create/reveal-once/rotate/revoke/use and webhook endpoint/change/delivery/replay/disable.

## 19. Data migration impact

Existing plaintext credentials require explicit rotation; never migrate values into source/logs.

## 20. Detailed implementation tasks

1. Define key format/hash/scopes/lifecycle/rate and webhook event/version/signature/replay contracts.
2. Implement credential lifecycle/authentication and rate/revocation cache.
3. Implement endpoint validation, signed async delivery/retry/DLQ/reconciliation/disablement.
4. Add security/SSRF/replay/rotation tests, observability, docs and runbook.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Valid scoped key authenticates allowed operation; subscribed endpoint receives one signed event.

## 22. Alternative flow

Key/secret rotation overlaps safely within explicit window; retry delivers idempotently.

## 23. Exception flow

Revoked/expired/wrong-scope key, invalid endpoint/signature/replay/rate/outage fails safely.

## 24. Business rules

- Key value is shown only once and stored hashed; webhook secret stored server-side.
- Webhook event is notification, not authority to bypass canonical validation.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Scope/tenant/expiry/revocation/rate and signature/timestamp/event ID/version deterministic.
- Retry does not duplicate effective consumer event.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Tenant Admin manages own allowed credentials/endpoints; Supreme controls global policy with audit.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/scopes, revoked/expired/rotated keys, invalid URLs, replay/duplicate/outage/rate cases. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Key hash/auth/scope/expiry/rotation/revoke/rate tests.
- Webhook URL/SSRF/signature/replay/idempotency/retry/DLQ/cross-tenant/audit tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Auth/RBAC/RLS, jobs/notifications, API contracts and secret scanning.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-129.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Credentials/webhooks are scoped, rotatable, revocable, signed and observable.
- No plaintext/replay/SSRF/cross-tenant weakness; tests/docs pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

