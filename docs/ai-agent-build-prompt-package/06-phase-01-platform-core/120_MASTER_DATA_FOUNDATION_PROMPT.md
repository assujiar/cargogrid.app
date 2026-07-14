# Prompt 120 — Master Data Foundation

**Prompt ID:** `CG-S6-PLT-017`  
**Package document:** `CG-AABPP-PLT-120`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-120.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-017` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Data Platform; Epic: Canonical Reference Data; Capability: Master data registry and lifecycle; Feature slice: Tenant/global masters, codes, version/effective status and dedupe; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical master-data primitives and initial platform masters with tenant isolation, stable IDs, lifecycle and import readiness.

## 5. Business value

Prevent duplicate entry and inconsistent reference data across Commercial, Operations, Finance and portals.

## 6. Source requirement

PLT-MDM-001..004; data dictionaries; canonical data flow; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Master registry/schema/migrations/service/contracts/tests/docs and bounded selector primitives. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full domain masters beyond approved initial set, destructive dedupe, full admin portal. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Master registry/entities, global/tenant scope, stable codes, aliases, version/effective dates, uniqueness/FKs, RLS/indexes.

## 14. API impact

CRUD/search/pagination/resolve/version contract via shared service and REST/GraphQL foundation.

## 15. UI/UX impact

Reusable selector/list/form view models; full admin screens later.

## 16. Security impact

Tenant/global write authority, field/record access, sensitive master classification and no cross-tenant alias resolution.

## 17. Performance impact

Indexed search/lookup, server pagination and cache invalidation; no full datasets.

## 18. Audit impact

Create/update/merge/deactivate/version/import and reference impact events.

## 19. Data migration impact

Map/dedupe existing masters with idempotent aliases and reference-preserving plan.

## 20. Detailed implementation tasks

1. Define master registry/types, ownership/global-vs-tenant policy and canonical IDs/codes.
2. Implement lifecycle/version/effective/alias/merge-safe model and service.
3. Implement search/resolve/pagination/cache and dependency checks.
4. Add initial platform masters, RLS/RBAC/import hooks, tests/audit/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized user creates/resolves active master in correct scope and downstream stores stable reference.

## 22. Alternative flow

Tenant alias/local label maps to canonical/global or tenant master without semantic duplication.

## 23. Exception flow

Duplicate/cross-tenant/inactive/ambiguous reference or unsafe merge fails.

## 24. Business rules

- Canonical entity is stored once; labels/aliases do not duplicate truth.
- Referenced master deactivation/merge preserves lineage and dependencies.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Scope/uniqueness/effective version/reference/alias deterministic.
- No orphan/cross-tenant FK or ambiguous resolution.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme manages global catalogue; Tenant Admin manages permitted own masters; users consume by scope.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Global+two-tenant masters, aliases, duplicates, effective versions, references, deactivate/merge. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/version/alias/search/pagination/cache/merge tests.
- Constraint/RLS/RBAC/cross-tenant/import/audit/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Organization, tenant context, localization, future domain references and exports.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-120.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Master data is canonical, tenant-safe, versioned and performant.
- Dedupe/reference/lifecycle/access evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

