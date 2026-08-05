# Driver Mobile Tracking Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff).
**Audience:** dispatchers issuing/revoking driver sessions, support staff explaining what "Driver Mobile" is and is not, and developers building the actual consuming application.
**Source of truth:** `supabase/migrations/20260729360000_create_advanced_tms_driver_mobile_tracking.sql` (`ATW-226C`, base), `20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql` (`ATW-027`, the consent live-recheck and current function bodies), `20260729390000_create_advanced_tms_canonical_telemetry_arbitration.sql` (`ATW-226F`, canonicalization). Read these directly for authoritative function bodies.

## 1. What "Driver Mobile" is today — an honest framing up front

**"Driver Mobile" is a tested, real HTTPS RPC contract. It is not a shipped mobile application, and no app exists anywhere in this repository that a driver could install and open.** This is not a gap unique to this checkpoint — it is this repository's own established, disclosed convention, recorded independently multiple times:

- `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-015` (`OPEN`, Medium): *"No PWA manifest, service worker, barcode/scanner component, or scheduler/worker runtime... exists anywhere in this repository."* This is a real gap against `docs/runtime/CARGOGRID_CONTEXT.md` §3's own ratified operating snapshot, which lists "online-first responsive PWA" as a decided product commitment — decided, not yet built.
- `ATW-226C.md` §5 (residual disclosures): *"No Driver PWA frontend exists yet — the HTTPS contract is real and tested; the consuming mobile web app is deferred."*
- `ATW-226C.md` §3.3 (service layer): *"the consuming mobile web app (service worker, manifest, offline handling, permission UI) is a substantial, separate front-end engineering effort disclosed as deferred, not silently included."*

Everything below describes the **real, tested backend contract**: what a dispatcher does today, what an eventual Driver PWA would need to call, and what a driver's device would actually experience if that PWA existed. Do not represent this capability as a shipped app in any customer-facing or sales material — the honest claim is "the tracking backend a mobile app can be built against," matching the repository's own established evidence discipline (the same discipline that records physical GPS hardware testing as `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` and live third-party providers as `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` — see `ADVANCED_TMS_WMS_HANDOFF_PACKAGE.md` for the full external-evidence policy).

## 2. Why drivers use a bearer token, not a CargoGrid login

Drivers are `app.master_records` rows (the same master-data identity `app.resource_assignments` references), **never `app.users` rows** — confirmed directly by `app.set_driver_mobile_tracking_consent` itself being `OPS:Edit`-gated: consent is recorded *by staff, on the driver's behalf*, because the driver has no portal session to record it themselves. There is no driver login flow anywhere in this repository. Instead:

1. A dispatcher already decided a leg should be tracked by `driver_mobile` (`app.shipment_leg_tracking_sessions`, `ATW-225`, `OPS:Edit`).
2. A dispatcher mints a bearer token for that specific session: `app.start_driver_mobile_session(shipment_leg_tracking_session_id, actor, ...)` — `OPS:Edit`-gated, the same authority tier `start_leg_tracking_session` itself uses.
3. The raw token is returned **exactly once**, in that function's own return value, and is never stored in plaintext anywhere (`app.driver_mobile_tracking_sessions.token_hash` is a one-way sha256 digest, `pgcrypto`'s `digest()`).
4. Transmitting that raw token to the driver's own device (QR code, SMS, or otherwise) is explicitly **out of this repository's scope entirely** — disclosed, not silently assumed solved.
5. The driver's device then presents the bearer token on every subsequent call to `app.ingest_driver_mobile_report` — the one `anon`-callable function in this contract, since a Driver PWA session genuinely has no Supabase Auth identity at all.

## 3. Session lifecycle

| Step | Function | Gate | Notes |
|---|---|---|---|
| Start | `app.start_driver_mobile_session` | `OPS:Edit` | At most one **active** token per `ATW-225` tracking session (partial unique index on `status='active'`) — revoked history is preserved, never overwritten, mirroring `app.shipment_tracking_tokens` (`OPS-180`) exactly |
| Revoke | `app.revoke_driver_mobile_session` | `OPS:Edit` | Lost-phone / reassignment flow — revoke, then a fresh `start_driver_mobile_session` call reissues cleanly (this required a partial, not plain, unique index — a real defect found and fixed during `ATW-226C`'s own authoring, see `ATW-226C.md` §4.1 item 2) |
| Ingest | `app.ingest_driver_mobile_report` | `anon`, bearer-token-gated | `report_type` ∈ `heartbeat`/`location`/`pause`/`resume`/`stop` |
| Stop (driver-initiated) | same function, `report_type='stop'` | token possession only, no `OPS:Edit` of the driver's own | Ends the underlying `ATW-225` session via a widened `app.end_leg_tracking_session(..., p_driver_mobile_session_id)` call — a driver "controls only their own assigned mobile session" (`226_*.md` §26), never any other shipment's session |
| Real-time consistency | — | — | If a dispatcher already ended/superseded the `ATW-225` session on their own side, the very next ingestion call is rejected immediately (`invalid`) — a stale token is never silently accepted after the dispatcher has moved on |

Every auth-failure branch (bad token, expired session, wrong report shape, revoked consent — see §4) returns a uniform `status` column (`invalid`/`rate_limited`) rather than raising an exception. This is deliberate: a raised exception's own distinct error class/timing would be a real enumeration oracle for an unauthenticated caller, the same reasoning `app.lookup_public_shipment_tracking` (`OPS-180`) already established and this contract follows exactly. A caller accumulating 10 `invalid` results within a trailing 15-minute window (keyed by a caller-supplied `client_key`, a sha256 hash of the caller's own best-effort IP) is rate-limited.

## 4. Consent — the real prerequisite, now checked live on every call

`app.driver_operational_profiles.mobile_tracking_consent` (boolean) plus `mobile_tracking_consent_at` (timestamptz, set on grant, cleared on revoke) is the one consent record this capability has. It is set by staff via `app.set_driver_mobile_tracking_consent` (`ATW-223`, `OPS:Edit`) — again, recorded on the driver's behalf, not captured through a driver-facing consent screen (none exists).

**Two distinct points where consent is checked, both real:**

1. **At session start** (`ATW-225`): `app.check_leg_tracking_source_eligible` requires `mobile_tracking_consent = true` before a `driver_mobile` tracking session may even be created.
2. **On every single ingestion call, live, since `ATW-027`**: before `ATW-027`, consent was checked only once, at session start — revoking consent mid-session via `app.set_driver_mobile_tracking_consent` did **not** stop a subsequent `app.ingest_driver_mobile_report` call from succeeding and persisting the driver's location. This was a real, live-reproduced HIGH-severity finding (`ATW-027` §3.6). The fix, now the current body of `app.ingest_driver_mobile_report` (`20260730360000`), re-checks the session's own driver's **current** `status='active'`/`mobile_tracking_consent=true` on every call:

```sql
if not exists (
  select 1 from app.driver_operational_profiles
  where driver_master_id = v_session.resource_master_id and status = 'active' and mobile_tracking_consent
) then
  -- clean 'invalid' result, never a raise
```

Revoking consent now takes effect on the very next ingestion call, not merely on the next session start. See `privacy-consent-and-retention-guide.md` for the full privacy treatment of this mechanism.

## 5. What a dispatcher actually sees

- The **Fleet** admin screen (`ATW-223`) and the **Fleet Control Tower** (`ATW-226H`) show whichever vehicle the leg's driver is currently resolved onto (`app.resolve_vehicle_for_driver_mobile_session` — the session's own leg's shipment order's own currently-assigned vehicle via `app.resource_assignments`), not the driver as an independent map marker. There is no separate "driver location" map layer distinct from the vehicle position projection.
- The dispatch board (`ATW-222`) shows the same `tracking_status`/`freshness_status`/`authoritative_source_type` columns regardless of which source class is winning — a dispatcher does not need to know the report came from `driver_mobile` specifically to read the shipment's tracking health, though `authoritative_source_type` does disclose it when relevant.
- Per-vehicle telemetry history, source health, and source-switch history (`ATW-226F`/`226H`) are visible from the Fleet Control Tower's own vehicle detail page, regardless of which source produced them.

## 6. What a driver would see (if the consuming app existed)

Since no PWA/native app exists, this is a description of the **contract surface**, not a UI walkthrough:

- `POST /api/tracking/driver-mobile` (`app/api/tracking/driver-mobile/route.ts`) — the one real HTTP route, accepting `Authorization: Bearer <token>` or a `rawToken` body field, using the `service_role` client (the service-role credential itself never reaches the browser — the RPC's own token-hash gate is what authorizes the call).
- A `heartbeat` report (no location) still proves the source is alive and updates `vehicle_source_health`, but never wins arbitration on its own.
- A `location` report requires real coordinates; `pause`/`resume` bracket a temporary stop without ending the session; `stop` ends it.
- Every report is timestamped with both a client-claimed `event_at` and a server-assigned `received_at`, kept as two genuinely separate columns (`226_*.md` §24's own business rule) — a slow or offline-buffered device's reports are not silently reinterpreted as "now."

## 7. Real limitations, disclosed

- **No Driver PWA/native app exists.** See §1.
- **Token delivery to the driver's device is out of scope.** No QR-code generation, SMS-send integration, or deep-link mechanism exists anywhere in this repository.
- **No barcode/scanner component exists** (`ISS-2026-015`) — irrelevant to GPS tracking itself, but named in the same disclosed gap since both are PWA-shell-dependent capabilities that share the same missing front-end foundation.
- **No scheduler/worker runtime** (`pg_cron` or equivalent) exists to auto-expire a session server-side — `app.driver_mobile_tracking_sessions.expires_at` is checked reactively on every ingestion call (an expired token is simply rejected `invalid`), not proactively swept.
- **Raw device-provided permission flags are stored, not verified.** `location_permission_granted`/`background_permission_granted` on `app.driver_mobile_position_reports` are exactly what the (hypothetical) client reports about its own OS-level permission state — the server has no independent way to confirm them.
- **The residual, disclosed direct-device IMEI-spoofing risk (`ATW-027` §3.4) does not apply to this source class** — Driver Mobile authenticates via a bearer token, not a device-presented IMEI, so that specific residual belongs to `direct_device` only (see `source-arbitration-and-fallback-explanation.md`).

## 8. Evidence

`scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` proves: authority-gating and not-found/wrong-source-type rejections for `start_driver_mobile_session`; a token minted exactly once, a second mint on the same session rejected; invalid-token/malformed-report_type both return a uniform `invalid` outcome, never an exception; `event_at` strictly before `received_at`; a `stop` report both records the raw report and ends the underlying `ATW-225` session, after which the same token is immediately rejected; rate limiting (10 bad attempts → `rate_limited`); the `end_leg_tracking_session` backward-compatibility proof (the pre-existing 5-argument call shape still resolves unambiguously after the widening); RLS; schema-privilege defense in depth (`anon` holds `EXECUTE` on exactly `ingest_driver_mobile_report`, zero on the other four functions in this contract). `ATW-027`'s own hardening additionally re-proves the live mid-session consent revocation and the out-of-range-coordinate exception-safety fix, extending this same `scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` file (no new db-test file was added for this hardening pass — `ATW-027.md` §6: 137 migrations, 133 test files, existing files extended) — see `ATW-027.md` §6 for the exact current gate counts.
