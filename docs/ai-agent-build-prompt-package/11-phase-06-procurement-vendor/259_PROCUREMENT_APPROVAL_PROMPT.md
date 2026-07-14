# Prompt 259 — Procurement Approval

**Prompt ID:** `CG-S11-PRC-010`  
**Package document:** `CG-AABPP-PRC-259`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-259.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-010` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Governance; Epic: Commitment Authority; Capability: Vendor, Rate, Selection, PO, Contract and Exception Approval; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Instantiate one configurable approval contract across high-risk Procurement/Vendor decisions without duplicating the Platform approval engine.

## 5. Business value

Enforce authority, separation of duties and SLA consistently before vendor activation or commercial commitment.

## 6. Source requirement

PRC-VND/ASM/RTE/SRC/POI-003 and the source approval catalogue. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..258; verified Platform approval/config/organization contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-260..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add only Procurement approval-policy bindings, context snapshots, threshold/dimension inputs, required approver groups, task references, delegation/escalation and decision linkage to canonical records.

## 14. API impact

Shared REST/GraphQL submit/withdraw-eligible, task-read, approve/reject/request-revision, delegate, escalate and decision-history operations through the canonical approval service. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Unified procurement approval inbox/detail with source snapshot, cost/variance/risk/compliance evidence, separation warnings, SLA, delegation and responsive accessible decision actions. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Server/database enforce approver eligibility, organization/value/branch scope, field masking, MFA for privileged financial/credential approvals, no requester/self-approval where prohibited and signed decision evidence. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/domain/entity/status/approver/SLA; bounded inbox cursor queries, durable reminders/escalations and no global realtime subscription. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record policy/config version, source snapshot/digest, requester, approver eligibility, delegation, decision/reason, MFA, SLA/escalation, override and downstream release. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map open approval tasks to canonical engine only with source/version/assignee evidence; never mark historical decisions approved by inference. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Map every Phase 6 decision to existing approval-engine policy bindings.
- Define thresholds, dimensions, separation, delegation, SLA/escalation and stale-source invalidation.
- Implement shared decision context/APIs and accessible approval inbox/detail.
- Integrate release gates for activation/rate/selection/PO/contract/match/exception.
- Test bypass, self-approval, stale evidence, concurrency, field scope and reminders.

## 21. Main flow

A source record is submitted with immutable decision context, engine resolves eligible approvers, reviewers inspect permitted evidence, decide with reason, and the owning domain releases the next transition idempotently.

## 22. Alternative flow

Parallel/conditional approval, request revision, delegate within authority, escalate after SLA or approve a time-bounded exception/override.

## 23. Exception flow

Block no eligible approver, self-approval, expired delegation, stale/changed source, hidden mandatory evidence, failed MFA, duplicate decision, timeout or release mismatch. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Reuse the Platform approval engine; Procurement stores bindings/context, not a second workflow engine.
- Decision context snapshots source/config/value/risk/compliance/rate versions and invalidates on material change.
- Approval does not itself post Finance, execute payment or change Operations status beyond authorized handoff.
- Rejection/revision/delegation/escalation/override require reason and complete audit.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate active policy/version, entity state, required evidence, value/currency/branch dimensions, approver/delegation/separation/MFA and optimistic source version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Requesters submit/withdraw eligible records; engine-selected approvers decide; admins configure published policies but cannot silently rewrite active decision context. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Sequential/parallel/conditional/value/risk approvals, self-approval denial, delegation/expiry, SLA escalation, stale source, MFA failure, duplicate click and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Policy binding/context/threshold/approver-resolution tests.
- Self/bypass/delegation/SLA/MFA/stale/concurrency tests.
- RLS/RBAC/field masking and REST/GraphQL parity tests.
- Activation/rate/selection/PO/contract/match release-gate E2Es.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform workflow/approval/notifications, vendor lifecycle, rate publish, sourcing selection, Finance approvals and audit. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Procurement approval binding/context/threshold/separation/delegation/SLA/staleness contract and no-approver/revision/escalation runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Pause new submissions/releases, preserve decisions/tasks, restore last policy binding and re-evaluate only pending tasks with governed migration. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- All high-risk Phase 6 decisions use one canonical approval engine.
- Separation, authority, MFA, delegation and SLA are enforced.
- Material source changes invalidate stale decisions.
- No approval bypass or cross-scope leakage remains.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-260 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

