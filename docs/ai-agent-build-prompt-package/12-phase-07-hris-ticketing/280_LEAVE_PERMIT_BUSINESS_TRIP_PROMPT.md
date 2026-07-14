# Prompt 280 — Leave, Permit and Business Trip

**Prompt ID:** `CG-S12-HRT-008`  
**Package document:** `CG-AABPP-HRT-280`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-280.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-008` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Time, Attendance and Scheduling; Epic: Governed Workforce Absence; Capability: Leave Balance, Request, Approval and Calendar; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned leave, permit and business-trip policy, balance and request workflows linked to effective schedules and payroll inputs.

## 5. Business value

Give employees and managers reliable absence planning while protecting entitlement balances, coverage and payroll accuracy.

## 6. Source requirement

HRS-ATT-001..004 and UX screen HRS-LVE-001. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..279; Platform approval/calendar/notification and shift snapshot contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-281..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create leave/permit/trip type and policy versions, eligibility/accrual rule, employee balance ledger, request/version, date/partial-day detail, schedule snapshot, approval, attachment and payroll-impact records. Balances change through ledger events, not silent field mutation.

## 14. API impact

Shared REST/GraphQL balance/read, request/draft/submit/revise/cancel, approve/reject, ledger adjustment, calendar and scoped export APIs with exact units, idempotency and overlap checks. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Employee balance and request form/calendar, manager approval/coverage view, HR policy/ledger and correction views; mobile-friendly and accessible complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Employees see own balances/requests; managers see effective team and only necessary reason/evidence; medical or personal attachments are specially classified; exports and notifications minimize detail. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/employee/type/status/date/approver; range/overlap indexes, precomputed authorized calendar summaries, async accrual/expiration and bulk carry-forward jobs. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record policy/config versions, balance ledger events, request dates/units/reason classification, approval/cancellation, attachment access, manual adjustment and payroll/calendar handoff. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Load opening balances and open requests through signed reconciliation totals and source dates; never invent historical accrual or overwrite the balance ledger. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define leave units, eligibility, accrual/expiry/carry-forward and ledger invariants.
- Implement policy/version, balance ledger, request/approval APIs and accessible ESS/MSS UX.
- Bind schedule/holiday/coverage, partial day, overlap and payroll-impact rules.
- Implement durable accrual/expiry/carry-forward jobs and reconciliation.
- Test exact balances, privacy, concurrency, rollback and scale.

## 21. Main flow

Employee reviews a source-reconciled balance, requests eligible dates/units, system validates schedule/holiday/overlap/coverage, routes approval and posts approved balance/payroll/calendar events idempotently.

## 22. Alternative flow

Permit without balance, business trip, partial day, future cancellation, revision/resubmission, delegated approval, HR adjustment or carry-forward/expiry batch.

## 23. Exception flow

Block insufficient balance, ineligible date/type, overlap, missing classified evidence, coverage threshold, stale balance/request version or unauthorized approval; preserve draft and exact remediation. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Entitlement balance is derived from auditable ledger events with exact units and effective policy versions.
- Approved/cancelled requests post idempotent ledger and payroll/calendar effects; no direct balance edit.
- Manager calendar visibility minimizes sensitive leave reason and attachment data.
- Policy change does not silently recalculate finalized history; explicit governed recalculation is required.
- Statutory leave activation needs current dated HR/legal SME evidence under RPD-016.

## 25. Validation rules

Validate employee eligibility, policy version/effective dates, units/precision, balance, schedule/holiday, overlap, coverage, approval authority, attachment state and optimistic version before mutation.

## 26. Access rules

Employee self-service for own data; managers approve effective team with minimized fields; HR configures and corrects within scope; payroll consumes approved classified impact only. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Accrual/front-loaded balances, carry-forward/expiry, paid/unpaid/permit/trip, partial/overnight, overlap, insufficient balance, cancel/revise, medical file and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Policy/accrual/ledger/exact-balance domain tests.
- Overlap/schedule/holiday/coverage/approval/concurrency tests.
- RLS/RBAC/reason/file/calendar/export privacy tests.
- Job retry/idempotency/reconciliation and payroll-impact tests.
- HRS-LVE-001 mobile browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Shift/attendance, Platform approval/calendar/jobs/files/notifications, employee/manager scope and payroll time-input contract. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Leave policy/version, balance ledger, accrual/expiry, request/approval/cancellation, privacy, migration and recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause affected policy/job, preserve request and ledger history, reverse only through linked compensating events, restore prior config for new requests and reconcile balances/payroll impacts. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Leave/permit/trip balances use exact auditable ledger events.
- Schedule, overlap, coverage, privacy and approval rules are enforced.
- Approved/cancelled payroll/calendar effects are idempotent and reconcilable.
- Opening balances, jobs, Tenant A/B and HRS-LVE-001 gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-281 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

