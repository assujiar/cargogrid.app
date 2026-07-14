# Prompt 199 — Accounts Payable

**Prompt ID:** `CG-S9-FIN-010`  
**Package document:** `CG-AABPP-FIN-199`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-199.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-010` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Procure to Pay; Epic: Payable Control; Capability: Accounts Payable Subledger; Feature slice: vendor open item, due balance, status, hold and source lineage; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Accounts Payable open-item control from verified vendor bills and Operations actual-cost references, without implementing the full Procurement/vendor lifecycle.

## 5. Business value

Give Finance reliable vendor obligations, due balances and settlement control.

## 6. Source requirement

FIN-AP-001..004; OPS-CST-001..004 Finance depth; Step 11 linkage. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..195 and verified Operations actual cost/vendor reference. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-200..218 and Step 11 full matching. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add AP account/open-item root, vendor/resource/job/shipment/bill references, currency, original/open/settled amounts, due date, canonical status, hold/release and subledger links.

## 14. API impact

Shared REST/GraphQL AP list/read/activity, authorized hold/release, balance and source-lineage operations; creation only through vendor-bill posting. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance AP queue/detail with server filters, vendor/job/shipment/bill/source drill-down, due/hold state, settlement history and access-safe actions. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Bank/tax/cost fields restricted; vendor record references follow actual available master contracts; no unauthorized creation of Procurement vendor identity. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/vendor/status/due/currency/bill; cursor paginate open items and budget live aggregates. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source posting, hold/release, settlement changes, status, approver and AP/subledger/GL reconciliation. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import legacy AP only with vendor/bill mapping, opening-balance approval and subledger/GL reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect vendor references, actual-cost and payable models.
- Define AP open-item lifecycle and exact balance constraints.
- Implement service/read APIs, AP queue/detail and field projections.
- Integrate vendor-bill/settlement/subledger events and Step 11 contract.
- Verify balance, isolation, migration, performance and evidence.

## 21. Main flow

A posted vendor bill creates one idempotent AP open item; settlements reduce the balance and status derives from exact remaining amount.

## 22. Alternative flow

Place an authorized payment hold, settle partially, or migrate an approved opening payable.

## 23. Exception flow

Block duplicate source, vendor/scope mismatch, unexplained negative balance, over-settlement, inactive/ambiguous vendor reference, locked correction or unauthorized cost/bank exposure. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- AP is created through controlled bill posting, not arbitrary balance entry except approved migration.
- Open amount equals original amount minus valid settlements and governed corrections.
- Phase 4 uses available verified vendor references; full onboarding/PO/contract/performance remains Step 11.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Amounts/currency reconcile to bill/subledger/GL.
- Due date follows captured payment-term policy and approved override.
- Hold/status transitions follow workflow and separation of duties.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

AP staff manage scoped items; Finance Manager approves holds/releases; Procurement receives only contract-defined status later; customer users have no AP access. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Open/partial/settled/overdue/held items, multiple vendors/companies, multi-currency, duplicate bill event, opening balance and unauthorized users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Open-item/balance/status/due/hold exact-money tests.
- Vendor-bill/idempotency/settlement/subledger integration and API parity tests.
- RLS/RBAC/field/record isolation, migration, concurrency, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Operations actual cost/vendor assignment, Finance configuration, vendor bill, settlement, aging, reconciliation and Step 11 contracts. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

AP lifecycle/data dictionary, vendor-reference boundary, opening-balance and reconciliation guide. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Stop new AP creation, reverse unposted event, restore prior read model and reconcile source/subledger/GL; posted correction uses governed reversal. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every AP item is unique, exact and source-linked.
- Balances reconcile after partial/full settlement.
- Finance implementation does not smuggle in Step 11 vendor/PO scope.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-200 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.
