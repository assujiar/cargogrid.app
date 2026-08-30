# Prompt 305 — Customer Portal Tracking from Canonical Multi-Source Projection

**Prompt ID:** `CG-S13-CPL-007`  
**Package document:** `CG-AABPP-CPL-305`  
**Version:** `0.14.0`  
**Runtime build log:** `docs/build-log/phase-08/CPL-305.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S13-CPL-007` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 8 — Customer Portal and Loyalty`; package version `0.14.0`.

## 3. Workstream

Workstream: Portal Operations Visibility; Epic: Customer Tracking; Capability: Tracking; Feature slice: customer-scoped canonical timeline, live-map granularity, freshness and exception visibility; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Build customer tracking only over the sanitized canonical projection produced by Operations/Advanced TMS.

## 5. Business value

Customers receive trustworthy visibility regardless of whether the underlying source is a driver phone, installed device, existing GPS platform, or hybrid.

## 6. Source requirement

CPT-TRK-001..004; revised ATW-226 canonical customer projection. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

CPL-300 and verified Operations/ATW-226/228 tracking contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

CPL-306..308 and customer support flows. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Use customer-scoped read models keyed by tenant/customer/account/site/shipment and canonical event/current-position projection. Never create raw telemetry tables in Phase 8.

## 14. API impact

Provide tracking list/detail/timeline/map-safe APIs with cursor pagination and identical REST/GraphQL policy. APIs must not call provider/device/mobile sources directly.

## 15. UI/UX impact

Timeline, map if entitled, milestone details, exception banners, source freshness/degraded label, ePOD/document actions, and responsive states.

## 16. Security impact

Layer 4 scope is database/service enforced. Hide driver PII, IMEI, SIM, provider IDs, internal route, exact location when policy restricts it, internal exception and source conflict details.

## 17. Performance impact

Selective projections, cursor pagination, bounded map refresh, scoped Realtime, safe caching by customer scope.

## 18. Audit impact

Audit customer tracking access, map access, exports, denials, freshness/source version and support access.

## 19. Data migration impact

Adopt verified canonical projection additively; never import raw position history into portal-owned tables.

## 20. Detailed implementation tasks

- Define customer-visible field/event/location granularity.
- Consume canonical current position and timeline.
- Add freshness/degraded/no-signal states.
- Enforce package entitlement for live map/history.
- Test all underlying source classes without exposing them.

## 21. Main flow

Customer opens tracking and sees authorized shipments, timeline and safe current location derived from canonical Operations data.

## 22. Alternative flow

When data is stale/incomplete, show last trusted update and allow ticket creation; do not fabricate live status.

## 23. Exception flow

Block forged shipment/customer scope, raw-source access, hidden event exposure, stale version, unscanned file, or unsafe map granularity.

## 24. Business rules

- Portal never reads raw mobile/device/provider data.
- Underlying source may be shown only as safe generic label when configured.
- ETA shown only from verified canonical source.
- Customer cannot edit milestones.
- Subscription governs live map/history.

## 25. Validation rules

- Validate customer/account/site/shipment scope, source/config version, field visibility, freshness and file status.
- Reject cross-tenant and unsafe inferred access.

## 26. Access rules

Customer users see effective Layer 4 scope; customer admins manage delegated scope only; internal users retain internal authorization without leaking fields.

## 27. Test data requirement

Tenant A/B, multiple customers/sites, mobile/device/provider/hybrid underlying sources, stale/fallback/no-signal, entitlement on/off, forged IDs.

## 28. Tests to create/update

- Canonical projection contract tests.
- Layer 4 RLS/field/file negative tests.
- REST/GraphQL parity and Realtime scope.
- Browser/accessibility and map-granularity tests.
- High-volume tracking list/history tests.

## 29. Regression tests

Operations/ATW tracking, milestone/exception, public/basic tracking, ePOD/files and portal scope.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Customer tracking field policy, source abstraction, freshness/degraded explanation, entitlement and support runbook.

## 32. Rollback/recovery note

Disable portal projection path, preserve Operations truth, revert compatible policies, and reconcile caches/subscriptions.

## 33. Acceptance criteria

- Tracking uses canonical source ownership.
- All underlying source classes appear consistently.
- No raw source or driver/device detail leaks.
- Customer scope and entitlement pass.

## 34. Definition of Done

Portal tracking APIs/UI/policies/tests/docs/rollback are complete with no critical customer privacy blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean CPL task. Prompt 327 alone may close Phase 8.
