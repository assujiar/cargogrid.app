# Prompt 192 — Chart of Accounts

**Prompt ID:** `CG-S9-FIN-003`  
**Package document:** `CG-AABPP-FIN-192`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-192.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-003` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: General Ledger Foundation; Epic: Account Master; Capability: Canonical Chart of Accounts; Feature slice: hierarchy, type, normal balance, posting eligibility, effective state and dimensions; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a tenant/company-aware chart of accounts with stable canonical account semantics, hierarchy validation and governed activation/deactivation.

## 5. Business value

Provide the controlled account master required for balanced posting, statements and reconciliation.

## 6. Source requirement

FIN-GL-001..004; BR-FIN-GL; CPD-019; INV-007. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191 effective Finance configuration. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-193..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add account root/code/name/type/subtype/normal-balance, parent hierarchy, posting/control flag, currency/dimension rules, effective state and referenced-record protection with tenant-aware keys.

## 14. API impact

Shared REST/GraphQL create, validate, list/tree, read, amend-draft, activate, deactivate and dependency-impact operations. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Accessible COA tree/table/editor with server search, filters, hierarchy navigation, validation, dependency view, audit and protected in-use state. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict create/activate/deactivate to authorized Finance Admin; apply company/branch scope and field masking; never expose balances through COA metadata endpoints. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/code/type/parent/state; bound hierarchy depth and use recursive query budgets without browser-side full-tree loading. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record code/hierarchy/type/normal-balance/posting-state changes, approval, actor, reason and impacted mappings. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map existing accounts explicitly with reconciliation and duplicate/code conflict report; preserve every source identifier. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory existing account masters and posting references.
- Define canonical types, normal balances, hierarchy and unique constraints.
- Implement services, REST/GraphQL, tree/list/editor and lifecycle controls.
- Protect referenced accounts and validate configuration dependencies.
- Create accounting, isolation, migration and performance evidence.

## 21. Main flow

Finance Admin creates or imports a draft account, validates code/type/hierarchy/dimensions, approves activation and makes it eligible for configured postings.

## 22. Alternative flow

Create a child account, schedule future activation, or deactivate an unused account after dependency review.

## 23. Exception flow

Reject duplicate code, hierarchy cycle, invalid parent/type, incompatible normal balance, cross-company reference or deactivation of an account required by active/posted records. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- An account code is unique within its configured tenant/company scope and effective lifecycle.
- Control accounts cannot accept manual posting unless an explicit approved rule permits it.
- Referenced accounts are never hard-deleted by normal roles.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Hierarchy is acyclic and depth bounded.
- Account type, normal balance, currency and dimension rules are compatible.
- Every active posting account is leaf/postable under published policy.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance Admin maintains; Accounting users read authorized accounts; posting services receive only eligible scoped projections; customer roles cannot query the COA. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Multi-level charts, duplicate codes, cycles, control/posting accounts, multiple companies, inactive referenced accounts and cross-tenant attempts. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Hierarchy/type/normal-balance and dependency constraint tests.
- CRUD/lifecycle REST/GraphQL, RLS/RBAC and cross-tenant tests.
- Import mapping, concurrent code creation, tree performance and accessible keyboard navigation.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Master-data/configuration, posting-map, report/export, audit and tenant isolation. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

COA data dictionary, canonical account taxonomy, import mapping, lifecycle and dependency runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable new activation, reverse unused additive records, restore prior account-policy resolver and reconcile all mappings; never remove a referenced account. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Valid accounts are searchable and usable only within authorized scope.
- Cycles, duplicates and unsafe deactivation are blocked.
- Every account mutation has complete audit and dependency evidence.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-193 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

