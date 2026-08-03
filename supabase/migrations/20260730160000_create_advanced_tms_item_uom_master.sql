-- Advanced TMS/WMS capability ATW-011A (CG-S10-ATW-011A), inserted between the
-- VERIFIED Prompt 230 ("Bin and Racking") and Prompt 231 ("WMS Inbound") by explicit
-- operator authorization following a comprehensive read-only gap audit of this
-- session's own build output (docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- row `CG-S10-ATW-012` already recorded the blocking fact this migration closes: "no
-- item/SKU/product master type has ever been registered anywhere in this repository").
--
-- This is not one of the 430 files in docs/ai-agent-build-prompt-package/ -- the audit
-- confirmed, by enumerating every *_PROMPT.md filename and grepping every prompt body
-- for "item master|sku master|product master|UOM master|unit of measure", that no
-- prompt in the entire package (79-430) ever creates an item/SKU/product master or a
-- UOM master; every WMS prompt (231-244) only consumes one. Prompt 231 §9 ("verified
-- customer/item/master and shipment contracts") and Prompt 234 §9 ("approved item/
-- UOM/owner/status identity") both require this identity to already be VERIFIED --
-- an unsatisfiable circular dependency inside the package itself, escalated to the
-- operator rather than silently resolved by a build agent (docs/adr/ADR-0019, this
-- checkpoint's own companion decision record).
--
-- Design boundary (disclosed):
--
-- 1. **A flat, typed-column `app.item_masters` table, never `app.master_records`
--    (PLT-120).** `ADR-0019` resolves this the same way `ADR-0018` resolved the
--    identical question for `app.accounts`: `app.master_records`'s own unique index
--    is `(master_type_code, tenant_id, code)` -- tenant-wide, with no owner dimension
--    -- so two different 3PL customers in the same tenant could never both hold SKU
--    code `A100`. Its own `attributes` validator (`app.validate_master_attributes`)
--    additionally rejects nested objects/arrays, which a real UOM-conversion or
--    dimension shape would need. `app.item_masters` instead mirrors `app.accounts`'
--    own shape and RLS posture directly (tenant-wide visibility gated by
--    `app.has_active_tenant_membership`, never per-org-unit record-scoped) --
--    Commercial-adjacent reference identity, not a company/branch operational record.
-- 2. **`owner_account_id` is a mandatory, real `uuid references app.accounts (id)`.**
--    Every SKU in a 3PL warehouse belongs to exactly one customer; this is the
--    identical proven FK shape `ATW-229`'s own `app.warehouse_customer_eligibility.
--    customer_account_id` already established (not the free-text, unlinked
--    `app.principal_memberships.customer_account_ref` the audit separately flagged as
--    unsuitable for this purpose) -- reused directly, not re-derived.
-- 3. **UOM is a real, governed registry (`app.uoms` + `app.uom_conversions`), mirroring
--    `app.finance_currencies`/`app.validate_currency_code` (FIN-194) verbatim** -- the
--    same "small global catalogue, `service_role`-only write, `select ... using
--    (true)` read for every authenticated identity" shape, not a second bespoke
--    mechanism. Every previously-existing UOM-shaped column in this repository
--    (`app.warehouse_zones.capacity_uom`, `app.warehouse_locations.capacity_uom`,
--    `app.actual_costs.uom`) stays exactly as-is (free text, unconstrained) -- this
--    migration edits no applied migration; retrofitting those columns to validate
--    against this new registry is disclosed as a deferred, real obligation for
--    whichever future capability first needs it, not silently done here.
-- 4. **`unit_category` is a closed, deliberately narrow CHECK enum** (`weight`,
--    `volume`, `count`, `length`) covering only genuinely fungible physical UOMs with
--    a fixed scalar conversion factor. Discrete handling/packaging units (box,
--    carton, pallet -- a "1 box = N pcs" ratio that varies per item, not a universal
--    physical constant) are deliberately **not** modelled here as a UOM -- that is
--    packaging/handling-unit identity, explicitly deferred to Prompt 237 ("WMS
--    Packing," whose own §13 already names "package/container hierarchy... material,
--    seal" as its own scope), not fabricated ahead of that capability's real
--    requirements.
-- 5. **`app.item_masters` does not itself carry an on-hand/allocated/available
--    quantity column.** Prompt 231 §24 ("Expected quantity is not on-hand inventory")
--    and Prompt 234 §24 ("normal roles never patch balance") both forbid it -- those
--    are `ATW-234`'s (Inventory Ledger) own derived-balance columns, never
--    duplicated onto the identity row itself.
-- 6. **Deactivation dependency-impact checking is disclosed as deferred, identical
--    boundary to `ATW-229`/`ATW-230`'s own design notes.** `app.set_item_master_status`
--    does not check for referencing inbound/receiving/ledger/lot rows, because no such
--    table exists yet at this checkpoint. `ATW-231` (or whichever future capability
--    first references an `app.item_masters` row) is the one obligated to wire a real
--    check before it lets a referenced item deactivate.
-- 7. **List reads are bounded (`p_limit`, default 50, max 200), never unbounded
--    `setof`** -- a disclosed, deliberate choice given the read-only audit's own
--    finding that no Phase 5 list RPC yet uses real keyset/cursor pagination; a fixed
--    bound is a strictly safer default than an unbounded `setof` while that shared
--    cursor convention remains unadopted repository-wide, not a claim that true
--    keyset pagination is unnecessary later.
-- 8. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. UOM registry (design note 3) -- global, not tenant-scoped, mirrors
-- app.finance_currencies exactly.
create table app.uoms (
  code text primary key,
  name text not null,
  unit_category text not null,
  is_active boolean not null default true,
  constraint uoms_code_format_check check (code ~ '^[A-Z][A-Z0-9_]{0,9}$'),
  constraint uoms_unit_category_check check (unit_category in ('weight', 'volume', 'count', 'length'))
);

comment on table app.uoms is
  'ATW-011A: the real, governed unit-of-measure registry every WMS/inventory quantity dimension resolves against -- mirrors app.finance_currencies (FIN-194) verbatim. unit_category is deliberately narrow (design note 4) -- discrete packaging/handling units (box/carton/pallet) are not a UOM here, deferred to Prompt 237.';

insert into app.uoms (code, name, unit_category) values
  ('KG', 'Kilogram', 'weight'),
  ('G', 'Gram', 'weight'),
  ('TON', 'Metric Ton', 'weight'),
  ('L', 'Litre', 'volume'),
  ('ML', 'Millilitre', 'volume'),
  ('M3', 'Cubic Metre', 'volume'),
  ('PCS', 'Piece', 'count'),
  ('DOZ', 'Dozen', 'count'),
  ('M', 'Metre', 'length'),
  ('CM', 'Centimetre', 'length');

create function app.validate_uom_code(p_code text)
returns boolean
language sql
stable
as $$
  select exists (select 1 from app.uoms where code = p_code and is_active);
$$;

comment on function app.validate_uom_code is
  'ATW-011A: real, governed UOM-code validation against app.uoms, mirroring app.validate_currency_code (PLT-119/FIN-194) verbatim.';

-- 2. UOM conversion factors -- global, same-category only (enforced below).
-- quantity_in(to_uom) = quantity_in(from_uom) * factor.
create table app.uom_conversions (
  id uuid primary key default gen_random_uuid(),
  from_uom_code text not null references app.uoms (code),
  to_uom_code text not null references app.uoms (code),
  factor numeric not null,
  constraint uom_conversions_distinct_codes_check check (from_uom_code <> to_uom_code),
  constraint uom_conversions_factor_positive_check check (factor > 0),
  constraint uom_conversions_unique unique (from_uom_code, to_uom_code)
);

comment on table app.uom_conversions is
  'ATW-011A: directed conversion factors between two app.uoms of the identical unit_category (app.uom_conversions_same_category_check below) -- app.convert_uom_quantity resolves either this row directly or its own inverse, never a third silently-derived path.';

create function app.uom_conversion_categories_match(p_from_uom_code text, p_to_uom_code text)
returns boolean
language sql
stable
as $$
  select (select unit_category from app.uoms where code = p_from_uom_code)
       = (select unit_category from app.uoms where code = p_to_uom_code);
$$;

comment on function app.uom_conversion_categories_match is
  'ATW-011A: true only when both UOM codes share the identical unit_category -- a STABLE (not VOLATILE) function, valid in a CHECK constraint per PostgreSQL''s own rule (the identical class of CHECK-constraint function FIN-194''s own app.validate_currency_code header already established).';

alter table app.uom_conversions
  add constraint uom_conversions_same_category_check
  check (app.uom_conversion_categories_match(from_uom_code, to_uom_code));

insert into app.uom_conversions (from_uom_code, to_uom_code, factor) values
  ('KG', 'G', 1000), ('G', 'KG', 0.001),
  ('TON', 'KG', 1000), ('KG', 'TON', 0.001),
  ('L', 'ML', 1000), ('ML', 'L', 0.001),
  ('M3', 'L', 1000), ('L', 'M3', 0.001),
  ('DOZ', 'PCS', 12), ('PCS', 'DOZ', 0.08333333333333333333),
  ('M', 'CM', 100), ('CM', 'M', 0.01);

create function app.convert_uom_quantity(p_quantity numeric, p_from_uom_code text, p_to_uom_code text)
returns numeric
language plpgsql
stable
as $$
declare
  v_factor numeric;
begin
  if p_from_uom_code = p_to_uom_code then
    return p_quantity;
  end if;

  select factor into v_factor from app.uom_conversions
    where from_uom_code = p_from_uom_code and to_uom_code = p_to_uom_code;
  if found then
    return p_quantity * v_factor;
  end if;

  select factor into v_factor from app.uom_conversions
    where from_uom_code = p_to_uom_code and to_uom_code = p_from_uom_code;
  if found then
    return p_quantity / v_factor;
  end if;

  raise exception 'uom_conversion_not_registered: no conversion path from % to %', p_from_uom_code, p_to_uom_code
    using errcode = 'no_data_found';
end;
$$;

comment on function app.convert_uom_quantity is
  'ATW-011A: exact-decimal quantity conversion via app.uom_conversions, resolving either a direct or an inverse row. Raises uom_conversion_not_registered rather than guessing when no path exists (e.g. across categories, or a genuinely unregistered pair) -- never a silent 1:1 fallback.';

-- 3. Item/SKU master (design notes 1-2/5-6) -- flat, typed-column, tenant + customer-
-- owner scoped, never built on app.master_records.
create table app.item_masters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  owner_account_id uuid not null references app.accounts (id),
  code text not null,
  name text not null,
  description text,
  base_uom_code text not null references app.uoms (code),
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint item_masters_code_check check (length(trim(code)) > 0),
  constraint item_masters_name_check check (length(trim(name)) > 0),
  constraint item_masters_status_check check (status in ('active', 'inactive')),
  constraint item_masters_code_unique unique (tenant_id, owner_account_id, code)
);

comment on table app.item_masters is
  'ATW-011A: the canonical item/SKU identity Prompt 231 (WMS Inbound) §9/§24 and Prompt 234 (Inventory Ledger) §9/§13 both require as an already-VERIFIED upstream. owner_account_id (design note 2) is mandatory -- a 3PL item always belongs to exactly one customer account. base_uom_code/owner_account_id/tenant_id are immutable once created (no RPC below ever changes them) -- changing an item''s own base UOM after real stock/ledger rows exist would corrupt historical quantities, and no ledger exists yet to migrate even if it did. Carries no on-hand/allocated/available column (design note 5) -- those are ATW-234''s own derived-balance columns.';

create index item_masters_tenant_status_idx on app.item_masters (tenant_id, status);
create index item_masters_tenant_owner_idx on app.item_masters (tenant_id, owner_account_id, status);

create function app.touch_item_masters_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger item_masters_touch_row
  before update on app.item_masters
  for each row
  execute function app.touch_item_masters_row();

-- 4. Item master mutations. Idempotent on (tenant_id, owner_account_id, code),
-- RBAC-gated (OPS:Create/Edit/View), tenant-wide scoped (design note 1 -- not
-- org-unit record-scoped, mirroring app.accounts/ADR-0018 exactly), and audited.

create function app.create_item_master(
  p_tenant_id uuid,
  p_owner_account_id uuid,
  p_code text,
  p_name text,
  p_description text,
  p_base_uom_code text,
  p_lot_controlled boolean,
  p_serial_controlled boolean,
  p_expiry_controlled boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.item_masters
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_existing app.item_masters;
  v_item app.item_masters;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_owner_account_id and tenant_id = p_tenant_id and status = 'active';
  if not found then
    raise exception 'owner_account_not_found: % is not an active account of tenant %', p_owner_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if not app.validate_uom_code(p_base_uom_code) then
    raise exception 'invalid_base_uom: % is not a registered active UOM code', p_base_uom_code using errcode = 'check_violation';
  end if;

  select * into v_existing from app.item_masters
    where tenant_id = p_tenant_id and owner_account_id = p_owner_account_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.item_masters (
      tenant_id, owner_account_id, code, name, description, base_uom_code,
      lot_controlled, serial_controlled, expiry_controlled, created_by
    ) values (
      p_tenant_id, p_owner_account_id, p_code, p_name, p_description, p_base_uom_code,
      coalesce(p_lot_controlled, false), coalesce(p_serial_controlled, false), coalesce(p_expiry_controlled, false), p_actor_label
    )
    returning * into v_item;
  exception
    when unique_violation then
      select * into v_item from app.item_masters
        where tenant_id = p_tenant_id and owner_account_id = p_owner_account_id and code = p_code;
      if found then
        return v_item;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_item_master',
    'app.item_masters', v_item.id, 'success', null, null,
    jsonb_build_object('code', p_code, 'name', p_name, 'owner_account_id', p_owner_account_id, 'base_uom_code', p_base_uom_code)
  );

  return v_item;
end;
$$;

comment on function app.create_item_master is
  'ATW-011A: idempotent on (tenant_id, owner_account_id, code) -- a same-code retry under the same owner returns the identical row. owner_account_id must reference an active (non-merged) app.accounts row of the same tenant; base_uom_code must be a registered active app.uoms code.';

create function app.update_item_master(
  p_item_master_id uuid,
  p_name text,
  p_description text,
  p_lot_controlled boolean,
  p_serial_controlled boolean,
  p_expiry_controlled boolean,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.item_masters
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  update app.item_masters set
    name = p_name,
    description = p_description,
    lot_controlled = coalesce(p_lot_controlled, false),
    serial_controlled = coalesce(p_serial_controlled, false),
    expiry_controlled = coalesce(p_expiry_controlled, false)
  where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_item_master',
    'app.item_masters', v_item.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'lot_controlled', v_item.lot_controlled, 'serial_controlled', v_item.serial_controlled, 'expiry_controlled', v_item.expiry_controlled)
  );

  return v_item;
end;
$$;

comment on function app.update_item_master is
  'ATW-011A: mutable fields only -- code, tenant_id, owner_account_id and base_uom_code are immutable once created (no re-parenting/re-UOM path exists). Optimistic-concurrency gated (record_version). Control-flag flips (lot/serial/expiry) are unguarded here since no ledger/lot table exists yet to reference them -- ATW-235''s own obligation to guard a flip against already-tracked stock, disclosed, not silently permitted forever.';

create function app.set_item_master_status(
  p_item_master_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.item_masters
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid item master status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if v_item.status = p_new_status then
    return v_item;
  end if;
  if p_new_status = 'inactive' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a reason is required to deactivate an item master' using errcode = 'check_violation';
  end if;

  update app.item_masters set status = p_new_status where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_item_master_status',
    'app.item_masters', v_item.id, 'success', p_reason, null,
    jsonb_build_object('new_status', p_new_status)
  );

  return v_item;
end;
$$;

comment on function app.set_item_master_status is
  'ATW-011A: does not check for referencing inbound/receiving/ledger/lot rows (design note 6) -- none exist yet at this checkpoint. ATW-231, or whichever future capability first references an app.item_masters row, is obligated to wire a real dependency check before it lets a referenced item deactivate.';

create function app.get_item_master(p_item_master_id uuid, p_actor_auth_user_id uuid)
returns app.item_masters
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_item;
end;
$$;

comment on function app.get_item_master is
  'ATW-011A: single-row read by id, RBAC-gated (OPS:View).';

create function app.resolve_item_master_by_code(p_tenant_id uuid, p_owner_account_id uuid, p_code text, p_actor_auth_user_id uuid)
returns app.item_masters
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_item from app.item_masters
    where tenant_id = p_tenant_id and owner_account_id = p_owner_account_id and code = p_code;
  if not found then
    raise exception 'item_master_not_found: no item % for owner % in tenant %', p_code, p_owner_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  return v_item;
end;
$$;

comment on function app.resolve_item_master_by_code is
  'ATW-011A: the exact-code lookup Prompt 231 (WMS Inbound) is expected to call when inheriting an item identity from a source shipment/customer reference, honestly not-found rather than a silent null.';

create function app.list_item_masters(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_search text default null,
  p_limit integer default 50
)
returns setof app.item_masters
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.item_masters m
  where m.tenant_id = p_tenant_id
    and (p_owner_account_id is null or m.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or m.status = p_status_filter)
    and (p_search is null or m.code ilike '%' || p_search || '%' or m.name ilike '%' || p_search || '%')
  order by m.code
  limit v_limit;
end;
$$;

comment on function app.list_item_masters is
  'ATW-011A: bounded read (design note 7) -- p_limit default 50, hard-capped 200. Tenant-wide, optionally narrowed to one owner_account_id.';

-- 5. RLS -- tenant-wide for item masters (design note 1, mirrors app.accounts/
-- ADR-0018 exactly); globally readable for the UOM registry (design note 3, mirrors
-- app.finance_currencies exactly).

alter table app.item_masters enable row level security;

create policy item_masters_select_scoped on app.item_masters
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

alter table app.uoms enable row level security;

create policy uoms_select_authenticated on app.uoms
  for select to authenticated
  using (true);

alter table app.uom_conversions enable row level security;

create policy uom_conversions_select_authenticated on app.uom_conversions
  for select to authenticated
  using (true);

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.item_masters, app.uoms, app.uom_conversions to authenticated, service_role;
grant insert, update, delete on app.item_masters to service_role;
grant insert, update, delete on app.uoms, app.uom_conversions to service_role;

grant execute on function app.validate_uom_code(text) to authenticated, service_role;
grant execute on function app.uom_conversion_categories_match(text, text) to authenticated, service_role;
grant execute on function app.convert_uom_quantity(numeric, text, text) to authenticated, service_role;
grant execute on function app.create_item_master(uuid, uuid, text, text, text, text, boolean, boolean, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.update_item_master(uuid, text, text, boolean, boolean, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_item_master_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_item_master(uuid, uuid) to authenticated, service_role;
grant execute on function app.resolve_item_master_by_code(uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.list_item_masters(uuid, uuid, uuid, text, text, integer) to authenticated, service_role;
