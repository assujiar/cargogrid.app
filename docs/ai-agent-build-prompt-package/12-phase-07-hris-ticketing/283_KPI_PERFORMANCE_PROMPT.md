# Prompt 283 — KPI and Performance

**Prompt ID:** `CG-S12-HRT-011`  
**Package document:** `CG-AABPP-HRT-283`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-283.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-011` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Performance, Learning and Talent; Epic: Human-Governed Workforce Development; Capability: KPI Library, Goal Cycle, Review and Calibration; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned KPI and performance cycles with explainable scoring, feedback, calibration and human decision authority.

## 5. Business value

Align employee goals to organization outcomes while preventing opaque scoring, manager overreach and historical result drift.

## 6. Source requirement

HRS-KPI-001..004 and HRIS Performance, KPI, Training & Talent requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..282; effective organization/manager, workflow/approval and reporting foundations. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-284..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create KPI library/version, cycle/template, goal/target/unit/weight, employee assignment, progress/evidence, self/manager/reviewer assessment, score/calculation version, calibration, outcome, acknowledgement and appeal records.

## 14. API impact

Shared REST/GraphQL KPI/cycle configure/publish, assign, update progress, submit review, score, calibrate, acknowledge/appeal and scoped report/export APIs with exact decimal and version semantics. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

KPI library/cycle builder, employee goal/progress/self-review, manager team review, calibration grid with accessible table alternative, evidence and acknowledgement/appeal views; complete privacy states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Performance notes, ratings and calibration are sensitive; employee/manager/reviewer/HR visibility is purpose- and cycle-stage-bound; aggregate reports prevent small-cohort inference. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/cycle/employee/manager/KPI/status/period; server score calculation, cursor team queues and async assignment/report/export for large cycles. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record template/KPI/weight/formula versions, assignments/targets, evidence access, assessment before/after, calibration adjustments/reason, outcome/appeal and exports. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import historical ratings/goals as source-labeled snapshots; do not synthesize score components or recalculate old outcomes without governed migration. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define KPI/cycle/weight/score/calibration and history invariants.
- Implement versioned schema, exact scoring, shared APIs and accessible role UX.
- Bind effective employee/manager scope and governed review/appeal workflow.
- Implement privacy-safe reporting/export and large-cycle jobs.
- Test scoring, stage access, calibration, concurrency and no-AI boundary.

## 21. Main flow

HR publishes a versioned performance cycle, assigns weighted goals, employee and manager record evidence/reviews, authorized calibration adjusts with reasons, final outcome is acknowledged and any appeal follows workflow.

## 22. Alternative flow

Mid-cycle goal revision, skipped/not-applicable KPI, multi-reviewer/360 input, delegated reviewer, incomplete cycle extension or appeal/reopen.

## 23. Exception flow

Block invalid weight/target/unit, unauthorized note/rating, stale stage/version, manager relationship change without explicit reassignment, missing evidence or unapproved calibration; retain prior submitted version. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- KPI definitions, weights, formulas, cycles and applied employee assignments are versioned and exact.
- A score is explainable from visible permitted inputs; manual adjustment requires reason and authority.
- Effective manager scope does not silently transfer submitted reviews; reassignment is explicit and audited.
- Performance outcomes do not automatically alter pay, employment or access; downstream actions require separate human approval.
- Predictive performance/talent scoring and autonomous recommendation remain Step 14.

## 25. Validation rules

Validate active cycle/version, employee/reviewer eligibility, goal unit/target, exact weight total/rounding, stage transition, evidence, calibration authority, concurrency and privacy policy.

## 26. Access rules

Employees see own permitted goals/reviews/outcomes; managers see effective assigned team; reviewers only assigned slices; HR configures/calibrates within scope. Reports/exports apply field and small-cohort controls. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Multiple KPI units/weights, not-applicable goals, manager transfer, self/manager disagreement, calibration adjustment, appeal/reopen, small cohorts, stale version and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- KPI/version/weight/exact-score and lifecycle tests.
- Reviewer assignment/stage/concurrency/calibration/appeal tests.
- RLS/RBAC/note/rating/small-cohort/export negative tests.
- Employee-manager transfer and downstream no-auto-action tests.
- Performance cycle browser/accessibility and large-cycle job tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Employee/organization/manager links, Platform workflow/jobs, payroll no-auto-change boundary, reporting and generic export/privacy controls. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

KPI/version/scoring, review/calibration, manager reassignment, privacy/reporting, appeal and cycle recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause cycle transitions, preserve submitted reviews/outcomes, restore prior published version for untouched assignments, revert compatible code/policy and reconcile scores/assignments before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- KPI and performance cycles are versioned, exact and explainable.
- Manager/reviewer/stage/privacy and small-cohort controls pass.
- Calibration/appeal preserves reasons, history and human authority.
- No autonomous pay/employment action; concurrency, scale and Tenant A/B gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-284 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

