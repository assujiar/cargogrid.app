# Prompt 243 — High-Volume TMS/WMS and Multi-Source Telemetry Controls

    **Prompt ID:** `CG-S10-ATW-024`  
    **Package document:** `CG-AABPP-ATW-243`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-243.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-024` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Operational Scale; Epic: High-Volume Reliability; Capability: Throughput, Backpressure and Reconciliation; Feature slice: transport/WMS hot paths plus mobile, TCP gateway, provider and hybrid telemetry workloads; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Prove and harden Phase 5 at declared target volumes, including all repository-controlled multi-source tracking paths.

    ## 5. Business value

    Keep dispatch, tracking and warehouse operations responsive and recoverable under peak workload.

    ## 6. Source requirement

    All advanced OPS scale slices; RPD-014/025/033/035; revised ATW-226. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    ATW-221..242, including all required ATW-226 child tasks. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-244..248 and downstream portal/enterprise consumers. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Add measured indexes, bounded job/queue metadata, reconciliation checkpoints, archival/partition structures, and source-health aggregates only where evidence justifies them.

    ## 14. API and integration impact

    Enforce cursor pagination, batch limits, rate/backpressure, async receipts, idempotency and consistent failure semantics across mobile, gateway and provider paths.

    ## 15. UI/UX impact

    Show queued/degraded/partial/retry states in boards, Driver PWA, device admin and tracking views.

    ## 16. Security and privacy impact

    Load and abuse tests preserve RLS, scoped jobs/channels, secret redaction, socket limits, and customer privacy.

    ## 17. Performance and reliability impact

    Declare separate target profiles:
- Driver Mobile HTTPS: active sessions, interval, reconnect burst, permission/freshness heartbeat.
- Direct Device Gateway: concurrent TCP sockets, AVL records/sec, ACK p50/p95/p99, reconnect, buffer depth, database outage.
- Third-Party Platform: webhook burst, polling batch, rate limit, cursor catch-up, provider outage.
- Hybrid: duplicate/conflicting coordinates, arbitration throughput, source switch and hysteresis.
- Canonical projection: database write latency, current-position latency, Realtime latency, route history query, geofence and milestone-candidate throughput.

Measure queue age, retry/DLQ rate, drop count, duplicate/stale ratio, CPU/memory/network, lock time, storage growth, and recovery backlog.

    ## 18. Audit and observability impact

    Record profile/environment, config versions, source class, batch/socket/job metrics, throttle, retry, DLQ, replay, reconciliation and residual limits without logging sensitive payloads.

    ## 19. Data migration and compatibility impact

    Rehearse indexes, retention and partition changes at representative scale; preserve audit and accepted event evidence.

    ## 20. Detailed implementation tasks

    - Profile all TMS/WMS and telemetry hot paths.
- Define reproducible workload fixtures and budgets.
- Fix measured query/socket/batch/locking/backpressure issues.
- Add monitoring and saturation alerts.
- Run load, soak, failure, restart and recovery reconciliation.

    ## 21. Main flow

    Representative concurrent operations remain within budgets; accepted work is buffered/queued, processed idempotently, and reconciled.

    ## 22. Alternative flow

    Degrade to polling/manual refresh, pause noncritical jobs, scale workers, or replay bounded DLQ batches.

    ## 23. Exception flow

    Fail safely on socket saturation, queue lag, provider throttling, worker loss, duplicate delivery, database outage, Realtime disconnect, or retention pressure.

    ## 24. Business rules

    - Performance claims name environment/profile/result.
- ACK and accepted-buffer semantics are explicit.
- No accepted event is silently dropped.
- Backpressure never weakens authorization/order.
- Partition/cache changes are evidence-driven.

    ## 25. Validation rules

    - Reconcile accepted, processed, duplicated, rejected, dead-lettered and replayed counts.
- Reject unsafe batch/socket limits and unscoped channels.
- Verify recovery from restart/outage.

    ## 26. Access rules

    Normal roles use workloads; only authorized admins trigger diagnostics/replay; metrics and traces are filtered.

    ## 27. Test data requirement

    Representative tenants, fleets, sessions, sockets, providers, warehouses, jobs, duplicate/replay/outage fixtures and target volumes.

    ## 28. Tests to create/update

    - Query plan/index/cursor tests.
- Socket/ACK/buffer/restart tests using simulator.
- Mobile/provider/hybrid load tests.
- Job retry/DLQ/replay reconciliation.
- RLS/cache/channel isolation.
- Browser responsiveness and observability tests.


### External-evidence policy

The implementation must not be blocked merely because physical hardware or a live third-party provider is unavailable at the active checkpoint.

1. **Physical GPS device testing**
   - Hardware-in-the-loop testing with an actual Teltonika or equivalent installed device is deferred until a device is available.
   - Before verification, protocol simulators and recorded vendor frames must prove IMEI handshake, Codec 8 Extended parsing, CRC validation, ACK behavior, duplicate/replay handling, reconnect, malformed payload rejection, buffering, database outage recovery, and canonical projection.
   - Record the deferred item as `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE`, including owner, target device/model, installation prerequisites, exact future test procedure, expected evidence, and safe activation gate.
   - Do not claim “tested on physical device” until that future evidence exists.

2. **Third-party GPS platform testing**
   - A live provider test is conditional on approved credentials, API access, legal/commercial permission, documented rate limits, and a stable provider contract.
   - When those prerequisites are unavailable, mark the live-provider test `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE`.
   - The provider adapter contract, authentication/signature checks, mapping, retry, rate-limit, schema-drift, idempotency, and failure behavior must still be tested with deterministic mocks, contract fixtures, or a sandbox when available.
   - Do not claim a named provider is live or certified without live evidence.

3. **Closure treatment**
   - These two deferred/conditional external tests are non-blocking when all repository-controlled implementation, simulator/contract, security, migration, load, recovery, and canonical-data gates pass.
   - Any unresolved repository-controlled defect remains blocking.

    ## 29. Regression tests

    All ATW-221..242 behavior, Platform/Finance contracts, audit/retention, and critical E2E.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Target profiles, budgets, results, dashboard/alerts, saturation, scaling, replay and reconciliation runbooks.

    ## 32. Rollback/recovery note

    Disable only new optimization, drain/reconcile queues, restore baseline settings, preserve accepted events, and rerun affected profiles.

    ## 33. Acceptance criteria

    - Declared budgets pass or explicit non-critical limits are documented.
- Accepted work remains exact and isolated.
- Gateway/mobile/provider/hybrid recovery is proven with simulators/contracts.
- No critical performance or correctness blocker remains.

    ## 34. Definition of Done

    Measured bottlenecks, observability, tests, docs, and rollback are complete; external hardware/live-provider absence is treated under Prompt 226 policy.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release ATW-244 or another dependency-clean task. Prompt 248 alone may close Phase 5.
