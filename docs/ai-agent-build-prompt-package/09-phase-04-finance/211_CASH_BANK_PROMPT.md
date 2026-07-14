# Prompt 211 — Cash and Bank

**Prompt ID:** `CG-S9-FIN-022`  
**Package document:** `CG-AABPP-FIN-211`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-211.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-022` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Treasury; Epic: Cash Position and Bank Control; Capability: Cash and Bank Baseline; Feature slice: bank/cash account, statement import, transaction, matching, position and restricted access; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/company bank and cash account control, statement ingestion, transaction matching and reconciled cash position without unapproved payment-provider behavior.

## 5. Business value

Provide trustworthy cash visibility and a governed source for receipt and settlement reconciliation.

## 6. Source requirement

FIN-TAX-001..004; master Phase 4 cash-and-bank requirement; RPD-038. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..195, FIN-198/201, FIN-208; reconciliation FIN-209. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-213..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add bank/cash account identity/masked details, currency/GL mapping, statement/import batch/line, transaction direction/amount/date/reference, match group/status and balance snapshots with source lineage.

## 14. API impact

Shared REST/GraphQL account management, staged statement import, validate, match/unmatch-request, position and reconciliation operations; provider adapters only by explicit case-specific scope. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Treasury account/statement/matching workspace with masked details, import review, unmatched queue, cash position, reconciliation status and complete error/degraded states. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Bank data/credentials are highly sensitive, masked and server-only; strict separation and MFA for account/config/import approval; files scanned/signed; no generic provider abstraction. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Stage/import asynchronously, deduplicate and index account/date/reference/amount/status; paginate statement lines and budget live cash queries. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record account/config changes, file/source hash, line mapping/dedup, manual match/unmatch, balance calculation, actor/approval and exports. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import accounts/statements with masked identifiers, stable source keys and opening balance/GL reconciliation; ambiguous lines remain unmatched. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect bank/cash/payment/import and GL contracts.
- Define account/statement/line/match/position schema and sensitive fields.
- Implement staged import/dedup, APIs, matching UX and position queries.
- Integrate receipts/settlements/journals and reconciliation.
- Run security, duplicate, scale, migration and cash-balance tests.

## 21. Main flow

Authorized Treasury imports a scanned/validated statement, system deduplicates lines, proposes matches to receipts/settlements, human confirms governed matches and cash position reconciles to GL.

## 22. Alternative flow

Enter approved petty-cash/manual transaction, leave line unmatched with owner, or implement one explicitly contracted case-specific adapter.

## 23. Exception flow

Block duplicate/altered statement, unknown account/currency, unsafe file, ambiguous automatic match, unauthorized detail access, balance discontinuity or blind adapter retry. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Bank statement/source evidence is preserved and never silently rewritten.
- Automatic match above approved confidence may still require human governance per policy; financial posting is never autonomous AI.
- Cash/bank position reconciles transactions, statements and GL; no direct summary balance editing.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Account ownership/currency/GL mapping and statement continuity are valid.
- Imported lines have stable source/hash/reference uniqueness.
- Match amount/date/direction/currency and target state satisfy configured rules.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Treasury/Accounting roles receive minimum bank data; approvers manage accounts/imports; management sees allowed positions; other roles and customer users cannot inspect bank details. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Multiple bank/cash accounts, statements with duplicate/changed files, exact/ambiguous/unmatched lines, receipts/settlements, petty cash, FX and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Import/dedup/continuity/match/position exact-money tests.
- Receipt/settlement/journal/reconciliation and API parity E2E tests.
- RLS/RBAC/MFA/field/file/export security, async retry, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Payment allocation, settlement, currency/tax, COA/journal, reconciliation, reports and integration security. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Bank/cash data classification, statement format/matching contract, case-specific adapter boundary and reconciliation/ambiguity runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Quarantine bad import, undo only unposted match metadata, preserve statement source, reverse financial effects through governed correction and reconcile account/GL. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Statement lines are deduplicated, restricted and source-preserved.
- Cash position reconciles to transactions and GL.
- No unapproved adapter or credential exposure is introduced.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-212 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

