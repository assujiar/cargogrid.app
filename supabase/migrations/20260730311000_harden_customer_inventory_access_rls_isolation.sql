-- Hardening follow-up to CG-S10-ATW-023 (Prompt 242, "Customer Inventory Access
-- Contract", supabase/migrations/20260730310000_create_advanced_tms_customer_
-- inventory_access.sql). A live-reproduced adversarial security review found that
-- ATW-023's own design note 6 disclosure ("the ONLY sanctioned read path for a
-- customer-portal actor is through the SECURITY DEFINER RPCs below") was not
-- actually true: the four pre-existing tables ATW-023 reads
-- (app.wms_outbound_orders/app.wms_outbound_order_lines, ATW-016A;
-- app.lot_identities/app.serial_identities, ATW-016) each carry a SELECT RLS policy
-- that already passes a real owner_account_id/customer_account_ref into
-- app.actor_can_view_owner_scoped_row (a mechanism ATW-016/ATW-016A built for a
-- FUTURE customer-facing capability to use, per their own design notes -- this is
-- that capability). Because ATW-023 is the first migration that ever actually GRANTS
-- a live customer_user principal (ISS-2026-010, docs/runtime/KNOWN_ISSUES.md, whose
-- own "Runtime agent / Prompt 242 owner" assignment and "blocking... the instant
-- Prompt 242 first grants a live customer_user principal" note names exactly this
-- checkpoint), that pre-existing owner-scope RLS branch stopped being latent/
-- unreachable and became a real, live, exploitable path the moment this task's own
-- db-test fixture called app.grant_principal_membership(..., 'customer_user', ...):
-- a genuine Supabase `authenticated` client (the standard way any real customer-
-- portal frontend talks to Postgres) can run `select * from app.wms_outbound_orders`
-- directly and read every column RLS's owner-scope check admits -- including fields
-- ATW-023's own RPC layer deliberately excludes as staff-internal
-- (source_reason/created_by/notes/parent_lot_id) -- and entirely bypasses ATW-023's
-- own new warehouse-eligibility gate (app.customer_warehouse_eligibility_active),
-- since no RLS policy anywhere references it. Live-reproduced: revoking a customer's
-- warehouse eligibility correctly blocks every ATW-023 RPC immediately, but a raw
-- `set role authenticated` read against these four tables kept returning the
-- now-revoked row unchanged.
--
-- Never edit an applied migration (AGENTS.md) -- ATW-016/ATW-016A's own migration
-- files are untouched; this is a new migration that narrows their already-applied
-- RLS SELECT policies via DROP POLICY/CREATE POLICY, the identical technique
-- ATW-017 (supabase/migrations/20260730240000_create_advanced_tms_wms_picking.sql
-- design note "15. Widening ATW-016A's own ... RLS SELECT policies") already used to
-- fix its own sibling instance of a related RLS defect.
--
-- Fix: a customer_user-layer actor's raw-table read access is removed entirely on
-- these four tables (never widened for anyone else -- every change below is a pure
-- AND-narrowing of an existing USING clause, so no actor who could not already read
-- a row before this migration can read one after it). This does not merely re-gate
-- on warehouse eligibility in RLS (which the original design note 6 correctly
-- rejected as "a second, independently-evolving enforcement point") -- it makes
-- design note 6's own claim actually true: a customer_user actor's ONLY read path
-- for these tables is now genuinely the SECURITY DEFINER RPCs in
-- 20260730310000_create_advanced_tms_customer_inventory_access.sql, which already
-- enforce identical owner+eligibility scope, field masking, and bounding. No staff
-- actor (tenant_admin/org_user/Supreme Admin/service_role) is affected -- none holds
-- a customer_user-layer membership, and every staff-facing read of these tables
-- already goes through its own SECURITY DEFINER RPC (app.get_wms_outbound_order,
-- app.list_lot_identities, etc.), never a raw table read, so this closes a path
-- nothing in this repository's live code currently depends on (confirmed: no
-- server/queries or server/mutations file performs a raw `.from()` select against
-- any of these four tables -- every real caller already uses an RPC).
--
-- Residual, explicitly out of scope here: ISS-2026-010's own broader observation --
-- that all 78 tenant-scoped RLS SELECT policies key off app.has_active_tenant_
-- membership without regard to layer -- names many more tables than these four,
-- most of which have no owner-scope branch at all and therefore already fail closed
-- for a customer_user actor (no org_unit_id, so app.can_access_record's own
-- org-unit branch never matches, exactly as this migration's companion db-test
-- already proves for app.inventory_balances/app.inventory_movements/app.inventory_
-- movement_lines). Auditing all 78 policies for the same owner-scope-branch pattern
-- fixed here is a repository-wide task beyond this checkpoint's own file scope; this
-- migration closes only the concrete, live-reproduced instance directly implicated
-- by ATW-023's own new capability (the four tables it itself reads).

-- 1. Shared "is this auth identity currently an active customer_user-layer principal
-- in this tenant" predicate -- security definer (app.principal_memberships grants
-- SELECT to service_role only; every RLS-called helper needs to bypass that the same
-- way app.resolve_customer_owner_account_scope already does).
create function app.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.principal_memberships pm
    where pm.auth_user_id = p_auth_user_id
      and pm.tenant_id = p_tenant_id
      and pm.layer = 'customer_user'
      and pm.status = 'active'
  );
$$;

comment on function app.actor_holds_customer_user_layer is
  'ATW-023 hardening: true only if this auth identity holds an ACTIVE customer_user-layer app.principal_memberships row in this tenant. Used exclusively to NARROW the four pre-existing RLS SELECT policies below (never to widen anything) -- a customer-portal actor''s only sanctioned read path for these tables is the SECURITY DEFINER RPC layer in 20260730310000_create_advanced_tms_customer_inventory_access.sql, which already enforces identical owner+warehouse-eligibility scope and field masking.';

-- 2. app.wms_outbound_orders / app.wms_outbound_order_lines (ATW-016A, most recently
-- superseded by ATW-017's own DROP POLICY/CREATE POLICY widening in
-- 20260730240000_create_advanced_tms_wms_picking.sql) -- add the customer_user-layer
-- denial on top of the existing, unchanged staff-facing predicate.
drop policy if exists wms_outbound_orders_select_scoped on app.wms_outbound_orders;
create policy wms_outbound_orders_select_scoped on app.wms_outbound_orders
  for select to authenticated
  using (
    not app.actor_holds_customer_user_layer(wms_outbound_orders.tenant_id)
    and app.wms_pick_record_scope_ok((select auth.uid()), wms_outbound_orders.warehouse_id, wms_outbound_orders.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_outbound_orders.tenant_id, wms_outbound_orders.owner_account_id)
  );

drop policy if exists wms_outbound_order_lines_select_scoped on app.wms_outbound_order_lines;
create policy wms_outbound_order_lines_select_scoped on app.wms_outbound_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_orders o
      where o.id = wms_outbound_order_lines.outbound_order_id
        and not app.actor_holds_customer_user_layer(o.tenant_id)
        and app.wms_pick_record_scope_ok((select auth.uid()), o.warehouse_id, o.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), o.tenant_id, o.owner_account_id)
    )
  );

-- 3. app.lot_identities / app.serial_identities (ATW-016, never superseded before
-- now) -- same narrowing.
drop policy if exists lot_identities_select_scoped on app.lot_identities;
create policy lot_identities_select_scoped on app.lot_identities
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and not app.actor_holds_customer_user_layer(tenant_id)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), tenant_id, owner_account_id)
  );

drop policy if exists serial_identities_select_scoped on app.serial_identities;
create policy serial_identities_select_scoped on app.serial_identities
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and not app.actor_holds_customer_user_layer(tenant_id)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), tenant_id, owner_account_id)
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant. Design note: this does NOT
-- undo any already-applied migration's own EXECUTE grant on wms_outbound_orders_
-- select_scoped's sibling functions (app.wms_pick_record_scope_ok, app.actor_can_
-- view_owner_scoped_row, app.has_active_tenant_membership, app.is_supreme_admin) --
-- grants are tied to each function's own OID, unaffected by this migration, which
-- creates exactly one new function.
revoke execute on all functions in schema app from public;

grant execute on function app.actor_holds_customer_user_layer(uuid, uuid) to authenticated, service_role;
