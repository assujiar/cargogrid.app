# Prompt 224 — Route and Load Planning Using Canonical Position

**Prompt ID:** `CG-S10-ATW-005`  
**Package document:** `CG-AABPP-ATW-224`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-224.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S10-ATW-005` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package version `0.11.0`.

## 3. Workstream

Workstream: Advanced Transportation; Epic: Constraint-Aware Planning; Capability: Route and Load Planning; Feature slice: versioned planning using canonical authoritative current position; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement explainable route and load planning without reading raw mobile, direct-device, or third-party telemetry.

## 5. Business value

Improve route feasibility and replanning while ensuring all location-dependent decisions use one trusted, source-arbitrated projection.

## 6. Source requirement

OPS-TMS-001..004; PostGIS; revised ATW-219/226 canonical tracking architecture. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-223, verified PostGIS/location/config foundations. Replanning based on live position requires ATW-226F. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-225, ATW-227..228, ATW-243..248. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Add planning scenarios, stops, constraints, score components, selected plans, overrides, and references to canonical current-position snapshot/version when used.

## 14. API impact

Provide prepare, validate, execute-async, compare, select, override, and replan APIs. Live-location input must be fetched through canonical current-position service and include freshness/confidence metadata.

## 15. UI/UX impact

Planner workspace shows route/load constraints, current trusted position, freshness, source class label at safe granularity, alternatives, infeasibility, and human override.

## 16. Security impact

Restrict customer locations, cost, driver, and source details. External routing inputs are minimized. Raw device/mobile/provider data never leaves telemetry services.

## 17. Performance impact

Bound scenarios and matrix size; run non-trivial planning asynchronously; cache safe matrices; reject stale canonical position beyond configured tolerance.

## 18. Audit impact

Audit algorithm/rule/source version, canonical-position snapshot, freshness/confidence, scenarios, selection, override, and replan trigger.

## 19. Data migration impact

No historical re-optimization. Additive schema only; existing plans remain linked to their captured inputs.

## 20. Detailed implementation tasks

- Define canonical-position input contract.
- Define hard/soft constraints and stale-position policy.
- Implement deterministic baseline planner and async jobs.
- Integrate human selection/override and position-aware replan.
- Test stale, conflicting, no-position, and fallback source cases.

## 21. Main flow

Planner submits authorized stops/cargo/resources; service validates constraints and optionally reads canonical current position; human selects a versioned plan.

## 22. Alternative flow

Plan manually when no trusted position exists, or replan unstarted legs after an approved tracking-derived exception.

## 23. Exception flow

Block raw-source access, stale/low-confidence position use, infeasible constraints, external timeout ambiguity, stale plan/resource versions, or mutation of started execution.

## 24. Business rules

- Planning is decision support.
- Only canonical current position may influence planning.
- Source arbitration remains Prompt 226 ownership.
- Stale positions are rejected or explicitly degraded.
- Human commitment is required.

## 25. Validation rules

- Validate stops, UOM, resource capacity, time windows, position freshness/confidence, source version, and unstarted legs.
- Reject tenant/source mismatch and stale concurrency.

## 26. Access rules

Planners create/select; managers approve configured overrides; dispatch consumes selected plans; customers never see internal scoring or source details.

## 27. Test data requirement

Multi-stop cases with fresh mobile/device/provider/hybrid positions, stale/conflict/no-position, fallback, infeasible loads, Tenant A/B.

## 28. Tests to create/update

- Constraint and score tests.
- Canonical-position contract and stale-policy tests.
- PostGIS/adapter/async/API tests.
- RLS/privacy and override audit tests.
- Load/cancel/recovery tests.

## 29. Regression tests

Shipment legs, resources, dispatch, Prompt 226 canonical telemetry, milestones, cost/profitability, and provider integration policy.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Planning contract, canonical-position dependency, source/freshness limitations, provider boundary, and replan runbook.

## 32. Rollback/recovery note

Cancel incomplete planning jobs, retain prior selected plan, reconcile downstream reservations, and fall back to manual validated planning.

## 33. Acceptance criteria

- Feasible plans satisfy hard constraints.
- No raw telemetry dependency exists.
- Position-aware replanning is freshness-controlled.
- Selection remains human-governed.

## 34. Definition of Done

Planner services, position contract, APIs, UX, tests, docs, and rollback are complete without false optimality or critical privacy blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-225 or another dependency-clean task. Prompt 248 alone may close Phase 5.
