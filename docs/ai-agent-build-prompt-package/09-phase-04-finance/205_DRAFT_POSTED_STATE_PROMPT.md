# Prompt 205 — Draft versus Posted State

**Prompt ID:** `CG-S9-FIN-016`  
**Package document:** `CG-AABPP-FIN-205`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-205.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-016` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: Financial Lifecycle; Capability: Draft-versus-Posted State Control; Feature slice: canonical lifecycle, editability matrix, approval/post transition and protected final state; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement one canonical draft/review/approved/posted/corrected lifecycle and editability matrix across invoices, bills, receipts, settlements, subledgers and journals.

## 5. Business value

Prevent ambiguous document state and ensure every financial mutation follows the correct authority and accounting effect.

## 6. Source requirement

FIN-GL/AR/AP-001..004; master Phase 4 draft-versus-posted requirement. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-196..204. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-206..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add/normalize canonical financial state, version/concurrency token, transition log and posted/correction references with database constraints preventing illegal normal-role transitions.

## 14. API impact

Shared lifecycle/transition policy used by REST/GraphQL and all source services; expose allowed-actions and validation reasons consistently. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Every Finance detail shows canonical state, allowed actions, pending approver, lock/source evidence and correction history; disabled actions explain why. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Action/status/value-aware permission, separation of duties and no client-only transition checks; RPD-022 exception remains explicit. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Resolve allowed actions from versioned workflow and indexed state/scope without per-row N+1 checks. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record state before/after, version, actor, approval, validation snapshot, posting/correction link and rejected attempts. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy states to canonical values with exception report; never mark a record posted without reconciled posting evidence. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory all Finance states and mutation paths.
- Define canonical lifecycle and per-field/action editability matrix.
- Implement shared transition policy across schema/services/APIs/UI.
- Migrate mappings and link posting/correction evidence.
- Run lifecycle, concurrency, access and cross-domain regressions.

## 21. Main flow

User edits a draft, submits it, approval validates the unchanged version, authorized posting moves it atomically to posted and later corrections create linked records.

## 22. Alternative flow

Reject/revise a submitted record, cancel an eligible draft, or resume a failed posting without duplicating effects.

## 23. Exception flow

Block illegal transition, stale edit/approval, posted direct mutation, missing posting evidence, cross-domain state mismatch or role/status policy bypass. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Canonical states are stable even when tenant display labels vary.
- Field editability is explicit by state and action; posted normal-role fields are read-only.
- Posting state changes atomically with the intended accounting effect.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Transition exists in published workflow and actor/action/scope are authorized.
- Record version and approval snapshot are current.
- Posted/corrected states have valid journal/source/correction links.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Prepare/review/approve/post/correct actions are separately configurable within platform minimums; APIs, bulk actions, exports and UI use identical state policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Every canonical state, stale versions, reject/revise/cancel, failed/retried post, linked correction, all Finance roles, Supreme Admin and cross-tenant attempts. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Lifecycle/editability/atomic-transition/concurrency tests for every Finance record type.
- REST/GraphQL/allowed-actions/UI/access/audit consistency tests.
- Posted mutation negative, retry/idempotency, migration and accessibility regressions.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

All Finance capabilities, workflow/approval/config engines, notification, reports and public contracts. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Canonical Finance lifecycle registry, field/action editability matrix and failed-transition/recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Restore last valid pre-transition version only when no posting effect occurred; otherwise complete or reverse atomically and reconcile before resume. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every financial record has one canonical state and deterministic allowed actions.
- Posting state and accounting effect cannot diverge silently.
- Illegal/stale/unauthorized transitions are blocked and evidenced.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-206 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

