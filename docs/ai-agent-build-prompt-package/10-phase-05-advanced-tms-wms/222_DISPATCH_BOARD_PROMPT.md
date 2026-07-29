# Prompt 222 — Advanced Dispatch Board with Tracking Health

    **Prompt ID:** `CG-S10-ATW-003`  
    **Package document:** `CG-AABPP-ATW-222`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-222.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-003` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Advanced Transportation; Epic: Dispatcher Control Tower; Capability: Advanced Dispatch Board; Feature slice: board/list/map dispatch plus canonical tracking-health projection; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Extend Phase 3 dispatch into a high-density, permission-safe control board that exposes assignment readiness and canonical tracking health without reading raw GPS sources.

    ## 5. Business value

    Dispatchers can assign and monitor many movements while immediately seeing whether a trip is tracked, stale, degraded, conflicting, or running on fallback.

    ## 6. Source requirement

    OPS-TMS/TRK-001..004; UX dispatch controls; revised ATW-219 multi-source architecture. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    ATW-221, verified Phase 3 dispatch, and the tracking projection contract from ATW-226F/H for live tracking fields. The board may be implemented before 226, but tracking columns remain feature-gated and must be reverified after 226. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-223..228, ATW-243, ATW-245..248, Customer Portal tracking. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Add or extend bounded dispatch read models with canonical `tracking_status`, `authoritative_source_type`, `last_position_at`, `freshness_status`, `accuracy_meters`, `fallback_active`, `tracking_entitled`, and `tracking_exception_count`. Never duplicate position history.

    ## 14. API and integration impact

    Provide shared REST/GraphQL window, queue, assign, hold, reassign, dispatch, tracking-health detail, and canonical map-position reads. Every map marker must originate from the source-arbitrated current-position service.

    ## 15. UI/UX impact

    Add board/list/map views showing source type, last update, freshness, accuracy, fallback, no-signal warning, and entitlement. Include keyboard/mobile alternatives and honest stale/degraded states.

    ## 16. Security and privacy impact

    Map and driver fields are scoped; raw IMEI, phone telemetry, provider credential, and private payload are never exposed. Drag/drop cannot bypass server authorization.

    ## 17. Performance and reliability impact

    Use cursor/window reads, selective subscriptions, bounded map viewport, batched tracking-health lookup, virtualization, and polling fallback. No global vehicle subscription.

    ## 18. Audit and observability impact

    Audit assignment actions plus the tracking snapshot visible at decision time, source switch, degraded-state acknowledgement, and override reason.

    ## 19. Data migration and compatibility impact

    Adopt existing dispatch records additively and join canonical telemetry projections by trip/vehicle. No historical position copy into dispatch tables.

    ## 20. Detailed implementation tasks

    - Define board projection fields and tracking status taxonomy.
- Integrate canonical position and tracking-health service.
- Add feature-gated columns, filters, alerts, and map markers.
- Preserve conflict-safe assignment and dispatch.
- Test stale, fallback, no-entitlement, and cross-tenant behavior.

    ## 21. Main flow

    Dispatcher opens an authorized operational window, sees ready movements and canonical tracking state, assigns/dispatches through server checks, and receives scoped updates.

    ## 22. Alternative flow

    When live updates fail, show last trusted position with timestamp and degraded state; allow manual refresh and operational follow-up.

    ## 23. Exception flow

    Block double assignment, stale board version, unentitled tracking access, raw-source leakage, wrong vehicle-trip mapping, and silent map freshness failure.

    ## 24. Business rules

    - The board is a projection, not a tracking source.
- Tracking state never grants dispatch authority.
- Raw telemetry is never read directly by the browser.
- A stale position is labeled stale, never displayed as live.
- Feature-disabled tenants see no inactive control.

    ## 25. Validation rules

    - Verify record scope before map/list output.
- Verify canonical source, freshness, assignment, and entitlement versions.
- Ensure bulk operations return per-item results.
- Reject forged vehicle/trip IDs and stale concurrency tokens.

    ## 26. Access rules

    Dispatchers see authorized branches/services/trips; managers approve configured overrides; customer users never access this internal board.

    ## 27. Test data requirement

    Active trips across mobile, direct-device, third-party, hybrid, untracked, stale, conflict, fallback, and revoked-entitlement scenarios for Tenant A/B.

    ## 28. Tests to create/update

    - Board projection and canonical-position contract tests.
- Assign/dispatch concurrency and idempotency tests.
- RLS/field/privacy negative tests.
- Selective realtime and degraded-polling tests.
- Browser/accessibility and target-window load tests.

    ## 29. Regression tests

    Re-run Phase 3 dispatch/assignment, ATW-223 resources, ATW-224 planning, ATW-226 telemetry, ATW-228 exceptions, and PostGIS/map tests.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Dispatch-board data dictionary, tracking-health UI guide, stale/fallback/no-signal runbook, and access/realtime architecture.

    ## 32. Rollback/recovery note

    Feature-disable tracking columns and fall back to verified dispatch behavior; reconcile pending assignments and preserve canonical telemetry.

    ## 33. Acceptance criteria

    - Board remains responsive at target window.
- No raw-source or cross-tenant data leaks.
- Stale/fallback states are honest and actionable.
- Assignment authority remains server-enforced.

    ## 34. Definition of Done

    Dispatch board, canonical tracking projection, access controls, UX states, tests, docs, and rollback are complete with no critical blocker.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release the next dependency-clean ATW task. Prompt 248 alone may close Phase 5.
