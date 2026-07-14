# Template 76 — UAT Defect Correction

**Prompt ID:** `CG-S4-REUSE-024`  
**Package document:** `CG-AABPP-REUSE-076`  
**Version:** `0.5.0`  
**Intended use:** Correct one accepted UAT defect against an approved scenario and expected result.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

UAT and Defect Correction.

## 4. Objective

Correct {{UAT_DEFECT_ID}} for {{UAT_SCENARIO_ID}} while preserving approved requirements and adjacent flows.

## 5. Business value

Close user-validated behavior gaps before release without turning feedback into uncontrolled scope.

## 6. Source requirement

{{UAT_EVIDENCE}}, {{EXPECTED_REQUIREMENT_IDS}}, {{RELEASE_GATE_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Identify whether defect caused/needs data correction; migrations/repair are separately authorized and rehearsed.

## 14. API impact

Preserve approved contract or document accepted compatibility change with consumer evidence.

## 15. UI/UX impact

Reproduce exact actor/portal/route/data/state; correct usability, validation and accessible feedback.

## 16. Security impact

Re-run tenant/access/field/record checks for the corrected actor and alternate/unauthorized actors.

## 17. Performance impact

Capture affected screen/flow baseline; UAT correction cannot introduce slow query/render.

## 18. Audit impact

Link UAT evidence, triage decision, fix, retest approver and release status.

## 19. Data migration impact

Affected UAT data may be reset only in authorized disposable environment; production-like repair requires migration template.

## 20. Detailed implementation tasks

1. Validate triage: defect versus enhancement, duplicate, configuration, data/setup or misunderstanding.
2. Reproduce with exact UAT steps/data/environment and add failing automated regression where feasible.
3. Implement minimal root-cause correction and preserve approved alternate/exception behavior.
4. Run automated regression plus UAT retest; record tester acceptance and release-gate impact.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Original UAT actor completes the scenario with expected persisted result.

## 22. Alternative flow

Supported role/configuration/device/browser path remains correct.

## 23. Exception flow

Invalid/denied/offline/conflict/dependency failure is understandable and recoverable.

## 24. Business rules

- Enhancements or requirement changes leave defect scope and require decision/change control.
- Do not hardcode UAT fixtures, tenant, role or expected status.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Expected result traces to approved requirement and retest data/setup is reproducible.
- UAT evidence distinguishes pass, fail, blocked and not-run.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Include original actor plus unauthorized role, other tenant and restricted field/record cases.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Synthetic UAT dataset matching scenario plus alternate, invalid, other-tenant and browser/device cases. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Automated defect regression and layer-specific unit/integration/API/UI tests.
- UAT scenario retest, accessibility, access and affected critical E2E regression.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Adjacent UAT scenarios, module flow, contracts, reports and release critical path.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Automated regression passes and authorized UAT retest is accepted.
- No enhancement creep, access/performance regression or unresolved release blocker.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
