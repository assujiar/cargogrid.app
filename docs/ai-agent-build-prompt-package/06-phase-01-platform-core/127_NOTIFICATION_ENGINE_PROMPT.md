# Prompt 127 — Notification Engine

**Prompt ID:** `CG-S6-PLT-024`  
**Package document:** `CG-AABPP-PLT-127`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-127.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-024` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: User and System Communication; Capability: Notification orchestration; Feature slice: Versioned templates, preferences, queue and delivery evidence; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-aware in-app/email-ready notification primitives with templates, preferences, dedupe, retries and audit.

## 5. Business value

Provide consistent reliable communication hooks for workflows/approvals without hard-coded module sends.

## 6. Source requirement

PLT-CFG-001..004; notification requirements; job/config/localization; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Notification/template/delivery schema/migrations/service/queue/in-app UI/tests/docs and one bounded adapter interface. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Bulk marketing campaigns, live provider sends without authority, generic integration hub. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Notification/template/version/preference/delivery/attempt records with tenant keys, retention, RLS and indexes.

## 14. API impact

Template/admin/send/list/read/unread/preference/status contracts; external channel adapter remains bounded.

## 15. UI/UX impact

In-app notification list/count/read states and reusable preference view models if within split.

## 16. Security impact

Recipient authorization, template escaping, link allowlist, secret/PII minimization and cross-tenant protection.

## 17. Performance impact

Asynchronous queue, batching/dedupe/rate/backoff and paginated inbox.

## 18. Audit impact

Template changes, send trigger, recipient resolution, delivery attempts/results and privileged overrides.

## 19. Data migration impact

Map existing templates/preferences/deliveries explicitly; no real recipient sends during migration/tests.

## 20. Detailed implementation tasks

1. Define event→recipient→channel→template contract, template version/localization and preferences.
2. Implement in-app delivery model and async send/dedupe/retry/status primitives.
3. Implement safe template rendering/links/recipient resolution and external adapter interface.
4. Add failure/rate/preference/access/audit/tests/docs and workflow/approval hooks.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Platform event resolves authorized recipients and delivers one localized notification.

## 22. Alternative flow

User preference/channel unavailable uses allowed fallback/in-app delivery.

## 23. Exception flow

No recipient, invalid template, duplicate, rate limit/provider failure or revoked access is handled safely.

## 24. Business rules

- Notification is not workflow truth; source record/status remains authoritative.
- No hard-coded tenant content/recipient or generic integration hub.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Template/version/context/recipient/channel/dedupe deterministic.
- No send to unauthorized/deactivated/wrong-tenant user.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Template/admin/send/read/preferences follow tenant/role/record access.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, locales, preferences, duplicate events, revoked users, template injection and provider failures. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Template/render/localization/preference/dedupe/retry/status tests.
- RLS/RBAC/cross-tenant/XSS/link/recipient/access/audit/load tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Workflow/approval/user lifecycle/localization/jobs and existing notifications.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-127.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Notifications are reliable, deduplicated, localized and tenant-safe.
- Failure/retry/preference/audit evidence passes without real sends.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

