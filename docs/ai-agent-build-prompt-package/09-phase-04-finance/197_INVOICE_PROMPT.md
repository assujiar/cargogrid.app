# Prompt 197 — Invoice

**Prompt ID:** `CG-S9-FIN-008`  
**Package document:** `CG-AABPP-FIN-197`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-197.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-008` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Order to Cash; Epic: Customer Billing; Capability: Customer Invoice; Feature slice: readiness consumption, charge/tax lines, approval, issue/post and document package; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned customer invoices from verified billing-readiness evidence with duplicate prevention, exact charge/tax calculations and source-linked posting.

## 5. Business value

Convert completed logistics work into controlled billable documents quickly and accurately.

## 6. Source requirement

FIN-AR-001..004; FIN-TAX; Operations FIN-181/184 handoff; UX FIN-INV-001. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..196 and one verified versioned `BillingReadinessHandoff`. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-198, FIN-202..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add invoice root/version/number, customer/billing identity snapshot, job/shipment/readiness manifest, charge/tax lines, currency/rate/rounding/payment-term snapshots, totals, canonical state, approval and posting references.

## 14. API impact

Shared REST/GraphQL prepare-from-readiness, validate, draft/update, submit/approve, post/issue, read and document-status operations with idempotency. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Internal invoice queue/editor/detail with inherited source lines, readiness blockers, tax preview, totals, approval timeline, document generation and all complete states. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Financial/customer field and record policy, separation of prepare/approve/post, private malware-scanned invoice/support files and signed URL; no Step 13 customer portal UI. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/customer/status/date/due/readiness/number; cursor paginate and generate document asynchronously. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source manifests, line mapping, calculation inputs/outputs, override reason, approvals, number, issue/post and file access. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy invoices/source links explicitly; posted imports require AR/subledger/GL reconciliation and duplicate controls. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect billing-readiness, customer, charge, tax and template contracts.
- Define invoice root/version/line/source/calculation and lifecycle schemas.
- Implement idempotent preparation, services, REST/GraphQL, editor/detail and async document.
- Integrate approval, AR/subledger/journal posting and notifications.
- Test accuracy, duplicate prevention, access, migration and E2E evidence.

## 21. Main flow

Finance selects an eligible readiness version, system inherits source data, prepares charge/tax lines, validates and approves the draft, then posts/issues once to AR and journal with a private document.

## 22. Alternative flow

Consolidate eligible jobs under configured rules, split billing when approved, revise a draft, or return it for missing evidence.

## 23. Exception flow

Block stale/not-ready evidence, duplicate source billing, customer/tax/currency mismatch, locked period, imbalance, failed document generation, approval conflict or unauthorized issue. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- A readiness item can be billed only according to versioned consolidation/split rules and uniqueness keys.
- Totals equal exact line plus tax/discount calculations under captured versions.
- Normal roles cannot edit a posted invoice; correction uses governed credit/debit/reversal flow.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Customer, billing identity, source jobs/shipments and supporting evidence are complete and authorized.
- Number/date/due date/currency/rate/tax/payment term and totals are valid.
- Posting preview is balanced, period-open and idempotency-safe.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Billing staff prepare; configured approvers approve; authorized Accounting posts/issues; Finance/Management read scoped amounts; customer delivery awaits Step 13 contract/UI. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Single/consolidated/split readiness, taxable/withholding fixtures, multi-currency, partial evidence, duplicate retries, locked period, approval thresholds and cross-customer actors. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Line/tax/total/due/source/duplicate and lifecycle unit/database tests.
- REST/GraphQL, approval, document, AR/subledger/journal and retry E2E tests.
- RLS/RBAC/field/customer isolation, accessibility, performance, migration and regression tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Operations readiness/doc/ePOD, customer/credit, tax/rates, numbering/templates, notifications, AR and reporting. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Invoice contract/data dictionary, readiness mapping, calculation/numbering/posting specification and billing issue/recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel only eligible drafts, retry idempotent generation/posting safely, restore prior template/service checkpoint and correct posted invoice via governed correction—not mutation. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Eligible evidence produces one accurate source-linked invoice.
- Posting creates balanced AR/subledger/journal effects once.
- Files and financial fields obey tenant/customer/access controls.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-198 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

