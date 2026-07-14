# Prompt 204 — Posted-Journal Integrity

**Prompt ID:** `CG-S9-FIN-015`  
**Package document:** `CG-AABPP-FIN-204`  
**Version:** `0.10.0`  
**Runtime build log:** `docs/build-log/phase-04/FIN-204.md`

Do not begin until Prompt 190 marks this task `READY`, all variables are resolved, and `PHASE_3_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S9-FIN-015` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 4 — Finance MVP`; package `0.10.0`.

## 3. Workstream

Workstream: Accounting Core; Epic: Posted Record Protection; Capability: Posted-Journal Integrity; Feature slice: normal-role immutability, privileged exception, mutation detection, evidence and disclosure; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Protect posted journals and related financial records from normal-role mutation while explicitly implementing and disclosing the RPD-022 Supreme Admin absolute-CRUD exception.

## 5. Business value

Reduce silent financial corruption and make the accepted administrator risk visible, detectable and reviewable.

## 6. Source requirement

FIN-GL-001..004; INV-005; RPD-022/025/036. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/tests, detect package manager, run feasible baseline gates, state the plan and expected files, and stop on tenant/data/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

FIN-203. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

FIN-205..218. Identify affected schemas, services, REST/GraphQL contracts, jobs/files, reports, integrations, tests, documents and compatibility consumers.

## 11. Allowed files/folders

Use only exact Finance/domain schema, migration, service, UI, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, Step 10/11/13 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–3 contracts and protected decisions.

## 13. Database impact

Add normal-role database protections, posted hashes/evidence snapshots where useful, correction-chain references, privileged-mutation reason/evidence hooks and retention metadata without claiming tamper-proof storage.

## 14. API impact

Remove normal-role update/delete surfaces for posted records; expose read/evidence/correction-start operations; Supreme Admin path follows explicit absolute-CRUD policy, warnings and audit best efforts. REST and GraphQL must share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Posted journal detail is read-only for normal roles with correction actions; Supreme Admin mutation/delete path displays severe irreversible warning, reason/evidence capture and impact preview without implying prevention. Include loading, empty, error, success, permission-denied and degraded states; responsive layout, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Default-deny posted mutation, MFA/re-auth for privileged action, strong alerts and tenant-visible support evidence where applicable; acknowledge Supreme Admin can defeat audit/evidence. Preserve tenant isolation, RLS, RBAC, company/branch/customer scope, field/record policy, MFA for privileged roles, server-only secrets and RPD-022 risk disclosure.

## 17. Performance impact

Integrity checks and alerts must be bounded and indexed; do not hash or reload entire ledgers on interactive paths. Use selective columns, server filtering/sort/search/pagination, query timeouts/budgets, async heavy work and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Capture attempted/blocked mutation, Supreme Admin actor/session/reason/before-after/evidence/alerts when controls are not themselves bypassed; disclose residual unverifiability. Include correlation/idempotency key, actor/context, source/config versions, before/after where allowed, outcome and privileged-access evidence.

## 19. Data migration impact

Apply protections additively and verify every existing posted row/correction chain; unresolved direct-mutation paths are critical blockers. Use additive or expand-and-contract migrations; never edit an applied migration. Any posted-finance migration needs backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Enumerate every posted financial table and mutation path.
- Add normal-role database/service/API/UI protections and negative tests.
- Implement explicit Supreme Admin exception UX, warnings, evidence and alerts.
- Add integrity monitoring and correction-entry navigation.
- Audit bypasses, documentation claims and RPD-022 residual risk.

## 21. Main flow

Normal user opens a posted journal, can inspect evidence and initiate governed reversal/adjustment, but every direct update/delete attempt is denied and logged.

## 22. Alternative flow

Supreme Admin deliberately invokes absolute CRUD after severe warning and reason/evidence capture; system records/alerts only to the extent that authority does not defeat those controls.

## 23. Exception flow

Classify any normal-role bypass, hidden admin path, silent mutation, misleading immutable claim or missing negative test as a critical financial-integrity blocker. Record blocker/error/issue, preserve evidence and provide an exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Posted journals are immutable for every normal role; correction uses reversal/adjustment.
- RPD-022 prevents any tamper-proof, immutable-for-all-roles or non-repudiation claim.
- Evidence hashes/alerts are detective controls, not proof against Supreme Admin authority.
- Persist money with exact decimals, explicit currency and versioned rounding; debit/credit invariants apply where posting is touched.
- Normal-role posted correction uses governed reversal/adjustment; Supreme Admin absolute CRUD under RPD-022 prevents any tamper-proof claim.
- No tenant-specific source fork, silent source re-entry, autonomous AI financial posting, or partial-GA claim.

## 25. Validation rules

- All normal-role update/delete paths fail at the strongest applicable boundary.
- Correction navigation creates a new linked draft rather than editing original lines.
- Product text, docs and reports disclose the exception consistently.
- Reject tenant/company/customer/source/config/version mismatch and stale concurrent mutation.
- Any posting preview must be balanced, period-eligible, idempotency-safe and source-reconcilable.

## 26. Access rules

Normal Finance roles read and correct through workflow; only Supreme Admin has the accepted absolute CRUD exception; support impersonation never silently inherits that authority. Enforce authorization in database/service as applicable, not UI only; list/search/export/report must use the same field and record policy.

## 27. Test data requirement

Posted/draft/reversed journals, all Finance roles, Supreme Admin, impersonation, direct SQL/API/GraphQL/UI attempts, audit deletion and alert-failure scenarios. Include deterministic IDs, exact expected decimals, source/config versions, allowed/denied roles, Tenant A/Tenant B and retry/concurrency fixtures.

## 28. Tests to create/update

- Database/service/API/UI normal-role mutation/delete negative tests.
- Correction-path, MFA/re-auth/warning/reason/alert and tenant-scope tests.
- RPD-022 Supreme Admin capability/disclosure tests without asserting impossible tamper-proof guarantees.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Financial balance, idempotency, period lock, reversal and reconciliation scenarios wherever the task touches posting or balances.

## 29. Regression tests

Invoice/bill/payment/settlement/subledger posted states, audit, support access, retention, reports and documentation. Re-run relevant tenant isolation, finance integrity, API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency and targeted Finance commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Posted-record protection matrix, RPD-022 accepted-risk statement, privileged-action response and correction guide; remove any absolute immutability claim. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable defective mutation surface immediately, restore trusted checkpoint where possible, reconcile affected ledgers and preserve incident evidence; treat uncertain history as an open critical risk. State the last trusted checkpoint, reversible steps, data reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- No normal role can directly alter/delete posted journal records.
- Supreme Admin exception is explicit, warned and best-effort evidenced.
- No artifact claims tamper-proof or universal immutability.
- All mandatory automated and manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, UX states, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/access/financial evidence; balance/idempotency/lock/reversal/reconciliation results as relevant; residual errors/issues/risks; docs updated; rollback/resume; and recommended next task. Update all persistent ledgers before reporting `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release FIN-205 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do so.

