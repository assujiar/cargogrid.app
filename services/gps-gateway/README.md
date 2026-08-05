# CargoGrid GPS Gateway (ATW-226D)

Always-on, direct-hardware GPS/telematics ingestion for CargoGrid's Advanced TMS/WMS
Multi-Source GPS and Telematics Integration capability (`CG-S10-ATW-007`, Prompt 226,
decomposition child `ATW-226D`). Speaks the Teltonika Codec 8 Extended protocol
(FMC920 and every other Codec 8 Extended device) over raw TCP.

## Why this is a separate package, not part of the Next.js app

`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/
219_MULTI_SOURCE_GPS_TELEMATICS_PLANNING.md` §5 and
`docs/build-log/phase-05/00_ADVANCED_TMS_WMS_WBS.md` §6 both require an always-on
container/VPS with a static public endpoint and configurable raw TCP ports --
explicitly **not** a Vercel Function or an ordinary Supabase Edge Function (neither
supports a long-lived raw TCP listener). This directory is therefore:

- its own `package.json` (not a pnpm workspace member of the repository root -- run
  `pnpm install` inside this directory, separately from the root install);
- its own `tsconfig.json` (Node-only `lib`, no DOM/Next.js plugin);
- excluded from the root `tsconfig.json` (`exclude: ["services/**"]`) and the root
  `eslint.config.js` (`ignores: ["services/**"]`) -- its own gate surface is `pnpm run
  typecheck` and `pnpm run test`, run from *this* directory, not the root `pnpm run
  typecheck`/`pnpm run lint`/`pnpm run test`;
- never imported by, or importing from, the main app's `server/`/`lib/` trees. Its own
  Supabase RPC client (`src/ingestClient.ts`) intentionally duplicates the wire shape of
  `server/mutations/gps-gateway-ingestion.ts` rather than sharing code with it.

## Architecture

- `src/codec8e.ts` -- the Teltonika Codec 8 Extended binary protocol: IMEI handshake,
  AVL data packet decoding (GPS element + all five IO-element width categories),
  CRC-16/IBM (ARC) validation. `encodeAvlDataPacket` is a test/simulator-only helper --
  a real device never receives it back.
- `src/server.ts` -- the raw `net.Server` TCP listener. Per-connection state machine
  (`awaiting_handshake` -> `awaiting_avl_data`); serializes concurrent `'data'` events
  through a promise chain so an in-flight RPC round-trip never races a later chunk.
  Malformed/oversized packets close the connection immediately, never crash the process.
  Since `CG-S10-ATW-027` (Prompt 246): rejects a second concurrent handshake for an IMEI
  that already has an open connection; every connection carries an idle-read timeout and
  the server enforces a `maxConnections` cap (see "Known, disclosed limitations" below).
- `src/buffer.ts` -- durable local buffering (`226_GPS_TELEMATICS_INTEGRATION_
  PROMPT.md` §14B). A live ingest failure durably persists the batch to a local
  newline-delimited JSON file rather than dropping it or blocking the device's own ACK;
  `src/index.ts` runs a periodic background flush loop against it. Since `CG-S10-ATW-027`
  (Prompt 246): a flush pass classifies each failure as PERMANENT (dead-lettered --
  skipped, removed from the queue, logged, never retried) or TRANSIENT (halts the pass,
  preserving oldest-first ordering) -- one device going permanently bad no longer blocks
  every other device sharing this one buffer file indefinitely.
- `src/ingestClient.ts` -- calls `app.resolve_gps_device_for_handshake`/
  `app.ingest_direct_device_telemetry_batch` (both `service_role`-only,
  `supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql`)
  using a scoped API key (`app.authenticate_api_key`/`app.api_key_has_scope`, `PLT-129`)
  layered inside the `service_role` credential -- defense in depth, so this gateway
  instance's own credential can be revoked without rotating the whole `service_role`
  secret.
- `src/health.ts` -- `/healthz`, `/readyz`, `/metrics` (plain-text) HTTP endpoints.
- `src/index.ts` -- entrypoint; env-var-only configuration (see below).
- `src/logger.ts` -- structured JSON-line logging. Since `CG-S10-ATW-027` (Prompt 246):
  redaction now scans STRING VALUES (both the free-text `message` and every string field
  value, not just `fields`' own keys) for a credential-shaped pattern, and `message` is
  truncated to a bounded length -- closing the gap where server.ts's own dominant
  logging pathway (dynamic/error-derived content routed through `message`) bypassed the
  original key-only redaction entirely.

## Configuration (environment variables)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SUPABASE_URL` | yes | -- | The Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | -- | `service_role` credential (never `anon`) |
| `GPS_GATEWAY_API_KEY` | yes | -- | A raw `app.api_keys` value scoped `OPS:Edit`, minted via `app.create_api_key` |
| `GPS_GATEWAY_INSTANCE_LABEL` | no | `gps-gateway` | Actor label recorded on every `app.audit_logs` event this gateway produces |
| `GPS_GATEWAY_TCP_PORT` | no | `6060` | Raw TCP port devices connect to |
| `GPS_GATEWAY_TCP_HOST` | no | `0.0.0.0` | TCP bind address |
| `GPS_GATEWAY_HEALTH_PORT` | no | `8080` | Health/readiness/metrics HTTP port |
| `GPS_GATEWAY_HEALTH_HOST` | no | `0.0.0.0` | Health HTTP bind address |
| `GPS_GATEWAY_BUFFER_FILE_PATH` | no | `./data/telemetry-buffer.jsonl` | Durable buffer file path |
| `GPS_GATEWAY_FLUSH_INTERVAL_MS` | no | `30000` | Background buffer-flush interval |
| `GPS_GATEWAY_IDLE_TIMEOUT_MS` | no | `60000` | Per-connection idle-read timeout (`CG-S10-ATW-027`) |
| `GPS_GATEWAY_MAX_CONNECTIONS` | no | `10000` | `net.Server.maxConnections` cap (`CG-S10-ATW-027`) |

## Running

```sh
cd services/gps-gateway
pnpm install
pnpm run typecheck
pnpm run test
pnpm run start   # requires the env vars above
```

## External-evidence policy (`226_*.md` §8)

No physical Teltonika hardware or live cellular network exists in this repository's
environment. Protocol correctness is proven by `test/codec8e.test.ts` (deterministic
byte-level decode/encode, including a hand-built packet independent of the encoder, and
the standard CRC-16/ARC check vector for `"123456789"` -> `0xBB3D`) and
`test/server.test.ts` (a real `net.Socket` client speaking the exact wire protocol
against the real server code, including a live-ingest-failure durable-buffering path).
Disclosed as `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` in
`docs/build-log/phase-05/ATW-226D.md`.

## Known, disclosed limitations

- IMEI is looked up globally (across every tenant) at handshake time -- see
  `app.resolve_gps_device_for_handshake`'s own migration header design note 3. A
  duplicate IMEI registered under two tenants is refused, never silently routed
  (`app.register_gps_device` itself now rejects registering an IMEI a different tenant
  already holds -- `imei_registered_to_another_tenant`, `CG-S10-ATW-027`/Prompt 246 --
  and `app.deregister_gps_device`, `OPS:Override`-gated, clears a spurious/erroneous
  registration so it stops ambiguating a victim's own handshake).
- **Accepted residual risk (`CG-S10-ATW-027`/Prompt 246 adversarial review, disclosed in
  full in `supabase/migrations/20260730360000_..._device_driver_mobile_tracking.sql`'s
  own header design note 2):** the raw Teltonika protocol authenticates a device by IMEI
  alone, and an IMEI is not secret (printed on the device/box, often externally
  queryable). `src/server.ts` now rejects a SECOND CONCURRENT connection presenting an
  IMEI that already has one open -- a cheap, always-available, bounded fix -- but a
  patient attacker who waits for the real device's own connection to genuinely end
  (rather than racing a still-open one) is unaffected and can still pass a fresh
  handshake with a known victim IMEI. If that spoofed traffic also respects the existing
  200 km/h impossible-movement ceiling (`app.arbitrate_and_project_vehicle_position`,
  `ATW-226F`), it can still inject plausible false telemetry. Fully closing this would
  require a real device-level PKI/certificate provisioning scheme -- out of reach without
  physical Teltonika hardware to design or validate against (this package's own
  External-evidence policy below) and beyond a bounded hardening task's own scope. Never
  represent the direct-device raw-TCP channel as providing device-identity authentication
  beyond bare IMEI presentation in any customer-facing material.
- `report_type` (`location` vs `heartbeat`) is inferred from whether the AVL record's
  GPS element carries a non-zero fix, since Codec 8 Extended itself has no explicit
  heartbeat/keepalive record type -- a device sending a genuine `(0, 0)` fix (mid-ocean,
  off the coast of West Africa) would be misclassified as a heartbeat. Disclosed,
  accepted: no real CargoGrid customer route passes through that specific point.
- Offline-detection (a device that stops reporting) is not this package's concern --
  `ATW-226F`'s own canonical-telemetry/health layer owns that, matching
  `app.vehicle_tracking_source_priorities`' (`ATW-223`) own disclosed scope boundary.
