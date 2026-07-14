# Template 64 — Bug Fix

**Prompt ID:** `CG-S4-REUSE-012`  
**Package document:** `CG-AABPP-REUSE-064`  
**Version:** `0.5.0`  
**Intended use:** Correct one reproducible defect and its root cause without broad refactoring.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

{{AFFECTED_WORKSTREAM}}.

## 4. Objective

Fix {{BUG_ID_AND_SYMPTOM}} at the confirmed root cause and prevent recurrence.

## 5. Business value

Restore intended behavior while minimizing regression and preserving existing contracts/data.

## 6. Source requirement

{{BUG_EVIDENCE}}, {{EXPECTED_REQUIREMENT_IDS}}, {{WBS_OR_ISSUE_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Inspect data/schema effect; migration/data repair is separate unless explicitly authorized and rehearsed.

## 14. API impact

Preserve public contract unless the contract itself is the approved defect; compatibility plan is mandatory.

## 15. UI/UX impact

Correct affected states/messages/actions with no hidden failure or placeholder workaround.

## 16. Security impact

Classify whether defect affects tenant/access/secrets/injection/files; security impact elevates to remediation template if needed.

## 17. Performance impact

Capture reproduction performance baseline and ensure fix does not introduce slow queries/rendering.

## 18. Audit impact

Preserve evidence and ensure corrected action/failure is auditable where required.

## 19. Data migration impact

Do not repair production data ad hoc; define affected-record detection and separate idempotent repair if needed.

## 20. Detailed implementation tasks

1. Reproduce the defect at the trusted checkpoint and add a failing regression test.
2. Confirm root cause and affected surface; distinguish symptom, data damage and adjacent issues.
3. Implement the smallest root-cause fix within allowed paths.
4. Run targeted and adjacent regression, compare baseline, and document residual affected data.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Original valid scenario now produces the required result.

## 22. Alternative flow

Nearby supported configuration/actor/input remains correct.

## 23. Exception flow

Original failure edge and invalid/unauthorized paths fail safely with useful evidence.

## 24. Business rules

- Expected behavior comes from cited requirement/contract, not guesswork.
- Do not broaden scope to unrelated cleanup or silence the symptom.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Regression test fails before and passes after the fix at the same checkpoint.
- Root cause and affected versions/data are documented.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Re-test affected role/scope/tenant/field/record behavior even when bug was not reported as security.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Minimal reproducer plus boundary, alternate role/configuration, second tenant and affected/unaffected record samples. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- One regression test that proves the defect plus unit/integration/API/UI layer tests at root cause.
- Negative security/data tests proportional to impact.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Adjacent behavior, public contracts, migrations, performance and critical flow containing the defect.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Defect is reproducible before, absent after, and root cause is documented.
- No unrelated changes or new regression; affected-data handling is explicit.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
