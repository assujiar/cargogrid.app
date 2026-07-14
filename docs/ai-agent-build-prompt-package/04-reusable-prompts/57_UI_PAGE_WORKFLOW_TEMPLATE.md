# Template 57 — UI Page and Workflow

**Prompt ID:** `CG-S4-REUSE-005`  
**Package document:** `CG-AABPP-REUSE-057`  
**Version:** `0.5.0`  
**Intended use:** Implement one accessible page and its bounded business workflow.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

UX and Design System.

## 4. Objective

Deliver {{PAGE_WORKFLOW}} for {{PORTAL_AND_ACTOR}} with complete states and server-enforced business/access behavior.

## 5. Business value

Let users complete a real task efficiently and safely without hidden failure or placeholder interaction.

## 6. Source requirement

{{UX_REQUIREMENT_IDS}}, {{FLOW_IDS}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Use approved services/contracts; direct database access from client is forbidden. Schema change requires explicit authorized migration.

## 14. API impact

Use documented REST/GraphQL/server action contract with validation, cancellation, errors and concurrency behavior.

## 15. UI/UX impact

Primary scope: route/navigation, responsive design, forms/tables/actions, complete states, design system, WCAG 2.2 AA and browser matrix.

## 16. Security impact

Server authorization is authoritative; prevent IDOR/XSS/CSRF/open redirect and sensitive-field leakage.

## 17. Performance impact

Server-side filter/sort/search/pagination, bounded payloads, no full dataset, measured loading and interaction budgets.

## 18. Audit impact

Expose appropriate timeline/status and record auditable user actions without displaying protected audit internals.

## 19. Data migration impact

Normally not applicable; if data shape changes, stop and instantiate migration template first.

## 20. Detailed implementation tasks

1. Map actor goal, route, navigation and main/alternate/exception workflow.
2. Implement with existing design-system components and white-label tokens.
3. Cover loading, empty, error, success, denied, offline/degraded, conflict and unsaved-change states.
4. Implement accessible keyboard/focus/labels/errors/live regions and responsive behaviors.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized actor completes the task and sees persisted confirmation/timeline.

## 22. Alternative flow

Alternate configuration, optional step, bulk/saved-view or mobile-supported path works.

## 23. Exception flow

Validation, permission, conflict, network/offline, timeout and partial-result failures remain understandable and recoverable.

## 24. Business rules

- Canonical statuses/rules come from server/configuration; UI must not duplicate business truth.
- No dead button, placeholder action, hidden failure or client-only authorization.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Client and server validation agree; errors identify remediation without leaking sensitive data.
- Destructive actions require confirmation and concurrency protection.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Specify portal, role/scope, field/record visibility, action, export/search/report and denial behavior.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, multiple roles, empty/single/many records, invalid/conflicting data, slow/failing network and responsive viewport cases. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Component, form/state, keyboard/focus/accessibility, responsive and browser tests.
- API integration, access negative, E2E main/alternate/exception and performance tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Navigation, design-system components, adjacent routes, saved filters, localization/branding and critical E2E.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Workflow is usable end to end with every required state and no placeholder.
- WCAG/access/security/performance/regression evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
