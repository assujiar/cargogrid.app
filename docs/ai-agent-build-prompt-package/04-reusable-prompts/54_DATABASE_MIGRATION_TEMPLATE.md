# Template 54 — Database Migration

**Prompt ID:** `CG-S4-REUSE-002`  
**Package document:** `CG-AABPP-REUSE-054`  
**Version:** `0.5.0`  
**Intended use:** Create one safe additive or expand-contract database change, normally 1–3 migrations.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Database Schema and Migration.

## 4. Objective

Implement {{SCHEMA_CHANGE}} without editing applied migrations or losing/corrupting tenant data.

## 5. Business value

Evolve the canonical schema with reproducible clean-build, upgrade and recovery evidence.

## 6. Source requirement

{{SCHEMA_REQUIREMENT_IDS}}, {{ADR_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Primary scope: inspect current schema/applied state; create new forward migration(s), constraints, tenant-aware FKs, indexes, RLS, seed/type updates and recovery plan.

## 14. API impact

Identify contract/generated-type compatibility; do not expose schema internals or break existing clients.

## 15. UI/UX impact

Identify form/table/state impact; UI change requires a separate authorized slice unless explicitly included.

## 16. Security impact

RLS stays enabled; no broad service-role bypass; classify sensitive columns and policy effects.

## 17. Performance impact

Assess locks, rewrite/downtime risk, index build, query plans and backfill batching.

## 18. Audit impact

Record migration identity/checksum, schema version, applied environments and privileged/data effects.

## 19. Data migration impact

Define idempotent backfill, checkpoints, batching, validation, data-preservation proof, rollback or forward-fix.

## 20. Detailed implementation tasks

1. Inspect current schema, migration history, dependencies, data shape and RLS before writing.
2. Create new forward migration(s); never edit an applied migration.
3. Update seeds/generated types if authorized; test clean rebuild and existing-database upgrade.
4. Rehearse backfill/recovery against disposable representative data and document staging rehearsal.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Clean database and existing supported database both reach the target schema with preserved data.

## 22. Alternative flow

Expand-contract compatibility supports old and new application versions during rollout.

## 23. Exception flow

Lock timeout, partial backfill, constraint violation or failed apply stops safely with a documented recovery checkpoint.

## 24. Business rules

- Destructive drop/rename requires explicit approval, backup, dependency analysis and rehearsal.
- Tenant-aware referential/unique constraints and business nullability are not weakened for convenience.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Pre/post row counts, checksums/invariants, constraints, RLS and generated types reconcile.
- Migration ordering and repeatability are proven.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Test tenant isolation and privileged migration path; runtime access remains least privilege.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Disposable old-schema dataset with multiple tenants, duplicates/edge cases, nulls, high-volume batch sample and sensitive classifications. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Migration apply/rebuild/upgrade/data-preservation/rollback-or-forward-fix tests.
- Constraint, FK, uniqueness, RLS, tenant-isolation, index/query and seed/type tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Existing schema contracts, APIs, jobs, reports, exports and supported rollback/restore procedure.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- New migration applies cleanly to fresh and existing database evidence.
- No applied migration edited, no data loss, and recovery/staging evidence is recorded.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
