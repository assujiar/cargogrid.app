# ATW-226C — Driver Mobile GPS Session and HTTPS Ingestion

## 0. Checkpoint

| Field | Value |
|---|---|
| Prompt | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226C`'s own scope line), parent `CG-S10-ATW-007` (`CG-AABPP-ATW-226`) |
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-225-udh-x4hsij` |
| Dependency | `CG-S10-ATW-004` (Prompt 223, `VERIFIED`); `CG-S10-ATW-006` (Prompt 225, `VERIFIED`) |
| Authorization | Explicit range authorization "lanjut sd prompt terakhir di 226 (226a-226i)" — third task within that range, following `226A`/`226B`. |

## 1. Pre-flight collision check

`pnpm run git:check` clean, continuing directly on top of `ATW-226B`'s own commit. No open PR.

## 2. Baseline reconciliation

Re-read `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §14A/§16/§21-23/§26 and `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1.4's own planned `226C` row. This is the **first genuinely real telemetry-producing surface** this repository builds. Fresh baseline gate suite green before any file was written: `typecheck`/`lint` 0 errors, `node:test` 2286/2286, `db:test` PASS across 102 migrations/104 db-test files.

## 3. Implementation

### 3.1 Scope boundaries and design decisions (disclosed, migration header)

1. **Integrates with `ATW-225`'s own orchestration layer, never duplicates it.** `app.shipment_leg_tracking_sessions` (`ATW-225`) already decides *whether* a leg should be tracked by `driver_mobile` and creates the intent-level session row. This checkpoint adds exactly one thing on top: the bearer-token layer a Driver PWA needs, since **drivers hold no CargoGrid portal login at all** — confirmed directly by `ATW-223`'s own `app.set_driver_mobile_tracking_consent` being `OPS:Edit`-gated (staff record consent on the driver's behalf, the driver never logs in).
2. **Raw telemetry storage only — never normalization/arbitration/current-position projection.** `app.driver_mobile_position_reports` is an append-only log of exactly what the device reported, `event_at`/`received_at` kept separate per `226_*.md` §24's own business rule. `ATW-226F`'s own canonical-telemetry/arbitration layer (not built yet) is the real consumer.
3. **The one deliberate `anon` grant in this migration, precedented, not novel.** A direct query of `information_schema.routine_privileges` found `anon` already holds `EXECUTE` on **five** pre-existing functions (white-label/custom-domain/locale pre-login resolution) — none token-gated. The directly-relevant prior art for a safely anon-callable, *token-gated* function is `app.lookup_public_shipment_tracking` (`OPS-180`); this checkpoint follows its exact proven shape: caller-supplied `client_key` rate-limited (10 bad attempts / 15 minutes), sha256 token-hash lookup, and a returned status column rather than a raised exception for every auth-failure branch (a raised exception's own distinct error class/timing would be a real enumeration oracle for an unauthenticated caller).
4. **`app.end_leg_tracking_session` (`ATW-225`) is widened, not forked**, so a driver tapping "Stop" can end their own session immediately (`226_*.md` §26: "drivers control only their assigned mobile session") without an `OPS:Edit`/`OPS:Override` grant of their own — matching the WBS's own `226C` `forbidden_paths` ("direct mutation of `app.shipment_leg_tracking_sessions` outside its own already-verified `ATW-225` RPCs"). A new trailing `p_driver_mobile_session_id default null` parameter changes the function's own signature, so `CREATE OR REPLACE` (same-signature only) could not be used — `DROP FUNCTION` then `CREATE FUNCTION` is the correct technique for a signature-widening change (the old migration file itself is never edited); every existing 5-positional-argument call site is unaffected, proven directly in this checkpoint's own db-test (§4.1).
5. PostGIS point storage/validation reuses `app.geojson_point_to_geography`/`app.validate_geography_point` (`PLT-134`) verbatim; the read-side GeoJSON projection (`app.get_driver_mobile_position_reports`) mirrors `app.get_shipment_leg_stops` (`ATW-221`) exactly.
6. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

### 3.2 Schema — `supabase/migrations/20260729360000_create_advanced_tms_driver_mobile_tracking.sql`

Three new tables: `app.driver_mobile_tracking_sessions` (bearer-token layer, at most one active row per `ATW-225` tracking session via partial unique index — revoked history preserved, mirroring `app.shipment_tracking_tokens`, `OPS-180`, exactly), `app.driver_mobile_ingestion_attempts` (rate-limiting, mirrors `app.tracking_lookup_attempts`), `app.driver_mobile_position_reports` (raw append-only telemetry). Five new functions: `app.start_driver_mobile_session`, `app.revoke_driver_mobile_session`, `app.ingest_driver_mobile_report` (the one anon-callable function), `app.get_driver_mobile_position_reports` (read projection). One dropped-and-recreated function: `app.end_leg_tracking_session` (`ATW-225`, widened with a new trailing default-null parameter).

### 3.3 Service layer

`server/contracts/driver-mobile-tracking/driver-mobile-tracking.ts`, `server/queries/driver-mobile-tracking.ts` (`getDriverMobileTrackingSession`, `listDriverMobilePositionReports`), `server/mutations/driver-mobile-tracking.ts` (`startDriverMobileSession`, `revokeDriverMobileSession`, `ingestDriverMobileReport` — the last of which never throws for a bad token/rate limit, only for a genuine transport error, unlike every other mutation wrapper in this repository).

**`app/api/tracking/driver-mobile/route.ts` — the first real HTTP API route this repository builds.** A `POST` handler accepting a bearer token (`Authorization: Bearer <token>` or a `rawToken` body field) plus report payload, using the service-role client exactly as `app/(public)/tracking/[token]/page.tsx` (`OPS-180`) already does for the same reason (no session exists to be RLS-scoped against) — the service-role credential itself never reaches the browser; the RPC's own token-hash gate is what actually authorizes the call. `client_key` is a sha256 hash of the caller's own best-effort IP, the identical convention the public tracking page already established.

**No Driver PWA frontend was built this checkpoint** — `226_*.md` §14A's own "authenticated HTTPS endpoint" requirement is the load-bearing contract this checkpoint delivers; the consuming mobile web app (service worker, manifest, offline handling, permission UI) is a substantial, separate front-end engineering effort disclosed as deferred, not silently included. The kickoff-time planned `226C` `allowed_paths` note did list a PWA UI path, but a direct re-scoping judgment this checkpoint made explicitly: the backend contract is what every later child (`226F` onward) actually depends on, and is what this checkpoint's own real, tested evidence covers.

## 4. Tests

`scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` (new) — full commercial-to-shipment pipeline fixture (one confirmed land-freight Shipment Order, one leg, a `driver_mobile`-allowed tracking policy, an already-started `ATW-225` driver_mobile session), then: authority-gating and not-found/wrong-source-type rejections for `start_driver_mobile_session`; a real dmt_-prefixed token minted exactly once, a second mint on the same session rejected; invalid-token/malformed-report_type both return a uniform `invalid` outcome, never an exception; a real token accepts heartbeat/location/pause/resume, `event_at` proven strictly before `received_at`, a location report with no coordinates rejected, `app.get_driver_mobile_position_reports`'s own GeoJSON projection proven to match the exact stored point; a `stop` report both records the raw report **and** ends the underlying `ATW-225` session via the widened path, after which the same token is immediately rejected (real-time consistency); rate limiting (10 bad attempts → `rate_limited`); **backward compatibility** — the pre-existing 5-positional-argument `end_leg_tracking_session` call shape proven to still resolve to exactly one function, never "function is not unique"; RLS; schema-privilege defense in depth (`anon` holds `EXECUTE` on exactly `ingest_driver_mobile_report`, zero on the other four); exact-count audit trail.

`server/contracts/driver-mobile-tracking/driver-mobile-tracking.test.ts` (9 cases), `server/queries/driver-mobile-tracking.test.ts` (5 cases), `server/mutations/driver-mobile-tracking.test.ts` (7 cases) — **21 net new** `node:test` cases. `node:test` **2307/2307**. `db:test` PASS across 102 migrations/**105** db-test files (1 new). `npx next build` PASS (**82 routes, 1 new**: `/api/tracking/driver-mobile`).

### 4.1 Real defects found and fixed during authoring (before any full-suite gate run)

1. **`CREATE OR REPLACE FUNCTION app.end_leg_tracking_session` with an added trailing parameter would NOT have replaced the original 5-argument function** — Postgres function identity is `(schema, name, parameter types)`; adding a parameter creates a *distinct overload* rather than replacing the original, making every existing unqualified 5-argument call site ambiguous (`function ... is not unique`). Caught by re-deriving Postgres's own overload-resolution semantics before running any gate, not discovered via a failing test. Fixed by `DROP FUNCTION` (exact old signature) then `CREATE FUNCTION` (new signature) instead of `CREATE OR REPLACE`, and added a dedicated backward-compatibility db-test proving the fix.
2. **`app.driver_mobile_tracking_sessions_session_unique unique (shipment_leg_tracking_session_id)` (a plain, non-partial constraint) made "revoke, then reissue" — a real, necessary lost-phone flow — structurally impossible**, since a revoked row still occupies the unique slot. Caught directly against a real Postgres instance (`driver_mobile_session_already_issued` on a call meant to succeed) while authoring the db-test's own revoke-then-reissue lifecycle assertion. Fixed by replacing the plain unique constraint with a partial unique index scoped to `status = 'active'`, the exact shape `app.shipment_tracking_tokens` (`OPS-180`) already uses — and correcting `start_driver_mobile_session`'s own "already issued" check and `revoke_driver_mobile_session`'s own lookup to filter on `status = 'active'` accordingly.
3. **The migration's own header initially claimed to be "the first migration to grant `anon` EXECUTE on anything"** — false, caught by directly querying `information_schema.routine_privileges` rather than trusting an un-verified grep pattern. Corrected to accurately cite all five pre-existing `anon`-granted functions and narrow the claim to what is actually true (the specific token-gated pattern precedent).

## 5. Residual disclosures

- No Driver PWA frontend exists yet — the HTTPS contract is real and tested; the consuming mobile web app is deferred (§3.3).
- Transmitting the raw bearer token from a dispatcher to a driver's own device (QR code, SMS, or otherwise) is out of this repository's scope entirely — `app.start_driver_mobile_session` discloses the raw value exactly once in its own return value and never again.
- `app.driver_mobile_position_reports` is raw storage only — no canonical current-position projection exists yet (`ATW-226F`, not built). Nothing in this checkpoint writes to `app.shipment_tracking_health`.
- `ATW-226D`/`226E` are now genuinely dependency-unblocked (both need `226A`+`226B`, both `VERIFIED`); `ATW-226F` additionally needs `226C` (this checkpoint) — one of its three prerequisites is now satisfied, `226D`/`226E` remain outstanding.
- No REST/GraphQL *resource* API exists for any domain yet (repository-wide) — the one route this checkpoint adds is a webhook-shaped ingestion endpoint, not a REST/GraphQL resource surface, a distinct category.

## 6. Completion

This checkpoint corrects `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1.4 row `ATW-226C` (`READY` → `VERIFIED`). All three of `226A`/`226B`/`226C` are now `VERIFIED`. `ATW-226D`/`226E` are next in this session's own explicit range authorization, per the family's own dependency order (both need `226A`+`226B`, satisfied; `226F` additionally needs `226C`, also now satisfied, but `226F` itself still needs `226D`+`226E` first).
