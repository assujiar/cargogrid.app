# Prompt 262 — Vendor Capacity and Availability

**Prompt ID:** `CG-S11-PRC-013`  
**Package document:** `CG-AABPP-PRC-262`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-262.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-013` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Execution; Epic: Supply Assurance; Capability: Capacity Declaration, Reservation and Fulfillment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement vendor-owned capacity and availability governance that extends Phase 5 resource capacity without creating a second fleet/driver truth.

## 5. Business value

Expose reliable supply for sourcing and assignment while measuring fulfillment.

## 6. Source requirement

PRC-SRC-001..004 and Phase 5 capacity/resource contracts. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..261; verified Phase 5 fleet/driver/load capacity and vendor contract. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-263..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add vendor capacity offer/version by service/mode/lane/region/resource type/period, quantity/UOM, availability window, commitments/reservations, blackout, acceptance, source/contract and fulfillment/release lineage referencing canonical operational resources where known.

## 14. API impact

Shared REST/GraphQL declare/import, validate/publish, query, reserve/request, accept/decline, release, blackout and utilization/fulfillment read operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Capacity calendar/grid, declarations, commitments, reservations, availability filters, acceptance/decline and shortage/conflict states; optional vendor update surface if enabled. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Vendor users update only own scoped capacity; internal budgets/customer demand are hidden; resource/driver personal data is minimized; server reauthorizes every reservation action. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/service/mode/region/resource type/window/status; PostGIS only where justified, bounded calendars, cursor queries and concurrency-safe reservation transactions. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source/contract/version, declared quantity/UOM/window, reservation/acceptance/release, blackout, actor, override, fulfillment and utilization calculation. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Link existing availability to canonical vendor/resource/time evidence; do not manufacture capacity or double-reserve imported commitments. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile Phase 5 capacity/resource ownership and define reference boundaries.
- Define offer/window/quantity/UOM/commitment/reservation/acceptance invariants.
- Implement concurrency-safe services/APIs and accessible capacity calendar.
- Integrate sourcing and assignment while preserving Operations execution authority.
- Test conflicts, retries, scope, utilization, migration and high-volume search.

## 21. Main flow

Vendor/internal Procurement publishes eligible capacity, sourcing requests a reservation, vendor accepts, and assignment consumes/releases the same commitment while fulfillment feeds performance.

## 22. Alternative flow

Recurring capacity, ad-hoc offer, partial acceptance, blackout, substitution of an eligible canonical resource or manual confirmation with evidence.

## 23. Exception flow

Block expired contract/compliance, wrong service/lane/resource, over-reservation, overlapping commitment, stale window, duplicate accept, network ambiguity or unauthorized vendor update. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Vendor capacity references, rather than duplicates, canonical Phase 5 fleet/driver/warehouse/resource identities.
- Available = declared eligible capacity minus active commitments/reservations using exact UOM/time-window rules.
- Reservation/accept/decline/release is concurrency-controlled and idempotent; no silent overbooking.
- Procurement governs supply commitment; Operations owns live dispatch/execution and custody status.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate active vendor/contract/compliance, service/mode/lane/region/resource/UOM/window, quantity, overlapping commitments, acceptance authority and current version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement manages internal declarations/requests; enabled vendor users manage own offers/acceptance; Operations reads/consumes permitted commitments; customers see none. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Recurring/ad-hoc/partial capacity, blackout, overlapping reservations, substitution, stale accept, duplicate retry, cross-branch and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Capacity equation/window/UOM/reservation/accept/release tests.
- Concurrency/overbooking/idempotency/retry tests.
- RLS/vendor-resource/customer-data isolation tests.
- Sourcing→capacity→assignment→fulfillment/performance E2E and load tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Phase 5 fleet/driver/capacity/dispatch, sourcing/RFQ, contracts, vendor performance and notifications. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Capacity offer/window/reservation/acceptance/resource-reference/utilization contract and shortage/overbooking/release/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Pause new reservations, preserve accepted commitments, release only eligible holds, restore last compatible resolver and reconcile Operations assignments. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Vendor capacity extends canonical resources without duplicate truth.
- Reservation and acceptance prevent overbooking under concurrency.
- Sourcing/assignment/fulfillment lineage reconciles.
- Vendor scope and target-volume budgets pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-263 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

