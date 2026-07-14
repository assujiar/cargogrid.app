# Prompt 194 — Currency and Exchange Rate

**Prompt ID:** `CG-S9-FIN-005`  
**Package document:** `CG-AABPP-FIN-194`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-194.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-005` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Foundation; Epic: Multi-Currency Control; Capability: Currency and Exchange-Rate Baseline; Feature slice: currency precision, rate type/source/version/effective time, conversion and rounding; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed currencies and exchange rates with exact-decimal conversion, versioned sources and deterministic rounding.

## 5. Business value

Let invoices, bills, payments and journals preserve transaction and functional-currency truth without silent rate changes.

## 6. Source requirement

FIN-TAX-001..004; FIN-GL; NFR financial integrity; RPD-016. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..193. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-195..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add currency/precision, tenant/company functional currency, exchange-rate type/source/pair/value/effective time/version/approval and transaction snapshot references using exact numeric types.

## 14. API impact

Shared REST/GraphQL manage-rate, approve, resolve, convert-preview and lineage operations; imports use staged idempotent jobs. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance Admin currency/rate table, import review, effective timeline, conversion preview, missing-rate errors and source/version drill-down. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict rate import/override/approval; field policy protects commercial rate sources and audit all privileged changes. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index pair/type/effective time; cache immutable approved versions and batch-resolve without N+1 calls. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source file/API, rate before/after, precision, approver, effective window, override reason and every transaction snapshot. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy currencies/rates with precision and source evidence; reconcile converted balances before activation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory currencies, money columns and rate sources.
- Define exact types, precision, pair/direction and resolver semantics.
- Implement staged import/approval, resolver, APIs and UX.
- Snapshot rate/version/rounding on every dependent transaction.
- Test conversions, missing/duplicate rates, isolation and reconciliation.

## 21. Main flow

Authorized user imports or enters a rate, validates source/pair/window, approves it, and transactions resolve and snapshot the exact version for deterministic conversion.

## 22. Alternative flow

Use tenant-approved manual rate with reason, triangulate only under an explicit published rule, or reverse a draft import before approval.

## 23. Exception flow

Block missing/zero/negative/ambiguous rate, overlapping approved versions, precision overflow, stale import, unsupported pair or unauthorized override. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Never use floating point for money or exchange rates.
- Posted transactions retain their captured rate/version; later rate changes do not rewrite them.
- Conversion direction, precision and rounding order are explicit and versioned.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Currency codes and scale are canonical and supported.
- Approved pair/type windows resolve deterministically.
- Converted amount and rounding residual reconcile under policy.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance Admin maintains; approvers publish; Finance users view authorized rate lineage; customer users see only allowed transaction amounts, never internal rate sources. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

IDR and foreign currencies, direct/inverse pairs, multiple rate types, overlapping/missing rates, boundary dates, high precision and unauthorized changes. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Exact conversion/rounding/resolver and constraint tests.
- Import/idempotency/API parity/RLS/RBAC/cross-tenant tests.
- Posted-snapshot immutability, concurrency, reconciliation and performance tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Commercial quote money, Operations actual cost, invoice/bill/payment/journal/profitability and exports. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Currency/rate data dictionary, resolver/rounding specification, import/approval and missing-rate runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Deactivate unconsumed erroneous rate version, restore prior resolver configuration and reconcile affected drafts; correct posted effects only through governed financial correction. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Conversions are exact, repeatable and source-linked.
- Missing or ambiguous rates block posting.
- Rate access and change evidence passes isolation and audit gates.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-195 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

