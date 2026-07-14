# Prompt 133 — Feature Flags

**Prompt ID:** `CG-S6-PLT-030`  
**Package document:** `CG-AABPP-PLT-133`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-133.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-030` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Configuration; Epic: Safe Capability Exposure; Capability: Platform feature flags; Feature slice: Tenant/module/feature/cohort/effective flag lifecycle; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend the Phase 0 flag foundation into tenant-safe Platform Core administration/evaluation integrated with entitlements and audit.

## 5. Business value

Control internal rollout/rollback without tenant forks or security/entitlement bypass.

## 6. Source requirement

PKG-PLT-FLG-001; PH0-098; entitlement/config engines; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Feature-flag schema/migrations/service/evaluator/admin slice/tests/docs. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain feature behavior, authorization weakening, tenant code forks. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Versioned flag definitions/targets/effective dates/overrides/kill state with tenant RLS/constraints/indexes if not already present.

## 14. API impact

Privileged lifecycle/evaluate/debug contract; server evaluation authoritative.

## 15. UI/UX impact

Admin view models or bounded portal slice for status/target/reason/history; no domain flag screens.

## 16. Security impact

Flags cannot grant permission/module entitlement, disable validation/RLS or hide critical defects.

## 17. Performance impact

Compiled/cache evaluation by environment/tenant/module/cohort/version with prompt invalidation.

## 18. Audit impact

Definition/target/change/effective/kill/rollback/debug privileged access.

## 19. Data migration impact

Map existing flags/values deterministically; unknown flags use safe default.

## 20. Detailed implementation tasks

1. Reconcile PH0 foundation with Platform Core target dimensions and ownership.
2. Implement governed definition/target/effective lifecycle and server evaluator/cache.
3. Integrate entitlement/access-safe evaluation and minimal admin/debug/audit path.
4. Add kill/rollback/cache/cross-tenant/security/performance/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized context receives deterministic flag state after entitlement/access checks.

## 22. Alternative flow

Scheduled/cohort/tenant override applies by precedence with audit.

## 23. Exception flow

Unknown/conflicting/expired/stale/unauthorized configuration falls to safe default.

## 24. Business rules

- Flag controls exposure only, never access/data/finance integrity.
- Internal progressive exposure does not replace direct-GA all-module gates.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Precedence/target/effective/cache/rollback deterministic and explainable.
- Server/client evaluation cannot diverge into unauthorized behavior.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme controls global; permitted Tenant Admin tenant flags only; user read is evaluated subset.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/environments/modules/cohorts/dates, conflicts, stale cache, kill and unknown flags. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/target/precedence/effective/cache/kill/rollback/debug tests.
- Entitlement/RBAC/RLS/cross-tenant/security bypass/performance/audit tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- PH0 flags, entitlements, config engine, SSR/client and CI.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-133.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Flags are governed, tenant-safe and reversible with no access bypass.
- Precedence/cache/kill/audit/docs evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

