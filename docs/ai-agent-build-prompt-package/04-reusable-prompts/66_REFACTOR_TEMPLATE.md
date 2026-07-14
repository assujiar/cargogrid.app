# Template 66 — Refactor

**Prompt ID:** `CG-S4-REUSE-014`  
**Package document:** `CG-AABPP-REUSE-066`  
**Version:** `0.5.0`  
**Intended use:** Perform one bounded behavior-preserving structural improvement.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Architecture and Maintainability.

## 4. Objective

Refactor {{TARGET_BOUNDARY}} to {{TARGET_STRUCTURE_OR_CONTRACT}} without changing observable business behavior.

## 5. Business value

Reduce verified debt or enforce approved architecture while preserving compatibility and delivery velocity.

## 6. Source requirement

{{DEBT_ID}}, {{ARCHITECTURE_ARTIFACT_OR_ADR}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

No schema/data behavior change unless separately approved; migration changes require migration template.

## 14. API impact

Public/internal contract changes require compatibility adapters and contract tests; default is no observable change.

## 15. UI/UX impact

Visual/workflow behavior remains unchanged unless explicitly scoped and baselined.

## 16. Security impact

Authorization and tenant boundaries must remain equivalent or stronger, never relocated to a weaker layer.

## 17. Performance impact

Capture baseline and ensure structure does not create N+1, bundle growth or slower hot paths.

## 18. Audit impact

Business audit semantics remain unchanged; structural logs may improve without leaking data.

## 19. Data migration impact

Normally not applicable; code movement cannot imply silent data transformation.

## 20. Detailed implementation tasks

1. Define observable behavior and characterization tests before refactor.
2. Map callers/dependencies and split one module boundary; no broad cleanup.
3. Refactor incrementally with compatibility seams and delete old path only after all consumers migrate.
4. Run architecture/dependency, characterization, security and performance comparison.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

All characterized supported behavior remains identical through the target structure.

## 22. Alternative flow

Old/new internal seam coexists temporarily under explicit transition if needed.

## 23. Exception flow

Unexpected dependency or behavior difference stops scope and records an ADR/debt follow-up.

## 24. Business rules

- Refactor is behavior-preserving and cannot smuggle new features or policy changes.
- No broad rename/reformat/dependency upgrade unrelated to the boundary.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Characterization and contract snapshots define equivalence; architecture rule is enforceable.
- Dead path removal has zero remaining consumers.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Authorization evaluation location and outcomes are compared before/after for all relevant actors.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Representative existing fixtures, two tenants, critical roles, boundary inputs/outputs and performance samples. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Characterization, unit/integration/contract and architecture dependency tests.
- RLS/RBAC/audit/performance and affected critical E2E regressions.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- All consumers, public contracts, build artifacts, tree-shaking/bundles and critical domain flows.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Observable behavior and contracts are preserved while target debt/boundary is measurably improved.
- No unrelated change, access weakening or performance regression.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
