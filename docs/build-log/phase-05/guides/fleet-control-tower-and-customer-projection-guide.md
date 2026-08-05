# Fleet Control Tower and Customer Projection Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff).
**Audience:** dispatchers/fleet ops using the Fleet Control Tower, support staff explaining what a customer can and cannot see on a public tracking link, and developers extending either surface.
**Source of truth:** `supabase/migrations/20260730100000_create_advanced_tms_fleet_control_tower.sql` (`ATW-226H`), `20260730130000_create_advanced_tms_milestone_exception_telemetry.sql` (`ATW-228`, the live-ETA widening), `20260728130000_create_operations_public_tracking.sql` (`OPS-180`, the original public projection).

## 1. The Fleet Control Tower (internal, tenant-authenticated)

`app/(tenant)/[tenantSlug]/operations/fleet-control-tower/` — a real, working Leaflet map (vanilla `leaflet@^1.9.4`, not `react-leaflet`, to avoid a React-19.2.7 wrapper-compatibility risk; imported dynamically inside a `useEffect`, never at module scope, since Leaflet's own browser-feature detection would otherwise break the server render). This closed a gap two earlier Phase 5 pages (`operations/fleet/page.tsx`, `operations/dispatch-board/page.tsx`) had each already disclosed as deferred ("no map library exists in this repository yet") — `ATW-226H` is the checkpoint whose job was to actually close it, not defer it a third time.

### 1.1 What a dispatcher/fleet-ops user sees

| Screen | Route | Backed by |
|---|---|---|
| Tenant-wide vehicle list + live map | `operations/fleet-control-tower/` | `app.get_tenant_vehicle_tracking_overview` — one aggregating read for every active vehicle's current position in the tenant, never one call per vehicle |
| Pending review queues | same page, `signals-panel.tsx` | `app.get_tenant_pending_milestone_candidates`/`app.get_tenant_pending_exception_signals` (`ATW-226G`'s staged output) — a dispatcher's confirm/dismiss action here is what actually creates a real `app.milestone_events`/`app.operational_exceptions` row; the telemetry itself never writes to either directly |
| One vehicle's own detail | `operations/fleet-control-tower/[vehicleMasterId]/` | current position, per-source health, source-switch history, and bounded recent telemetry — reusing `ATW-226F`'s already-existing read functions unchanged |
| Tracking package/entitlement (read-only) + source policy (editable) | `admin/tracking/` | `app.resolve_tenant_tracking_package` (display only — see `subscription-package-and-entitlement-guide.md` §6 for why assignment itself has no UI yet), `app.upsert_tenant_tracking_source_policy` (fully editable, `OPS:Edit`) |
| Provider-mapping / per-vehicle source-priority admin | `operations/fleet/` (extended, not a new page) | wires `ATW-223`'s already-shipped `registerProviderVehicleMapping`/`setVehicleTrackingSourcePriority` mutations, which had existed with zero UI since `226B` |

**Deliberate exception to the "no one-request-per-item" rule:** the provider-mapping/source-priority admin section fetches per-vehicle via `Promise.all` (N calls) rather than one new aggregating SQL function — a disclosed, bounded exception for an infrequently-loaded admin page, never applied to the live map or any hot ingestion path.

### 1.2 What the map does and does not show

The map renders one marker per currently-tracked vehicle and fits its own bounds to them. It does **not** render route history, geofence radii, or the route-deviation corridor as a visual overlay — that data is real and reachable (bounded telemetry history, `ATW-226F`; geofence/deviation state, `ATW-226G`) but is presented as tabular history on the vehicle detail sub-page, not as a further map layer. A richer map (polylines, geofence circles) was considered and explicitly deferred as scope beyond this checkpoint's own ask, not an oversight.

### 1.3 Source health states a dispatcher sees

`app.get_vehicle_source_health` computes a per-source status on every read, against the tenant's own live `freshness_threshold_seconds` — never a stored, potentially-stale status column:

| Status | Meaning |
|---|---|
| `healthy` | last received within the tenant's own freshness threshold (default 300s) |
| `stale` | last received within 1×–3× that threshold |
| `offline` | last received longer ago than 3× that threshold, or never |
| `unknown` | no report ever received for this (vehicle, source) pair |

`app.shipment_tracking_health.freshness_status` (the shipment-level projection, `ATW-024`) deliberately collapses `stale`/`offline`/`unknown` all into `stale` — the shipment-level view does not distinguish "quite stale" from "very stale" the way the vehicle-level check does, since both already mean "the dispatcher should not trust this position blindly" (`20260730320000`'s own design note 2).

## 2. The customer-safe public projection

`app.lookup_public_shipment_tracking` is the one function a customer (or anyone holding a valid tracking link) ever calls — `app/(public)/tracking/[token]/page.tsx`, deliberately outside every tenant-authentication guard, `anon`-callable, rate-limited the same way `driver_mobile`/`third_party_platform` ingestion is (10 bad attempts / 15 minutes). It originated at Operations (`OPS-180`) and has been widened three times since, **each an additive, signature-changing widening (`DROP FUNCTION` + `CREATE FUNCTION`) that never removed or renamed an existing output column** — every pre-existing db-test assertion (all field-name-based, never positional) still passes unmodified after each widening:

| Widened at | Added |
|---|---|
| `ATW-226C` | rate limiting (no new output columns) |
| `ATW-226H` | `vehicle_position_geojson`, `vehicle_position_updated_at`, `vehicle_position_status` |
| `ATW-228` | `live_eta_status`, `live_eta_at` |

### 2.1 What "sanitized" means, concretely

A customer never receives a raw source type, a raw device identifier, a raw provider payload, or the driver's own identity. Instead:

- **Position status** is one of exactly three coarse words: `live` / `delayed` / `unavailable` — never `driver_mobile`/`direct_device`/`third_party_platform`. This reuses the identical 1×/3× freshness-multiplier banding `app.get_vehicle_source_health` already established internally, just relabeled for a customer-facing audience, computed against the tenant's own `freshness_threshold_seconds`.
- **ETA status** is likewise one of exactly three coarse words: `on_time` / `delayed` / `unavailable` — computed via `app._compute_shipment_leg_eta` (`ATW-228`) and coarsened, never a raw distance-remaining or delay-in-minutes figure. This is deliberately distinct from the pre-existing `current_eta`/`is_delayed` fields (`OPS-173`'s own milestone-only heuristic, still present unchanged) — `live_eta_status`/`live_eta_at` are the real, telemetry-based estimate.
- **Position coordinates**, when present, are the real current position — rounded in the UI presentation layer, not truncated at the database layer.

### 2.2 The one real gate: `customer_visible`

A customer sees a vehicle position or live ETA **only when the shipment's own currently-executing leg's tracking policy explicitly sets `customer_visible = true`** (`app.shipment_leg_tracking_policies.customer_visible`, `ATW-225` — reused, not reinvented). Every one of the following conditions yields honest `null` position/ETA fields, **never a raised error and never a silent default-to-visible**:

- No vehicle is currently assigned to the shipment.
- No leg is currently executing.
- The currently-executing leg's own tracking policy has `customer_visible = false` (the default).
- No canonical position has ever been captured for the assigned vehicle.

### 2.3 What the public page renders

`app/(public)/tracking/[token]/page.tsx` shows the three sanitized fields as a coarse status message plus — only when a real position is present — rounded coordinates and an updated timestamp. **There is deliberately no embedded map on this page.** Two reasons, both disclosed at `ATW-226H`: this is a pre-authentication, anonymous public route, and embedding a live map would mean either a third-party tile-server request from an anonymous page (a privacy/dependency concern) or a second Leaflet integration outside that checkpoint's own bounded scope.

## 3. Evidence

`scripts/db-tests/advanced-tms-fleet-control-tower.sql` proves: `app.get_tenant_vehicle_tracking_overview` returns one row per active vehicle including a never-tracked vehicle with honest null position fields (never a missing row); the pending-signal reads are tenant-wide and unauthorized-actor-rejecting; the widened `app.lookup_public_shipment_tracking` yields a sanitized live position when `customer_visible=true` with a real position, and honest nulls the instant the same leg is flipped to `customer_visible=false`; schema-privilege defense in depth (the three new Fleet Control Tower reads are `authenticated`-only; the public function keeps its exact pre-existing 3-grantee shape — `anon`, `authenticated`, `service_role` — after each widening; the repository-wide `anon`-grant count is tracked exactly). `scripts/db-tests/advanced-tms-milestone-exception-telemetry.sql` proves the `live_eta_status`/`live_eta_at` widening on the identical `customer_visible` gate. See `ATW-226H.md` §4 and `ATW-228.md` for the exact historical gate counts at each checkpoint — read the live `db:test` output for the current repository-wide total.

## 4. Residual boundaries, disclosed

- No live map on the public/customer route — coarse status text plus rounded coordinates only (§2.3).
- No responsive/interactive browser verification of the Fleet Control Tower UI was possible in this sandbox (the disclosed Playwright `chrome-headless-shell` binary-revision-skew condition, present since `PLT-117`) — verification is `next build` (all new routes compile and appear in the route manifest) plus `next dev` + `curl` reachability probing against placeholder Supabase environment values, never a claim of full visual/interactive verification.
- The remaining `ISS-2026-010` scope (roughly 74 tenant-scoped RLS `SELECT` policies still keyed only on `has_active_tenant_membership`, never a `customer_user`-layer check) is **not** exercised by anything in this guide's own surfaces — the Fleet Control Tower and the customer-safe public projection are both staff-authenticated or deliberately anonymous, never a `customer_user`-layer session. See `privacy-consent-and-retention-guide.md` §4 and `ADVANCED_TMS_WMS_HANDOFF_PACKAGE.md` for the full disclosure of that residual, which instead concerns `app.wms_outbound_orders`/`wms_outbound_order_lines`/`lot_identities`/`serial_identities` and the broader Customer Portal boundary.
