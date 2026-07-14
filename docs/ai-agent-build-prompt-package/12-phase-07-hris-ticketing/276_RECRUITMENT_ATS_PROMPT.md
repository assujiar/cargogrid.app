# Prompt 276 — Recruitment, Job Portal and ATS

**Prompt ID:** `CG-S12-HRT-004`  
**Package document:** `CG-AABPP-HRT-276`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-276.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-004` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Recruitment and Workforce Entry/Exit; Epic: Governed Talent Acquisition; Capability: Vacancy, Candidate, Assessment, Interview and Offer; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-scoped recruitment from approved vacancy through candidate assessment, interview and offer while protecting candidate data and deferring employee creation to onboarding.

## 5. Business value

Replace spreadsheet/email recruiting with traceable, permission-safe candidate progression and reusable approved workforce entry.

## 6. Source requirement

HRS-REC-001..004 and HRIS Recruitment, Job Portal & ATS requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-275; Platform workflow/approval/file/notification/public-intake primitives. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-277..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create or extend vacancy, candidate, application, source/consent, assessment, interview, feedback, offer/version and stage-history records with position references, retention classification and no employee/user duplication.

## 14. API impact

Shared REST/GraphQL vacancy, scoped job-posting intake, application, duplicate candidate search, stage transition, assessment/interview feedback, offer approval/acceptance and export APIs with expiring intake tokens and idempotency. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Recruitment pipeline/table, vacancy builder, candidate profile, assessment/interview scorecards, offer version/timeline and bounded responsive job-application surface; complete accessibility and failure states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Candidate PII/documents/feedback/offers are purpose-bound and field-separated; interviewers see only assigned candidate fields; public intake cannot enumerate vacancies/candidates or read existing data. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vacancy/position/stage/owner/source/candidate hash/date; server filters and cursor pipeline, async resume scan/import/notification, bounded duplicate search. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record consent/source, candidate merge decisions, stage/feedback/offer versions, approvals, downloads, exports, denials and retention actions. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Stage legacy vacancies/candidates/applications with reviewed duplicate crosswalks and consent/retention classification; never infer acceptance or auto-convert to employee. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define candidate identity, consent, duplicate and vacancy-position ownership.
- Implement recruitment schema, workflow, APIs and accessible pipeline/intake.
- Implement assessment/interview feedback and versioned offer approval/acceptance.
- Add retention, private scanned documents and purpose/field access.
- Test public abuse, duplicate/concurrency, stage/offer and onboarding handoff.

## 21. Main flow

Recruiter opens an approved vacancy linked to a position, receives a consented application, screens and advances the candidate through governed assessment/interview, issues an approved offer and records explicit acceptance for onboarding.

## 22. Alternative flow

Talent-pool candidate, employee referral, agency/import intake, duplicate merge review, reschedule, rejection with retention policy or offer revision/resubmission.

## 23. Exception flow

Block invalid/closed vacancy, duplicate ambiguity, missing consent, unscanned document, unauthorized feedback, stale offer version or illegal stage transition; preserve application and safe resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Candidate/application is not an employee or Platform user until governed onboarding conversion.
- Vacancy headcount and position references use the effective organization/position contract.
- Assessment criteria and offer terms are versioned; only authorized humans decide selection and approval.
- Candidate data, interview notes and offer compensation are purpose- and field-restricted.
- Public intake is rate-limited, enumeration-safe and non-authoritative; AI ranking stays Step 14.

## 25. Validation rules

Validate vacancy/position/headcount, candidate identity/consent, document scan, stage prerequisites, interviewer assignment, assessment completeness, offer exact amounts/effective dates/version and approval before transition.

## 26. Access rules

Recruiters manage scoped pipelines; hiring managers/interviewers see assigned slices; approvers see offer evidence; candidates use scoped expiring intake/session grants only. Policies apply to search/export/files. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Open/closed/future vacancies, duplicate candidates, consent states, multiple applications, interviewer conflicts, offer revisions/declines, malicious files and Tenant A/B/public fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Vacancy/candidate/application/stage/offer domain tests.
- Public token/rate-limit/enumeration/cross-tenant/file negative tests.
- Assessment/interview/offer workflow, idempotency and concurrency tests.
- Retention/export/field-masking and notification tests.
- Recruitment pipeline/application browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Position capacity, Platform workflow/approval/file/notification, employee duplicate search and generic public-route protections. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Recruitment lifecycle, candidate privacy/retention, public intake, assessment/interview, offer approval and onboarding-handoff runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Close new intake safely, preserve applications/offer history, revoke tokens, revert compatible code/policies and reconcile notifications/jobs before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Vacancy-to-accepted-offer flow is governed, versioned and auditable.
- Candidate identity never silently becomes employee/user truth.
- Public intake and candidate PII/documents resist enumeration and unauthorized access.
- Position, approval, file, retention and onboarding-handoff gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-277 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

