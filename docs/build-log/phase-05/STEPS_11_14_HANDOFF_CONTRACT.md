# Phase 5 → WBS Steps 11–14 Handoff Contract

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), per Prompt 247 §20's own "Steps 11–14 handoff contracts" deliverable.
**Structure:** mirrors `docs/build-log/phase-02/JOB_ORDER_HANDOFF_CONTRACT.md`'s own precedent — this document explains and exemplifies the real, already-`VERIFIED` contract surfaces; it does not redefine them. If this document and a cited migration/contract file ever disagree, the migration/contract file is authoritative.
**Phase-to-step mapping** (`docs/runtime/CARGOGRID_BUILD_STATUS.md` §3, "Phase status" table): Step 11 = Phase 6, Procurement/Vendor; Step 12 = Phase 7, HRIS/Ticketing; Step 13 = Phase 8, Customer Portal/Loyalty; Step 14 = Phase 9, Intelligence/Enterprise. All four phases are `NOT_STARTED` as of this checkpoint — zero Procurement/HR/Ticketing/Customer-Portal/Loyalty/Intelligence/Enterprise domain code exists anywhere in this repository (re-confirmed below, §6).

## 1. What this contract is, and is not

Phase 5 ships exactly one shipped, read-only, backend contract explicitly designed for a downstream customer-facing phase to build against (`ATW-023`, Customer Inventory Access — Step 13). For the other three steps, Phase 5 either names an explicit, deliberate non-integration boundary in its own source prompts (Step 11) or has never addressed the pairing at all (Steps 12 and 14) — this document discloses each honestly rather than inventing a contract that does not exist, mirroring the precedent `docs/build-log/phase-04/FINANCE_DOWNSTREAM_CONTRACTS.md` set for the equivalent "no relationship" and "future, undesigned" cases (as summarized in `docs/build-log/phase-04/FINANCE_HANDOFF_PACKAGE.md` §3).

## 2. Step 11 (Phase 6, Procurement/Vendor) — deliberately not integrated, one named extension point

**No live integration exists.** Phase 5's own source prompt is explicit that this is deliberate, not an oversight: `app.wms_inbound_orders.source_type` is a closed `CHECK` enum (`'shipment_order'`, `'manual'`, `'import'`) that **deliberately excludes `'purchase_order'`** — Prompt 231 §24's own words, quoted directly in `ATW-012.md` §2 design note 3: *"Future PO/vendor linkage does not implement Step 11 lifecycle."*

### 2.1 Owned data Phase 6 may read

Nothing Phase 5 owns is designed as a Phase-6 read contract today. If Phase 6 needs to know what warehouse activity already exists for a shipment it is procuring transport/vendor services for, it must read Phase 3's own already-`VERIFIED` Operations contracts (`app.shipment_orders`, `app.job_order_handoffs`), not a Phase 5 table.

### 2.2 Explicitly forbidden mutations

- Phase 6 must never write to `app.wms_inbound_orders`, `app.wms_inbound_order_lines`, or any other Phase 5 WMS table directly.
- Phase 6 must never represent a purchase-order-sourced receipt as `source_type = 'manual'` or `'import'` as a workaround for the missing `'purchase_order'` value — that would misattribute provenance in a table other capabilities (billing eligibility, claim evidence) already trust as accurate.
- Phase 6 must never edit `ATW-012`'s own already-applied migration (`supabase/migrations/20260730180000_create_advanced_tms_wms_inbound.sql`) to add the missing enum value — any widening must be a new, additive migration, per this repository's own standing convention.

### 2.3 The exact extension point, if Phase 6 ever needs one

Widening `app.wms_inbound_orders.source_type`'s own `CHECK` constraint to add `'purchase_order'` (plus whatever new PO-reference column Phase 6's own design requires) is the one concretely-named seam. This is a real, disclosed **design decision Phase 6 must make itself** — Phase 5 does not prescribe the shape of a PO reference, a vendor master, or a three-way-match mechanism; none of those exist anywhere in this repository.

A second, narrower and unrelated observation: `app.gps_devices.ownership_type` (`'cargogrid'`/`'customer'`/`'partner'`, `ATW-223`) records who owns a piece of GPS hardware. This is **not** a vendor/asset-procurement record and carries no linkage to any future Procurement vendor-master table — disclosed here only so a future Phase 6 agent does not mistake it for an existing asset-procurement contract.

### 2.4 Unresolved dependency list

1. The purchase-order → inbound-order linkage itself (schema, RPC, and reconciliation logic) — entirely Phase 6's own design.
2. Any vendor-master or three-way-match concept — does not exist anywhere in this repository (Finance's own `app.finance_vendor_bills`, Phase 4, is the closest existing artifact, and it explicitly carries no Job Order/Shipment Order/warehouse linkage either — see `docs/build-log/phase-04/FINANCE_HANDOFF_PACKAGE.md` §6).
3. Whether Procurement ever needs its own view of GPS/fleet asset ownership (`ownership_type`) for vendor-supplied hardware — undesigned.

## 3. Step 12 (Phase 7, HRIS/Ticketing) — no relationship built, disclosed rather than omitted

**Phase 5 has no direct dependency relationship with Phase 7, and no Phase 5 build log, prompt, or migration anywhere names HR, HRIS, or Ticketing.** This is disclosed explicitly, the same way `docs/build-log/phase-04/FINANCE_HANDOFF_PACKAGE.md` §3's own "Phase 5 boundary note" disclosed Finance's own lack of a relationship rather than silently omitting the pairing.

### 3.1 What exists that a future HR domain might eventually care about

`app.driver_operational_profiles` (`ATW-223`) is the one Phase-5-owned "driver as a worker" operational record — `license_class`, `license_expiry_date`, `status` (`active`/`inactive`/`suspended`/`retired`), and the tracking-consent fields (§ below). This is an **operational extension**, not the driver's own identity record — the identity itself is `app.master_records`, owned by Platform Core, not Phase 5. `app.claim_responsibility_reviews` (`ATW-025`, Advanced Claim and Incident Operations) additionally records a driver-responsibility finding when a claim investigation assigns fault — a record a future HR/disciplinary process might plausibly want visibility into, but no such visibility exists today.

### 3.2 Explicitly forbidden mutations

- No future HR/Ticketing capability may write to `app.driver_operational_profiles` directly. `mobile_tracking_consent` in particular must only ever change through `app.set_driver_mobile_tracking_consent` (`OPS:Edit`-gated) — never a direct table `UPDATE`, since that RPC is also the audit-event boundary.
- No future HR/Ticketing capability may write to `app.claim_responsibility_reviews` or any other claim/incident table — that lifecycle is owned entirely by `app.operational_exceptions`'s own governed RPC surface (Operations, extended by `ATW-025`).

### 3.3 Contract surface

**None exists.** This is a disclosed future dependency, not a built one — the same honesty convention `FINANCE_HANDOFF_PACKAGE.md` §3 applied to Finance's own undesigned Phase 9 analytics relationship.

### 3.4 Unresolved dependency list

1. Whether a future HR/personnel domain reads `app.driver_operational_profiles` at all, or instead builds its own worker record referencing the same `app.master_records` identity independently.
2. Whether license-expiry tracking (`license_expiry_date`) becomes an HR-owned compliance concern or remains Phase-5-owned operational data.
3. Whether claim-responsibility findings ever feed a disciplinary/ticketing workflow — undesigned, no schema exists for it.

## 4. Step 13 (Phase 8, Customer Portal/Loyalty) — the one real, shipped, read-only contract

This is the one Phase 5 downstream relationship that is genuinely built and `VERIFIED`. Source: `supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql` and `20260730311000_harden_customer_inventory_access_rls_isolation.sql` (`ATW-023`, Prompt 242). Every RPC below is `authenticated`-gated (never `anon`), composes `app.evaluate_customer_inventory_access(actor, tenant, warehouse, owner)`, and is read-only in Phase 5 by design — "zero `insert`/`update`/`delete` against any inventory/order/reservation table; the only `insert` in the base migration is the audit-log call inside the export RPC" (`ATW-023.md` §2 design note 7).

### 4.1 The gate

```sql
app.evaluate_customer_inventory_access(p_actor_auth_user_id uuid, p_tenant_id uuid, p_warehouse_id uuid, p_owner_account_id uuid) returns boolean
```

Composes exactly two ANDed checks: an active `customer_user`-layer membership whose uuid-shaped `customer_account_ref` equals the target `owner_account_id` (`app.principal_memberships`, reused from `ATW-016`'s own convention), **and** an active `app.warehouse_customer_eligibility` row for that warehouse/owner (`app.warehouse_customer_eligibility`, reused from `ATW-229` verbatim — no new grant table was created). This function never returns an "unrestricted" signal — deny-by-default throughout, unlike the staff-facing `app.resolve_actor_owner_account_scope` (`ATW-016`) it deliberately does not reuse for that exact reason.

### 4.2 The read/export RPC surface (owned data Phase 8 may read)

| Function | Returns |
|---|---|
| `app.get_customer_inventory_balance` | One permitted inventory balance |
| `app.list_customer_inventory_balances` | Cursor-paginated list of permitted balances |
| `app.list_customer_lot_identities` | Lot-level tracked-stock identities in scope |
| `app.list_customer_serial_identities` | Serial-level tracked-stock identities in scope |
| `app.get_customer_outbound_order` | One permitted outbound order |
| `app.list_customer_outbound_orders` | Cursor-paginated list of permitted outbound orders |
| `app.list_customer_outbound_order_lines` | Lines for one permitted outbound order |
| `app.list_customer_inventory_movement_summary` | Permitted movement-lineage summary |
| `app.export_customer_inventory_snapshot` | A bounded, audited export (the one RPC with a real side effect — an audit-log insert) |
| `app.list_customer_warehouse_eligibility` | The customer's own visibility into their own warehouse eligibility grants |
| `app.resolve_customer_owner_account_scope` | Resolves which `owner_account_id` values the calling `customer_user` may see at all |
| `app.customer_warehouse_eligibility_active` | Shared predicate (internal composition, not typically called directly by a consumer) |
| `app.record_customer_inventory_access_denial` | Records a denied-access attempt for audit — called by the service layer after catching a `record_not_found`, never by a client directly |

### 4.3 Compatibility notes

- **Cursor pagination is mandatory and keyset-based** (`(col, id) < (p_cursor_col, p_cursor_id)`, never `OFFSET`) on every list RPC — a stricter bar than the plain-`LIMIT` convention most internal staff list RPCs in this repository use. A malformed cursor (one component supplied without the other) raises an explicit `invalid_cursor` error rather than silently returning an empty page — Phase 8's own client code must handle this as a real error, not "no more results."
- **Anti-enumeration**: every single-row `get` RPC raises an identical `record_not_found` whether the row is missing, cross-tenant, or forbidden — deliberately narrower than the distinguishable `insufficient_authority` staff-facing RPCs raise. Phase 8 must not build any UI affordance that would let a user distinguish "does not exist" from "not yours" (e.g. do not surface the raw Postgres error text to the browser).
- **`app.list_customer_outbound_order_lines` takes no `p_tenant_id` parameter**, unlike its 12 sibling RPCs — it derives tenant from the fetched row instead, which is fed back into `app.get_customer_outbound_order`'s own full gate. This is confirmed non-exploitable, a signature-consistency note only (`ATW-023.md` §3.3 finding 10).
- **No REST/GraphQL surface exists for this contract, or any domain, anywhere in this repository yet.** Whichever phase first wires a live HTTP route to any of these RPCs is responsible for re-verifying the anti-enumeration and masking behavior holds through that route's own serializer — it is not guaranteed to hold automatically.

### 4.4 Explicitly forbidden mutations

- **Phase 8 must never grant a real production `customer_user`-layer membership before re-running the broader `ISS-2026-010` RLS audit.** `docs/runtime/KNOWN_ISSUES.md`'s current entry narrows the *known-fixed* exposure to exactly four tables (`app.wms_outbound_orders`/`app.wms_outbound_order_lines`/`app.lot_identities`/`app.serial_identities`, hardened at `20260730311000`) and explicitly names the remaining ~74 other tenant-scoped `SELECT` policies across the repository as unaudited for the identical latent-owner-scope-branch pattern — `OPEN`, and explicitly scoped as blocking "the next capability that grants a live production `customer_user` principal (Step 13 Customer Portal)." This is not optional due diligence; it is the literal condition the currently-open issue names as its own trigger.
- Phase 8 must treat every RPC in §4.2 as read-only — none of them may be wrapped in a way that performs a write against any WMS/inventory/order table. The one legitimate write (the audit-log insert inside `export_customer_inventory_snapshot`, and the denial-audit insert inside `record_customer_inventory_access_denial`) is already built and must not be duplicated.
- Phase 8 must never bypass this RPC layer via a direct table read against `app.wms_outbound_orders`/`wms_outbound_order_lines`/`lot_identities`/`serial_identities`/`inventory_balances` (or any other Phase 5 table) for a `customer_user`-layer session, even where RLS might appear permissive — the RPC layer is the one sanctioned customer read path by design (`ATW-023.md` §2 design note 4), and the one place this claim was found not fully true (the four tables above) was closed by hardening the RLS itself, not by asking callers to route around it.

### 4.5 Unresolved dependency list

1. **Full Customer Portal UX/navigation/self-service** — explicitly Step 13's own scope by design (Prompt 242 §15/§24); Phase 5 ships only the backend contract for Step 13 to build against, deliberately no UI route.
2. **Real "expiry" semantics on warehouse-customer eligibility** — `app.warehouse_customer_eligibility`'s own two-value (`active`/`revoked`) status `CHECK` cannot express expiry as currently shipped; building it requires altering `ATW-229`'s own already-applied table/RPCs, a capability-sized change Phase 5 deliberately did not make.
3. **Rate limiting on the 13 customer-facing RPCs** — none exists; the one existing repository precedent (`app.lookup_public_shipment_tracking`) is purpose-built for a genuinely anonymous `anon`-role surface, a materially different threat model from these already-authenticated RPCs. Phase 8 must design its own if it judges this necessary before production launch.
4. **The broader `ISS-2026-010` audit itself** (§4.4) — a repository-wide task, not a Phase 8 task per se, but Phase 8's own launch is the actual trigger condition.
5. **Independent "company/site" scope-axis test coverage** — very likely functionally subsumed by the warehouse-eligibility check (a warehouse belongs to exactly one company/org-unit), but never proven as its own independent axis.

## 5. Step 14 (Phase 9, Intelligence/Enterprise) — no relationship built, disclosed rather than omitted

**No Phase 5 build log, prompt, or migration anywhere names Intelligence, Enterprise, or BI.** Disclosed explicitly, mirroring `FINANCE_HANDOFF_PACKAGE.md` §3's own treatment of Finance's identical undesigned relationship with Phase 9.

### 5.1 What exists that a future analytics domain might eventually read

Phase 5 ships several dashboard-shaped, tenant-scoped read projections that are natural future analytics inputs, though no contract exists yet: `app.dispatch_board_queue` (`ATW-222`), `app.get_tenant_tracking_coverage`/`app.get_tenant_tracking_utilization_summary` (`ATW-227`), `app.get_tenant_vehicle_tracking_overview` (`ATW-226H`), and the warehouse-billing-event tables (`ATW-022`, which already hands off to Finance, not to Phase 9). None of these were designed with a cross-tenant or aggregate-analytics consumer in mind — every one of them enforces per-tenant RLS and per-caller RBAC exactly as every other Phase 5 read path does, and pulling data across tenants for analytics purposes (if that is ever Phase 9's model) is not a pattern anything in Phase 5 has been built or tested against.

### 5.2 Explicitly forbidden mutations

None specifically designed, since no contract exists. The general rule that applies until one is designed: any future Phase 9 capability must be read-only against every Phase 5 table, and must respect the same `customer_visible`/RLS/entitlement boundaries this document describes elsewhere when aggregating data that touches customer-visible fields.

### 5.3 Contract surface

**None exists.** A disclosed real future dependency, not a built one.

### 5.4 Unresolved dependency list

1. Whether Phase 9 reads Phase 5's operational tables directly (requiring a new, audited cross-tenant/aggregate read path) or via a data-warehouse/ETL layer outside the live transactional schema — undesigned, no decision has been made either way.
2. Whether the existing `app.shipment_tracking_health`/`vehicle_source_health` freshness/health signals become a Phase 9 fleet-reliability metric — undesigned.
3. Whether claim/incident data (`ATW-025`) becomes a loss-ratio or risk-analytics input — undesigned.

## 6. Forbidden-scope confirmation (re-checked this checkpoint)

```
git ls-files app/ lib/ server/ components/ | grep -iE "purchase_order|vendor_master|three_way_match|hris|employee_profile|ticketing|customer_portal|loyalty|intelligence_enterprise|business_intelligence"
```

returns zero matches (re-run directly this checkpoint) — zero Procurement/Vendor, HRIS/Ticketing, Customer-Portal/Loyalty (beyond the disclosed `ATW-023` backend contract in §4, which is a Phase 5-owned artifact, never a Customer Portal UI route), or Intelligence/Enterprise domain concept exists anywhere in application code.
