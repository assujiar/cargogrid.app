# Subscription Package and Entitlement Guide — Tracking

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff).
**Audience:** tenant admins configuring a tracking package, developers building on top of `app.is_shipment_tracking_entitled`, and support staff explaining why an untracked shipment is still visible on the dispatch board.
**Source of truth:** `supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql` (`ATW-226A`). Read that migration directly for the authoritative function bodies; this guide explains and cites it, it does not redefine it.

## 1. What "tracking entitlement" actually is

Tracking entitlement answers exactly one question: **has an authorized tenant admin published a `tracking.enabled = true` configuration item for this tenant?** It is not a separate SaaS-subscription gate (`app.evaluate_entitlement`, `PLT-106`) and not a feature flag (`PLT-133`) — `ATW-226A` deliberately reuses neither, because Prompt 222's own migration header (`20260729300000`) already named the real mechanism: "the real `tracking.*` entitlement keys in the Configuration Engine (`PLT-121`)." `ATW-226A` honors that citation exactly.

There is no new schema for entitlement itself. `app.tracking_package_resolution` is a composite type read through the existing Configuration Engine's `app.resolve_config('feature', p_tenant_id)` RPC against three tenant-scoped config items:

| Config item | Meaning |
|---|---|
| `tracking.enabled` | boolean — the actual entitlement gate |
| `tracking.package` | text — a package/tier code (free-form; no fixed enum is defined in this checkpoint) |
| `tracking.limits.max_tracked_vehicles` | integer or absent |
| `tracking.limits.max_mobile_sessions` | integer or absent |
| `tracking.limits.history_retention_days` | integer or absent — see §4 below; **declared but not enforced anywhere in code** |

## 2. How to assign a package to a tenant

There is no dedicated "assign tracking package" screen or mutation. A tenant admin (or an operator acting on their behalf) assigns a package through Platform Core's already-shipped generic Configuration Engine mutations — `createConfigDraft` → `setConfigItems` → `publishConfigVersion` (`PLT-121`), targeting the pre-seeded bare `feature` config type, exactly as any other Configuration Engine consumer would. No per-tenant tracking data is seeded by any migration — every tenant starts, and stays, unentitled until this real publish action happens.

## 3. The two resolver functions every later capability reads

```sql
app.resolve_tenant_tracking_package(p_tenant_id uuid) returns app.tracking_package_resolution
app.is_shipment_tracking_entitled(p_tenant_id uuid) returns boolean  -- select (resolve_tenant_tracking_package(p_tenant_id)).enabled
```

Both **always return exactly one row/value**, never `null` and never a raised error. When no package was ever assigned, the honest default is `enabled = false` with every other field `null` — never a fabricated entitlement. `app.is_shipment_tracking_entitled` was originally shipped as a disclosed, always-`false` stub at `ATW-222` (`20260729300000`); `ATW-226A` replaced it with this real implementation via `CREATE OR REPLACE FUNCTION` at the identical signature, so its pre-existing `authenticated`/`service_role` grant carried forward unchanged.

`app.resolve_tenant_tracking_source_policy(p_tenant_id uuid)` is the companion resolver for the *tenant-level default source policy* (priority order, freshness/accuracy thresholds, switch hysteresis) — a distinct concept from entitlement, at a distinct grain from `ATW-223`'s per-vehicle `app.vehicle_tracking_source_priorities`. It also always returns exactly one row (`is_explicit = false` when no tenant admin has ever called `app.upsert_tenant_tracking_source_policy`), falling back to the system-wide constants (`driver_mobile` → `direct_device` → `third_party_platform` priority, 300s freshness, 100m accuracy, 120s hysteresis).

## 4. Package limits are declared, not enforced

Direct inspection of every migration that references `max_tracked_vehicles`/`max_mobile_sessions`/`history_retention_days` confirms:

- `max_tracked_vehicles` is read exactly once outside its own definition — by `app.get_tenant_tracking_utilization_summary` (`ATW-227`, `20260730120000_create_advanced_tms_capacity_utilization.sql`), which computes and returns `tracked_vehicle_limit_remaining` as a **reporting figure**. No registration or session-start RPC anywhere in the schema (`app.register_gps_device`, `app.start_driver_mobile_session`, `app.start_leg_tracking_session`) reads this value or rejects a call once the limit is reached. It is not a hard gate today.
- `max_mobile_sessions` is likewise only read for the same utilization-reporting purpose, never enforced against an active session count.
- `history_retention_days` is read nowhere at all outside its own definition file and the TypeScript contract/test layer that mirrors it. No purge, deletion, or TTL job exists anywhere in this repository that consumes it — see `privacy-consent-and-retention-guide.md` §3 for the full, honest retention disclosure.

**Practical consequence:** setting `tracking.limits.max_tracked_vehicles` to a number today changes only what the utilization dashboard reports as "remaining capacity" — it does not stop a 21st vehicle from being tracked once 20 is configured as the limit. Any future capability that wants a real hard cap must add that check itself; nothing in Phase 5 silently enforces one today, and this document does not claim otherwise.

## 5. What happens when a tenant is NOT entitled — disclosed, not blocking

This is the single most important behavioral fact to carry forward: **entitlement is disclosed everywhere it is relevant, but it is never a hard gate on session start, dispatch-board visibility, or orchestration bookkeeping.**

- `app.dispatch_board_queue` (`ATW-222`) always shows every `assigned`/`dispatched`/`in_transit` shipment the caller can access, regardless of entitlement — `tracking_entitled` is one honest column among the tracking columns (alongside `tracking_status`, `freshness_status`, etc.), never a filter that hides rows.
- `app.shipment_leg_tracking_sessions` (`ATW-225`) snapshots `app.is_shipment_tracking_entitled(tenant_id)` onto every session it creates, as `tracking_entitled_at_start` — a permanent audit fact, never re-evaluated after session start and never consulted by any later function to decide whether the session should exist. `ATW-225`'s own migration header states this explicitly: *"Entitlement is disclosed, never a hard gate... orchestration bookkeeping itself is not blocked by it — real eligibility is what gates start/handoff (`app.check_leg_tracking_source_eligible`)."*
- The real gate on whether a leg's tracking session may actually start is **eligibility**, a separate, independent check: does the shipment have a current vehicle assignment (`app.resource_assignments`), does the assigned driver have `mobile_tracking_consent = true` (for `driver_mobile`), does the vehicle have a current device/provider mapping (for `direct_device`/`third_party_platform`)? A tenant can be fully entitled and still have zero eligible sources for a given leg; conversely a tenant can be unentitled and still have every session-orchestration mechanic function normally — entitlement is recorded, not enforced.
- `app.arbitrate_and_project_vehicle_position` (`ATW-226F`) itself never checks entitlement at all — a raw ingested report from an unentitled tenant is still canonicalized and can still win arbitration. Nothing in the ingestion or arbitration path reads `app.is_shipment_tracking_entitled`.

This was a real design decision recorded during `ATW-225` (Prompt 225), before real entitlement evaluation even existed (`app.is_shipment_tracking_entitled` was still `ATW-222`'s always-`false` stub at that point) — every session `ATW-225` itself created was therefore honestly `tracking_entitled_at_start = false`, disclosed, never hidden. The behavior did not change once `ATW-226A` shipped the real evaluator; only the *value* being snapshotted changed from an always-`false` stub to a real per-tenant resolution.

**What this means for support/operations:** if a customer asks "why does the dispatch board show a tracking column for a shipment when we haven't purchased tracking," the honest answer is that the column is always structurally present and honestly reports `not_tracked`/`unknown`/`not entitled` — it is a disclosed absence, not a bug, and switching the tenant's own `tracking.enabled` config item on does not retroactively fabricate any position history that was never actually captured.

## 6. No UI exists for package assignment; the source policy is fully editable

`ATW-226A` shipped schema and resolvers only — no screen exists to publish a `tracking.enabled=true` config item (Configuration Engine draft/publish UI does not exist generically anywhere in this repository yet, for any config type). `ATW-226H` (Fleet Control Tower) later added `app/(tenant)/[tenantSlug]/admin/tracking/` with a **read-only** entitlement/package display, plus a **fully editable** tenant-level source-policy form (`app.upsert_tenant_tracking_source_policy`, `OPS:Edit`-gated) — see `fleet-control-tower-and-customer-projection-guide.md` §1. Assigning or changing a tenant's actual tracking package today requires an operator using Platform Core's generic Configuration Engine mutations directly (`createConfigDraft`/`setConfigItems`/`publishConfigVersion` against the `feature` config type, item keys `tracking.enabled`/`tracking.package`/`tracking.limits.*`).

## 7. Evidence

`scripts/db-tests/advanced-tms-tracking-entitlement-source-policy.sql` proves: the honest false/null default before any package is assigned; a real package assignment reflected immediately by both resolvers, with a second tenant provably unaffected (cross-tenant isolation); a superseding published version (package upgrade) reflected immediately; the source-policy system-default before any explicit override; full input validation on `app.upsert_tenant_tracking_source_policy` (empty/duplicate/invalid-element priority array, non-positive freshness/accuracy, negative hysteresis); RLS (tenant-wide read, zero cross-tenant visibility); schema-privilege defense in depth (zero `anon` `EXECUTE` on any of the four functions). `node:test` and `db:test` counts for this file are recorded at `ATW-226A.md` §4 — read the live gate output for the current repository-wide total rather than treating any single historical count as durable.
