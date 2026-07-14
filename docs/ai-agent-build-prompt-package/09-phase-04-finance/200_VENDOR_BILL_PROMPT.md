# Prompt 200 — Vendor Bill

**Prompt ID:** `CG-S9-FIN-011`  
**Package document:** `CG-AABPP-FIN-200`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-200.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-011` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Procure to Pay; Epic: Vendor Billing; Capability: Vendor Bill; Feature slice: actual-cost/source capture, basic match, tax, approval and AP posting; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement vendor bills linked to Operations actual cost and available governed vendor references, with basic non-PO validation and no full Procurement lifecycle.

## 5. Business value

Turn verified service costs into accurate payable obligations without retyping shipment, vendor, cost or supporting evidence.

## 6. Source requirement

FIN-AP-001..004; FIN-TAX; OPS-CST-001..004; Phase 6 PRC-POI boundary. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..195 and FIN-199; verified Operations actual-cost/source manifest. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-201..218 and Step 11 advanced matching. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add vendor-bill root/version/number, vendor/resource and job/shipment/actual-cost references, bill/tax lines, currency/rate/term snapshots, totals, canonical lifecycle, basic variance/match result and AP/journal posting links.

## 14. API impact

Shared REST/GraphQL prepare-from-cost, capture/import, validate/basic-match, draft/update, submit/approve, post and read operations with idempotency. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

AP bill queue/editor/detail with inherited cost lines, scanned supporting file, duplicate/variance warnings, tax/total preview, approval and source/posting timeline. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict vendor tax/bank/cost fields; private files require malware scan and signed URL; AI/OCR extraction requires human review before submit/post. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/vendor/reference/date/status/job/currency; async OCR/document processing and cursor pagination. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source cost/version, bill identity/file, extraction provenance/human edits, line mapping, variance, tax/rate, approvals and posting. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy bills to vendor/source/AP and reconcile posted imports; ambiguous sources remain blocked. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect actual-cost, vendor-reference, file/OCR and AP contracts.
- Model bill/version/line/source/basic-match and duplicate constraints.
- Implement capture/import/OCR-review, services, APIs and AP UX.
- Integrate approval, AP/subledger/journal posting and Step 11 handoff.
- Verify accuracy, security, reconciliation and E2E evidence.

## 21. Main flow

AP captures or imports a bill, system links verified vendor and actual-cost evidence, human reviews extracted data, validates basic variance/tax, approves and posts once to AP and journal.

## 22. Alternative flow

Create a bill from approved direct cost without PO, split across jobs under policy, or return a draft for clarification.

## 23. Exception flow

Block duplicate vendor reference/file hash, missing/ambiguous vendor/source, material variance without approval, tax/currency mismatch, malicious file, locked period or unauthorized posting. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Phase 4 supports basic source/cost matching; PO/contract/three-way and vendor lifecycle depth remain Step 11.
- Bill totals equal exact lines plus tax/adjustment under captured versions.
- Normal roles cannot edit posted bills; correction uses governed debit/reversal/adjustment.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Vendor, source job/shipment/cost, bill reference/date/currency/rate/tax and terms are valid.
- Duplicate keys include tenant/vendor/reference and appropriate source/file evidence.
- Posting preview balances AP, expense/cost/tax accounts and dimensions.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

AP staff capture/review; configured approvers approve variance/bill; Accounting posts; Procurement later sees contract-defined status only; customer users have no access. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Single/multi-job bills, direct costs, duplicate references/files, OCR mismatches, tax fixtures, FX, variance thresholds, locked periods and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Source/basic-match/duplicate/line/tax/total/lifecycle tests.
- File scan/OCR-human-review/API parity/AP/subledger/journal E2E tests.
- RLS/RBAC/field/record isolation, idempotency, concurrency, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Operations actual cost/vendor assignment/documents, tax/currency, AP, reporting and future Step 11 contracts. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Vendor-bill data/contract, Phase 4 versus Step 11 matching boundary, OCR review and duplicate/variance recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel draft, quarantine unsafe file, retry idempotent processing, and correct posted bill only through governed reversal/debit flow with AP/GL reconciliation. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Each bill is unique, exact and source-linked.
- Human-approved capture posts balanced AP/journal effects once.
- No full Procurement/vendor scope is implemented in Phase 4.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-201 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

