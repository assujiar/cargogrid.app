# Prompt 279 — Shift, Roster and Scheduling

**Prompt ID:** `CG-S12-HRT-007`  
**Package document:** `CG-AABPP-HRT-279`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-279.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-007` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Time, Attendance and Scheduling; Epic: Auditable Workforce Time; Capability: Shift Template, Roster and Schedule Assignment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned shift definitions and effective roster assignment that attendance, leave, overtime and Operations can reference consistently.

## 5. Business value

Make work expectations, coverage and payroll inputs predictable while preventing overlapping or stale schedules.

## 6. Source requirement

HRS-ATT-001..004 and HRIS Attendance, Shift, Leave & Overtime requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..278; Platform calendar/timezone/config and effective organization/position contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-280..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create shift template/version, work/break segments, timezone, grace/cross-midnight rules, calendar/holiday reference, roster cycle, schedule assignment, coverage requirement, swap request and published snapshot records.

## 14. API impact

Shared REST/GraphQL shift/roster create, validate, publish, assign, bulk schedule, swap/request, calendar read and export APIs with optimistic concurrency and retained published versions. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Shift template editor, roster calendar/table, coverage/conflict preview, bulk assignment and employee/manager schedule views with accessible non-drag alternatives and complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

HR/scheduler writes are scoped; employee reads own schedule and manager reads effective team only; location, work pattern and operational assignment visibility are purpose-limited. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/shift/status/location/employee/date range/roster version; range-safe queries, batch schedule generation in durable jobs and bounded calendar windows. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record template/published version, assignment before/after, coverage conflicts, swaps, overrides, actor, reason and attendance/payroll/Operations consumers. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Stage legacy schedules with explicit timezone/workday mapping and reconcile employee/date coverage; do not guess cross-midnight, break or holiday semantics. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define shift segment, timezone, roster publish and schedule-overlap invariants.
- Implement versioned shift/roster schema, services/APIs and accessible calendar/table UX.
- Implement bulk generation, assignment, swap and conflict/coverage preview.
- Bind attendance, leave, overtime and Operations references to published snapshots.
- Test timezone, overnight, overlap, version, concurrency and scale.

## 21. Main flow

An authorized scheduler defines and publishes a versioned shift/roster, assigns eligible employees for an effective range, resolves overlap/coverage conflicts and exposes immutable-by-normal-role schedule snapshots to attendance and downstream calculations.

## 22. Alternative flow

Rotating roster, flexible shift, split shift, cross-midnight shift, temporary reassignment, employee swap request or future schedule revision.

## 23. Exception flow

Block invalid segments, ambiguous timezone, prohibited overlap, inactive employee/position, capacity/coverage conflict, stale roster version or unauthorized scope; retain last published schedule. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Published schedules retain exact shift/calendar/config versions; later edits create a new effective version.
- Cross-midnight workday and breaks are explicit, not inferred from local date alone.
- Attendance, leave and overtime reference the scheduled snapshot used at calculation time.
- Employee swaps and overrides require eligibility, approval/reason and conflict revalidation.
- Schedule planning is human-governed; optimization/prediction remains Step 14.

## 25. Validation rules

Validate tenant/location/timezone, segment order and duration, break/work totals, employee eligibility, effective dates, overlap/coverage, active config/version and concurrency before publish/assignment.

## 26. Access rules

HR/scheduler roles configure within scope; managers request/approve scoped changes; employees read own and request swaps; Operations consumes only authorized workforce availability projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Fixed/rotating/flexible/split/overnight shifts, holidays, DST/timezone edges, overlap, swap, inactive employee, future revision, bulk generation and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Shift/segment/roster/version and range-constraint tests.
- Overlap/coverage/swap/concurrency and batch-job tests.
- RLS/RBAC/own-team/location/export negative tests.
- Attendance/leave/overtime/Operations snapshot compatibility tests.
- Roster calendar/table browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Attendance status, employee/position assignment, Platform calendars/config/jobs, Operations availability and payroll time-input versioning. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Shift/timezone/workday, roster publish, overlap/coverage, swap/override and schedule recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Stop new roster publication, keep last published version active, cancel pending generation safely, revert compatible code/policy and reconcile employee/date assignments. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Shift and roster definitions are versioned, effective-dated and timezone-explicit.
- Overlap, coverage, swap and concurrency controls are enforced.
- Downstream attendance/leave/overtime retain published schedule snapshots.
- Tenant/own/team, bulk-job, accessibility and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-280 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

