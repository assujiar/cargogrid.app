# Prompt 253 — Compliance and Document Expiry

**Prompt ID:** `CG-S11-PRC-004`  
**Package document:** `CG-AABPP-PRC-253`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-253.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-004` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Compliance Control; Capability: Document Requirement, Verification, Expiry and Corrective Action; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement vendor compliance requirements, private document verification, expiry monitoring and eligibility holds.

## 5. Business value

Prevent assignments and commitments to vendors whose required evidence is missing, invalid or expired.

## 6. Source requirement

PRC-ASM-001..004, PRC-VND-001..004, RPD-025 and RPD-032. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..252; verified document/file engine. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-254..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add versioned compliance requirement by vendor category/service/coverage, document metadata/version, verification result, effective/expiry dates, reminder/escalation, waiver, corrective action, legal hold and eligibility impact.

## 14. API impact

Shared REST/GraphQL requirement-read, upload/register, verify/reject/revise, waive-with-approval, renew, reminder status, expiry evaluation and eligibility-read operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Compliance matrix, document/version viewer, expiry calendar/queue, verification/revision and waiver/corrective-action screens; signed access only after scan. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Files remain private and malware-scanned; signed URLs are short-lived and record-scoped; sensitive legal/compliance fields are masked and download audited. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/requirement/document type/status/expiry/service; async scans, reminders and bounded expiry evaluation with cursor queues. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record requirement/config version, upload/scan, verifier/result/reason, issue/expiry/renewal, waiver/approval, file access and eligibility changes. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map only evidenced current documents and dates; unknown verification becomes pending, never approved; preserve legal hold and access history. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define requirement/version/category/service/coverage and eligibility rules.
- Implement private versioned document lifecycle and malware-scan release gate.
- Implement verification, renewal, expiry reminders/escalation, waiver and corrective action.
- Integrate compliance result with sourcing/PO/assignment checks.
- Test file, timing, scope, job retry and downstream holds.

## 21. Main flow

Current requirements are resolved for the vendor, documents are uploaded and scanned, authorized reviewers verify them, reminders precede expiry, and expired blocking evidence places a governed eligibility hold.

## 22. Alternative flow

Request revision, renew before expiry, accept an approved time-bounded waiver, or apply a non-blocking warning requirement.

## 23. Exception flow

Block unsafe file, foreign vendor/document, inconsistent issue/expiry date, duplicate version, stale verification, unapproved waiver or failed reminder job; fail eligibility safely. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- A file is unavailable to another user until RPD-032 scan policy permits it.
- Requirement, blocking effect, reminder schedule and waiver authority are versioned and source-snapshotted.
- Expiry never silently deletes evidence; renewal creates a linked version.
- Legal hold overrides normal deletion; RPD-022 residual absolute-CRUD risk remains disclosed.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate vendor/category/service/coverage, requirement version, file type/size/scan, issue/expiry dates, verifier/waiver authority and current optimistic version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Vendor/intake users upload only requested evidence; procurement/compliance verifies; approvers grant waivers; Operations/Finance receive eligibility result, not unrestricted files. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Required/optional docs, safe/unsafe upload, pending/verified/rejected/expired/renewed, blocking/warning, waiver, legal hold, reminder retry and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Requirement resolution/version and eligibility tests.
- Private file/scan/signed URL/download audit and cross-tenant tests.
- Expiry/reminder/renewal/waiver/corrective-action job tests.
- Sourcing/PO/assignment blocked-by-compliance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform document engine, vendor onboarding/assessment, Operations assignment, Finance vendor reference and retention jobs. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Compliance requirement/document/version/expiry/waiver/eligibility contract and unsafe-file/renewal/reminder/legal-hold runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop release/reminder jobs, default affected eligibility to safe hold, preserve files/versions and restore last compatible rule after reconciliation. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Required documents are private, scanned, verified and versioned.
- Expiry/reminders/renewal and approved waivers work deterministically.
- Blocking compliance prevents downstream commitment/assignment.
- File and tenant isolation tests pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-254 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

