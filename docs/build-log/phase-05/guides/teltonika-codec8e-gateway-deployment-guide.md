# Teltonika Codec 8 Extended and GPS Gateway Deployment Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), the TECHNICAL/HARDWARE/PROTOCOL/OPERATIONS half of this checkpoint.
**Audience:** DevOps/whoever deploys `services/gps-gateway`, and developers who need the exact wire protocol it speaks.
**Source of truth:** `services/gps-gateway/src/{codec8e,server,index,buffer,logger}.ts`, `services/gps-gateway/Dockerfile`, `services/gps-gateway/README.md`, `supabase/migrations/20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql` (`CG-S10-ATW-027`). Read the source directly for exact byte offsets and current env-var defaults; this guide explains and cites it, it does not redefine it.
**Companion documents:** `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` (how a device gets to the point of dialing in), `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` (health/metrics/firewall/scaling, kept separate from this deployment guide rather than duplicated), `services/gps-gateway/README.md` (extended, not replaced, by this checkpoint — see its own "Related documentation" section).

## 1. What this deploys

`services/gps-gateway` is a standalone Node.js package — **not** part of the Next.js app, not deployed to Vercel, and not built from the repository root. It is an always-on raw TCP listener speaking the Teltonika Codec 8 Extended protocol, required because neither a Vercel Function nor an ordinary Supabase Edge Function can hold a long-lived raw TCP socket open (`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/219_ADVANCED_TMS_WMS_README.md` §4.3/§5: "Do not pretend a Vercel Function or ordinary Supabase Edge Function is a permanent raw TCP listener"). It has its own `package.json`, `pnpm-lock.yaml`, and `tsconfig.json`, is excluded from the root `tsconfig.json` (`exclude: ["services/**"]`) and root `eslint.config.js` (`ignores: ["services/**"]`), and never imports from or is imported by the main app's `server/`/`lib/` trees (`services/gps-gateway/README.md` "Why this is a separate package").

**No hosting platform has been chosen or stood up for this service anywhere in this repository.** No ADR resolves which container/VPS platform runs it (`docs/adr/` has no gateway-hosting ADR), no live registry or orchestrator exists, and `docs/build-log/phase-05/ATW-226I.md` §9 discloses this directly: "`services/gps-gateway/` has never been deployed to any live registry/orchestrator... the Dockerfile builds and typechecks... but no live container has ever run against a real network." Everything in this guide describes how to deploy the real, tested Dockerfile against whatever Docker-compatible container platform an operator chooses — it is not a claim that a specific platform has already been selected or exercised.

### 1.1 The Dockerfile (`services/gps-gateway/Dockerfile`)

A two-stage build:

- **Builder stage** (`node:22-slim`): installs `devDependencies` (TypeScript, for the typecheck gate only), copies `src`/`test`, runs `pnpm run typecheck`. The package ships as plain `.ts` run via `node --experimental-strip-types` — there is no compiled `dist/` to emit; the builder stage exists purely to fail the image build if the code does not typecheck.
- **Runtime stage** (`node:22-slim`): installs production dependencies only (`pnpm install --prod`), copies `src` (not `test`), sets `NODE_ENV=production`.
- **`EXPOSE 6060 8080`** — the raw TCP device-listener port and the health/readiness/metrics HTTP port, documenting the image's own out-of-the-box defaults (both are independently overridable via env vars, §2).
- **`HEALTHCHECK`** — polls `http://127.0.0.1:<GPS_GATEWAY_HEALTH_PORT or 8080>/healthz` every 30s (5s timeout, 10s start period, 3 retries) using a bare `node -e fetch(...)` call, no extra dependency.
- **`CMD ["node", "--experimental-strip-types", "src/index.ts"]`** — runs the TypeScript source directly.

Build it from inside `services/gps-gateway/`:

```sh
cd services/gps-gateway
docker build -t cargogrid/gps-gateway:latest .
```

## 2. Environment variables (the complete, current list — read directly from `src/index.ts`)

`services/gps-gateway` is configured entirely by environment variables — no config file, matching this repository's own `scripts/env/` convention of failing loudly on a missing required value rather than silently defaulting a secret (`services/gps-gateway/src/index.ts`'s own header). These are a **separate** set of environment variables from the root Next.js app's own `scripts/env/schema.ts` — the gateway is an independently deployed process and does not share that schema.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SUPABASE_URL` | yes | — | The Supabase project URL the gateway's own RPC client connects to |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | — | `service_role` credential — never `anon`. Missing/empty causes `main()` to throw `missing_required_env` and exit(1) before the process ever starts listening |
| `GPS_GATEWAY_API_KEY` | yes | — | A raw `app.api_keys` value scoped `OPS:Edit`, minted via `app.create_api_key` (§3) — layered *inside* the `service_role` credential as defense in depth, so this one gateway instance's own credential can be revoked/rotated without rotating the whole `service_role` secret |
| `GPS_GATEWAY_INSTANCE_LABEL` | no | `gps-gateway` | Actor label recorded on every `app.audit_logs` event this gateway instance produces (e.g. `gps-gateway:<imei>` on a handshake event) — set a distinct value per gateway instance if running more than one, so audit evidence can tell them apart |
| `GPS_GATEWAY_TCP_PORT` | no | `6060` | Raw TCP port devices connect to |
| `GPS_GATEWAY_TCP_HOST` | no | `0.0.0.0` | TCP bind address |
| `GPS_GATEWAY_HEALTH_PORT` | no | `8080` | Health/readiness/metrics HTTP port |
| `GPS_GATEWAY_HEALTH_HOST` | no | `0.0.0.0` | Health HTTP bind address |
| `GPS_GATEWAY_BUFFER_FILE_PATH` | no | `./data/telemetry-buffer.jsonl` | Durable local buffer file path — must be on a persistent volume if the container's own filesystem does not survive a restart (see `docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md`) |
| `GPS_GATEWAY_FLUSH_INTERVAL_MS` | no | `30000` | How often the background loop retries flushing the durable buffer against Supabase |
| `GPS_GATEWAY_IDLE_TIMEOUT_MS` | no | `60000` | Per-connection idle-read timeout, milliseconds — added at `CG-S10-ATW-027` (finding 6, TCP socket exhaustion). A connection with zero bytes received for this long is destroyed |
| `GPS_GATEWAY_MAX_CONNECTIONS` | no | `10000` | `net.Server.maxConnections` — added at `CG-S10-ATW-027` (finding 6). Node destroys any connection beyond this cap before the `'connection'` handler even runs |

This is the complete list — `src/index.ts` reads exactly these eleven variables and no others. If a future checkpoint adds a new one, extend this table rather than duplicating it elsewhere; `services/gps-gateway/README.md` carries the same table and both should stay in sync (this guide adds narrative around it, the README is the terser canonical reference).

## 3. Minting `GPS_GATEWAY_API_KEY`

The gateway authenticates itself to Supabase using a **scoped API key**, not the bare `service_role` credential presented directly by devices — `app.resolve_gps_device_for_handshake`/`app.ingest_direct_device_telemetry_batch` (`ATW-226D`) both call `app.authenticate_api_key(p_raw_api_key)` then require `app.api_key_has_scope(api_key_id, 'OPS:Edit')` before doing anything else.

1. Mint the key with `app.create_api_key(p_tenant_id, p_name, p_scopes, p_expires_at, p_rate_limit_per_minute, p_actor_auth_user_id, p_actor_label)` (`PLT-129`), with `p_scopes` containing at least `["OPS:Edit"]`. The actor minting it must themselves already hold `OPS:Edit` for that tenant — a key's scopes can only narrow what the issuing actor already holds, never widen it.
2. The function returns the raw key in its own `raw_key` column **exactly once** — only `key_hash` (a one-way SHA-256 digest) is ever stored afterward. Capture it immediately (e.g. into whatever secret manager the chosen hosting platform uses) — there is no way to redisplay it later.
3. Set it as `GPS_GATEWAY_API_KEY` in the deployed container's own environment.
4. **A bad, revoked, or expired key fails every single handshake, loudly.** `app.authenticate_api_key` raises `api_key_not_found`/`api_key_revoked`/`api_key_expired` (never returns a soft "rejected" row) for a bad credential — `GpsGatewayIngestClient.resolveHandshake` (`services/gps-gateway/src/ingestClient.ts`) lets that exception propagate, and `server.ts`'s own `drainAccumulator` catches it, increments `handshakesRejected`, writes the `0x00` rejection byte, and closes the connection with `handshake_authentication_failed` logged. If **every** device connecting to a gateway instance is being rejected at the handshake stage (not just one specific IMEI), check the gateway's own credential before suspecting a device-side problem — this is the single most common gateway-wide (not per-device) failure mode.
5. Rotation: `app.rotate_api_key(p_key_id, p_overlap_minutes, ...)` (`PLT-129`) supports an overlap window (0–10080 minutes; 0 means immediate revoke) — mint the new key, update the deployed environment, restart the gateway process, then let the overlap window elapse before the old key stops working, rather than an instant cutover that would reject every in-flight connection using the old key.

## 4. The wire protocol (Teltonika Codec 8 Extended over raw TCP)

Implemented byte-for-byte in `services/gps-gateway/src/codec8e.ts`, matching the vendor's own publicly documented frame layout — not a simplified stand-in. Two phases per TCP connection.

### 4.1 Phase 1 — IMEI handshake

The device opens a TCP connection and sends, as its very first bytes:

```
[2-byte big-endian length][that many ASCII-digit bytes = the IMEI]
```

`decodeImeiHandshake` (`codec8e.ts`) reads the 2-byte length, waits for that many more bytes if they have not all arrived yet (never treats a short buffer as malformed — only rejects once the declared length's worth of bytes has actually arrived and fails the all-digit check), and throws `malformed_imei_handshake` if the bytes are not all ASCII digits.

The gateway replies with exactly **one byte**:

- `0x01` — handshake accepted, the device may proceed to phase 2.
- `0x00` — handshake rejected. The gateway closes the connection immediately afterward; it never leaves a rejected connection half-open.

Server-side, acceptance requires (in order, `services/gps-gateway/src/server.ts` `drainAccumulator`):

1. `app.resolve_gps_device_for_handshake` returns `accepted = true` (device known, correct tenant for the presented API key, and in an ingestible status — `installed`, `active`, or `offline`; see `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` §3 for the full status machine).
2. The presented IMEI does not already have another **currently open** connection on this same gateway process (`CG-S10-ATW-027` finding 2 — see §6 below). If it does, the second handshake is rejected with `handshake_rejected: imei_already_connected`.

### 4.2 Phase 2 — AVL data packets

Once accepted, the device streams AVL (Automatic Vehicle Location) data packets on the same connection. Each packet:

```
[4-byte zero preamble]
[4-byte big-endian data-field length]
[data field:
   [1-byte codec ID, must be 0x8E]
   [1-byte record count]
   [record]... (one per declared record, see below)
   [1-byte record count, repeated — must match the header's own count]
]
[4-byte CRC-16/IBM (ARC) of the data field, big-endian]
```

Each record inside the data field:

```
[8-byte big-endian timestamp, milliseconds since epoch]
[1-byte priority]
[GPS element: 4-byte lon, 4-byte lat (both signed, ×10,000,000 fixed-point),
 2-byte altitude (meters), 2-byte angle (degrees), 1-byte satellite count, 2-byte speed (km/h)]
[IO element block: event IO ID (2 bytes), total count (2 bytes), then five
 width-grouped sub-blocks — 1-byte, 2-byte, 4-byte, 8-byte, and variable-length
 IO values, each sub-block prefixed with its own element count]
```

`crc16Ibm` implements CRC-16/IBM (ARC): polynomial `0xA001`, initial value `0x0000`, no final XOR — verified in `services/gps-gateway/test/codec8e.test.ts` against the standard `"123456789"` → `0xBB3D` check vector. A CRC mismatch, a non-`0x8E` codec ID, a header/trailer record-count mismatch, or an IO-element count that does not match its own declared total all throw a structural error (`crc_mismatch`, `unsupported_codec_id`, `record_count_mismatch`, `io_element_count_mismatch`) — the server catches every one of these, increments `packetsRejected`, and closes the connection without an ACK and without crashing the process. One malformed connection never affects any other concurrent connection.

On success, the gateway replies with a **4-byte big-endian count of accepted records** (`encodeAckResponse`) — the real Teltonika ACK shape; a real device retransmits the whole packet if this count does not match what it sent. The ACK is sent once the batch is durably persisted (either written live to Supabase, or, on a live-ingest failure, appended to the local durable buffer — `docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md`), never withheld pending full downstream processing.

A device reporting `(0, 0)` for latitude/longitude — no GPS fix — is stored as `reportType = 'heartbeat'` rather than `'location'` (`recordToReport`, `server.ts`) since Codec 8 Extended has no explicit heartbeat record type of its own. This is a disclosed, accepted simplification (`services/gps-gateway/README.md` "Known, disclosed limitations") — a device genuinely reporting a real `(0, 0)` fix (mid-ocean, off the coast of West Africa) would be misclassified. No real CargoGrid route is expected to pass through that exact point.

## 5. Deployment steps

1. Build the image (§1.1).
2. Mint `GPS_GATEWAY_API_KEY` (§3).
3. Run the container with the env vars from §2 set, publishing (or otherwise making reachable) TCP `6060` to the device network and HTTP `8080` to whatever monitors it — see `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` for the exact firewall posture.
4. Mount `GPS_GATEWAY_BUFFER_FILE_PATH`'s own directory on a persistent volume — a container filesystem that resets on restart would silently discard any batch buffered but not yet flushed at the moment of restart. This is an operational requirement this guide states explicitly; nothing in the code enforces it, since the process has no way to know whether its own filesystem is ephemeral.
5. Confirm `/healthz` returns `200` and `/readyz` returns `200` once the process reports ready (both bind after the TCP listener and the health server itself are both up — `src/index.ts`'s own `main()` sets `ready = true` only after both `server.listen()` and `health.listen()` resolve).
6. Point device SIM APN configuration or a network route at the gateway's own public TCP endpoint, per `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` §7.1 step 5.
7. On `SIGTERM`/`SIGINT`, the process sets `ready = false` (so a load balancer/orchestrator health check can stop routing new connections to it), clears the flush timer, and closes both the TCP and health servers before exiting — a graceful shutdown an orchestrator's own rolling-restart logic can rely on.

## 6. Residual risk: IMEI-only "authentication" is spoofable — this is not fully closed by code

This is the single most important operational fact in this guide, stated exactly as disclosed in the migration header (`supabase/migrations/20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql`, design note 2) and `services/gps-gateway/README.md`'s own "Known, disclosed limitations":

**The raw Teltonika protocol authenticates a device by IMEI alone, and an IMEI is not secret** — it is printed on the device and its packaging, and is often externally queryable. `CG-S10-ATW-027` (Prompt 246) hardened one narrow, cheap, always-reproducible half of this: `services/gps-gateway/src/server.ts` now tracks in-flight IMEI → "has an open connection" state in-process (`activeImeis`) and rejects a **second concurrent** handshake for an IMEI that already has one open (§4.1). This closes the case where an attacker races the real device's own live connection.

**What this does not close, and what remains an accepted, disclosed residual risk:** a patient attacker who waits for the real device's own connection to genuinely end (rather than racing a still-open one) is unaffected by the concurrency check and can still pass a fresh handshake presenting a known victim IMEI. If the spoofed traffic also respects the existing 200 km/h impossible-movement ceiling (`app.arbitrate_and_project_vehicle_position`, `ATW-226F`, hardened further at `CG-S10-ATW-027` for an unrelated future-timestamp defect), it can still inject plausible false telemetry attributed to the victim's device.

Fully closing this would require a real device-level PKI/certificate provisioning scheme — explicitly out of reach without physical Teltonika hardware to design and validate against (this repository's own External-evidence policy, §7 below) and beyond the bounded scope of the hardening checkpoint that found it.

**This is an operational requirement for any real deployment, not a code change this repository has made or claims to have made:** compensating network-layer controls — a private APN dedicated to CargoGrid's own fleet SIMs, a VPN/tunnel between the cellular carrier and the gateway's own network, or a static-IP allowlist per device/SIM if the carrier supports one — are required to make IMEI-spoofing impractical in practice, since none of them is implemented in this repository's code today. **Never represent the direct-device raw-TCP channel as providing device-identity authentication beyond bare IMEI presentation in any customer-facing material** — this is the migration header's own required permanent disclosure, restated here for the deployment audience specifically.

## 7. External-evidence policy for this deployment guide

No physical Teltonika hardware or live cellular network exists anywhere in this repository's environment. Every claim in §4 (protocol correctness) is proven by `services/gps-gateway/test/codec8e.test.ts` (16 deterministic byte-level cases, including a hand-built packet independent of the encoder and the standard CRC-16/ARC check vector) and `services/gps-gateway/test/server.test.ts` (10 cases, a real `net.Socket` client speaking the exact wire protocol against the real server code, including handshake accept/ACK, IMEI rejection, live-ingest-failure durable buffering, malformed-packet rejection, and two packets arriving in one TCP chunk). This is real, repository-controlled evidence, not a substitute claim of physical-hardware testing — see `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` for the formal `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` record and the exact procedure a first real device would need to follow.
