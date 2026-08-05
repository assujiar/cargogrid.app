# Third-Party GPS Provider Onboarding and Credential Rotation Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), the TECHNICAL/HARDWARE/PROTOCOL/OPERATIONS half of this checkpoint.
**Audience:** integration admins onboarding a third-party GPS/fleet platform connection, developers building a real vendor-specific adapter on top of this contract, and DevOps rotating a compromised or vendor-rotated secret.
**Source of truth:** `supabase/migrations/20260729380000_create_advanced_tms_third_party_provider_adapter.sql` (`ATW-226E`), `supabase/migrations/20260730110000_harden_advanced_tms_third_party_provider_connection_recovery.sql` (`ATW-226I`, auto-disable), `supabase/migrations/20260730350000_harden_advanced_tms_third_party_hybrid_tracking.sql` (`CG-S10-ATW-027`, the CRITICAL secret-column fix and 3 other findings), `app/api/webhooks/third-party-gps/[connectionId]/route.ts`, `docs/adr/ADR-0011-webhook-signature-and-auto-disable-thresholds.md`. Read those migrations directly for the authoritative function bodies; this guide explains and cites them, it does not redefine them.
**Companion documents:** `docs/runbooks/third-party-provider-outage.md` (what to do once a connection auto-disables or misbehaves — this guide focuses on onboarding and planned rotation, the runbook focuses on incident response), `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` (the formal record of what a real, live provider connection would still need to prove).

## 1. What this is, and what it explicitly is not

`ATW-226E`'s own migration header states this precisely, and it remains true today: this is a **repository-owned reference webhook contract**, not a certified integration with any named real vendor. `app.third_party_provider_connections`/`app.third_party_telemetry_reports`/`app.ingest_third_party_provider_webhook_event` define and validate one JSON payload shape (`event_id`/`vehicle_id`/`event_type`/`timestamp`/`latitude`/`longitude`/`speed_kmh`/`heading_degrees`) that this repository controls end to end. **No live third-party GPS platform credential, contract, or connection exists anywhere in this repository** — every provider-facing claim in this guide is proven against this one reference contract and deterministic test fixtures, never a live vendor. See `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` for the formal `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` record and exactly what a real vendor integration would still need to prove beyond what is documented here.

If a real vendor's actual proprietary webhook payload shape differs from the reference contract above (the overwhelmingly likely case — this contract was never designed against a specific vendor's real API documentation), integrating that vendor requires a translation layer in front of `app.ingest_third_party_provider_webhook_event`, not a change to this function's own contract. Do not represent a real vendor as "integrated" on the strength of this guide alone.

## 2. Onboarding a connection

`app.register_third_party_provider_connection(p_tenant_id, p_provider_code, p_integration_mode, p_actor_auth_user_id, p_actor_label)` — requires `OPS:Create`.

- `p_provider_code` — a free-text identifier for the vendor (e.g. a short vendor name/code). No enum or registry constrains this value; it is case-specific by design (`219_ADVANCED_TMS_WMS_README.md` §4.4: "Third-party adapters must be case-specific... a universal lowest-common-denominator provider abstraction is forbidden").
- `p_integration_mode` — `webhook` or `poll` (`app.third_party_provider_connections`'s own `CHECK` constraint). **Only `webhook` mode has a real, callable ingestion path today.** `poll` mode is structurally represented (`poll_cursor` storage, `app.update_third_party_provider_poll_cursor`) but no live HTTP poll call exists anywhere in this repository — there is no live provider credential to poll against, and building a real poll worker is left to `app.jobs` (`PLT-131`/`132`) as its own future, not-yet-built consumer (§7 below, and `docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md`).
- Idempotent on `(tenant_id, provider_code)` — re-registering the same pair returns the existing row, with `raw_webhook_secret` returned as `null` (never re-disclosed, never re-minted on a re-call).
- For `webhook` mode, a raw signing secret is minted (`'tpws_' || 32 random bytes, hex-encoded`) and returned **exactly once**, in this call's own return row. There is no way to retrieve it again later — only `app.rotate_third_party_provider_webhook_secret` (§4) can produce a new one.

## 3. The webhook secret's access model — the corrected, now-fixed shape

**Read this section before assuming any pre-`CG-S10-ATW-027` documentation, code comment, or your own prior understanding of this table's grants is still accurate.** A real, live, CRITICAL vulnerability existed here and was fixed at `CG-S10-ATW-027` (Prompt 246) — describing the corrected model precisely matters.

### 3.1 What was wrong (fixed, not a current risk)

`ATW-226E`'s original migration (`20260729380000`) granted `select on app.third_party_provider_connections to authenticated` — a **table-wide** grant. Row Level Security scopes which *rows* an `authenticated` caller can see (by tenant), but it does nothing to restrict which *columns* of a visible row are readable. The result: any authenticated member of a tenant — regardless of their own RBAC role or permissions — could directly `SELECT webhook_secret_value` for that tenant's own connections. `CG-S10-ATW-027`'s own adversarial review live-reproduced the full exploit chain: a zero-permission tenant member read the raw secret, computed a valid HMAC-SHA256 signature from it, and successfully forged accepted telemetry that became a vehicle's live current position.

### 3.2 The corrected model (current, real, verified)

Migration `20260730350000` (`CG-S10-ATW-027` finding 1) applies the identical pattern this repository's own `app.users`/`email` column-level protection already established (`PLT-113/114`) — a column-level `REVOKE` alone cannot carve an exception out of an existing table-level `GRANT` (Postgres ACLs are additive), so the fix is:

```sql
revoke select on app.third_party_provider_connections from authenticated;
grant select (
  id, tenant_id, provider_code, integration_mode, poll_cursor, status,
  consecutive_failure_count, last_successful_ingest_at, record_version, created_by,
  created_at, updated_at, auto_disabled_at, disabled_reason
) on app.third_party_provider_connections to authenticated;
```

`authenticated` now has zero ability to read `webhook_secret_value` under any circumstance, at any permission level, for any tenant, full stop — there is no RBAC role or scope that grants read access to this column; it is not exposed via RLS-plus-role-check, it is not exposed at all. Independently re-verified by the `CG-S10-ATW-027` orchestrating session (not accepted on the fix agent's own self-report alone): `information_schema.column_privileges` confirms zero grant on the secret column for `authenticated`/`anon` while all 14 other columns remain granted; a direct raw-SQL probe as `authenticated` against a live fixture row raised `permission denied` on the secret column while an ordinary column proceeded to normal RLS filtering.

**The only two ways to ever see the raw secret are `app.register_third_party_provider_connection` (§2) and `app.rotate_third_party_provider_webhook_secret` (§4) — each `SECURITY DEFINER` computed return values, never a raw table read, and each already `OPS:Create`/`OPS:Edit`-gated independently of this column grant.** Never write application code, a support script, or a customer-facing doc that reads `webhook_secret_value` via a raw `select("*")`/`select("webhook_secret_value")` against `app.third_party_provider_connections` — it will fail with a permission error for an `authenticated`-role client, by design, and should.

`docs/runtime/KNOWN_ISSUES.md`'s own `ISS-2026-026` records a related, low-severity, currently-dead-code gap worth being aware of: `server/queries/third-party-provider-adapter.ts`'s `getThirdPartyProviderConnection` still calls `select("*")` against this now-column-restricted table. It has zero live callers today (confirmed by direct inspection — only its own mocked unit test exercises it), so this is not a live regression, but it would need an explicit column list the moment a real caller is wired up, or it will simply fail once that caller runs with anything less than `service_role` privilege.

## 4. Rotating the webhook secret

`app.rotate_third_party_provider_webhook_secret(p_connection_id, p_actor_auth_user_id, p_actor_label)` — requires `OPS:Edit`, only valid for a `webhook`-mode connection (raises `not_a_webhook_connection` otherwise).

- **Immediate, no overlap window** — unlike `app.rotate_api_key` (`PLT-129`), there is no grace period during which both the old and new secret are valid. The moment this call returns, the old secret stops working. This is a deliberate design choice (`app.rotate_third_party_provider_webhook_secret`'s own comment): a webhook secret has exactly one live consumer — the provider's own outbound webhook configuration — which the operator is expected to update out-of-band **at the same time** as calling this function.
- **Operational sequencing that matters:** because there is no overlap window, calling this without first coordinating with the provider will cause every webhook delivery attempt between the rotation and the provider's own config update to fail signature verification, counting toward the 10-consecutive-failure auto-disable threshold (§5). For a real vendor integration, coordinate the timing with the provider's own support/API team before calling this.
- Returns the new raw secret exactly once, in this call's own return row — the same "shown once" contract as registration.

## 5. HMAC-SHA256 signing (ADR-0011, reused verbatim for the inbound direction)

`app.compute_third_party_provider_webhook_signature`/`app.verify_third_party_provider_webhook_signature` implement the identical scheme `ADR-0011` already established for this repository's own *outbound* webhook deliveries (`PLT-129`), reused for the *inbound* direction a third-party provider calls:

- **Signed payload**: `"<unix_timestamp>.<raw_payload_bytes>"`, HMAC-SHA256 keyed with the connection's own `webhook_secret_value`, hex-encoded.
- **Timestamp tolerance**: 300 seconds (5 minutes) — `abs(extract(epoch from now()) - p_timestamp) > 300` fails verification outright, before even attempting to recompute the signature.
- **Fails closed, never raises**: `verify_third_party_provider_webhook_signature` returns `false` for every reason (stale timestamp, unknown/non-webhook `connection_id`, mismatched signature) — never a distinguishable exception, so an unauthenticated caller cannot use error class/timing to enumerate which failure mode they hit.

### 5.1 The real HTTP endpoint

`POST /api/webhooks/third-party-gps/{connectionId}` (`app/api/webhooks/third-party-gps/[connectionId]/route.ts`) — `connectionId` is the routable identity (not `provider_code`), since each tenant's own connection gets its own URL, unlike the raw-TCP gateway's global-IMEI-lookup problem.

Required headers:

| Header | Meaning |
|---|---|
| `x-webhook-timestamp` | Unix timestamp (seconds) the payload was signed at |
| `x-webhook-signature` | The hex-encoded HMAC-SHA256 signature, computed per §5 above |

The route reads the request body via `request.text()` — **never** `request.json()` — because signature verification is computed over the exact bytes the provider sent; re-serializing through `JSON.parse`/`JSON.stringify` first (even of semantically-identical JSON) can reorder keys or change whitespace and silently break a legitimate signature. A real provider integration's own HTTP client must send the identical raw bytes that were signed — do not let any intermediate proxy or client library re-serialize the body before it reaches CargoGrid.

Response status codes (`STATUS_BY_INGEST_STATUS` in the route):

| `ingestStatus` | HTTP status | Meaning |
|---|---|---|
| `ok` | 200 | Accepted, canonicalized (or rejected by arbitration for a legitimate reason — see `docs/build-log/phase-05/guides/source-arbitration-and-fallback-explanation.md` for how a `200`/`ok` report can still lose arbitration to a higher-priority or fresher source) |
| `duplicate` | 200 | The same `provider_event_id` was already ingested for this connection — a genuine provider retry, not an error |
| `quarantined` | 200 | `vehicle_id` did not match any active `app.provider_vehicle_mappings` row — the payload is preserved (`raw_payload`) but not canonicalized |
| `invalid` | 401 | Bad signature, stale timestamp, malformed payload, or an inactive/unknown `connectionId` |
| `rate_limited` | 429 | See §6 |

## 6. Rate limiting (hardened at `CG-S10-ATW-027`, finding 4)

10 `invalid`-result attempts within a rolling 15-minute window trips `rate_limited`. **Before `CG-S10-ATW-027`, this counted only the caller-supplied `client_key`** (a SHA-256 hash of the first `x-forwarded-for` hop — itself fully attacker-controlled), so an attacker could bypass the limiter entirely by varying that header per request; live-reproduced at 30 distinct `client_key` values against the same connection, 0/30 ever tripped `rate_limited`. The count now matches **`connection_id` in addition to `client_key`** — `connection_id` is the caller's own chosen attack target and cannot be rotated without abandoning the attack, so it is now the primary, unavoidable bound; `client_key` remains a secondary signal, and is the only signal available for a wholly nonexistent `connection_id` (which is recorded with a `null` FK by design, so it cannot be matched by the `connection_id` predicate).

## 7. Auto-disable at 10 consecutive signature failures, and recovery

`app.third_party_provider_connections.consecutive_failure_count` existed since `ATW-226E`'s own original migration but had nothing incrementing or acting on it until `ATW-226I` closed that gap, reusing `ADR-0011`'s own exact threshold: **10 consecutive `signature_verification_failed` outcomes auto-disables the connection** (`status → 'disabled'`, `auto_disabled_at`/`disabled_reason = 'consecutive_failure_threshold_exceeded'` set). This is deliberately scoped to signature failures only — `malformed_json`/`schema_validation_failed`/`quarantined` are data-quality outcomes about the *payload*, not a security/outage signal about the *connection's own health*, the identical distinction `ADR-0011` itself draws for outbound webhooks. Once disabled, every further call for that connection is rejected at the connection-status check (`connection_not_active`) before signature verification even runs — no further raw payload is accepted, but nothing already ingested is affected.

Two authenticated recovery RPCs, mirroring `app.disable_webhook_endpoint`/`app.reenable_webhook_endpoint` exactly:

- `app.disable_third_party_provider_connection(p_connection_id, p_reason, p_actor_auth_user_id, p_actor_label)` — `OPS:Edit`, idempotent-safe, captures a real `app.audit_logs` event (a human-driven action). Use this to **proactively** take a connection offline (suspected compromise, planned provider maintenance, decommissioning) before 10 failures accumulate.
- `app.reenable_third_party_provider_connection(p_connection_id, p_actor_auth_user_id, p_actor_label)` — `OPS:Edit`, resets `consecutive_failure_count` to 0 and clears `status`/`auto_disabled_at`/`disabled_reason`.

The automated auto-disable transition itself captures no `app.audit_logs` event (mirrors `app.record_webhook_delivery_attempt`'s own identical precedent — an unattended, no-human-actor state transition is evidenced by the row's own timestamped columns, not a synthetic audit actor); the two manual RPCs above do, since a human drove them.

**Full incident-response procedure (diagnosis steps, the "was this a key rotation or an active probe" decision, communication plan) lives in `docs/runbooks/third-party-provider-outage.md` — this guide covers the mechanism, that runbook covers the response.**

## 8. Related documentation

- `docs/runbooks/third-party-provider-outage.md` — incident response for an auto-disabled or misbehaving connection.
- `docs/adr/ADR-0011-webhook-signature-and-auto-disable-thresholds.md` — the source ADR this entire signing/tolerance/threshold scheme reuses verbatim.
- `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` — the formal record of what a real, live provider connection would still need to prove.
- `docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md` — `poll_cursor`'s own structurally-represented-but-not-executed status, and the generic `app.jobs` queue a real poll worker would sit on.
