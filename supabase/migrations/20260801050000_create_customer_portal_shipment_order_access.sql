-- Phase 8 capability CPL-304 (CG-S13-CPL-006, Prompt 304, "Shipment Order").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md,
-- supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300), supabase/migrations/20260801040000_create_customer_portal_
-- booking_requests.sql (CPL-303), and supabase/migrations/20260727100000_
-- create_operations_shipment_order.sql (OPS-169, the canonical, Operations-
-- owned source table) in full before this migration was written.
--
-- Structurally DIFFERENT from CPL-302/303: this capability is a READ
-- PROJECTION over the already-existing app.shipment_orders table, plus a
-- narrow "request a change" WRITE surface -- it does NOT create a parallel
-- shipment-truth table, and it NEVER calls app.confirm_shipment_order/app.
-- cancel_shipment_order (both stay OPS:Edit-gated, staff-only, byte-for-byte
-- untouched -- confirmed unmodified by this migration).
--
-- ===========================================================================
-- Design decisions (cited, not re-derived where given by the orchestrating
-- task; disclosed where this checkpoint had to resolve something itself)
-- ===========================================================================
--
-- 1. **Read RPCs are a customer-safe PROJECTION, never `app.shipment_orders`
--    itself and never `select *`.** `app.get_customer_shipment_order`/`app.
--    list_customer_shipment_orders` return an explicit 21-column `table(...)`
--    shape, not `setof app.shipment_orders` (contrast with CPL-303's own
--    portal-OWNED `app.customer_portal_booking_requests`, which correctly
--    returns its own full row -- there is nothing to mask on a table this
--    migration itself owns end to end). The full column list of `app.
--    shipment_orders` (20260727100000, read in full) is: id, tenant_id,
--    job_order_id, shipment_number, idempotency_key, status,
--    shipper_account_id, consignee_snapshot, notify_party_snapshot,
--    cargo_service_snapshot, service_type, mode, origin, destination,
--    planned_pickup_at, planned_delivery_at, basis_quantity,
--    basis_weight_kg, basis_volume_cbm, allocated_quantity,
--    allocated_weight_kg, allocated_volume_cbm, split_reason, owner_user_id,
--    org_unit_id, record_version, created_by, created_at, updated_at.
--    Confirmed by that migration's own design-note comment ("No masked
--    column exists on this table -- cost/selling data stays in app.
--    job_orders' own revenue_snapshot/credit_snapshot") that there is no
--    tariff/rate/margin field to mask here at all -- but the following ARE
--    excluded from the customer-safe projection, on direct inspection, as
--    staff-internal:
--      - `idempotency_key` -- a pure technical dedup token for Operations'
--        own creation RPC, no customer meaning.
--      - `owner_user_id`/`org_unit_id` -- internal record-scope/ownership
--        plumbing `app.can_access_record`/`app.lead_record_scope_org_unit_
--        ids` use for STAFF authorization, never a customer-facing identity.
--      - `created_by` -- a staff actor label (e.g. `'cbr1-staff'` in this
--        repository's own db-test fixtures), not a customer-facing field.
--      - `split_reason` -- a literal staff-authored "reason" column
--        (explicitly named as an exclusion class by the orchestrating
--        task's own instruction: "any internal notes/reason columns").
--      - `basis_quantity`/`basis_weight_kg`/`basis_volume_cbm` -- internal
--        cross-shipment allocation bookkeeping for the PARENT Job Order's
--        total split basis (OPS-169's own design note), not a fact about
--        THIS shipment's own cargo. `allocated_quantity`/`allocated_weight_
--        kg`/`allocated_volume_cbm` -- this shipment's own real allocated
--        cargo figures -- ARE kept, since they describe what is actually on
--        THIS shipment, the customer-relevant fact.
--    `job_order_id`/`shipper_account_id` are kept as opaque reference ids
--    (CPL-303's own `linked_job_order_id`/`linked_shipment_order_id` already
--    return exactly this class of reference verbatim to the customer -- not
--    a new disclosure).
-- 2. **`app.confirm_shipment_order`/`app.cancel_shipment_order` are never
--    called from anything in this migration** -- grep-confirmed. Both stay
--    OPS:Edit-gated, staff-only.
-- 3. **`app.customer_portal_shipment_change_requests` is a new, portal-owned
--    "request a change" table**, per the orchestrating task's own literal
--    column list (id, tenant_id, account_id, shipment_order_id, requested_
--    by_auth_user_id, request_type, details, status, idempotency_key,
--    record_version, timestamps, staff_response/staff_responded_by/at).
--    Disclosed refinements this checkpoint had to resolve:
--      a. **`account_id` is derived from the shipment order's own
--         `shipper_account_id` at create time, never customer-supplied.**
--         Unlike CPL-303's own `create_customer_booking_request_draft`
--         (which takes a customer-supplied `p_account_id` and must
--         separately cross-check a linked quote request's own account
--         against it), the shipment order here already structurally names
--         its own account -- deriving `account_id` from it eliminates that
--         entire class of account-mismatch bug rather than re-deriving the
--         same guard.
--      b. **The shipment-order lookup inside the create RPC combines
--         "genuinely nonexistent" and "exists but out of scope" into ONE
--         `shipment_order_not_found` error** -- the identical anti-
--         enumeration technique CPL-303's own `create_customer_booking_
--         request_draft` already applies to its OWN referenced record (a
--         linked quote request, `quote_request_not_found`), not merely to
--         a primary get-by-id RPC.
--      c. **No dedicated append-only history table** (contrast with CPL-303,
--         which added one for its own 6-status machine). This table's own
--         4-status machine (`submitted`/`acknowledged`/`resolved`/
--         `rejected`) is exactly as simple as CPL-302's own 4-status `app.
--         customer_portal_quote_requests` (`draft`/`submitted`/`cancelled`/
--         `converted`), which itself has no dedicated history table --
--         `capture_audit_event` on every mutation plus the row's own real
--         `created_at`/`updated_at`/`staff_responded_at` timestamps are the
--         transition record, mirroring CPL-302's own precedent rather than
--         CPL-303's (a checkpoint-by-checkpoint judgment call each of those
--         two already made differently for their own differently-sized
--         state machines).
--      d. **The staff respond RPC takes `p_expected_version`** (record_
--         version optimistic concurrency "on every update," the general
--         house style given up front), locks the row (`for update`), and is
--         idempotent for a genuine retry landing on the exact SAME target
--         status AND the same response text -- mirrors app.submit_customer_
--         booking_request's own status-check-before-version-check shape
--         (CPL-303). A call to a DIFFERENT target status once the row has
--         already left `submitted`, or a same-status call with different
--         response text once the row is `acknowledged`/`resolved`/
--         `rejected`, is a real `invalid_transition`, never a silent
--         overwrite -- contrast with CPL-303's own staff link RPC, which
--         deliberately has NO `p_expected_version` at all (a one-directional
--         terminal-ish conversion); this RPC's own status machine has a real
--         middle state (`acknowledged -> resolved|rejected`) a second staff
--         actor could race against, so the version guard is a real, live
--         concurrency control here, not boilerplate.
--      e. **One additional customer RPC beyond the two explicitly named
--         ones**: `app.list_customer_shipment_order_change_requests`. The
--         orchestrating task names exactly `app.request_customer_shipment_
--         order_change` (customer) and `app.respond_to_customer_shipment_
--         order_change_request` (staff) -- both built exactly as named,
--         unmodified in shape. Neither the shipment order projection nor
--         the change-request table itself gives the customer any way to
--         read back a request it already submitted or a staff response
--         once given, which would leave "request a change" a submit-into-
--         a-void action with no visible outcome (`RECURRING_DEFECT_
--         TAXONOMY.md` C-20's "no caller" shape, applied to the READ side
--         of a write flow rather than the write side). This one additional,
--         narrowly-scoped read RPC -- built to the identical ADR-0024 Part A
--         shape as every other read RPC in this migration -- closes that
--         gap. Disclosed as an addition, not a deviation from the two named
--         RPCs, which are otherwise built exactly as specified.
-- 4. **Alternative flow (source prompt §22, "if Operations has locked the
--    shipment, customer sees immutable detail and can create a ticket or
--    change request instead") needs no new "locked" concept.** `app.
--    shipment_orders.status` (`draft`/`confirmed`/`cancelled`, OPS-169's own
--    enum) is rendered plainly by the read RPC/UI; a `confirmed` or
--    `cancelled` shipment is already immutable from the customer's own side
--    (no customer RPC anywhere ever mutates `app.shipment_orders` itself),
--    and this migration's own change-request path is exactly the
--    alternative action named. No ticket-creation INTEGRATION is built this
--    checkpoint (that composition is Prompt 313's own job, per the
--    orchestrating task's own explicit instruction) -- the shipment detail
--    UI carries a plain link/mention pointing at the existing app/(tenant)/
--    [tenantSlug]/customer-tickets/ route, honest and disclosed, not a fake
--    integration.
-- 5. **RLS: `authenticated` holds ZERO direct grant** on the new change-
--    request table, mirroring CPL-300/302/303's own convention exactly.
--    `app.shipment_orders` itself is completely untouched by this migration
--    -- no RLS policy on it is edited, narrowed, or widened; it already
--    correctly denies `customer_user` by default per `CG-S10-ATW-032`
--    (its own single `shipment_orders_select_scoped` policy tests `app.
--    can_access_record`, which fails closed for a `customer_user`-layer
--    principal carrying no staff org-unit/owner relationship -- re-verified
--    live in this checkpoint's own db-test, not merely assumed).
-- 6. **Two new, purely additive covering indexes on the EXISTING, already-
--    applied `app.shipment_orders` table** -- `(tenant_id, updated_at desc,
--    id desc)` for `app.list_customer_shipment_orders`' own keyset
--    pagination, and `(tenant_id, shipper_account_id)` for the scope
--    predicate every read/write RPC in this migration filters on (OPS-169's
--    own migration indexed `job_order_id`/`status`/`owner_user_id`/`mode`,
--    but never `shipper_account_id` -- this migration's own new query shape
--    needs it). A new migration adding an index to an already-applied table
--    is additive DDL, never an edit to that migration's own file (`AGENTS.
--    md`'s "never edit an applied migration" rule) -- mirrors ATW-023's own
--    companion pagination-index-migration precedent, built inline here
--    instead of as a separate file, matching that same precedent's own
--    disclosed "your call" latitude on inline-vs-separate.
-- 7. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Actions + UI only, no `app/api/` HTTP route -- identical in kind to
--    CPL-300/301/302/303's own disclosed residual gap.
-- 8. **No edit to `scripts/db-tests/rbac-enforcement.sql`** -- every new
--    `SECURITY DEFINER` function granted to `authenticated` either calls
--    `app.assert_actor_is_session_identity` directly as its own first
--    statement (every function in this migration does, reads and writes
--    alike, CPL-300's own Tier C lesson) or is covered transitively by that
--    shared test's own base-regex closure via `app.resolve_customer_
--    account_scope`/`app.evaluate_permission` (both already-recognized base
--    keywords since CPL-300/ATW-031) -- mirrors CPL-303's own identical,
--    already-verified "no edit required" precedent exactly.
-- 9. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from
--    public` before its final grants.

-- ===========================================================================
-- 1. Additive covering indexes on the existing app.shipment_orders table
--    (design decision 6) -- no other change to that table or its RLS.
-- ===========================================================================

create index shipment_orders_tenant_updated_id_idx
  on app.shipment_orders (tenant_id, updated_at desc, id desc);

create index shipment_orders_tenant_shipper_account_idx
  on app.shipment_orders (tenant_id, shipper_account_id);

-- ===========================================================================
-- 2. app.get_customer_shipment_order / app.list_customer_shipment_orders --
--    customer-safe projection read RPCs (design decision 1)
-- ===========================================================================

create function app.get_customer_shipment_order(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
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
  v_shipment app.shipment_orders;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Table alias required: this function's own `returns table (id uuid,
  -- tenant_id uuid, ...)` shape creates implicitly-named OUT parameters
  -- (`id`, `tenant_id`, ...) visible in this function's own body, which
  -- would otherwise make an unqualified `where id = ...` against app.
  -- shipment_orders' own same-named columns genuinely ambiguous to the
  -- planner (live-caught by this migration's own db-test on first run, not
  -- merely reasoned about) -- `so.` qualifies every column reference below.
  select so.* into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id and so.tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  return query
  select
    v_shipment.id, v_shipment.tenant_id, v_shipment.job_order_id, v_shipment.shipment_number, v_shipment.status,
    v_shipment.shipper_account_id, v_shipment.consignee_snapshot, v_shipment.notify_party_snapshot, v_shipment.cargo_service_snapshot,
    v_shipment.service_type, v_shipment.mode, v_shipment.origin, v_shipment.destination,
    v_shipment.planned_pickup_at, v_shipment.planned_delivery_at,
    v_shipment.allocated_quantity, v_shipment.allocated_weight_kg, v_shipment.allocated_volume_cbm,
    v_shipment.record_version, v_shipment.created_at, v_shipment.updated_at;
end;
$$;

comment on function app.get_customer_shipment_order is
  'CPL-304: anti-enumerating get-by-id (ADR-0024 Part A) over app.shipment_orders -- raises the IDENTICAL record_not_found (errcode no_data_found) whether p_shipment_order_id genuinely does not exist, belongs to a different tenant, or exists but its own shipper_account_id is outside this identity''s resolved scope. Returns ONLY the customer-safe 21-column projection (design decision 1) -- never the base table, never select *. app.shipment_orders'' own RLS is untouched; this SECURITY DEFINER function reads the base table directly (as its own owner) and applies its own scope check in code, the same pattern every other Phase 8 read RPC uses.';

create function app.list_customer_shipment_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
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

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    so.id, so.tenant_id, so.job_order_id, so.shipment_number, so.status,
    so.shipper_account_id, so.consignee_snapshot, so.notify_party_snapshot, so.cargo_service_snapshot,
    so.service_type, so.mode, so.origin, so.destination,
    so.planned_pickup_at, so.planned_delivery_at,
    so.allocated_quantity, so.allocated_weight_kg, so.allocated_volume_cbm,
    so.record_version, so.created_at, so.updated_at
  from app.shipment_orders so
  where so.tenant_id = p_tenant_id
    and so.shipper_account_id = any (v_scope)
    and (p_account_id is null or so.shipper_account_id = p_account_id)
    and (p_status is null or so.status = p_status)
    and (p_cursor_id is null or (so.updated_at, so.id) < (p_cursor_updated_at, p_cursor_id))
  order by so.updated_at desc, so.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_shipment_orders is
  'CPL-304: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200 -- mirrors app.list_customer_booking_requests (CPL-303) exactly. Deny-by-default: zero scope or an out-of-scope p_account_id filter both return an empty result, never an error. Returns ONLY the customer-safe 21-column projection (design decision 1).';

-- ===========================================================================
-- 3. app.customer_portal_shipment_change_requests -- the portal-owned
--    "request a change" table (design decision 3)
-- ===========================================================================

create table app.customer_portal_shipment_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  requested_by_auth_user_id uuid not null references auth.users (id),
  request_type text not null,
  details text,
  status text not null default 'submitted',
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  staff_response text,
  staff_responded_by text,
  staff_responded_at timestamptz,
  constraint cpscr_request_type_check check (request_type in ('reschedule', 'cancel', 'other')),
  constraint cpscr_status_check check (status in ('submitted', 'acknowledged', 'resolved', 'rejected')),
  constraint cpscr_details_check check (details is not null and length(trim(details)) > 0),
  constraint cpscr_staff_response_check check (
    (status = 'submitted' and staff_response is null and staff_responded_by is null and staff_responded_at is null)
    or (status in ('acknowledged', 'resolved', 'rejected') and staff_response is not null and length(trim(staff_response)) > 0
        and staff_responded_by is not null and staff_responded_at is not null)
  )
);

comment on table app.customer_portal_shipment_change_requests is
  'CPL-304: the portal-owned "request a change" record for an Operations-owned app.shipment_orders row -- never a canonical mutation, never a call into app.confirm_shipment_order/app.cancel_shipment_order (design decision 2). account_id is derived from the target shipment order''s own shipper_account_id at create time, never customer-supplied (design decision 3a). RLS enabled, authenticated holds zero direct grant (design decision 5) -- the 3 RPCs below are the only sanctioned access path.';

create unique index cpscr_tenant_idempotency_key_uq
  on app.customer_portal_shipment_change_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create index cpscr_tenant_updated_id_idx
  on app.customer_portal_shipment_change_requests (tenant_id, updated_at desc, id desc);

create index cpscr_shipment_order_idx on app.customer_portal_shipment_change_requests (shipment_order_id);
create index cpscr_account_idx on app.customer_portal_shipment_change_requests (account_id);

-- ===========================================================================
-- 4. Triggers -- status machine: submitted -> acknowledged|resolved|rejected;
--    acknowledged -> resolved|rejected; resolved/rejected are terminal.
-- ===========================================================================

create function app.enforce_customer_portal_shipment_change_request_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('resolved', 'rejected') then
    raise exception 'invalid_cpscr_transition: change request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'submitted' and new.status in ('acknowledged', 'resolved', 'rejected'))
    or (old.status = 'acknowledged' and new.status in ('resolved', 'rejected'))
  ) then
    raise exception 'invalid_cpscr_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger customer_portal_shipment_change_requests_enforce_transition
  before update of status on app.customer_portal_shipment_change_requests
  for each row
  execute function app.enforce_customer_portal_shipment_change_request_transition();

create function app.touch_customer_portal_shipment_change_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_portal_shipment_change_requests_touch_row
  before update on app.customer_portal_shipment_change_requests
  for each row
  execute function app.touch_customer_portal_shipment_change_request_row();

-- ===========================================================================
-- 5. app.request_customer_shipment_order_change -- customer, Layer-4-only
-- ===========================================================================

create function app.request_customer_shipment_order_change(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_request_type text,
  p_details text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_shipment_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_shipment_change_requests;
  v_shipment app.shipment_orders;
  v_request app.customer_portal_shipment_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_request_type not in ('reschedule', 'cancel', 'other') then
    raise exception 'invalid_request_type: % is not a recognized shipment change request type', p_request_type using errcode = 'check_violation';
  end if;

  if p_details is null or length(trim(p_details)) = 0 then
    raise exception 'details_required: a non-empty details description is required to request a shipment change' using errcode = 'not_null_violation';
  end if;

  -- Design decision 3b: combines "genuinely nonexistent" and "exists but
  -- out of scope" into ONE anti-enumerating error, mirroring CPL-303's own
  -- quote_request_not_found technique for a referenced (non-primary) record.
  -- Tier C fix (C-01 discipline): this scope check now runs BEFORE the
  -- idempotency short-circuit below, never after -- the idempotent-return
  -- path must not be reachable for a shipment order this identity cannot
  -- see at all.
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'shipment_order_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (C-01 discipline): the idempotent short-circuit must verify
  -- the found row actually targets the SAME shipment order this call
  -- targets before ever returning it. A colliding key belonging to a
  -- DIFFERENT shipment order (and therefore, in general, a different
  -- account) -- whether guessed, or a genuine same-actor multi-shipment
  -- collision -- is a real idempotency_key_conflict, never a silent
  -- cross-account disclosure of another shipment's change-request details.
  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_shipment_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.shipment_order_id = p_shipment_order_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different shipment''s change request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  -- Tier C fix (C-01 discipline): a REAL exception handler, not merely a
  -- pre-check select -- two genuinely concurrent calls carrying the
  -- identical key can both pass the pre-check above before either commits;
  -- the race LOSER's own INSERT must recover via the SAME shipment-scoped
  -- re-select, never surface a raw unique_violation to the caller.
  begin
    insert into app.customer_portal_shipment_change_requests (
      tenant_id, account_id, shipment_order_id, requested_by_auth_user_id, request_type, details, idempotency_key
    ) values (
      p_tenant_id, v_shipment.shipper_account_id, p_shipment_order_id, p_actor_auth_user_id, p_request_type, p_details, p_idempotency_key
    )
    returning * into v_request;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_request from app.customer_portal_shipment_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_request.shipment_order_id <> p_shipment_order_id then
        raise;
      end if;
      -- Race LOSER recovering onto the WINNER's already-committed row:
      -- return it as-is, exactly like the pre-check idempotent-return path
      -- above -- never fall through to a second, spurious audit event for a
      -- row this call did not actually create.
      return v_request;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_shipment_order_change',
    'app.customer_portal_shipment_change_requests', v_request.id, 'success', p_details, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.request_customer_shipment_order_change is
  'CPL-304: creates a submitted "request a change" record against a shipment order in this identity''s resolved scope. account_id is derived from the shipment order''s own shipper_account_id, never customer-supplied (design decision 3a). Idempotent on (tenant_id, idempotency_key) when a key is supplied, for the SAME shipment order only -- the SAME key against a DIFFERENT shipment order is a real idempotency_key_conflict, never a silent cross-shipment/cross-account return (Tier C fix, C-01 discipline, mirrors CPL-302/303). The INSERT itself is wrapped in a real unique_violation handler, not only a pre-check, so a genuine two-process race on the same key converges on one row (Tier C fix). Never calls app.confirm_shipment_order/app.cancel_shipment_order or mutates app.shipment_orders in any way (design decision 2) -- this is a REQUEST only, resolved by staff via app.respond_to_customer_shipment_order_change_request.';

-- ===========================================================================
-- 6. app.list_customer_shipment_order_change_requests -- customer, read
--    (design decision 3e -- disclosed addition, closes the "submit into a
--    void" gap)
-- ===========================================================================

create function app.list_customer_shipment_order_change_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_shipment_change_requests
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

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_shipment_change_requests r
  where r.tenant_id = p_tenant_id
    and r.account_id = any (v_scope)
    and (p_shipment_order_id is null or r.shipment_order_id = p_shipment_order_id)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_shipment_order_change_requests is
  'CPL-304: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200. Deny-by-default: zero scope returns an empty result, never an error. Returns the full portal-owned row (no masking concern -- this table has no cost/rate/vendor field, design decision 3). Optional p_shipment_order_id narrows to one shipment''s own change requests for the detail page; scope is enforced via account_id regardless.';

-- ===========================================================================
-- 7. app.respond_to_customer_shipment_order_change_request -- staff,
--    OPS:Edit (the ONLY staff-RBAC touchpoint in this migration)
-- ===========================================================================

create function app.respond_to_customer_shipment_order_change_request(
  p_change_request_id uuid,
  p_expected_version integer,
  p_to_status text,
  p_staff_response text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_shipment_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_shipment_change_requests;
  v_updated app.customer_portal_shipment_change_requests;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_to_status not in ('acknowledged', 'resolved', 'rejected') then
    raise exception 'invalid_status: % is not a status this function may set', p_to_status using errcode = 'check_violation';
  end if;

  if p_staff_response is null or length(trim(p_staff_response)) = 0 then
    raise exception 'staff_response_required: a non-empty staff response is required' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_shipment_change_requests where id = p_change_request_id for update;
  -- Tier C fix (C-05 discipline): fold a tenant-standing check into the SAME
  -- not-found branch, BEFORE the specific-permission check. This migration's
  -- own earlier comment here claimed this ordering already "mirrors CPL-303's
  -- own C-05 self-check precedent exactly" -- that claim was inaccurate:
  -- neither this function nor CPL-303's own link_customer_booking_request_to_
  -- operational_records actually performed a tenant-standing check before
  -- evaluate_permission until this Tier C fix pass corrected all three
  -- (302/303/304) together. Mirrors app.get_rfq's own established fix
  -- (supabase/migrations/20260730670000_harden_procurement_batch_257_259_
  -- review_fixes.sql). "Standing" here is deliberately wider than staff-only
  -- has_active_tenant_membership alone: this RPC is reachable by BOTH a
  -- staff caller AND a genuine customer_user-layer caller with real portal
  -- scope in this tenant (resolve_customer_account_scope) -- that
  -- identity's own app.tenant_user_identities row is deliberately NEVER
  -- 'active' (CPL-302 design decision 4(b)), so has_active_tenant_
  -- membership alone would wrongly hide insufficient_authority from a
  -- customer who is genuinely a member of this tenant (a live-tested case:
  -- a customer, Layer 4, not staff, must still get insufficient_authority,
  -- never not_found). A caller satisfying EITHER predicate still reaches
  -- the informative insufficient_authority branch below; a caller
  -- satisfying NEITHER (e.g. a customer_user of a completely different
  -- tenant) gets the identical not-found error a missing row would produce.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or array_length(app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id), 1) is not null
  ) then
    raise exception 'change_request_not_found: %', p_change_request_id using errcode = 'no_data_found';
  end if;

  -- Reuses the already-existing OPS:Edit action (the same module/action
  -- app.confirm_shipment_order/app.cancel_shipment_order/CPL-303's own
  -- link_customer_booking_request_to_operational_records already require);
  -- no new module/action added.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op (design decision 3d): a genuine retry landing on the
  -- SAME target status AND the same response text returns the row
  -- unchanged, mirroring app.submit_customer_booking_request''s own
  -- status-check-before-version-check shape (CPL-303).
  if v_request.status = p_to_status and v_request.staff_response = p_staff_response then
    return v_request;
  end if;

  if not (
    (v_request.status = 'submitted')
    or (v_request.status = 'acknowledged' and p_to_status in ('resolved', 'rejected'))
  ) then
    raise exception 'invalid_transition: change request % is % and cannot move to %', p_change_request_id, v_request.status, p_to_status
      using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: change request % expected version % but found %', p_change_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_shipment_change_requests
  set status = p_to_status, staff_response = p_staff_response, staff_responded_by = p_actor_label, staff_responded_at = now()
  where id = p_change_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'respond_to_customer_shipment_order_change_request',
    'app.customer_portal_shipment_change_requests', v_updated.id, 'success', p_staff_response, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.respond_to_customer_shipment_order_change_request is
  'CPL-304: staff-only (OPS:Edit) response/resolution -- submitted -> acknowledged|resolved|rejected, or acknowledged -> resolved|rejected (resolved/rejected are terminal). Mandatory non-empty staff_response. Optimistic concurrency via select ... for update + explicit p_expected_version check (design decision 3d) -- a real, live guard, since acknowledged -> resolved|rejected is a genuine second race a concurrent staff actor could hit. Idempotent only for a retry landing on the exact SAME target status and response text; any other same-status or later-status collision is invalid_transition. Tier C fix (C-05 discipline): the not-found branch now also requires has_active_tenant_membership on the row''s own tenant, BEFORE the OPS:Edit check runs, so a non-member cannot learn the row''s real tenant_id from a distinguishable insufficient_authority error.';

-- ===========================================================================
-- 8. RLS -- enable, grant service_role only (design decision 5)
-- ===========================================================================

alter table app.customer_portal_shipment_change_requests enable row level security;

grant select, insert, update, delete
  on app.customer_portal_shipment_change_requests
  to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_shipment_order(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_shipment_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.request_customer_shipment_order_change(uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_shipment_order_change_requests(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.respond_to_customer_shipment_order_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
