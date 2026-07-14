# Prompt 217 — Finance Documentation and Handoff

**Prompt ID:** `CG-S9-FIN-028`  
**Package document:** `CG-AABPP-FIN-217`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-217.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-028` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Finance Documentation; Epic: Durable Operating Knowledge; Capability: Phase 4 Documentation and Handoff; Feature slice: user/admin/API/accounting/runbook reconciliation and Phase 5/6/8 contracts; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Reconcile all Finance technical, accounting, user, admin, API, support and operating documentation and create a durable handoff for independent closure and later phases.

## 5. Business value

Let a new agent or operator understand, verify, support and safely extend Finance without relying on chat history.

## 6. Source requirement

All Phase 4 artifacts; master documentation/traceability rules; Step 5/6/8 dependency contracts. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-216 evidence-closed with no unresolved in-scope critical/high blocker. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-218; Steps 10, 11 and 13. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

No feature schema change; reconcile schema registry, migration inventory, RLS/field policy, posting/lock/idempotency/correction/reconciliation and retention documentation to actual code.

## 14. API impact

Reconcile REST/GraphQL contracts, errors, idempotency, access/field projections, versioning and compatibility examples; no invented endpoint. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Reconcile routes/navigation/roles/states/accessibility and task guides for Finance Admin/Manager, Accounting, Billing, AR/AP, Treasury and Management. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Document classification, MFA/support, bank/tax/file controls, RPD-022 exception, SME/provider gates and incident/escalation paths accurately. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Publish measured budgets/baselines, high-volume query/export/reconciliation behavior and troubleshooting evidence. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Create a documentation reconciliation manifest with source artifact, code checkpoint, owner/reviewer, mismatch/fix and verification result. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Document clean rebuild/upgrade, backup, posted-data migration/reconciliation and rollback; do not alter data merely to match prose. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory every Phase 4 artifact, code contract and audience document.
- Reconcile schema/API/data-flow/dependency/access/accounting/runbook content to checkpoint.
- Write role guides and critical flow/correction/close/reconciliation procedures.
- Define Step 10/11/13 contracts and explicit deferred boundaries.
- Create closure handoff with evidence index, residual risks and exact resume.

## 21. Main flow

Compare each document to verified implementation/evidence, fix mismatches, obtain owner review and publish a checkpointed handoff usable by Prompt 218.

## 22. Alternative flow

Mark an unsupported feature explicitly deferred with owner/phase/contract; do not fabricate completion or hide a blocked gate.

## 23. Exception flow

Block handoff for undocumented posting behavior, inconsistent formula/state/access rule, missing recovery/reconciliation command, stale contract or misleading immutability/GA claim. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Repository documentation is the durable context; chat is not a dependency.
- Every example uses safe fictitious data and matches actual contract.
- Later-phase handoff preserves shared product codebase and backward compatibility.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- Every changed schema/API/UI/flow/control has matching current documentation.
- Numbers, formulas, states, roles, commands and paths match verified evidence.
- Deferred Step 10/11/13 scope has explicit input/output/ownership contracts.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Document sensitive controls without exposing secrets, real bank/tax/PII data or exploit detail; audience-specific guides respect authority boundaries. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Use sanitized examples for invoice/receipt/bill/settlement/journal/reversal/lock/reconciliation/profitability and role-denied paths. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Documentation link/path/command/example and contract-schema checks where available.
- New-agent dry-run of entry, posting, correction, close, recovery and handoff steps.
- Security review for secret/PII/bank/tax leakage and RPD-022/GA claim accuracy.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Persistent context/status/task/change/error/issues/handoff, all registries/maps/contracts/runbooks and Phase 1–4 documentation. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

User/Admin/API/Support/Accounting/Deployment/Recovery docs, release note, evidence index and Phase 4 handoff are the task output. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Restore previous documentation version only if it was more accurate, preserve mismatch evidence and resume from the exact unresolved artifact. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- A new agent can execute/verify/support Finance from repository docs alone.
- All Finance contracts and controls match the verified checkpoint.
- Prompt 218 receives complete evidence and later phases receive bounded compatible handoffs.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-218 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

