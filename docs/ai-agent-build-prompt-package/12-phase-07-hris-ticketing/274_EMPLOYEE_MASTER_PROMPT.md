# Prompt 274 — Employee Master

**Prompt ID:** `CG-S12-HRT-002`  
**Package document:** `CG-AABPP-HRT-274`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-274.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-002` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Workforce Master and Lifecycle; Epic: Canonical Workforce Identity; Capability: Employee Master; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the canonical tenant-scoped employee workforce profile linked to—never replacing—Platform identity and organization records.

## 5. Business value

Give HR and authorized managers one effective-dated workforce truth that downstream time, payroll, assignment and self-service flows can reuse without re-entry.

## 6. Source requirement

HRS-EMP-001..004, HRS-EMP-US requirements and UX screen HRS-EMP-001. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-273; verified Platform identity/organization/master/file/access foundations and Phase 5 operational workforce references. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-275..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend the canonical workforce domain with employee number, employment type/status, work and sensitive-personal profiles, company/branch/department/position/manager references, effective dates, contacts, emergency contact, documents, source/config versions and lifecycle history. Authentication remains on Platform user identity.

## 14. API impact

Shared REST/GraphQL create, import, search, read, update, submit, approve, activate, suspend, terminate/archive, request-change and scoped export operations with one domain service and parity. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Employee directory/profile with personal, employment, organization, document and history tabs; HR edit, own read/request-change and manager-scoped views with masked fields and complete loading/empty/error/denied/stale/degraded states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Classify identity numbers, address, phone, personal email, bank/tax and emergency data; enforce purpose/field/record policy, own/team/HR scope, export controls, private scanned files and sensitive-access audit. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/employee number/status/company/branch/department/position/manager/effective period; cursor lists, selective projections, server filters and asynchronous import/document work. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record profile and lifecycle before/after, source, effective version, approval, document access, sensitive reads/exports, impersonation and downstream references. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Adopt existing Platform users and operational driver/worker references through explicit mapping; never auto-create duplicate employees or rewrite historical assignments. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Prove employee-versus-user-versus-driver ownership and publish an ADR if ambiguous.
- Define effective-dated employee identity, lifecycle, duplicate and correction invariants.
- Implement schema/policies/services/APIs and accessible employee directory/profile.
- Implement staged import and governed own-profile change requests.
- Test tenant/field isolation, history, duplicates, files and downstream compatibility.

## 21. Main flow

HR creates or imports a candidate employee profile, resolves duplicates, completes required employment and sensitive fields, submits for approval and activates the effective-dated employee linked to the correct Platform identity.

## 22. Alternative flow

Create a profile before a user account, link an existing user later, request personal-data correction, transfer company/branch/department/position, suspend or archive with preserved history.

## 23. Exception flow

Block duplicate employee/user ambiguity, invalid effective dates, inactive organization, unauthorized field access, unscanned file, stale version or conflicting downstream assignment; preserve staged data and exact resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- One employee workforce profile may link to zero or one active Platform user identity per effective context; identity/authentication remains Platform-owned.
- Employee number uniqueness, employment status and transfer rules are tenant-configured and versioned.
- Sensitive personal data is minimized and never copied into generic user, ticket, log, cache or analytics payloads.
- Deletion/termination never erases required payroll, attendance, Operations or audit history.
- RPD-022 prevents immutable-for-all claims; no tenant fork, offline sync or autonomous HR decision.

## 25. Validation rules

Validate tenant/company/branch/department/position/manager scope, uniqueness, required fields, dates, lifecycle, source/config version and document state before mutation. Reject cyclic reporting lines, cross-tenant references and stale concurrency.

## 26. Access rules

HR roles maintain permitted profiles; employees see/request changes only to allowed own fields; managers see current effective team fields; Finance/Operations receive only contracted projections. Database/service enforcement is mandatory. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Active/inactive/transferred/terminated employees, linked/unlinked users, duplicate numbers, cyclic managers, sensitive fields, staged imports, unscanned documents and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Employee identity/lifecycle/effective-date/database/service tests.
- RLS/RBAC/field-masking/own-team/cross-tenant/export negative tests.
- Import duplicate/idempotency/concurrency and file-scan tests.
- Platform user and Operations driver/reference compatibility tests.
- HRS-EMP-001 browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform user provisioning, organization hierarchy, role membership, Operations assignment, search/import/file and audit behavior. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Employee identity/user-link contract, lifecycle/effective dating, import/duplicate, sensitive-data and downstream-projection runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable new HR mutations, preserve canonical mappings/history, revert compatible code/policies and reconcile staged imports or duplicate links before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Canonical employee master works without duplicating Platform user or organization truth.
- Effective-dated lifecycle and transfers preserve history and downstream references.
- Sensitive personal fields are masked, purpose-bound and audited.
- Tenant/own/team/HR isolation, files, import and downstream compatibility gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-275 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

