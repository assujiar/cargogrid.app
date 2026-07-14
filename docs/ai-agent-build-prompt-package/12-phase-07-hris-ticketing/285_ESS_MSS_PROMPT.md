# Prompt 285 — Employee and Manager Self-Service

**Prompt ID:** `CG-S12-HRT-013`  
**Package document:** `CG-AABPP-HRT-285`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-285.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-013` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Employee and Manager Self-Service; Epic: Purpose-Bound Workforce Self-Service; Capability: ESS and MSS Workspace; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Provide employee and manager self-service over verified HR capabilities using server-derived own/team scope and field-minimized projections.

## 5. Business value

Reduce HR administration while keeping sensitive workforce, payroll and performance data under the same policy as core services.

## 6. Source requirement

HRS-ESS-001..004 and HRIS ESS, MSS & Offboarding requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..284; effective manager scope and all verified HR service contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-286..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

No duplicate HR truth; add only self-service preference, saved view, request/task projection or acknowledgement records when not already Platform-owned. Every widget/action references canonical employee, time, payroll, performance and training services.

## 14. API impact

Compose shared REST/GraphQL self-service home, own profile/request, schedule/time/leave/overtime, payslip/benefit, performance/training and manager queue endpoints from canonical services with policy-safe projections. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Responsive ESS home and MSS team workspace with role-based tasks, profile change, schedule/attendance/leave/overtime, payslip, performance/training and approvals; no sensitive fields in generic widgets or dead shortcuts. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Own/team scope is derived server-side from effective assignments; manager status alone does not grant payroll, candidate, medical, talent or unrestricted personal data. Widgets, counts, search, cache and notifications resist inference. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Use bounded server composition, cached policy-safe aggregates with correct invalidation, cursor queues and async exports; no client fan-out across full HR datasets. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record self-service request/action, manager decision, sensitive view/download, projection denial, acknowledgement, export and source/config versions; avoid logging restricted payloads. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map existing self-service preferences only; do not copy HR data into portal-specific tables or create stale materialized truth without reconciliation. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define ESS own and MSS effective-team projection/action contracts.
- Implement policy-safe composition APIs and responsive accessible workspaces.
- Wire canonical HR actions, approvals, files and complete states without re-entry.
- Add inference-safe counts/search/cache/notification/export behavior.
- Test manager changes, revocation, field leakage, performance and all action routes.

## 21. Main flow

Employee opens one scoped workspace, sees only current permitted own data/tasks and executes canonical HR requests; manager opens an effective-team queue and performs only permitted approvals/actions against source services.

## 22. Alternative flow

Employee without user link, multiple effective assignments, delegated approver, manager transfer, read-only historical access or feature-disabled module.

## 23. Exception flow

Deny stale manager scope, unauthorized widget/action, sensitive field/count inference, revoked employee/user, unavailable source service or stale request version; show safe error and source resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- ESS/MSS is a projection and action surface, never a second employee, attendance, payroll or performance datastore.
- Every write calls the canonical domain service and shares validation, approval, audit and idempotency.
- Effective team scope is evaluated at request time and sensitive fields require independent permissions.
- Feature/module entitlements hide and deny both UI and API behavior without weakening underlying access.
- Full customer-facing portal remains Step 13; native/offline app remains out of scope.

## 25. Validation rules

Validate active user↔employee link, effective own/team scope, module entitlement, field permission, source record/version, action lifecycle and idempotency for every widget and mutation.

## 26. Access rules

Employees access permitted own records; managers access effective assigned team actions only; HR/admin uses dedicated HR surfaces. Database/service and cached projections enforce identical scope and revocation. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Employee/manager/dual-role, transferred manager, delegated approver, unlinked/revoked user, feature disabled, restricted payroll/performance fields, stale cache and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Projection/source-service contract and no-duplicate-truth tests.
- Own/team/effective-date/revocation/entitlement RLS/RBAC tests.
- Sensitive widget/count/search/cache/notification/export inference tests.
- Canonical-action/idempotency/error/degraded-state tests.
- ESS/MSS responsive browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

All HR source services, Platform navigation/entitlement/session/cache, approvals/files and generic home dashboard behavior. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

ESS/MSS projection/action contract, own/team scope, sensitive widgets, manager transfer/revocation, degraded-source and support runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable affected widget/action through governed feature flag, preserve canonical source data, invalidate projections/cache, revert compatible composition/UI code and reconcile pending requests. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- ESS/MSS introduces no duplicate HR truth.
- Own/effective-team, entitlement, field and inference controls pass for every route/widget/action.
- Canonical request/approval/download behavior and complete UX states pass.
- Manager transfer/revocation, performance and Tenant A/B gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-286 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

