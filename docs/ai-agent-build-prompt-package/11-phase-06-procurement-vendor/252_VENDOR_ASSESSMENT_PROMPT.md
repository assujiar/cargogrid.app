# Prompt 252 — Vendor Assessment

**Prompt ID:** `CG-S11-PRC-003`  
**Package document:** `CG-AABPP-PRC-252`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-252.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-003` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Qualification and Risk; Capability: Initial, Periodic and Event-Driven Assessment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned initial, periodic and event-driven vendor assessments with explainable scores, findings, approval and reassessment.

## 5. Business value

Select and retain vendors using consistent evidence instead of informal judgment.

## 6. Source requirement

PRC-ASM-001..004 and Product Brief Vendor Assessment capabilities. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251; Platform configuration/approval; verified vendor identity. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-253..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add assessment template/version, scope/type, questions/criteria/weights, evidence, assessor, score/band, findings, corrective actions, approval, expiry/reassessment and vendor eligibility outcome.

## 14. API impact

Shared REST/GraphQL template-read, create/start, assign, answer/evidence, calculate, submit, review/approve, corrective-action, close and reassess operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Assessment queue, guided questionnaire, evidence panel, score explanation, findings/corrective action and reassessment schedule with all accessible states. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict financial, safety and compliance evidence by purpose/field; separate assessor/approver where configured; vendor users may supply evidence but never approve themselves. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/template/type/status/assessor/expiry/risk band; cursor queues and async score/reassessment batches with bounded evidence metadata. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record template/config version, answers/evidence, score components, manual adjustment reason, findings, approvals, expiry and eligibility impact. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Do not invent historical scores or approvals; import only evidenced assessments and mark unknowns pending reassessment. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define assessment types, criteria/weight/version and eligibility effects.
- Implement assessment/answer/evidence/findings/corrective-action lifecycle.
- Implement exact explainable scoring and maker-checker approval.
- Schedule expiry/reassessment and vendor-status impact without silent changes.
- Test calculation, concurrency, access, migration and eligibility integration.

## 21. Main flow

An authorized assessor opens the current template for a vendor, collects evidence, calculates an explainable score, resolves findings, submits to a separate reviewer and schedules reassessment.

## 22. Alternative flow

Run simplified category-specific, periodic, incident-triggered, financial, operational or safety assessment; request corrective action before approval.

## 23. Exception flow

Block stale template, incomplete mandatory criteria, unsafe evidence, self-approval, conflicting active assessment, unexplained score override or expired result. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Assessment outcome is versioned evidence, not an untraceable editable vendor field.
- Score weights, thresholds, bands, expiry and eligibility effects are configured and snapshotted.
- Manual score adjustment requires reason, permission and before/after evidence.
- No AI may autonomously approve, reject, blacklist or legally qualify a vendor.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate active vendor/template, required criteria/evidence, exact weight totals/rounding, assessor/approver eligibility, effective dates and current optimistic version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement assessors manage assigned assessments; compliance/finance/safety roles see purpose-bound sections; approvers decide; vendor users only answer allowed requests. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Initial/periodic/incident assessments, category templates, pass/conditional/fail, corrective action, score override, expiry/reassessment, self-approval denial and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Template/version/weight/rounding/score/band tests.
- Lifecycle/finding/corrective-action/approval/expiry/reassessment tests.
- RLS/RBAC/field/evidence isolation and concurrency tests.
- Vendor eligibility and performance downstream contract E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Vendor onboarding, compliance, sourcing eligibility, assignment, performance and private document service. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Assessment template/scoring/band/finding/corrective-action/expiry contract and reassessment/escalation runbook. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Pause new assessments, preserve decided evidence, restore compatible template version and recalculate only through governed versioned reassessment. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Initial and periodic assessments are complete and explainable.
- Findings/corrective actions and approval separation are enforced.
- Expiry triggers governed reassessment/eligibility behavior.
- Isolation and downstream eligibility tests pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-253 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

