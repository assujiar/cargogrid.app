-- Closes `ISS-2026-120`. CPL-310 shipped three customer-facing OUTBOUND warehouse-order RPCs and
-- disclosed, in its own design decision 11, that the inbound half was never built anywhere --
-- "grep-confirmed: zero `app.get_customer_inbound_order`/`app.list_customer_inbound_orders`
-- anywhere in this repository, before or after this migration." Re-confirmed before writing this
-- file: still zero. This migration builds it, exactly as that entry's own "Recommended fix"
-- specified.
--
-- WHY THIS IS BUILDABLE NOW WHEN IT WAS NOT THEN, AND IT IS NOT A CHANGE OF MIND
--
--   `ISS-2026-120` was not a defect report; it was a budget disclosure. CPL-310's own charter
--   named exactly three RPCs to build, all outbound, and honestly said so rather than quietly
--   half-building a fourth surface. Nothing about the design was wrong. What has changed is only
--   that this is now its own bounded unit of work rather than an overflow of somebody else's.
--
--   The entry itself already did the hard part of the analysis and it holds up on re-reading:
--   `app.wms_inbound_orders` carries both `warehouse_id` and `owner_account_id`, which is exactly
--   the shape `app.evaluate_customer_portal_inventory_access` (CPL-309) already expects. So the
--   gate is reused unmodified, the same way CPL-310 reused it. This migration contains zero
--   `create or replace` against any pre-existing function.
--
-- WHAT IS MIRRORED, AND THE THREE PLACES INBOUND GENUINELY DIFFERS
--
--   Everything structural is CPL-310's, deliberately: `assert_actor_is_session_identity` as the
--   literal first statement of every RPC; the identical anti-enumerating `record_not_found` for
--   "does not exist", "other tenant" and "failed the gate" alike; the lines RPC delegating its
--   gate to the get RPC rather than re-deriving it, and keeping the same tenant-id-less
--   signature; the list RPC resolving owner scope ONCE per call and checking warehouse
--   eligibility per row; keyset pagination on `(updated_at desc, id desc)`, never OFFSET.
--
--   Three real differences, each forced by the inbound table's own shape rather than chosen:
--
--   1. **Four statuses, not three.** `wms_inbound_orders_status_check` admits `draft`/`scheduled`/
--      `confirmed`/`cancelled` -- `scheduled` has no outbound counterpart. Returned verbatim; the
--      customer-facing label lives at the presentation layer only, the same split CPL-310 made.
--   2. **Three source types, not two.** `shipment_order`/`manual`/`import`.
--   3. **The appointment window is projected; `requested_ship_date` has no inbound twin.**
--      `expected_date` is the closest analogue and is included. The window is included too, and
--      that is a judgement worth stating rather than burying: it is not internal operational
--      data in the sense Business rule 2 protects (no worker identity, no productivity, no task
--      queue, no other customer's location). It is when this customer's own goods are booked to
--      arrive at a warehouse this customer is eligible to see -- the single most useful fact an
--      inbound view can carry, and one the customer is normally a party to arranging. Withholding
--      it would make the surface honest but useless.
--
--   Excluded, inheriting CPL-310 design note 10 unchanged: `source_shipment_order_id`,
--   `source_reason`, `idempotency_key`, `created_by` (internal correlation ids and an operational
--   free-text note this surface gives no way to resolve or act on), and `notes` on lines.
--
-- A REAL DEFENSE-IN-DEPTH GAP FOUND WHILE BUILDING THIS, AND CLOSED HERE
--
--   `20260730311000_harden_customer_inventory_access_rls_isolation.sql` narrowed the raw-table
--   SELECT policy on seven tables so that a `customer_user`-layer actor is denied outright at the
--   RLS layer, on the reasoning that the SECURITY DEFINER RPC surface is their only sanctioned
--   read path. `app.wms_outbound_orders`/`app.wms_outbound_order_lines` are in that seven.
--   `app.wms_inbound_orders`/`app.wms_inbound_order_lines` are NOT -- they were outside that
--   migration's scope because no customer-facing inbound surface existed to harden against.
--
--   That was defensible then and is not now: this migration is the thing that creates the
--   customer-facing inbound read path, so it is the migration that owes the matching raw-table
--   denial. Shipping the RPCs without it would leave the inbound tables as the only pair in the
--   family whose customer denial rests on `app` not being exposed to PostgREST, rather than on a
--   policy that says so.
--
--   The narrowing is one conjunct -- `not app.actor_holds_customer_user_layer(tenant_id)` -- added
--   to each existing policy with the rest kept byte-identical. It cannot widen anything: it only
--   removes rows, and only for actors who should never have been reading these tables raw. Staff
--   readers are unaffected, and every RPC in the inbound capability is SECURITY DEFINER, so none
--   of them is subject to this policy at all.

-- ===========================================================================
-- 1. app.get_customer_portal_inbound_order
-- ===========================================================================

create function app.get_customer_portal_inbound_order(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_inbound_order_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  inbound_number text,
  source_type text,
  expected_date date,
  appointment_window_start timestamptz,
  appointment_window_end timestamptz,
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
  v_order app.wms_inbound_orders;
begin
  -- The literal first statement, not merely the transitive check inside the resolver/gate.
  -- CPL-300 Tier C Finding 1's lesson, applied from the first draft.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_inbound_orders o where o.id = p_inbound_order_id and o.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted inbound order exists for %', p_inbound_order_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, p_tenant_id, v_order.warehouse_id, v_order.owner_account_id) then
    raise exception 'record_not_found: no permitted inbound order exists for %', p_inbound_order_id using errcode = 'no_data_found';
  end if;

  return query
  select v_order.id, v_order.warehouse_id, v_order.owner_account_id, v_order.inbound_number, v_order.source_type,
    v_order.expected_date, v_order.appointment_window_start, v_order.appointment_window_end, v_order.status,
    v_order.cancelled_reason, v_order.record_version, v_order.created_at, v_order.updated_at;
end;
$$;

comment on function app.get_customer_portal_inbound_order is
  'ISS-2026-120: the inbound half CPL-310 disclosed as unbuilt (its own design decision 11). Mirrors app.get_customer_portal_outbound_order''s shape exactly, gated via the same unmodified app.evaluate_customer_portal_inventory_access (CPL-309''s composition of the CPL-300-widened resolver with ATW-023''s warehouse-eligibility predicate). Raises the identical anti-enumerating record_not_found (errcode no_data_found) whether the order does not exist, belongs to another tenant, or fails the gate. Excludes source_shipment_order_id/source_reason/idempotency_key/created_by, inheriting CPL-310 design note 10. Projects the appointment window deliberately: it is when this customer''s own goods are booked to arrive at a warehouse they are eligible to see, not internal operational data -- no worker identity, productivity, task queue or other customer''s location is exposed anywhere in this surface. Not self-audited on the denial branch (an audit insert cannot survive the subsequent RAISE in the same transaction, ATW-023 design note 9); the TS layer records the denial separately.';

-- ===========================================================================
-- 2. app.list_customer_portal_inbound_order_lines
-- ===========================================================================

create function app.list_customer_portal_inbound_order_lines(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  inbound_order_id uuid,
  line_number integer,
  item_master_id uuid,
  expected_uom_code text,
  expected_quantity numeric,
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
  v_order app.wms_inbound_orders;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_inbound_orders o where o.id = p_inbound_order_id;
  if not found then
    raise exception 'record_not_found: no permitted inbound order exists for %', p_inbound_order_id using errcode = 'no_data_found';
  end if;

  -- Gate and its identically-shaped denial re-derived through this migration's own get RPC,
  -- never duplicated -- so the two cannot drift apart about what a customer may see.
  perform app.get_customer_portal_inbound_order(v_order.tenant_id, p_actor_auth_user_id, p_inbound_order_id);

  return query
  select l.id, l.inbound_order_id, l.line_number, l.item_master_id, l.expected_uom_code, l.expected_quantity,
    l.lot_controlled, l.serial_controlled, l.expiry_controlled, l.record_version, l.updated_at
  from app.wms_inbound_order_lines l
  where l.inbound_order_id = p_inbound_order_id
  order by l.line_number;
end;
$$;

comment on function app.list_customer_portal_inbound_order_lines is
  'ISS-2026-120: mirrors app.list_customer_portal_outbound_order_lines exactly, including its deliberately tenant-id-less signature and its delegate-the-gate-to-the-get-RPC shape. Excludes notes (free-text, potentially staff-internal).';

-- ===========================================================================
-- 3. app.list_customer_portal_inbound_orders
-- ===========================================================================

create function app.list_customer_portal_inbound_orders(
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
  inbound_number text,
  source_type text,
  expected_date date,
  appointment_window_start timestamptz,
  appointment_window_end timestamptz,
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
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- A cursor is a (timestamp, id) PAIR. p_cursor_id alone would compare a value against null,
  -- evaluate to unknown, and silently return an empty page instead of surfacing the caller's
  -- own malformed-cursor bug. Fails loud, mirroring CPL-310/ATW-023.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select o.id, o.warehouse_id, o.owner_account_id, o.inbound_number, o.source_type, o.expected_date,
    o.appointment_window_start, o.appointment_window_end, o.status, o.cancelled_reason, o.record_version,
    o.created_at, o.updated_at
  from app.wms_inbound_orders o
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

comment on function app.list_customer_portal_inbound_orders is
  'ISS-2026-120: mirrors app.list_customer_portal_outbound_orders'' signature, projection, decomposition and pagination shape. Owner scope resolved ONCE per call via app.resolve_customer_account_scope (the CPL-300 widened resolver, the ISS-2026-117 fix); warehouse eligibility per row, since it genuinely varies per row. Bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. An empty resolved scope yields zero rows, never an error. p_status_filter accepts app.wms_inbound_orders'' four real values (draft/scheduled/confirmed/cancelled) -- note the extra `scheduled` state outbound has no counterpart for; an unrecognized value matches zero rows rather than raising, the same non-validating filter shape its outbound sibling uses.';

-- ===========================================================================
-- 4. Raw-table RLS: extend 20260730311000's customer_user-layer denial to the
-- inbound pair. One added conjunct; the rest of each policy is byte-identical
-- to what 20260730180000 established. Narrows only, never widens.
-- ===========================================================================

drop policy if exists wms_inbound_orders_select_scoped on app.wms_inbound_orders;
create policy wms_inbound_orders_select_scoped on app.wms_inbound_orders
  for select to authenticated
  using (
    not app.actor_holds_customer_user_layer(wms_inbound_orders.tenant_id)
    and exists (
      select 1 from app.warehouses w
      where w.id = wms_inbound_orders.warehouse_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

drop policy if exists wms_inbound_order_lines_select_scoped on app.wms_inbound_order_lines;
create policy wms_inbound_order_lines_select_scoped on app.wms_inbound_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_inbound_orders o
      join app.warehouses w on w.id = o.warehouse_id
      where o.id = wms_inbound_order_lines.inbound_order_id
        and not app.actor_holds_customer_user_layer(o.tenant_id)
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_portal_inbound_order(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_inbound_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- 5. public.* wrappers (RGL-394 Option 2). `app` is not exposed to PostgREST.
-- `revoke ... from anon, authenticated, service_role, public` rather than
-- `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE
-- explicitly at CREATE time, and an explicit grant survives a PUBLIC revoke
-- (ISS-2026-309).
-- ===========================================================================

create function public.get_customer_portal_inbound_order(p_tenant_id uuid, p_actor_auth_user_id uuid, p_inbound_order_id uuid)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  inbound_number text,
  source_type text,
  expected_date date,
  appointment_window_start timestamptz,
  appointment_window_end timestamptz,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.get_customer_portal_inbound_order(p_tenant_id, p_actor_auth_user_id, p_inbound_order_id);
$wrap$;

comment on function public.get_customer_portal_inbound_order(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_customer_portal_inbound_order with an identical grant set, never a reimplementation.';

revoke execute on function public.get_customer_portal_inbound_order(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_customer_portal_inbound_order(uuid, uuid, uuid) to authenticated, service_role;

create function public.list_customer_portal_inbound_order_lines(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  inbound_order_id uuid,
  line_number integer,
  item_master_id uuid,
  expected_uom_code text,
  expected_quantity numeric,
  lot_controlled boolean,
  serial_controlled boolean,
  expiry_controlled boolean,
  record_version integer,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_customer_portal_inbound_order_lines(p_inbound_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_customer_portal_inbound_order_lines(uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_customer_portal_inbound_order_lines with an identical grant set, never a reimplementation.';

revoke execute on function public.list_customer_portal_inbound_order_lines(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_portal_inbound_order_lines(uuid, uuid) to authenticated, service_role;

create function public.list_customer_portal_inbound_orders(
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
  inbound_number text,
  source_type text,
  expected_date date,
  appointment_window_start timestamptz,
  appointment_window_end timestamptz,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_customer_portal_inbound_orders(p_tenant_id, p_actor_auth_user_id, p_warehouse_id, p_status_filter, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_customer_portal_inbound_orders with an identical grant set, never a reimplementation.';

revoke execute on function public.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
