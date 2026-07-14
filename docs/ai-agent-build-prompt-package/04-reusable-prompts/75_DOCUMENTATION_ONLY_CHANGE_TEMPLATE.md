# Template 75 — Documentation-Only Change

**Prompt ID:** `CG-S4-REUSE-023`  
**Package document:** `CG-AABPP-REUSE-075`  
**Version:** `0.5.0`  
**Intended use:** Create or correct documentation without changing runtime behavior.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Documentation and Traceability.

## 4. Objective

Update {{DOCUMENTATION_SCOPE}} to match verified repository/product evidence without changing code, contracts, configuration or data.

## 5. Business value

Keep agents, users and operators aligned with the actual system and trusted checkpoints.

## 6. Source requirement

{{SOURCE_EVIDENCE_IDS}}, {{DOC_ISSUE_OR_WBS_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

No database/migration/data write. Schema claims must cite registry/migrations/verified evidence.

## 14. API impact

No contract change. API documentation must be validated against actual OpenAPI/GraphQL/source evidence.

## 15. UI/UX impact

No UI change. Screens/routes/flows described must exist or be clearly marked planned/not implemented.

## 16. Security impact

Redact secrets/PII and do not expose internal sensitive topology, exploit detail or private endpoints beyond audience need.

## 17. Performance impact

No performance change; claims/budgets/results require dated evidence and environment.

## 18. Audit impact

Record documentation author/source/checkpoint/change/reviewer and superseded content.

## 19. Data migration impact

Not applicable; migration/runbook docs may be changed only from verified evidence.

## 20. Detailed implementation tasks

1. Identify audience, incorrect/missing statement, authoritative evidence and checkpoint.
2. Update only allowed documentation; distinguish current, planned, deprecated, risk and unknown.
3. Validate links, IDs, commands, examples, tables, terminology, version and cross-document consistency.
4. Update change/traceability/task/build records and request appropriate review.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Reader can perform/understand the documented task accurately from current evidence.

## 22. Alternative flow

Audience-specific user/admin/API/support view is linked without duplicating contradictory truth.

## 23. Exception flow

Missing/contradictory evidence becomes a blocker or explicit unknown, not invented documentation.

## 24. Business rules

- Documentation cannot silently change product decisions, API/schema contracts or implementation status.
- Never claim runtime verified, production ready, market ready or guaranteed recovery without gates.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Commands/examples/links/IDs/versions and referenced paths are checked.
- No code/config/data/generated artifact changes appear in worktree.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Classify intended audience and remove/redact information outside that audience.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Use synthetic/redacted examples only; never copy real tenant/customer/employee/financial/credential data. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Markdown/link/schema/example validation and cross-document terminology/version checks.
- Worktree forbidden-change audit and readback review by target audience/owner.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Persistent context, status, traceability, API/schema/data-flow/module docs and user/admin/support consistency.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Documentation is accurate, complete for audience and traceable to evidence.
- Only documentation/authorized ledgers changed; no runtime behavior or sensitive disclosure.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
