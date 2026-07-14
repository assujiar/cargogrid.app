# Prompt 117 — White-Label Foundation

**Prompt ID:** `CG-S6-PLT-014`  
**Package document:** `CG-AABPP-PLT-117`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-117.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-014` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Tenant Experience; Epic: Tenant Branding; Capability: White-label configuration; Feature slice: Versioned tenant brand tokens/assets/templates; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-scoped white-label configuration using governed tokens/assets and canonical semantic constraints.

## 5. Business value

Let tenants present their brand without code forks or altered business meaning.

## 6. Source requirement

PLT-WLB-001..004; design-system foundation; tenant/config decisions. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Brand config schema/migrations/evaluator/shared theme/assets/tests/docs within foundation. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Tenant-specific source forks, broad page redesign, arbitrary CSS/JS and unscanned assets. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Versioned tenant brand config/assets refs, draft/publish/effective date/rollback, constraints and RLS.

## 14. API impact

Permission-aware config/read/evaluate contract with cache invalidation.

## 15. UI/UX impact

Apply approved logo/color/typography/template tokens across shared shell/components with accessible fallbacks.

## 16. Security impact

Validate assets/URLs/content, malware scan files, prevent CSS/script injection and cross-tenant cache leakage.

## 17. Performance impact

Optimize assets/cache by tenant+version; prevent layout/bundle/runtime bloat.

## 18. Audit impact

Record brand draft/publish/change/rollback/asset access and actor.

## 19. Data migration impact

Map existing theme variables/assets safely; no tenant-specific code branch.

## 20. Detailed implementation tasks

1. Define canonical brand tokens/asset types, validation and accessibility constraints.
2. Implement versioned draft/publish/rollback model and evaluator/cache.
3. Integrate shared shell/design-system token application and safe fallbacks.
4. Add asset/security/contrast/cache/cross-tenant tests, docs and admin dependencies.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Tenant publishes valid brand version and authorized surfaces render it consistently.

## 22. Alternative flow

Missing/invalid tenant override uses accessible CargoGrid/default theme.

## 23. Exception flow

Unsafe asset/CSS, poor contrast, invalid token or cross-tenant cache key is rejected.

## 24. Business rules

- Branding changes presentation only; canonical terminology/status/access remain stable.
- No tenant code fork or arbitrary executable style/script.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Token schema/assets/contrast/effective versions deterministic.
- SSR/client/cache resolve same tenant version without flash/leak.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Tenant Admin manages own permitted brand; Supreme may manage defaults/override with audit.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/themes, valid/invalid colors/assets, long text, missing versions and cache switch. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Config lifecycle/evaluator/cache/rollback and component theme tests.
- Injection/malware/contrast/cross-tenant asset/cache and responsive/accessibility tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Design system, SSR/hydration, auth shells, localization and build/bundle.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-117.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- White-label works through shared components with accessible safe fallback.
- No code fork/injection/cache leak; version/audit tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

