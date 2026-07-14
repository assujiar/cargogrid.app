# Prompt 193 — Fiscal Period

**Prompt ID:** `CG-S9-FIN-004`  
**Package document:** `CG-AABPP-FIN-193`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-193.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-004` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Financial Close; Epic: Accounting Calendar; Capability: Fiscal Period Lifecycle; Feature slice: calendar, open/soft-close/close workflow, close checklist and recognition dependencies; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/company fiscal calendars and governed period lifecycle with explicit open, soft-close, close and reopen readiness states.

## 5. Business value

Ensure all Finance transactions post into a valid controlled period and Finance can manage close dependencies consistently.

## 6. Source requirement

FIN-CLS-001..004; BR-FIN-CLS; FIN-GL. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-191..192. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-194..218, especially FIN-207. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add fiscal year/period calendars, date ranges, canonical lifecycle, close checklist/version, budget/accrual/recognition dependency status, owner, approval and uniqueness/non-overlap constraints.

## 14. API impact

Shared REST/GraphQL calendar generation, validate, read, transition-readiness, submit-close, approve-close and reopen-request operations; hard lock enforcement is FIN-207. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance Manager period workspace with calendar, readiness checklist, unresolved reconciliation/accrual/recognition blockers, approval timeline and explicit locked-state messaging. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Separate prepare, review, close and reopen authorities; enforce tenant/company scope and MFA for privileged Finance approvers. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/company/date/state; resolve posting period in bounded indexed lookup and paginate checklist evidence. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record calendar creation, state transitions, checklist results, approver, reopen request/reason and exact dependency snapshot. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Import existing calendars and states only with overlap validation and transaction-to-period reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inspect date/period usage and close dependencies.
- Model non-overlapping calendar and canonical lifecycle.
- Implement period resolver, readiness service, APIs and management UX.
- Integrate budget/accrual/recognition/reconciliation checklist contracts.
- Test transitions, concurrency, migration and downstream posting behavior.

## 21. Main flow

Finance Manager creates a calendar, opens a period, monitors checklist readiness, submits close, obtains approval and transitions the period without changing existing transaction dates.

## 22. Alternative flow

Use 4-4-5 or custom valid calendar, soft-close for restricted actions, or submit a governed reopen request.

## 23. Exception flow

Block overlap/gap inconsistent with policy, close with unposted/imbalanced items, stale checklist, concurrent transition, unauthorized reopen or any transaction date outside a valid period. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Each transaction date resolves to exactly one eligible fiscal period.
- Close readiness includes configured budget, accrual, revenue/cost recognition and reconciliation dependencies.
- Tenant display labels may vary but canonical lifecycle remains reportable.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Periods do not overlap and cover configured fiscal ranges.
- State transitions follow published workflow and separation of duties.
- Close/reopen requests capture reason, scope, approval and evidence.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance Manager manages lifecycle; Accounting staff view and execute allowed work; close/reopen approvers are separately authorized; other roles see only permitted status. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Calendar-year and non-calendar-year sets, overlaps/gaps, open/soft-close/closed states, unresolved accrual/reconciliation, multiple companies and unauthorized actors. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Period resolver/overlap/lifecycle/checklist unit and database tests.
- API parity, RLS/RBAC/MFA/separation and cross-tenant negative tests.
- Concurrent close, migration, performance, accessibility and downstream-date regression tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Transaction dates, approval, jobs, journals, reports, exports and Operations billing readiness. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Fiscal calendar semantics, close checklist/dependency map and close/reopen operating runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Revert uncommitted lifecycle transition, restore last valid calendar/checklist checkpoint and block posting until transaction-period reconciliation passes. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every supported date resolves deterministically.
- Unsafe close or reopen is blocked with exact reasons.
- Lifecycle and checklist evidence is complete and auditable.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-194 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

