# Prompt 343 — Enterprise Maps, GPS and Telematics Integrations

**Prompt ID:** `CG-S14-IAE-015`  
**Package document:** `CG-AABPP-IAE-343`  
**Version:** `0.15.0`  
**Runtime build log:** `docs/build-log/phase-09/IAE-343.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S14-IAE-015` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 9 — Intelligence, Automation, and Enterprise Expansion`; package version `0.15.0`.

## 3. Workstream

Workstream: Operations Integrations; Epic: Location Providers; Capability: Maps, GPS and Telematics Enterprise Integrations; Feature slice: additional enterprise provider adapters and maps services extending, never replacing, ATW-226; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Add enterprise maps/geocoding/routing and additional approved GPS/telematics provider adapters through the existing Prompt 226 canonical ingestion architecture.

## 5. Business value

Expand integration choices without creating a second telemetry truth or bypassing TMS entitlements, source arbitration, privacy, and customer projections.

## 6. Source requirement

Phase 9 maps/GPS/telematics; revised ATW-226; Integration Hub. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

Verified Phase 5 multi-source telemetry, Phase 8 customer tracking, Platform jobs/secrets, IAE-336 Integration Hub. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

Predictive ETA, route optimization, public APIs/webhooks and enterprise monitoring. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Add provider connection/config/catalog records only where not already owned by Prompt 226/Integration Hub. New adapters map into the existing canonical telemetry contract; no duplicate current-position/history tables.

## 14. API impact

Provide provider setup/test/sync/geocode/route APIs, adapter registration, metering and health. GPS events must enter through ATW-226 adapter interfaces and canonical normalization/arbitration.

## 15. UI/UX impact

Enterprise provider catalogue, setup, mapping, health, usage/cost, schema version, test result and degraded state.

## 16. Security impact

Protect secrets, provider payloads, location/driver data, customer scope and support access. No provider credential in client/log.

## 17. Performance impact

Async sync, rate/backpressure, metering, bounded caches, target-volume tests and no global Realtime.

## 18. Audit impact

Audit provider/version/config, credential lifecycle, test/sync, cost/usage, mapping, canonical outcome and support action.

## 19. Data migration impact

Adopt existing mappings explicitly; no raw history import without retention/dedup/reconciliation.

## 20. Detailed implementation tasks

- Inventory existing ATW-226 adapters and ownership.
- Add only approved enterprise provider/map adapters.
- Reuse canonical telemetry and source arbitration.
- Add metering/health and setup UX.
- Test contract, failure, privacy and non-duplication.

## 21. Main flow

Admin configures an approved provider; adapter validates and maps data into existing canonical telemetry or map/routing contract.

## 22. Alternative flow

If provider unavailable, show degraded status and retain last trusted canonical state; use contract fixtures for implementation verification.

## 23. Exception flow

Block duplicate telemetry roots, provider spoofing, schema drift, credential leak, wrong mapping, rate-limit failure, or direct shipment mutation.

## 24. Business rules

- Prompt 226 remains telemetry source owner.
- Phase 9 adds adapters/enterprise controls, not a second gateway.
- Provider events never overwrite canonical milestones directly.
- Costs are metered where applicable.
- Live provider evidence is optional when unavailable.

## 25. Validation rules

- Validate tenant/scope, provider/config/schema version, mapping, idempotency, rate, retention, compatibility and canonical outcome.
- Reject duplicate ownership or cross-tenant mapping.

## 26. Access rules

Enterprise admins manage provider connections; Operations consumes normalized state; customers see only Phase 8 sanitized projection.

## 27. Test data requirement

Tenant A/B, multiple provider contracts, schema drift, outage, rate limit, credential rotation, mapping collision and cost-meter fixtures.

## 28. Tests to create/update

- Provider adapter contract tests.
- Integration Hub and canonical telemetry tests.
- Secret/RLS/webhook/API negative tests.
- Failure/retry/DLQ/metering tests.
- Browser/accessibility and migration tests.


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

Platform, ATW-226, Customer Portal, Integration Hub, public API/webhook and enterprise monitoring.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Provider catalogue, adapter ownership, credential rotation, schema drift/outage, metering and canonical-data-flow docs.

## 32. Rollback/recovery note

Disable affected adapter, revoke credentials, pause jobs, preserve canonical truth, reconcile queued events and restore last trusted config.

## 33. Acceptance criteria

- New adapters reuse canonical telemetry.
- No duplicate gateway/current-position/history exists.
- Security, metering, failure and compatibility gates pass.
- Live provider test may be conditionally skipped.

## 34. Definition of Done

Enterprise adapter code/config/UI/tests/docs/rollback are complete with no critical duplication/security blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean IAE task. Prompt 367 alone may close Phase 9.
