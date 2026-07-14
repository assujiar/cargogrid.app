# Prompt 275 — Organization and Position Linkage

**Prompt ID:** `CG-S12-HRT-003`  
**Package document:** `CG-AABPP-HRT-275`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-275.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-003` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Workforce Master and Lifecycle; Epic: Effective Workforce Structure; Capability: Organization, Position, Grade and Reporting Linkage; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Link employees to Platform-owned company, branch and organization structures through effective-dated position, grade and reporting assignments.

## 5. Business value

Keep authorization, approval routing, manager scope and workforce reporting aligned to one governed organization truth.

## 6. Source requirement

HRS-EMP-001..004 and HRIS Organization, Employee & Position requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274; verified Platform organization/role/scope and employee identity contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-276..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add or extend position, grade and employee-assignment/version tables referencing canonical company/branch/department/team nodes; store manager/reporting line, primary/secondary assignment, capacity, effective range, config version and change lineage without duplicating Platform organization roots.

## 14. API impact

Shared REST/GraphQL position/grade and employee-assignment CRUD, effective transfer/promotion/reorganization, hierarchy read, impact preview and scoped export APIs with cycle/version guards. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Position/grade catalogue, organization-linked position tree, assignment timeline, transfer/promotion/reorg wizard and impact preview; responsive accessible tables/tree alternatives and complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Organization write is Platform-governed; HR may manage HR metadata and assignments only within scope. Manager views derive from effective server-side hierarchy; no client-asserted department or manager scope. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/org node/position/employee/manager/effective range/status; prevent recursive N+1 hierarchy loads, use bounded recursive queries/materialized closure only with measured need. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record position/grade definition, assignment before/after, effective date, manager path, approval/config version, impact preview and downstream authorization changes. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map existing department/position strings to canonical IDs through staged, reviewed crosswalks; preserve unresolved rows and historical labels rather than guessing. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile Platform organization ownership and HR metadata boundary.
- Define effective position/grade/manager assignment and acyclic hierarchy invariants.
- Implement schema, impact-safe services/APIs and accessible linkage UX.
- Bind workflow/approval/team scope to versioned effective assignments.
- Test reorganization, cycles, concurrency, historical queries and authorization effects.

## 21. Main flow

HR creates or reuses a governed position/grade, assigns an employee within canonical organization scope, previews downstream access/approval effects, obtains required approval and activates the assignment on its effective date.

## 22. Alternative flow

Future-date transfer/promotion, secondary assignment, manager replacement, reorganization or correction with preserved prior version.

## 23. Exception flow

Block cross-tenant/org references, reporting cycles, overlapping forbidden assignments, position over-capacity, stale source version or downstream access conflict; keep the current effective assignment intact. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Platform owns the company/branch/department/team tree; HRIS extends it with workforce position/grade/assignment metadata.
- Assignments are effective-dated and historical payroll, time, approval and reporting retain their applied version.
- Manager scope comes from server-evaluated effective relationships and may be narrower than department visibility.
- Reorganization requires impact preview for approval queues, roles, payroll, time and open tickets.
- No hard delete of referenced positions/assignments; RPD-022 residual risk remains disclosed.

## 25. Validation rules

Validate canonical organization IDs, position/grade status, effective ranges, overlap policy, capacity, reporting acyclicity, permission and config/version before activation.

## 26. Access rules

Platform admins govern organization nodes; scoped HR roles manage positions/assignments; managers and employees read only permitted effective/historical projections. List/search/export/report share one policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Multi-company/branch orgs, vacant/filled positions, primary/secondary assignments, transfers, promotions, cycles, overlaps, future-effective changes and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Position/grade/assignment constraints and lifecycle tests.
- Cycle/overlap/capacity/effective-date/concurrency tests.
- RLS/RBAC/manager-scope/cross-company/export negative tests.
- Approval-routing and role/scope impact regression tests.
- Organization tree/table and transfer browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform organization, user role/scope, approval routing, employee master, Operations assignment and reporting filters. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Platform-versus-HRIS ownership ADR, position/grade model, effective assignment, reorganization impact and recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Cancel future-effective change, preserve prior active version and impact evidence, revert compatible code/policies, rebuild derived hierarchy and reconcile authorization caches. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- No duplicate organization tree is introduced.
- Position, grade, manager and employee assignments are effective-dated and acyclic.
- Transfer/reorganization impact on access and approvals is previewed and auditable.
- Historical/downstream version and tenant/manager-scope tests pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-276 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

