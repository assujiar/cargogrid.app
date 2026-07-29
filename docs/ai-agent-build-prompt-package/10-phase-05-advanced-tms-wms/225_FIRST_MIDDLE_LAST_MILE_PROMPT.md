# Prompt 225 — First-, Middle-, and Last-Mile Orchestration with Tracking Policy

    **Prompt ID:** `CG-S10-ATW-006`  
    **Package document:** `CG-AABPP-ATW-225`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-225.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-006` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Advanced Transportation; Epic: End-to-End Mile Execution; Capability: Mile Orchestration; Feature slice: per-leg tracking requirement, source policy, handoff, geofence and SLA; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Implement first-, middle-, and last-mile orchestration where every executable leg can resolve an explicit tracking policy.

    ## 5. Business value

    Different owned, vendor, rental, and partner legs can use the appropriate subscribed tracking mode while customer progress remains consistent.

    ## 6. Source requirement

    OPS-SHP/TMS/TRK-001..004; revised multi-source tracking architecture. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    ATW-221 and ATW-224; verified Phase 3 milestones/exceptions; resource eligibility from ATW-223. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-226..228, ATW-243..248, Customer Portal tracking. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Add leg/stage tracking policy fields or versioned linked policy: required flag, allowed sources, preferred source, fallback order, freshness, accuracy, interval, start/end trigger, geofence policy, customer visibility, and no-signal escalation.

    ## 14. API and integration impact

    Provide stage plan/readiness/handoff APIs plus resolve-tracking-policy and tracking-start/stop orchestration contracts. Do not ingest telemetry here.

    ## 15. UI/UX impact

    Control-tower stage timeline shows expected tracking mode, active source, freshness, handoff source change, and no-signal readiness.

    ## 16. Security and privacy impact

    Handoff parties and locations are scoped. Driver/mobile/device/provider details are minimized. Customer projection hides internal source identifiers.

    ## 17. Performance and reliability impact

    Index active leg/stage/status/source requirement/time; batch resolve policies and selectively update active stages.

    ## 18. Audit and observability impact

    Audit policy version, source expectation, source activation/deactivation, custody handoff, fallback, exception, and override.

    ## 19. Data migration and compatibility impact

    Classify existing active legs only with explicit rules. Uncertain tracking requirements remain unclassified and visible.

    ## 20. Detailed implementation tasks

    - Define tracking policy per stage/leg.
- Integrate resource eligibility and subscription entitlements.
- Define tracking session/device/provider handoff semantics.
- Integrate geofence/milestone/exception candidates.
- Test vehicle/driver/source changes at handoff.

    ## 21. Main flow

    Confirmed stages execute in dependency order; at each tracking-required leg, the system resolves entitlement and resource mapping, starts the allowed source, and records handoff.

    ## 22. Alternative flow

    Allow mobile-only vendor pickup, direct-device linehaul, provider-based partner delivery, or hybrid fallback under published policy.

    ## 23. Exception flow

    Block untracked required leg, unsupported package, missing mapping, premature handoff, stale source, unauthorized override, or silent source loss.

    ## 24. Business rules

    - Every leg has explicit tracking requirement or explicit not-required status.
- Source changes at handoff are recorded.
- Customer progress is derived, not editable.
- No source silently continues after its assignment ends.
- Fallback follows configured order.

    ## 25. Validation rules

    - Validate stage dependencies, entitlement, resource assignment, source eligibility, freshness/accuracy, and handoff timing.
- Reject cross-tenant/source/config mismatch.

    ## 26. Access rules

    Operations manages stages; assigned field users confirm scoped actions; customers receive only sanitized progress.

    ## 27. Test data requirement

    Pickup-linehaul-delivery using mobile/direct/provider/hybrid, vehicle swap, driver swap, provider outage, skipped stage, no-signal, Tenant A/B.

    ## 28. Tests to create/update

    - Stage/tracking-policy resolution tests.
- Start/stop/handoff source tests.
- Entitlement and fallback tests.
- RLS/privacy and customer projection tests.
- E2E across dispatch, Prompt 226, milestones.

    ## 29. Regression tests

    Phase 3 shipment/tracking/ePOD/readiness, ATW-223 resources, ATW-224 planning, ATW-226 ingestion, future Customer Portal.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Mile-stage and tracking-policy specification, handoff/source-switch runbook, fallback/no-signal operations guide.

    ## 32. Rollback/recovery note

    Disable faulty policy version, restore prior stage plan, stop invalid sessions/mappings, and reconcile active source/history before resume.

    ## 33. Acceptance criteria

    - Stage tracking requirements are deterministic.
- Handoffs cannot orphan or leak tracking sessions.
- Multiple tracking packages work without duplicate shipment truth.
- Customer progress remains safe.

    ## 34. Definition of Done

    Stage policies, services, UX, integrations, tests, docs, and recovery are complete with no critical tracking-orchestration blocker.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release ATW-226 or another dependency-clean task. Prompt 248 alone may close Phase 5.
