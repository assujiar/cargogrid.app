# Prompt 263 — Vendor Assignment

**Prompt ID:** `CG-S11-PRC-014`  
**Package document:** `CG-AABPP-PRC-263`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-263.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-014` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement and Operations; Epic: Governed Operational Supply; Capability: Vendor Selection Acceptance and Shipment/Task Assignment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed vendor assignment that consumes approved eligibility, commercial and capacity evidence while extending canonical Operations shipment/leg/task assignments.

## 5. Business value

Ensure each operational assignment is executable, commercially controlled and traceable to the selected vendor evidence.

## 6. Source requirement

PRC-SRC-001..004, PRC-POI-001..004 and OPS-TMS/SHP Phase 3/5 contracts. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..262; verified Phase 3/5 assignment and capacity contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-264..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend canonical shipment/leg/task assignment with procurement selection, vendor, accepted quote/rate/contract/PO/capacity reservation, eligibility snapshot, invitation/acceptance/decline, override, reassignment/cancellation and actual fulfillment lineage.

## 14. API impact

Shared REST/GraphQL eligible-candidate read, propose/invite, accept/decline, assign, reassign, cancel-eligible and lineage/status operations routed through existing Operations assignment service boundaries. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Assignment panel/queue with vendor eligibility, rate/contract/capacity evidence, response deadline, acceptance/decline, override warning and reassignment timeline; Operations context remains canonical. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict customer/cargo, vendor cost/rate and driver/resource fields by purpose; vendor accepts only its scoped offer; reference/token possession never grants shipment access. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/branch/shipment/leg/task/vendor/status/window; concurrency-safe assignment/reservation, cursor queues, bounded notifications and target-volume dispatch compatibility. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record demand/selection/rate/contract/PO/capacity/compliance versions, candidate/override, invitation, acceptance/decline, assignment/reassignment, actor and Operations fulfillment. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Link existing assignments to evidenced canonical vendor/rate/source where available; mark unknown procurement lineage, never duplicate Operations records or invent acceptance. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile Procurement eligibility and canonical Phase 3/5 assignment ownership.
- Define proposal/invitation/acceptance/assignment/reassignment/override invariants.
- Implement shared contracts/APIs and responsive assignment evidence UI.
- Integrate capacity reservation and Operations execution without status duplication.
- Test conflicts, eligibility expiry, tokens, concurrency, retries and actual-cost lineage.

## 21. Main flow

Operations/Procurement requests an assignment, service validates current vendor/compliance/rate/contract/capacity evidence, vendor accepts if required, and canonical shipment/leg/task receives one idempotent assignment snapshot.

## 22. Alternative flow

Direct assign under approved policy, invite multiple sequential candidates, partially accept capacity, reassign before/after start under lifecycle rules or use a governed emergency override.

## 23. Exception flow

Block expired/suspended/blacklisted vendor, invalid service/coverage/rate/contract/capacity, double booking, stale shipment, unauthorized vendor token, duplicate accept or unsafe in-progress reassignment. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Procurement governs vendor eligibility/commercial source; Operations owns shipment/leg/task execution and status.
- Assignment snapshots exact selected vendor/rate/contract/PO/capacity/compliance/source versions.
- Acceptance, assignment and capacity consumption are concurrency-controlled/idempotent.
- Emergency override requires reason, approval, expiry, customer/financial impact and later review.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate shipment/leg/task state, vendor/service/coverage/compliance/rate/contract/PO/capacity eligibility, acceptance/deadline, override authority and optimistic versions. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Authorized Procurement/Operations propose; vendor accepts/declines own invitation; dispatcher performs canonical assignment; Finance reads source lineage; customers do not see vendor cost. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Direct/invited/declined/expired offers, partial capacity, duplicate accept, reassignment, emergency override, in-progress block, multi-leg and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Eligibility/snapshot/invitation/accept/assignment/reassignment tests.
- Capacity/assignment concurrency/idempotency and event-order tests.
- RLS/vendor token/customer/cost-field isolation tests.
- Sourcing→PO/contract→capacity→assignment→actual-cost E2E and dispatch load regression.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Phase 3 assignment/milestones/actual cost, Phase 5 fleet/driver/capacity/dispatch, rates/PO/contracts and Finance source lineage. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Vendor eligibility/proposal/acceptance/assignment/snapshot/override/reassignment contract and no-response/emergency/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop new invitations/assignments, preserve accepted/live Operations records, release only eligible capacity and reconcile actual-cost/PO/Finance lineage before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Assignments extend canonical Operations records without duplication.
- Eligibility, commercial and capacity snapshots are exact.
- Acceptance/concurrency/reassignment/override controls work.
- Operations and Finance compatibility remains intact.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-264 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

