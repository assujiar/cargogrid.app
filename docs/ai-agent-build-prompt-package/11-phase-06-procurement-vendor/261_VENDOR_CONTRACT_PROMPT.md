# Prompt 261 — Vendor Contract

**Prompt ID:** `CG-S11-PRC-012`  
**Package document:** `CG-AABPP-PRC-261`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-261.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-012` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Commercial Agreement; Capability: Vendor Contract, SLA, Terms and Renewal; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned vendor contracts that govern services, coverage, rates, capacity, SLA, compliance, terms, amendments and renewal.

## 5. Business value

Give Procurement and Operations one effective agreement source for eligibility and performance.

## 6. Source requirement

PRC-POI-001..004 and PRC-VND-001..004. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..260; verified document/e-sign integration controls and Finance terms. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-262..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add contract root/version/number, vendor/entities, service/coverage, rate/pricelist references, capacity, SLA/KPI, tax/payment terms, required compliance, validity/renewal/termination, document/signature metadata, approval and downstream usage snapshots.

## 14. API impact

Shared REST/GraphQL draft/from-template, validate, submit/approve, send/signature-status, activate, amend, renew, suspend/terminate and effective-term read operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Contract queue/builder/detail with terms matrix, linked rates/compliance, version diff, approvals/signatures, effective/expiry/renewal alerts and downstream usage. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Contracts/files/signatures/bank/tax/commercial terms are private and field-scoped; e-sign connectors are case-specific; signed URL and download/access audit apply. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/status/effective/expiry/service/coverage; cursor queues, async document generation/signature polling/reminders and selective term resolution. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record template/config, clause/term/rate/SLA/compliance versions, approvals, signature/provider evidence, activation, amendments, renewal/termination and every effective-term resolution. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import only evidenced signed/effective agreements and versions; unknown clauses/approval/signature remain legacy/pending, never active by inference. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define contract root/version/effective-term and downstream snapshot invariants.
- Implement structured terms, linked documents, approval/signature/activation lifecycle.
- Implement amendment/renewal/termination and expiry reminders.
- Expose authorized effective eligibility/rate/capacity/SLA contract to Operations/Finance.
- Test legal evidence, adapter failure, versions, scope, performance and migration.

## 21. Main flow

Procurement builds a contract from approved vendor/terms/rates, obtains governed approval and signature evidence, activates an effective version, and downstream transactions snapshot applicable terms.

## 22. Alternative flow

Framework agreement plus call-off PO, scheduled future contract, amendment, renewal, suspension or termination with impact review.

## 23. Exception flow

Block missing legal entity/authority, conflicting validity, expired compliance, unsigned/unapproved activation, stale terms, failed e-sign callback, overlapping exclusive contract or termination with active dependency. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Contract root is stable; signed/effective content changes only through linked version/amendment.
- Effective service/coverage/rate/capacity/SLA/compliance/term resolution is deterministic and source-versioned.
- E-sign is case-specific under RPD-038 and never treated as legal validity without required evidence/review.
- Contract activation does not create PO, AP, journal or payment; downstream consumers snapshot applicable terms.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate tenant/legal entities, vendor eligibility, services/coverage, linked rate/capacity/SLA/compliance, effective/expiry dates, approvals/signatures and version conflicts. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement/legal-authorized roles draft; designated approvers/signatories decide; vendor sees own allowed contract; Operations/Finance receive permitted effective terms. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Framework/fixed-term/future, amendment/renewal/termination, overlapping terms, missing signature, adapter retry/replay, expired compliance and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Contract root/version/effective-term/overlap tests.
- Approval/signature/callback/idempotency/amendment/renewal/termination tests.
- Private file/field/RLS/vendor isolation tests.
- Operations eligibility/performance and PO/Finance term-snapshot E2Es.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform templates/files/integrations, rates, PO, vendor compliance, Phase 5 assignment and Finance payment terms. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Contract/version/terms/effective resolution/signature/amendment/renewal/termination contract and adapter/expiry/dependency runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop activation/signature jobs, preserve signed/effective versions, revert only unused drafts/config and reconcile downstream snapshots before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Vendor contracts are versioned, approved, evidenced and effective-dated.
- Amendment/renewal/termination preserve history and dependency checks.
- Operations/PO/Finance consume exact permitted term snapshots.
- Private files and integration recovery pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-262 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

