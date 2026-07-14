# Template 72 — Rollback

**Prompt ID:** `CG-S4-REUSE-020`  
**Package document:** `CG-AABPP-REUSE-072`  
**Version:** `0.5.0`  
**Intended use:** Return one failed change/release/task to the last trusted checkpoint.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Rollback and Recovery.

## 4. Objective

Rollback {{CHANGE_OR_RELEASE_ID}} to {{LAST_KNOWN_GOOD_CHECKPOINT}} without compounding data, tenant or financial damage.

## 5. Business value

Restore trusted behavior quickly while preserving evidence and a clean path to resume.

## 6. Source requirement

{{ROLLBACK_TRIGGER_EVIDENCE}}, {{CHANGE_MANIFEST_ID}}, {{AUTHORITY_RECORD}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase/incident build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS_OR_AUTHORITY}}`, approved ADRs/migrations/contracts, verified runtime gates or recorded recovery/emergency authority, and baseline evidence.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; one bounded objective and module/operational boundary. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, unapproved lockfile/dependency changes, secrets, tenant data and broad refactors.

## 13. Database impact

Determine whether code rollback is schema-compatible; never blindly reverse applied/destructive/data migrations. Use forward-fix/restore only with approved plan.

## 14. API impact

Restore compatible contracts or keep adapters; avoid breaking clients during rollback.

## 15. UI/UX impact

Restore known-good behavior and communicate degraded/unavailable states accurately.

## 16. Security impact

Do not roll back a security control into known vulnerability; require compensating containment.

## 17. Performance impact

Verify rollback does not reintroduce overload/bottleneck that triggered the change.

## 18. Audit impact

Record trigger, authority, commands, artifacts, checkpoints, data decisions, results and communications.

## 19. Data migration impact

Reconcile writes since change, backups, forward-only migrations and irreversible effects; no guessed reversal.

## 20. Detailed implementation tasks

1. Stop further change and capture exact current/last-good state, evidence and affected writes.
2. Assess rollback compatibility across code/schema/data/contracts/flags/jobs/integrations and security.
3. Execute the smallest authorized rollback/forward-recovery sequence with checkpoints.
4. Run health, smoke, integrity, reconciliation and regression; update ledgers/handoff and block unsafe resume.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

System returns to last trusted compatible state and mandatory health/integrity checks pass.

## 22. Alternative flow

Code rollback plus compatibility adapter/feature disable/forward schema fix restores service safely.

## 23. Exception flow

Irreversible migration, untrusted backup, mixed-version writes or security exposure blocks automatic rollback and escalates.

## 24. Business rules

- Rollback is not destructive cleanup and cannot erase evidence.
- Database/data trust and tenant/financial integrity determine recovery path.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Artifact/commit/schema/flags/config/environment match the intended checkpoint.
- Data written during failed window is reconciled and no hidden partial state remains.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Only authorized operators execute rollback; emergency access is time-bound/audited.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Use production-safe health/invariant checks and isolated representative rollback rehearsal where possible. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Deployment health/smoke, migration compatibility, data/finance invariants and affected critical flow.
- Security/tenant isolation, jobs/integrations, monitoring and rollback-trigger clearance.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Unaffected modules and contracts plus the failure path that triggered rollback.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Trusted checkpoint is restored or explicit blocked recovery state is recorded.
- Integrity, compatibility, security, monitoring, evidence and resume instructions pass.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
