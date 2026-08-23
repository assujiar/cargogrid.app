-- Advanced TMS/WMS capability ATW-016 (CG-S10-ATW-016, Prompt 235, "Lot, Batch,
-- Serial and Expiry" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- §1). Implements this prompt's own §4 objective: "configurable lot/batch/serial/
-- expiry dimensions and allocation rules only where item/customer policy requires
-- them."
--
-- Direct upstream: ATW-011A (app.item_masters' own lot_controlled/serial_controlled/
-- expiry_controlled flags -- the base, already-VERIFIED signal this migration composes
-- with, never re-litigates or duplicates), ATW-015 (app.inventory_movement_lines/
-- app.inventory_balances' own plain, nullable lot_number/serial_number/expiry_date
-- columns -- this migration's own governance layer over them), ATW-013 (app.
-- wms_receipt_lines' own caller-supplied capture-time text, validated only for
-- presence when controlled).
--
-- Design boundary (disclosed):
--
-- 1. **A versioned item/owner control-policy table (`app.item_control_policy_versions`)
--    scoped by `item_master_id`** (which already fixes exactly one `tenant_id`/
--    `owner_account_id`, `ATW-011A`'s own unique-per-owner shape) -- draft/published/
--    archived lifecycle, one published row per item at a time (a partial unique index,
--    the identical mechanism `app.margin_rule_versions`/`app.publish_margin_rule_
--    version`, `COM-150`, already established and reused verbatim here, including its
--    own `p_supersedes_version_id` archive-then-publish shape). This table carries
--    only the genuinely NEW policy surface Prompt 235 §13/§24 names -- `allocation_rule`
--    (fifo/fefo), `hold_on_unknown_lot` (the default-hold-on-unregistered-identity
--    behavor), and `near_expiry_warning_days` (a FEFO/near-expiry decision-support
--    threshold) -- it never stores a second copy of `lot_controlled`/`serial_
--    controlled`/`expiry_controlled`; every register/publish RPC below reads those
--    flags live off `app.item_masters` and rejects a field this policy or a lot/serial
--    registration would otherwise store when the item's own flag says it is
--    irrelevant (Prompt 235 §33 "uncontrolled items avoid unnecessary fields" --
--    `item_not_lot_controlled`/`item_not_serial_controlled`/`invalid_allocation_rule`
--    (fefo requires an expiry-controlled item)/`invalid_near_expiry_warning_days`).
-- 2. **`app.lot_identities` is the real lot/batch identity registry** -- uniqueness
--    scope `(tenant_id, owner_account_id, item_master_id, lot_number)`, mirroring
--    `app.item_masters`' own owner-scoped uniqueness precedent exactly. Registering an
--    already-known lot number is a real, natural-key idempotent no-op (mirrors `app.
--    create_item_master` exactly, including the identical nested `begin/exception`
--    `unique_violation` recovery, design lesson (d)) -- a lot number legitimately
--    refers to the same physical batch across every unit within it, so "duplicate lot"
--    is not a business error the way "duplicate serial" is. `parent_lot_id` (nullable,
--    self-referencing) is the disclosed, bounded genealogy reference Prompt 235 §13
--    names -- one parent link per lot, set only at registration with `source_type =
--    'split'`, structurally required to share the identical `tenant_id`/
--    `owner_account_id`/`item_master_id` as its child (`genealogy_mismatch`
--    otherwise). No multi-generation graph-traversal API is built over it -- a real,
--    bounded feature, not the larger one.
-- 3. **`app.serial_identities` carries REAL uniqueness in governed scope** -- a genuine
--    unique index `(tenant_id, item_master_id, serial_number)`, structurally
--    Postgres-enforced (the fifth adversarial-review lesson `ATW-014`'s own header
--    names: a real unique constraint, not merely a cross-row aggregate/on-hand<=1
--    check, so Postgres itself serializes two concurrent callers registering the
--    identical serial -- `app.post_inventory_movement`'s own bounded on-hand<=1
--    `serial_conflict` check, ATW-015, stays exactly as-is, unmodified, a separate
--    layer). Distinct from lot registration, a serial is registered with its own real
--    `idempotency_key` (a real unique `(tenant_id, idempotency_key)` constraint, the
--    same "idempotency is a real unique constraint on a created-once row" convention
--    `app.wms_receipt_sessions`/`app.wms_putaway_tasks` already established) -- a
--    same-key retry (a genuine race, or a client resend) returns the identical row
--    unchanged; a DIFFERENT idempotency key attempting to register the identical
--    `(tenant_id, item_master_id, serial_number)` natural key is the real, structural
--    `duplicate_serial` rejection Prompt 235 §33 requires ("duplicate-serial stock
--    cannot be allocated silently") -- disambiguated in `app.register_serial_identity`'s
--    own `unique_violation` handler by re-selecting on the idempotency key first
--    (a race/retry) before concluding the natural key itself is what tripped (a real
--    duplicate).
-- 4. **Status/hold lifecycle is one generic transition RPC per identity type**
--    (`app.set_lot_identity_status`/`app.set_serial_identity_status`, covering
--    `active`/`held`/`quarantined`/`expired`/`consumed`), `OPS:Override`-gated
--    (Prompt 235 §26 "supervisors hold/release/override") -- mirrors `app.set_item_
--    master_status`/`app.set_warehouse_location_status`'s own established
--    generic-status-transition shape exactly, rather than four separate hold/release/
--    quarantine/expire functions. `consumed` is terminal (no further transition out of
--    it) -- a reason is required for every non-`active` target status.
-- 5. **No scheduler/cron marks a lot/serial `expired` automatically** -- this
--    repository has no scheduler/worker runtime yet (`ISS-2026-015`, the identical
--    disclosed boundary `ATW-014`'s own design note 9 already used). Instead, the
--    FIFO/FEFO candidate query (`app.list_allocation_candidates`) structurally
--    excludes any lot/serial whose `expiry_date` has already passed REGARDLESS of its
--    stored `status` -- Prompt 235 §33's "expired stock cannot be allocated silently"
--    holds even for a lot nobody has yet run `set_lot_identity_status(..., 'expired')`
--    against.
-- 6. **Live wiring into `app.commit_wms_receipt_line`/`app.record_wms_receipt_line_
--    count` (ATW-013, an already-applied migration) is deliberately NOT done --
--    mechanism proven, live wiring deferred, the identical disclosed boundary `ATW-012`'s
--    own design note 9 already used.** `app.register_lot_identity`/`app.register_
--    serial_identity` are real, independently-callable RPCs a caller (a future WMS
--    capture flow, or this migration's own db-test fixture) invokes explicitly after a
--    physical receipt/count. This was a deliberate, reasoned choice, not an oversight:
--    ATW-013's own `wms_receipt_lines`/`inventory_movement_lines` rows already exist
--    today with plain, unregistered lot/serial text (the already-passing ATW-013/
--    ATW-015 db-test fixtures prove this), so silently requiring registration inside an
--    already-`VERIFIED` capture path risks breaking a real, already-proven flow for a
--    benefit (auto-registration) achievable just as well by a caller-visible, optional
--    RPC call -- and per the standing convention, `app.commit_wms_receipt_line`'s own
--    already-applied migration file is never edited; only a same-signature `CREATE OR
--    REPLACE` widening was even structurally available, and the risk of it silently
--    changing already-verified behavior (e.g. requiring `OPS:Create`, which the
--    ATW-013 db-test's own receiving actor may not separately hold, in addition to the
--    `OPS:Edit` it already checks) outweighed the benefit here. A direct, disclosed
--    consequence: `app.list_allocation_candidates` can only exclude a held/expired lot
--    or serial for a balance dimension that HAS been explicitly registered through
--    this capability's own RPC -- a balance whose lot/serial predates registration is
--    not (and structurally cannot be) excluded on hold/status grounds, only on its own
--    real `expiry_date` once registered.
-- 7. **The FIFO/FEFO candidate query is real decision support, never authoritative
--    allocation** (Prompt 235 §24 verbatim) -- a read-only `stable` function, no
--    reservation/consumption side effect. FIFO orders by the identity's own
--    registration `created_at` (the closest real proxy this repository has for
--    "received first" without a strict per-balance received-at ledger timestamp that
--    survives a transfer/putaway -- a disclosed, reasoned simplification, the same
--    class of bounded default `ATW-230`'s own `app.warehouse_location_max_depth()`
--    already used without a fresh ADR); FEFO orders by `expiry_date` ascending, nulls
--    last. Real allocation/reservation execution stays exclusively `app.reserve_
--    inventory`/`app.consume_inventory_reservation` (ATW-015), never rebuilt or
--    modified here -- ATW-236 (Picking)'s own scope.
-- 8. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Versioned item/owner control policy (design note 1).
create table app.item_control_policy_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  item_master_id uuid not null references app.item_masters (id),
  owner_account_id uuid not null references app.accounts (id),
  allocation_rule text not null default 'fifo',
  hold_on_unknown_lot boolean not null default true,
  near_expiry_warning_days integer,
  status text not null default 'draft',
  supersedes_version_id uuid references app.item_control_policy_versions (id),
  effective_from timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint item_control_policy_versions_allocation_rule_check check (allocation_rule in ('fifo', 'fefo')),
  constraint item_control_policy_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint item_control_policy_versions_near_expiry_check check (near_expiry_warning_days is null or near_expiry_warning_days >= 0),
  constraint item_control_policy_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.item_control_policy_versions is
  'ATW-016: a versioned, per-item control policy composing with (never duplicating) app.item_masters'' own lot_controlled/serial_controlled/expiry_controlled flags (design note 1). Editing a published policy in place is never allowed -- app.publish_item_control_policy_version''s p_supersedes_version_id parameter archives the prior published version and links the new one, mirroring app.publish_margin_rule_version (COM-150) exactly.';

create unique index item_control_policy_versions_item_published_unique on app.item_control_policy_versions (item_master_id) where status = 'published';
create index item_control_policy_versions_tenant_item_idx on app.item_control_policy_versions (tenant_id, item_master_id, status);

-- 2. Lot/batch identity registry (design note 2).
create table app.lot_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  lot_number text not null,
  manufacture_date date,
  expiry_date date,
  status text not null default 'active',
  hold_reason text,
  parent_lot_id uuid references app.lot_identities (id),
  source_type text not null default 'receipt',
  source_id uuid,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lot_identities_lot_number_check check (length(trim(lot_number)) > 0),
  constraint lot_identities_status_check check (status in ('active', 'held', 'quarantined', 'expired', 'consumed')),
  constraint lot_identities_source_type_check check (source_type in ('receipt', 'manual', 'split')),
  constraint lot_identities_date_order_check check (manufacture_date is null or expiry_date is null or expiry_date >= manufacture_date),
  constraint lot_identities_hold_reason_check check (status not in ('held', 'quarantined', 'expired') or (hold_reason is not null and length(trim(hold_reason)) > 0)),
  constraint lot_identities_not_self_parent check (parent_lot_id is null or parent_lot_id <> id),
  constraint lot_identities_unique unique (tenant_id, owner_account_id, item_master_id, lot_number)
);

comment on table app.lot_identities is
  'ATW-016: the real lot/batch identity registry (design note 2), never storing more than a real, bounded parent_lot_id genealogy reference. Registration is idempotent on the natural key (tenant_id, owner_account_id, item_master_id, lot_number) -- a repeat registration of an already-known lot is not an error.';

create index lot_identities_tenant_item_status_idx on app.lot_identities (tenant_id, item_master_id, status);
create index lot_identities_tenant_expiry_idx on app.lot_identities (tenant_id, item_master_id, expiry_date);

create function app.touch_lot_identities_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger lot_identities_touch_row
  before update on app.lot_identities
  for each row
  execute function app.touch_lot_identities_row();

-- 3. Serial identity registry -- real uniqueness in governed scope (design note 3).
create table app.serial_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  serial_number text not null,
  lot_number text,
  manufacture_date date,
  expiry_date date,
  status text not null default 'active',
  hold_reason text,
  source_type text not null default 'receipt',
  source_id uuid,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint serial_identities_serial_number_check check (length(trim(serial_number)) > 0),
  constraint serial_identities_status_check check (status in ('active', 'held', 'quarantined', 'expired', 'consumed')),
  constraint serial_identities_source_type_check check (source_type in ('receipt', 'manual')),
  constraint serial_identities_date_order_check check (manufacture_date is null or expiry_date is null or expiry_date >= manufacture_date),
  constraint serial_identities_hold_reason_check check (status not in ('held', 'quarantined', 'expired') or (hold_reason is not null and length(trim(hold_reason)) > 0)),
  constraint serial_identities_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint serial_identities_governed_scope_unique unique (tenant_id, item_master_id, serial_number)
);

comment on table app.serial_identities is
  'ATW-016: REAL uniqueness in governed scope -- serial_identities_governed_scope_unique (tenant_id, item_master_id, serial_number), structurally Postgres-enforced (design note 3), distinct from and never replacing app.post_inventory_movement''s own bounded on-hand<=1 serial_conflict check (ATW-015, unmodified). idempotency_key is a SEPARATE real unique constraint (mirrors app.wms_receipt_sessions) -- a same-key retry replays the identical row; a different key colliding on the governed-scope natural key is a genuine duplicate_serial rejection.';

create index serial_identities_tenant_item_status_idx on app.serial_identities (tenant_id, item_master_id, status);

create function app.touch_serial_identities_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger serial_identities_touch_row
  before update on app.serial_identities
  for each row
  execute function app.touch_serial_identities_row();

-- 4. Control policy version mutations. Tenant-wide RBAC/scope (mirrors app.item_masters,
-- design note 1) -- never warehouse-record-scoped, since an item/owner policy is not a
-- warehouse operational record.

create function app.create_item_control_policy_version_draft(
  p_item_master_id uuid,
  p_allocation_rule text,
  p_hold_on_unknown_lot boolean,
  p_near_expiry_warning_days integer,
  p_effective_from timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.item_control_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_rule text;
  v_policy app.item_control_policy_versions;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_rule := coalesce(p_allocation_rule, 'fifo');
  if v_rule not in ('fifo', 'fefo') then
    raise exception 'invalid_allocation_rule: % is not a recognized allocation rule', v_rule using errcode = 'check_violation';
  end if;
  if v_rule = 'fefo' and not v_item.expiry_controlled then
    raise exception 'invalid_allocation_rule: fefo requires item % to be expiry-controlled', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_near_expiry_warning_days is not null and not v_item.expiry_controlled then
    raise exception 'invalid_near_expiry_warning_days: item % is not expiry-controlled -- near_expiry_warning_days is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_near_expiry_warning_days is not null and p_near_expiry_warning_days < 0 then
    raise exception 'invalid_near_expiry_warning_days: % must be non-negative', p_near_expiry_warning_days using errcode = 'check_violation';
  end if;

  insert into app.item_control_policy_versions (
    tenant_id, item_master_id, owner_account_id, allocation_rule, hold_on_unknown_lot, near_expiry_warning_days, effective_from, created_by
  ) values (
    v_item.tenant_id, p_item_master_id, v_item.owner_account_id, v_rule, coalesce(p_hold_on_unknown_lot, true), p_near_expiry_warning_days, coalesce(p_effective_from, now()), p_actor_label
  )
  returning * into v_policy;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_item_control_policy_version_draft',
    'app.item_control_policy_versions', v_policy.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'allocation_rule', v_rule, 'hold_on_unknown_lot', v_policy.hold_on_unknown_lot)
  );

  return v_policy;
end;
$$;

comment on function app.create_item_control_policy_version_draft is
  'ATW-016: rejects fefo/near_expiry_warning_days when the item is not expiry-controlled (design note 1, Prompt 235 section 33 "uncontrolled items avoid unnecessary fields") -- reads app.item_masters'' own flags live, never a second stored copy.';

create function app.publish_item_control_policy_version(
  p_policy_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.item_control_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.item_control_policy_versions;
  v_superseded app.item_control_policy_versions;
begin
  select * into v_policy from app.item_control_policy_versions where id = p_policy_version_id;
  if not found then
    raise exception 'policy_version_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_policy_version_id, p_expected_version, v_policy.record_version
      using errcode = 'check_violation';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is % and cannot be published', p_policy_version_id, v_policy.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.item_control_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_policy_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.item_master_id <> v_policy.item_master_id then
      raise exception 'invalid_supersede: superseded policy must share the same item_master_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded policy % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.item_control_policy_versions set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.item_control_policy_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_policy_version_id and record_version = p_expected_version
    returning * into v_policy;
  exception
    when unique_violation then
      raise exception 'active_policy_exists: item % already has a published control policy -- supply p_supersedes_version_id to replace it', v_policy.item_master_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_item_control_policy_version',
    'app.item_control_policy_versions', v_policy.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_policy;
end;
$$;

comment on function app.publish_item_control_policy_version is
  'ATW-016: OPS:Override-gated (a governance action, mirrors app.publish_margin_rule_version''s own COM:Approve). draft -> published, archiving p_supersedes_version_id first so at most one published policy ever exists per item (item_control_policy_versions_item_published_unique).';

-- 5. Lot/serial identity registration (design notes 2/3/6).

create function app.register_lot_identity(
  p_item_master_id uuid,
  p_lot_number text,
  p_manufacture_date date,
  p_expiry_date date,
  p_source_type text,
  p_source_id uuid,
  p_parent_lot_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.lot_identities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_existing app.lot_identities;
  v_parent app.lot_identities;
  v_policy app.item_control_policy_versions;
  v_hold_default boolean;
  v_status text;
  v_hold_reason text;
  v_lot app.lot_identities;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay by natural key -- only after authority is confirmed above,
  -- never before.
  select * into v_existing from app.lot_identities
    where tenant_id = v_item.tenant_id and owner_account_id = v_item.owner_account_id and item_master_id = p_item_master_id and lot_number = p_lot_number;
  if found then
    return v_existing;
  end if;

  if not v_item.lot_controlled then
    raise exception 'item_not_lot_controlled: item % is not lot-controlled -- a lot identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_lot_number is null or length(trim(p_lot_number)) = 0 then
    raise exception 'invalid_lot_number: a lot number is required' using errcode = 'check_violation';
  end if;
  if coalesce(p_source_type, 'receipt') not in ('receipt', 'manual', 'split') then
    raise exception 'invalid_source_type: % is not a recognized lot source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_manufacture_date is not null and p_expiry_date is not null and p_expiry_date < p_manufacture_date then
    raise exception 'invalid_date_order: expiry_date % precedes manufacture_date %', p_expiry_date, p_manufacture_date using errcode = 'check_violation';
  end if;
  if p_expiry_date is not null and not v_item.expiry_controlled then
    raise exception 'expiry_date_not_applicable: item % is not expiry-controlled -- an expiry date is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;

  if p_parent_lot_id is not null then
    if coalesce(p_source_type, 'receipt') <> 'split' then
      raise exception 'genealogy_mismatch: a parent_lot_id may only be set when source_type is split' using errcode = 'check_violation';
    end if;
    select * into v_parent from app.lot_identities where id = p_parent_lot_id;
    if not found then
      raise exception 'parent_lot_not_found: %', p_parent_lot_id using errcode = 'no_data_found';
    end if;
    if v_parent.tenant_id <> v_item.tenant_id or v_parent.owner_account_id <> v_item.owner_account_id or v_parent.item_master_id <> p_item_master_id then
      raise exception 'genealogy_mismatch: parent lot % does not share the same tenant/owner/item as the new lot', p_parent_lot_id using errcode = 'check_violation';
    end if;
  end if;

  select * into v_policy from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  v_hold_default := coalesce(v_policy.hold_on_unknown_lot, true);
  if v_hold_default then
    v_status := 'held';
    v_hold_reason := 'hold_on_unknown_lot_policy_default';
  else
    v_status := 'active';
    v_hold_reason := null;
  end if;

  begin
    insert into app.lot_identities (
      tenant_id, owner_account_id, item_master_id, lot_number, manufacture_date, expiry_date, status, hold_reason,
      parent_lot_id, source_type, source_id, created_by
    ) values (
      v_item.tenant_id, v_item.owner_account_id, p_item_master_id, p_lot_number, p_manufacture_date, p_expiry_date, v_status, v_hold_reason,
      p_parent_lot_id, coalesce(p_source_type, 'receipt'), p_source_id, p_actor_label
    )
    returning * into v_lot;
  exception
    when unique_violation then
      select * into v_existing from app.lot_identities
        where tenant_id = v_item.tenant_id and owner_account_id = v_item.owner_account_id and item_master_id = p_item_master_id and lot_number = p_lot_number;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_lot_identity',
    'app.lot_identities', v_lot.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'lot_number', p_lot_number, 'status', v_status)
  );

  return v_lot;
end;
$$;

comment on function app.register_lot_identity is
  'ATW-016: idempotent by natural key (tenant_id, owner_account_id, item_master_id, lot_number), including under a genuine race (unique_violation handler re-selects, mirrors app.create_item_master). Defaults to status=held when the item''s published control policy''s own hold_on_unknown_lot is true (or no policy is published at all -- a safe default, Prompt 235 section 19 "unknown lot remains explicitly blocked/held per policy").';

create function app.register_serial_identity(
  p_item_master_id uuid,
  p_serial_number text,
  p_lot_number text,
  p_manufacture_date date,
  p_expiry_date date,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.serial_identities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_existing app.serial_identities;
  v_policy app.item_control_policy_versions;
  v_hold_default boolean;
  v_status text;
  v_hold_reason text;
  v_serial app.serial_identities;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to register a serial identity' using errcode = 'check_violation';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before.
  select * into v_existing from app.serial_identities where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if not v_item.serial_controlled then
    raise exception 'item_not_serial_controlled: item % is not serial-controlled -- a serial identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_serial_number is null or length(trim(p_serial_number)) = 0 then
    raise exception 'invalid_serial_number: a serial number is required' using errcode = 'check_violation';
  end if;
  if coalesce(p_source_type, 'receipt') not in ('receipt', 'manual') then
    raise exception 'invalid_source_type: % is not a recognized serial source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_lot_number is not null and not v_item.lot_controlled then
    raise exception 'item_not_lot_controlled: item % is not lot-controlled -- a lot_number on a serial identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_manufacture_date is not null and p_expiry_date is not null and p_expiry_date < p_manufacture_date then
    raise exception 'invalid_date_order: expiry_date % precedes manufacture_date %', p_expiry_date, p_manufacture_date using errcode = 'check_violation';
  end if;
  if p_expiry_date is not null and not v_item.expiry_controlled then
    raise exception 'expiry_date_not_applicable: item % is not expiry-controlled -- an expiry date is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;

  select * into v_policy from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  v_hold_default := coalesce(v_policy.hold_on_unknown_lot, true);
  if v_hold_default then
    v_status := 'held';
    v_hold_reason := 'hold_on_unknown_lot_policy_default';
  else
    v_status := 'active';
    v_hold_reason := null;
  end if;

  begin
    insert into app.serial_identities (
      tenant_id, owner_account_id, item_master_id, serial_number, lot_number, manufacture_date, expiry_date, status, hold_reason,
      source_type, source_id, idempotency_key, created_by
    ) values (
      v_item.tenant_id, v_item.owner_account_id, p_item_master_id, p_serial_number, p_lot_number, p_manufacture_date, p_expiry_date, v_status, v_hold_reason,
      coalesce(p_source_type, 'receipt'), p_source_id, p_idempotency_key, p_actor_label
    )
    returning * into v_serial;
  exception
    when unique_violation then
      -- Design note 3: disambiguate a race on idempotency_key (re-select and return
      -- the winner, the real idempotent-replay guarantee) from a genuine duplicate
      -- serial tripping the separate governed-scope natural-key unique index.
      select * into v_existing from app.serial_identities where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise exception 'duplicate_serial: serial % is already registered for item % (owner %) in tenant %', p_serial_number, p_item_master_id, v_item.owner_account_id, v_item.tenant_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_serial_identity',
    'app.serial_identities', v_serial.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'serial_number', p_serial_number, 'status', v_status)
  );

  return v_serial;
end;
$$;

comment on function app.register_serial_identity is
  'ATW-016: idempotent on (tenant_id, idempotency_key) -- a same-key retry returns the identical row, never re-inserted or double-counted. A DIFFERENT idempotency key colliding on the real governed-scope unique index (tenant_id, item_master_id, serial_number) is rejected duplicate_serial (design note 3) -- the structural, Postgres-enforced rejection Prompt 235 section 33 requires, distinct from app.post_inventory_movement''s own bounded on-hand<=1 check (ATW-015, unmodified).';

-- 6. Status/hold lifecycle -- one generic transition RPC per identity type (design
-- note 4), OPS:Override-gated (Prompt 235 section 26 "supervisors hold/release/
-- override").

create function app.set_lot_identity_status(
  p_lot_identity_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.lot_identities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_lot app.lot_identities;
begin
  if p_new_status not in ('active', 'held', 'quarantined', 'expired', 'consumed') then
    raise exception 'invalid_status: % is not a recognized lot identity status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_lot from app.lot_identities where id = p_lot_identity_id for update;
  if not found then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_lot.status = p_new_status then
    return v_lot;
  end if;

  if v_lot.record_version <> p_expected_version then
    raise exception 'stale_version: lot identity % expected version % but found %', p_lot_identity_id, p_expected_version, v_lot.record_version using errcode = 'check_violation';
  end if;
  if v_lot.status = 'consumed' then
    raise exception 'invalid_transition: lot identity % is consumed -- a terminal status, no further transition is permitted', p_lot_identity_id using errcode = 'check_violation';
  end if;
  if p_new_status <> 'active' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required to set lot identity status to %', p_new_status using errcode = 'check_violation';
  end if;

  update app.lot_identities set
    status = p_new_status,
    hold_reason = (case when p_new_status = 'active' then null else p_reason end)
  where id = p_lot_identity_id
  returning * into v_lot;

  perform app.capture_audit_event(
    v_lot.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_lot_identity_status',
    'app.lot_identities', v_lot.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_lot;
end;
$$;

comment on function app.set_lot_identity_status is
  'ATW-016: the one generic hold/release/quarantine/expire/reactivate transition (design note 4), OPS:Override-gated. consumed is terminal. Row-locked (SELECT ... FOR UPDATE) on its first read; idempotent no-op on an already-target-status row, but only after authority is confirmed -- never before.';

create function app.set_serial_identity_status(
  p_serial_identity_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.serial_identities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_serial app.serial_identities;
begin
  if p_new_status not in ('active', 'held', 'quarantined', 'expired', 'consumed') then
    raise exception 'invalid_status: % is not a recognized serial identity status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_serial from app.serial_identities where id = p_serial_identity_id for update;
  if not found then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_serial.status = p_new_status then
    return v_serial;
  end if;

  if v_serial.record_version <> p_expected_version then
    raise exception 'stale_version: serial identity % expected version % but found %', p_serial_identity_id, p_expected_version, v_serial.record_version using errcode = 'check_violation';
  end if;
  if v_serial.status = 'consumed' then
    raise exception 'invalid_transition: serial identity % is consumed -- a terminal status, no further transition is permitted', p_serial_identity_id using errcode = 'check_violation';
  end if;
  if p_new_status <> 'active' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required to set serial identity status to %', p_new_status using errcode = 'check_violation';
  end if;

  update app.serial_identities set
    status = p_new_status,
    hold_reason = (case when p_new_status = 'active' then null else p_reason end)
  where id = p_serial_identity_id
  returning * into v_serial;

  perform app.capture_audit_event(
    v_serial.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_serial_identity_status',
    'app.serial_identities', v_serial.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_serial;
end;
$$;

comment on function app.set_serial_identity_status is
  'ATW-016: mirrors app.set_lot_identity_status exactly for serial identities.';

-- 6b. Owner-account read scoping (Prompt 235 section 26: "customers see only their
-- owner-scoped permitted trace data"; section 27: "cross-owner attempts"). None of this
-- migration's own owner-scoped tables (app.item_control_policy_versions/app.lot_
-- identities/app.serial_identities, all keyed by a real owner_account_id uuid FK to
-- app.accounts, ATW-011A's own established shape) previously restricted a read by owner
-- at all -- every read RPC below gated solely on tenant-wide OPS:View, so any actor
-- holding that permission could read every owner's data in the tenant, including a
-- customer_user-layer actor who is supposed to be confined to their own account.
--
-- No existing mechanism in this repository resolves "which app.accounts row(s) can this
-- actor see" today: app.principal_memberships.customer_account_ref (PLT-108) is
-- documented at its own point of definition as "a reserved scope-dimension placeholder
-- (free-text external reference), not a live foreign key" -- deliberately left for a
-- later, real capability to give it concrete meaning, since PLT-108 itself pre-dates
-- app.accounts entirely. This is that capability: the disclosed, minimal convention
-- adopted here is that a customer_user membership's own customer_account_ref, when it is
-- being used to scope this migration's owner_account_id-keyed tables, is the owning
-- app.accounts row's own id in text form -- no new column, no new linking table, and no
-- edit to any already-applied migration (app.accounts' own creation RPC, COM-149, is
-- never touched). This is intentionally narrower than "any free-text ref" -- only a
-- syntactically real uuid-shaped customer_account_ref is ever resolved against
-- app.accounts, so this migration's own convention can never collide with a different
-- capability's unrelated, human-entered customer_account_ref label (e.g. app.files',
-- ATW-119, or app.sales_plans', COM-146, which stay exactly as-is, unmodified).
create function app.resolve_actor_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select case
    -- Supreme Admin and any staff (tenant_admin/org_user) membership in this tenant see
    -- every owner, exactly as today -- "staff/tenant-wide actors ... continue to see
    -- tenant-wide."  An actor with no principal_memberships row at all in this tenant
    -- also falls through unrestricted here -- RBAC (OPS:View) remains the real gate for
    -- that case, unchanged from this migration's own pre-existing behavior; only an
    -- actor explicitly holding a customer_user membership is ever narrowed.
    when app.is_supreme_admin(p_auth_user_id) then null
    when exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id
        and layer in ('tenant_admin', 'org_user') and status = 'active'
    ) then null
    when exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id
        and layer = 'customer_user' and status = 'active'
    ) then coalesce((
      select array_agg(distinct pm.customer_account_ref::uuid)
      from app.principal_memberships pm
      where pm.auth_user_id = p_auth_user_id and pm.tenant_id = p_tenant_id
        and pm.layer = 'customer_user' and pm.status = 'active'
        and pm.customer_account_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ), array[]::uuid[])
    else null
  end;
$$;

comment on function app.resolve_actor_owner_account_scope is
  'ATW-016: null means unrestricted/tenant-wide (staff, Supreme Admin, or no principal membership at all in this tenant); a real (possibly empty) uuid[] means the actor is a customer_user-layer, owner-scoped actor and may only see rows whose owner_account_id is in that array. See design note 6b for the customer_account_ref=owner_account_id::text convention this resolves against.';

create function app.actor_can_view_owner_scoped_row(p_auth_user_id uuid, p_tenant_id uuid, p_owner_account_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  v_scope := app.resolve_actor_owner_account_scope(p_auth_user_id, p_tenant_id);
  return v_scope is null or p_owner_account_id = any(v_scope);
end;
$$;

comment on function app.actor_can_view_owner_scoped_row is
  'ATW-016: the single boolean predicate every owner-scoped read RPC below AND this migration''s own RLS SELECT policies (design note 3) share -- one source of truth for "can this actor see this owner_account_id row," never re-implemented a second way.';

-- 7. Reads: policy/identity single-row and bounded list reads (tenant-wide, owner-scoped
-- per design note 6b), trace and FIFO/FEFO candidate reads.

create function app.get_item_control_policy(p_item_master_id uuid, p_actor_auth_user_id uuid)
returns app.item_control_policy_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_policy app.item_control_policy_versions;
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

  select * into v_policy from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  if not found then
    raise exception 'policy_version_not_found: item % has no published control policy currently in effect', p_item_master_id using errcode = 'no_data_found';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_policy.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view item %''s control policy', p_actor_auth_user_id, p_item_master_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_policy;
end;
$$;

comment on function app.get_item_control_policy is
  'ATW-016: the currently published control policy for an item whose effective_from has already arrived (design note 1 / Prompt 235 section 25 "policy version matches owner/item/effective time") -- a published policy scheduled for a future effective_from is treated as not yet in effect (policy_version_not_found), never applied early.';

create function app.list_item_control_policy_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_item_master_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.item_control_policy_versions
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
  select * from app.item_control_policy_versions p
  where p.tenant_id = p_tenant_id
    and (p_item_master_id is null or p.item_master_id = p_item_master_id)
    and (p_status_filter is null or p.status = p_status_filter)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, p.owner_account_id)
  order by p.created_at desc
  limit v_limit;
end;
$$;

create function app.get_lot_identity(p_lot_identity_id uuid, p_actor_auth_user_id uuid)
returns app.lot_identities
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_lot app.lot_identities;
begin
  select * into v_lot from app.lot_identities where id = p_lot_identity_id;
  if not found then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_lot.tenant_id, v_lot.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view lot identity %', p_actor_auth_user_id, p_lot_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_lot;
end;
$$;

create function app.get_serial_identity(p_serial_identity_id uuid, p_actor_auth_user_id uuid)
returns app.serial_identities
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_serial app.serial_identities;
begin
  select * into v_serial from app.serial_identities where id = p_serial_identity_id;
  if not found then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_serial.tenant_id, v_serial.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view serial identity %', p_actor_auth_user_id, p_serial_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_serial;
end;
$$;

create function app.list_lot_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.lot_identities
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
  select * from app.lot_identities l
  where l.tenant_id = p_tenant_id
    and (p_item_master_id is null or l.item_master_id = p_item_master_id)
    and (p_owner_account_id is null or l.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or l.status = p_status_filter)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, l.owner_account_id)
  order by l.created_at desc
  limit v_limit;
end;
$$;

create function app.list_serial_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.serial_identities
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
  select * from app.serial_identities s
  where s.tenant_id = p_tenant_id
    and (p_item_master_id is null or s.item_master_id = p_item_master_id)
    and (p_owner_account_id is null or s.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or s.status = p_status_filter)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, s.owner_account_id)
  order by s.created_at desc
  limit v_limit;
end;
$$;

-- 8. Trace reads -- every ledger movement line referencing a given lot/serial, in
-- order (Prompt 235 section 13 "read trace"). Record-scoped per row by the movement
-- line's own warehouse (a lot/serial identity itself is tenant-wide, but the ledger
-- rows it traces through remain warehouse-record-scoped, mirroring app.list_
-- inventory_movement_lines exactly).

create function app.get_lot_trace(p_lot_identity_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns table (
  movement_id uuid,
  movement_type text,
  source_type text,
  source_id uuid,
  occurred_at timestamptz,
  warehouse_id uuid,
  location_id uuid,
  signed_quantity numeric,
  line_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_lot app.lot_identities;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_lot from app.lot_identities where id = p_lot_identity_id;
  if not found then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.movement_id, m.movement_type, m.source_type, m.source_id, m.occurred_at, ml.warehouse_id, ml.location_id, ml.signed_quantity, ml.status
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  join app.warehouses w on w.id = ml.warehouse_id
  where ml.tenant_id = v_lot.tenant_id
    and ml.owner_account_id = v_lot.owner_account_id
    and ml.item_master_id = v_lot.item_master_id
    and ml.lot_number = v_lot.lot_number
    and app.can_access_record(p_actor_auth_user_id, v_lot.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), v_lot.owner_account_id::text)
  order by m.occurred_at asc
  limit v_limit;
end;
$$;

comment on function app.get_lot_trace is
  'ATW-016: every app.inventory_movement_lines row referencing this lot''s own (owner, item, lot_number) dimension, in chronological order -- bounded (design note, standard p_limit convention). Depends on the lot identity''s own lot_number matching a movement line''s text column exactly (ATW-015''s own not-yet-foreign-keyed columns, design note 6) -- a movement posted before this lot was registered still traces correctly, since the match is by value, not by foreign key.';

create function app.get_serial_trace(p_serial_identity_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns table (
  movement_id uuid,
  movement_type text,
  source_type text,
  source_id uuid,
  occurred_at timestamptz,
  warehouse_id uuid,
  location_id uuid,
  signed_quantity numeric,
  line_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_serial app.serial_identities;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_serial from app.serial_identities where id = p_serial_identity_id;
  if not found then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.movement_id, m.movement_type, m.source_type, m.source_id, m.occurred_at, ml.warehouse_id, ml.location_id, ml.signed_quantity, ml.status
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  join app.warehouses w on w.id = ml.warehouse_id
  where ml.tenant_id = v_serial.tenant_id
    and ml.owner_account_id = v_serial.owner_account_id
    and ml.item_master_id = v_serial.item_master_id
    and ml.serial_number = v_serial.serial_number
    and app.can_access_record(p_actor_auth_user_id, v_serial.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), v_serial.owner_account_id::text)
  order by m.occurred_at asc
  limit v_limit;
end;
$$;

-- 9. FIFO/FEFO allocation candidate read -- real decision support, never authoritative
-- (design note 7).

create function app.list_allocation_candidates(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_item_master_id uuid,
  p_owner_account_id uuid,
  p_actor_auth_user_id uuid,
  p_allocation_rule text default null,
  p_limit integer default 50
)
returns table (
  balance_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  manufacture_date date,
  expiry_date date,
  available numeric,
  lot_status text,
  serial_status text,
  near_expiry boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_rule text;
  v_near_expiry_days integer;
  v_limit integer;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select allocation_rule, near_expiry_warning_days into v_rule, v_near_expiry_days
    from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  v_rule := coalesce(p_allocation_rule, v_rule, 'fifo');
  if v_rule not in ('fifo', 'fefo') then
    raise exception 'invalid_allocation_rule: % is not a recognized allocation rule', v_rule using errcode = 'check_violation';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    b.id,
    b.location_id,
    b.lot_number,
    b.serial_number,
    coalesce(l.manufacture_date, s.manufacture_date),
    coalesce(l.expiry_date, s.expiry_date),
    b.available,
    l.status,
    s.status,
    (v_near_expiry_days is not null and coalesce(l.expiry_date, s.expiry_date) is not null
      and coalesce(l.expiry_date, s.expiry_date) <= (current_date + make_interval(days => v_near_expiry_days)))
  from app.inventory_balances b
  left join app.lot_identities l on l.tenant_id = b.tenant_id and l.owner_account_id = b.owner_account_id and l.item_master_id = b.item_master_id and l.lot_number = b.lot_number and b.lot_number is not null
  left join app.serial_identities s on s.tenant_id = b.tenant_id and s.owner_account_id = b.owner_account_id and s.item_master_id = b.item_master_id and s.serial_number = b.serial_number and b.serial_number is not null
  where b.tenant_id = p_tenant_id
    and b.warehouse_id = p_warehouse_id
    and b.item_master_id = p_item_master_id
    and (p_owner_account_id is null or b.owner_account_id = p_owner_account_id)
    and b.status = 'on_hand'
    and b.available > 0
    and (l.id is null or l.status = 'active')
    and (s.id is null or s.status = 'active')
    and (l.id is null or l.expiry_date is null or l.expiry_date >= current_date)
    and (s.id is null or s.expiry_date is null or s.expiry_date >= current_date)
  order by
    case when v_rule = 'fefo' then coalesce(l.expiry_date, s.expiry_date) end asc nulls last,
    case when v_rule = 'fifo' then coalesce(l.created_at, s.created_at) end asc nulls last,
    b.updated_at asc
  limit v_limit;
end;
$$;

comment on function app.list_allocation_candidates is
  'ATW-016: real, read-only FIFO/FEFO decision support (design note 7) -- excludes held/quarantined/expired/consumed lot or serial identities, and any lot/serial whose own expiry_date has already passed regardless of stored status (design note 5). A balance dimension whose lot/serial was never registered via app.register_lot_identity/app.register_serial_identity (design note 6) cannot be excluded on hold/status grounds, only once registered. Never reserves or consumes stock -- app.reserve_inventory/app.consume_inventory_reservation (ATW-015) remain the only real allocation execution path.';

-- 10. RLS -- tenant-wide-but-owner-scoped for policy/lot/serial identities (design note
-- 6b) -- the RPCs above are all SECURITY DEFINER so RLS does not gate them today, but
-- this is this repository's own stated architectural last line of defense, and it must
-- carry the identical owner-scope predicate the RPC layer enforces (app.actor_can_view_
-- owner_scoped_row), not just tenant membership -- otherwise it stays a no-op for the
-- one axis (owner) this capability's own read RPCs are scoped by. Trace/candidate reads
-- are RPC-gated functions, not raw table policies, so no additional RLS is needed for
-- them beyond the underlying tables already governed by ATW-015's own policies.

alter table app.item_control_policy_versions enable row level security;

create policy item_control_policy_versions_select_scoped on app.item_control_policy_versions
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and app.actor_can_view_owner_scoped_row((select auth.uid()), tenant_id, owner_account_id)
  );

alter table app.lot_identities enable row level security;

create policy lot_identities_select_scoped on app.lot_identities
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and app.actor_can_view_owner_scoped_row((select auth.uid()), tenant_id, owner_account_id)
  );

alter table app.serial_identities enable row level security;

create policy serial_identities_select_scoped on app.serial_identities
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and app.actor_can_view_owner_scoped_row((select auth.uid()), tenant_id, owner_account_id)
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.item_control_policy_versions, app.lot_identities, app.serial_identities to authenticated, service_role;
grant insert, update, delete on app.item_control_policy_versions, app.lot_identities, app.serial_identities to service_role;

grant execute on function app.create_item_control_policy_version_draft(uuid, text, boolean, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.publish_item_control_policy_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_actor_owner_account_scope(uuid, uuid) to authenticated, service_role;
grant execute on function app.actor_can_view_owner_scoped_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.register_lot_identity(uuid, text, date, date, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.register_serial_identity(uuid, text, text, date, date, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_lot_identity_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_serial_identity_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_item_control_policy(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_item_control_policy_versions(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.get_lot_identity(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_serial_identity(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_lot_identities(uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_serial_identities(uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.get_lot_trace(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_serial_trace(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.list_allocation_candidates(uuid, uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
