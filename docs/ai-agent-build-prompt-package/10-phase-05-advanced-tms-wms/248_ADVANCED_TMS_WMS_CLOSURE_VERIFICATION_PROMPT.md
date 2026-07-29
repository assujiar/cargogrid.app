# Prompt 248 — Advanced TMS/WMS Closure Verification

**Prompt ID:** `CG-S10-ATW-029`  
**Package document:** `CG-AABPP-ATW-248`  
**Version:** `0.12.0-multisource-gps`  
**Runtime output:** `docs/build-log/phase-05/ADVANCED_TMS_WMS_CLOSURE_REPORT.md`

Do not begin until Prompt 247 is `VERIFIED`, all Phase 5 evidence is available, and the active checkpoint still carries the required Phase 4 closure.

## Objective

Independently verify Phase 5 completeness, including multi-source GPS architecture, without requiring unavailable physical hardware or unavailable third-party credentials to fabricate evidence.

## Required verification

1. Reconcile Prompts 220–247 at one repository/schema/deployment checkpoint.
2. Confirm all Phase 5 capabilities have implementation, migrations/contracts/UI/jobs/deployment as applicable, tests, documentation, owner, rollback, and evidence.
3. Prove canonical Phase 3/4 roots were extended without duplicate shipment, vehicle, trip, telemetry, milestone, customer, inventory, or Finance truth.
4. Prove multi-leg planning → dispatch → resource assignment → mile execution → tracking → milestone/exception → delivery/custody.
5. Prove `DRIVER_MOBILE` works through authenticated active tracking sessions, assignment, entitlement, consent/permission/freshness, canonical normalization, geofence and customer-safe projection.
6. Prove `DIRECT_DEVICE` repository-controlled implementation:
   - always-on gateway deployment definition;
   - TCP listener and configurable endpoint;
   - Teltonika Codec 8 Extended simulator/recorded-frame tests;
   - IMEI handshake, CRC, parsing, ACK, duplicate/order, reconnect, buffering, Supabase ingestion, restart, outage and recovery;
   - container health/readiness/metrics/logging and secret controls.
7. Physical hardware-in-loop evidence may remain `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` and does not block closure when all item 6 evidence passes. The closure report must not claim physical-device validation.
8. Prove `THIRD_PARTY_PLATFORM` adapter framework, authentication, schema mapping, rate-limit/retry/replay, mapping, failure and deterministic contract tests.
9. A live third-party provider test may be `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` when credentials/API/legal/commercial prerequisites are absent. The closure report must not claim the provider is live.
10. Prove `HYBRID` arbitration for priority, freshness, accuracy, conflict, fallback, source switch, hysteresis and complete source history.
11. Prove subscription entitlements prevent unauthorized tracking modes and limits.
12. Prove route/load planning consumes only canonical current position.
13. Prove dispatch board, milestone/exception and capacity/utilization consume canonical projections.
14. Prove Fleet Control Tower and Customer Portal use the same canonical data with different field visibility.
15. Prove no raw telemetry directly mutates shipment lifecycle.
16. Prove source histories, event/received time, order, dedup, retention and reconciliation.
17. Prove critical WMS flow and exact inventory controls.
18. Prove target-volume profiles for mobile, TCP gateway, provider contract, hybrid, jobs, Realtime and WMS.
19. Prove tenant/customer/company/branch/warehouse/owner/record/field/file/job/realtime isolation.
20. Prove secrets are server-only and logs/metrics are redacted.
21. Prove clean install, upgrade, gateway deployment, backup/restore, rollback and forward recovery.
22. Confirm no unresolved critical/high repository-controlled blocker.
23. Confirm later-phase boundaries and no production/pilot/GA claim.

## External-evidence policy

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

## Closure states

- `PHASE_5_VERIFIED`: every repository-controlled runtime gate passes; physical hardware and/or live provider may remain properly deferred/conditionally skipped.
- `PHASE_5_PARTIALLY_COMPLETE`: a bounded repository-controlled non-critical gate remains; downstream phase remains blocked unless policy explicitly permits.
- `PHASE_5_BLOCKED`: a critical repository-controlled security, tenant, tracking, transport, inventory, Finance, migration, deployment, or evidence gate fails.
- `PHASE_5_ROLLED_BACK`: phase returned to a trusted checkpoint.

## Required output

Write:

- checkpoint, schema, service, container and deployment inventory;
- capability/requirement evidence matrix;
- four tracking-package E2E results;
- physical-device deferred evidence record;
- third-party live-test conditional status;
- simulator/contract test evidence;
- gateway/mobile/provider/hybrid security and load evidence;
- canonical telemetry and customer projection reconciliation;
- WMS/Finance and customer isolation results;
- migration/build/accessibility/observability evidence;
- residual issues and risks;
- closure state and rationale;
- next-phase eligibility and exact resume.

## Completion gate

Set `PHASE_5_VERIFIED` only when all repository-controlled mandatory checks pass and external-evidence statuses comply with this prompt. Never convert deferred or skipped evidence into a claim that testing occurred.
