# Template 74 — Resume Interrupted Phase

**Prompt ID:** `CG-S4-REUSE-022`  
**Package document:** `CG-AABPP-REUSE-074`  
**Version:** `0.5.0`  
**Intended use:** Reconstruct and resume a phase interrupted between atomic tasks.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Phase Recovery and Continuation.

## 4. Objective

Resume {{PHASE_ID}} from the last verified atomic checkpoint without replaying completed tasks or skipping gates.

## 5. Business value

Continue a long build safely across agents/sessions with full traceability.

## 6. Source requirement

{{PHASE_PACKAGE_VERSION}}, {{PHASE_CLOSURE_PLAN}}, {{HANDOFF_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Reconcile latest applied migration/schema/seed/types and database trust across all completed/in-progress tasks.

## 14. API impact

Reconcile published/partial contracts and compatibility windows before choosing next task.

## 15. UI/UX impact

Reconcile completed routes/workflows and unfinished feature flags/states without treating partial UX as complete.

## 16. Security impact

Recheck critical tenant/access/security blockers and expired support/emergency authority.

## 17. Performance impact

Identify stale baseline/evidence due to checkpoint/environment drift and re-run only required gates.

## 18. Audit impact

Create a phase-resume record linking all task checkpoints, changes, errors, issues, decisions and evidence.

## 19. Data migration impact

Reconcile every migration/backfill run and checkpoint; unknown partial state blocks phase resume.

## 20. Detailed implementation tasks

1. Read phase package, runtime architecture/WBS/traceability, status/ledgers/build logs/change manifest and last handoff.
2. Inventory task statuses, branches/commits/worktrees/migrations/contracts/tests/docs and dependencies.
3. Validate last trusted checkpoint and recompute next READY atomic task; resolve stale/contradictory records first.
4. Resume exactly one eligible atomic task via its proper template; update phase handoff and closure path.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

All completed tasks remain intact and the next dependency-satisfied atomic task becomes READY.

## 22. Alternative flow

Recover/rollback one failed partial task before selecting the next phase task.

## 23. Exception flow

Conflicting status, missing evidence, orphan migration, broken dependency or untrusted environment blocks the phase.

## 24. Business rules

- Never mark phase complete from task count alone; closure gates and requirement traceability control status.
- Do not batch multiple READY tasks into one oversized prompt.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Task/dependency graph has no unexplained gaps/cycles and records match repository/database state.
- Completed/verified/blocked/failed/partial statuses use the approved vocabulary.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Confirm environment/operator authority for the next task and revoke stale temporary access.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

No new feature data; use checkpoint validation and affected baseline fixtures only. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Checkpoint/build/migration/status reconciliation and last-verified smoke/regression.
- Next-task preflight and stale evidence detection.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Completed phase capabilities, shared platform controls and prior phase closure gates.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- One authoritative phase checkpoint and exact next eligible atomic prompt are established.
- No completed work is replayed, no gate skipped and all contradictions/blockers are recorded.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
