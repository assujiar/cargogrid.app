# Prompt 293 — Sensitive Personal and Payroll Data Controls

**Prompt ID:** `CG-S12-HRT-021`  
**Package document:** `CG-AABPP-HRT-293`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-293.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-021` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: HR/Ticket Privacy, Files, API and Jobs; Epic: Purpose-Bound Sensitive Data Protection; Capability: HR/Payroll Classification, Field Policy and Inference Control; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Harden all Phase 7 HR and payroll surfaces so restricted fields remain purpose-bound across database, service, API, UI, files, jobs, logs, cache, search, notification, reports, exports and support access.

## 5. Business value

Prevent direct and inferential workforce-data leakage while preserving legitimate HR/payroll operations and auditable employee rights.

## 6. Source requirement

All HRS families, master sensitive personal/payroll control, UX field security and Technical Architecture PII/payroll controls. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..292; Platform field policy, MFA, files, audit, retention and support controls. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-294..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Audit and repair classification/column ownership, RLS, field policy, encrypted/secret references where appropriate, purpose grants, sensitive-access events, export approvals and retention/legal-hold metadata across HR/ticket-linked surfaces. Do not add shadow sensitive stores.

## 14. API impact

Enforce one field-projection policy for REST/GraphQL/actions/jobs/exports; typed errors and safe aggregates prevent inference. Bulk sensitive exports and high-risk mutations require current auth, reason, approval/MFA as configured. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Role/purpose-aware masking, reveal-with-reason where approved, secure payslip/document delivery, export warnings/approval, session timeout and safe print/download; denied fields disappear from totals, filters, suggestions and saved views. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Cover personal identifiers/contact/address/emergency/medical, candidate, attendance/location, salary/allowance/deduction/tax/bank/loan/reimbursement, performance/talent and support-linked HR data. Apply least privilege, separation, MFA, private scanned files, retention and RPD-022 disclosure. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Field policy must be index- and query-aware without broad fetch-then-redact; benchmark authorized/denied projections, sensitive audit volume, export jobs and cache invalidation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record sensitive read/reveal/download/export/search denial/mutation with actor, purpose, scope, field class, case/approval/MFA context and result; logs contain no raw sensitive value. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Classify/backfill metadata and move unsafe plaintext/log/cache/search artifacts through reviewed, reversible migration; rotate/revoke derived exports and URLs where required without deleting legal-hold evidence. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Build a complete Phase 7 data-classification and purpose/role/field/record matrix.
- Inspect and repair RLS/service/API/UI/job/file/search/cache/log/export policy parity.
- Implement high-risk mutation/export/reveal MFA/maker-checker and sensitive audit.
- Verify retention/legal hold, malware scan/signed URL and support-case access.
- Run abuse, inference, observability, performance and recovery testing across all HR/ticket surfaces.

## 21. Main flow

A caller requests an HR/payroll field or action; server resolves tenant, principal, role, effective record scope, purpose, field class, state and high-risk controls, returns the minimum permitted projection and records privacy-safe evidence.

## 22. Alternative flow

Employee accesses own data/payslip, manager sees minimized team data, HR/payroll performs approved bulk work, Finance consumes contracted payroll handoff or case-bound support investigates with time-limited grant.

## 23. Exception flow

Deny/terminate access on missing purpose, field/record permission, stale employment/manager scope, absent MFA/approval, cross-tenant/account link, unsafe export/file/cache or expired support grant; reveal no protected value/existence. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Authorization is field- and record-specific at database/service boundaries; UI masking alone is never sufficient.
- Restricted fields never enter generic search facets, logs, analytics, notifications, cache keys/values, URLs or error messages.
- Manager hierarchy does not grant payroll, bank/tax, medical, candidate, talent or unrestricted personal fields.
- Every upload is private and malware-scanned before release; downloads use short-lived scoped URLs and audit.
- RPD-025 retention/legal hold and RPD-022 absolute-admin residual risk are explicit; never claim tamper-proof privacy.

## 25. Validation rules

Validate classification, purpose, tenant/company/branch/employee/customer/support scope, field permission, current auth/MFA/approval, file state, export destination/retention and policy version for each surface.

## 26. Access rules

Employees get configured own-data rights; managers get minimized effective-team data; HR/payroll duties are separated; Finance/Operations receive contracted projections; support is case/time/purpose-bound. Supreme Admin risk remains disclosed. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

All sensitivity classes, employee/manager/HR/payroll/Finance/Operations/customer/support/Supreme roles, revoked/transfer cases, bulk export, malicious file, stale cache/search index, expired grant and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Classification/policy matrix and field-projection parity tests.
- RLS/RBAC/ABAC/manager/customer/support/cross-tenant abuse tests.
- Search/filter/count/cache/log/error/notification/report/export inference tests.
- MFA/maker-checker/reveal/file/retention/legal-hold/audit tests.
- Authorized/denied query, export-job and cache-invalidation performance tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

All Phase 7 capabilities, Platform IAM/RLS/files/audit/support, Finance handoff, Operations workforce references, customer ticket links and generic analytics/search/export. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Data classification, purpose/field matrix, employee/manager/payroll/support access, high-risk action/export, files/retention/legal hold, incident and evidence-redaction runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Immediately revoke unsafe route/export/grant/cache/file URL, preserve privacy-safe evidence/legal holds, restore last verified policy, rotate affected credentials/links, reconcile exposure scope and follow incident process. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- All HR/payroll sensitive fields have one source-backed classification and policy matrix.
- Database/service/API/UI/job/file/search/cache/log/report/export parity passes abuse tests.
- MFA/maker-checker, private scanned files, retention/legal hold and support grants pass.
- No prohibited inference or raw-value telemetry; performance and recovery evidence pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-294 after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

