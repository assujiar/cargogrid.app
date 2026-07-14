# Prompt 208 — Idempotent Posting

**Prompt ID:** `CG-S9-FIN-019`  
**Package document:** `CG-AABPP-FIN-208`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-208.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-019` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: Duplicate-Safe Financial Mutation; Capability: Idempotent Posting; Feature slice: stable key, request fingerprint, claim/result state, retry, collision and recovery; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement one idempotent posting protocol across invoice, bill, receipt allocation, settlement, subledger, journal, reversal and imports.

## 5. Business value

Prevent duplicate financial effects during retry, timeout, worker replay or concurrent requests.

## 6. Source requirement

FIN-GL/AR/AP-001..004; INV-011; master Phase 4 idempotent-posting requirement. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-197..207. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-209..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add tenant/scope/operation/source/idempotency key, canonical request fingerprint, claim/status/result references, attempt/error timestamps and uniqueness/locking constraints.

## 14. API impact

Shared REST/GraphQL mutation semantics accept required idempotency keys, return original compatible result on retry and reject key reuse with a different fingerprint. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Finance action states distinguish processing, safely completed, retryable, ambiguous and collision; no double-click duplicate and no misleading silent retry. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Keys are tenant/actor/scope bound, unguessable where exposed, rate-limited and never authorize access to a result the caller cannot read. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Use indexed atomic claims and bounded retention; avoid long locks and hot global keys; workers use retry/backoff/DLQ semantics. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record key/fingerprint/source, attempts, claim owner, timestamps, result/error/ambiguity, actor and linked posting references. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Backfill stable keys only where source uniqueness is provable; otherwise block replay and document legacy ambiguity. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory every retriable financial mutation and existing key semantics.
- Define canonical key/fingerprint/claim/result protocol.
- Implement shared service/middleware/database constraints and API behavior.
- Integrate UI/jobs/imports/webhooks and ambiguity recovery.
- Run retry, collision, concurrency, access and balance tests.

## 21. Main flow

Caller submits a stable key and request; system atomically claims it, posts once and stores the result; identical retries return the authorized original result.

## 22. Alternative flow

Resume a failed-before-effect attempt, retry a verified safe error, or reconcile an ambiguous external outcome before deciding.

## 23. Exception flow

Reject same key with different fingerprint, cross-tenant/result access, simultaneous conflicting claim, expired unsafe replay or blind retry after unknown external execution. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- One logical financial operation has one stable scoped idempotency key.
- Fingerprint covers every business-significant input and source/config version.
- Ambiguous outcome is reconciled, never blindly replayed.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Key scope/format/source and caller authority are valid.
- Identical fingerprint returns compatible prior result; mismatch is a conflict.
- Stored result references exactly one intended financial effect/correction.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Authorized caller can retrieve only results it could otherwise read; admins cannot use a key as an access bypass; service jobs use least-privilege identities. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Identical retry, changed payload reuse, concurrent claims, worker crash before/after commit, timeout, DLQ replay, cross-tenant key and external ambiguity. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Claim/fingerprint/uniqueness/state/recovery unit and database tests.
- REST/GraphQL/UI/job/import concurrent retry and result-authorization tests.
- Balance/no-duplicate, period-lock, reversal, reconciliation, load and failure-injection tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

All Finance mutation endpoints, job framework, API keys/webhooks, audit and reporting. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Idempotency protocol/key matrix, client/job retry guidance and ambiguous-outcome recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Stop affected consumers, inspect claim/effect/result atomically, complete safe result recording or reconcile and correct through governed flow; never delete keys to force replay. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Retries and concurrency produce at most one intended effect.
- Key collision or ambiguity is explicit and recoverable.
- No idempotency path bypasses access, lock, balance or audit.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-209 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

