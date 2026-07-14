# Prompt 257 — Procurement RFQ

**Prompt ID:** `CG-S11-PRC-008`  
**Package document:** `CG-AABPP-PRC-257`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-257.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-008` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Execution; Epic: Competitive Request; Capability: Vendor RFQ, Invitation and Response; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement source-linked Procurement RFQs with governed vendor invitations, comparable response capture and deadline/clarification control.

## 5. Business value

Collect competitive, traceable vendor offers without fragmented email/chat re-entry.

## 6. Source requirement

PRC-SRC-001..004 and PRC-RTE-001..004. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..256; verified notification/file/job/API primitives. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-258..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add RFQ root/version/number, sourcing/demand source, requirement lines, invitation/vendor scope, issued/deadline/clarification, response/version/attachments, commercial terms, decline/no-response, status and comparison eligibility.

## 14. API impact

Shared REST/GraphQL draft-from-sourcing, revise, invite/issue, clarify, submit/withdraw response, extend/close, read/status/export operations with signed scoped external actions. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

RFQ queue/builder, inherited requirements, invited-vendor panel, clarification timeline, response normalization preview and deadline/status states; optional external response surface only when vendor identity scope is verified. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Invitation tokens are vendor/RFQ/action scoped, expiring and replay-safe; vendors cannot see competitor identities/offers, internal budget or customer-sensitive fields; attachments are private/scanned. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/RFQ/status/owner/deadline/vendor/source; bounded bulk invitations, durable notification jobs, cursor queues and selective response comparison reads. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source/version, requirements, invited vendors/reasons, issue/delivery, clarification, response versions, withdrawals, extensions, actor and job attempts. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map open RFQs/responses only from evidenced sources; preserve emails/files as private source attachments and never infer acceptance or comparability. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define RFQ/requirement/invitation/response/deadline/version invariants.
- Implement sourcing no-reentry mapping and vendor eligibility at issue time.
- Implement internal builder, scoped invitation/response channel and private files.
- Implement clarification, extension, decline/no-response and durable notification/retry.
- Test confidentiality, idempotency, timing, scope, import and comparison handoff.

## 21. Main flow

Procurement converts an approved sourcing shortlist into one versioned RFQ, issues scoped invitations, manages clarifications, receives comparable vendor responses before deadline and closes responses for comparison.

## 22. Alternative flow

Invite additional eligible vendor with reason, extend deadline, accept a revision before close, capture authorized offline response with source evidence, or record decline/no-response.

## 23. Exception flow

Block ineligible vendor, foreign/forged token, leaked competitor data, response after close, stale RFQ version, unsafe file, duplicate submit or failed notification ambiguity; preserve safe retry. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- RFQ inherits sourcing/demand requirements and source version; changed requirements create a governed revision/reissue.
- Each vendor sees only its invitation, allowed demand fields, clarifications and own responses.
- A response is versioned evidence and never automatically selects/commits the vendor.
- Offline/email capture requires actor, source file/message, received time and vendor confirmation where policy requires.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate approved sourcing source, active eligible vendor, requirements/UOM/currency/tax, invitation scope, deadlines/time zone, response completeness/version and file scan. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement drafts/issues/closes; invited vendor users or scoped token submit own response; Sales/Operations view permitted source status; approvers/comparison roles see costs. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Multi-vendor RFQ, revision/reissue, clarification, extension, decline/no-response, offline capture, duplicate submit, expired/forged token, unsafe file and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- RFQ lifecycle/version/source/invitation/idempotency tests.
- Vendor confidentiality/token/replay/field/file isolation tests.
- Deadline/time-zone/clarification/extension/notification retry tests.
- Sourcing→RFQ→comparison browser/API E2E and batch load tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Sourcing, canonical rates, notifications/email, file service, vendor portal identity and cost-field policy. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

RFQ source/requirement/invitation/response/version/deadline/confidentiality contract and notification/offline-capture/reissue runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop new invitations, preserve issued RFQ/responses, cancel only eligible drafts/pending jobs and restore last compatible version after reconciliation. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- RFQs inherit demand and reach only eligible scoped vendors.
- Responses are confidential, versioned and comparable.
- Clarification/deadline/retry/offline evidence is auditable.
- Comparison handoff and isolation gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-258 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

