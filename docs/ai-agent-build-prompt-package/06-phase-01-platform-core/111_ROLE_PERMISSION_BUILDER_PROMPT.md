# Prompt 111 — Role and Permission Builder

**Prompt ID:** `CG-S6-PLT-008`  
**Package document:** `CG-AABPP-PLT-111`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-111.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-008` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Authorization Administration; Capability: Role/permission catalogue and builder; Feature slice: Versioned custom tenant roles with scope-safe assignment; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical permission catalogue and versioned tenant role builder without hard-coded customer roles or security bypass.

## 5. Business value

Let CargoGrid and Tenant Admin configure organizational roles while retaining stable permission semantics.

## 6. Source requirement

PLT-IAM-001..004; four-layer decisions; permission catalogue; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Permission catalogue/role schema/migrations/service/contracts/tests/docs and builder view models. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full portal page, RLS policies outside integration, hard-coded tenant roles. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Add canonical permissions, tenant roles/versions, role-permission bindings, assignments, constraints and effective dates.

## 14. API impact

Admin CRUD/draft/publish/clone/assign contract with dependency/impact validation.

## 15. UI/UX impact

Builder view model/states for later portal; no full page unless explicitly split.

## 16. Security impact

Protected permissions, least privilege, separation of duties, no self-escalation and delegated admin limits.

## 17. Performance impact

Bound catalogue/search/assignment queries; cache published roles with invalidation.

## 18. Audit impact

Record role draft/publish/change/assignment/revocation and permission diffs.

## 19. Data migration impact

Seed stable permission IDs and map existing roles deterministically; no broad default grant.

## 20. Detailed implementation tasks

1. Define stable permission action/resource IDs, categories, protected flags and scope compatibility.
2. Implement versioned role draft/validate/publish/clone/archive and binding model.
3. Implement assignment eligibility, impact/dependency checks and cache invalidation.
4. Add builder contract/tests/audit/docs and downstream RBAC integration.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized admin creates/publishes role and assigns it within allowed tenant/scope.

## 22. Alternative flow

Clone/version change takes effect at approved date without mutating historical snapshot.

## 23. Exception flow

Protected permission, self-escalation, separation conflict, invalid scope or orphaning last admin fails.

## 24. Business rules

- Tenant may configure title/composition; permission semantics remain canonical.
- Role assignment alone does not bypass entitlement/RLS/field/record rules.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Only published valid versions evaluate; stable IDs and effective dates enforced.
- Protected permissions/assignment constraints are server-side.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme controls catalogue/protected permissions; Tenant Admin manages allowed tenant roles only.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Default/custom/protected roles, scopes, versions, concurrent edits, last admin and cross-tenant attempts. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Role lifecycle/version/publish/assignment/constraint/cache tests.
- Self-escalation/protected/cross-tenant/separation/audit API tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- User lifecycle, four-layer context, organization hierarchy and future RBAC.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-111.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Custom roles are versioned/configurable without permission-semantic drift.
- No escalation or broad default; audit/migration/tests/docs pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

