# Template 56 — RBAC Permission

**Prompt ID:** `CG-S4-REUSE-004`  
**Package document:** `CG-AABPP-REUSE-056`  
**Version:** `0.5.0`  
**Intended use:** Add or revise one permission/scope capability across interfaces.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

RLS/RBAC and Tenant Isolation.

## 4. Objective

Implement {{PERMISSION_SLICE}} consistently across server, API, UI, database/storage and audit boundaries.

## 5. Business value

Give authorized users precise capabilities while preventing privilege escalation and field/record leakage.

## 6. Source requirement

{{ACCESS_REQUIREMENT_IDS}}, {{PERMISSION_CATALOG_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Update permission seeds/catalogue through new migration if required; preserve stable identifiers and tenant-aware grants.

## 14. API impact

Enforce the permission in REST/GraphQL/server actions, not only UI; errors must not disclose record existence.

## 15. UI/UX impact

Show/hide/disable actions according to UX policy with explicit denied state and no dead buttons.

## 16. Security impact

Primary scope: least privilege, role inheritance, scope, field/record rules, separation of duties, support and privileged access.

## 17. Performance impact

Permission checks must be bounded/cache-safe with invalidation and no per-row N+1 authorization.

## 18. Audit impact

Log permission assignment/revocation and privileged use with actor, target, tenant, scope, reason and time.

## 19. Data migration impact

Migrate existing roles/grants deterministically; no accidental grant broadening.

## 20. Detailed implementation tasks

1. Define permission action/resource/scope semantics and affected actors.
2. Implement catalogue/seed, enforcement adapters and UI affordance consistently.
3. Add assignment, revocation, cache invalidation and audit behavior.
4. Prove denied paths for direct URL/API/GraphQL/export/search/report/file access.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized role/scope performs the action and receives only permitted fields/records.

## 22. Alternative flow

Custom role or narrower organization/branch/record scope behaves predictably.

## 23. Exception flow

Missing/stale/revoked permission, conflicting duties and forged identifiers fail closed.

## 24. Business rules

- Permissions have stable canonical identifiers; labels may localize without changing semantics.
- No implicit allow through UI visibility, ownership guess or tenant membership alone.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Assignment constraints, inheritance and scope precedence are deterministic.
- Revocation becomes effective within the documented session/cache window.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Document complete role × scope × action × field/record matrix.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Multiple tenants, default/custom roles, nested scopes, owner/non-owner, revoked grants, support and privileged actors. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- RBAC assignment/evaluation/revocation, API/UI/direct-route, field/record and cross-tenant negative tests.
- Audit, separation-of-duty and cache invalidation tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Existing roles, RLS, exports/reports/search, jobs and portal behavior.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Permission is enforced identically at all relevant boundaries.
- No privilege escalation or regression; audit and negative evidence pass.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
