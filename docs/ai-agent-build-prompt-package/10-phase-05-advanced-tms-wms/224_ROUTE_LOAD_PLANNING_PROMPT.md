# Prompt 224 — Route and Load Planning

**Prompt ID:** `CG-S10-ATW-005`  
**Package document:** `CG-AABPP-ATW-224`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-224.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-005` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Advanced Transportation; Epic: Constraint-Aware Planning; Capability: Route and Load Planning; Feature slice: stops, time windows, capacity/UOM, compatibility, distance/time/cost score, explainable plan and human override; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned explainable route and load planning for multi-stop legs using PostGIS and approved constraints without claiming guaranteed optimality.

## 5. Business value

Improve asset use and execution feasibility while keeping planners accountable for final decisions.

## 6. Source requirement

OPS-TMS-001..004 route/load slice; RPD-015; RPD-038; NFR-PERF. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221 and ATW-223; verified location/PostGIS and configuration foundations. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-225, ATW-227..228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add planning request/scenario/version, stops/time windows, cargo/UOM/capacity constraints, compatibility, distance/time/cost inputs, score/components, selected plan and override evidence.

## 14. API impact

Shared REST/GraphQL prepare, validate, execute-async, compare-scenarios, select/override and read-lineage operations; case-specific map/routing calls remain explicit. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Planner workspace with stop/load constraints, capacity visualization, map/sequence, scenario comparison, infeasibility reasons, selected plan and human override audit. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Restrict customer locations, rates/cost and driver/resource details; external routing input is minimized and secrets remain server-only. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Run non-trivial planning asynchronously, cache safe distance matrices by governed key, bound scenario size/time and preserve timeout/cancel/progress evidence. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record algorithm/rule version, inputs, external-source version, scenarios/scores, infeasibility, selected plan, human override/reason and downstream effect. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

No historical re-optimization; migrate only active draft planning inputs with source/version reconciliation. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory planning inputs, PostGIS/map adapters and operational constraints.
- Define exact UOM/capacity/time-window/scenario/score contracts.
- Implement deterministic baseline planner, async job, APIs and planner UX.
- Integrate route/load selection with legs/dispatch and override evidence.
- Run correctness, infeasibility, privacy, load and compatibility tests.

## 21. Main flow

Planner submits authorized stops/cargo/resources/constraints, service validates and produces explainable feasible scenarios, human selects or overrides one, then commits a versioned plan to unstarted legs.

## 22. Alternative flow

Plan manually with server validation, compare route/load scenarios, replan only affected unstarted legs or use a contracted case-specific routing adapter.

## 23. Exception flow

Block infeasible capacity/time window/service/location, missing/invalid UOM conversion, stale leg/resource version, external timeout ambiguity, unsafe override or attempt to mutate started execution. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- A plan is decision support and may be called optimal only with proven objective/constraint evidence.
- Every score and constraint result is explainable from captured versioned inputs.
- Human override requires authority/reason and cannot bypass hard safety/capacity rules.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Stops, cargo/UOM, vehicle/resource capacity, time windows, service and location data are complete.
- Scenario satisfies all hard constraints and labels soft violations explicitly.
- Selected plan references current source versions and unstarted compatible legs.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Planners create/select; managers approve configured overrides; dispatch receives selected plan; restricted cost/location/resource fields use policy-safe projections. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Multi-stop/multi-leg loads, weight/volume/pallet limits, time windows, incompatible cargo/resource, no-feasible plan, external timeout, stale version and Tenant A/B. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Constraint/UOM/capacity/sequence/score/infeasibility unit/property tests.
- PostGIS/adapter/async/API/leg/dispatch integration and idempotency tests.
- RLS/RBAC/field/privacy, performance/cancel, accessibility and human-override audit tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Shipment legs, fleet/driver, dispatch, milestones, cost/profitability and provider integration policy. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Planning constraint/objective/algorithm/version contract, provider boundary and infeasible/timeout/replan runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Cancel incomplete job, retain prior selected plan, remove only uncommitted scenario data and reconcile any downstream reservations before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Feasible plans satisfy captured hard constraints.
- No false optimality or hidden autonomous commitment exists.
- Selection/override is versioned, auditable and dispatch-compatible.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-225 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

