# Prompt 227 — Capacity, Utilization and Tracking Coverage

**Prompt ID:** `CG-S10-ATW-008`  
**Package document:** `CG-AABPP-ATW-227`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-227.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S10-ATW-008` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package version `0.11.0`.

## 3. Workstream

Workstream: Transport Resources; Epic: Capacity Control; Capability: Capacity and Utilization; Feature slice: resource capacity plus tracking-package utilization and coverage analytics; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact resource capacity reservation and expose tracking coverage/utilization without mixing commercial entitlement with physical capacity truth.

## 5. Business value

Prevent overbooking while showing how many vehicles are tracked, untracked, offline, mobile-compliant, device-active, or consuming subscription limits.

## 6. Source requirement

OPS-TMS-001..004; NFR-PERF; revised ATW-219/226. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

ATW-223..226 and verified exact cargo/UOM data. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-228, ATW-243..248, management reporting. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Add capacity profiles/reservations and safe tracking-coverage snapshots: entitled vehicle limit, active tracked vehicles, source class, current health/freshness, mobile-session compliance, device utilization, provider mapping coverage, and untracked required legs.

## 14. API impact

Provide capacity reserve/release/consume plus tracking coverage/utilization reads. Do not allow analytics APIs to alter entitlements or source mappings.

## 15. UI/UX impact

Capacity calendar and utilization dashboard with tracked/untracked/offline/fallback/source-class metrics, subscription usage, and drill-down under field policy.

## 16. Security impact

Protect vendor/customer loads, costs, driver/device identifiers, and provider details. Aggregates must resist inference across customer/branch scope.

## 17. Performance impact

Batch aggregates, query budgets, selective realtime only for active operations, no global telemetry scans, and history aggregation for long ranges.

## 18. Audit impact

Audit capacity changes, entitlement-limit evaluation, coverage snapshots, threshold alerts, and source-health classification.

## 19. Data migration impact

Backfill active reservations and coverage only from reconciled assignments and canonical tracking state.

## 20. Detailed implementation tasks

- Implement exact capacity ledger-like reservations.
- Add tracking coverage and subscription utilization projections.
- Detect tracking-required but untracked legs.
- Add threshold alerts and safe aggregates.
- Test capacity and tracking metrics independently and together.

## 21. Main flow

Planning reserves capacity; dispatch consumes it; tracking coverage updates from canonical source health; management views authorized aggregates.

## 22. Alternative flow

Allow untracked operations only when policy permits or under approved exception; allow mobile fallback without changing physical capacity.

## 23. Exception flow

Block over-capacity, inconsistent UOM, entitlement overage, hidden untracked required leg, stale aggregate, double consume/release, or unauthorized drill-down.

## 24. Business rules

- Capacity and tracking usage are separate dimensions.
- Subscription limit does not alter vehicle capacity.
- Tracking coverage derives from canonical state.
- Untracked required work is explicit.
- Aggregates are scope-safe.

## 25. Validation rules

- Reconcile reservation equations.
- Validate tracking policy, entitlement, assignment, and freshness.
- Reject cross-tenant/customer inference and stale versions.

## 26. Access rules

Planners/dispatchers reserve; managers approve tolerance; management sees scoped aggregates; customer users receive no internal fleet utilization.

## 27. Test data requirement

Multi-dimensional loads, mobile/device/provider/hybrid coverage, offline/fallback, subscription limit, untracked required leg, Tenant A/B.

## 28. Tests to create/update

- Capacity equation/concurrency tests.
- Tracking coverage and entitlement-limit tests.
- Aggregate privacy and inference tests.
- Planning/dispatch/Prompt 226 integration.
- Load/query budget tests.

## 29. Regression tests

Cargo/service, resources, route/load, dispatch, Prompt 226, milestones, cost/profitability and reporting.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Capacity equations, tracking-coverage definitions, subscription metric guide, and reconciliation runbook.

## 32. Rollback/recovery note

Stop new reservations or coverage alerts, restore prior profiles, reconcile active holds and tracking snapshots.

## 33. Acceptance criteria

- Concurrent actions cannot overbook.
- Tracking coverage reconciles to canonical source state.
- Subscription usage is accurate and scoped.
- No sensitive aggregate leakage.

## 34. Definition of Done

Capacity and tracking utilization models, services, UX, tests, docs, and rollback are complete without critical integrity/privacy blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-228 or another dependency-clean task. Prompt 248 alone may close Phase 5.
