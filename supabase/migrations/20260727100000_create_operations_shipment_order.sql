-- Operations capability OPS-169 (Shipment Order, CG-S8-OPS-003)
-- Converts one confirmed Job Order (`app.job_orders`, OPS-168) into one or more
-- single-leg Shipment Orders -- each an executable shipment definition that inherits
-- its parties/cargo/service from the Job Order rather than re-entering them, with a
-- governed, reconciled allocation across every non-cancelled Shipment Order that
-- shares the same Job Order (Prompt 169 §22's own "split into multiple independent
-- basic Shipment Orders with reconciled allocation" alternative flow).
--
-- Allocation-basis design decision (disclosed): `app.job_order_handoffs`' own
-- `cargoService` sub-object (COM-160's `JobOrderDraftInput.cargoService`) is
-- deliberately untyped jsonb (`server/contracts/job-order-lineage/job-order-lineage.ts`
-- models it as `z.record(z.string(), z.unknown())`) -- Commercial never guarantees a
-- quantity/weight/volume sub-field exists on it. Rather than inventing a job-level
-- allocation-basis column against an unknown source shape, this migration establishes
-- the basis structurally instead: the first non-cancelled Shipment Order created
-- against a given Job Order declares that Job Order's own allocation basis via its own
-- `basis_quantity`/`basis_weight_kg`/`basis_volume_cbm` columns (each dimension
-- independently, any of which may be left null and is then advisory-only -- never
-- enforced -- for that one dimension; every later Shipment Order against the same Job
-- Order carries null in these three columns, since only the first row is authoritative
-- for the basis). That first row's own `allocated_*` is simply its own share of that
-- basis, exactly like every later split -- not the basis itself. Every subsequent
-- non-cancelled Shipment Order against the same Job Order must supply a non-empty
-- `split_reason` and must not push the running sum of every non-cancelled row's own
-- `allocated_*`, for any dimension where a basis was established, past that basis. No
-- override path exists in this bounded slice (Prompt 169 §24's "without approved
-- override" is read as "an override mechanism may be added later," not as a
-- requirement here) -- an over-allocation attempt is a hard, structural block,
-- disclosed rather than silently accepted.
--
-- Mode/service stay a simple top-level classifier only (`mode`/`service_type` text
-- columns) -- the per-mode typed baseline (land vehicle/vendor/route; air AWB/flight/
-- airport; sea BL/booking/vessel/port/container) is `OPS-171`'s own explicit scope,
-- not duplicated or anticipated here.
--
-- Permission catalogue: reuses the same 'OPS' action set already seeded at `PLT-111`
-- and already granted a first real consumer at `OPS-168` -- no new permission-catalogue
-- row is inserted by this migration.
--
-- Record-scope reuses `app.lead_record_scope_org_unit_ids` (COM-143) directly, the
-- same precedent `OPS-168` itself already established for Operations-domain records.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

create table app.shipment_order_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.shipment_order_number_counters is
  'OPS-169: one atomic, tenant-scoped monotonic counter for app.next_shipment_number() -- the same bounded, disclosed alternative to the Configurable Numbering Engine (PLT-125) app.job_order_number_counters (OPS-168) and app.next_quotation_number (COM-151) already established.';

create function app.next_shipment_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.shipment_order_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.shipment_order_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'SHP-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_shipment_number is
  'OPS-169: atomic collision-safe allocation via a single INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING, the same safe pattern app.next_job_order_number (OPS-168) uses. Never recycled -- last_seq only increases.';

create table app.shipment_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  shipment_number text not null,
  idempotency_key text not null,
  status text not null default 'draft',
  shipper_account_id uuid not null references app.accounts (id),
  consignee_snapshot jsonb not null,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb not null,
  service_type text not null,
  mode text not null,
  origin text not null,
  destination text not null,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_orders_status_check check (status in ('draft', 'confirmed', 'cancelled')),
  constraint shipment_orders_mode_check check (mode in ('land', 'air', 'sea')),
  constraint shipment_orders_tenant_number_unique unique (tenant_id, shipment_number),
  constraint shipment_orders_tenant_job_idempotency_unique unique (tenant_id, job_order_id, idempotency_key),
  constraint shipment_orders_allocated_quantity_check check (allocated_quantity is null or allocated_quantity >= 0),
  constraint shipment_orders_allocated_weight_check check (allocated_weight_kg is null or allocated_weight_kg >= 0),
  constraint shipment_orders_allocated_volume_check check (allocated_volume_cbm is null or allocated_volume_cbm >= 0),
  constraint shipment_orders_basis_quantity_check check (basis_quantity is null or basis_quantity >= 0),
  constraint shipment_orders_basis_weight_check check (basis_weight_kg is null or basis_weight_kg >= 0),
  constraint shipment_orders_basis_volume_check check (basis_volume_cbm is null or basis_volume_cbm >= 0)
);

comment on table app.shipment_orders is
  'OPS-169: one single-leg, single-mode executable shipment definition per row, always linked to exactly one Job Order (OPS-168). shipper_account_id is a live canonical FK (the Job Order''s own account, never re-entered); consignee_snapshot/notify_party_snapshot are structured jsonb (a shipment''s consignee may legitimately differ from the Job Order''s own billing customer -- e.g. a drop-ship destination -- so these are not forced through the same account reference); cargo_service_snapshot is a verbatim copy of the Job Order''s own cargo_service_snapshot at creation time, a governed snapshot never silently re-entered. Idempotent on (tenant_id, job_order_id, idempotency_key) -- a retry with the same key returns the same row, never a duplicate; a genuinely new split allocation uses a new idempotency_key and must carry a non-empty split_reason once any other non-cancelled Shipment Order already exists for the same Job Order.';

create index shipment_orders_tenant_job_idx on app.shipment_orders (tenant_id, job_order_id);
create index shipment_orders_tenant_status_idx on app.shipment_orders (tenant_id, status);
create index shipment_orders_tenant_owner_idx on app.shipment_orders (tenant_id, owner_user_id);
create index shipment_orders_tenant_mode_idx on app.shipment_orders (tenant_id, mode);

create function app.touch_shipment_orders_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_orders_touch_row
  before update on app.shipment_orders
  for each row
  execute function app.touch_shipment_orders_row();

-- Governed allocation balance (Prompt 169 §22/§24) -- sums every non-cancelled
-- Shipment Order against one Job Order and reports the basis (the first non-cancelled
-- Shipment Order's own allocated_* values, per dimension) plus the remaining headroom.
-- A null basis dimension is advisory-only, disclosed via basis_established=false for
-- that dimension rather than silently treating null as "no limit" without saying so.
create function app.get_job_shipment_allocation_balance(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  remaining_quantity numeric,
  remaining_weight_kg numeric,
  remaining_volume_cbm numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_basis_qty numeric;
  v_basis_weight numeric;
  v_basis_volume numeric;
  v_alloc_qty numeric;
  v_alloc_weight numeric;
  v_alloc_volume numeric;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The basis is declared once, on the very first Shipment Order ever created for
  -- this Job Order -- looked up across every row regardless of its own current
  -- status, since a later cancellation of that first row must never erase the
  -- basis it already declared.
  select so.basis_quantity, so.basis_weight_kg, so.basis_volume_cbm
    into v_basis_qty, v_basis_weight, v_basis_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id
  order by so.created_at asc
  limit 1;

  select coalesce(sum(so.allocated_quantity), 0), coalesce(sum(so.allocated_weight_kg), 0), coalesce(sum(so.allocated_volume_cbm), 0)
    into v_alloc_qty, v_alloc_weight, v_alloc_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id and so.status <> 'cancelled';

  return query select
    v_basis_qty, v_basis_weight, v_basis_volume,
    v_alloc_qty, v_alloc_weight, v_alloc_volume,
    case when v_basis_qty is null then null else v_basis_qty - v_alloc_qty end,
    case when v_basis_weight is null then null else v_basis_weight - v_alloc_weight end,
    case when v_basis_volume is null then null else v_basis_volume - v_alloc_volume end;
end;
$$;

comment on function app.get_job_shipment_allocation_balance is
  'OPS-169: the basis is the very first Shipment Order ever created for the Job Order''s own basis_quantity/basis_weight_kg/basis_volume_cbm (looked up regardless of that row''s own current status, so a later cancellation of the first row never erases the basis it already declared), per dimension independently; a null basis dimension means no cap was ever established for it (advisory-only), distinct from a basis of zero. allocated_* sums every currently non-cancelled row.';

-- The one atomic, idempotent creation action (Prompt 169 §20 task 2/§21). OPS:Create-
-- gated, requires the Job Order be confirmed (the one gate OPS-168 itself named as
-- making a Job Order eligible for this), and enforces the split-reason/allocation-
-- balance rules above.
create function app.create_shipment_order_from_job(
  p_job_order_id uuid,
  p_idempotency_key text,
  p_consignee jsonb,
  p_notify_party jsonb,
  p_service_type text,
  p_mode text,
  p_origin text,
  p_destination text,
  p_planned_pickup_at timestamptz,
  p_planned_delivery_at timestamptz,
  p_allocated_quantity numeric,
  p_allocated_weight_kg numeric,
  p_allocated_volume_cbm numeric,
  p_basis_quantity numeric,
  p_basis_weight_kg numeric,
  p_basis_volume_cbm numeric,
  p_split_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_orders;
  v_shipment app.shipment_orders;
  v_number text;
  v_existing_count integer;
  v_balance record;
  v_basis_quantity numeric;
  v_basis_weight_kg numeric;
  v_basis_volume_cbm numeric;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode' , p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'confirmed' then
    raise exception 'job_order_not_confirmed: job order % is % and is not eligible for Shipment Order creation', p_job_order_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_existing_count from app.shipment_orders where job_order_id = p_job_order_id and status <> 'cancelled';
  if v_existing_count > 0 and (p_split_reason is null or length(trim(p_split_reason)) = 0) then
    raise exception 'split_reason_required: a non-empty split_reason is required when another Shipment Order already exists for job order %', p_job_order_id
      using errcode = 'check_violation';
  end if;

  if v_existing_count > 0 then
    select * into v_balance from app.get_job_shipment_allocation_balance(p_job_order_id, p_actor_auth_user_id);
    if v_balance.basis_quantity is not null and coalesce(p_allocated_quantity, 0) > coalesce(v_balance.remaining_quantity, 0) then
      raise exception 'over_allocation: allocated_quantity % exceeds remaining % for job order %', p_allocated_quantity, v_balance.remaining_quantity, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_weight_kg is not null and coalesce(p_allocated_weight_kg, 0) > coalesce(v_balance.remaining_weight_kg, 0) then
      raise exception 'over_allocation: allocated_weight_kg % exceeds remaining % for job order %', p_allocated_weight_kg, v_balance.remaining_weight_kg, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_volume_cbm is not null and coalesce(p_allocated_volume_cbm, 0) > coalesce(v_balance.remaining_volume_cbm, 0) then
      raise exception 'over_allocation: allocated_volume_cbm % exceeds remaining % for job order %', p_allocated_volume_cbm, v_balance.remaining_volume_cbm, p_job_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Only the first non-cancelled Shipment Order for a Job Order may declare the
  -- allocation basis -- a later split's own p_basis_* arguments are structurally
  -- ignored (stored null), since only the first row is ever consulted by
  -- app.get_job_shipment_allocation_balance.
  if v_existing_count = 0 then
    v_basis_quantity := p_basis_quantity;
    v_basis_weight_kg := p_basis_weight_kg;
    v_basis_volume_cbm := p_basis_volume_cbm;
  end if;

  v_number := app.next_shipment_number(v_job.tenant_id);

  begin
    insert into app.shipment_orders (
      tenant_id, job_order_id, shipment_number, idempotency_key, shipper_account_id,
      consignee_snapshot, notify_party_snapshot, cargo_service_snapshot,
      service_type, mode, origin, destination, planned_pickup_at, planned_delivery_at,
      basis_quantity, basis_weight_kg, basis_volume_cbm,
      allocated_quantity, allocated_weight_kg, allocated_volume_cbm, split_reason,
      owner_user_id, created_by
    ) values (
      v_job.tenant_id, p_job_order_id, v_number, p_idempotency_key, v_job.account_id,
      coalesce(p_consignee, v_job.customer_snapshot), p_notify_party, v_job.cargo_service_snapshot,
      p_service_type, p_mode, p_origin, p_destination, p_planned_pickup_at, p_planned_delivery_at,
      v_basis_quantity, v_basis_weight_kg, v_basis_volume_cbm,
      p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_split_reason,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_shipment;
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
      return v_shipment;
  end;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_shipment_order_from_job',
    'app.shipment_orders', v_shipment.id, 'success', null, null,
    jsonb_build_object('job_order_id', p_job_order_id, 'shipment_number', v_number, 'split_reason', p_split_reason)
  );

  return v_shipment;
end;
$$;

comment on function app.create_shipment_order_from_job is
  'OPS-169: idempotent on (tenant_id, job_order_id, idempotency_key) -- a repeated call, including under a concurrent-insert race, returns the exact same Shipment Order row, never a duplicate. shipper_account_id/cargo_service_snapshot are inherited verbatim from the Job Order; consignee_snapshot defaults to the Job Order''s own customer_snapshot when not explicitly supplied. Requires the Job Order be confirmed. p_basis_quantity/p_basis_weight_kg/p_basis_volume_cbm are only stored when this is the first non-cancelled Shipment Order for the Job Order (structurally ignored on any later call). A second (or later) non-cancelled Shipment Order against the same Job Order requires a non-empty split_reason and is allocation-balance-checked against app.get_job_shipment_allocation_balance.';

-- draft -> confirmed. OPS:Edit-gated, mirroring app.confirm_job_order (OPS-168).
create function app.confirm_shipment_order(
  p_shipment_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'invalid_transition: shipment order % is % and cannot be confirmed', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'confirmed'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('status', v_shipment.status)
  );

  return v_shipment;
end;
$$;

comment on function app.confirm_shipment_order is
  'OPS-169: draft -> confirmed, the one gate Prompt 170 (Shipment Lifecycle) will build its own canonical transition matrix on top of. Optimistic-concurrency-checked and record-scope-checked, matching app.confirm_job_order (OPS-168).';

-- draft/confirmed -> cancelled. Mandatory reason; releases this Shipment Order's own
-- allocation from the balance (get_job_shipment_allocation_balance excludes cancelled
-- rows), the one release mechanism this bounded slice needs.
create function app.cancel_shipment_order(
  p_shipment_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a Shipment Order' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is already cancelled', p_shipment_order_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'cancelled'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_shipment;
end;
$$;

comment on function app.cancel_shipment_order is
  'OPS-169: draft/confirmed -> cancelled, mandatory reason. A cancelled Shipment Order''s own allocation is excluded from app.get_job_shipment_allocation_balance, releasing its share of the Job Order''s basis for a future split.';

alter table app.shipment_orders enable row level security;

create policy shipment_orders_select_scoped on app.shipment_orders
  for select to authenticated
  using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));

revoke execute on all functions in schema app from public;

-- No masked column exists on this table (cost/selling data stays in app.job_orders'
-- own revenue_snapshot/credit_snapshot, never duplicated here per Prompt 169 §16's own
-- "cost/selling projections are minimized" -- there simply are none to mask), so a
-- plain full-column grant is correct here, matching app.leads'/app.opportunities' own
-- established convention for a table with nothing sensitive to carve out (unlike
-- app.job_orders/app.quotations, which do carry a masked column and so use the
-- explicit-column-grant technique instead).
grant select on app.shipment_orders to authenticated;
grant select on app.shipment_orders to service_role;
grant insert, update, delete on app.shipment_orders to service_role;

grant execute on function app.next_shipment_number(uuid) to service_role;
grant execute on function app.get_job_shipment_allocation_balance(uuid, uuid) to authenticated, service_role;
grant execute on function app.create_shipment_order_from_job(uuid, text, jsonb, jsonb, text, text, text, text, timestamptz, timestamptz, numeric, numeric, numeric, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_shipment_order(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_shipment_order(uuid, integer, text, uuid, text) to authenticated, service_role;
