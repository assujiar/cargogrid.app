# Prompt 124 — Status Engine

**Prompt ID:** `CG-S6-PLT-021`  
**Package document:** `CG-AABPP-PLT-124`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-124.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-021` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Canonical Lifecycle Semantics; Capability: Status registry and transition presentation; Feature slice: Canonical status, tenant labels, lifecycle and history; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical status registry and versioned tenant presentation layered with workflow transitions.

## 5. Business value

Keep lifecycle meaning stable across modules while allowing tenant-specific terminology and reporting.

## 6. Source requirement

PLT-CFG-001..004; 24 status transitions; localization/white-label; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Status registry/schema/migrations/resolver/UI metadata/tests/docs and bounded legacy map. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain transition logic, client authorization, destructive status rewrite. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Canonical status/sets/labels/mappings/effective versions/history with tenant scope/RLS; workflow remains transition authority.

## 14. API impact

Status metadata/resolve/history contract using stable machine IDs.

## 15. UI/UX impact

Status labels/colors/badges/actions/view models with accessible non-color cues.

## 16. Security impact

Status label/config cannot grant transitions/access or hide prohibited states.

## 17. Performance impact

Cache status metadata by set/tenant/version; bounded history/pagination.

## 18. Audit impact

Status definition/label/map change and record status transition references.

## 19. Data migration impact

Map legacy status values to canonical IDs with idempotent compatibility plan.

## 20. Detailed implementation tasks

1. Define canonical status sets/IDs/categories/terminal semantics and ownership.
2. Implement tenant label/presentation versioning, fallback and effective dates.
3. Integrate workflow status resolution/history contract and shared UI metadata.
4. Add legacy mapping, semantic drift/accessibility/cache/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Record stores canonical status and displays approved tenant label/presentation.

## 22. Alternative flow

Tenant terminology override changes label only and falls back safely.

## 23. Exception flow

Unknown/deprecated/ambiguous mapping or invalid attempted transition blocks.

## 24. Business rules

- Canonical status meaning never changes with label/color.
- Workflow/authorization controls transitions; status engine describes/resolves.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Stable IDs/set membership/terminal semantics and effective mapping deterministic.
- Legacy mapping has no silent collision.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Status visibility/action metadata respects field/record access.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/labels/locales/versions, deprecated/legacy/unknown statuses and transitions. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Registry/mapping/version/fallback/cache/history tests.
- Semantic drift/invalid mapping/accessibility/RBAC/legacy migration negatives.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Workflow, localization, white-label, APIs, reports and existing status values.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-124.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Canonical statuses remain stable and presentation configurable/accessibly.
- No semantic/access drift; legacy mapping and tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

