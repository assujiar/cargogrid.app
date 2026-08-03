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
- `src/buffer.ts` -- durable local buffering (`226_GPS_TELEMATICS_INTEGRATION_
  PROMPT.md` §14B). A live ingest failure durably persists the batch to a local
  newline-delimited JSON file rather than dropping it or blocking the device's own ACK;
  `src/index.ts` runs a periodic background flush loop against it.
- `src/ingestClient.ts` -- calls `app.resolve_gps_device_for_handshake`/
  `app.ingest_direct_device_telemetry_batch` (both `service_role`-only,
  `supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql`)
  using a scoped API key (`app.authenticate_api_key`/`app.api_key_has_scope`, `PLT-129`)
  layered inside the `service_role` credential -- defense in depth, so this gateway
  instance's own credential can be revoked without rotating the whole `service_role`
  secret.
- `src/health.ts` -- `/healthz`, `/readyz`, `/metrics` (plain-text) HTTP endpoints.
- `src/index.ts` -- entrypoint; env-var-only configuration (see below).

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
  duplicate IMEI registered under two tenants is refused, never silently routed.
- `report_type` (`location` vs `heartbeat`) is inferred from whether the AVL record's
  GPS element carries a non-zero fix, since Codec 8 Extended itself has no explicit
  heartbeat/keepalive record type -- a device sending a genuine `(0, 0)` fix (mid-ocean,
  off the coast of West Africa) would be misclassified as a heartbeat. Disclosed,
  accepted: no real CargoGrid customer route passes through that specific point.
- Offline-detection (a device that stops reporting) is not this package's concern --
  `ATW-226F`'s own canonical-telemetry/health layer owns that, matching
  `app.vehicle_tracking_source_priorities`' (`ATW-223`) own disclosed scope boundary.
