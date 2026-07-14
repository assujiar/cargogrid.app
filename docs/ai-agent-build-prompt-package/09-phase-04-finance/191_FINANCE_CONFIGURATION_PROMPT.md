# Prompt 191 — Finance Configuration

**Prompt ID:** `CG-S9-FIN-002`  
**Package document:** `CG-AABPP-FIN-191`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-191.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-002` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Foundation; Epic: Governed Accounting Policy; Capability: Versioned Finance Configuration; Feature slice: accounting dimensions, numbering, posting, rounding, budget/accrual/recognition and close-policy baseline; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/company-scoped Finance configuration that versions accounting dimensions, document numbering, posting maps, rounding, budget controls, accrual/revenue-cost recognition policies and close dependencies without hardcoded tenant logic.

## 5. Business value

Give Finance one publishable policy source so every invoice, bill, payment and journal uses the same effective rules.

## 6. Source requirement

FIN-GL-002, FIN-TAX-002, FIN-CLS-001..004; PLT-CFG-001..004; RPD-016/022/040. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-190; verified Platform configuration/approval/numbering engines and `PHASE_3_VERIFIED`. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-192..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add versioned tenant/company finance-policy sets, dimensions, posting-map references, numbering/rounding rules, budget-control mode, accrual/recognition method references, effective dates, publish/rollback state and dependency graph.

## 14. API impact

Shared REST/GraphQL draft, validate, preview-impact, publish, rollback and resolve-effective-policy operations. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance Admin configuration workspace with tabs for dimensions, numbering, posting, rounding, budget/accrual/recognition and close rules; diff, preview, dependency blockers and publish timeline. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Only Finance Admin/approved authority may publish; mask sensitive bank/tax defaults and prevent lower scope from weakening platform controls. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Cache effective immutable policy versions by tenant/company/date; bound dependency traversal and invalidate safely after publish. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record field diffs, author/reviewer/publisher, effective window, dependency result, reason, rollback and affected transaction classes. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Backfill a single explicit draft only from proven existing settings; never infer or auto-publish accounting policy. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect existing configuration primitives and finance dependencies.
- Design canonical policy/version/dimension/posting-map contracts and constraints.
- Implement shared resolver plus REST/GraphQL parity and admin UX.
- Add publish/rollback/dependency and concurrency controls.
- Verify downstream snapshots, access and complete evidence.

## 21. Main flow

Admin drafts a policy version, configures rules, validates dependencies, previews impact, obtains required approval and publishes an effective immutable version used by later transactions.

## 22. Alternative flow

Clone a prior version, schedule a future effective date, or roll back unpublished configuration while retaining audit lineage.

## 23. Exception flow

Block overlapping effective windows, missing account/dimension mappings, unsafe rounding, stale version, unauthorized publish, cyclic dependency or rules that would invalidate posted records. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Published versions are never silently edited; supersede with a new version.
- Budget/accrual/recognition options expose only implemented, SME-approved semantics; unsupported modes remain blocked.
- Tenant labels may vary but canonical accounting states and dimensions remain stable.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Unique policy version/effective window per tenant/company and configuration class.
- Every posting map resolves to active compatible accounts and dimensions.
- Rounding precision/order is explicit and exact-decimal safe.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance Admin drafts; configured approvers publish; Finance users read effective policy needed for their actions; margin/bank/tax fields follow field policy; customer users have no configuration access. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Two tenants, multiple companies/branches/cost centers, current/future versions, conflicting windows, missing/deactivated accounts, budget/accrual/recognition variants and unauthorized users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Version/effective-date resolver, publish/rollback and dependency unit/integration tests.
- REST/GraphQL parity, RLS/RBAC/field-policy and cross-tenant negative tests.
- Concurrency, stale version, performance, accessibility and downstream snapshot tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Platform configuration, approval, numbering, audit, Commercial money and Operations cost/readiness contracts. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Finance configuration catalogue, policy semantics, posting-map/dimension registry and administrator publish/rollback runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable unpublished UI/API, roll back additive migration only if unused, restore prior published resolver checkpoint and never rewrite transactions that captured a policy version. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- One effective version resolves deterministically for every supported context.
- Invalid or unsafe configuration cannot publish.
- Later Finance records snapshot exact policy/version lineage.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-192 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

