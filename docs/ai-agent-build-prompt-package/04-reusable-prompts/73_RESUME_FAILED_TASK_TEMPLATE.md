# Template 73 — Resume Failed Task

**Prompt ID:** `CG-S4-REUSE-021`  
**Package document:** `CG-AABPP-REUSE-073`  
**Version:** `0.5.0`  
**Intended use:** Resume one FAILED, BLOCKED or PARTIALLY_COMPLETE atomic task from its checkpoint.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Recovery and Task Continuation.

## 4. Objective

Resume {{FAILED_TASK_ID}} from {{LAST_KNOWN_GOOD_CHECKPOINT}} and complete only the unresolved authorized scope.

## 5. Business value

Recover progress without repeating completed work or introducing conflicting changes.

## 6. Source requirement

{{ORIGINAL_PROMPT_ID}}, {{ERROR_LEDGER_IDS}}, {{TASK_LEDGER_ENTRY}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Record applied/pending/failed migration and data state exactly; do not rerun uncertain writes without idempotency/reconciliation.

## 14. API impact

Preserve completed verified contracts; repair only failing/incomplete portions within scope.

## 15. UI/UX impact

Preserve completed verified states; do not redo or redesign unrelated work.

## 16. Security impact

Reconfirm tenant/data/finance trust before resume; any lost trust blocks and escalates.

## 17. Performance impact

Reuse comparable baseline; re-run only stale/affected measures and final mandatory gates.

## 18. Audit impact

Link original attempt, checkpoint, failures, recovery actions, new evidence and final state.

## 19. Data migration impact

Resume only from explicit checkpoint with idempotent step markers and reconciliation; otherwise stop.

## 20. Detailed implementation tasks

1. Read original prompt, task/build/change/error/issues/handoff and inspect worktree ownership.
2. Reconcile what is completed/verified, changed/uncommitted, failed, pending and stale.
3. Confirm root cause/recovery plan and narrow allowed files; do not repeat passed destructive steps.
4. Execute repair/remaining tasks, re-run affected plus mandatory final gates and close documentation.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Resume from trusted checkpoint, preserve completed work and finish remaining acceptance criteria.

## 22. Alternative flow

Choose documented rollback or bounded replacement task when direct repair is unsafe.

## 23. Exception flow

Checkpoint mismatch, unknown migration/data state, overlapping user changes or lost repository/database trust blocks resume.

## 24. Business rules

- Do not restart phase/task from scratch unless total rollback is approved and documented.
- Original scope and protected decisions remain binding; recovery cannot expand them.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Branch/HEAD/worktree/migrations/tests/files reconcile with handoff and ledgers.
- Every prior passed/still-failing gate is explicitly classified.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Reconfirm current credentials/roles/environment authority; never reuse expired emergency access implicitly.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Reuse original fixtures where trustworthy; add only root-cause/failure/resume cases and keep tenant isolation. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Re-run failed tests and recovery-specific idempotency/checkpoint tests.
- Run regression for files/contracts/migrations already changed and mandatory completion gates.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Previously completed portions, upstream/downstream contracts and original acceptance suite.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Original task reaches VERIFIED or an exact bounded blocker with no repeated harmful action.
- Checkpoint, evidence, errors, migrations, documentation and next task reconcile.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
