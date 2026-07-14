# Prompt 126 — Form and Custom Field Builder

**Prompt ID:** `CG-S6-PLT-023`  
**Package document:** `CG-AABPP-PLT-126`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-126.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-023` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Tenant Extensibility; Capability: Form/custom-field configuration; Feature slice: Versioned safe schema, layout and value capture; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed form and custom-field definitions, versioning, validation, access metadata and safe value storage without arbitrary code.

## 5. Business value

Allow tenant-specific data capture in shared code while preserving canonical fields and security.

## 6. Source requirement

PLT-CFG-001..004; UX form builder; field-access/data classification; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Form/custom-field engine schema/migrations/service/renderer/tests/docs and isolated example. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain forms/pages, arbitrary code/SQL, uncontrolled EAV, full builder portal. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Definition/version/layout/field/value storage strategy, tenant keys, typed constraints, indexes and RLS; avoid EAV query explosion.

## 14. API impact

Define/simulate/publish/render-schema/validate/read/write contract with field projection.

## 15. UI/UX impact

Accessible renderer primitives, layout/conditions, states and design-system integration; full builder page later.

## 16. Security impact

Allowlisted field types/validators/conditions; field-level access, XSS/file protection and no executable scripts.

## 17. Performance impact

Bound field count/conditions/query/index strategy; no per-field N+1 or full dynamic scan.

## 18. Audit impact

Definition/version/publish/value change and sensitive custom-field access as required.

## 19. Data migration impact

Definition/value schema changes use version snapshots and explicit transformation; no silent coercion.

## 20. Detailed implementation tasks

1. Define field types, canonical-vs-custom boundary, schemas/layout/conditions/validation/access/classification.
2. Implement versioned draft/preview/validate/publish/rollback definitions.
3. Implement safe renderer/schema/value validation/storage/projection strategy.
4. Add condition/access/XSS/performance/migration/tests/docs and one example form.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized admin publishes form version; authorized user submits valid values stored under snapshot.

## 22. Alternative flow

Conditional/optional/tenant override renders deterministically and preserves prior version data.

## 23. Exception flow

Invalid type/condition/cycle/unsafe content/unauthorized field or incompatible version fails.

## 24. Business rules

- Custom fields extend but do not replace canonical required fields/business semantics.
- No arbitrary JavaScript/SQL or security rule in form configuration.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Schema/types/conditions/dependencies/version snapshot deterministic.
- Values remain interpretable under historical definition.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Definition admin separate from field read/write; field/record policies enforced server-side.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/forms/versions/field types/conditions, sensitive fields, invalid values and long layouts. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Definition lifecycle/schema/conditions/render/submit/version/rollback tests.
- RLS/RBAC/field access/XSS/file/performance/migration/accessibility tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Configuration/status/workflow, design system, APIs and existing forms.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-126.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Custom forms/fields are versioned, accessible, secure and query-safe.
- No canonical/security bypass or arbitrary code; history/tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

