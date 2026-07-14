# Prompt 277 — Onboarding and Offboarding

**Prompt ID:** `CG-S12-HRT-005`  
**Package document:** `CG-AABPP-HRT-277`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-277.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-005` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Recruitment and Workforce Entry/Exit; Epic: Governed Workforce Entry and Exit; Capability: Onboarding, Transfer and Offboarding Orchestration; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Convert an accepted candidate or approved direct hire into linked employee/user readiness and later offboard workers without losing required business history.

## 5. Business value

Coordinate People, access, assets, training, Operations and Finance handoffs with clear ownership, due dates and revocation evidence.

## 6. Source requirement

HRS-REC and HRS-ESS requirement cards plus master Onboarding/offboarding capability. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..276; Platform identity/access/workflow/task/file and verified downstream ownership contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-278..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create versioned onboarding/offboarding case, checklist template/version, task/dependency, owner, due/SLA, asset/access/training/payroll/Operations handoff, evidence and completion records linked to canonical candidate, employee and user IDs.

## 14. API impact

Shared REST/GraphQL start, preview, assign, complete/waive/reopen task, provision-request, revoke-request, finalize/cancel and read/report APIs; external systems remain acknowledged handoffs, not assumed success. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Role-based onboarding/offboarding case workspace, checklist/dependencies, due/blocked state, evidence, access/asset preview and approval timeline with responsive accessible employee/manager/HR views. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Provision/revoke operations go through Platform identity authority; sensitive HR evidence and exit reason are field-restricted; task owners receive only minimum payload; files are private/scanned. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/case/employee/user/type/status/owner/due date/template version; async notifications/provisioning adapters with backpressure and reconciliation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record case source, checklist version, task assignment/completion/waiver, provision/revoke request and acknowledgement, asset/evidence access, approvals and finalization. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Adopt open manual checklists only through explicit case/import mapping; never mark access revoked, asset returned or payroll closed without verified acknowledgement. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define case/checklist/dependency and candidate→employee→user conversion invariants.
- Implement versioned onboarding/offboarding workflow, APIs and accessible workspace.
- Bind Platform access provisioning/revocation and downstream handoffs with acknowledgement.
- Implement evidence/files, waiver/reopen and overdue escalation.
- Test partial failure, rehire/cancel, retention and no-history-loss behavior.

## 21. Main flow

HR starts from an accepted offer or approved direct hire, creates/links the employee, instantiates the current checklist, completes verified access/asset/training/payroll/Operations handoffs and finalizes only after mandatory acknowledgements.

## 22. Alternative flow

Preboarding without user access, delayed start, transfer checklist, contractor lifecycle, cancellation, rehire linked to historical employee or immediate security offboarding.

## 23. Exception flow

Block duplicate employee/user conversion, missing mandatory task, failed provisioning/revocation, unreturned critical asset, stale checklist/config or unauthorized waiver; keep case resumable and surface exact owner. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Accepted offer conversion is idempotent and creates/links one canonical employee; it never duplicates user or organization truth.
- Checklist templates are versioned; active cases retain their applied version under RPD-040.
- Task completion requiring external action needs acknowledged evidence, not UI-only success.
- Offboarding schedules or performs access revocation via Platform authority and preserves legal/financial/operational history.
- Waive, reopen, cancel, rehire and emergency exit require reason, permission and audit.

## 25. Validation rules

Validate source candidate/direct-hire approval, employee/user links, effective dates, checklist dependencies, mandatory evidence, task authority, acknowledgement and active config version before completion/finalization.

## 26. Access rules

HR controls cases; employees/managers/task owners see only assigned/permitted slices; Platform admins execute access actions; Finance/Operations acknowledge contracted handoffs without seeing unrestricted HR fields. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Candidate/direct hire, prehire, transfer, contractor, cancelled start, rehire, immediate exit, failed provisioning/revocation, overdue tasks, waivers and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Case/checklist/dependency/version and lifecycle tests.
- Idempotent conversion and duplicate employee/user tests.
- Provision/revoke acknowledgement, partial-failure and retry tests.
- RLS/RBAC/field/file/task-owner isolation tests.
- Onboarding/offboarding browser/accessibility and recovery E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Recruitment offer, employee master, Platform user/role/session, Operations assignment, Finance payroll handoff, notifications/files/jobs. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Entry/exit ownership, checklist authoring, provisioning/revocation, emergency offboarding, rehire and partial-failure recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause case transitions, revoke new intake grants if unsafe, preserve employee/history and verified acknowledgements, restore prior task/config behavior and reconcile access/asset states. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Accepted candidate/direct hire converts idempotently to linked employee/user readiness.
- Mandatory checklist and downstream acknowledgements gate finalization.
- Offboarding revokes/schedules access without deleting required history.
- Partial failure, waiver, rehire, tenant/field/file and audit gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-278 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

