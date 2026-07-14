# Template 69 — Data Migration

**Prompt ID:** `CG-S4-REUSE-017`  
**Package document:** `CG-AABPP-REUSE-069`  
**Version:** `0.5.0`  
**Intended use:** Transform, backfill or reconcile existing data without changing product policy.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Data Migration and Integrity.

## 4. Objective

Migrate {{DATASET_AND_TRANSFORMATION}} idempotently with checkpoints, reconciliation, preservation and recovery.

## 5. Business value

Bring existing records to the approved canonical model without tenant mixing, duplicate effects or silent loss.

## 6. Source requirement

{{DATA_REQUIREMENT_IDS}}, {{SCHEMA_MIGRATION_IDS}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Primary scope: read/write sets, tenant partitioning, ordering, batches, locks, constraints, indexes, checkpoint and completion markers.

## 14. API impact

Pause/dual-read/write/compatibility behavior is explicit; no consumer sees mixed invalid state.

## 15. UI/UX impact

Operational status/error/review UX only if authorized; users must not see misleading partial completion.

## 16. Security impact

Least-privilege server execution, tenant-scoped batches, sensitive-data redaction and no real data in logs/source.

## 17. Performance impact

Dry-run counts, batch size, throttling, lock/replication/storage impact and maintenance window are measured.

## 18. Audit impact

Record run ID, code/version, actor, tenant scope, counts, checksums/invariants, errors, retries and approvals.

## 19. Data migration impact

Primary scope: dry run, idempotent transform, checkpoints, resume, rollback/forward repair, reconciliation and staging rehearsal.

## 20. Detailed implementation tasks

1. Profile source data safely; define eligibility, transform, conflicts, invariants and expected counts.
2. Implement dry-run/report and idempotent batch runner with tenant checkpoints and bounded retries.
3. Rehearse against representative copy, validate partial failure/resume and compatibility window.
4. Execute only in explicitly authorized environment; reconcile and preserve evidence/rollback decision.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Every eligible record transforms once and all invariants/counts reconcile.

## 22. Alternative flow

Previously completed batch is skipped safely; recoverable conflict enters reviewed exception path.

## 23. Exception flow

Invalid record, constraint conflict, timeout, partial batch, tenant mismatch and interrupted run stop/resume without corruption.

## 24. Business rules

- Canonical semantics and business history are preserved; no fabricated defaults to force success.
- Never combine tenants or erase source before verified retention/rollback gate.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Pre/post counts, sums, balances, relationships, checksums/samples and orphan/duplicate counts reconcile.
- Rerun produces zero duplicate effective change.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Migration identity has minimum scope; outputs/errors are tenant and sensitivity aware.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Synthetic representative old/new records, two tenants, duplicates/orphans/nulls, high volume, partial completion and sensitive classifications. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Dry-run, transform, idempotency, batching/checkpoint/resume and failure atomicity tests.
- Constraint/RLS/cross-tenant, reconciliation, performance, upgrade and rollback/forward-repair rehearsal.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Live application compatibility, APIs/jobs/reports/finance/exports and backup/restore.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Migration is idempotent, resumable and fully reconciled in rehearsal/authorized execution.
- No tenant mixing, silent loss, duplicate effect or unapproved destructive cleanup.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
