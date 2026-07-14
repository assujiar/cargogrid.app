# Prompt 278 — Attendance

**Prompt ID:** `CG-S12-HRT-006`  
**Package document:** `CG-AABPP-HRT-278`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-278.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-006` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Time, Attendance and Scheduling; Epic: Auditable Workforce Time; Capability: Clock-In, Clock-Out, Attendance Exception and Correction; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement online-first attendance capture and governed correction against effective employee, shift and location/time policy.

## 5. Business value

Create reliable auditable work-time evidence for operations and payroll while exposing exceptions before they become payroll errors.

## 6. Source requirement

HRS-ATT-001..004, HRS-ATT-US-001 and UX screen HRS-ATT-001. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..277; effective employee/position and Platform location/config primitives. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-279..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create attendance event/session, device/channel, timezone, policy/version, shift reference, timestamp, approved location/geofence result, exception, correction request/version and payroll-input status records. Preserve raw source separately from derived approved time.

## 14. API impact

Shared REST/GraphQL clock-in/out, status, exception/correction, approve/reject, import/device-adapter and scoped list/report APIs with server timestamps, idempotency and replay protection. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Mobile-first responsive attendance action/status, calendar/table, exception banner, correction request and HR review queue; no offline-sync promise, fake location success or hidden failure. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Employees act only for self unless explicit HR authority; location/device data is minimized and purpose-bound; server validates employee, policy and timestamps; prevent spoofed IDs and cross-team views. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Fast indexed current-status query by tenant/employee/date; partition or lifecycle high-volume events only after measured need; async device imports and exception recalculation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record source and received/server times, policy/shift versions, geolocation decision (minimized), exception, correction before/after, approval and payroll handoff. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import legacy attendance as classified source events with reconciliation totals; do not invent device/location proof or silently mark exceptions approved. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define raw-event, session, workday/timezone, exception and correction invariants.
- Implement secure idempotent clock-in/out and attendance status services/APIs.
- Implement accessible mobile action, calendar/list and correction/review UX.
- Bind shift/location policy and approved-time payroll handoff.
- Test spoofing, duplicate/out-of-order events, DST/timezone, concurrency and scale.

## 21. Main flow

An active employee clocks in online; the server resolves current effective shift/time/location policy, records source and server evidence, flags any exception, accepts clock-out and produces approved time only after required review.

## 22. Alternative flow

Kiosk/device/import event, authorized manual attendance, remote-work policy, missed clock correction, overnight shift or manager/HR approval.

## 23. Exception flow

Reject inactive employee, no eligible shift/policy, forged employee/location, duplicate/replayed event, impossible ordering, stale correction or cross-scope action; retain safe diagnostic evidence. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Server time and authorized source evidence are authoritative; client time/location alone never proves attendance.
- Attendance raw events are preserved; corrections create linked versions and never overwrite source evidence silently.
- Workday, timezone, grace, geofence and exception rules are versioned per effective scope.
- Approved attendance may feed payroll once with source/config/version lineage; finalized payroll is not silently recalculated.
- RPD-004 is responsive online-first; offline synchronization remains out of scope.

## 25. Validation rules

Validate active employee, effective shift/policy, permitted channel/device, timestamp/order, location policy, idempotency key, correction reason/evidence, approval and payroll-input version.

## 26. Access rules

Employee self-action/read; manager effective-team review where configured; HR scoped correction/approval; payroll receives approved projection only. Database/service policy applies to raw location and exports. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Normal/late/early/missed/duplicate/out-of-order clocks, overnight/timezone boundary, remote/geofence denied, correction/retry, inactive employee, device import and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Attendance event/session/order/idempotency domain tests.
- Policy/timezone/workday/geofence/exception calculation tests.
- RLS/RBAC/self-team/raw-location/export negative tests.
- Correction approval and payroll-handoff reconciliation tests.
- HRS-ATT-US-001 mobile browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Employee status, shift links, Platform location/config, notification/jobs, payroll input contract and operational worker availability. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Attendance source/time policy, exception/correction, device import, privacy, payroll handoff and failure/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable affected capture channel, preserve raw events and current approved state, revert compatible code/policy, replay idempotently and reconcile employee/day/payroll totals. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Clock-in/out is server-authoritative, idempotent and tied to effective employee/shift/policy.
- Exceptions and corrections preserve raw evidence and approval lineage.
- HRS-ATT-US-001, online-first mobile, timezone and performance gates pass.
- Tenant/self/team/location privacy and payroll reconciliation pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-279 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

