# Prompt 216 — Finance Integrity and Security Hardening

**Prompt ID:** `CG-S9-FIN-027`  
**Package document:** `CG-AABPP-FIN-216`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-216.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-027` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Hardening; Epic: Evidence-Ranked Blocker Repair; Capability: Finance Integrity, Security and Performance Hardening; Feature slice: verification findings, root cause, bounded repair, abuse/failure tests and risk reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Repair every in-scope critical/high Finance integrity, tenant, access, security, performance and reliability finding from Prompt 215 without broad refactoring.

## 5. Business value

Ensure Phase 4 closes only after evidence-ranked risks are fixed or formally blocked with accountable ownership.

## 6. Source requirement

FIN-215 findings; all Finance guardrails; RPD-016/021/022/023/025/032/033/036/038/039. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-215 completed with classified findings. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-217..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Apply only additive/bounded corrections to constraints, policies, indexes, posting/lock/idempotency/reconciliation paths; posted-data repair requires backup and exact reconciliation.

## 14. API impact

Repair shared-service and REST/GraphQL parity, authorization, idempotency, rate/error/compatibility defects with regression contracts. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Repair dead/unsafe actions, state/accessibility/error disclosure and privileged warnings without hiding unresolved Finance failure. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Prioritize tenant/customer/field leakage, normal-role posted mutation, bank/tax/file exposure, support/MFA bypass and secret/log issues; RPD-022 accepted exception cannot be misrepresented as fixed. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Fix measured posting/list/report/reconciliation/import/export regressions with query-plan and before/after evidence, not speculative architecture churn. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Link each finding to root cause, change, tests, before/after evidence, residual risk, owner and closure decision. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Every data repair is rehearsed, idempotent, backup-backed and reconciled; never edit applied migrations or delete evidence. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Triage Prompt 215 findings by severity and root cause.
- Create/execute one bounded repair task per coherent cause.
- Add regression/abuse/failure tests before closing findings.
- Rerun affected FINTEST, E2E, reconciliation and non-regression suites.
- Reconcile residual RPD-022/legal/provider risks and handoff readiness.

## 21. Main flow

Take highest in-scope blocker, reproduce it, implement bounded root-cause repair, prove regression/financial reconciliation and close only with evidence.

## 22. Alternative flow

If repair requires new authority, source decision or later-phase work, keep Phase 4 blocked and record exact owner/dependency rather than weaken controls.

## 23. Exception flow

Stop on evidence loss, uncertain posted-data history, migration mismatch, new imbalance/leak/bypass, broad-scope pressure or inability to reproduce a critical finding. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- No finding closes from code review alone; impacted automated and reconciliation tests must pass.
- Do not disable checks, reduce precision, widen access or patch balances to make tests green.
- RPD-022 and SME/provider limitations remain explicit accepted/external gates.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Root cause and affected surface are proven.
- Repair preserves compatibility and all financial invariants.
- Before/after evidence and residual risk are complete.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Hardening uses least privilege and isolated authorized environments; privileged tests and data repairs require explicit approval and audit. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Exact failing fixtures plus neighboring boundaries, retry/concurrency, Tenant A/B, all Finance roles, malicious/denied inputs and target volume. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Finding-specific regression and negative/abuse/failure-injection tests.
- Impacted balance/idempotency/lock/reversal/reconciliation and E2E suites.
- Full REST/GraphQL/access/migration/performance smoke after final repair.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

All Phase 1–4 critical flows and controls touched by repairs; compare against FIN-215 baseline. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Finding/repair ledger, threat/risk records, schema/API/change/regression/traceability updates and residual-risk handoff. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Revert only bounded unapplied change, restore trusted database checkpoint where authorized, reconcile effects and reopen finding with exact resume evidence. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every in-scope critical/high finding is evidence-closed or keeps Phase 4 blocked.
- Repairs introduce no new imbalance, leak, bypass or compatibility regression.
- RPD-022 and legal/provider residual risks remain accurate.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-217 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

