# Prompt 106 — Subscription, Module and Feature Entitlement

**Prompt ID:** `CG-S6-PLT-003`  
**Package document:** `CG-AABPP-PLT-106`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-106.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-003` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Multi-Tenancy; Epic: Commercial Control Plane; Capability: Entitlement evaluation; Feature slice: Versioned package/module/feature limits and lifecycle; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned tenant entitlements for subscription package, modules, features, quotas and effective dates without replacing RBAC.

## 5. Business value

Ensure tenants access only subscribed capabilities while preserving separate user authorization.

## 6. Source requirement

PLT-TNT-001..004; entitlement decisions; pricing/package policy; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Entitlement schema/migrations/service/guards/tests/docs and bounded presentation context. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Billing/finance implementation, broad portal, hard-coded tenant exceptions and unrelated roles. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Create versioned entitlement/package/tenant assignment/limit records with tenant keys, constraints, effective dates and audit.

## 14. API impact

Shared server entitlement evaluation/admin contract for REST/GraphQL/SSR/jobs.

## 15. UI/UX impact

Provide typed evaluated state/reason for later navigation/admin; no client-only enforcement.

## 16. Security impact

Entitlement is necessary but never sufficient authorization; no cross-tenant/package tampering.

## 17. Performance impact

Cache deterministic evaluation by tenant/version with invalidation; no per-row remote lookup.

## 18. Audit impact

Record package/version/assignment/change/override/reason/effective actor.

## 19. Data migration impact

Migrate existing tenant subscriptions deterministically; no default broad grant.

## 20. Detailed implementation tasks

1. Define package/module/feature/quota taxonomy, states, precedence and effective-date behavior.
2. Implement versioned data model/evaluator and tenant assignment/renewal/trial/suspend/expire transitions.
3. Integrate server guard primitive and safe client presentation context without authorization bypass.
4. Add cache invalidation, usage/limit hooks, tests, docs and admin dependencies.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Active entitled tenant passes module/feature/limit check at correct version/date.

## 22. Alternative flow

Trial/grace/override uses explicit authority/expiry/reason and remains audited.

## 23. Exception flow

Expired/suspended/missing/conflicting/stale entitlement fails closed with actionable reason.

## 24. Business rules

- Entitlement does not grant role/record/field access.
- Canonical module/feature IDs are stable; labels/package names may change.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Effective dates, versions, limits and precedence deterministic; unknown defaults deny.
- Cache invalidates on assignment/version/lifecycle change.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme controls catalogue; authorized Tenant Admin views own package/usage, not global packages/other tenants.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple packages/tenants/modules/features/limits, trials, overrides, expiry, suspension and stale cache. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Evaluator/precedence/effective date/quota/cache tests.
- Cross-tenant tampering, RBAC-combination, API/UI/job and audit tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Tenant lifecycle, future navigation, API guards, jobs and billing assumptions.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-106.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Entitlements evaluate correctly at every boundary without replacing access controls.
- No silent broad grant; version/audit/cache evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

