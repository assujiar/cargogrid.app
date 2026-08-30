# Prompt 220 — Advanced TMS/WMS WBS and Runtime Kickoff

**Prompt ID:** `CG-S10-ATW-001`  
**Package document:** `CG-AABPP-ATW-220`  
**Version:** `0.11.0`  
**Runtime output:** `docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 5 hierarchy, dependency graph, bounded atomic tasks, deployment workstreams, and evidence ledger without implementing capabilities in this kickoff.

## Mandatory entry gate

Stop with `PHASE_5_BLOCKED` unless the active checkpoint proves all required Phase 0–4 closures and reconciles canonical Operations/Finance contracts, PostGIS, jobs, integrations, entitlements, environment, and deployment foundations.

## Required work

1. Read all persistent governance, context, status, task, decision, assumption, error, issue, and handoff artifacts.
2. Inspect actual repository paths, Supabase schemas, migrations, RLS/RBAC, APIs, UI, jobs, deployment configuration, observability, and tests.
3. Map all Phase 5 capabilities and advanced `OPS-*` anchors.
4. Preserve canonical Phase 3/4 roots; prohibit duplicate telemetry, vehicle, trip, shipment, milestone, or customer truth.
5. Create an explicit multi-source GPS workstream and dependency graph.
6. Record deployment ownership for the serverless application and always-on GPS Gateway.
7. Map external-evidence status and future execution procedure.
8. Mark only dependency-clean tasks `READY`.

## Mandatory Prompt 226 decomposition

Prompt 226 is a parent capability and must be split into the following independently reviewable child tasks unless repository evidence proves an equivalent or safer split:

| Child | Atomic scope | Minimum dependency |
|---|---|---|
| `ATW-226A` | Tracking entitlement and source policy | Platform entitlement/config |
| `ATW-226B` | Device, SIM, provider, installation, and mapping management | ATW-223 |
| `ATW-226C` | Driver Mobile GPS session and HTTPS ingestion | ATW-223/225 |
| `ATW-226D` | Always-on GPS Gateway and Teltonika Codec 8E adapter | ATW-226A/B |
| `ATW-226E` | Third-party GPS platform adapter contract | ATW-226A/B |
| `ATW-226F` | Canonical telemetry storage, normalization, ordering, and source arbitration | ATW-226C/D/E |
| `ATW-226G` | Geofence, milestone, exception, and route-deviation signals | ATW-226F |
| `ATW-226H` | Fleet Control Tower, device administration, and sanitized projections | ATW-226F/G |
| `ATW-226I` | Deployment, observability, load, security, outage, and recovery verification | ATW-226A..H |

Every child task requires exact paths, owner, migration IDs, API contracts, secrets, deployment target, test plan, rollback, evidence, and status.

## Required execution-index columns

`task_id`, `parent_prompt`, `child_slice`, `workstream`, `epic`, `capability`, `atomic_objective`, `source_ids`, `upstream`, `downstream`, `allowed_paths`, `forbidden_paths`, `migration_ids`, `api_contracts`, `deployment_target`, `secret_ownership`, `access_controls`, `transport_invariants`, `tests`, `external_evidence_status`, `commands`, `evidence`, `rollback`, `owner`, `status`, `resume_point`.

## Multi-source planning gates

- `DRIVER_MOBILE` cannot become `READY` until authenticated driver-trip-vehicle assignment and consent/freshness semantics are defined.
- `DIRECT_DEVICE` cannot become `READY` until the always-on deployment target, public endpoint, protocol, buffering, and Supabase ingestion boundary are approved.
- `THIRD_PARTY_PLATFORM` cannot become `READY` without either an approved live contract or a declared contract-fixture-only mode.
- Hybrid arbitration cannot become `READY` until all source records preserve history and deterministic priority/freshness/accuracy rules are approved.
- Customer projection cannot consume raw telemetry.
- Route/load planning can consume only the canonical authoritative current-position projection.
- No physical-hardware evidence may be fabricated.

## External test treatment

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

## Completion gate

Mark Prompt 220 `VERIFIED` only when the WBS contains complete multi-source GPS coverage, all child dependencies are acyclic, deployment ownership is explicit, every external test has a valid status, and the first safe atomic task is deterministic. Do not set `PHASE_5_VERIFIED`.
