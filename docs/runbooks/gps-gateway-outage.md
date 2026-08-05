# GPS Gateway (direct-device) unreachable or crashed — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 5 (`ATW-226I`, Prompt 226's closing decomposition child)
**Severity class:** `NOT_YET_REHEARSED` today — `services/gps-gateway/` has never been deployed to any live registry/orchestrator (`docs/build-log/phase-05/ATW-226D.md`'s own disclosed gap), so this describes the *designed* safe-degrade behavior, not a rehearsed live incident.

> This runbook covers the standalone `services/gps-gateway/` process (`ATW-226D`) — the raw-TCP Teltonika Codec 8 Extended listener, separately deployed from the Vercel serverless application. It does **not** cover the driver-mobile HTTPS path (`ATW-226C`, ordinary Vercel availability) or the third-party webhook path (`ATW-226E`/`ATW-226I`, see `docs/runbooks/third-party-provider-outage.md`).

## 1. Symptom / trigger

`/healthz` (`services/gps-gateway/src/health.ts`) stops returning `200`, or `/readyz` returns `503` (its own `getReady()` callback going false), or the container's own Docker `HEALTHCHECK` (`services/gps-gateway/Dockerfile`, curling `/healthz`) starts failing. Devices themselves will show repeated TCP reconnect attempts against their configured public endpoint.

## 2. Impact

**By design, none to the serverless application or to already-accepted data.** The GPS Gateway is architecturally independent from Vercel (`226_*.md` §32: "The serverless application must continue operating when the GPS Gateway is disabled") — every other source (`driver_mobile`, `third_party_platform`) and every already-canonicalized position/history row is completely unaffected. Impact is confined to: (a) no *new* `direct_device` telemetry is ingested while the gateway is down, so `app.vehicle_source_health` for that source will age past `freshness_threshold_seconds` and report `stale`/`offline` (`app.get_vehicle_source_health`, `ATW-226F`); (b) `app.arbitrate_and_project_vehicle_position`'s own priority/freshness logic will fall back to a lower-priority source if one is configured and healthy (`ATW-226A`'s own tenant/vehicle source-priority policy), or the vehicle's current position simply goes stale if `direct_device` was the only configured source for it.

## 3. Diagnosis steps

1. Check the gateway process's own `/healthz`/`/readyz`/`/metrics` (`services/gps-gateway/src/health.ts`) directly — `/metrics` exposes `gps_gateway_<key> <value>` counters (connection/parse/ack/buffer counts) that distinguish "process is up but no devices are connecting" from "process itself crashed."
2. Check the durable local buffer (`services/gps-gateway/src/buffer.ts`, an append-only NDJSON file) for an unusually large backlog. Since `CG-S10-ATW-027` (Prompt 246), a flush pass distinguishes PERMANENT failures (e.g. a device that became `device_not_ingestible`/`tenant_mismatch` mid-flight — dead-lettered, removed from the queue, logged, never retried) from TRANSIENT ones (anything else, presumed connectivity — still halts the pass at that point, oldest-first ordering preserved for the next attempt). A large backlog after a Supabase-side recovery therefore indicates a genuine TRANSIENT run needing drainage (see `docs/runbooks/gps-ingestion-database-outage.md` for that case) — look for `"durable buffer dead-lettered a permanently-failing batch"` log lines (one per dead-lettered batch, with `deviceId`/`reportCount`/`reason`) to distinguish that from device-specific permanent rejections that were already skipped and will never clear on their own.
3. Confirm the container/process itself is running (`docker ps` / orchestrator dashboard, once one exists) versus a network-level reachability problem (public TCP port blocked, DNS, load balancer) — `services/gps-gateway/src/logger.ts`'s own structured JSON stdout logs (with `SENSITIVE_KEY_PATTERN` redaction already applied) are the first place to look for a crash stack trace.

## 4. Resolution steps

1. If the process crashed: restart it (the Dockerfile's own `HEALTHCHECK` should already trigger an orchestrator-level restart once a real orchestrator exists — none is wired yet, disclosed in `docs/build-log/phase-05/ATW-226D.md`).
2. If credentials are the cause (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`/`GPS_GATEWAY_API_KEY` — `services/gps-gateway/src/index.ts`'s own `requireEnv()`, which fails loudly rather than defaulting): rotate/restore per `scripts/env/schema.ts`'s server-only secret classification pattern (`ADR-0003`) and restart.
3. Once the gateway is back and `/readyz` returns `200`, devices reconnect on their own configured retry interval — no manual device-side action is required. The durable buffer (§3.2) replays its own backlog in order once the process resumes writing to Supabase.
4. **Rollback procedure if resolution fails:** disable the affected vehicles' `direct_device` source at the tenant/vehicle level (`app.set_vehicle_tracking_source_priority`, `ATW-223`/`ATW-226A`) so arbitration falls back to a configured lower-priority source rather than silently going stale; re-enable once the gateway is confirmed healthy again.

## 5. Communication

Today: none required — no production deployment exists. Once deployed: notify DevOps/on-call; no customer-facing communication is warranted unless `direct_device` is a tenant's *only* configured source and the outage exceeds their own `freshness_threshold_seconds` long enough to visibly stale their Fleet Control Tower (`ATW-226H`).

## 6. Post-incident

Confirm the durable buffer drained cleanly with no gap in `app.canonical_telemetry_events`'s own `received_at` sequence for affected vehicles, and that no device's own reconnect logic silently dropped data rather than buffering it locally first.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-03 | Rehearsal (unit-level, not a live deployment) | Durable buffer append/flush-stops-on-first-failure/re-entrant-no-op behavior confirmed | `services/gps-gateway/test/buffer.test.ts` |

A live-deployment rehearsal (a real container against a real orchestrator, with a real network partition) is required before this runbook can be marked fully rehearsed — tracked as a post-deployment item, not claimed complete here (`226_*.md` §8's own external-evidence policy: hardware/live-provider evidence is honestly deferred, not fabricated).

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-03 | 0.1.0 | Initial — instantiated at `ATW-226I` | Claude Code (runtime build agent) |
| 2026-08-05 | 0.2.0 | `CG-S10-ATW-027` (Prompt 246) hardening: §3 step 2 updated for the buffer's own new permanent-vs-transient failure classification (a permanently-failing device's batch is now dead-lettered and logged, never blocking every other device's own backlog); the raw TCP handshake now rejects a second concurrent connection for an already-open IMEI (`services/gps-gateway/src/server.ts`) and enforces a per-connection idle-read timeout plus a `maxConnections` cap. See `services/gps-gateway/README.md`'s own "Known, disclosed limitations" section for the residual, NOT-fully-fixed risk this checkpoint's own adversarial review left honestly disclosed (a patient, sequential IMEI spoof is not addressed by an in-process concurrency check alone). | Claude Code (runtime build agent) |
