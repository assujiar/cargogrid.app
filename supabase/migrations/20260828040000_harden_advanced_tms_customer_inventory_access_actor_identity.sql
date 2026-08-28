-- Track B Batch 4, ISS-2026-117 (docs/runtime/KNOWN_ISSUES.md): every actor-taking
-- function in ATW-023's customer-inventory-access migration (supabase/migrations/
-- 20260730310000_create_advanced_tms_customer_inventory_access.sql) takes its own
-- p_actor_auth_user_id parameter and derives scope directly from it via app.resolve_
-- customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id) / app.evaluate_
-- customer_inventory_access(p_actor_auth_user_id, ...), but never calls app.assert_
-- actor_is_session_identity(p_actor_auth_user_id) first -- confirmed still true by
-- direct read: `grep -c assert_actor_is_session_identity` against the whole file
-- returns zero, and 20260730310000 is never CREATE OR REPLACE'd by any later
-- migration (grep-confirmed across supabase/migrations/*.sql -- the only later file
-- mentioning any of these function names, 20260826000000_create_public_api_data_
-- wrappers.sql, defines unrelated public.* wrappers for two different CPL-300
-- functions, app.accept_customer_portal_invite/app.set_customer_portal_account_
-- membership_status, not any function in this migration). This migration file
-- (20260730310000) predates app.assert_actor_is_session_identity's own introduction
-- (20260730440000_harden_actor_identity_session_crosscheck.sql, ATW-031, a LATER
-- migration) and was never retrofitted -- the gap is real, live, and unchanged from
-- the issue entry's own description.
--
-- Live exposure: a genuinely authenticated session with zero relationship to a given
-- customer identity could pass that identity's own auth_user_id as p_actor_auth_
-- user_id to any of these RPCs directly and read that identity's own inventory-
-- balance/lot/serial/outbound-order/movement-lineage/export/warehouse-eligibility
-- rows -- the identical IDOR shape CPL-300's own Tier C review already found and
-- fixed on four different functions (docs/build-log/phase-08/CPL-300.md §14 Finding
-- 1), and the identical fix app.list_customer_tickets/app.list_customer_ticket_
-- messages (HRT-287, 20260731080000_extend_ticketing_customer_channel.sql) and every
-- CPL-300 RPC already carry.
--
-- Fix: CREATE OR REPLACE FUNCTION against every function in this migration file that
-- takes a p_actor_auth_user_id/p_auth_user_id parameter representing the CALLING
-- identity (not an internal helper composed with an already-checked identity),
-- adding `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as the
-- first statement -- the issue entry's own recommended fix, applied to the full
-- migration file rather than only the two title-named functions, since the entry's
-- own text discloses the gap as repository-wide across this one file, not narrowly
-- scoped to a pair, and fixing the remaining eight costs nothing extra in the same
-- migration (identical signatures, zero TS-layer ripple -- every existing caller,
-- including this checkpoint's own app.get_customer_portal_dashboard_summary
-- composition, already passes a same-session identity).
--
-- Ten functions fixed (every actor-taking, externally-reachable RPC in the file):
--   1. app.get_customer_inventory_balance            (20260730310000:361)
--   2. app.list_customer_inventory_balances           (20260730310000:412)
--   3. app.list_customer_lot_identities                (20260730310000:487)
--   4. app.list_customer_serial_identities              (20260730310000:555)
--   5. app.get_customer_outbound_order                 (20260730310000:625)
--   6. app.list_customer_outbound_order_lines           (20260730310000:672)
--   7. app.list_customer_outbound_orders                (20260730310000:716)
--   8. app.list_customer_inventory_movement_summary      (20260730310000:776)
--   9. app.export_customer_inventory_snapshot            (20260730310000:838)
--  10. app.list_customer_warehouse_eligibility            (20260730310000:913)
--
-- Deliberately NOT touched: app.customer_warehouse_eligibility_active/app.resolve_
-- customer_owner_account_scope/app.evaluate_customer_inventory_access (internal
-- helper primitives always composed by the ten functions above with an identity that
-- IS, after this migration, already asserted before either is ever called -- adding
-- the same check inside them would be redundant, not a second layer of defense,
-- since they are `language sql`, not `plpgsql`, and take no independent caller-
-- identity decision of their own); app.record_customer_inventory_access_denial (a
-- pure audit-write RPC called by the TS service layer only AFTER one of the ten RPCs
-- above has already thrown, using an actor id that call has, after this migration,
-- already had asserted -- a forged actor here could only misattribute an audit row
-- about a denial that RPC itself never disclosed anything from, not read any other
-- identity's data).
--
-- Every other line of every function below is byte-identical to its own already-
-- applied body in 20260730310000 -- no other predicate, column, ordering, side
-- effect, or anti-enumeration shape is touched, and no already-applied migration file
-- is edited (mirrors this repository's own established harden_*.sql pattern, e.g.
-- 20260801160000_harden_customer_portal_ticket_link_invoice_status_gate.sql and
-- 20260827130000_harden_tenant_disclosure_representative_extension_batch2.sql). No
-- new GRANT/REVOKE statement is needed: every function below is CREATE OR REPLACE on
-- an already-existing, identical signature -- PostgreSQL preserves the existing ACL
-- across a replace.
--
-- Regression coverage: a live forged-actor regression assertion is added to
-- scripts/db-tests/advanced-tms-customer-inventory-access.sql for each of the ten
-- functions, mirroring the forged-actor assertion shape scripts/db-tests/ticketing-
-- customer-channel.sql already establishes for app.list_customer_tickets.

-- ---------------------------------------------------------------------------
-- 1/10. app.get_customer_inventory_balance
-- ---------------------------------------------------------------------------

create or replace function app.get_customer_inventory_balance(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_balance_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_balance app.inventory_balances;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_balance from app.inventory_balances b where b.id = p_balance_id and b.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_inventory_access(p_actor_auth_user_id, p_tenant_id, v_balance.warehouse_id, v_balance.owner_account_id) then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  return query
  select v_balance.id, v_balance.warehouse_id, v_balance.owner_account_id, v_balance.item_master_id, v_balance.location_id,
    v_balance.lot_number, v_balance.serial_number, v_balance.status, v_balance.on_hand, v_balance.reserved, v_balance.held,
    v_balance.available, v_balance.record_version, v_balance.updated_at;
end;
$$;

comment on function app.get_customer_inventory_balance is
  'ATW-242: raises the identical record_not_found (errcode no_data_found) whether p_balance_id genuinely does not exist, belongs to a different tenant, or exists but fails app.evaluate_customer_inventory_access -- design note 5. Not self-audited on the denial branch -- an audit insert cannot survive the subsequent RAISE within the same transaction (design note 9); this stays a pure, stable read. The TS service layer durably records the denial via a separate app.record_customer_inventory_access_denial call in a new transaction after catching this RPC''s own error (design note 9). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first, closing a repository-wide gap this migration file predated (ATW-031 postdates it) -- mirrors CPL-300/app.list_customer_tickets.';

-- ---------------------------------------------------------------------------
-- 2/10. app.list_customer_inventory_balances
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_inventory_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- A cursor is a (timestamp, id) PAIR (design note 7) -- p_cursor_id supplied alone
  -- would otherwise silently filter out every row (a non-null-vs-null row comparison
  -- evaluates to unknown, which WHERE treats as false), returning an empty page
  -- instead of surfacing the caller's own malformed-cursor bug. Fails loud instead.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
    and (p_cursor_id is null or (b.updated_at, b.id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_inventory_balances is
  'ATW-242: bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET (design note 7). Excludes all-zero (on_hand=reserved=held=0) rows, mirroring app.list_inventory_balances (ATW-015). A caller with an empty resolved owner scope (design decision 4) gets zero rows, never an error. ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first, closing the repository-wide gap this issue entry named this function under.';

-- ---------------------------------------------------------------------------
-- 3/10. app.list_customer_lot_identities
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_lot_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  lot_number text,
  manufacture_date date,
  expiry_date date,
  status text,
  hold_reason text,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select l.id, l.owner_account_id, l.item_master_id, l.lot_number, l.manufacture_date, l.expiry_date, l.status,
    l.hold_reason, l.record_version, l.updated_at
  from app.lot_identities l
  where l.tenant_id = p_tenant_id
    and l.owner_account_id = any(v_scope)
    and (p_owner_account_id is null or l.owner_account_id = p_owner_account_id)
    and (p_item_master_id is null or l.item_master_id = p_item_master_id)
    and (p_status_filter is null or l.status = p_status_filter)
    and exists (
      select 1 from app.inventory_balances b
      where b.tenant_id = l.tenant_id
        and b.owner_account_id = l.owner_account_id
        and b.item_master_id = l.item_master_id
        and b.lot_number = l.lot_number
        and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
        and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, l.owner_account_id)
    )
    and (p_cursor_id is null or (l.updated_at, l.id) < (p_cursor_updated_at, p_cursor_id))
  order by l.updated_at desc, l.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_lot_identities is
  'ATW-242: owner+warehouse-eligibility-scoped lot list. Columns exclude parent_lot_id/source_type/source_id/created_by (design note 10) and include hold_reason (a customer legitimately needs to know why their own lot is held, Prompt 242 field-policy guidance). Bounded, keyset-paginated on (updated_at desc, id desc). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first.';

-- ---------------------------------------------------------------------------
-- 4/10. app.list_customer_serial_identities
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_serial_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  serial_number text,
  lot_number text,
  manufacture_date date,
  expiry_date date,
  status text,
  hold_reason text,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select s.id, s.owner_account_id, s.item_master_id, s.serial_number, s.lot_number, s.manufacture_date, s.expiry_date,
    s.status, s.hold_reason, s.record_version, s.updated_at
  from app.serial_identities s
  where s.tenant_id = p_tenant_id
    and s.owner_account_id = any(v_scope)
    and (p_owner_account_id is null or s.owner_account_id = p_owner_account_id)
    and (p_item_master_id is null or s.item_master_id = p_item_master_id)
    and (p_status_filter is null or s.status = p_status_filter)
    and exists (
      select 1 from app.inventory_balances b
      where b.tenant_id = s.tenant_id
        and b.owner_account_id = s.owner_account_id
        and b.item_master_id = s.item_master_id
        and b.serial_number = s.serial_number
        and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
        and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, s.owner_account_id)
    )
    and (p_cursor_id is null or (s.updated_at, s.id) < (p_cursor_updated_at, p_cursor_id))
  order by s.updated_at desc, s.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_serial_identities is
  'ATW-242: mirrors app.list_customer_lot_identities exactly (design note above) for app.serial_identities. Excludes source_type/source_id/idempotency_key/created_by (design note 10). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first.';

-- ---------------------------------------------------------------------------
-- 5/10. app.get_customer_outbound_order
-- ---------------------------------------------------------------------------

create or replace function app.get_customer_outbound_order(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_outbound_order_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.evaluate_customer_inventory_access, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287). app.list_customer_outbound_order_lines
  -- (below) calls this function for its own gate and therefore inherits this check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id and o.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_inventory_access(p_actor_auth_user_id, p_tenant_id, v_order.warehouse_id, v_order.owner_account_id) then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  return query
  select v_order.id, v_order.warehouse_id, v_order.owner_account_id, v_order.outbound_number, v_order.source_type,
    v_order.requested_ship_date, v_order.status, v_order.cancelled_reason, v_order.record_version, v_order.created_at, v_order.updated_at;
end;
$$;

comment on function app.get_customer_outbound_order is
  'ATW-242: columns exclude source_shipment_order_id/source_reason/idempotency_key/created_by (design note 10 -- internal correlation ids and an operational free-text note this RPC surface gives no way to resolve/act on). Anti-enumerating not-found, not self-audited on the denial branch, mirrors app.get_customer_inventory_balance exactly (design note 9) -- the TS service layer durably records the denial separately. ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first -- app.list_customer_outbound_order_lines inherits this via its own composed call into this function.';

-- ---------------------------------------------------------------------------
-- 6/10. app.list_customer_outbound_order_lines
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_outbound_order_lines(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  outbound_order_id uuid,
  line_number integer,
  item_master_id uuid,
  requested_uom_code text,
  requested_quantity numeric,
  lot_controlled boolean,
  serial_controlled boolean,
  expiry_controlled boolean,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- explicitly here too (not only via the composed app.get_customer_outbound_order
  -- call below), for the same reason every other actor-taking RPC in this migration
  -- now does -- fail fast and identically regardless of which function a caller
  -- reaches first.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  -- Re-derives the gate (and its own identically-shaped anti-enumerating denial)
  -- through app.get_customer_outbound_order rather than duplicating it.
  perform app.get_customer_outbound_order(v_order.tenant_id, p_actor_auth_user_id, p_outbound_order_id);

  return query
  select l.id, l.outbound_order_id, l.line_number, l.item_master_id, l.requested_uom_code, l.requested_quantity,
    l.lot_controlled, l.serial_controlled, l.expiry_controlled, l.record_version, l.updated_at
  from app.wms_outbound_order_lines l
  where l.outbound_order_id = p_outbound_order_id
  order by l.line_number;
end;
$$;

comment on function app.list_customer_outbound_order_lines is
  'ATW-242: columns exclude notes (free-text, potentially staff-internal -- design note 10). Reuses app.get_customer_outbound_order for its own authority/scope gate rather than duplicating it (mirrors ATW-016A''s own app.list_wms_outbound_order_lines). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) directly as well as inheriting it from the composed app.get_customer_outbound_order call.';

-- ---------------------------------------------------------------------------
-- 7/10. app.list_customer_outbound_orders
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_outbound_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select o.id, o.warehouse_id, o.owner_account_id, o.outbound_number, o.source_type, o.requested_ship_date, o.status,
    o.cancelled_reason, o.record_version, o.created_at, o.updated_at
  from app.wms_outbound_orders o
  where o.tenant_id = p_tenant_id
    and (p_warehouse_id is null or o.warehouse_id = p_warehouse_id)
    and (p_status_filter is null or o.status = p_status_filter)
    and o.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, o.warehouse_id, o.owner_account_id)
    and (p_cursor_id is null or (o.updated_at, o.id) < (p_cursor_updated_at, p_cursor_id))
  order by o.updated_at desc, o.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_outbound_orders is
  'ATW-242: same column projection and exclusions as app.get_customer_outbound_order. Bounded, keyset-paginated on (updated_at desc, id desc). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first, closing the repository-wide gap this issue entry named this function under.';

-- ---------------------------------------------------------------------------
-- 8/10. app.list_customer_inventory_movement_summary
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_inventory_movement_summary(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  movement_id uuid,
  movement_type text,
  occurred_at timestamptz,
  item_master_id uuid,
  warehouse_id uuid,
  signed_quantity numeric,
  lot_number text,
  serial_number text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_occurred_at is null then
    raise exception 'invalid_cursor: p_cursor_occurred_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.id, ml.movement_id, m.movement_type, m.occurred_at, ml.item_master_id, ml.warehouse_id, ml.signed_quantity,
    ml.lot_number, ml.serial_number
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  where ml.tenant_id = p_tenant_id
    and (p_warehouse_id is null or ml.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or ml.item_master_id = p_item_master_id)
    and ml.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, ml.warehouse_id, ml.owner_account_id)
    and (p_cursor_id is null or (m.occurred_at, ml.id) < (p_cursor_occurred_at, p_cursor_id))
  order by m.occurred_at desc, ml.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_inventory_movement_summary is
  'ATW-242: movement_type/occurred_at/item_master_id/warehouse_id/signed_quantity/lot_number/serial_number only -- no internal source_type/posted_by (design note 10, Prompt 242''s own required column list verbatim). Bounded, keyset-paginated on (occurred_at desc, id desc) -- occurred_at, not updated_at/created_at, is the real chronological anchor of this joined read (design note 7). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first.';

-- ---------------------------------------------------------------------------
-- 9/10. app.export_customer_inventory_snapshot
-- ---------------------------------------------------------------------------

create or replace function app.export_customer_inventory_snapshot(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_limit integer default 500,
  p_actor_label text default null
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
  v_matched_count integer;
  v_result_count integer;
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 500), 1), 1000);

  select count(*) into v_matched_count
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id);
  v_result_count := least(v_matched_count, v_limit);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'export_customer_inventory_snapshot',
    'app.inventory_balances', null, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'item_master_id', p_item_master_id, 'limit', v_limit, 'result_count', v_result_count)
  );

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.export_customer_inventory_snapshot is
  'ATW-242: p_limit default 500, hard-capped 1000 (larger than the plain list RPC''s own 200 cap, still bounded -- design note "export" above). Audits every call (actor, requested scope jsonb, result_count) regardless of outcome -- never the row payload itself (design note 9). No cursor -- a single bounded snapshot, not a list. ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first, before either the scope resolution or the audit write, so a forged actor is rejected outright rather than audited as if it were a genuine export.';

-- ---------------------------------------------------------------------------
-- 10/10. app.list_customer_warehouse_eligibility
-- ---------------------------------------------------------------------------

create or replace function app.list_customer_warehouse_eligibility(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  warehouse_id uuid,
  customer_account_id uuid,
  status text,
  granted_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  -- ISS-2026-117 Track B Batch 4 fix: reject a forged/unrelated p_actor_auth_user_id
  -- before it ever reaches app.resolve_customer_owner_account_scope, mirroring CPL-300
  -- and app.list_customer_tickets (HRT-287).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);

  return query
  select wce.id, wce.warehouse_id, wce.customer_account_id, wce.status, wce.granted_at, wce.revoked_at, wce.revoked_reason, wce.record_version
  from app.warehouse_customer_eligibility wce
  where wce.tenant_id = p_tenant_id
    and wce.customer_account_id = any(v_scope)
  order by wce.granted_at desc;
end;
$$;

comment on function app.list_customer_warehouse_eligibility is
  'ATW-242: no OPS RBAC gate -- purely resolved-owner-scope, matching this being the one contract in the repository with a genuine customer_user-only authorization path. Columns exclude granted_by (a staff label -- design note 10) and include revoked_reason (a customer legitimately needs to know why a warehouse eligibility grant was revoked). ISS-2026-117 Track B Batch 4 fix: now calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first.';
