# Prompt 214 — Financial Field-Level Security

**Prompt ID:** `CG-S9-FIN-025`  
**Package document:** `CG-AABPP-FIN-214`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-214.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-025` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Security; Epic: Sensitive Financial Data Protection; Capability: Financial Field and Record Policy; Feature slice: classification, projection, mutation, filter/sort/search/export/report/log and inference control; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement and verify one financial field/record access policy across database, services, REST, GraphQL, UI, reports, exports, jobs, logs and support access.

## 5. Business value

Prevent unauthorized disclosure or mutation of price, margin, cost, tax, bank, credit, payment and journal data.

## 6. Source requirement

FIN-GL/AR/AP/TAX/CLS/PRF security; CPD-006/007; RPD-023/025/035/039. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..213 and Platform field/record policy foundation. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-215..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add/extend policy metadata/views/functions/masking needed for Finance fields and record scopes; RLS remains tenant control and field security is not simulated only in UI.

## 14. API impact

REST/GraphQL share allowlisted serializers/projections, input mutation rules, filter/sort/search/export policy and schema/introspection behavior appropriate to authorization. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance pages render only allowed fields/actions; masked values are not recoverable from HTML/client state; permission-denied and support/impersonation context are explicit. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Classify selling price, margin, cost, credit, tax identity/rule, bank account, payment, payroll-adjacent and journal fields; MFA, least privilege, time/purpose-bound visible support access and safe logs. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Policy enforcement uses indexed scope and precomputed safe projections where needed; no post-fetch filtering of sensitive full rows. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record privileged view/export/unmask/mutation, policy version, actor/scope/purpose, support session and denied inference attempts without logging secrets/full sensitive values. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Classify every existing Finance field/API/report/export/log; unsafe surfaces are blocked until repaired and tested. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Finance fields, records and every read/write/derived surface.
- Define canonical classification/action/role/scope/status/value policy matrix.
- Implement shared database/service/API/UI/report/export/search/log enforcement.
- Add support/impersonation/MFA and aggregate-inference controls.
- Run exhaustive allowed/denied/cross-tenant and performance tests.

## 21. Main flow

Request enters with tenant/user/role/company/branch/customer/action/status context; service/database selects only permitted records/fields, applies mask/serializer and audits privileged access.

## 22. Alternative flow

Return a safe aggregate or masked projection, require step-up/MFA, or deny with readable reason when detail is not authorized.

## 23. Exception flow

Treat leakage through GraphQL introspection/error, filter/sort/search, export, cache, job, log, report aggregate, client payload or support session as critical/high blocker. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Field policy governs read, create/update input, filter, sort, search, aggregate, export, print and logs.
- RLS alone is not field security; UI hiding is never sufficient.
- Customer users see only their own allowed invoice/payment fields after Step 13, never internal cost/margin/bank/journal data.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Every field has classification, owner, allowed actions/scopes and mask behavior.
- Derived metrics inherit the strongest contributing restriction and suppress inference.
- Policy parity holds across REST/GraphQL/UI/report/export/job/cache/log.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Use configurable roles within immutable platform security minimums; privileged Finance approvers require MFA; support is time/purpose-bound, logged and tenant-visible; RPD-022 risk remains explicit. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

All Finance roles/layers, customer scopes, support/impersonation, allowed/denied fields, aggregate inference, error/log/cache/export/search channels and Tenant A/Tenant B. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Policy matrix unit/property tests and database RLS/view/function tests.
- REST/GraphQL/UI/report/export/search/filter/sort/job/cache/log parity and leakage-negative tests.
- MFA/support/impersonation, cross-tenant/customer, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Platform RBAC/RLS/field policy, every Finance prompt, Commercial credit/margin, Operations cost and future portal/enterprise APIs. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Finance data classification and field/action matrix, support/MFA procedures, leakage response and verification evidence map. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable unsafe surface/export/cache, rotate exposed credentials if relevant, restore prior safe projection and open incident/reconciliation tasks; never accept masking-only cosmetic fixes. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every Finance surface enforces the same policy.
- Negative tests prove no cross-tenant/customer or restricted-field leakage.
- Privileged access is bounded, visible and auditable to the available extent.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-215 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

