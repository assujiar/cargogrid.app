# ATW-226D — Always-on GPS Gateway and Direct-Device Telemetry Ingestion

## 0. Checkpoint

| Field | Value |
|---|---|
| Prompt | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §14B (`226D`'s own scope line), parent `CG-S10-ATW-007` (`CG-AABPP-ATW-226`) |
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-225-udh-x4hsij` |
| Dependency | `ATW-226A` (`VERIFIED`), `ATW-226B` (`VERIFIED`) — both satisfied at kickoff of this checkpoint |
| Authorization | Explicit range authorization "lanjut sd prompt terakhir di 226 (226a-226i)" — fourth task within that range, following `226A`/`226B`/`226C`. |

## 1. Pre-flight collision check

`pnpm run git:check` clean, continuing directly on top of `ATW-226C`'s own commit (`fb60a0b`). No open PR.

## 2. Baseline reconciliation

Re-read `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §14B (GPS Gateway requirements: raw TCP listener, Teltonika FMC920/Codec 8 Extended, IMEI handshake, CRC validation, AVL parsing, IO-element mapping, ACK, reconnect/timeout handling, malformed/oversized packet rejection, durable buffering, batch/RPC write, Dockerfile, health/readiness/metrics, structured logs, independent deployment from Vercel) and §8 (external-evidence policy). Re-read `00_ADVANCED_TMS_WMS_WBS.md` §4/§6/§7, confirming: `app.gps_devices` (`ATW-223`) is the reuse target for device identity (its own table comment already disclosed "device secrets are ATW-226D's own deployment-time concern"); hosting-platform selection is deliberately deferred to this checkpoint as its own ADR candidate; the API key/webhook primitives (`PLT-129`) are the named reuse target for GPS Gateway authentication. Confirmed `app.audit_logs.actor_auth_user_id` is nullable (`20260716113048_create_audit_trail.sql`), enabling machine-triggered (no human actor) audit events without a bespoke table. Fresh baseline gate suite green before any file was written: `typecheck`/`lint` 0 errors, `node:test` 2307/2307, `db:test` PASS across 103 migrations/105 db-test files.

## 3. Implementation

### 3.1 Scope boundaries and design decisions (disclosed, migration header)

1. **A fundamentally different trust model than `ATW-226C`, not the same one reused.** A Driver PWA is an unauthenticated public browser session (`226C`'s own `anon` grant is the necessary consequence). The GPS Gateway is the opposite: an always-on, CargoGrid-operated backend process (`220_*.md` §6: "always-on container/VPS... explicitly not a Vercel Function"). This migration grants nothing to `anon` — both new functions are `service_role`-only, reusing `PLT-129`'s `app.authenticate_api_key`/`app.api_key_has_scope` exactly as that migration's own header already anticipated ("the real authentication entry point a future API-gateway middleware would call"). A scoped `OPS:Edit` API key lets this gateway instance's own credential be revoked/rotated independently of the shared `service_role` secret.
2. **Two-phase interaction, mirroring the real Teltonika wire protocol.** `app.resolve_gps_device_for_handshake()` runs once per TCP connection (IMEI only, immediate accept/reject); `app.ingest_direct_device_telemetry_batch()` runs once per AVL data packet on that same connection, keyed by the `device_id` the handshake already resolved — never a second IMEI lookup per batch.
3. **IMEI is looked up globally, not per-tenant.** The physical handshake presents only the bare IMEI; `app.gps_devices` scopes uniqueness to `(tenant_id, imei)`, not `imei` alone. `app.resolve_gps_device_for_handshake()` matches on `imei` across every tenant and explicitly refuses (`imei_ambiguous_across_tenants`) rather than guesses if more than one row matches — no new database-level uniqueness constraint was added to the already-applied `app.gps_devices` table for this; the runtime refusal is the safer choice under uncertainty.
4. **Raw storage only**, exactly like `app.driver_mobile_position_reports` (`ATW-226C`). `app.direct_device_telemetry_reports` preserves the full decoded Codec 8E `{io_id: value}` map verbatim in `io_elements` rather than inventing a typed column per IO ID — `ATW-226F` decides which IDs are canonically meaningful.
5. **`app.jobs` (`PLT-131`/`PLT-132`) is deliberately not used for live ingestion**, despite the WBS naming it as *a* reuse target. `226_*.md` §14B's own required mechanism is "batch/RPC write" with durable buffering owned by the gateway itself — `services/gps-gateway`'s own local durable buffer is where that genuinely lives, not a second, redundant server-side queue. `ATW-226E`'s third-party polling adapter (genuinely schedule-driven) is left as the more natural `app.jobs` consumer.
6. Device status auto-transition (`installed`/`offline` → `active` on accepted telemetry) is a direct, narrowly-scoped `UPDATE` inside the ingestion RPC, not a call to `app.transition_gps_device_status` (`OPS:Edit`-gated against a human actor) — still captures the identical `app.capture_audit_event` shape, with a null actor and a `gps-gateway:<imei>` label.
7. PostGIS point storage reuses `app.geojson_point_to_geography`/`app.validate_geography_point` (`PLT-134`) verbatim.
8. External-evidence policy (`226_*.md` §8): no physical Teltonika hardware or live cellular network exists in this environment. Protocol correctness is proven by `services/gps-gateway`'s own deterministic byte-level parser tests plus a real `net.Socket` TCP simulator integration test — disclosed as `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE`.
9. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

### 3.2 Schema — `supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql`

One additive column (`app.gps_devices.last_telemetry_at`, nullable, no default — the already-applied `ATW-223` table is never edited in place). One new table: `app.direct_device_telemetry_reports` (raw append-only telemetry, `event_at`/`received_at` kept separate). Three new functions: `app.resolve_gps_device_for_handshake` (per-connection handshake decision, never raises for a per-device outcome — only a bad gateway credential raises), `app.ingest_direct_device_telemetry_batch` (per-packet batch write, raises on any structurally invalid report — a trusted, already-protocol-decoded caller, unlike `226C`'s anon-facing status-column pattern; the whole batch rolls back atomically on the first bad report), `app.get_direct_device_telemetry_reports` (read projection, mirrors `app.get_driver_mobile_position_reports`).

A real defect found while authoring the db-test: two reports inserted within the same `ingest_direct_device_telemetry_batch` transaction shared an identical `received_at` (Postgres's `now()` is frozen at transaction start, not per-statement), making "newest first" ordering non-deterministic for reports from the same batch. Fixed by explicitly writing `clock_timestamp()` (which genuinely advances per row) instead of relying on the column's own `now()`-based default, inside this one RPC's insert loop only.

### 3.3 Service layer

`server/contracts/gps-gateway-ingestion/gps-gateway-ingestion.ts`, `server/queries/gps-gateway-ingestion.ts` (`listDirectDeviceTelemetryReports`), `server/mutations/gps-gateway-ingestion.ts` (`resolveGpsDeviceForHandshake`, `ingestDirectDeviceTelemetryBatch` — both throw on every failure mode, unlike `226C`'s own anon-facing mutation wrapper, since every caller here already holds a service_role-tier credential).

### 3.4 `services/gps-gateway` — the standalone, independently-deployed package

Its own `package.json`/`pnpm-lock.yaml`/`tsconfig.json`, excluded from the root `tsconfig.json` (`exclude: ["services/**"]`) and `eslint.config.js` (`ignores: ["services/**"]`) — its own gate surface is `pnpm run typecheck`/`pnpm run test`, run from inside that directory, never the root equivalents (`README.md` §"Why this is a separate package" discloses the reasoning in full).

- `src/codec8e.ts` — a real, byte-level Teltonika Codec 8 Extended parser: `crc16Ibm` (CRC-16/IBM/ARC, verified against the standard `"123456789"` → `0xBB3D` check vector), `decodeImeiHandshake`/`encodeHandshakeResponse`, `decodeAvlDataPacket`/`encodeAckResponse` (preamble, data-length, codec ID, record count ×2, CRC validation; GPS element; all five IO-element width categories — 1/2/4/8-byte and Codec 8E's own variable-length elements). `encodeAvlDataPacket` is a test/simulator-only inverse.
- `src/server.ts` — the raw `net.Server` TCP listener. Per-connection state machine (`awaiting_handshake` → `awaiting_avl_data`), with `'data'` events serialized through a promise chain (a real race found and fixed during authoring — see §4.1). Malformed/oversized packets (§14B) close the connection without an ACK, never crash the process.
- `src/buffer.ts` — `DurableTelemetryBuffer`, a newline-delimited-JSON local file queue (§14B: "durable buffering"). A live ingest failure durably persists the batch instead of dropping it or withholding the device's own ACK; flushes oldest-first, stopping at the first failure (never reorders).
- `src/ingestClient.ts` — the gateway's own minimal Supabase RPC client (deliberately not imported from `server/`, see `README.md`).
- `src/health.ts` — `/healthz`, `/readyz`, `/metrics` (plain text).
- `src/index.ts` — entrypoint; env-var-only configuration; background buffer-flush loop; graceful `SIGTERM`/`SIGINT` shutdown.
- `Dockerfile` — two-stage build (typecheck in the builder stage, `--prod` install in the runtime stage); `HEALTHCHECK` against `/healthz`.

## 4. Tests

`scripts/db-tests/advanced-tms-gps-gateway-ingestion.sql` (new) — two tenants (one with a real device taken to `installed` via the real `ATW-226B` evidence flow, one left at `stock` for cross-tenant/not-ingestible assertions), one `OPS:Edit`-scoped API key per tenant: bad-key rejection (raised); unknown-IMEI/cross-tenant/not-ingestible all return `accepted=false` with a `rejectionReason`, never raised; a real installed device accepted, a location+heartbeat batch ingested, `installed → active` transition and `last_telemetry_at` proven; a second, structurally invalid batch proven to roll back atomically (still exactly 2 stored reports); `get_direct_device_telemetry_reports`'s GeoJSON projection matched against the exact ingested coordinates; `offline → active` on reconnect (not merely `installed → active`); a suspended device refused at both the handshake and the ingest RPC; a revoked/narrow-scope API key refused; RLS; schema-privilege defense in depth (zero `anon`/`authenticated` grants on either RPC); exact-count audit trail (5 handshake events, 2 ingestion events, every one with a null `actor_auth_user_id`).

`server/contracts/gps-gateway-ingestion/gps-gateway-ingestion.test.ts` (8 cases), `server/queries/gps-gateway-ingestion.test.ts` (3 cases), `server/mutations/gps-gateway-ingestion.test.ts` (5 cases) — **16 net new** root `node:test` cases. Root `node:test` **2323/2323**. `db:test` PASS across **104** migrations/**106** db-test files (1 new each). `npx next build` PASS (no new routes — this checkpoint added no `app/` files).

`services/gps-gateway` (its own, separate gate surface): `pnpm run typecheck` 0 errors; `pnpm run test` **26/26** — `test/codec8e.test.ts` (16 cases: CRC vector, handshake encode/decode, a hand-built packet independent of the encoder, negative-altitude and all-five-IO-width round trips, every structural-violation error path), `test/buffer.test.ts` (5 cases: drain-to-empty, ordered stop-at-first-failure, partial-success retention, concurrent-flush no-op), `test/server.test.ts` (5 cases: real `net.Socket` handshake accept/ACK, IMEI rejection + close, live-failure durable buffering, malformed-packet rejection, two packets in one TCP chunk).

### 4.1 Real defects found and fixed during authoring (before any full-suite gate run)

1. **`received_at` non-determinism within one ingestion batch** — see §3.2. Caught by a failing db-test assertion (`get_direct_device_telemetry_reports`'s "newest first" ordering did not match the ingested order) against a real Postgres instance, not by inspection. Fixed with `clock_timestamp()`.
2. **A race between overlapping `'data'` events on the same TCP connection.** The original `handleConnection` mutated a closure-captured `accumulator`/`state` pair from inside an un-awaited async call — a second `'data'` event firing before the first chunk's RPC round-trip resolved would read a stale snapshot, corrupting or duplicating the byte stream. Self-diagnosed by reasoning through Node's own event-loop/`net.Socket` semantics before writing the integration test, not discovered via a failing run. Fixed by serializing all per-connection chunk processing through a promise chain, with a terminal `.catch()` guarding against both an unhandled rejection and the chain silently getting stuck rejected.
3. **TypeScript 5.9's `Buffer<ArrayBufferLike>` generic** — `Buffer.concat()`/`.subarray()` return the wider `Buffer<ArrayBufferLike>`, not assignable to a bare `Buffer` (= `Buffer<ArrayBuffer>`) parameter/variable. Fixed by introducing a shared `Bytes = Buffer<ArrayBufferLike>` alias used consistently across `codec8e.ts`/`server.ts` — a TypeScript-version-specific fix, not a protocol defect, but real friction any Node 22 + TypeScript 5.9 codebase using raw `Buffer` slicing will hit.
4. **`node --experimental-strip-types` does not support TypeScript constructor parameter properties** (`constructor(private readonly buffer: Buffer) {}`) — this repository's own established runtime constraint, re-confirmed here; fixed by declaring the field explicitly and assigning it in the constructor body.

## 5. Residual disclosures

- No live Teltonika hardware or cellular network was available — `services/gps-gateway/README.md` §"External-evidence policy" and this build log both disclose `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE`; a real `net.Socket` client speaking the exact wire protocol is this checkpoint's own repository-controlled evidence, per `226_*.md` §8's own allowance.
- `report_type` (`location` vs `heartbeat`) is inferred from whether the AVL record's own GPS element carries a non-zero fix — a device genuinely reporting `(0, 0)` would be misclassified. Disclosed and accepted (`README.md`'s own "Known, disclosed limitations").
- Offline-detection (a device that stops reporting) is not this checkpoint's concern — `ATW-226F`'s own canonical-telemetry/health layer owns that, the same disclosed boundary `app.vehicle_tracking_source_priorities` (`ATW-223`) already drew.
- `services/gps-gateway` was never actually deployed to any container/VPS platform (none exists yet, `220_*.md` §6's own disclosed `NOT_STARTED` hosting decision, unchanged by this checkpoint) — the Dockerfile builds and typechecks but has not been run against a live registry/orchestrator.
- `ATW-226E` remains the only other `226A`+`226B`-dependent child now outstanding; `ATW-226F` needs `226C`+`226D`+`226E` — two of its three prerequisites (`226C`, now `226D`) are satisfied, `226E` remains.

## 6. Completion

This checkpoint corrects `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1.4 row `ATW-226D` (`READY` → `VERIFIED`). Four of nine `226` children (`226A`–`226D`) are now `VERIFIED`. `ATW-226E` is next in this session's own explicit range authorization.
