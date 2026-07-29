# Prompt 226 — Multi-Source GPS, Telematics, Mobile Driver Tracking, and Direct Device Gateway Integration

**Prompt ID:** `CG-S10-ATW-007`  
**Package document:** `CG-AABPP-ATW-226`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-226.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

---

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-007` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.13.0`.

## 3. Workstream

**Workstream:** Transportation Integration  
**Epic:** Trusted Multi-Source Movement Events and Fleet Visibility  
**Capability:** Subscription-Based Mobile GPS, Direct Physical Device, Existing GPS Platform, and Hybrid Tracking Integration  
**Feature slice:** tracking entitlement, driver-mobile location sessions, direct-device gateway, provider-cloud adapters, canonical telemetry, source arbitration, device/SIM provisioning, geofence, tracking projection, operational automation, deployment, observability, privacy, retention, replay, and recovery  
**Atomic task:** `{{WBS_TASK_ID}}`

## 4. Objective

Implement CargoGrid's complete **subscription-based multi-source GPS and telematics architecture** so each tenant can use the tracking method included in its subscribed package.

The implementation must support all of the following schemes through one governed canonical telemetry pipeline:

1. **Driver Mobile GPS Tracking**  
   Location is captured from the driver's authenticated CargoGrid Driver PWA/mobile web session during an assigned active trip and sent to CargoGrid through HTTPS.

2. **Direct Fleet GPS Tracking**  
   A physical GPS tracker installed on a vehicle sends raw device data directly to a separately deployable, always-on **CargoGrid GPS Gateway**.

3. **Existing GPS Platform Integration**  
   CargoGrid receives vehicle location from an approved third-party GPS/fleet platform already used by the customer through authenticated webhook, push API, or bounded polling.

4. **Hybrid Tracking**  
   Two or more approved sources may operate for the same vehicle or trip. CargoGrid must preserve every source event, select the authoritative live projection using deterministic source-priority/freshness/accuracy rules, expose source status, and avoid silently overwriting conflicting evidence.

The first mandatory direct-device adapter is:

- **Teltonika FMC920 4G**;
- Teltonika **Codec 8 Extended**;
- raw TCP connection;
- IMEI handshake;
- AVL packet parsing;
- CRC validation;
- record acknowledgment;
- device session and timeout management.

Teltonika FMC130 or another compatible Teltonika device may reuse the same adapter only when protocol and I/O compatibility are proven by fixture, simulator, or device evidence.

The first mandatory mobile implementation is an authenticated, online-first Driver PWA/mobile web tracking session. Native background tracking may be added only through a separately approved scope. The implementation must explicitly communicate browser/OS limitations when the app is minimized, suspended, closed, denied location access, or battery-restricted.

A webhook-only, polling-only, physical-device-only, mobile-only, mock-only, database-only, or UI-only implementation does **not** satisfy this prompt. All three source schemes and the hybrid arbitration model are mandatory.

## 5. Business value

Provide a flexible tracking product that can be packaged according to the customer's fleet model, existing technology, operating scale, and budget.

CargoGrid must support:

- ad-hoc, rented, or vendor vehicles tracked from the driver's phone;
- customer-owned fleets using GPS devices supplied and installed through CargoGrid;
- customer-owned GPS devices connected directly to CargoGrid when technically approved;
- customers that retain an existing GPS platform and integrate it into CargoGrid;
- hybrid tracking where a physical tracker is primary and the driver's phone is fallback or corroborating evidence;
- automated arrival/departure, geofence, route, freshness, exception, and customer-visibility workflows;
- source-aware historical evidence and operational reconciliation;
- multi-tenant packaging without tenant-specific code forks.

The product must enable package configurations such as:

| Example package | Driver mobile GPS | Direct physical GPS | Existing GPS platform | Hybrid arbitration |
|---|---:|---:|---:|---:|
| Mobile Tracking | Enabled | Disabled | Disabled | Disabled |
| Fleet GPS | Optional | Enabled | Disabled | Optional |
| Existing GPS Integration | Optional | Disabled | Enabled | Optional |
| Enterprise Hybrid Control Tower | Enabled | Enabled | Enabled | Enabled |

Package names and commercial pricing remain configurable product data. The capability must not hard-code the example names above.

## 6. Source requirement

OPS-TMS/TRK-001..004 integration slice; RPD-004/014/015/022/025/033/038; Platform API/webhook/job/PostGIS controls; Phase 3 Shipment Order, lifecycle, assignment, milestone, exception, public tracking, audit, and transaction-lineage contracts.

Cite exact source sections, runtime evidence, ADR/configuration versions, relevant Phase 3/4 contracts, and prerequisite task IDs.

## 7. Current repository context

Record:

- repository root;
- branch and HEAD;
- dirty-worktree ownership;
- active closure IDs;
- existing schema, migrations, contracts, routes, jobs, integrations, tests, and deployment targets;
- current entitlement/subscription architecture;
- current Supabase/PostgreSQL/PostGIS architecture;
- current Next.js/Vercel deployment model;
- current durable-job, API, webhook, audit, RLS, RBAC, and Realtime foundations;
- current driver, vehicle, trip, leg, Shipment Order, customer-tracking, and mobile/PWA foundations;
- last trusted checkpoint.

Explicitly document that the main CargoGrid application may remain serverless while the raw TCP GPS Gateway is a separate always-on service.

Required target topology:

```text
                         ┌──────────────────────────────┐
                         │ Tenant Subscription Package  │
                         │ Entitlements and Limits      │
                         └──────────────┬───────────────┘
                                        │
                 ┌──────────────────────┼──────────────────────┐
                 │                      │                      │
                 ▼                      ▼                      ▼
┌────────────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐
│ Driver Phone GPS       │  │ Physical GPS Device    │  │ Third-Party GPS Cloud  │
│ Driver PWA / HTTPS     │  │ Teltonika / Raw TCP    │  │ Webhook / Push / Poll  │
└────────────┬───────────┘  └────────────┬───────────┘  └────────────┬───────────┘
             │                           │                           │
             │                           ▼                           │
             │              ┌────────────────────────┐               │
             │              │ CargoGrid GPS Gateway  │               │
             │              │ TCP, Codec, ACK, Queue │               │
             │              └────────────┬───────────┘               │
             │                           │                           │
             └───────────────────────────┼───────────────────────────┘
                                         ▼
                         ┌────────────────────────────────┐
                         │ Canonical Telemetry Ingestion │
                         │ Validation, Dedup, Mapping     │
                         └───────────────┬────────────────┘
                                         ▼
                         ┌────────────────────────────────┐
                         │ Source Arbitration and Trust   │
                         │ Priority, Freshness, Accuracy  │
                         └───────────────┬────────────────┘
                                         ▼
                         ┌────────────────────────────────┐
                         │ Supabase PostgreSQL + PostGIS  │
                         │ History, Current Position,     │
                         │ Sessions, Devices, Geofence,   │
                         │ Trip/Leg/Shipment Projections  │
                         └───────────────┬────────────────┘
                                         ▼
          ┌──────────────────────────────┼──────────────────────────────┐
          ▼                              ▼                              ▼
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│ Fleet Control Tower │      │ Driver Tracking UI  │      │ Customer Tracking   │
│ Operations          │      │ Start/Stop/Status   │      │ Permitted Projection│
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
```

All three source types must converge into one canonical event model while preserving their original source identity, trust classification, and raw evidence policy.

## 8. Preconditions

Read:

- `CARGOGRID_CONTEXT.md`;
- `CARGOGRID_BUILD_STATUS.md`;
- `TASK_LEDGER.md`;
- `DECISION_REGISTER.md`;
- `ASSUMPTION_REGISTER.md`;
- `ERROR_LEDGER.md`;
- `KNOWN_ISSUES.md`;
- relevant architecture documents;
- Phase 3 Operations handoff and downstream contracts;
- relevant Platform Core entitlement, API, webhook, durable-job, audit, file, PostGIS, security, configuration, and Realtime documentation;
- current driver/vehicle/trip assignment and PWA/mobile-web contracts;
- Teltonika Codec 8 Extended protocol documentation or approved equivalent device contract;
- at least one approved third-party GPS platform API/webhook contract or a provider-adapter test contract.

Before implementation:

1. inspect the repository and deployment model;
2. identify exact existing canonical tables and services to extend;
3. define the package-entitlement model for mobile, direct-device, provider-cloud, hybrid, limits, retention, and location interval;
4. confirm the initial supported physical device and protocol;
5. confirm the first third-party provider contract or build a provider-adapter seam with a contract fixture that cannot be mistaken for completed provider certification;
6. define Driver PWA location-session behavior, consent, assignment, start/stop, foreground limitations, freshness, and degraded-state behavior;
7. define the public DNS, static-IP, TCP-port, and environment requirements for the gateway;
8. define device/SIM provisioning ownership;
9. define source-priority, trust, freshness, accuracy, conflict, and fallback rules;
10. define retention, sampling, privacy, and customer-visibility policies by source and subscribed package;
11. run feasible baseline gates;
12. state expected files, migrations, services, deployment artifacts, tests, and rollback boundaries;
13. stop on tenant, customer, driver privacy, consent, security, financial, shipment-state, entitlement, or phase-boundary conflict.

## 9. Upstream dependencies

Required upstream dependencies:

- ATW-221 Multi-leg and multimodal shipment;
- ATW-223 Fleet and driver;
- ATW-225 First-, middle-, and last-mile orchestration;
- verified Phase 3 Shipment Order, lifecycle, resource assignment, milestone, exception, public tracking, and transaction-lineage capabilities;
- verified Platform tenant entitlement/subscription, API key, webhook, durable-job, audit, PostGIS, RLS/RBAC, and Realtime controls;
- verified driver identity, vehicle assignment, trip assignment, and online-first PWA/session foundations;
- one approved direct-device contract, with Teltonika FMC920 and Codec 8 Extended as the mandatory initial adapter;
- one approved third-party GPS provider integration contract or contract fixture for the adapter seam;
- approved infrastructure destination for an always-on container with static public IPv4.

Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

Identify and protect downstream impacts to:

- ATW-222 Dispatch Board;
- ATW-224 Route and Load Planning;
- ATW-227 Capacity and Utilization;
- ATW-228 Advanced Milestone and Exception;
- ATW-243 High-volume Operation Controls;
- ATW-245..248 verification, hardening, documentation, and closure;
- tenant subscription, entitlement, usage, and billing-metering contracts;
- Finance profitability or chargeable-event contracts when tracking-derived events are used as evidence;
- Customer Portal tracking contracts;
- Intelligence and Enterprise analytics;
- provider/device/mobile support and incident-response runbooks.

Document affected schemas, services, REST/GraphQL, mobile HTTPS ingestion, TCP gateway, jobs, integrations, files, Finance/portal contracts, tests, docs, infrastructure, product entitlements, and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS, Platform integration, deployment, and authorized shared-infrastructure paths resolved from the repository.

Expected additions may include:

```text
services/
  gps-gateway/
    src/
      server/
      protocols/teltonika/
      devices/
      ingestion/
      processing/
      persistence/
      health/
      observability/
    tests/
    Dockerfile
    package.json
    tsconfig.json

server/
  contracts/
  queries/
  mutations/

app/(tenant)/[tenantSlug]/operations/
  fleet-control-tower/
  gps-devices/
  gps-integrations/
  driver-tracking/
  geofences/
  tracking/

app/(tenant)/[tenantSlug]/driver/
  trips/
  tracking/

supabase/
  migrations/

scripts/
  db-tests/
  gps-simulator/

docs/
  architecture/
  integrations/
  runbooks/
  build-log/phase-05/
```

Resolve exact paths before editing. Normally this task may require more than the generic 5–15 file range because it contains a separately deployable service, database integration, administrative UI, operational UI, simulator, deployment artifacts, tests, and runbooks. Keep changes bounded to this capability.

Use additive migrations. Do not edit applied migrations.

## 12. Forbidden files/folders and forbidden completion shortcuts

Forbidden:

- unrelated domains;
- duplicate Job Order, Shipment Order, Trip, Leg, Vehicle, Driver, milestone, exception, or customer-tracking roots;
- tenant-specific forks;
- direct GPS-to-database credentials embedded in devices;
- browser-side service credentials;
- `service_role` keys in device firmware, frontend bundles, public repositories, logs, or customer-accessible configuration;
- direct raw provider payload mutation of shipment status;
- webhook-only completion;
- polling-only completion;
- a mock TCP server that is not deployable;
- a parser without a real listener and acknowledgment flow;
- an ingestion table without gateway deployment and recovery behavior;
- an Operations map driven only by fabricated fixture data;
- applied-migration edits;
- destructive cleanup;
- hidden test, permission, RLS, audit, or privacy weakening;
- native background-location application or offline synchronization scope expansion unless separately authorized; authenticated Driver PWA/mobile-web tracking is mandatory;
- full Step 11–14 implementation;
- universal GPS-provider abstraction unsupported by real provider evidence;
- production-ready, pilot-ready, or GA claims from this task alone.

The task cannot be marked `VERIFIED` unless Driver Mobile GPS, direct physical-device protocol ingestion, third-party provider integration, entitlement enforcement, and hybrid source arbitration are implemented and proven through the mandatory tests. Direct-device ingestion must be proven with an approved protocol simulator or physical device.

## 13. Mandatory architecture

### 13.1 Supported tracking schemes

Implement all four operating schemes.

#### Scheme A — Driver Mobile GPS Tracking

```text
Authenticated Driver
  → assigned active trip
  → CargoGrid Driver PWA/mobile web
  → browser geolocation permission
  → HTTPS mobile telemetry endpoint
  → canonical telemetry ingestion
```

Mandatory behavior:

- tracking is available only when the tenant package enables mobile tracking;
- the driver must be authenticated and assigned to the relevant vehicle/trip;
- the driver explicitly starts a tracking session and receives a visible active-tracking indicator;
- location events carry driver, session, assigned vehicle, trip, source timestamp, server-received timestamp, accuracy, speed/heading when available, battery when available, permission state, app visibility/state when available, and client schema version;
- the server resolves tenant, vehicle, trip, leg, shipment, and customer mapping;
- the driver can stop tracking only under the configured operational policy, with reason when a mandatory active trip remains unfinished;
- session freshness, permission denial, app suspension, closed browser, lost connectivity, low accuracy, and low battery become explicit degraded states;
- the system must not claim continuous background tracking when the browser/OS does not provide it;
- a future native app may reuse the canonical mobile contract but is not required by this task.

#### Scheme B — Direct Physical GPS Device

```text
GPS Device
  → raw TCP
  → CargoGrid GPS Gateway
  → normalized canonical telemetry
  → Supabase ingestion RPC/job
```

The direct-device implementation is mandatory and must include Teltonika FMC920, Codec 8 Extended, IMEI handshake, packet validation, CRC, ACK, connection lifecycle, durable buffering, and recovery.

#### Scheme C — Existing Third-Party GPS Platform

```text
Customer GPS Device or Smartphone
  → existing GPS/fleet platform
  → authenticated webhook/push API/bounded polling
  → CargoGrid provider adapter
  → normalized canonical telemetry
```

Examples of provider categories include fleet-management platforms, telematics clouds, OEM vehicle clouds, or self-hosted tracking servers. The implementation must not hard-code a universal abstraction or claim certification for a provider without an approved contract and tests.

#### Scheme D — Hybrid Tracking

```text
Physical GPS + Driver Mobile + Third-Party Provider
  → canonical telemetry history
  → deterministic source arbitration
  → one authoritative live projection
```

Hybrid mode must:

- preserve every accepted source event;
- identify `source_type`, `source_id`, `source_priority`, trust classification, freshness, and accuracy;
- select the current authoritative projection using tenant-configured deterministic rules;
- expose the selected source and fallback state to authorized users;
- detect source conflict and prolonged divergence;
- never silently delete, overwrite, or fabricate conflicting source evidence;
- support physical-device primary with mobile fallback, provider primary with mobile fallback, and evidence-only secondary sources;
- prevent two sources from creating duplicate milestone or exception mutations through idempotent canonical derivation.

### 13.2 Subscription and entitlement enforcement

Tracking capability is controlled by tenant subscription entitlements and limits, including at minimum:

```text
tracking.mobile_enabled
tracking.direct_device_enabled
tracking.third_party_provider_enabled
tracking.hybrid_enabled
tracking.customer_live_location_enabled
tracking.max_registered_devices
tracking.max_active_mobile_sessions
tracking.max_active_tracked_vehicles
tracking.history_retention_days
tracking.raw_payload_retention_days
tracking.mobile_interval_seconds
tracking.device_interval_policy
tracking.allowed_provider_codes
tracking.allowed_source_priority_policy
```

Requirements:

- entitlements are server-enforced, not UI-only;
- disabled source types cannot ingest or start new sessions;
- existing history remains governed and readable according to retention/access rules after entitlement downgrade;
- limits produce explicit errors and admin visibility;
- package changes are effective-dated and audited;
- no customer-specific code fork is permitted.

### 13.3 Canonical telemetry contract

Every source must normalize into one versioned contract containing, where applicable:

- tenant-resolved source identity;
- `source_type`: `driver_mobile`, `direct_device`, or `third_party_provider`;
- provider/device/session source ID;
- event ID and idempotency key;
- recorded time and server-received time;
- latitude, longitude, altitude, accuracy, speed, and heading;
- ignition, movement, power, satellites, battery, app/permission state where available;
- raw source schema and adapter version;
- auth/signature/CRC result as applicable;
- trust classification;
- freshness classification;
- mapping outcome;
- duplicate/order classification;
- retention classification;
- canonical trip/leg/shipment linkage after server resolution.

Missing fields from a source remain explicitly unavailable. Do not infer ignition from phone GPS or claim hardware-grade telematics from mobile tracking.

### 13.4 Source arbitration

Implement a versioned, tenant-scoped arbitration policy. A default policy may prefer:

1. fresh, active, directly connected physical GPS;
2. fresh, authenticated approved third-party provider data;
3. fresh driver-mobile data from an active assigned tracking session;
4. manual milestone/location evidence only as a non-live fallback.

The policy must consider:

- entitlement;
- source active status;
- event age/freshness;
- accuracy;
- mapping confidence;
- device/session/provider health;
- configured primary/secondary role;
- suspicious/impossible coordinates;
- divergence from another trusted source;
- trip and assignment effective period.

Arbitration must be deterministic, explainable, versioned, tested, and auditable. Tenant configuration may alter priority within allowed product policy.

### 13.5 CargoGrid GPS Gateway

Build a separately deployable service that:

- runs continuously outside the Vercel/serverless request lifecycle;
- is containerized with Docker;
- listens on configurable TCP host and port;
- supports static public IPv4 and DNS such as `gps.cargogrid.net`;
- accepts multiple concurrent device connections;
- performs IMEI handshake and registered-device validation;
- handles TCP fragmentation and packet reassembly;
- parses Teltonika Codec 8 Extended AVL records;
- validates preamble, data length, codec, record count, and CRC;
- sends protocol-correct acknowledgment;
- applies socket idle timeout and maximum-packet protection;
- converts records into the shared canonical telemetry schema;
- durably buffers validated records before acknowledgment or uses an equivalent loss-controlled boundary;
- batches database writes;
- retries transient failures with bounded exponential backoff;
- quarantines permanently invalid or unmapped records;
- exposes health, readiness, and metrics endpoints;
- supports graceful shutdown without silently dropping acknowledged records;
- emits structured logs and correlation IDs;
- has a documented deployment and rollback procedure.

### 13.6 Serverless boundary

The CargoGrid web application, authenticated mobile-web ingestion endpoint, provider webhook APIs, Supabase services, and customer portal may remain serverless.

The raw TCP gateway is a deliberate always-on infrastructure component. Do not run the TCP listener as a Vercel Function, browser process, normal Supabase Edge Function, or request-scoped server action.

### 13.7 Initial device protocol

The initial direct-device adapter must support:

- Teltonika FMC920 4G;
- Codec 8 Extended;
- IMEI registration handshake;
- AVL packet decoding;
- timestamp and priority;
- longitude and latitude;
- altitude;
- heading/angle;
- satellite count;
- speed;
- event I/O ID;
- total I/O count;
- supported ignition/movement/external-power parameters;
- CRC validation;
- server acknowledgment;
- multiple records in one packet;
- duplicate packet and record classification;
- delayed records after signal recovery;
- device reconnect and session replacement.

Maintain a documented I/O mapping table by device model and firmware/configuration profile. Unknown I/O elements must be preserved in bounded raw metadata where policy permits and must not silently change canonical operational state.

## 14. Database impact

Add or extend canonical structures for, at minimum:

### 14.0 Tracking subscription, entitlement and usage

Add or extend:

- tenant tracking entitlement definitions;
- effective-dated package assignment;
- source-type enablement;
- device/session/vehicle limits;
- retention and sampling limits;
- provider allowlist;
- hybrid/source-priority policy assignment;
- usage counters and limit evidence;
- audited entitlement changes.

### 14.1 Device inventory and provisioning

- `gps_devices`;
- manufacturer, model, protocol and firmware;
- IMEI and serial number;
- tenant ownership;
- vehicle/resource assignment;
- status lifecycle;
- installed/activated/retired timestamps;
- last connection and last valid record timestamps;
- device configuration profile;
- assignment and installation history.

### 14.2 SIM management

- `gps_device_sims` or an approved shared SIM resource model;
- ICCID;
- MSISDN where permitted;
- operator;
- APN profile;
- activation and suspension state;
- masked display and restricted access;
- subscription ownership and lifecycle;
- no credential leakage.

### 14.3 Device configuration profiles

- provider/protocol;
- target host/domain;
- port;
- codec;
- moving interval;
- stopped interval;
- ignition-off interval;
- event priorities;
- optional I/O mappings;
- version and effective dates;
- immutable historical snapshot on assignment where required.

Do not implement remote configuration or FOTA unless the approved Teltonika management contract is available. When unavailable, provide configuration-profile governance and manual provisioning evidence without a fake remote-control action.

### 14.4 Connection state

- active/last connection evidence;
- gateway instance;
- connected/disconnected timestamps;
- last packet and last acknowledgment;
- disconnect reason where available;
- current online/offline/degraded projection;
- no claim that a TCP socket alone proves vehicle movement or driver identity.

### 14.5 Raw and normalized telemetry

Add:

- provider/device source ID;
- gateway receive ID;
- event time;
- server received time;
- sequence/order classification;
- location;
- accuracy where available;
- speed;
- heading;
- altitude;
- satellites;
- ignition;
- movement;
- external power;
- event I/O ID;
- normalized I/O values;
- packet hash;
- protocol and schema version;
- auth/CRC result;
- mapping outcome;
- dedup status;
- processing status;
- retention classification.

### 14.6 Current position and history separation

Maintain separate projections:

- one current/last-known position per vehicle or active resource;
- append-oriented position history;
- raw packet evidence under explicit retention;
- device event history;
- connection-state history.

Do not query full history to render a live map.

### 14.7 Canonical linkage

Link normalized events to authorized canonical records:

- tenant;
- company/branch where applicable;
- device;
- vehicle;
- driver assignment where active and authorized;
- trip;
- shipment leg;
- Shipment Order;
- Job Order where derived through shipment lineage;
- geofence;
- milestone;
- exception;
- customer tracking projection.

The server resolves these mappings. Never trust tenant, vehicle, trip, shipment, or customer IDs supplied by an untrusted device payload.

### 14.8 Spatial controls

Use PostGIS for:

- current point;
- position history point;
- circular geofences;
- polygon geofences;
- distance and route-deviation calculations where required;
- tenant-aware spatial indexes;
- deterministic coordinate validation.

### 14.9 Driver mobile tracking sessions

Add at minimum:

- `driver_tracking_sessions` or an approved canonical equivalent;
- tenant, driver, vehicle, trip and assignment linkage;
- session token/identity binding without storing reusable secrets in public data;
- started, paused/degraded, stopped, expired and revoked states;
- start/stop actor, timestamps and reason;
- consent and location-permission evidence;
- last mobile event and freshness;
- client/app/schema version;
- battery and app/permission state where available;
- entitlement snapshot;
- no active session outside an authorized effective driver/vehicle/trip assignment.

### 14.10 Third-party provider integrations

Add at minimum:

- provider integration definition;
- tenant/provider account mapping;
- credential reference stored server-side;
- webhook/poll mode;
- provider vehicle/device identifier mapping;
- schema/adapter version;
- health, last success and failure state;
- rate-limit and cursor/checkpoint state where polling is used;
- mapping history and reconciliation evidence.

### 14.11 Source arbitration and authoritative projection

Add:

- versioned source-priority policies;
- per-vehicle/trip source-role assignment where configured;
- selected authoritative source and selection reason;
- freshness and health projection for every active source;
- source conflict/divergence events;
- fallback transition history;
- no destruction of non-selected source history.

### 14.12 Ingestion contract

Create a versioned, idempotent batch ingestion RPC or approved server-side database contract that:

1. resolves source identity as driver-mobile session, direct device, or third-party provider mapping;
2. verifies tenant entitlement, package limit, source state, assignment, consent where applicable, and tenant state;
3. deduplicates records;
4. inserts append-oriented source history;
5. evaluates source trust, freshness, accuracy, and arbitration policy;
6. conditionally upserts the authoritative current position only when deterministic arbitration permits it;
7. preserves late, out-of-order, non-authoritative, and conflicting records as history;
8. resolves active trip/leg/shipment mapping;
9. emits or queues geofence evaluation;
10. emits or queues milestone/exception processing exactly once;
11. updates device, provider, mobile-session, and source freshness projections;
12. returns an explicit per-record outcome and source-selection result;
13. records audit and operational evidence.

Database credentials used by the gateway must be server-only and least-privileged. Prefer a gateway-specific role or narrowly scoped RPC over unrestricted database access.

## 15. API and service impact

Implement:

### 15.1 Driver mobile HTTPS interface

- authenticated start-tracking command;
- authenticated mobile telemetry batch endpoint;
- heartbeat/freshness update;
- pause/degraded/stop/revoke flow;
- assignment and entitlement validation;
- consent and permission-state evidence;
- payload schema/version validation;
- rate, batch-size and timestamp limits;
- idempotency and replay protection;
- explicit response containing accepted/rejected event outcomes and current session state.

### 15.2 Direct-device TCP interface

- configurable TCP listener;
- Teltonika handshake;
- Codec 8 Extended packet processing;
- protocol acknowledgment;
- device session lifecycle;
- packet size and timeout controls;
- bounded connection concurrency;
- structured protocol errors.

### 15.3 Third-party GPS platform interface

- provider-specific authenticated webhook, push API, or bounded polling adapter;
- signature, token, OAuth, or approved provider-auth validation;
- replay window;
- rate limit;
- schema-version validation;
- checkpoint/cursor handling for polling;
- provider vehicle/device mapping;
- one canonical normalization contract shared with mobile and direct-device modes.

### 15.4 Internal canonical telemetry and arbitration service

One shared service must govern:

- normalization;
- validation;
- entitlement enforcement;
- deduplication;
- ordering;
- mapping;
- trust classification;
- source arbitration;
- persistence;
- geofence evaluation;
- derived milestone/exception signals;
- freshness projection;
- customer-safe projection.

### 15.5 CargoGrid application APIs

Expose authorized REST and GraphQL contracts from shared services for:

- package entitlement and tracking-usage administration;
- driver tracking-session status;
- device administration;
- device/vehicle assignment;
- SIM and configuration status;
- third-party provider integration and mapping;
- source-priority policy;
- current authoritative position and selected-source explanation;
- source-health comparison;
- active fleet map;
- trip route history;
- event timeline;
- geofence administration;
- alert and exception review;
- gateway/provider/mobile-session health summary;
- customer-safe shipment tracking.

REST and GraphQL must share authentication, authorization, field policy, idempotency, audit, pagination, filtering, and version semantics.

Do not expose raw credentials, raw full provider payload, unmasked SIM data, unrestricted driver movement history, or cross-customer source information.

## 16. UI/UX impact

Implement complete user-facing surfaces with loading, empty, error, success, permission-denied, stale, offline, degraded-mobile, degraded-device, degraded-provider, source-conflict, fallback, entitlement-limit, and partial-data states.

### 16.0 Tracking Package and Entitlement Administration

Required capabilities:

- display effective tracking package and enabled source types;
- display device, session, tracked-vehicle, retention, and provider limits;
- show current usage against limits;
- show source-priority/hybrid policy;
- prevent unsupported actions with explicit entitlement reason;
- preserve audit and effective-date history.

### 16.1 GPS Device Management

Required capabilities:

- register device by IMEI;
- manufacturer/model/protocol;
- assign and reassign vehicle;
- assign SIM;
- select configuration profile;
- record installation;
- activate, suspend, maintain, replace, and retire;
- show last connection and last valid GPS record separately;
- show firmware/configuration metadata;
- show assignment and installation history;
- prevent destructive deletion of used device history by normal roles.

### 16.2 SIM Management

Required capabilities:

- register ICCID and operator;
- masked data display;
- device assignment;
- active/suspended/replaced status;
- subscription and ownership evidence;
- restricted permission surface.

### 16.3 Third-Party GPS Integration Management

Required capabilities:

- register an approved provider integration;
- select webhook/push/poll mode where supported;
- store credentials through a server-only secret flow;
- map provider vehicles/devices to CargoGrid vehicles;
- show provider health, last success, schema version, rate limit and mapping errors;
- quarantine/replay bounded failed events;
- prevent false certification or unsupported-provider claims.

### 16.4 Driver Mobile Tracking

Required driver experience:

- display assigned active trip and vehicle;
- show whether the tenant package permits mobile tracking;
- request location permission with clear explanation;
- start tracking explicitly;
- show tracking-active indicator, last successful send, accuracy, connectivity and battery when available;
- show degraded state when location permission is denied, browser is suspended, data is stale, accuracy is poor, internet is unavailable, or the session is revoked;
- stop tracking with configured reason/authorization rules;
- prevent tracking an unassigned vehicle or trip;
- never imply background continuity that the browser cannot guarantee.

Required operations experience:

- see active mobile sessions;
- see driver, vehicle, trip, freshness and permission/app state;
- revoke a compromised or incorrect session;
- distinguish mobile tracking from physical-device tracking.

### 16.5 Fleet Control Tower

Required capabilities:

- authorized live fleet map;
- moving, stopped, idle, offline, stale, and degraded states;
- active trip, leg, shipment, driver, and vehicle context;
- last event time versus received time;
- speed, heading, ignition, and freshness;
- geofence status;
- route deviation where route geometry exists;
- ETA only when supported by an explicit deterministic rule or approved service;
- alert/exception queue;
- current authoritative source and reason;
- health/freshness of available secondary sources;
- fallback and source-conflict indicator;
- selective Realtime subscription limited to active authorized vehicles or shipments.

### 16.6 Vehicle Tracking Detail

Display:

- current location;
- last update and freshness;
- active assignment;
- trip and shipment context;
- route history for a bounded period;
- stop and idle history;
- speed history where authorized;
- device, provider, mobile-session and source-selection status;
- comparison of accepted source events where authorized;
- geofence events;
- milestone and exception timeline;
- raw provider payload only to a separately authorized integration-support role, when retention permits.

### 16.7 Geofence Management

Support:

- pickup;
- transfer;
- port;
- airport;
- depot;
- warehouse;
- branch;
- customer destination;
- circular and polygon areas;
- effective status;
- authorized tenant/company/branch scope;
- duplicate and overlap warnings without inventing business meaning.

### 16.8 Customer tracking

Customer-facing tracking may show only:

- permitted shipment status;
- customer-visible milestones;
- bounded current location or route progress when tenant policy allows;
- ETA when authorized and supported;
- exception messaging approved for customer display;
- ePOD availability under existing customer-document controls.

Never expose unrelated vehicle history, driver identity, device IMEI, SIM data, exact private stops, raw telemetry, or another customer's shipment.

### 16.9 Accessibility and interaction

All surfaces must be responsive online-first PWA, keyboard accessible, properly labeled, focus-managed, and free of dead actions. Include unsaved-change protection for entitlement, provider, device, SIM, configuration, geofence, assignment, and source-priority forms.

## 17. Security impact

Implement:

- server-only gateway and provider credentials;
- authenticated driver-mobile sessions tied to active driver/vehicle/trip assignments;
- explicit mobile location permission and consent evidence;
- mobile-session revocation and expiry;
- entitlement and package-limit enforcement on every ingestion path;
- no credential embedded in physical device beyond its required server target and provider-supported authentication configuration;
- registered IMEI/device validation;
- tenant and resource mapping enforced server-side;
- least-privileged gateway database role or RPC;
- per-device and per-IP connection/rate controls where feasible;
- malformed-packet limits;
- replay and duplicate detection;
- impossible-coordinate, suspicious jump, timestamp, speed, and source-divergence sanity checks;
- maximum future/past timestamp policy;
- device reassignment protection;
- audit of privileged mapping, replay, suspension, replacement, and retention actions;
- restricted driver location, consent, mobile-session, device, provider, and SIM data;
- RLS/RBAC, company/branch/customer-owner, field and record policies;
- encrypted transport for HTTP provider integrations;
- protected infrastructure secrets;
- firewall limiting exposed ports;
- health endpoint isolation or authentication where appropriate;
- private APN/VPN support as optional deployment hardening, not a fabricated default;
- RPD-022 risk disclosure without any tamper-proof or immutable-for-all claim.

IMEI alone must not be represented as cryptographically strong authentication. Browser/mobile GPS must not be represented as hardware-grade or tamper-proof location evidence. Third-party provider data inherits the assurance limits of its provider contract. Document its role as device identity and combine it with registered mapping, network controls, protocol validation, and tenant isolation.

## 18. Performance and scalability impact

### 18.1 Event-rate assumptions

Define and test explicit scenarios, including at minimum:

- 100 concurrent mixed tracking sources;
- 1,000 concurrent mixed tracked vehicles or an evidence-backed bounded equivalent;
- driver-mobile intervals governed by entitlement and browser capability;
- physical-device moving interval between 15 and 30 seconds;
- stopped interval between 3 and 5 minutes;
- reconnect burst after cellular outage;
- multiple AVL records in one packet;
- delayed and out-of-order replay;
- mobile reconnect burst, provider outage, gateway outage, and Supabase slowdown.

Do not fabricate a capacity claim without test evidence.

### 18.2 Gateway behavior

- parse and validate before expensive processing;
- acknowledge only after the record reaches the defined loss-controlled buffer boundary;
- batch writes;
- apply bounded backpressure;
- cap active connections and packet size;
- use graceful shutdown;
- avoid one database request per individual point where batching is feasible;
- avoid logging every coordinate at normal production log level;
- separate protocol receipt from business-event processing.

### 18.3 Database behavior

- tenant-aware indexes;
- composite indexes on device/vehicle and recorded time;
- PostGIS indexes where measured and justified;
- current-position table separated from history;
- cursor pagination for history;
- date-based partitioning or equivalent strategy after measured need;
- retention and aggregation jobs;
- no `SELECT *`;
- no browser-loaded full history;
- selective Realtime only;
- query and load evidence before/after.

### 18.4 Durable processing

Use the existing PostgreSQL durable-job framework where suitable for downstream processing across all sources, including:

- geofence evaluation;
- milestone derivation;
- exception generation;
- retention;
- aggregation;
- replay;
- reconciliation.

The durable-job framework does not replace the raw TCP listener or gateway buffer.

## 19. Audit and observability impact

Record:

- gateway instance and version;
- protocol adapter and version;
- device configuration profile version;
- IMEI/device mapping;
- connection ID;
- packet hash;
- auth/handshake/CRC result;
- event count;
- event and received time;
- duplicate/order classification;
- canonical mapping;
- database outcome;
- ACK outcome;
- retry, quarantine, replay, and DLQ outcome;
- privileged actor/context;
- before/after for device, SIM, vehicle assignment, configuration, and geofence changes;
- correlation and idempotency key.

Implement at minimum:

```text
GET /health
GET /ready
GET /metrics
```

or repository-equivalent endpoints.

Metrics must cover:

- active device connections;
- active driver-mobile tracking sessions;
- active third-party provider integrations;
- accepted and rejected connections;
- known and unknown IMEIs;
- rejected mobile sessions and entitlement-limit failures;
- provider auth/schema/rate failures;
- packets and AVL records per minute;
- malformed packet count;
- CRC failures;
- ACK failures;
- parser latency;
- ingestion latency;
- database failure and retry count;
- buffer or queue depth;
- oldest unprocessed record age;
- quarantined record count;
- offline/stale devices, stale mobile sessions, and degraded providers;
- source fallback and conflict counts;
- last successful database ingestion;
- process CPU, memory, file descriptors, and restart count where infrastructure supports them.

Do not log service credentials, complete SIM identifiers, or unrestricted raw location history.

## 20. Data migration impact

No raw GPS history import without explicit:

- provider/device mapping;
- tenant and vehicle ownership;
- schema version;
- event/received-time semantics;
- deduplication rule;
- retention rule;
- privacy classification;
- load rehearsal;
- reconciliation report;
- rollback strategy.

Use additive or expand-and-contract migrations. Never edit an applied migration.

Device reassignment must not rewrite historical vehicle or shipment linkage. Corrections use governed, audited mapping or reconciliation records.

## 21. Detailed implementation tasks

1. Confirm and document the multi-source architecture, product-entitlement model, and serverless/always-on boundary.
2. Define tracking entitlements, package limits, effective dates, usage counters, retention, and source-priority policy.
3. Define one versioned canonical telemetry contract for driver mobile, direct physical device, and third-party provider sources.
4. Implement driver-mobile tracking sessions, assignment checks, consent/permission evidence, start/heartbeat/batch/stop/revoke APIs, freshness, and degraded states.
5. Confirm Teltonika FMC920, Codec 8 Extended, TCP, IMEI handshake, packet, CRC, ACK, and I/O mapping requirements.
6. Create the separately deployable `gps-gateway` service.
7. Implement TCP listener, connection lifecycle, framing, parser, CRC, ACK, timeout, packet-limit, and graceful-shutdown behavior.
8. Implement registered-device validation and least-privileged Supabase ingestion.
9. Implement durable loss-controlled gateway buffering, batching, retry, quarantine, and bounded replay.
10. Implement at least one approved third-party provider adapter through webhook/push/polling and the provider integration/mapping lifecycle.
11. Add device, SIM, configuration-profile, installation, assignment, provider, mobile-session, connection-state, raw-message, normalized-event, current-position, source-health, position-history, arbitration, and vehicle-event structures.
12. Add the canonical batch ingestion RPC or equivalent database contract.
13. Implement deterministic source arbitration, fallback, divergence detection, and authoritative-position projection.
14. Integrate vehicle, driver, trip, leg, Shipment Order, milestone, exception, public tracking, and transaction-lineage projections.
15. Implement geofence entry/exit with deterministic event ordering, source-aware idempotency, and anti-flapping controls.
16. Implement entitlement, provider, device, SIM, configuration, installation, and source-priority administration.
17. Implement Driver Mobile Tracking UI, operations session monitoring, Fleet Control Tower, vehicle tracking detail, geofence management, and customer-safe projections.
18. Implement selective Supabase Realtime for authorized active projections without global subscriptions.
19. Add Dockerfile, environment contract, static-IP/DNS/port runbook, health/readiness/metrics, and deployment documentation for the gateway.
20. Add deterministic Teltonika protocol simulator, recorded binary fixtures, mobile-source simulator, and provider contract fixtures.
21. Execute mobile, provider, parser, TCP, ACK, reconnect, replay, outage, privacy, entitlement, arbitration, RLS/RBAC, load, and end-to-end tests.
22. Reconcile every tracking-derived milestone or exception against authoritative operational state.
23. Update architecture, API, schema, data-flow, threat model, deployment, subscription, support, and incident-response documentation.
24. Record exact rollback and recovery steps for each source mode and hybrid arbitration.

## 22. Main flows

### 22.1 Driver Mobile GPS flow

```text
1. Tenant package enables Driver Mobile GPS.
2. Driver authenticates and opens an assigned active trip.
3. CargoGrid verifies driver, vehicle, trip, entitlement and active-session limit.
4. Driver grants location permission and explicitly starts tracking.
5. CargoGrid creates an effective tracking session and returns its safe session contract.
6. Driver PWA sends idempotent HTTPS location batches with event and received-time semantics.
7. Server validates session, entitlement, assignment, coordinates, accuracy and schema.
8. Canonical ingestion stores source history and evaluates source arbitration.
9. Current position updates only when the mobile source is authoritative under policy.
10. Fleet Control Tower shows mobile source, freshness, accuracy and degraded state.
11. Geofence/milestone/exception processing runs idempotently.
12. Driver or an authorized operator stops/revokes the session; history remains preserved.
```

### 22.2 Direct Physical GPS flow

```text
1. Device powers on and connects to CargoGrid GPS Gateway.
2. Gateway reads and validates IMEI.
3. Gateway verifies registered active device, entitlement and mapping.
4. Gateway accepts or rejects the device using protocol-correct handshake response.
5. Device sends one or more Codec 8 Extended AVL records.
6. Gateway reassembles the TCP frame and validates structure and CRC.
7. Gateway normalizes records into the canonical telemetry contract.
8. Gateway durably buffers validated records.
9. Gateway sends the protocol-correct record-count acknowledgment.
10. Gateway batches records into the Supabase ingestion contract.
11. Database resolves tenant, vehicle, active trip, leg and shipment mapping.
12. Source history is appended and arbitration selects the authoritative projection.
13. Geofence and downstream operational processing run idempotently.
14. Authorized Realtime projections update tracking surfaces.
```

### 22.3 Existing GPS Platform flow

```text
1. Tenant package enables an approved provider code.
2. Integration administrator configures server-only credentials and maps provider units to CargoGrid vehicles.
3. Provider sends an authenticated webhook/push event or CargoGrid performs bounded polling.
4. Adapter validates auth, rate, schema, cursor/replay and provider identifiers.
5. Adapter normalizes data into the shared canonical telemetry contract.
6. Canonical ingestion stores source history and evaluates arbitration.
7. Provider health, mapping, failures and freshness remain visible and auditable.
```

### 22.4 Hybrid flow

```text
1. Two or more entitled sources send events for the same active vehicle/trip.
2. CargoGrid stores every accepted source event separately.
3. Arbitration evaluates configured priority, freshness, accuracy, health and mapping confidence.
4. One source becomes the authoritative current-position source.
5. Secondary sources remain visible as corroborating, fallback or conflicting evidence.
6. Source change/fallback is effective-dated, explained and audited.
7. Canonical milestone/exception derivation remains idempotent across source changes.
```

## 23. Alternative flows

### 23.1 Driver phone suspended or permission revoked

Mark the mobile source degraded/stale, notify the driver and authorized operations users, retain the last valid point, and select another fresh entitled source when hybrid policy permits. Do not fabricate continued tracking.

### 23.2 Driver phone offline

Queue only within the explicitly supported client behavior, preserve recorded and received times, send after reconnect when feasible, and classify delayed records. Browser offline synchronization is not implied or required beyond the implemented contract.

### 23.3 Cellular outage on physical device

The device sends stored historical records after connectivity returns. CargoGrid classifies them as delayed and does not replace a newer authoritative current position.

### 23.4 Third-party provider outage or API rate limit

Mark provider health degraded, preserve the last valid provider event, use another entitled fresh source when hybrid policy permits, and retry/poll under bounded provider-specific rules.

### 23.5 Supabase outage

The gateway and provider/mobile ingress continue only within their defined durable or bounded buffer capacity, apply backpressure, record degraded status, retry safely, and do not claim successful persistence beyond the established loss-controlled boundary.

### 23.6 Unknown device, session, or provider unit

Quarantine or reject the event, record minimal security evidence, and never create tenant, vehicle, driver, trip, or shipment mapping automatically.

### 23.7 Manual mapping correction

An authorized administrator corrects a device, provider-unit, or mobile assignment mapping with a mandatory reason. History remains preserved and projections are reconciled through an explicit job or governed correction.

### 23.8 Bounded replay

An authorized administrator replays quarantined or failed canonical records after root-cause repair using an idempotent, bounded, fully audited command.

### 23.9 Entitlement downgrade

Stop new source sessions/connections or provider ingestion according to effective policy, preserve existing governed history, display the change, and avoid destructive deletion. Device connection handling and grace behavior must be explicit and tested.

## 24. Exception flow

Handle and record:

- disabled or exceeded subscription entitlement;
- driver not assigned to vehicle/trip;
- mobile session expired, revoked, duplicated or conflicting;
- mobile permission denied;
- mobile app/browser suspended, closed or stale;
- low mobile accuracy, suspicious jump, impossible speed or timestamp;
- invalid or unknown IMEI;
- malformed handshake;
- incomplete TCP frame;
- packet too large;
- unsupported codec;
- record-count mismatch;
- CRC failure;
- inactive/suspended/retired device;
- device assigned to conflicting active vehicles;
- invalid provider signature/token/OAuth state;
- provider unit unmapped;
- provider schema drift;
- provider cursor/replay/rate-limit failure;
- invalid coordinate;
- stale, duplicate or out-of-order record;
- mapping ambiguity;
- source divergence or oscillating fallback;
- gateway overload;
- Supabase timeout or failure;
- buffer exhaustion;
- retry exhaustion;
- DLQ/quarantine growth;
- geofence evaluation failure;
- derived milestone contradiction;
- tenant, company, branch, customer-owner, trip, leg or shipment mismatch;
- unauthorized raw-location access;
- device power loss, disconnection or prolonged offline state.

Record blocker/error/issue, preserve bounded evidence, identify the last trusted checkpoint, and provide an exact safe resume point. Never hide or bypass failure.

## 25. Business rules

- All three tracking sources are mandatory product capabilities: driver mobile, direct physical device, and third-party GPS platform.
- Hybrid arbitration is mandatory when more than one source is enabled for a vehicle or trip.
- Source availability is controlled by effective tenant subscription entitlements and server-enforced limits.
- Teltonika FMC920 with Codec 8 Extended is the initial required direct-device adapter.
- Driver mobile tracking requires authentication, active assignment, explicit session start, permission evidence, and visible tracking state.
- Driver mobile GPS is not represented as ignition, tamper-proof, or hardware-grade telematics.
- Third-party provider data is accepted only through an approved provider adapter and mapped source identity.
- Raw source records never directly mutate shipment lifecycle state.
- Canonical rules decide current position, milestone, geofence, exception, and customer-visible projections.
- `recorded_at` and `received_at` are distinct for every source.
- A delayed point cannot replace a newer authoritative position unless an explicit correction process proves the newer point invalid.
- Duplicate and out-of-order data are preserved or classified, not silently overwritten.
- Device, provider-unit, and mobile-session assignments are effective-dated and do not rewrite prior history.
- One physical device cannot be actively assigned to conflicting vehicles.
- One driver cannot have conflicting active tracking sessions beyond an explicitly approved multi-trip rule.
- One vehicle may have multiple sources only under a versioned primary/secondary/evidence policy.
- Tenant, vehicle, driver, trip, leg, shipment, and customer mapping is server-resolved.
- Source arbitration is deterministic, explainable, versioned, auditable, and stable under replay.
- GPS-derived arrival/departure is evidence, not an unrestricted lifecycle override.
- Geofence signals use deterministic event ordering and hysteresis/tolerance to prevent boundary flapping.
- Customer location visibility is entitlement-controlled, tenant-configurable, and record-scoped.
- Retention is versioned, auditable, source-aware, and privacy-aware.
- Exact financial or inventory changes never occur directly from raw telemetry.
- No tenant fork, autonomous AI commitment, unsupported background-tracking claim, tamper-proof claim, or partial-GA claim.

## 26. Validation rules

Validate:

- effective tracking entitlement and source limit;
- driver authentication, assignment, session, consent and permission state;
- mobile client/schema version, session ID and idempotency key;
- IMEI format and registration;
- active device status;
- provider authentication, provider-unit mapping, schema and cursor/replay state;
- protocol and codec;
- packet structure;
- CRC;
- record count;
- event and received time;
- coordinate ranges;
- accuracy, suspicious jump and impossible-speed policy;
- optional altitude, heading, satellites, power, ignition, movement, battery and app-state values;
- source/configuration/adapter version;
- duplicate and ordering classification;
- trust and freshness classification;
- tenant/resource mapping;
- active assignment effective period;
- trip/leg/shipment mapping;
- source-priority and arbitration outcome;
- divergence and fallback rules;
- geofence configuration and scope;
- retention and privacy classification;
- stale concurrent mutation;
- permitted customer projection;
- batch size and payload limits;
- gateway/provider/mobile/database outcome consistency;
- ACK count equals accepted protocol record count under the documented gateway boundary.

Reject tenant, company, branch, warehouse, customer-owner, driver, session, device, vehicle, provider, source, config, version, trip, leg, shipment, entitlement, or assignment mismatch.

Every external event and privileged action must be authorized, idempotency-safe, source-reconcilable, and auditable.

## 27. Access rules

### Subscription and tenant administrators

May manage effective tracking package, limits, retention, allowed providers, customer location policy, and source-priority policy within product authorization.

### Integration administrators

May manage provider credentials, provider mappings, device registration, SIM assignment, configuration profiles, device/vehicle mapping, quarantine, bounded replay, gateway/provider health, and raw payload access only when separately permitted.

### Drivers

May start, view and stop only their own authorized tracking session for an assigned active vehicle/trip, subject to entitlement and operational policy. Drivers cannot browse other driver sessions, unrestricted vehicle history, raw provider data, device credentials, or integration configuration.

### Operations users

May see authorized normalized events, current positions, selected-source explanation, source freshness, fleet maps, trip/shipment context, geofence signals, mobile-session status, and operational exceptions under record and field scope.

### Customer users and public tracking

May see only permitted customer-safe shipment projections under existing token/account/site/customer-owner authorization and tenant location-visibility policy.

### Restricted data

Raw source payload, precise long-term driver history, consent details, session identifiers, IMEI, ICCID, MSISDN, APN/provider credentials, and infrastructure details require separately defined permissions and masking.

Enforce access in database and service layers, not UI only. List, search, export, reports, maps, Realtime, and API must apply the same tenant, customer, field, entitlement, and record policies.

## 28. Test data requirement

Create deterministic test fixtures for:

### Driver mobile

- entitled and non-entitled tenants;
- valid driver/vehicle/trip assignment;
- unassigned driver;
- start, heartbeat, batch, stop, revoke and expiry;
- permission granted/denied;
- accurate and low-accuracy location;
- app visible/backgrounded/suspended where representable;
- connectivity loss and delayed upload;
- battery and schema-version metadata;
- duplicate/replayed mobile event;
- concurrent/conflicting session;
- entitlement session and vehicle limits.

### Direct physical device

- valid FMC920 IMEI handshake;
- unknown IMEI;
- valid single-record Codec 8 Extended packet;
- valid multi-record packet;
- TCP fragmentation and multiple packets per read;
- invalid preamble, length, codec, CRC and record count;
- valid and invalid I/O elements;
- ignition, movement, stopped and external-power events;
- duplicate packet and AVL record;
- delayed/out-of-order record;
- reconnect/retransmission;
- cellular-outage backlog;
- gateway restart and database slowdown.

### Third-party provider

- valid/invalid provider authentication;
- mapped and unmapped provider units;
- webhook duplicate/replay;
- polling cursor/checkpoint;
- provider rate limit;
- schema version and drift;
- outage and delayed events.

### Hybrid and canonical operations

- physical primary/mobile fallback;
- provider primary/mobile fallback;
- mobile-only, device-only and provider-only packages;
- all three sources active;
- source freshness transition;
- source accuracy difference;
- source divergence/conflict;
- stable arbitration under replay;
- same IMEI/source collision rejection;
- device/provider/mobile reassignment;
- active and completed trip/leg/shipment;
- circular and polygon geofence;
- route deviation where route geometry exists;
- customer-visible and restricted projections.

Include deterministic binary and JSON fixtures, expected acknowledgment bytes/count, exact timestamps, coordinates, accuracy, source/config versions, roles, Tenant A/B, customer owners, retry keys, entitlement snapshots, and concurrency fixtures.

## 29. Tests to create or update

### 29.1 Driver mobile tests

- entitlement and assignment enforcement;
- start/heartbeat/batch/stop/revoke/expiry lifecycle;
- permission and consent evidence;
- idempotency, replay and rate limits;
- stale/degraded/offline behavior;
- browser/PWA UX and accessibility;
- driver and cross-tenant isolation.

### 29.2 Protocol and parser tests

- IMEI handshake;
- TCP framing and fragmentation;
- Codec 8 Extended parsing;
- CRC;
- record counts;
- I/O mapping;
- malformed and oversized packet rejection;
- acknowledgment behavior.

### 29.3 Gateway integration tests

- real TCP socket connection;
- concurrent devices;
- reconnect;
- timeout;
- graceful shutdown;
- durable buffer boundary;
- database failure and retry;
- replay and quarantine;
- structured logging and metrics;
- container health/readiness.

### 29.4 Third-party provider tests

- provider authentication;
- webhook/push/poll behavior;
- mapping;
- schema drift;
- cursor/checkpoint;
- replay and rate limits;
- outage and recovery;
- canonical-contract convergence.

### 29.5 Database and arbitration tests

- entitlement lifecycle and usage limits;
- device/SIM/configuration lifecycle;
- provider integration lifecycle;
- mobile tracking-session lifecycle;
- RLS and RBAC;
- assignment conflict;
- idempotent canonical batch ingestion;
- late/out-of-order current-position rules;
- source trust/freshness/priority arbitration;
- fallback and divergence detection;
- stable selection under replay;
- PostGIS and geofence;
- trip/leg/shipment mapping;
- milestone/exception derivation exactly once;
- customer projection isolation;
- retention/reconciliation;
- audit evidence.

### 29.6 UI and API tests

- tracking package and usage administration;
- driver tracking UI;
- provider integration administration;
- device and SIM administration;
- Fleet Control Tower;
- vehicle tracking detail;
- geofence management;
- authoritative-source explanation;
- source conflict/fallback states;
- stale/offline/degraded states;
- authorized Realtime;
- REST/GraphQL equivalence;
- customer-safe tracking;
- accessibility and keyboard flow.

### 29.7 Load and resilience tests

- mixed 100-source baseline;
- 1,000 tracked-vehicle target or evidence-backed bounded equivalent;
- mobile reconnect burst;
- physical-device reconnect burst;
- provider webhook burst/poll backlog;
- multi-record backlog;
- provider outage;
- gateway outage/restart;
- Supabase outage;
- buffer exhaustion behavior;
- recovery and reconciliation.

### 29.8 End-to-end completion tests

At least three end-to-end flows are mandatory:

```text
Driver PWA
→ authenticated mobile tracking session
→ HTTPS canonical ingestion
→ source arbitration
→ fleet/trip/shipment projection
→ geofence/milestone or exception
→ Fleet Control Tower and customer-safe tracking
```

```text
Teltonika simulator or physical FMC920
→ TCP handshake and Codec 8 Extended
→ CRC and gateway buffer
→ ACK
→ Supabase canonical ingestion
→ source arbitration
→ current position/history
→ operational and customer projections
```

```text
Approved provider fixture/integration
→ authenticated webhook/push/poll
→ provider mapping and normalization
→ canonical ingestion
→ source arbitration
→ operational and customer projections
```

A fourth hybrid test must prove source fallback and recovery without duplicate milestones or corrupted current position.

Unit-test-only parser or isolated endpoint results do not satisfy end-to-end acceptance.

## 30. Regression tests

Re-run relevant:

- Platform API/webhook/job/security tests;
- Supabase migration reset and database tests;
- RLS/RBAC and tenant isolation;
- PostGIS;
- fleet/resource assignment;
- shipment lifecycle;
- milestone and exception;
- public tracking;
- transaction lineage;
- Finance compatibility;
- browser/accessibility;
- critical Operations E2E;
- security, dependency, data-classification, threat-model, and standards checks;
- build and deployment validation.

Compare trusted baseline before and after. Do not weaken existing assertions to make this capability pass.

## 31. Commands to run

Detect and run repository equivalents of:

```bash
pnpm run typecheck
pnpm run lint
pnpm test
pnpm run db:test
pnpm run test:e2e
pnpm run security:check
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check
pnpm run docs:check
pnpm exec next build
```

Also add and run gateway-specific commands equivalent to:

```bash
pnpm --filter gps-gateway test
pnpm --filter gps-gateway test:protocol
pnpm --filter gps-gateway test:integration
pnpm --filter gps-gateway test:load
pnpm --filter gps-gateway build
docker build -t cargogrid-gps-gateway ./services/gps-gateway
docker run --rm cargogrid-gps-gateway <health-or-smoke-command>
pnpm run gps:simulate:teltonika
pnpm run gps:simulate:mobile
pnpm run gps:simulate:provider
```

Run database reset/migration/type generation, protocol simulator, real TCP smoke test, container smoke test, security, and target-volume tests feasible in the environment.

Do not disable a gate. Separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 32. Documentation to update

Update:

- multi-source tracking and entitlement architecture;
- Driver Mobile GPS session, consent, assignment, limitation and degraded-state behavior;
- third-party GPS provider adapter and certification boundary;
- hybrid source-priority, arbitration, fallback and divergence rules;
- GPS Gateway architecture;
- serverless versus always-on deployment boundary;
- Teltonika FMC920 and Codec 8 Extended contract;
- I/O element mapping;
- canonical telemetry schema;
- device/SIM/configuration provisioning;
- DNS, static IPv4, port, firewall, environment, and Docker deployment;
- Supabase ingestion RPC/job and least-privileged credentials;
- PostGIS/geofence design;
- Realtime subscription limits;
- privacy, masking, and retention;
- tracking package/entitlement and usage-limit policy;
- customer location-visibility policy;
- outage, reconnect, replay, quarantine, and DLQ runbook;
- gateway restart and Supabase outage recovery;
- monitoring and alert thresholds;
- physical installation checklist;
- device replacement/RMA and reassignment;
- support troubleshooting for mobile, gateway, device and provider modes;
- schema, API, data-flow, dependency, threat-model, and deployment diagrams;
- persistent context, status, task, change, regression, and traceability artifacts;
- user, admin, API, infrastructure, and support documentation;
- release note when behavior changes.

Document the external hardware boundary clearly: hardware supply, installation, SIM subscription, and warranty are separate commercial/operational concerns from the SaaS subscription unless explicitly bundled by contract.

## 33. Rollback and recovery note

Rollback must support:

- disabling the direct-device adapter without deleting history;
- closing or redirecting the TCP listener under a controlled maintenance procedure;
- revoking gateway credentials;
- suspending a device or configuration profile;
- preserving acknowledged-but-unprocessed buffered records;
- restoring the last trusted mapping and adapter version;
- replaying only bounded, verified canonical records;
- reconciling current-position, history, geofence, milestone, exception, and customer projections;
- rolling back UI exposure while retaining evidence;
- restoring the last trusted container image;
- documenting DNS/port/firewall rollback;
- recording exact resume commands.

Never use destructive Git or database shortcuts. Do not discard raw evidence outside the approved retention policy.

## 34. Acceptance criteria

All criteria are mandatory:

1. Tenant tracking entitlements and limits exist for mobile, direct device, third-party provider, hybrid, retention, customer visibility and source priority.
2. Entitlements are effective-dated, audited and enforced server-side on every ingestion and session path.
3. Driver Mobile GPS supports authenticated start, telemetry batch, heartbeat/freshness, stop, revoke and expiry tied to an assigned active vehicle/trip.
4. Driver mobile consent/permission, accuracy, stale, offline, suspended and degraded states are implemented without unsupported background-tracking claims.
5. A separately deployable, always-on CargoGrid GPS Gateway exists.
6. The gateway runs as a Docker container outside the request-scoped serverless runtime.
7. A real TCP listener accepts concurrent device connections.
8. Teltonika FMC920 IMEI handshake, Codec 8 Extended parsing, CRC, record-count validation and protocol ACK are implemented.
9. TCP fragmentation, reconnect, timeout, malformed packet, packet limit and graceful shutdown are tested.
10. Validated direct-device records cross a documented loss-controlled boundary before ACK.
11. At least one approved third-party provider adapter supports authenticated webhook/push/polling, mapping, schema/version control, replay/rate handling and health evidence.
12. Driver mobile, direct device and provider events converge into one versioned canonical telemetry contract.
13. Supabase ingestion is batched, idempotent, least-privileged and retry-safe.
14. Package entitlement, device, SIM, configuration, installation, provider integration, mobile session, connection, raw evidence, normalized telemetry, source health, current position, history, arbitration and vehicle-event structures exist.
15. Deterministic source arbitration selects one authoritative live projection while preserving every accepted source history.
16. Hybrid fallback, recovery and source divergence are visible, explainable, versioned and audited.
17. Late, duplicate, replayed, conflicting and out-of-order records cannot corrupt current position or shipment truth.
18. Vehicle, driver, trip, leg, shipment, geofence, milestone, exception and customer-safe tracking integration is complete.
19. Tracking Package Admin, Driver Tracking, Provider Integration Admin, GPS Device Admin, Fleet Control Tower and Vehicle Tracking Detail are complete with required UX states.
20. RLS, RBAC, field masking, entitlement enforcement, tenant isolation, driver privacy, consent, SIM privacy, provider-secret protection and customer isolation pass tests.
21. Health, readiness, metrics, structured logs, retry, quarantine and recovery evidence exist for mobile, gateway and provider paths.
22. Static-IP/DNS/port/firewall/container deployment is documented and smoke-tested in the available environment.
23. Mandatory mobile, Teltonika, provider and hybrid end-to-end flows pass.
24. Mixed-source load, reconnect burst, provider outage, gateway restart, Supabase outage, entitlement limit, retention and recovery controls pass evidence gates.
25. All mandatory automated and manual gates pass at one recorded checkpoint.
26. Completion evidence maps source requirement → task → architecture → code/migration/service/deployment/UI → test → documentation.

The task must remain `PARTIALLY_COMPLETE` or `BLOCKED` when any mandatory source mode, entitlement enforcement, source arbitration, direct TCP gateway, Teltonika adapter, provider adapter, deployment artifact, or end-to-end verification is missing.

## 35. Definition of Done

Scope is complete only when:

- Driver Mobile GPS, Direct Fleet GPS and Existing GPS Platform Integration are functional;
- Hybrid arbitration and fallback are functional;
- tracking entitlements, package limits, retention and customer-visibility controls are functional;
- no placeholder, fake persistence, fake device/provider/mobile state, unsupported background claim or dead action remains;
- migrations and generated types are complete;
- RLS/RBAC/field, entitlement and record policies are enforced;
- canonical telemetry, source trust, arbitration and ingestion contracts are versioned;
- the gateway is containerized and separately deployable;
- Teltonika Codec 8 Extended is implemented and verified;
- device/SIM/configuration and provider provisioning are complete;
- driver tracking sessions and consent/permission evidence are complete;
- fleet-control, driver and customer tracking UX are complete;
- jobs, buffering, retries, quarantine, geofence, milestones, exceptions, Realtime, source fallback and customer-safe projections are complete;
- tests, docs, audit, privacy, performance, observability, deployment, rollback and recovery evidence are complete;
- no critical tenant, entitlement, customer, driver privacy, consent, operational integrity, security, inventory or financial blocker remains.

No production-ready, market-ready, pilot-ready or GA claim is permitted from this task alone.

## 36. Completion report format

Report:

- task and prompt IDs;
- repository checkpoint;
- changed files and migrations;
- tracking package, entitlement, limits and usage model;
- supported source modes and unsupported boundaries;
- driver-mobile session, permission/consent and degraded-state implementation;
- service and container artifacts;
- DNS/static-IP/port/environment contract;
- protocol and device decisions;
- Teltonika adapter version and supported-device evidence;
- third-party provider adapter, auth, mapping and certification evidence;
- canonical telemetry, source trust, arbitration and database contracts;
- device/SIM/configuration/provider/mobile implementation;
- Fleet Control Tower, Driver Tracking and customer tracking implementation;
- commands and before/after results;
- mobile, provider, protocol parser, TCP, ACK, reconnect, retry, outage, load, entitlement, arbitration, privacy, RLS/RBAC, tenant/customer isolation, PostGIS/geofence, shipment/milestone/exception, Realtime and end-to-end evidence;
- gateway/provider/mobile health and observability evidence;
- residual errors, issues, risks, unsupported providers/I/O elements, browser limitations or environment limitations;
- documentation;
- rollback and resume instructions for each source mode and hybrid arbitration;
- recommended next task.

Update all persistent ledgers before `VERIFIED`.

## 37. Next eligible prompt

Only the execution index may release ATW-227 or another dependency-clean atomic task after this task is `VERIFIED`.

Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
