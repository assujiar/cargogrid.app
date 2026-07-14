# Prompt 195 — Tax Baseline

**Prompt ID:** `CG-S9-FIN-006`  
**Package document:** `CG-AABPP-FIN-195`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-195.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-006` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Tax; Epic: Indonesia-First Tax Control; Capability: Configurable Tax Baseline; Feature slice: tax code, PPN/VAT, withholding, effective rule, calculation, evidence and SME activation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement an Indonesia-first configurable tax baseline with versioned rules and explicit SME approval, without inventing legal rates or autonomous legal decisions.

## 5. Business value

Support controlled invoice/bill tax calculation and evidence while keeping legal assumptions visible and updateable.

## 6. Source requirement

FIN-TAX-001..004; RPD-016/021/025/040; ASM-CH-004. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..194 plus current legal/finance/tax SME evidence for activation. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-196..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add tax code/type/jurisdiction, rate/formula basis, recoverable/withholding flags, account mappings, document requirements, effective versions, SME approval evidence and transaction tax snapshots.

## 14. API impact

Shared REST/GraphQL draft, validate, preview, approve-activate, resolve and calculate operations; adapter boundary is case-specific under RPD-038. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Tax configuration workspace with rule version, calculation examples, legal-evidence attachment, effective timeline, approval and explicit unverified/blocked state. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict tax identity/rules/documents and account mappings; private evidence uses malware scan and signed access; AI extraction requires human approval. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Resolve approved tax rules by indexed context/date and batch-calculate lines with bounded deterministic functions. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record rule/evidence/version/formula/account mapping, reviewer, effective date, calculation inputs/outputs and overrides. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import tax codes/rates only with source/effective-date mapping and SME reconciliation; keep unverified entries inactive. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory tax fields, calculations, templates and legal assumptions.
- Define configurable tax rule/version/evidence and posting contracts.
- Implement calculation service, APIs, admin UX and human approval.
- Integrate invoice/bill/journal snapshots and private evidence controls.
- Run SME, calculation, access, migration and regression gates.

## 21. Main flow

Finance Admin drafts a tax rule with current evidence, SME reviews and approves it, the version activates on its effective date, and transactions calculate and snapshot rule/input/output lineage.

## 22. Alternative flow

Apply a documented exemption/withholding path or manual authorized adjustment with reason and approval.

## 23. Exception flow

Keep activation blocked for missing/expired SME evidence, ambiguous jurisdiction, unsupported formula, invalid account map, stale version, missing document or unauthorized override. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- No rate, filing rule or legal conclusion may be guessed by the coding agent.
- Tax calculation is exact-decimal, deterministic, effective-dated and separately visible from subtotal.
- Posted tax is corrected through governed reversal/credit/debit/adjustment, not direct edit.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Rule context and effective window resolve to one approved version.
- Tax base, rate/formula, rounding and amount reconcile per line and document.
- Required legal evidence and account mappings exist before activation.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Tax/Finance Admin drafts; authorized SME/approver activates; Accounting uses resolved rules; other users see only permitted tax fields; customer views are deferred to Step 13. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

PPN/VAT and withholding examples supplied by SME fixtures, exemptions, boundary dates, expired evidence, multiple companies, invalid mappings and cross-tenant attempts. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- SME-fixture calculation, effective resolver, rounding and account-map tests.
- Approval/API parity/RLS/RBAC/file/security/cross-tenant tests.
- Invoice/bill/journal integration, idempotency, concurrency, migration and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Finance configuration, currency, document templates, Commercial pricing, Operations costs and future provider adapters. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Tax rule catalogue, SME evidence register, calculation/posting specification and legal-change response runbook with non-advice disclaimer. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Deactivate an unconsumed invalid rule, restore last approved resolver and reconcile all affected drafts; posted tax correction follows governed financial correction. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Only SME-approved effective rules can calculate posting tax.
- Every amount is reproducible from captured inputs and version.
- Unverified legal behavior remains visibly blocked.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-196 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

