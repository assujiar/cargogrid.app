# Prompt 281 — Overtime and Timesheet

**Prompt ID:** `CG-S12-HRT-009`  
**Package document:** `CG-AABPP-HRT-281`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-281.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-009` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Time, Attendance and Scheduling; Epic: Approved Work-Time Inputs; Capability: Overtime Request, Actual Time and Timesheet Approval; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement requested, worked and approved overtime/timesheet evidence using effective schedules, attendance and exact configurable calculations.

## 5. Business value

Prevent unsupported overtime and inconsistent payroll inputs while preserving operational work references and approval history.

## 6. Source requirement

HRS-ATT-001..004 and HRIS Attendance, Shift, Leave & Overtime requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..280; attendance, shift, leave, approval and Operations assignment contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-282..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create overtime policy/version, request, planned interval, actual interval/source, break, eligible duration, rate-classification input, timesheet line/period, project/job/shipment reference, approval and payroll-input version records.

## 14. API impact

Shared REST/GraphQL request, submit, record actual, timesheet enter/import, validate, approve/reject/revise, lock/unlock by authority and payroll-handoff APIs with exact minute/decimal rules. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Employee overtime request/timesheet, attendance comparison, manager approval, HR exception/reconciliation and locked-period views with responsive accessible grids/cards. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Employees write own permitted records; managers approve effective team; job/shipment references are authorized independently; pay rate/value fields are withheld unless payroll permission exists. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/employee/date/status/approver/timesheet period/job reference; server totals and async bulk imports/period validation; no client-only calculation authority. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record requested versus scheduled/attendance/actual, policy/formula/config versions, edits, approval, overrides, lock, payroll handoff and linked Operations source. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import open timesheets/overtime with source totals and explicit approved/paid state; do not infer approval or rewrite attendance history. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define request/actual/eligible/approved time and exact rounding invariants.
- Implement overtime/timesheet schema, calculations, APIs and accessible UX.
- Bind shift, attendance, leave and authorized Operations references.
- Implement period approval/lock and idempotent payroll-input handoff.
- Test overlaps, caps, rounding, concurrency, privacy and reconciliation.

## 21. Main flow

Employee requests overtime or enters a timesheet against an eligible schedule/work reference, actual evidence is reconciled to attendance, authorized manager/HR approves exact eligible time and one versioned payroll input is emitted.

## 22. Alternative flow

Pre-approved overtime, emergency after-the-fact request, manual timesheet, authorized import, multi-job allocation, revision/resubmission or period reopen with reason.

## 23. Exception flow

Block schedule/leave overlap, unsupported work reference, duration/cap violation, attendance mismatch, stale approval, locked period or unauthorized pay detail; retain evidence and remediation. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Requested, actual, eligible, approved and paid time are distinct values with source and version lineage.
- Rounding, minimum, maximum, break and eligibility rules are exact, configurable and SME-verified where statutory.
- Payroll amount/rate calculation belongs to payroll; this capability emits approved time/classification inputs.
- Approved/locked records change only through linked correction/reopen workflow, never silent overwrite.
- AI workload or overtime recommendation remains Step 14.

## 25. Validation rules

Validate employee/schedule/attendance/leave, work reference access, interval order/overlap, caps/breaks, exact units/rounding, policy/config version, approver and period lock before mutation.

## 26. Access rules

Employees maintain own drafts; managers approve effective team; HR handles scoped exceptions; payroll reads approved inputs; Operations references reveal only permitted job/shipment metadata. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Planned/emergency overtime, attendance match/mismatch, overnight/weekend/holiday, overlapping leave, caps, multi-job timesheet, locked/reopened period, retries and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Overtime/timesheet interval/rounding/cap domain tests.
- Schedule/attendance/leave/work-reference and approval tests.
- RLS/RBAC/pay-field/job-link/export negative tests.
- Lock/reopen, idempotent payroll handoff and reconciliation tests.
- Timesheet grid/mobile browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Attendance/shift/leave, Operations job/shipment scope, Platform approvals/jobs and payroll input/finalization contracts. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Overtime policy, timesheet/work-reference, exact calculation, approval/lock, payroll handoff and correction/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause submissions/handoffs, preserve approved and raw evidence, reverse only unconsumed input through governed correction, restore prior policy for new records and reconcile employee/period totals. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Requested, actual and approved time remain distinct and traceable.
- Exact policy, overlap, cap, attendance and approval controls pass.
- One versioned idempotent payroll input is emitted without pay-field leakage.
- Lock/reopen, Operations link, tenant/field and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-282 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

