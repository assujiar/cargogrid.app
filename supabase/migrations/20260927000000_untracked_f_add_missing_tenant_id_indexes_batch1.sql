-- CG-AUDIT-2026-09-02 UNTRACKED-F-tenant-index (batch 1 of a CODE-BIG follow-up): the
-- audit's own closing parenthetical to section F states "99 of 550 tenant-scoped
-- tables (including vehicle_current_positions, ticket_events, the route-deviation/
-- geofence tables, and the WMS order-line tables) lack any index leading on
-- tenant_id" -- "the exact index coverage that would otherwise absorb some of F4's
-- own RLS-predicate cost." Never mentioned anywhere in this backlog under any row.
--
-- Personally re-verified against the CURRENT live schema (not the audit's own
-- 2026-09-02 snapshot) before writing this migration: applied every migration to a
-- fresh disposable database and queried pg_class/pg_attribute/pg_index directly for
-- every app.* table carrying a tenant_id column with no index whose first key
-- column is tenant_id. Result: 551 tenant-scoped tables today (one more than the
-- audit's own 550, reflecting normal schema growth since 2026-09-02), and the
-- missing-index count is STILL exactly 99 -- confirming the gap is real, current,
-- and genuinely still open, not something a later migration already closed.
--
-- This is a mechanical, purely additive schema fix -- the exact same pattern
-- already merged in 20260907170000_fix_shipment_order_dispatch_double_scan_iss_f5.sql
-- (new `CREATE INDEX ... ON app.<table> (tenant_id, ...)`, zero RLS/policy change,
-- zero data-model change) -- not a product/business decision, unlike this backlog's
-- other DEFERRED_LARGE/NEEDS_PRODUCT_DECISION rows. 99 tables in one migration would
-- exceed AGENTS.md's own default bounded-task envelope (1-3 migrations, ~5-15
-- changed files), so this is deliberately scoped to a first batch: the 4 table
-- groups the audit's own closing parenthetical named explicitly by name --
-- `vehicle_current_positions`, `ticket_events`, the route-deviation/geofence
-- tables (`shipment_leg_route_deviation_states`, `shipment_leg_stop_geofence_states`),
-- and the WMS order-line tables (`wms_inbound_order_lines`, `wms_outbound_order_lines`,
-- `wms_package_lines`, `wms_shipment_issue_lines`) -- 8 tables. The remaining 91
-- tables are logged as a separate, disclosed follow-up in the backlog, not silently
-- dropped.
--
-- Plain single-column `(tenant_id)` indexes, not a composite: the audit's own
-- framing is a coverage gap ("lack ANY index leading on tenant_id"), not a specific
-- slow query with a known secondary sort/filter column -- confirmed for each of
-- these 8 tables that no existing index leads with tenant_id (grepped every
-- `create index ... on app.<table>` statement across all migrations first). A
-- composite index tuned to one particular query shape would be speculative
-- optimization ahead of a measured need, which AGENTS.md's own performance rule
-- cautions against ("read replicas/read models only after measured thresholds").
-- Every one of these 8 tables' own existing indexes (verified non-overlapping)
-- is left untouched.

create index vehicle_current_positions_tenant_idx on app.vehicle_current_positions (tenant_id);
create index ticket_events_tenant_idx on app.ticket_events (tenant_id);
create index shipment_leg_route_deviation_states_tenant_idx on app.shipment_leg_route_deviation_states (tenant_id);
create index shipment_leg_stop_geofence_states_tenant_idx on app.shipment_leg_stop_geofence_states (tenant_id);
create index wms_inbound_order_lines_tenant_idx on app.wms_inbound_order_lines (tenant_id);
create index wms_outbound_order_lines_tenant_idx on app.wms_outbound_order_lines (tenant_id);
create index wms_package_lines_tenant_idx on app.wms_package_lines (tenant_id);
create index wms_shipment_issue_lines_tenant_idx on app.wms_shipment_issue_lines (tenant_id);
