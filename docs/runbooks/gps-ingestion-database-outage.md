# Database (Supabase) unreachable during GPS/telematics ingestion — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 5 (`ATW-226C`/`226D`/`226E` ingestion paths; `ATW-226I` closing verification of the buffered/replay behavior)
**Severity class:** `NOT_YET_REHEARSED` against a live Supabase outage — no live Supabase project exists yet (the same disclosed sandbox condition every UI-adjacent Phase-5 checkpoint since `PLT-135` has carried); this describes the *designed* per-source safe-degrade behavior.

> Covers a Supabase/database-layer outage affecting the write path shared by all three ingestion modes: `app.ingest_driver_mobile_report` (`ATW-226C`), `app.ingest_direct_device_telemetry_batch` (`ATW-226D`), and `app.ingest_third_party_provider_webhook_event` (`ATW-226E`, widened at `ATW-226F`/`ATW-226I`). Each mode's own recovery posture differs by design — this runbook covers all three per §2/§4 below, rather than three near-duplicate documents.

## 1. Symptom / trigger

RPC calls into any of the three ingestion functions above start failing with a connection/timeout error rather than a normal returned status row. For `direct_device`, this surfaces as growing entries in the GPS Gateway's own durable local buffer (`services/gps-gateway/src/buffer.ts`) rather than an ingestion failure the device itself ever sees (the gateway ACKs the device once the report is durably buffered locally, before the Supabase write — `226_*.md` §17's own "acknowledge devices after safe buffer acceptance, not after all business processing").

## 2. Impact

Impact differs by source, by design:

- **`direct_device`**: **none to already-buffered reports.** The gateway's `DurableTelemetryBuffer` (append-only NDJSON, oldest-first flush that stops at the first failure and never reorders — `buffer.ts` lines 34-86) holds every report locally until the Supabase write succeeds. Devices are never blocked or told to retry; they keep sending, the gateway keeps buffering.
- **`driver_mobile`**: the PWA's own HTTPS request to `app.ingest_driver_mobile_report` fails outright (no local buffer exists in a browser tab — `226_*.md` §15's own disclosed PWA limitation: "continuous tracking may stop when the browser closes, the OS suspends the page, permission is revoked, or connectivity fails"). The next successful report simply resumes the session; no reconciliation step is needed since nothing was silently dropped from the *server's* own perspective (the request never succeeded).
- **`third_party_platform`**: for `integration_mode='webhook'`, the provider's own webhook delivery fails and the provider's own retry policy governs (out of this repository's control — a case-specific external system, `226_*.md` §16). For `integration_mode='poll'`, no live poll worker exists yet (`app.update_third_party_provider_poll_cursor` is structurally represented, not executed — `ATW-226E`'s own disclosed design note 6), so this mode has no real outage behavior to rehearse yet.

Across all three: **canonicalization/arbitration never runs speculatively** — `app.arbitrate_and_project_vehicle_position` is only ever called after its own raw insert already committed, so a database outage during the raw insert itself simply means the whole ingestion call fails (buffered for later retry, per source, as above), never a partial/inconsistent canonical state.

## 3. Diagnosis steps

1. Confirm the outage is genuinely database-layer, not a single ingestion function's own defect — check whether *unrelated* RPCs (any other capability) are also failing against the same Supabase project.
2. For `direct_device`: check `/metrics` (`services/gps-gateway/src/health.ts`) for the buffer-depth counter growing without a corresponding flush-success counter increase.
3. For `third_party_platform` webhook mode: check the provider's own delivery-failure dashboard (external, out of this repository's control) for their own retry/backoff state.

## 4. Resolution steps

1. Restore Supabase connectivity (standard platform-level recovery — outside this capability's own repository-controlled scope).
2. **`direct_device` replay**: once connectivity returns, the gateway's own buffer flush loop resumes automatically on its next scheduled attempt, replaying oldest-first, stopping again at the first failure if the outage recurs — no manual replay command exists or is needed; the buffer *is* the replay mechanism.
3. **`driver_mobile`**: no replay needed — nothing was buffered client-side to begin with (§2); the driver's own next report simply resumes.
4. **`third_party_platform`**: rely on the provider's own webhook retry policy; `provider_event_id`'s own per-connection partial unique index (`ATW-226E`) makes any provider-side retry safe — a genuinely retried delivery of the same event returns `duplicate`, never a second row.
5. **Rollback procedure if resolution fails:** none needed at the application layer for any of the three modes — each degrades safely by design (§2); "rollback" here means reverting a bad *Supabase-side* configuration change via the platform's own standard path, not a data or schema rollback in this repository.

## 5. Communication

Today: none required — no production deployment exists. Once deployed: notify DevOps/on-call; escalate to a Sev1/Sev2 posture only if the outage duration risks exceeding the GPS Gateway's own local disk capacity for the durable buffer (a genuine, if currently unrehearsed, "safe-degrade design still has a bound" risk worth naming honestly rather than claiming unlimited buffering).

## 6. Post-incident

For `direct_device`: confirm the buffer drained to zero backlog and `app.canonical_telemetry_events`'s own `received_at` sequence shows no gap for affected vehicles beyond the outage window itself. For `third_party_platform`: confirm the provider's own delivery log shows zero permanently-dropped events (their own DLQ/dead-letter state, if any) — CargoGrid's own quarantine mechanism (`app.third_party_provider_ingestion_attempts.result='quarantined'`) is a separate concept (an unmapped vehicle, not an outage) and should not be confused with a provider-side delivery failure.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-03 | Rehearsal (unit-level, `direct_device` buffer only) | Append/flush-stops-on-first-failure/re-entrant-no-op behavior confirmed | `services/gps-gateway/test/buffer.test.ts` |

A live database-outage rehearsal (a real Supabase connectivity interruption against a real deployed gateway, PWA session, and provider webhook) is required before this runbook can be marked fully rehearsed — tracked as a post-deployment item, not claimed complete here.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-03 | 0.1.0 | Initial — instantiated at `ATW-226I` | Claude Code (runtime build agent) |
