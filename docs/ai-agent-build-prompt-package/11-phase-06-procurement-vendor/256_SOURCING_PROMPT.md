# Prompt 256 — Sourcing

**Prompt ID:** `CG-S11-PRC-007`  
**Package document:** `CG-AABPP-PRC-256`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-256.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-007` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Execution; Epic: Vendor Discovery and Selection; Capability: Sourcing Request and Candidate Longlist; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement source-linked sourcing requests, vendor discovery, candidate eligibility and governed selection preparation.

## 5. Business value

Turn operational/commercial demand into an auditable vendor sourcing process.

## 6. Source requirement

PRC-SRC-001..004 with PRC-RTE/VND/ASM dependencies. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..255; verified Commercial costing request and Operations demand contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-257..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add sourcing request/version, demand source, service/lane/mode/fleet/capacity/schedule/cargo constraints, budget/currency, candidate longlist, eligibility result/reasons, owner/SLA/status and selection lineage.

## 14. API impact

Shared REST/GraphQL create-from-source, revise, candidate-search, eligibility-evaluate, shortlist, submit, cancel and scoped read/export operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Sourcing queue/detail, inherited demand constraints, eligibility filters, candidate longlist/reasons, shortlist and handoff to RFQ; never require retyping available source data. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict budget/vendor cost and customer/cargo fields; candidate queries are tenant-scoped and cannot enumerate foreign vendors; exports follow field policy. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/status/owner/SLA/service/mode/origin/destination/date; selective candidate query, PostGIS where justified, cursor lists and async large searches. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source demand/version, criteria/config, candidates considered/excluded and reasons, shortlist changes, owner/SLA, override and RFQ handoff. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Link open sourcing records to canonical demand/vendor/rate evidence; unknown candidates remain staged and never auto-approved. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define source-demand mapping and sourcing lifecycle/constraints.
- Implement eligibility query using vendor/service/coverage/compliance/rate/capacity inputs.
- Implement queue/detail/longlist/shortlist APIs and accessible UX.
- Handoff a source-versioned shortlist to Procurement RFQ.
- Test no-reentry, eligibility, scope, concurrency and performance.

## 21. Main flow

Procurement creates sourcing from a costing or operational demand, inherits constraints, evaluates eligible vendors with explainable reasons, curates a shortlist and launches a linked RFQ.

## 22. Alternative flow

Start proactive lane/service sourcing, add an approved new-vendor intake, widen constraints with authorization, or close no-source with evidence.

## 23. Exception flow

Block missing/foreign source, no eligible vendor, expired compliance/rate, conflicting constraints, restricted cargo mismatch, stale demand or unauthorized budget override. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Sourcing inherits available customer/service/cargo/lane/schedule data; no silent re-entry or conflicting copy.
- Candidate eligibility is explainable and based on current canonical vendor/compliance/rate/capacity contracts.
- No algorithm autonomously selects or commits a vendor; authorized staff own shortlist/selection.
- Constraint override requires reason, permission, expiry/version and downstream visibility.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate source/version, service/mode/lane/cargo/schedule/capacity/budget compatibility, vendor eligibility, owner/SLA and current config/version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement manages sourcing; Sales/Operations submit/view own source status; approvers see sensitive comparisons; external vendors cannot view candidate lists. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Commercial/Operations requests, proactive sourcing, no candidate, expired compliance/rate, restricted cargo, widened constraints, multi-branch and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Source mapping/no-reentry/lifecycle/SLA tests.
- Eligibility/exclusion/override/candidate-query tests.
- RLS/RBAC/cost-field/customer-data/export isolation tests.
- Sourcing→RFQ handoff and target-volume search E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Commercial costing requests, vendor/rate lookup, Phase 5 capacity/assignment, notifications and reports. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Sourcing request/source mapping/criteria/eligibility/shortlist/RFQ handoff contract and no-source/override/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Pause new searches/RFQs, preserve request/candidate evidence, restore prior eligibility version and reconcile launched RFQs before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Sourcing inherits demand without re-entry.
- Candidate eligibility and exclusions are explainable and scope-safe.
- Human shortlist and RFQ handoff are versioned/auditable.
- No-source, override and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-257 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

