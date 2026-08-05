# Queue, Dead-Letter, Replay, and Reconciliation Procedure

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), the TECHNICAL/HARDWARE/PROTOCOL/OPERATIONS half of this checkpoint.
**Audience:** developers building a worker against `app.jobs`, DevOps operating a deployed GPS Gateway, and anyone reconciling a backlog after an outage.
**Source of truth:** `supabase/migrations/20260719170000_create_import_export_job_framework.sql` (`PLT-131`), `supabase/migrations/20260719180000_create_background_job_framework.sql` (`PLT-132`), `docs/adr/ADR-0013-job-queue-retry-lease-defaults.md`, `services/gps-gateway/src/buffer.ts`, `docs/build-log/phase-05/ATW-024.md` (the real load/recovery evidence), `docs/runtime/KNOWN_ISSUES.md` (`ISS-2026-015`).
**Companion documents:** `docs/runbooks/gps-gateway-outage.md`, `docs/runbooks/gps-ingestion-database-outage.md`, `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md`.

## 1. Read this first: there are two different queue/DLQ mechanisms, not one

Do not conflate them — they live in different code, are operated differently, and one of them does **not** currently have anything GPS-specific in it despite how this document's own name might read at a glance:

| | `app.jobs` (Postgres durable queue, `PLT-131`/`132`) | The GPS Gateway's own durable local buffer (`services/gps-gateway/src/buffer.ts`) |
|---|---|---|
| Where it lives | Inside Supabase Postgres, a normal table | A local append-only NDJSON file on the gateway container's own disk |
| What it queues | Generic platform background work: `import`, `export`, `report_generation`, `notification_batch`, `webhook_retry`, `document_generation`, `dashboard_refresh`, `loyalty_expiration`, `recurring_billing`, `integration_sync`, `route_load_planning`, `print_label` | Exactly one thing: a decoded, ACK-ready GPS telemetry batch that failed to write live to Supabase |
| GPS/tracking-specific job type? | **No.** Direct inspection of every `jobs_job_type_check` constraint across every migration confirms no `job_type` value for GPS telemetry, third-party polling, or any tracking-domain concept exists anywhere in this schema today | N/A — it is not `app.jobs`-shaped at all; it has no `job_type` concept |
| Real load/recovery evidence | `scripts/load-tests/` Scenario 3/3d (§3 below) | `scripts/load-tests/` Scenario 4's own outage sub-case (§4 below), and `services/gps-gateway/test/buffer.test.ts` |

**If you came here expecting "the real `app.jobs` queue widened for GPS/tracking use," that specific claim is not accurate as written and this document deliberately does not repeat it.** `ATW-226D`'s own migration header states the actual design decision directly: "`app.jobs` (`PLT-131`/`PLT-132`) is deliberately not used for live ingestion... `services/gps-gateway`'s own local durable buffer is where that genuinely lives, not a second, redundant server-side queue." What *is* true, and is the real, evidence-backed connection between the two: `scripts/load-tests/`'s own harness proves both mechanisms' queue/DLQ/backlog/recovery characteristics in the same suite, and a real future third-party-provider **poll** worker (§5) is the one place `ATW-226E`'s own migration header names `app.jobs` as its intended future home — not built yet (§5).

## 2. `app.jobs` — the generic platform queue

### 2.1 Lifecycle

```
app.enqueue_job(tenant_id, job_type, payload, priority, idempotency_key, max_attempts, actor_auth_user_id, actor_label)
  -> status='pending'

app.claim_next_job(worker_id, job_types[], lease_duration_seconds default 300)
  -> SELECT ... FOR UPDATE SKIP LOCKED, ordered (priority desc, created_at asc)
  -> status='in_progress', locked_by=worker_id, locked_until=now()+lease

app.heartbeat_job(job_id, worker_id, lease_duration_seconds default 300)
  -> extends locked_until; rejects (job_lease_not_held) if the caller does not hold the current lease

app.complete_job(job_id, worker_id, result_url, actor_label)
  -> status='completed', lease released

app.record_job_failure(job_id, error_message, actor_auth_user_id, actor_label)
  -> attempts += 1
  -> if attempts >= max_attempts: status='dead_letter' (terminal)
  -> else: status='pending', next_attempt_at = now() + backoff (see 2.2), lease released

app.requeue_dead_letter_job(job_id, actor_auth_user_id, actor_label)
  -> requires support/supreme authority (app.check_import_export_admin_authority)
  -> only valid from status='dead_letter'
  -> status='pending', attempts=0, error=null, lease cleared -- immediately claimable
```

`app.claim_next_job` uses `FOR UPDATE SKIP LOCKED` — PostgreSQL's own standard, documented-since-9.5 mechanism guaranteeing no two concurrent workers ever claim the same row, genuinely provable without a live multi-process worker fleet since it is a documented database guarantee, not something this repository invented. A stale lease (an `in_progress` row whose `locked_until` has already passed — the worker that held it crashed or hung) is structurally eligible for reclaim by the same claim query.

### 2.2 Backoff (`ADR-0013`)

`app.compute_job_backoff_seconds(attempts)` implements "equal jitter": base 30 seconds, ×2 multiplier per attempt, capped at 3,600 seconds (1 hour) — half the computed exponential delay is fixed, half is randomized, avoiding both a zero-jitter thundering herd and unbounded full-jitter randomness. These are reasoned defaults (`ADR-0013`), not derived from measured production traffic, since none exists yet.

### 2.3 Real load/recovery evidence (not projected — read directly from the currently committed results)

`scripts/load-tests/results/RESULTS_CG-S10-ATW-024.txt`, Scenario 3 (a synthetic, non-GPS 5,000-job backlog — `report_generation`/`notification_batch`/etc. job types, seeded specifically to prove the generic mechanism, not any GPS-specific one):

```
pending_before=5000
number of transactions actually processed: 6000/6000, 0 failed
duration_seconds=5.371312287 completed=5000 still_pending=0
throughput_jobs_per_sec=930.8
queue age percentiles (seconds, completed_at - created_at):
 p50=20.7755485  p95=22.3048475  p99=22.392952909999998  max=22.418261
SCENARIO 3 RESULT: PASS -- full 5,000-job backlog drained, no lost/double-claimed jobs
```

And, deterministically forcing the dead-letter → replay path end to end (Scenario 3d, added specifically because Scenario 3's own soak sub-case naturally produced zero dead-letters within its own window and so never actually exercised replay):

```
-- max_attempts=1, so the very first app.record_job_failure call dead-letters immediately --
dead_lettered=10 (expected 10)
-- every one replayed via the real app.requeue_dead_letter_job RPC --
replayed_to_pending=10 (expected 10)
-- a real worker claims and completes every replayed job --
completed_after_replay=10 still_dead_letter=0
SCENARIO 3d RESULT: PASS -- all 10 jobs genuinely reached dead_letter, were replayed, and completed
```

This is real evidence for the mechanism `app.jobs` provides. It is not evidence of a GPS-specific job type, because none exists (§1).

## 3. The GPS Gateway's own durable local buffer — a categorically different mechanism

`services/gps-gateway/src/buffer.ts`'s `DurableTelemetryBuffer` is an append-only newline-delimited-JSON file on the gateway container's own local disk (`GPS_GATEWAY_BUFFER_FILE_PATH`, default `./data/telemetry-buffer.jsonl`) — deliberately **not** `app.jobs`, and deliberately not in-memory-only (a process restart mid-outage would silently lose every buffered batch). This is the gateway's own real point of custody transfer: once a batch is appended to this file, the device does not need to hold or retransmit it — the ACK is sent regardless of whether the live Supabase write succeeded (`docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` §4.2).

### 3.1 Flush semantics and permanent-vs-transient classification (`CG-S10-ATW-027`, finding 5)

`src/index.ts` runs a background loop (`GPS_GATEWAY_FLUSH_INTERVAL_MS`, default 30,000ms) calling `buffer.flush(ingestClient)`. Before `CG-S10-ATW-027`, a flush pass halted its **entire** queue on the very first failure, regardless of whether that failure was permanent or transient — a single suspended device's own correctly-rejected batch would permanently block every other device sharing that one gateway process's buffer file. The fix classifies each failure:

- **PERMANENT** (dead-lettered — skipped, removed from the persisted queue, logged, never retried): the batch is structurally invalid, or the owning device/tenant is in a state the server will never accept from. Matched against an explicit allowlist of `app.ingest_direct_device_telemetry_batch`'s own thrown-error prefixes: `device_not_ingestible`, `tenant_mismatch`, `device_not_found`, `reports_required`, `device_id_required`, `invalid_report_type`, `event_at_required`, `location_required`.
- **TRANSIENT** (halts the whole pass at that point — that entry and everything enqueued after it stays buffered, oldest-first ordering preserved for the next attempt): anything **not** matching the permanent allowlist, presumed a network/connectivity-class failure. This is the safe default — misclassifying a real transient failure as permanent would silently drop real telemetry, while the reverse (keeping an unclassified permanent failure as transient) only reproduces the pre-fix behavior for that one specific reason, never a new regression. Deliberately **excludes** `insufficient_authority` from the permanent list — a broken/revoked gateway API key is gateway-wide, not per-device; misclassifying it as permanent would silently dead-letter every device's telemetry forever instead of correctly halting-and-alerting.

```
DurableTelemetryBuffer.flush(client) -> { flushedCount, deadLettered: DeadLetteredBatch[] }
```

Every dead-lettered batch is logged once (`"durable buffer dead-lettered a permanently-failing batch"`, with `deviceId`/`reportCount`/`enqueuedAt`/`reason`) — never a silent drop.

### 3.2 Real load/recovery evidence

`scripts/load-tests/gps-telemetry-load.ts`'s own outage sub-case, run against the real `GpsGatewayServer` + real `DurableTelemetryBuffer` under concurrent load (not merely a single-connection unit test):

```
outage_devices=10 acks_during_outage_failed=0
reports_buffered_during_outage=10 pending_after_outage=10
flushed_after_recovery=10 dead_lettered_after_recovery=0 pending_after_flush=0
live_batches_ingested_by_flush=10
OUTAGE_BUFFER_RECOVERY_SCENARIO: PASS
```

Separately, `services/gps-gateway/test/buffer.test.ts` (7 cases) proves the unit-level append/flush/dead-letter/re-entrant-no-op behavior deterministically, and `scripts/load-tests/`'s own Scenario 7 (`docs/build-log/phase-05/ATW-024.md` §2) proves a **different but related** recovery property at the database layer: a real client `SIGKILL` mid-transaction plus a genuine `pg_ctlcluster` Postgres cluster restart, followed by an idempotency-key retry that returns the original committed result rather than double-applying — real crash-recovery evidence for the write path the gateway's own buffer eventually flushes into, not the buffer file itself.

## 4. Reconciliation procedure for a backlog

### 4.1 `app.jobs` backlog

1. Check `app.jobs` row counts by `status` for the tenant/job_type in question — a growing `pending` count with a shrinking `in_progress` count usually means no worker is currently claiming (see `ISS-2026-015` below), not that jobs are failing.
2. For rows in `dead_letter`: inspect `error` (the last recorded failure message) and `attempts`/`max_attempts` before replaying — `app.requeue_dead_letter_job` resets `attempts` to 0 and makes the row immediately claimable again, so replaying a job whose underlying cause was never fixed will simply fail and dead-letter again after `max_attempts` more tries.
3. `app.requeue_dead_letter_job` requires "support/supreme authority" (`app.check_import_export_admin_authority`) — a bare `OPS:Edit` tenant role is not sufficient; this is a deliberately higher bar than most mutations in this domain.
4. **No live worker/scheduler exists anywhere in this repository yet** (`docs/runtime/KNOWN_ISSUES.md`, `ISS-2026-015`, `OPEN`): no PWA, no `pg_cron` or equivalent, nothing periodically calling `app.claim_next_job` in production. `scripts/load-tests/job-poll-worker.sh` is an explicitly test-only polling-loop driver used to soak-test the queue mechanics (§2.3) — it is **not** a production scheduler, and running it against a live environment would be a misuse of a test tool, not an operational procedure. Until a real scheduler exists, every queued `app.jobs` row remains real but dormant until invoked by hand or by a future dedicated worker capability.

### 4.2 GPS Gateway durable-buffer backlog

1. Check `/metrics`' `gps_gateway_reportsBuffered` counter (cumulative, not current depth — see `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` §1.1) alongside the gateway's own structured logs for `"durable buffer flush"` (successful flush count) and `"durable buffer dead-lettered a permanently-failing batch"` (permanent failures, logged individually) lines.
2. **No manual replay command exists or is needed for a transient backlog** — the buffer *is* the replay mechanism. Once the underlying outage clears, the next scheduled flush (`GPS_GATEWAY_FLUSH_INTERVAL_MS`) automatically drains the backlog oldest-first, stopping again at the first failure if the outage recurs.
3. For a dead-lettered batch (permanent failure — a specific device/tenant, not the whole backlog): the underlying cause (device suspended, device/tenant no longer exists, structurally invalid batch) must be fixed at its source (e.g. `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` §3's status machine) — there is no requeue RPC for this buffer, since the batch bytes themselves are gone once dead-lettered (removed from the persisted queue, per §3.1). This is a real, disclosed difference from `app.jobs`' own `requeue_dead_letter_job`: the gateway buffer's dead-letter path is a final, logged drop of that one batch, not a resumable state.
4. Confirm reconciliation completed by checking `app.canonical_telemetry_events`' own `received_at` sequence for the affected device(s) shows no unexplained gap beyond the outage window itself (`docs/runbooks/gps-ingestion-database-outage.md` §6).

## 5. Third-party polling — structurally represented, not yet a real consumer of either mechanism

`app.third_party_provider_connections.poll_cursor` (an opaque per-provider watermark) and `app.update_third_party_provider_poll_cursor` exist and are tested, but **no live HTTP poll call, and no real `app.jobs` consumer for a poll job type, exists anywhere in this repository** — there is no live provider credential to poll against yet (`docs/build-log/phase-05/guides/third-party-provider-onboarding-and-credential-rotation-guide.md` §2). `ATW-226E`'s own migration header names `app.jobs` as the intended future home for a real poll worker's own scheduling once one is built — this remains a forward-looking design intent, not a shipped integration, and this document does not claim otherwise.

## 6. Related documentation

- `docs/runbooks/gps-gateway-outage.md`, `docs/runbooks/gps-ingestion-database-outage.md` — incident response referencing both mechanisms above.
- `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` — the `/metrics` counters this procedure's own diagnosis steps read.
- `docs/build-log/phase-05/ATW-024.md` — the full load-test harness build log.
