# Prompt 135 — Tenant Admin Portal

**Prompt ID:** `CG-S6-PLT-032`  
**Package document:** `CG-AABPP-PLT-135`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-135.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-032` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Portals; Epic: Tenant Administration Experience; Capability: Tenant Admin portal; Feature slice: One coherent platform administration shell and core workflows; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Tenant Admin portal shell and bounded core workflows for users, roles, hierarchy, entitlements view, configuration, branding and platform operations.

## 5. Business value

Give each customer controlled self-service administration without exposing global or other-tenant controls.

## 6. Source requirement

Platform Admin portal requirements; UX IA; PLT-105..134; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Tenant Admin portal shell/routes/components/tests/docs and exact bounded workflow adapters. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Supreme/Customer/domain portals, direct DB access, all-admin-pages mega task. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

No direct client DB; use approved services/RLS. New portal-specific schema is prohibited unless separately justified.

## 14. API impact

Use REST/GraphQL shared contracts with exact access/field projection and pagination.

## 15. UI/UX impact

Primary scope: tenant admin route shell/navigation/context, dashboards/status and approved core management workflow slices; split oversized pages.

## 16. Security impact

Tenant Admin only own tenant/delegated scope; no Supreme controls, service secrets, hidden impersonation or client authorization.

## 17. Performance impact

Server-render/query bounded, pagination/search/filter, route bundle budgets and no full datasets.

## 18. Audit impact

Show appropriate activity/timeline and audit every admin mutation/export/support request.

## 19. Data migration impact

No data migration; existing admin routes transition compatibility-safe.

## 20. Detailed implementation tasks

1. Map approved Tenant Admin IA/routes/navigation/capability/entitlement/access matrix.
2. Implement shared portal shell/context/guard/error/loading/empty/denied/offline/responsive states.
3. Implement bounded core management flows by child slice using design system/services.
4. Add accessibility/browser/security/cross-tenant/E2E/performance/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Tenant Admin signs in and manages authorized own-tenant platform configuration end to end.

## 22. Alternative flow

Delegated/narrow-scope admin sees only allowed modules/actions and read-only states.

## 23. Exception flow

Suspended/unentitled/forbidden/conflict/network/partial-service states are explicit/recoverable.

## 24. Business rules

- Portal is presentation/orchestration, not authority/source of business rules.
- No dead buttons/placeholders or exposure of other tenant/global controls.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Every route/action maps to entitlement+permission+scope and complete state set.
- Server/API/UI behavior agrees for direct URL and navigation.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Tenant Admin only; Supreme/customer/organizational roles route to appropriate surfaces.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, full/delegated admins, packages, empty/large lists, denied/suspended/conflicts and responsive browsers. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Route/nav/state/form/table/component/accessibility/browser tests.
- REST/GraphQL integration, direct URL, cross-tenant/field/record/export, E2E and performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Auth/context, design system, localization/branding, engines and existing routes.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-135.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Tenant Admin completes approved platform workflows with complete accessible states.
- No global/cross-tenant leak/dead action/performance regression.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

