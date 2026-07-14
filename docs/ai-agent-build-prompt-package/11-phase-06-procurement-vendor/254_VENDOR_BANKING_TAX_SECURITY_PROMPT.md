# Prompt 254 — Vendor Banking and Tax Security

**Prompt ID:** `CG-S11-PRC-005`  
**Package document:** `CG-AABPP-PRC-254`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-254.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-005` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Sensitive Financial Master; Capability: Bank, Tax and Payment-Term Verification; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement purpose-bound vendor banking, tax and payment-term data with masking, maker-checker change control and Finance-compatible verification.

## 5. Business value

Reduce payment fraud, tax errors and unauthorized exposure of sensitive vendor data.

## 6. Source requirement

PRC-VND-001..004, PRC-ASM-001..004, RPD-016, RPD-023, RPD-025 and RPD-038. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..253; verified Finance tax/payment-term and privileged-access contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-255..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add encrypted/masked bank-account versions, ownership/verification status, tax identity hashes/versions, payment-term references, effective dates, change request, dual approval, hold and downstream usage snapshot.

## 14. API impact

Shared REST/GraphQL masked read, propose-change, verify, approve/reject, activate/deactivate and audit-status operations; never return full secrets in lists/exports/logs. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Masked bank/tax/payment-term detail, add/change wizard, re-auth/MFA confirmation, maker-checker queue, verification evidence and downstream hold warning. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Strict field/record policy, encryption/key handling, purpose-bound reveal, MFA for privileged approvers/credential managers, separation of duties, no plaintext export/log/cache and monitored sensitive access. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/status/effective date and deterministic protected hashes for duplicate checks; never index plaintext account/tax values; bounded verification jobs. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record masked fingerprint, source/evidence, maker/checker, re-auth/MFA result, before/after protected reference, effective date, hold and every reveal/export denial. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Encrypt and classify existing values, validate key rotation/backup, default unverified/ambiguous data to hold and preserve Finance references without plaintext copies. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile Finance tax/payment-term and vendor-master ownership.
- Define classification, encryption/masking/hash, verification and change lifecycle.
- Implement maker-checker/MFA services/APIs and accessible masked UI.
- Integrate effective verified snapshots with PO/invoice-match/Finance without payment mutation.
- Run key, leakage, concurrency, migration and fraud-path tests.

## 21. Main flow

A maker proposes protected bank/tax/payment-term data, service validates format and evidence, an independent privileged checker reauthenticates/approves, and the effective verified version becomes eligible for downstream reference.

## 22. Alternative flow

Maintain multiple approved accounts by currency/purpose, schedule an effective change, reject/revise evidence, or place the vendor on payment hold.

## 23. Exception flow

Block plaintext leakage, duplicate/foreign account, unsupported tax assumption, self-approval, failed MFA, stale version, unavailable case-specific verifier or downstream conflict. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Bank/tax values are masked by default and never included in generic export, search, logs, analytics or notifications.
- No bank change becomes effective without maker-checker, reason/evidence and privileged current authentication.
- RPD-016 requires dated Indonesia-first SME validation; do not guess statutory rules.
- Verification/payment/e-sign adapters are case-specific under RPD-038; this capability cannot execute settlement or cash movement.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate vendor/legal owner, supported currency/country format, tax/payment-term reference, uniqueness hash, evidence, maker/checker separation, MFA and effective version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement proposes; authorized Finance/compliance checks; Operations sees eligibility only; vendor user sees own masked values and may request change; support access is purpose/time bound. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Verified/unverified/multiple currency accounts, duplicate hash, tax format variants, maker/checker roles, failed MFA, scheduled change, payment hold, key rotation and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Mask/encrypt/hash/key rotation and no-plaintext tests.
- Maker-checker/MFA/re-auth/effective-version/concurrency tests.
- RLS/RBAC/field/export/log/cache/support isolation tests.
- PO/invoice-match/Finance reference compatibility without payment mutation.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Finance tax/payment term, vendor bill/AP/settlement, vendor onboarding, export/search/audit and support access. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Sensitive vendor master classification, encryption/masking, verification/change/hold and Finance handoff contracts plus fraud/key/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Freeze sensitive changes/reveals, keep payment hold, restore last verified version/key path and reconcile every downstream reference before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Vendor bank/tax/payment-term data is masked and purpose-bound.
- Maker-checker/MFA and effective versioning prevent unauthorized change.
- No plaintext leaks through APIs/UI/export/log/cache.
- Finance compatibility works without Procurement posting or paying.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-255 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

