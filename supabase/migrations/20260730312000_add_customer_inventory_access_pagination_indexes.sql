-- Follow-up to CG-S10-ATW-023 (Prompt 242, "Customer Inventory Access Contract",
-- supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql).
-- Adversarial spec-compliance review found Prompt 242 section 17 ("Index tenant/
-- customer-account/warehouse/owner/item/status/date and grant validity... Prove
-- target-volume plans") was not satisfied: the new capability introduces four new
-- keyset-pagination query shapes (order by updated_at desc, id desc on app.
-- inventory_balances/app.lot_identities/app.serial_identities/app.wms_outbound_
-- orders; order by occurred_at desc, id desc on the app.inventory_movement_lines
-- <-> app.inventory_movements join) that no existing index (each table's own
-- already-applied indexes only cover (tenant_id, item_master_id[, status]) and
-- (tenant_id, owner_account_id)) supports -- confirmed by direct inspection of every
-- `create index` statement across supabase/migrations/20260730190000_create_
-- advanced_tms_inventory_ledger.sql, 20260730220000_create_advanced_tms_lot_batch_
-- serial_expiry.sql, and 20260730230000_create_advanced_tms_wms_outbound_order.sql,
-- none of which was touched (AGENTS.md: never edit an applied migration).
--
-- Every index below is purely additive (no existing index dropped/altered) and
-- exists solely to support this migration's own new cursor-pagination order by
-- clause efficiently at real volume -- avoiding a full sort of the tenant's entire
-- balance/identity/order set on every page. (tenant_id, updated_at desc, id desc)
-- matches this repository's own established keyset-pagination index shape (the
-- same convention app.audit_logs' own indexing, PLT-116, already uses per its own
-- "keyset mandatory" comment). app.inventory_movement_lines has no updated_at/
-- created_at column that means anything for this query (design note 7 in the
-- capability migration -- app.inventory_movements.occurred_at is the real
-- chronological anchor, on the JOINED table); the owner-scope filter index added for
-- it below is the highest-value covering improvement available without restructuring
-- the join itself, and mirrors app.inventory_balances_tenant_owner_idx's own
-- established (tenant_id, owner_account_id) shape for the identical scope dimension.

create index inventory_balances_tenant_updated_id_idx on app.inventory_balances (tenant_id, updated_at desc, id desc);
create index lot_identities_tenant_updated_id_idx on app.lot_identities (tenant_id, updated_at desc, id desc);
create index serial_identities_tenant_updated_id_idx on app.serial_identities (tenant_id, updated_at desc, id desc);
create index wms_outbound_orders_tenant_updated_id_idx on app.wms_outbound_orders (tenant_id, updated_at desc, id desc);
create index inventory_movement_lines_tenant_owner_idx on app.inventory_movement_lines (tenant_id, owner_account_id);
