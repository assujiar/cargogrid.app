# Prompt 198 — Receipt and Payment Allocation

**Prompt ID:** `CG-S9-FIN-009`  
**Package document:** `CG-AABPP-FIN-198`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-198.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-009` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Order to Cash; Epic: Cash Application; Capability: Receipt and Payment Allocation; Feature slice: receipt capture, unapplied cash, exact split allocation, deallocation and source posting; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement customer receipt capture and exact allocation to AR open items with partial, multi-item and unapplied-cash control.

## 5. Business value

Provide timely cash visibility and auditable settlement of customer receivables.

## 6. Source requirement

FIN-AR-001..004; FIN-TAX; UAT Billing Readiness → Invoice/AR → Receipt → Allocation → Journal. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-194 and FIN-196..197; use the published Finance account contract, which FIN-211 later extends with bank-statement control. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-202..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add receipt root/reference/date/payer/bank/currency/rate/amount, allocation lines to AR, unapplied balance, canonical state, idempotency key and posting/reversal links with exact constraints.

## 14. API impact

Shared REST/GraphQL capture/import, validate, allocate-preview, allocate, deallocate-request, read and reconciliation operations. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Accounting split-screen receipt allocation with suggested candidates, exact remaining amounts, manual search, partial/unapplied handling, warnings and audit timeline. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Bank/payment fields are highly restricted; separate capture, allocate and approve where configured; imports/files are scanned and customer data is scoped. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/reference/date/payer/status/currency; server-search AR candidates and batch allocation transactionally. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record bank/source reference, matching logic, allocation before/after, rate, approver, idempotency, deallocation/reversal reason and journal links. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import receipts/allocations with source statements, stable keys and AR/subledger/GL/bank reconciliation before activation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect receipt/bank/import and AR contracts.
- Model receipt, allocation, unapplied balance and exact constraints.
- Implement capture/import, matching, allocation service, APIs and UX.
- Integrate subledger/journal/bank reconciliation and governed deallocation.
- Test balance, idempotency, concurrency, access and E2E.

## 21. Main flow

Accounting captures an authorized receipt, validates bank/currency, selects compatible AR items, previews exact allocations and posts once, leaving any remainder as controlled unapplied cash.

## 22. Alternative flow

Allocate partially across invoices, hold unapplied cash, use an approved exchange-rate path, or request governed deallocation/reallocation.

## 23. Exception flow

Block duplicate bank reference/idempotency key, over-allocation, currency/rate mismatch, closed/foreign AR, locked period, stale balance, negative remainder or unauthorized bank access. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Sum of allocations plus unapplied amount equals receipt amount exactly.
- Allocation cannot exceed current eligible AR open amount and uses concurrency control.
- Posted allocation correction uses governed reversal/deallocation with linked journal, never direct edit.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Receipt identity, date, bank/cash account, payer, currency/rate and amount are complete.
- Every allocation targets an open authorized AR item in compatible scope.
- Preview and commit preserve exact balance under retry and concurrency.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Accounting captures/allocates; configured approver handles thresholds/deallocation; Finance Manager reviews; non-Finance users cannot access bank details or internal allocations. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Exact/partial/multi-invoice/overpayment/unapplied receipts, multi-currency, duplicate statement rows, concurrent allocations, locked period and cross-tenant attempts. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Allocation equation, open-balance, rounding, idempotency and concurrency tests.
- Receipt/import/API parity/AR/subledger/journal/bank reconciliation E2E tests.
- RLS/RBAC/field/record isolation, performance, accessibility, migration and reversal tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

AR balance/aging, invoice status, bank/cash, journal posting, reporting and future customer visibility. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Receipt/allocation data dictionary, matching and FX policy, unapplied-cash/deallocation and reconciliation runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Void eligible draft receipt, reverse posted allocation and linked journal through approved flow, restore AR balances and reconcile bank/subledger/GL. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Allocation and unapplied balances equal receipt exactly.
- Retries and concurrent actions cannot double-allocate.
- Every posted allocation reconciles to AR, bank/cash and journal lineage.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-199 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.
