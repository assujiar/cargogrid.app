# Prompt 228 — Advanced Milestone and Exception with Multi-Source Telemetry

**Prompt ID:** `CG-S10-ATW-009`  
**Package document:** `CG-AABPP-ATW-228`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-228.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S10-ATW-009` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package version `0.11.0`.

## 3. Workstream

Workstream: Operations Control Tower; Epic: Predictable Network Execution; Capability: Advanced Milestone and Exception; Feature slice: telemetry candidate signals, source confidence/freshness, SLA, recovery and customer-safe projection; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend milestones and exceptions across legs/stages using canonical multi-source telemetry signals without allowing telemetry to become authoritative shipment truth by itself.

## 5. Business value

Give the control tower early, explainable delay and tracking-health signals while preserving human-governed operational truth.

## 6. Source requirement

OPS-TRK-001..004; revised ATW-219/226; Phase 3 milestone/exception contracts. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-225..227, Prompt 226 canonical telemetry, verified Phase 3 milestone/exception contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-243..248, Customer Portal tracking and monitoring. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Extend milestone/exception records with leg/stage, planned/estimated/actual time, source class, source event ID, confidence, freshness, candidate/confirmed state, conflict and recovery metadata.

## 14. API impact

Provide event ingest/reconcile/confirm/suppress/rebaseline/acknowledge/escalate/recover/close operations. Only canonical telemetry candidate signals are accepted, never raw provider/device/mobile payloads.

## 15. UI/UX impact

Control-tower timeline/map/exception queue showing source, freshness, confidence, candidate/confirmed status, conflict, owner, SLA, and recovery.

## 16. Security impact

Internal cause, driver, device, provider, cost and raw telemetry are restricted. Customer projection is allowlisted.

## 17. Performance impact

Index active leg/stage/SLA/source/time; batch dependency impact; bound ETA calculations; selective realtime.

## 18. Audit impact

Audit source event/version, recorded/received time, candidate generation, human confirmation, conflict resolution, source switch, ETA, exception, escalation and recovery.

## 19. Data migration impact

Map existing milestones additively. Historical source classification may remain unknown rather than fabricated.

## 20. Detailed implementation tasks

- Define telemetry candidate-to-domain-event rules.
- Add tracking-health exception taxonomy.
- Implement confidence/freshness/conflict handling.
- Integrate dependency-aware ETA and recovery.
- Add customer-safe projection and tests.

## 21. Main flow

Canonical telemetry produces a validated candidate; domain rules reconcile it with geofence, lifecycle, and confirmed evidence; milestone/exception is created or requires review.

## 22. Alternative flow

Manually confirm uncertain signals, suppress duplicate alerts with reason, switch to fallback source, or rebaseline unstarted milestones.

## 23. Exception flow

Block contradictory terminal event, low-confidence autonomous mutation, stale source, source conflict, duplicate escalation, no-signal storm, or unauthorized customer exposure.

## 24. Business rules

- Event and received time stay separate.
- Raw telemetry cannot complete lifecycle.
- Candidate signals remain distinguishable from confirmed events.
- Source conflict/fallback is visible.
- Customer sees only approved projection.

## 25. Validation rules

- Validate canonical source link, confidence, freshness, geofence, event order, lifecycle compatibility and scope.
- Reject stale/duplicate/conflicting terminal mutation.

## 26. Access rules

Control tower manages internal exceptions; operators confirm scoped candidates; managers approve override; customers see allowlisted status only.

## 27. Test data requirement

Late/duplicate/out-of-order mobile/device/provider events, hybrid conflict, source switch, no signal, ETA cascade, SLA breach, recovery, Tenant A/B.

## 28. Tests to create/update

- Candidate reconciliation and event-order tests.
- Source freshness/confidence/conflict tests.
- ETA/SLA/escalation/recovery tests.
- RLS/field/customer isolation.
- Prompt 226 and customer projection E2E.

## 29. Regression tests

Phase 3 milestone/exception/tracking/ePOD, ATW-225 orchestration, ATW-226 telemetry, capacity, notifications, Finance impacts.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Candidate-event contract, source-confidence taxonomy, tracking exception codes, conflict/no-signal/provider-outage runbook.

## 32. Rollback/recovery note

Disable faulty derived rules, preserve confirmed events, recompute projections, reopen unresolved exceptions, and restore prior source policy.

## 33. Acceptance criteria

- Advanced timeline reconciles to canonical events.
- Telemetry never silently overrides confirmed truth.
- Tracking-health exceptions are actionable and storm-controlled.
- Customer projection is safe.

## 34. Definition of Done

Milestone/exception extensions, services, UI, tests, docs, and recovery are complete without critical event-order or privacy blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean task. Prompt 248 alone may close Phase 5.
