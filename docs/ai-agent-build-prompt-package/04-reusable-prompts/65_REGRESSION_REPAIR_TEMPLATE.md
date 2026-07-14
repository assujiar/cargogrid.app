# Template 65 — Regression Repair

**Prompt ID:** `CG-S4-REUSE-013`  
**Package document:** `CG-AABPP-REUSE-065`  
**Version:** `0.5.0`  
**Intended use:** Restore behavior that previously passed and was broken by an identified change.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Quality and Regression.

## 4. Objective

Repair {{REGRESSION_ID}} while preserving the intentional behavior of the causal change.

## 5. Business value

Recover trusted functionality without reverting valid product/security/data improvements.

## 6. Source requirement

{{REGRESSION_EVIDENCE}}, {{LAST_GOOD_CHECKPOINT}}, {{CAUSAL_CHANGE_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Compare schema/migration/data between last good and current; never edit applied migrations.

## 14. API impact

Diff contract/behavior and restore compatibility or implement approved migration path.

## 15. UI/UX impact

Compare prior/current states and restore intended UX without resurrecting obsolete behavior.

## 16. Security impact

Do not restore behavior by weakening newer RLS/RBAC/security controls.

## 17. Performance impact

Compare last-good/current/post-repair performance and avoid masking timeout/race defects.

## 18. Audit impact

Link regression, causal change, repair and verification evidence.

## 19. Data migration impact

Identify data written under broken behavior; repair uses a separate idempotent, reconciled plan.

## 20. Detailed implementation tasks

1. Prove last-good and first-bad checkpoint/change with reproducible tests or evidence.
2. Identify the exact causal interaction and intended combined behavior.
3. Add/strengthen regression test, implement minimal compatibility-safe repair and retain valid causal change.
4. Re-run original change tests, affected critical flow and broader risk-based regression.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Previously passing intended flow works together with the causal change.

## 22. Alternative flow

Supported old/new configuration or contract window remains compatible.

## 23. Exception flow

Boundary/race/error case that caused regression is deterministic and recoverable.

## 24. Business rules

- Do not blindly revert security/data/finance migrations or intentional requirements.
- Separate pre-existing failure from introduced regression with checkpoint evidence.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Last-good/first-bad/current comparison supports causality.
- Repair passes both old intended and new intentional behavior tests.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Confirm no permission/tenant behavior was accidentally restored or broadened.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Fixtures reproducing last-good behavior, causal-change behavior, combined edge, two tenants and concurrent cases if relevant. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Regression reproducer, causal-change preservation and combined interaction tests.
- Layered integration/E2E plus security/data/finance tests proportional to risk.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Original causal task suite, affected module/consumers/contracts and release critical flows.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Regression is repaired without undoing intended causal behavior.
- Causality, compatibility and broader regression evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
