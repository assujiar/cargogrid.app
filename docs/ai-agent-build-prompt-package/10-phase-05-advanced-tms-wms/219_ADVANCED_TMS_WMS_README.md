# Phase 5 — Advanced TMS and WMS Prompt Package

**Document ID:** `CG-AABPP-ATW-219`  
**Version:** `0.11.0`  
**Status:** `FINAL_FOR_RUNTIME_PLANNING`

## 1. Purpose

This directory extends the verified Phase 3 shipment backbone and Phase 4 Finance contracts into multi-leg and multimodal transportation, multi-source fleet visibility, and complete warehouse execution.

The Phase 5 transportation architecture must support three mandatory tracking source classes:

1. `DRIVER_MOBILE` — location sent through the CargoGrid Driver PWA over authenticated HTTPS during an authorized active tracking session.
2. `DIRECT_DEVICE` — location and telematics sent by a physical GPS tracker installed in a vehicle through the separately deployable, always-on CargoGrid GPS Gateway.
3. `THIRD_PARTY_PLATFORM` — location and telematics obtained from an existing GPS/fleet platform through an approved webhook, push API, polling API, or sandbox contract.

`HYBRID` is a governed combination of two or more source classes. All sources converge into one canonical telemetry model while preserving source identity, accuracy, freshness, confidence, event time, received time, raw-evidence policy, entitlement, and deterministic source arbitration.

## 2. Runtime entry gate

Prompt 220 must stop with `PHASE_5_BLOCKED` unless the same checkpoint proves all required Phase 0–4 closure states. The kickoff must reconcile:

- canonical Job Order, Shipment Order, leg, stop, resource assignment, milestone, exception, ePOD, actual-cost, and billing-readiness contracts;
- Supabase/PostgreSQL, PostGIS, Auth, RLS/RBAC, Realtime, jobs, files, API keys, webhooks, feature flags, and entitlement foundations;
- deployment topology for the Next.js application and the new always-on GPS Gateway;
- vehicle, driver, device, SIM, provider, trip, and customer tracking boundaries;
- retention, privacy, consent, security, load, outage, replay, and recovery requirements.

## 3. Capability catalogue

The original capability order remains, including:

- Prompt 223 Fleet and Driver;
- Prompt 225 First-, Middle-, and Last-Mile Orchestration;
- Prompt 226 Multi-Source GPS and Telematics Integration;
- Prompt 228 Advanced Milestone and Exception;
- Prompt 243 High-Volume Controls;
- Prompts 245–248 verification, hardening, documentation, and closure.

## 4. Binding multi-source tracking architecture

### 4.1 Canonical source classes

Every normalized telemetry record must include at least:

- tenant, source class, source/provider/device/session identity;
- vehicle, driver, trip, shipment, leg, and stop linkage where resolved;
- `recorded_at` and `received_at`;
- location, accuracy, speed, heading, movement, and optional telematics;
- validation/auth result, dedup/order classification, source priority, freshness, confidence, and retention class.

Raw telemetry never directly mutates authoritative shipment status. It may generate a candidate signal that is validated, reconciled, and converted into a canonical milestone or exception by domain rules.

### 4.2 Driver mobile mode

The supported baseline is an online-first Driver PWA active-trip tracking session. The system must not claim reliable continuous background tracking after the browser is closed, the OS suspends the page, permission is revoked, or the device is offline. Those conditions must be visible as stale/degraded states.

### 4.3 Direct physical-device mode

The direct-device path must include:

- an always-on, separately deployable GPS Gateway;
- static public network endpoint and configurable raw TCP ports;
- provider-protocol adapter architecture;
- initial Teltonika Codec 8 Extended adapter;
- IMEI handshake, packet length and CRC validation, AVL parsing, ACK, reconnect, timeout, malformed-packet protection, buffering, batch ingestion, health checks, metrics, and structured logs;
- secure batch/RPC ingestion into Supabase;
- no service-role key stored in the GPS device or client application.

The main CargoGrid application may remain serverless. The GPS Gateway is an explicit non-serverless infrastructure component.

### 4.4 Third-party platform mode

Third-party adapters must be case-specific and governed. A universal lowest-common-denominator provider abstraction is forbidden. Each approved adapter declares authentication, schema/version, mapping, rate limits, retention, retry, replay, outage, and cost/usage behavior.

### 4.5 Hybrid source arbitration

Canonical current position and derived tracking state must be selected deterministically using configured policy, including:

- entitlement and active assignment;
- source allowlist and priority;
- event freshness;
- location accuracy and confidence;
- authentication and health;
- impossible movement and conflict detection;
- controlled fallback and source-switch evidence.

No source silently overwrites another source’s history.

### 4.6 Subscription and entitlement

Tracking modes are package-controlled. At minimum support:

- `tracking.mobile_enabled`;
- `tracking.direct_device_enabled`;
- `tracking.third_party_enabled`;
- `tracking.hybrid_enabled`;
- `tracking.customer_live_map_enabled`;
- `tracking.max_active_vehicles`;
- `tracking.location_interval_seconds`;
- `tracking.history_retention_days`.

Unauthorized source modes must be rejected server-side.

## 5. Binding deployment rule

The deployment topology must explicitly separate:

```text
CargoGrid Web/API        → serverless deployment
CargoGrid GPS Gateway    → always-on container/VPS with static endpoint
Supabase                 → PostgreSQL, PostGIS, Auth, Realtime, Storage, RPC/jobs
```

Do not pretend a Vercel Function or ordinary Supabase Edge Function is a permanent raw TCP listener.

## 6. Cross-cutting controls

- Realtime is limited to authorized active trips/vehicles.
- High-volume ingestion uses bounded queues/batches, retry, DLQ, reconciliation, and backpressure.
- Customer views use sanitized canonical projections, never raw device, raw mobile, or provider payloads.
- Device/SIM/installation records are operational assets, not duplicate vendor or HR masters.
- Location and driver data are purpose-bound and retention-controlled.
- No tenant fork, unsupported native/offline claim, false optimality, or autonomous commitment.

## 7. Verification treatment for unavailable external systems

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

## 8. Mandatory evidence

Phase 5 evidence must include:

- entitlement and source-policy enforcement;
- mobile tracking session flow;
- GPS Gateway container build and protocol-simulator evidence;
- canonical telemetry normalization and arbitration;
- geofence, milestone, exception, dispatch-board, route-planning, and customer-projection integration;
- source conflict, stale data, provider outage, database outage, replay, buffering, and recovery;
- target-volume and tenant/customer isolation;
- deferred physical-hardware procedure and conditional provider evidence status.

## 9. Runtime states

`PHASE_5_NOT_STARTED`, `PHASE_5_IN_PROGRESS`, `PHASE_5_BLOCKED`, `PHASE_5_PARTIALLY_COMPLETE`, `PHASE_5_VERIFIED`, `PHASE_5_ROLLED_BACK`.

Only Prompt 248 may set `PHASE_5_VERIFIED`.

## 10. Completion

This package is complete when all revised prompts are reflected in the runtime WBS, Prompt 226 is decomposed into reviewable child tasks, repository-controlled gates pass, external-evidence deferrals are honestly recorded, and no critical unresolved defect remains.
