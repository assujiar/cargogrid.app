# Prompt 130 — REST and GraphQL Platform API Foundation

**Prompt ID:** `CG-S6-PLT-027`  
**Package document:** `CG-AABPP-PLT-130`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-130.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-027` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: API and Integration; Epic: Public Platform Contracts; Capability: REST/GraphQL shared foundation; Feature slice: Shared context/validation/errors/pagination/idempotency/versioning; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement shared REST and GraphQL platform API foundations over common services with identical access, validation, audit and performance controls.

## 5. Business value

Provide consistent extensible contracts without duplicated business logic or interface-specific bypass.

## 6. Source requirement

RPD REST+GraphQL; Technical API architecture; PKG performance/security controls; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Shared API middleware/schema/context/errors/pagination/server/tests/docs and bounded representative operations. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Broad domain APIs, duplicated interface business logic, unbounded queries. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

No direct interface-specific DB bypass; shared service/repository uses RLS/transactions/pagination.

## 14. API impact

Primary scope: context, schema/input validation, errors, version/deprecation, pagination/filter/sort, idempotency, correlation, GraphQL complexity/batching.

## 15. UI/UX impact

Provide typed clients/contracts only if approved; no feature pages.

## 16. Security impact

Auth/entitlement/RBAC/RLS/field/record parity, rate/CORS/CSRF, input/injection/IDOR, persisted operation/introspection policy.

## 17. Performance impact

No N+1/SELECT */unbounded payload; complexity/depth, resolver batching, timeouts and cancellation.

## 18. Audit impact

Correlate API actor/context/operation/outcome/privileged mutations without sensitive payload.

## 19. Data migration impact

No data migration; contract version transition explicit.

## 20. Detailed implementation tasks

1. Define shared request context/error/pagination/idempotency/version/security contracts.
2. Implement REST middleware/handlers and GraphQL server/schema/resolver foundations over shared services.
3. Implement GraphQL depth/complexity/batching/field access and REST resource/filter controls.
4. Add parity/contract/security/performance/observability/docs and representative Platform Core operations.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized REST and GraphQL calls execute same service and return equivalent permitted result.

## 22. Alternative flow

Paginated/filter/idempotent/conditional operation follows documented interface form.

## 23. Exception flow

Invalid/unauthorized/too complex/rate/conflict/timeout/internal failure yields safe stable error.

## 24. Business rules

- Neither interface is secondary or may bypass common service/access rules.
- Breaking changes require version/deprecation/consumer plan.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Contract/error/pagination/idempotency/access parity machine-tested.
- GraphQL complexity/field access and REST input/resource constraints enforced.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- All four layers/API keys/service identities mapped per operation/field/record.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants/roles/scopes, valid/invalid payloads, large pages, duplicate/concurrent/complex queries and sensitive fields. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- REST/GraphQL contract/parity/schema/error/pagination/idempotency tests.
- Auth/RBAC/RLS/field/record/IDOR/injection/rate/complexity/N+1/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Platform services, auth/context, audit, API keys/webhooks and build/types.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-130.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- REST/GraphQL foundations share behavior with no access/validation/performance bypass.
- Contracts/docs/security/parity evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

