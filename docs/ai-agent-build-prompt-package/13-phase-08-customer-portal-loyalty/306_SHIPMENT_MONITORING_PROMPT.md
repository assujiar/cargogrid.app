# Prompt 306 — Customer Shipment Monitoring and Tracking-Health Alerts

    **Prompt ID:** `CG-S13-CPL-008`  
    **Package document:** `CG-AABPP-CPL-306`  
    **Version:** `0.15.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-08/CPL-306.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S13-CPL-008` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 8 — Customer Portal and Loyalty`; package version `0.15.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Portal Operations Visibility; Epic: Monitoring and Alerts; Capability: Shipment Monitoring; Feature slice: customer-safe alerts for milestone and tracking-health changes; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Implement customer monitoring over canonical approved alerts, including safe stale/no-signal/degraded notifications, without exposing internal source details or creating storms.

    ## 5. Business value

    Customers proactively know when a shipment is delayed or visibility is degraded.

    ## 6. Source requirement

    CPT-TRK-001..004; revised ATW-228 and CPL-305. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    CPL-300, CPL-305, Platform notification/jobs and canonical Operations alert projection. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    CPL-313 and Phase 9 automation/reporting boundaries. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Store customer alert subscriptions/preferences and emitted audit linked to canonical shipment alerts. Do not store raw GPS events.

    ## 14. API and integration impact

    Subscribe/unsubscribe/preferences/alerts APIs with per-emission scope revalidation, idempotency, throttle, retry and DLQ.

    ## 15. UI/UX impact

    Monitoring widgets, alert history and preferences for milestone delay, exception, no-fresh-position, tracking restored, delivery and document/ePOD availability.

    ## 16. Security and privacy impact

    Internal source conflict, provider/device identity, driver data, SLA workload, vendor dispute and root-cause details are excluded.

    ## 17. Performance and reliability impact

    Batch fan-out, storm control, idempotent jobs, scoped channels, cursor history and bounded retries.

    ## 18. Audit and observability impact

    Audit subscription, scope check, canonical alert source/version, throttle/suppression, delivery attempt and outcome.

    ## 19. Data migration and compatibility impact

    Adopt canonical alert codes; no raw history backfill without approved mapping.

    ## 20. Detailed implementation tasks

    - Define customer-visible alert allowlist.
- Map internal tracking-health events to safe messages.
- Implement preferences, throttling, retry/DLQ.
- Add tracking-restored and stale/no-signal handling.
- Test scope revocation and replay storms.

    ## 21. Main flow

    Customer subscribes to allowed alerts and receives updates only for currently scoped shipments.

    ## 22. Alternative flow

    Account admin sets defaults; individual users override channels; degraded tracking may produce one bounded alert and one restoration alert.

    ## 23. Exception flow

    Block forged scope, internal detail leakage, duplicate notification storm, stale subscription, unsafe source wording, or failed reauthorization.

    ## 24. Business rules

    - Subscription grants no shipment access.
- Each emission revalidates scope.
- Internal source identifiers are hidden.
- Duplicate/replay is storm-controlled.
- Automation depth remains Phase 9.

    ## 25. Validation rules

    - Validate customer scope, alert allowlist, canonical source/version, idempotency and throttle.
- Reject cross-tenant and revoked membership.

    ## 26. Access rules

    Customer users manage personal preferences; customer admins manage scoped defaults; internal users configure tenant-safe templates.

    ## 27. Test data requirement

    Mobile/device/provider/hybrid underlying alerts, stale/no-signal/restored, duplicate/replay, revoked user, Tenant A/B and high-volume alert bursts.

    ## 28. Tests to create/update

    - Subscription/scope tests.
- Canonical alert mapping and privacy tests.
- Idempotency/throttle/retry/DLQ tests.
- Browser/accessibility and notification history.
- Target-volume storm prevention.

    ## 29. Regression tests

    Platform notifications/jobs, Operations/ATW exceptions, CPL-305 tracking, ticketing and customer scope.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Alert allowlist, message wording, freshness/no-signal behavior, preferences, throttling and recovery runbook.

    ## 32. Rollback/recovery note

    Pause affected alert class, drain/reconcile jobs, preserve subscriptions, and restore last valid mapping/template.

    ## 33. Acceptance criteria

    - Alerts are scoped, safe and storm-controlled.
- Tracking degradation/restoration is understandable.
- No raw source detail leaks.
- Delivery history is auditable.

    ## 34. Definition of Done

    Monitoring preferences, jobs, APIs, UI, tests, docs and rollback are complete with no critical privacy/storm blocker.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release the next dependency-clean CPL task. Prompt 327 alone may close Phase 8.
