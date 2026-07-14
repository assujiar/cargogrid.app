# Template 70 — Release Preparation

**Prompt ID:** `CG-S4-REUSE-018`  
**Package document:** `CG-AABPP-REUSE-070`  
**Version:** `0.5.0`  
**Intended use:** Prepare one bounded release candidate evidence package without deploying production.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Release and Go-Live.

## 4. Objective

Prepare {{RELEASE_CANDIDATE}} for go/no-go review with frozen scope, complete evidence and verified rollback readiness.

## 5. Business value

Expose blockers before deployment and prevent unsupported production/market-ready claims.

## 6. Source requirement

{{RELEASE_SCOPE_IDS}}, {{RELEASE_TRAIN_GATE}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Verify migration ordering/checksums, clean rebuild, existing upgrade, seed/types, backup/restore and staging rehearsal; do not alter applied migrations.

## 14. API impact

Inventory contract/version/deprecation/consumer compatibility and freeze public schema/payloads.

## 15. UI/UX impact

Verify release routes, browser/device/accessibility, states, feature flags/entitlements and user-facing notes.

## 16. Security impact

Require tenant/RLS/RBAC, dependency, secret, file, auth/session and penetration evidence with zero critical/high blocker.

## 17. Performance impact

Require approved representative performance budgets and capacity evidence; disclose untested/contract-limited recovery.

## 18. Audit impact

Assemble immutable release evidence references, approvals, exceptions, artifacts and change provenance while respecting RPD-022 disclosure.

## 19. Data migration impact

Validate rehearsal, counts/invariants, cutover/checkpoint/recovery and compatibility; production execution remains separately authorized.

## 20. Detailed implementation tasks

1. Freeze release scope and reconcile requirements, WBS, changes, migrations, contracts, defects and known issues.
2. Run/collect full CI, critical E2E, tenant, finance, migration, security, performance, accessibility, backup/restore and DR evidence.
3. Build release artifact/provenance, deployment/smoke/rollback/hypercare/runbook package.
4. Produce evidence-backed go/no-go report; do not approve on missing or failed mandatory gates.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

All release gates pass and authorized reviewers receive a complete go/no-go package.

## 22. Alternative flow

A bounded non-critical accepted risk has named approver, expiry, monitoring and rollback without violating mandatory blockers.

## 23. Exception flow

Any critical/Sev-1/Sev-2, tenant/security/finance, migration, core E2E or rollback failure blocks release.

## 24. Business rules

- Direct GA includes all major modules; no external pilot is inserted.
- Code complete/feature complete/phase complete/RC/production ready/market ready/GA remain distinct.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Scope, artifact, commit, migrations, environment and evidence checksums/versions reconcile.
- Exceptions cannot override prohibited critical blockers.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Verify release/deploy/secret/approval authority and separation of duties.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Release-like synthetic data across tenants/modules, upgrade and clean rebuild datasets, load profiles and recovery fixtures. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Full CI/regression/smoke/E2E/UAT, 18 tenant and 24 financial scenarios as applicable.
- Migration, security, performance, accessibility/browser, backup/restore and DR rehearsal evidence.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- All release modules, contracts, critical integrations, operations and support/onboarding paths.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Go/no-go package is complete, reproducible and blocker-free under mandatory policy.
- Rollback, monitoring, runbooks, support and hypercare are verified; no deployment performed unless separately authorized.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
