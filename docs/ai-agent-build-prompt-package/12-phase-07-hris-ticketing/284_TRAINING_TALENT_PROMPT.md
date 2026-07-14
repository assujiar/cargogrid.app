# Prompt 284 — Training and Talent

**Prompt ID:** `CG-S12-HRT-012`  
**Package document:** `CG-AABPP-HRT-284`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-284.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-012` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Performance, Learning and Talent; Epic: Human-Governed Workforce Development; Capability: Training Catalogue, Enrollment, Completion and Talent Planning; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed learning and talent records linked to employee, position and performance evidence without predictive or autonomous talent decisions.

## 5. Business value

Track required skills, training completion and development actions with verifiable evidence and controlled visibility.

## 6. Source requirement

HRS-KPI-001..004 and HRIS Performance, KPI, Training & Talent requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..283; employee/position, performance, workflow/file/job foundations. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-285..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create competency/skill and training catalogue/version, course/session/provider, prerequisite, enrollment, attendance/completion, assessment/certificate/expiry, development plan, talent review/pool/succession candidate and decision-evidence records.

## 14. API impact

Shared REST/GraphQL catalogue/session configure, enroll/approve/cancel, record attendance/result, issue/verify certificate, development plan, talent review and scoped report/export APIs; reminders/expiry use durable jobs. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Training catalogue/calendar, enrollment and completion views, manager/HR learning queue, certificate evidence, development plan and restricted talent-review workspace with accessible complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Training may be broadly visible but results, development plans and talent/succession records are purpose- and field-restricted; provider/certificate files are private/scanned; small-cohort reporting is protected. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/employee/course/session/status/date/skill/certificate expiry; cursor catalogues, async enrollment/expiry/notification/report jobs and selective evidence projections. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record catalogue/session/version, enrollment decision, completion/result/certificate, expiry/reminder, development/talent changes, manual adjustment, evidence access and export. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import historical completion/certificates as source-labeled evidence with verification/expiry state; do not infer competency or talent classification from incomplete records. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define catalogue/session/completion/certificate and development/talent evidence invariants.
- Implement schema, shared APIs, durable jobs and accessible role UX.
- Bind employee/position/KPI evidence and governed enrollment/approval.
- Implement certificate expiry, private evidence and restricted talent review.
- Test privacy, prerequisites, completion, retry/reconciliation and later-AI boundary.

## 21. Main flow

HR publishes a versioned course/session, eligible employee enrolls or is assigned, prerequisite and approval rules pass, attendance/assessment evidence is recorded, completion/certificate is verified and development records update with human review.

## 22. Alternative flow

External course/provider, mandatory compliance training, waitlist/cancel/reschedule, certificate renewal, manager-assigned plan or restricted succession review.

## 23. Exception flow

Block ineligible/prerequisite failure, session capacity conflict, unauthorized result/talent access, unscanned certificate, stale course/session version or duplicate completion; preserve enrollment/evidence. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Course, competency, assessment and certificate semantics are versioned; active records retain applied versions.
- Training completion requires configured attendance/assessment/evidence, not a UI toggle alone.
- Talent pool/succession decisions require authorized human evidence, reason and review; predictive ranking stays Step 14.
- Training outcomes do not automatically change position, pay or employment.
- Certificate expiry/reminder may affect eligibility only through configured, auditable downstream rules.

## 25. Validation rules

Validate employee/course/session/provider, prerequisites, capacity, dates, result scale, evidence scan, certificate uniqueness/expiry, reviewer authority, config version and concurrency.

## 26. Access rules

Employees see own eligible/enrolled/completed learning; managers see effective team development; HR/training admins manage scope; restricted talent reviewers see assigned cases. Policies cover reports/exports/files. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Mandatory/optional/external courses, prerequisites, full/waitlist, pass/fail/incomplete, certificate expiry/renewal, talent review, small cohort, retries and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Catalogue/session/enrollment/completion/certificate domain tests.
- Prerequisite/capacity/waitlist/version/concurrency tests.
- RLS/RBAC/result/talent/small-cohort/file/export negative tests.
- Expiry/reminder job retry/reconciliation tests.
- Training and restricted talent browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Employee/position/performance, Platform workflow/files/jobs/notifications, Operations eligibility and reporting privacy controls. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Training catalogue/session, enrollment/completion, certificate verification/expiry, development/talent privacy and recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause enrollment/results/jobs, preserve verified completion/certificates, restore prior published versions for new activity, revert compatible code/policy and reconcile session/employee totals. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Training enrolment, completion and certificate evidence are versioned and verifiable.
- Prerequisite, capacity, privacy, file and expiry controls pass.
- Talent/development decisions remain restricted and human-governed.
- Jobs, Tenant A/B, accessibility and downstream compatibility gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-285 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

