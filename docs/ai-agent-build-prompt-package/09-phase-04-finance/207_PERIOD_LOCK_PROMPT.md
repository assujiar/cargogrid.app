# Prompt 207 — Period Lock

**Prompt ID:** `CG-S9-FIN-018`  
**Package document:** `CG-AABPP-FIN-207`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-207.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-018` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Financial Close; Epic: Posting Cutoff Control; Capability: Period Lock and Governed Reopen; Feature slice: scope/action lock, database enforcement, close evidence, reopen approval and re-lock; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement company/ledger/module-aware period locks enforced at posting boundaries with governed reopen and re-lock.

## 5. Business value

Prevent backdated or unauthorized financial changes after close while supporting controlled correction.

## 6. Source requirement

FIN-CLS-001..004; FIN-GL; master Phase 4 period-lock requirement. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-193 and FIN-203..206. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-208..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add period-lock scope/type/effective state, action matrix, close evidence, approval, reopen window/reason and constraints/functions checked atomically by financial mutations.

## 14. API impact

Shared REST/GraphQL preview-lock-impact, lock, reopen-request/approve, re-lock, read and allowed-action operations; every posting service calls one authoritative guard. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance close/lock console with scope, unresolved blockers, affected actions, approval timeline, reopen warning/window and real-time allowed-state explanation. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Separate prepare/approve lock and reopen authority; MFA for privileged reopen; database/service enforcement cannot be bypassed by normal APIs/jobs/imports. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Resolve lock by indexed tenant/company/ledger/module/period/action and cache only safely with invalidation; avoid global scans. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record scope/action, checklist hash, actor/approver, lock/reopen/re-lock time, reason/evidence, affected transactions and blocked attempts. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Create locks only after existing transactions map to valid periods and reconciliation passes; never infer closed state from dates alone. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Enumerate every financial mutation/import/job and period check.
- Model scoped lock/action and reopen lifecycle.
- Implement authoritative guard, APIs and close UX.
- Integrate all posting/correction/import paths and monitoring.
- Run bypass, concurrency, migration, performance and reconciliation tests.

## 21. Main flow

Finance completes readiness, previews affected actions, obtains approval and locks a scope; every later normal mutation is blocked until a bounded approved reopen, after which it re-locks with reconciliation.

## 22. Alternative flow

Soft-lock selected actions/modules, reopen only an exact period/scope/window, or process correction in a current open period.

## 23. Exception flow

Block lock with unresolved mandatory checklist, unauthorized/broad reopen, stale state, active posting race, missing reason/evidence or any mutation path that bypasses the guard. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Period lock is authoritative in database/service boundary, never UI-only.
- Reopen is minimum scope/time, approved, reasoned, audited and followed by re-lock/reconciliation.
- RPD-022 exception is disclosed; no absolute prevention claim applies to Supreme Admin.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Scope resolves deterministically and no conflicting lock state exists.
- All mandatory close/reconciliation evidence is current.
- Every mutation declares date/period/action and receives an authoritative decision.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Finance Manager prepares; independent close/reopen approver authorizes; Accounting sees lock reasons; jobs/imports use scoped service paths; non-Finance cannot alter locks. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Open/soft/hard locks, company/module/action scopes, boundary dates/time zones, concurrent posting/lock, reopen windows, imports/jobs and cross-tenant users. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Lock resolver/action matrix/database guard and transition tests.
- All invoice/bill/payment/journal/correction/import bypass-negative tests.
- RLS/RBAC/MFA/separation, concurrency, migration, performance, audit and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Fiscal period, all posting services, jobs/imports, reports, correction and close operations. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Period-lock scope/action matrix, close/reopen/re-lock runbook and RPD-022 limitation. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Abort uncommitted lock transition, restore prior valid lock state and reconcile any race-window transactions before resume; never silently reopen. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every normal financial mutation obeys the same lock guard.
- Reopen is bounded, approved and fully evidenced.
- Concurrent lock/post cannot create silent closed-period entries.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-208 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

