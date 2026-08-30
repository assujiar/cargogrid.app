# Prompt 226 — Multi-Source GPS and Telematics Integration

**Prompt ID:** `CG-S10-ATW-007`  
**Package document:** `CG-AABPP-ATW-226`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-226.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S10-ATW-007` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package version `0.11.0`.

## 3. Workstream

Workstream: Transportation Integration; Epic: Trusted Movement Events; Capability: Multi-Source GPS and Telematics; Feature slice: driver mobile, direct physical device gateway, third-party platform adapters, canonical telemetry and hybrid arbitration; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement all repository-controlled architecture needed to support CargoGrid Mobile Tracking, Direct Fleet GPS, Existing GPS Integration, and Hybrid Tracking under customer subscription entitlements.

## 5. Business value

Customers can track vendor/ad-hoc fleets through driver phones, owned fleets through installed devices, existing fleets through their current GPS platform, or combine sources without changing the canonical TMS workflow.

## 6. Source requirement

OPS-TMS/TRK-001..004; RPD-015/025/033/038; revised ATW-219 binding architecture. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-223, ATW-225, Platform API/webhook/job/PostGIS/entitlement/secrets controls, and an approved initial Teltonika protocol specification. A live third-party provider contract is optional at this checkpoint. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-227..228, ATW-243..248, Customer Portal tracking/monitoring, Enterprise integration hub. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Add additive schemas for:
- tracking entitlements and tenant source policies;
- GPS devices, SIMs, installations, provider connections/mappings, driver-mobile tracking sessions;
- raw-message metadata and controlled raw payload retention;
- normalized canonical telemetry events;
- current authoritative vehicle position;
- position history and route segments;
- source health, source conflicts, source switches, geofence events, and vehicle events;
- idempotency/dedup/order keys, event/received time, accuracy, confidence, and retention class.

Use PostGIS `geography(Point,4326)` for governed spatial values. Keep current position separate from high-volume history. Tenant, vehicle, trip, shipment, leg, source, and version indexes are mandatory.

## 14. API impact

Implement three ingestion modes:

**A. Driver Mobile**
- authenticated HTTPS endpoint used by Driver PWA;
- authorized driver/vehicle/trip/session binding;
- start, heartbeat, location, pause, stop, permission/battery/freshness status;
- server-generated session token and revocation;
- no service credential in the browser.

**B. Direct Device**
- separately deployable always-on `gps-gateway` service;
- raw TCP listener on configurable public ports and static endpoint;
- provider adapter interface with initial Teltonika FMC920/Codec 8 Extended implementation;
- IMEI handshake, length/CRC validation, AVL parsing, IO-element mapping, ACK, reconnect, timeout, malformed/oversized packet rejection;
- durable local/external buffering before downstream processing;
- batch/RPC write to Supabase and safe retry;
- Dockerfile, health/readiness/metrics endpoints, structured logs, secret management, and independent deployment from Vercel.

**C. Third-Party Platform**
- provider-specific webhook/push/poll adapter;
- signature/token validation, schema/version mapping, rate limiting, cursor/watermark, replay, retry, DLQ, and provider outage state;
- deterministic contract fixtures when live provider access is unavailable.

All modes call one canonical normalization and source-arbitration service. REST/GraphQL tracking reads share authorization and field policy. Raw TCP is never handled by a serverless web request.

## 15. UI/UX impact

Build:
- Tenant Admin tracking package and entitlement screen;
- device/SIM/installation/provider mapping administration;
- Driver PWA active-trip tracking start/stop/permission/freshness interface;
- Fleet Control Tower live map and vehicle/trip detail;
- source health, last update, accuracy, conflict, fallback, and offline states;
- bounded route history and event timeline;
- customer-safe preview.

The PWA must state that continuous tracking may stop when the browser closes, the OS suspends the page, permission is revoked, or connectivity fails. Do not claim native-grade background tracking.

## 16. Security impact

- Store all privileged credentials server-side.
- Never place Supabase service-role/database credentials in GPS devices, PWA, or browser.
- Validate tenant/device/session/provider mapping before accepting canonical impact.
- Apply rate, size, socket, replay, and malformed-payload controls.
- Treat IMEI as an identifier, not sufficient strong authentication.
- Support private APN/VPN/device TLS where the selected device/network permits, without making it mandatory for the baseline.
- Minimize driver/location data, enforce purpose/retention, and expose only sanitized customer projections.
- Prevent cross-tenant source mapping and unauthorized source-priority override.

## 17. Performance impact

- Ingest asynchronously and acknowledge devices after safe buffer acceptance, not after all business processing.
- Batch writes and source arbitration.
- Limit Realtime to authorized active vehicles/trips and current-position rows.
- Partition/archive history only after measured need; define retention and aggregation.
- Define target profiles for mobile HTTPS, concurrent TCP sockets, AVL records/sec, provider webhook/poll bursts, hybrid duplicates/conflicts, queue age, ACK latency, projection latency, and recovery backlog.
- Do not use global subscriptions or one database request per IO element.

## 18. Audit impact

Record:
- provider/device/session/config/schema versions;
- connection ID, IMEI/source ID, request or packet hash, auth result, CRC/result, record count;
- recorded time, received time, order/dedup classification;
- mapping, canonical result, source priority/confidence/freshness;
- ACK, queue/batch, retry, DLQ, source switch, geofence, milestone candidate, exception;
- privileged replay, configuration, installation, consent, and retention actions.

Logs and metrics must redact credentials and sensitive raw payloads.

## 19. Data migration impact

Use additive/expand-contract migrations. Do not import raw location history without explicit mapping, consent/legal basis, retention, dedup, load rehearsal, and reconciliation. Existing Phase 3 milestones and assignments remain authoritative. No applied migration edits.

## 20. Detailed implementation tasks

Prompt 220 must decompose this capability into ATW-226A..I.

- **226A:** implement entitlements, package limits, source policy, priority/freshness/accuracy rules.
- **226B:** implement device/SIM/installation/provider/mobile eligibility mappings.
- **226C:** implement Driver Mobile session lifecycle and HTTPS ingestion.
- **226D:** implement always-on GPS Gateway, Teltonika Codec 8E parser, ACK, buffering, Supabase batch ingestion, Docker deployment, health and metrics.
- **226E:** implement third-party provider adapter contract and at least deterministic sandbox/mock contract tests; live provider activation is conditional.
- **226F:** implement canonical telemetry, dedup/order, current position, history, source arbitration, and conflict/fallback.
- **226G:** implement geofence, route deviation, milestone candidate, and exception signals.
- **226H:** implement administration, Fleet Control Tower, live map, timeline, and sanitized projections.
- **226I:** implement load, security, privacy, outage, recovery, deployment, and integrated verification.

A child task is not allowed to mark the parent complete by itself.

## 21. Main flow

A subscribed trip starts with its configured tracking policy. Mobile, direct-device, or provider events are authenticated and mapped, normalized into canonical telemetry, ordered/deduplicated, arbitrated, stored, and projected into current position. Geofence and domain rules create milestone candidates/exceptions; authorized users see live/degraded state.

## 22. Alternative flow

- Use mobile as fallback when a direct device is offline.
- Use an existing provider mapping for customer-owned GPS.
- Run mobile-only for ad-hoc vendor vehicles.
- Run direct-device-only for owned fleet.
- Quarantine unknown device/provider data.
- Replay bounded failed batches after root-cause repair.
- Keep manual operational milestones available when tracking is not subscribed or unavailable.

## 23. Exception flow

Quarantine or reject invalid session, IMEI mapping, CRC, packet size, signature, provider token, duplicate/replay, impossible coordinate, impossible movement, stale/out-of-order conflict, schema drift, unauthorized entitlement, database outage beyond buffer limit, source oscillation, or ambiguous retry. Never silently drop accepted data or fabricate a live position.

## 24. Business rules

- Supported source classes are `DRIVER_MOBILE`, `DIRECT_DEVICE`, and `THIRD_PARTY_PLATFORM`; `HYBRID` is a governed combination.
- Raw telemetry never directly completes a shipment lifecycle.
- All source histories are preserved according to retention policy.
- Canonical current position is selected deterministically.
- Source switches are auditable and cannot oscillate without configured hysteresis.
- Event time and received time are separate.
- Mobile PWA is online-first and active-session based.
- Direct-device gateway is an explicit always-on component.
- Third-party adapters are case-specific.
- Tracking features are entitlement-controlled.
- Customer views never reveal raw device/driver/provider secrets.

## 25. Validation rules

- Validate tenant, entitlement, device/session/provider, vehicle, driver, trip, shipment, leg, source/config/schema version, timestamp, coordinate range, accuracy, event order, idempotency, and retention.
- Reject duplicate current assignment, cross-tenant mapping, stale priority override, malformed protocol frame, or unsupported provider schema.
- Canonical source selection must be reproducible from stored policy and evidence.
- Derived milestone/exception cannot contradict confirmed actual events without review.
- Current position must never move backward to older `recorded_at` merely because it arrived later.

## 26. Access rules

Integration admins manage credentials and mappings; device technicians manage installation evidence; drivers control only their assigned mobile session; Operations sees normalized authorized events; customers see sanitized shipment-level projections; raw payload and driver-sensitive data are restricted. Database/service authorization is mandatory.

## 27. Test data requirement

Create deterministic fixtures for:
- valid/invalid mobile sessions, revoked consent, permission loss, stale heartbeat, low battery;
- Teltonika IMEI handshake, valid/invalid Codec 8E frames, CRC errors, duplicate records, reconnect, buffer/replay, database outage;
- provider signatures/tokens, webhook replay, polling watermark, schema drift, rate limit and outage;
- hybrid conflicts, priority/freshness/accuracy switching, impossible movement;
- Tenant A/B, multiple vehicles/trips, entitlement allow/deny, customer-safe projections and target volume.

## 28. Tests to create/update

- Unit tests for parser, CRC, IO mapping, canonical normalization, dedup/order, arbitration, freshness, conflict and geofence.
- Integration tests for mobile HTTPS, gateway TCP simulator, queue/buffer, Supabase RPC, provider contract fixture, milestone/exception, and Realtime projection.
- Security tests for forged IMEI/session/provider signature, socket/payload abuse, cross-tenant mappings, secret leakage, raw-data access and source-priority override.
- Deployment tests for container build, health/readiness, restart, network configuration, environment validation and rollback.
- Load/soak/failure tests for mobile, sockets, provider bursts and hybrid duplicates.
- Browser/accessibility tests for Driver PWA and Fleet Control Tower.
- Migration, retention, audit and reconciliation tests.


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

Re-run Platform entitlement/Auth/RLS/API/webhook/jobs/PostGIS, Phase 3 assignment/milestone/exception/public tracking, ATW-222 dispatch, ATW-223 resources, ATW-224 planning, ATW-225 orchestration, ATW-228 exceptions, and customer tracking contracts.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Publish:
- architecture and deployment diagram;
- canonical telemetry and arbitration contract;
- Teltonika Codec 8E mapping and gateway configuration;
- Driver PWA tracking guide and limitations;
- device/SIM/installation guide;
- provider adapter onboarding contract;
- security/privacy/retention policy;
- gateway, database, provider and mobile outage runbooks;
- replay/DLQ/reconciliation procedure;
- monitoring dashboard and alerts;
- customer-safe tracking explanation;
- deferred physical-device test procedure.

## 32. Rollback/recovery note

Disable the affected source adapter or entitlement, revoke credentials/session, quarantine queue, preserve accepted evidence, restore last trusted source policy/mapping, reconcile current position and milestones, and replay only bounded verified events. The serverless application must continue operating when the GPS Gateway is disabled.

## 33. Acceptance criteria

- Mobile tracking works through authenticated active sessions.
- Direct-device architecture, container, protocol simulator, parser, ACK, buffering, Supabase ingestion, and recovery pass.
- Provider adapter contract and deterministic fixtures pass; live-provider test may be conditionally skipped.
- Hybrid arbitration is deterministic and auditable.
- Entitlement, tenant isolation, privacy, load, outage and recovery gates pass.
- Physical-device test is honestly deferred when hardware is unavailable.
- No raw telemetry directly mutates shipment truth.

## 34. Definition of Done

All repository-controlled code, migrations, container/deployment definitions, APIs, UI, canonical models, security, tests, observability, documentation, and rollback are complete. Deferred physical-hardware and conditional live-provider evidence are recorded under the approved external-evidence policy. No critical repository-controlled blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-227 or another dependency-clean task after all required ATW-226 child tasks are verified. Prompt 248 alone may close Phase 5.
