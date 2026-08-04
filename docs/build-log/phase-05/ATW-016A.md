# ATW-016A — WMS Outbound Order

## 0. Checkpoint

| Field | Value |
|---|---|
| Task | `CG-S10-ATW-016A` — inserted between the `VERIFIED` Prompt 235 (Lot, Batch, Serial and Expiry, `CG-S10-ATW-016`) and Prompt 236 (WMS Picking, `CG-S10-ATW-017`), no source prompt number |
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-231-238-e2wb54` |
| Dependency | `CG-S10-ATW-011A`/`012`/`016` (Item/SKU and UOM Master, WMS Inbound, Lot/Batch/Serial/Expiry, all `VERIFIED`); `app.shipment_orders` (`OPS-169`, Operations/Phase 3, already `VERIFIED`) |
| Authorization | The operator gave standing authorization to complete Prompts 231–238 ("saya bebaskan anda untuk memilih opsi terbaik, yg penting prompt 231-238 bisa selesai pembangunannya dengan baik" — I give you freedom to choose the best option, the important thing is prompts 231-238 get built well), after this session's own orchestrating agent identified that `docs/runtime/KNOWN_ISSUES.md`'s own `ISS-2026-011` Part 2 (`OPEN` since `ATW-015`) genuinely blocks Prompt 236 (Picking) from starting: Prompt 236 §9 names "a confirmed outbound demand contract" as its own upstream, but the only WBS-designated producer, Prompt 238 (WMS Outbound), is itself sequenced *after* Picking/Packing and requires their output. Direct inspection confirmed no existing repository entity (`app.shipment_orders`, aggregate-only, no item/SKU-level lines) already satisfies this. This checkpoint's own resolution mirrors the exact `ATW-011A` insertion precedent this session already used once for an identical package-level circular dependency: extract and build only the demand-creation/confirmation slice of Prompt 238 §13, now, ahead of Picking. |
| Execution method | Built via a background `Workflow` orchestration (implement → three independent adversarial reviewers → fix) — the identical structure `ATW-013`/`014`/`016` used. The `Workflow` tool itself had failed twice in a row on `ATW-016`'s own first two attempts (a confirmed environment defect, a malfunctioning permission handler in the workflow's own subagent sandbox, unrelated to any task content). This checkpoint's own `Workflow` invocation completed cleanly on its first attempt — the environment defect did not recur. Every gate result claimed by the workflow was independently re-run and re-verified by this checkpoint's own orchestrating session before this document was written — see §5. |

## 1. Pre-flight

Postgres 16 + PostGIS already running from the prior checkpoint in this same session. `git status` confirmed a clean worktree apart from this checkpoint's own new files. Full `db:test` run against the pre-existing 120 migrations/121 db-test files confirmed green before this task's own migration was authored (carried over directly from `ATW-016`'s own closing state, re-confirmed by the implementing agent).

## 2. Why this task exists and what it deliberately does not build

Prompt 238 (WMS Outbound) §13 database impact names, as one undifferentiated scope: "outbound root/version/number, customer owner/source order/shipment, lines/UOM, allocation/pick/pack references, staging/dock/load/custody, canonical lifecycle, idempotent ship-confirm inventory movements and billing-event eligibility." This checkpoint builds **only** the first clause — "outbound root/version/number, customer owner/source order/shipment, lines/UOM" — the demand header/lines and their draft→confirmed→cancelled lifecycle. Everything else in that list — allocation/pick/pack references, staging/dock/load/custody, ship-confirm inventory movements, billing-event eligibility — remains the real Prompt 238/`ATW-019` checkpoint's own later job, deferred until Picking (`ATW-017`) and Packing (`ATW-018`) exist for it to compose against. Prompt 238 §24's own business rule — "Outbound quantity reconciles demand → allocation → pick → pack → load → issue" — names this checkpoint's own output as exactly the first link in that chain, nothing more.

## 3. Design decisions (disclosed, migration header)

Twelve design notes are disclosed in the migration header (`supabase/migrations/20260730230000_create_advanced_tms_wms_outbound_order.sql`). The most consequential:

1. **`app.wms_outbound_orders`/`app.wms_outbound_order_lines` mirror `app.wms_inbound_orders`/`app.wms_inbound_order_lines` (`ATW-012`) near-exactly**, adapted for the outbound/demand-only side — same header/lines shape, numbering-counter mechanism, add/update/remove-line RPCs plus a bounded bulk-add RPC, and a readiness projection. Deliberately **not** mirrored: `ATW-012`'s own dock-appointment-scheduling RPCs — staging/loading is Prompt 238's own later job, not demand capture. Lifecycle is the simpler `draft` → `confirmed` → `cancelled` (mirroring `app.shipment_orders`' own three-state lifecycle exactly); `confirmed` is the exact state Prompt 236 §9 means by "confirmed outbound demand contract."
2. **Owner scope is tenant + customer-owner + warehouse company-org-unit**, mirroring `ATW-012`'s own header note 1. `owner_account_id` is a mandatory live FK, inherited from `app.shipment_orders.shipper_account_id` when prepared from a source shipment, or supplied directly for a manual order.
3. **`source_type` is a closed CHECK enum (`shipment_order`/`manual`), deliberately excluding `import`** — the bounded `app.add_wms_outbound_order_lines` bulk RPC already covers that need, mirroring `ATW-012`'s own precedent exactly.
4. **Sourcing from a shipment order requires the shipment order's own `status = 'confirmed'` at prepare time** — stricter than `ATW-012`'s own "not cancelled," since a draft shipment's own aggregate basis figures aren't yet authoritative. Duplicate-source prevention via the identical real partial unique index shape `ATW-012` established.
5. A bounded, disclosed alternative to the full Configurable Numbering Engine (`PLT-125`), mirroring `app.next_wms_inbound_order_number` (`ATW-012`) exactly.
6. **Line items snapshot `lot_controlled`/`serial_controlled`/`expiry_controlled` from `app.item_masters` at add-time**, the identical governed-snapshot precedent `ATW-012` established — Picking (the next checkpoint) needs these snapshots to know which lines require lot/serial/expiry-aware allocation without joining live back to `app.item_masters`. Lines carry only `requested_quantity`, never an allocated/reserved/picked quantity column — allocation is explicitly Picking's own job.
7. **`app.confirm_wms_outbound_order` re-validates full readiness rather than trusting a stale prior check**, and additionally re-checks a shipment-order-sourced order's own source shipment is still `confirmed` at confirm time, not merely at prepare time — a genuinely new validation `ATW-012` itself does not need, since an inbound order has no analogous upstream source-order state to re-check.
8. **`app.cancel_wms_outbound_order` deliberately carries no downstream-progress guard** — for a different reason than `ATW-012`'s own identical-looking omission: Picking does not exist as a live capability yet at this checkpoint, so there is genuinely nothing that could reference a confirmed outbound order. `ATW-017` (Picking) is explicitly named as the future obligated widener, mirroring how `ATW-013` widened `ATW-012`'s own cancel RPC once WMS Receiving went live.
9. **Two known-bug-class fixes applied proactively, beyond what `ATW-012`'s own (earlier, not-yet-hardened) migration literally does**: (a) create-once INSERTs wrap in nested `begin/exception unique_violation` recovery, which `ATW-012` itself does not do; (b) `app.add_wms_outbound_order_line` locks the header row before computing the next line number and before its own status check, closing the exact cross-row-aggregate race class `ATW-012`'s own equivalent function leaves open.
10. **Owner-account read scoping (the sixth known bug class, from `ATW-016`'s own review) is applied to every read RPC** — all four read RPCs call `app.actor_can_view_owner_scoped_row` (`ATW-016`, reused directly, never re-derived) in addition to tenant-wide RBAC and warehouse-record-scope checks; RLS `SELECT` policies on both new tables carry the identical predicate. Every `app.can_access_record` call additionally passes the order's own `owner_account_id` as `p_customer_account_ref` — the exact mechanism `app.get_lot_trace`/`app.get_serial_trace` (`ATW-016`) established — so a `customer_user`-layer actor with no `org_unit_id` membership can still pass the warehouse-record-scope check on their own owner's row; `ATW-012`'s own calls pass `null` here (predating owner-scoping entirely), a gap this migration does not repeat.
11. No UI route, no REST/GraphQL surface, no dock/load/ship-confirm — matches every prior WMS checkpoint's own disclosed "read surface first" precedent.
12. Per `ERR-2026-004`: the migration carries its own explicit revoke-all-from-public statement before its final grants.

## 4. Implementation

### 4.1 Schema — `supabase/migrations/20260730230000_create_advanced_tms_wms_outbound_order.sql`

Two new tables (`app.wms_outbound_orders`, `app.wms_outbound_order_lines`) plus a numbering-counter table, and RPCs covering prepare-from-shipment/create-manual, add/update/remove line (single + bounded bulk), a readiness projection, confirm, cancel, and bounded reads. No direct write to `app.inventory_movements`/`app.inventory_balances`/`app.item_masters`/`app.shipment_orders` anywhere.

### 4.2 Service layer

`server/contracts/wms-outbound-order/wms-outbound-order.ts`, `server/queries/wms-outbound-order.ts`, `server/mutations/wms-outbound-order.ts` (plus their `.test.ts` files), mirroring the established `wms-inbound`/`lot-batch-serial` pattern exactly. No UI route.

### 4.3 Defect found by adversarial review, fixed

**[LOW, correctness-concurrency, inherited pattern not a new regression]** `app.update_wms_outbound_order_line`/`app.remove_wms_outbound_order_line` checked the header's `status <> 'draft'` business-state condition *before* the `OPS:Edit` RBAC check and `app.can_access_record` warehouse-scope check — an ordering inconsistency relative to every other mutation in the same file, inherited verbatim from `ATW-012`'s own `app.update_wms_inbound_order_line` (confirmed by diffing the two files). This let an unauthorized actor (including one from a completely different tenant) learn whether a given order was in draft state via which error message came back (`outbound_not_draft` vs. `insufficient_authority`), without ever passing authorization — a narrow, UUID-gated single-bit state-disclosure oracle, not a full authorization bypass (the actual `UPDATE`/`DELETE` still requires passing RBAC). **Fix:** reordered both functions so the RBAC and record-scope checks now run immediately after the header row is locked and loaded, with the draft-status check strictly after both — matching `app.add_wms_outbound_order_line`'s own already-correct ordering and this checkpoint's own disclosed design lesson 9(a)/(b). The header row's own `FOR UPDATE` lock was deliberately left in its original position (locking order doesn't affect information-disclosure timing, and reordering the lock itself would risk a different deadlock/race profile — only the check/raise order changed). The other two independent review lenses (spec-compliance-and-scope-boundary, security-authority-owner-scoping) returned no findings after genuinely trying, including a live cross-owner isolation proof (two owner accounts under one tenant, a `customer_user`-layer actor scoped to one owner, confirmed correct read scoping across all four read RPCs) and confirmation that no allocation/reservation logic and no stage/load/ship-confirm logic leaked into this checkpoint's own scope.

### 4.4 Tests

`scripts/db-tests/advanced-tms-wms-outbound-order.sql` — two tenants, two owner accounts under tenant1 plus a `customer_user`-layer actor scoped to one owner, authority gating, idempotent replay with RBAC-before-short-circuit regression assertions, real duplicate-source-shipment-order rejection via the partial unique index (including a raw-INSERT probe bypassing the RPC layer entirely), add/update/remove lines, bulk-add-lines, confirm (including the new source-shipment-still-confirmed re-check), cancel, cross-owner isolation on every read RPC, bounded/filtered reads, cross-tenant isolation, schema-privilege defense in depth.

`server/contracts|queries|mutations/wms-outbound-order.test.ts` — net new `node:test` cases (2686 total after this checkpoint, up from 2661 before it).

## 5. Independent verification (this checkpoint's own orchestrating session, not any agent's own self-report)

Before writing this document: read the actual migration file directly and confirmed, by line, that `app.update_wms_outbound_order_line`/`app.remove_wms_outbound_order_line` now run `app.evaluate_permission`/`app.can_access_record` before the `outbound_not_draft` check (lines 626–636 and 691–700); confirmed every mutation/read RPC passes the order's own `owner_account_id::text` as `p_customer_account_ref` into `app.can_access_record`; confirmed `app.actor_can_view_owner_scoped_row` is genuinely reused (not re-derived) across all four read RPCs and both RLS policies. Independently re-ran `db:test`, `typecheck`, `lint`, `pnpm test`, all six governance gates, and `next build` from a clean shell rather than trusting any agent's own reported numbers; independently confirmed the exact migration count (121), db-test file count (122), and route count (90) by direct enumeration. All independently confirmed green and matching every agent's own claims.

`typecheck` (0 errors); `lint` (0 errors, 85 pre-existing warnings, unchanged); `node:test` **2686/2686**; `db:test` PASS across **121 migrations/122 db-test files** (1 new migration, 1 new db-test file, zero regression); `docs:check`/`security:check`/`data-classification:check` (25-entry threat register valid)/`standards:check`/`git:check-paths` all pass; `next build` PASS (**90 routes, unchanged**).

## 6. Known issue narrowed

`docs/runtime/KNOWN_ISSUES.md`'s `ISS-2026-011` Part 2 is narrowed this checkpoint: the "confirmed outbound demand contract" Prompt 236 §9 requires now genuinely exists (`app.wms_outbound_orders`/`app.wms_outbound_order_lines`, `confirmed` status) — Picking (`ATW-017`) is unblocked and can proceed. The entry is not fully `RESOLVED` until Prompt 238's own remaining scope (stage/load/ship-confirm) is actually built against Picking/Packing's real output — see `ISS-2026-011`'s own updated text.

## 7. Residual scope, explicitly not this checkpoint's own

- Allocation/reservation against inventory — Picking's (`ATW-017`) own job, the very next checkpoint.
- Staging/dock/load/custody, ship-confirm inventory movements, billing-event eligibility — the real Prompt 238/`ATW-019` checkpoint's own later job.
- Cancel-time downstream-progress guard — deferred, design note 8, `ATW-017` is the obligated future widener.
- No UI route, no REST/GraphQL surface — matches repository-wide precedent.

## 8. Rollback/recovery note

`git revert` this checkpoint's own commit — one new, purely additive migration (121st; no existing table/function/view modified), no destructive rollback needed.

## 9. Status

`VERIFIED`. Inserted task, no source prompt number, resolving `ISS-2026-011` Part 2 ahead of Prompt 236. Proceeding directly to `ATW-017` (Prompt 236, WMS Picking) next, per the operator's own standing authorization to complete Prompts 231–238.
