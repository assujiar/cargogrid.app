# Prompt 121 — Configuration Engine

**Prompt ID:** `CG-S6-PLT-018`  
**Package document:** `CG-AABPP-PLT-121`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-121.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-018` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Governed Tenant Configuration; Capability: Versioned configuration engine; Feature slice: Draft→validate→publish→effective→rollback config lifecycle; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement shared versioned configuration foundation with precedence, dependencies, simulation and audit for later engines/modules.

## 5. Business value

Replace tenant-specific hard coding with governed reversible configuration.

## 6. Source requirement

PLT-CFG-001..004; PKG engine gaps; ARCH configuration workstream; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Configuration engine schema/migrations/service/evaluator/cache/contracts/tests/docs and bounded example. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full workflow/approval/forms modules, arbitrary scripts, mass hard-code migration. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Config definitions/versions/values/scopes/dependencies/effective dates/snapshots, RLS, constraints and indexes.

## 14. API impact

Typed definition/admin/evaluate/simulate/publish/rollback contract.

## 15. UI/UX impact

Reusable schema/view models for admin forms; full builder screen later.

## 16. Security impact

Allowlisted schema/types, no executable code, access-controlled values and secret references only.

## 17. Performance impact

Compile/cache published effective config by tenant/scope/version with bounded invalidation.

## 18. Audit impact

All draft/change/validate/approve/publish/rollback/evaluate-critical events and diffs.

## 19. Data migration impact

Map existing hard-coded/config values incrementally with compatibility snapshots.

## 20. Detailed implementation tasks

1. Define config definition/type/scope/precedence/version/dependency/lifecycle model.
2. Implement draft/validate/simulate/publish/effective/snapshot/rollback service.
3. Implement evaluator/cache/invalidation and dependency/cycle/conflict detection.
4. Add representative platform config, access/audit/tests/docs and adoption guide.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized admin publishes valid config; consumers bind deterministic effective snapshot.

## 22. Alternative flow

Scheduled/effective-dated or inherited override resolves by documented precedence.

## 23. Exception flow

Invalid schema/conflict/cycle/unauthorized/unsafe value or dependency blocks publish.

## 24. Business rules

- Configuration cannot bypass security/finance/canonical semantics.
- No arbitrary executable code or tenant source fork.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Precedence, version, effective date, snapshot and rollback deterministic.
- All consumers declare definition/version and dependency.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme definitions/defaults; Tenant Admin allowed tenant values; user consumers read evaluated subset.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/scopes/versions/effective dates/inheritance/conflicts/cycles/invalid values. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/schema/precedence/simulation/publish/snapshot/rollback/cache tests.
- RLS/RBAC/cycle/unsafe input/cross-tenant/audit/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Entitlements, localization, white-label, master data and future engines.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-121.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Configuration lifecycle/evaluation is deterministic, safe and reversible.
- No hard-coded tenant behavior or security bypass; evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

