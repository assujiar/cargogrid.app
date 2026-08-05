# Privacy, Consent, and Retention Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff).
**Audience:** support/compliance staff answering "what does CargoGrid collect about a driver, who can see it, and how long is it kept," and developers who must not weaken any of the controls described here.
**Source of truth:** the migrations cited inline. Where this guide states that something is *not* enforced, that is a direct, checked finding (grep across the relevant migrations/service code), not an assumption.

## 1. What is collected, and why

| Data | Table | Collected from | Purpose |
|---|---|---|---|
| Driver location, speed, heading, accuracy, battery level | `app.driver_mobile_position_reports` | The driver's own device, via the Driver Mobile HTTPS contract | Trip tracking, ETA, geofence/exception detection |
| Device-reported OS permission state | `app.driver_mobile_position_reports.location_permission_granted`/`background_permission_granted` | The (hypothetical) client app self-reports these; the server cannot independently verify them | Diagnostic — lets a dispatcher tell "driver never granted background location" apart from "no signal" |
| Vehicle position, speed, heading | `app.direct_device_telemetry_reports` | Hardware GPS unit installed in the vehicle | Vehicle-level (not driver-level) tracking |
| Vehicle position, speed, heading | `app.third_party_telemetry_reports` | A third-party fleet-telematics platform, via signed webhook | Vehicle-level tracking, sourced from an existing customer/partner telematics contract |
| Consent flag and timestamp | `app.driver_operational_profiles.mobile_tracking_consent`/`mobile_tracking_consent_at` | Recorded by staff (`OPS:Edit`), on the driver's own behalf | The one real precondition to `driver_mobile` tracking existing at all |
| License class/expiry, employment status | `app.driver_operational_profiles.license_class`/`license_expiry_date`/`status` | Staff data entry | Operational eligibility, not itself telemetry |

No name, phone number, or other direct driver-identity field is stored on any telemetry table — the driver is referenced only by `app.master_records` foreign keys (`driver_master_id`, or transitively via `app.shipment_leg_tracking_sessions.resource_master_id`). Identity resolution (turning that id into a name) happens at the master-data layer, not the telemetry layer.

## 2. Consent — what it actually gates, and what it does not

`mobile_tracking_consent` is a boolean recorded by staff, because **drivers hold no CargoGrid login and there is no driver-facing consent-capture screen anywhere in this repository** (see `driver-mobile-tracking-guide.md` §1/§2 for the full disclosure — "Driver Mobile" is a tested backend contract, not a shipped app a driver could use to grant or review their own consent). This is a real, honest limitation: consent today is an internal record-keeping mechanism, not a driver-facing consent-management flow.

**What consent gates, precisely:**

1. **Session start** — `app.check_leg_tracking_source_eligible` (`ATW-225`) requires `mobile_tracking_consent = true` before a dispatcher can even start a `driver_mobile` tracking session for a leg.
2. **Every single ingestion call, live, since `ATW-027`** — before this checkpoint, revoking consent mid-session (via `app.set_driver_mobile_tracking_consent`) did not stop an already-issued bearer token from continuing to submit location reports; this was a real, live-reproduced HIGH-severity finding, fixed by adding a live re-check of the session's own driver's *current* `mobile_tracking_consent` value on every call to `app.ingest_driver_mobile_report` (`20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql`). Revoking consent now takes effect on the very next report the driver's device submits, not merely on the next session start.

**What consent does not gate:** `direct_device` and `third_party_platform` telemetry are vehicle-sourced, not driver-sourced — `mobile_tracking_consent` has no bearing on either. A driver operating a vehicle fitted with a hardware GPS unit is tracked via that unit regardless of their own `mobile_tracking_consent` flag; that flag only ever controls the `driver_mobile` (phone-based) source specifically.

## 3. Retention — read honestly, not invented

This section states the real, current fact rather than a plausible-sounding number: **no automated deletion, purge, or TTL job exists anywhere in this repository for any Phase 5 telemetry table.** This was checked directly, not assumed:

- `app.tenant_tracking_source_policies`'s own entitlement composite type declares a `history_retention_days` field (`tracking.limits.history_retention_days`, resolved via `app.resolve_tenant_tracking_package`) — but a repository-wide search confirms this value is **read nowhere outside its own definition file and the mirroring TypeScript contract/test layer**. No function anywhere deletes a row from `app.canonical_telemetry_events`, `app.driver_mobile_position_reports`, `app.direct_device_telemetry_reports`, or `app.third_party_telemetry_reports` based on age, and no scheduler exists to run one even if it did — `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-015` already records that no `pg_cron`-or-equivalent scheduler/worker runtime exists anywhere in this repository, for any purpose.
- **This is distinct from the ratified, contractual retention *policy*.** `RPD-025` (`docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md`) states a real, class-based retention schedule — "operational data: contract term + 90 days" is the class GPS telemetry would fall under. That decision is ratified at the product/legal level. **It has no corresponding enforcement mechanism in Phase 5's own code.** Do not represent Phase 5 as retention-compliant against `RPD-025` in any customer- or auditor-facing material — the honest statement is: the policy exists, the enforcement does not yet.
- `app.get_vehicle_telemetry_history` and `app.get_driver_mobile_position_reports` are both hard-capped at read time (500 rows / unbounded-but-ordered respectively) — this bounds a single *query's* result size, it is not a data-retention control and does not delete anything.

**Practical consequence:** every telemetry row this repository has ever accepted, for any tenant, remains queryable indefinitely today, subject only to the access controls in §4 below. Whichever future checkpoint builds a scheduler (the same one `ISS-2026-015` already names as a prerequisite for several other deferred capabilities) should treat wiring a real `history_retention_days`-driven purge as a genuinely new deliverable, not a bounded fix to anything that exists today.

## 4. Tenant data isolation (RLS)

Every Phase 5 telemetry, position, and health table has row-level security enabled, and every one of them uses the identical, repository-standard predicate:

```sql
using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
```

Confirmed directly on: `app.canonical_telemetry_events`, `app.vehicle_current_positions`, `app.vehicle_source_health`, `app.vehicle_source_switches` (`20260729390000`), `app.driver_mobile_tracking_sessions`, `app.driver_mobile_position_reports` (`20260729360000`), `app.direct_device_telemetry_reports` (`20260729370000`), `app.third_party_telemetry_reports` (`20260729380000`), `app.tenant_tracking_source_policies` (`20260729340000`).

**What this means, stated precisely:** RLS enforces *tenant* isolation — no member of Tenant A can ever read a row belonging to Tenant B (or Supreme Admin, subject to `RPD-022` below). It does **not**, by itself, restrict *which role within* a tenant can read raw driver location/telemetry history — `app.get_driver_mobile_position_reports` is `security invoker` (relies entirely on the caller's own RLS-scoped session, applies no additional RBAC check of its own), so any authenticated member of a tenant — not only `OPS`-permissioned staff — can read raw driver location history for that tenant, including battery level and device permission flags, either through this function or a direct table `SELECT`. This is the same tenant-wide-read convention every prior phase in this repository has used for its own internal (non-customer-facing) operational tables; it is not a Phase-5-specific weakening, and it is a materially different scope question from the `customer_user`-layer isolation problem described next.

**The `customer_user`-layer boundary (`ISS-2026-010`, narrowed, still partly `OPEN`) is a different concern and does not affect any table named above.** `ATW-023` (Customer Inventory Access Contract) discovered and fixed a live, exploitable RLS gap on four *WMS* tables (`app.wms_outbound_orders`/`app.wms_outbound_order_lines`/`app.lot_identities`/`app.serial_identities`) once a real `customer_user`-layer principal became meaningful for the first time — see `docs/build-log/phase-05/ATW-023.md` §3.3 finding 1 for the full account. `docs/runtime/KNOWN_ISSUES.md`'s current entry narrows the remaining exposure to roughly 74 other tenant-scoped `SELECT` policies across the repository (none of them a Phase 5 telemetry table) that have never been individually audited for the same latent pattern — `OPEN`, non-blocking today (no live production `customer_user` principal exists anywhere), explicitly named as blocking "the next capability that grants a live production `customer_user` principal (Step 13 Customer Portal)." Carry this forward: whichever team builds Step 13 must re-run that audit before granting the first real `customer_user` membership, not assume Phase 5's own telemetry tables are already covered by it (they were never in scope for `ATW-023`'s own fix, since no customer-facing read of raw driver/vehicle telemetry exists anywhere — only the sanitized public projection, §5 below).

**`RPD-022`** (Supreme Admin can mutate/delete audit, ledger, payment, and — by the same standing exception — any tenant-scoped record including telemetry) applies here exactly as it does everywhere else in this repository: no tamper-proof or immutability claim may ever be made about driver location history, canonical telemetry events, or any other Phase 5 table. This is a permanent, disclosed, repository-wide condition, not something Phase 5 introduced or could opt out of.

## 5. What a customer ever sees

A customer-facing session (whether the deliberately-anonymous public tracking link, or a future `customer_user`-layer Customer Portal session) never receives raw telemetry. The only customer-reachable surface is `app.lookup_public_shipment_tracking`'s sanitized projection — a coarse `live`/`delayed`/`unavailable` position status and `on_time`/`delayed`/`unavailable` ETA status, gated on the shipment's own currently-executing leg having `customer_visible = true` — see `fleet-control-tower-and-customer-projection-guide.md` §2 for the full treatment. No raw source type, device identifier, driver identity, or provider payload is ever exposed through this path.

## 6. Audit

Every mutation described in this guide is captured through the repository-standard `app.capture_audit_event` call — device registration/deregistration, installation evidence, consent changes, tenant source-policy edits, milestone/exception confirm-or-dismiss decisions. A pre-existing, repository-wide (not Phase-5-specific) architectural characteristic is worth disclosing here since it bears on audit trustworthiness: `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-017` (Low, `OPEN`) records that no `SECURITY DEFINER` RPC anywhere in this repository (~130 migrations, Phase 5 included) independently cross-checks its own `p_actor_auth_user_id` parameter against the caller's real, session-bound `auth.uid()` — every real caller today is this repository's own TypeScript service layer, which is expected to pass the session's own true identity, but no database-level backstop exists to catch a hypothetical future caller that skips that layer. Not known to be live-exploitable, not fixed by this checkpoint (out of its own bounded scope), disclosed for completeness.

## 7. Evidence

The consent live-recheck is proven in `scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` (see `driver-mobile-tracking-guide.md` §8). RLS tenant-isolation for every table in §4 is proven per-capability in that capability's own db-test file (`advanced-tms-canonical-telemetry-arbitration.sql`, `advanced-tms-driver-mobile-tracking.sql`, `advanced-tms-gps-gateway-ingestion.sql`, `advanced-tms-third-party-provider-adapter.sql`, `advanced-tms-tracking-entitlement-source-policy.sql`) — each asserts zero cross-tenant visibility and the exact schema-privilege grant shape (`ERR-2026-004`'s own per-migration convention: `revoke execute on all functions in schema app from public` before every explicit grant).
