# Third-party GPS provider connection auto-disabled or misbehaving — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call, Operations administrators — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** Operations administrators (tenant-level recovery), DevOps (platform-level diagnosis)
**Since:** Phase 5 (`ATW-226E` connection/ingestion, `ATW-226I` auto-disable/recovery)
**Severity class:** `NOT_YET_REHEARSED` against a live vendor outage — no live third-party provider contract exists yet (`226_*.md` §8's own `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` allowance); this describes the *designed* behavior, proven by real `db:test` evidence, not a rehearsed live incident.

## 1. Symptom / trigger

A tenant's own `app.third_party_provider_connections.status` shows `disabled` with `disabled_reason = 'consecutive_failure_threshold_exceeded'` and a non-null `auto_disabled_at` — the connection auto-disabled after exactly 10 consecutive HMAC signature-verification failures (`app.ingest_third_party_provider_webhook_event`, widened at `ATW-226I`, reusing `ADR-0011`'s own exact threshold and evidence-column pattern). This most commonly means the provider rotated their signing key without updating CargoGrid, or the connection is being probed with forged signatures.

## 2. Impact

**No impact to already-canonicalized data or to any other source type for the same vehicle.** While disabled, every further webhook call for this connection is rejected at the connection-status check with `ingest_status='invalid'`/`reason='connection_not_active'` — before signature verification even runs — so no further raw payload is accepted, but nothing already ingested is affected, and `app.arbitrate_and_project_vehicle_position` simply stops receiving new `third_party_platform` candidates for vehicles mapped through this connection. If a tenant configured `third_party_platform` as a vehicle's *only* source, that vehicle's current position goes stale (`app.vehicle_source_health` ages past `freshness_threshold_seconds`) until the connection is recovered.

Tenant/isolation implications: none — the auto-disable is scoped to exactly one `(tenant_id, provider_code)` connection row; no other tenant's own connection is affected regardless of cause.

## 3. Diagnosis steps

1. Confirm the auto-disable reason: `select status, consecutive_failure_count, auto_disabled_at, disabled_reason from app.third_party_provider_connections where id = <connection_id>` (or the equivalent `getThirdPartyProviderConnection` read, `server/queries/third-party-provider-adapter.ts`).
2. Check `app.third_party_provider_ingestion_attempts` for the connection's own recent `result='invalid'`/`reason='signature_verification_failed'` rows to confirm the failure pattern (a burst from one source vs. sustained, both consistent with either a key-rotation mismatch or an active probe).
3. Confirm with the provider (out-of-band) whether they rotated their own signing secret, or whether the failures are unexpected from their side (a possible forged-signature probe against the endpoint, not a real provider malfunction).

## 4. Resolution steps

1. **If the provider rotated their key:** `app.rotate_third_party_provider_webhook_secret(connectionId, actorAuthUserId, actorLabel)` (`ATW-226E`, `server/mutations/third-party-provider-adapter.ts`) mints a new secret immediately, no overlap window (unlike `app.rotate_api_key`) — coordinate the provider's own outbound webhook config update at the same time as calling this function. Then `app.reenable_third_party_provider_connection(connectionId, actorAuthUserId, actorLabel)` (`ATW-226I`) resets `consecutive_failure_count` to 0 and clears `status`/`auto_disabled_at`/`disabled_reason`.
2. **If the failures look like an active probe, not a real provider issue:** rotate the secret anyway (§4.1) before reenabling — a probe that guessed or leaked the old secret must not be able to resume once reenabled.
3. **If an operator wants to proactively take a connection offline** (suspected compromise, planned provider maintenance, decommissioning) before 10 failures accumulate: `app.disable_third_party_provider_connection(connectionId, reason, actorAuthUserId, actorLabel)` — idempotent-safe, authority-gated (`OPS:Edit`), and captures a real `app.audit_logs` event (unlike the automated auto-disable path, which is evidenced only by the row's own timestamped columns, never a synthetic audit actor).
4. **Rollback procedure if resolution fails:** `app.disable_third_party_provider_connection` again (idempotent) to keep the connection safely offline while further investigating; no data rollback is ever needed, since a disabled connection never wrote anything malformed in the first place — the widened ingestion function rejects before any insert on every failure path.

## 5. Communication

Notify the affected tenant's own Operations administrator (they hold `OPS:Edit` and can self-serve §4.1/§4.3 without DevOps involvement) if the connection carries a customer-visible tracking policy (`app.shipment_leg_tracking_policies.customer_visible`, `ATW-225`) for an active shipment — their own Fleet Control Tower (`ATW-226H`) will show the vehicle as `never tracked`/stale for this source while disabled.

## 6. Post-incident

Confirm `consecutive_failure_count` reset to exactly 0 and a fresh, correctly-signed webhook call succeeds (`ingest_status='ok'`). If the cause was a genuine forged-signature probe (not a key-rotation mismatch), consider whether the connection's own `provider_code`/endpoint needs additional network-layer protection (out of this capability's own repository-controlled scope — a WAF/rate-limiting concern at the deployment layer).

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-03 | Rehearsal (db-test, not a live vendor outage) | Exactly 10 consecutive signature failures auto-disable at the 10th, never before; a well-signed request against the disabled connection is rejected (`connection_not_active`), never silently accepted; manual disable/reenable both authority-gated and cross-tenant-isolated | `scripts/db-tests/advanced-tms-gps-telematics-integrated-verification.sql`, Part A |

A live-vendor rehearsal (a real forged-signature burst against a real live provider integration) is required before this runbook can be marked fully rehearsed — tracked as a post-live-provider-activation item (`226_*.md` §8's own external-evidence policy), not claimed complete here.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-03 | 0.1.0 | Initial — instantiated at `ATW-226I` | Claude Code (runtime build agent) |
