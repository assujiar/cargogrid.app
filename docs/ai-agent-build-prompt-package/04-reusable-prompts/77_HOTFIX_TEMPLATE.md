# Template 77 — Hotfix

**Prompt ID:** `CG-S4-REUSE-025`  
**Package document:** `CG-AABPP-REUSE-077`  
**Version:** `0.5.0`  
**Intended use:** Deliver one minimal urgent production correction under explicit emergency authority.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Production Hotfix.

## 4. Objective

Correct {{PRODUCTION_DEFECT_OR_SECURITY_ID}} with the smallest safe change, preserved evidence and verified rollback.

## 5. Business value

Reduce urgent production harm while maintaining tenant, data, financial and operational trust.

## 6. Source requirement

{{INCIDENT_ID}}, {{EMERGENCY_APPROVAL}}, {{AFFECTED_REQUIREMENT_OR_CONTRACT}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Avoid schema/data changes; if unavoidable, use new additive migration, backup/rehearsal/compatibility and separate data recovery authority.

## 14. API impact

Preserve compatibility; any emergency disable/limit has explicit consumer communication and restoration plan.

## 15. UI/UX impact

Implement only necessary correction/degraded messaging; no unrelated design cleanup.

## 16. Security impact

Do not bypass security for speed; apply least privilege, secret handling, negative tests and containment/rotation as needed.

## 17. Performance impact

Validate hot path and production-safe smoke/metrics; avoid unmeasured resource amplification.

## 18. Audit impact

Preserve incident/change/approval/deployment/rollback evidence, exact artifact/commit and privileged actions.

## 19. Data migration impact

No ad hoc production updates. Affected-record repair is idempotent, reconciled and separately authorized.

## 20. Detailed implementation tasks

1. Confirm severity, emergency authority, scope, last-good checkpoint, reproduction and rollback trigger.
2. Create minimal isolated fix with targeted regression/security test and no broad refactor/dependency upgrade.
3. Run fastest sufficient mandatory gates plus affected tenant/data/finance/contract checks; record any deferred non-critical gate.
4. Deploy only under explicit deployment authority, smoke/monitor, decide retain/rollback and schedule full follow-up.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Urgent affected production flow is restored safely with monitoring.

## 22. Alternative flow

Feature disable/degraded mode/traffic containment reduces harm until a standard fix is ready.

## 23. Exception flow

Failed gate/smoke, worsening metrics, tenant/data/finance uncertainty or rollback incompatibility stops and rolls back/escalates.

## 24. Business rules

- Emergency authority narrows time, not integrity requirements or scope.
- Hotfix must be followed by standard regression, documentation and post-incident review; no hidden technical debt.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Artifact/commit/config/migration and environment are exact; production symptom and rollback threshold are measurable.
- Deferred gates have owner/deadline and cannot include critical tenant/security/finance integrity.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Only emergency-approved operators; time-bound credentials and full privileged audit.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Minimal synthetic reproducer plus production-safe read-only/health checks; never extract live sensitive data. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Targeted failing regression, negative security and affected layer integration/smoke tests.
- Post-deploy health/metrics, tenant isolation/data/finance invariant and full follow-up regression.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Affected critical flow, contract consumers, auth/access, jobs/integrations and rollback path.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Production harm is corrected or contained with passing smoke/monitoring and verified rollback.
- Evidence, approval, incident/task/change/docs, deferred gates and standard follow-up are recorded.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
