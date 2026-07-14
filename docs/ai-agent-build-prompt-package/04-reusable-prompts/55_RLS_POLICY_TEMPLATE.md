# Template 55 — RLS Policy

**Prompt ID:** `CG-S4-REUSE-003`  
**Package document:** `CG-AABPP-REUSE-055`  
**Version:** `0.5.0`  
**Intended use:** Add or correct tenant-aware Row Level Security for a bounded table set.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

RLS/RBAC and Tenant Isolation.

## 4. Objective

Implement {{RLS_POLICY_SLICE}} with deny-by-default tenant/record isolation and measurable policy performance.

## 5. Business value

Prevent cross-tenant disclosure or mutation across database, API, jobs, realtime, reports and files.

## 6. Source requirement

{{SECURITY_REQUIREMENT_IDS}}, {{TABLE_IDS}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Enable/retain RLS and create explicit SELECT/INSERT/UPDATE/DELETE policies using verified tenant/member/scope primitives.

## 14. API impact

Confirm REST/GraphQL/server actions cannot bypass policies and map database denial safely.

## 15. UI/UX impact

Denied/forbidden states are explicit; do not use UI hiding as authorization.

## 16. Security impact

Primary scope: auth context, tenant binding, role/scope/record rules, service identities, support grants and negative abuse cases.

## 17. Performance impact

Use tenant-leading indexes and measure representative authorized/denied policy query plans.

## 18. Audit impact

Audit privileged/support access and sensitive mutations without leaking protected values.

## 19. Data migration impact

If existing rows lack tenant keys, split backfill from enforcement with safe checkpoints; never set permissive defaults.

## 20. Detailed implementation tasks

1. Map table operations to actors, tenant source, ownership/scope and policy expressions.
2. Implement policies and helper functions without recursion or broad bypass.
3. Test direct database, REST, GraphQL, job/realtime/report/export access including cross-tenant denial.
4. Document exception paths for migrations, workers and time-bound support access.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized subject accesses only allowed tenant/record rows for the permitted operation.

## 22. Alternative flow

Scoped organization/branch/team/owner or support-grant access works within explicit limits.

## 23. Exception flow

Missing/forged/expired context, cross-tenant ID, unauthorized operation and policy recursion fail closed.

## 24. Business rules

- RLS is mandatory for every tenant-scoped table and cannot rely solely on application filters.
- Supreme Admin exception is disclosed; no tamper-proof claim.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- WITH CHECK and USING semantics cover writes and reads; helper functions are stable and least privilege.
- No anonymous/authenticated/public grant creates unintended reachability.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Matrix every role/scope/operation and include two-tenant negative evidence.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two or more tenants, organizations/branches, owners/non-owners, support grant states, missing/forged claims and sensitive records. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Policy unit/database tests for SELECT/INSERT/UPDATE/DELETE and cross-tenant IDOR attempts.
- REST/GraphQL/job/report/realtime parity, support expiry and policy performance tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Existing authorized access, service jobs, exports/reports and migration operations remain functional.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- All authorized matrix cells pass and all forbidden cells fail closed.
- RLS/performance/audit evidence is recorded with no bypass introduced.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
