-- CG-AUDIT-2026-09-02 F5 remediation: the two highest-traffic operational screens
-- (server/queries/shipment-order.ts#listShipmentOrders, server/queries/basic-dispatch.ts#
-- listDispatchReadyQueue) each run `.select("*", { count: "exact" }).range(from, to)` with
-- no supporting index for their own ORDER BY column -- app.shipment_orders carries 9
-- indexes, none leading with `created_at` (only `(tenant_id, updated_at desc, id desc)`,
-- added by 20260801050000 for a different query), and none at all for `planned_pickup_at`.
-- Both the exact-count pass and the data pass therefore force a full scan-and-sort of
-- every row matching `tenant_id` on every single page load.
--
-- The dispatch board compounds this: `app.dispatch_ready_queue` is
-- `select so.*, r.is_ready, r.blockers from app.shipment_orders so cross join lateral
-- app.evaluate_dispatch_readiness(so.id) as r where so.status = 'assigned' and ...` -- a
-- ~40-line SECURITY DEFINER function invoked once per matching row, on BOTH the exact-
-- count pass (which PostgREST/Postgres cannot prove is safe to skip just because the
-- lateral output columns aren't referenced by `count(*)`) and the data pass. For a tenant
-- with N assigned shipments, a single page load previously ran the readiness function
-- N + pageSize times; this fix reduces that to exactly pageSize.
--
-- Two independent fixes, per the audit's own two-part framing ("sorting on a column
-- neither table indexes" + the LATERAL join compounding it):
--
-- 1. Two new covering indexes, additive, no other change to app.shipment_orders or its
--    RLS -- mirroring 20260801050000's own `shipment_orders_tenant_updated_id_idx` shape
--    exactly (design decision 6 there: "additive covering indexes... no other change").
--
-- 2. server/queries/basic-dispatch.ts#listDispatchReadyQueue is restructured (this
--    migration's own SQL side needs no new function for it) to compute its exact count
--    as a separate, plain HEAD request against app.shipment_orders directly -- filtered
--    identically (`tenant_id` + `status = 'assigned'`) -- rather than piggy-backing
--    `count: "exact"` onto the `dispatch_ready_queue` view read. This is provably
--    equivalent, not an approximation: app.shipment_orders' own RLS policy
--    (`shipment_orders_select_scoped`, 20260727100000) is
--    `using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--    app.lead_record_scope_org_unit_ids(org_unit_id), null))` -- the IDENTICAL predicate
--    `app.dispatch_ready_queue`'s own WHERE clause uses, and neither the view's WHERE
--    clause nor the row count depends on `r.is_ready`/`r.blockers` (the lateral join's own
--    only output) at all, so a plain base-table count can never disagree with a count
--    taken through the view. `listShipmentOrders` keeps its existing single `count: exact`
--    query as-is (the base-table-only sort/count-exact combination has no LATERAL join to
--    make asymmetric here) -- only the missing index was the gap for that screen.
--
-- `server/queries/shipment-order.ts`/`basic-dispatch.ts` are two of ten files across the
-- codebase sharing the `count: "exact"` shape (the audit's own count) -- a wholesale
-- redesign of all ten, or of the numbered-jump-to-page `components/tables/pagination.tsx`
-- UI they all feed (which genuinely needs an exact total to render page-number links, so
-- switching away from `count: "exact"` everywhere is a real UX trade-off, not a drop-in
-- change), is out of this bounded item's scope -- this migration closes exactly the two
-- screens the audit itself named and reproduced (shipment-order list, dispatch board).

create index shipment_orders_tenant_created_at_id_idx
  on app.shipment_orders (tenant_id, created_at desc, id desc);

-- Partial, scoped to `where status = 'assigned'` -- exactly app.dispatch_ready_queue's own
-- WHERE clause, so this index covers precisely the row set the dispatch board's data pass
-- reads, nothing wider. `nulls last` matches `.order("planned_pickup_at", { ascending:
-- true, nullsFirst: false })`'s own default (Postgres ASC defaults to NULLS LAST already,
-- stated explicitly here so the index's own intent needs no cross-reference to prove it).
create index shipment_orders_tenant_assigned_pickup_id_idx
  on app.shipment_orders (tenant_id, planned_pickup_at nulls last, id)
  where status = 'assigned';
