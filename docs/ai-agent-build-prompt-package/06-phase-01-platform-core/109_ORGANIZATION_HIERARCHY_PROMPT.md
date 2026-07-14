# Prompt 109 — Organization and Operational Hierarchy

**Prompt ID:** `CG-S6-PLT-006`  
**Package document:** `CG-AABPP-PLT-109`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-109.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-006` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Organization Management; Epic: Tenant Organization Model; Capability: Company/branch/department/team hierarchy; Feature slice: Versioned organizational tree and scope ancestry; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-scoped organization/company/branch/department/team nodes, relationships and lifecycle for access and operations.

## 5. Business value

Model real logistics organizations so permissions, workflows, reporting and transactions use canonical structure.

## 6. Source requirement

PLT-IAM-001..004; organization data rules; access scope model; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Organization hierarchy schema/migrations/service/API/tests/docs and bounded shared types. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Employee/HR/domain transactions, broad portal, unapproved bulk restructuring. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Add tenant-scoped hierarchy nodes/edges, types, lifecycle, codes, parent constraints, cycle prevention and indexes.

## 14. API impact

CRUD/move/status/tree/query contracts with concurrency and server pagination.

## 15. UI/UX impact

Minimal reusable tree/list/form contracts or split full admin UX to PLT-135.

## 16. Security impact

Tenant isolation, scoped management, cycle/escalation prevention and sensitive metadata access.

## 17. Performance impact

Indexed ancestry/descendant queries, bounded depth and server pagination; avoid recursive N+1.

## 18. Audit impact

Record create/move/rename/status/merge effects and before/after hierarchy.

## 19. Data migration impact

Map existing org/branch data with idempotent canonical IDs; no silent merging.

## 20. Detailed implementation tasks

1. Define node types, allowed parent/child relationships, lifecycle and canonical codes.
2. Implement schema/constraints/cycle-safe hierarchy service and query model.
3. Implement CRUD/move/deactivate with dependency/conflict/concurrency checks.
4. Add scope ancestry helpers, migration/tests/audit/docs and portal dependencies.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized Tenant Admin creates valid hierarchy node and users/records can reference it.

## 22. Alternative flow

Move/restructure preserves history/references and recomputes scope safely.

## 23. Exception flow

Cycle, cross-tenant parent, duplicate code, active dependency or unauthorized change fails.

## 24. Business rules

- Hierarchy labels configurable; canonical node types/semantics stable.
- Referenced nodes are not hard-deleted when retention/dependencies require preservation.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- No cycle/cross-tenant edge/orphan; codes and parent-type rules enforced.
- Scope ancestry deterministic at effective time.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Manage/view operations respect tenant and delegated org/branch scope.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, deep trees, duplicate codes, cycle attempts, move/deactivate and referenced nodes. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Constraint/cycle/CRUD/move/lifecycle/concurrency/query tests.
- RLS/RBAC/cross-tenant/scope ancestry/audit/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Tenant lifecycle, context resolver, master data and reporting assumptions.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-109.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Hierarchy is canonical, cycle-free, tenant-isolated and queryable efficiently.
- Move/lifecycle/access/audit/migration evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

