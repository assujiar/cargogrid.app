-- Operations capability OPS-168 (Job Order, CG-S8-OPS-002)
-- The first Operations-domain (and first Phase 3) table in this repository. Converts one
-- verified Commercial `JobOrderDraftInput` handoff (`app.job_order_handoffs`, COM-160)
-- into one canonical, tenant-scoped Job Order -- idempotently, with complete source/
-- version lineage, and with zero re-entry of customer/contact/address/cargo/service/
-- rate/quote/price/credit data (every value is either a verbatim jsonb snapshot copied
-- straight from the handoff's own payload, or a live canonical FK, `account_id`, never a
-- re-typed free-text value -- the exact field-by-field mapping this migration implements
-- is documented in `docs/build-log/phase-03/00_OPERATIONS_WBS.md` §3).
--
-- Permission catalogue: the full 'OPS' action set (View/Create/Edit/Delete/Assign/Export/
-- Print/Download/Override/Reopen/Close) was already seeded at PLT-111
-- (20260716103445_create_roles_permissions.sql), unused until now -- exactly the same
-- "seeded ahead of the first real consumer" precedent COM-143 itself relied on for its own
-- base 'COM' actions. No new permission-catalogue row is inserted by this migration.
--
-- Sensitive-field masking reuses Commercial's own two entitlement dimensions directly
-- (`app.has_view_selling_price`/`app.has_view_cost`, both COM-scoped, COM-147/148) rather
-- than inventing a redundant OPS-level "View selling price" pair for data that is still
-- fundamentally Commercial-owned revenue/credit information merely carried into
-- Operations by reference -- "conversion never broadens Commercial access" (Prompt 168
-- §16) means literally this: an OPS:Create holder without COM:View selling price still
-- cannot see `revenue_snapshot`/`credit_snapshot` after conversion, the same as before it.
--
-- Record-scope reuses `app.lead_record_scope_org_unit_ids` (COM-143) directly rather than
-- duplicating it -- its body is generic (an org unit's own ancestors plus itself) despite
-- the lead-specific name, the same "reuse rather than re-author a byte-identical utility"
-- precedent every later Commercial capability already established for this exact function.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own explicit
-- `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final
-- grants, the standing per-migration convention since PLT-118.

create table app.job_order_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.job_order_number_counters is
  'OPS-168: one atomic, tenant-scoped monotonic counter for app.next_job_order_number() -- a bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125), which no Commercial or Operations capability has adopted yet (COM-151''s own identical disclosed boundary for app.next_quotation_number()).';

create function app.next_job_order_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.job_order_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.job_order_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'JOB-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_job_order_number is
  'OPS-168: atomic collision-safe allocation via a single INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING (serialized by the row lock the upsert itself takes), the same safe pattern app.next_quotation_number (COM-151) uses. Never recycled -- last_seq only increases.';

create table app.job_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_number text not null,
  source_handoff_id uuid not null references app.job_order_handoffs (id),
  quotation_id uuid not null references app.quotations (id),
  account_id uuid not null references app.accounts (id),
  customer_snapshot jsonb not null,
  cargo_service_snapshot jsonb not null,
  revenue_snapshot jsonb not null,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  acceptance_snapshot jsonb not null,
  status text not null default 'draft',
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_orders_status_check check (status in ('draft', 'confirmed', 'cancelled')),
  constraint job_orders_tenant_handoff_unique unique (tenant_id, source_handoff_id)
);

comment on table app.job_orders is
  'OPS-168: the canonical Operations execution root, one row per converted Commercial JobOrderDraftInput handoff (unique on tenant_id/source_handoff_id -- "one Commercial source/version/purpose/idempotency key yields one Job Order outcome," Prompt 168 §24). customer_snapshot/cargo_service_snapshot/revenue_snapshot/contract_snapshot/credit_snapshot/acceptance_snapshot are verbatim copies of app.job_order_handoffs.payload''s own sub-objects -- governed snapshots, never a live re-typed copy, mirroring every prior Commercial capability''s own snapshot discipline. account_id is a live canonical FK, not a copy.';

create unique index job_orders_tenant_number_unique on app.job_orders (tenant_id, job_number);
create index job_orders_tenant_status_idx on app.job_orders (tenant_id, status);
create index job_orders_tenant_account_idx on app.job_orders (tenant_id, account_id);
create index job_orders_tenant_owner_idx on app.job_orders (tenant_id, owner_user_id);
create index job_orders_quotation_idx on app.job_orders (quotation_id);

create function app.touch_job_orders_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger job_orders_touch_row
  before update on app.job_orders
  for each row
  execute function app.touch_job_orders_row();

-- Append-only evidence for a justified operational snapshot correction (Prompt 168 §22's
-- own alternative flow: "a justified operational snapshot override is reviewed and
-- audited"). Mirrors app.credit_profile_overrides' (COM-157) own "a full separate table,
-- always time-stamped and reasoned" shape rather than bare columns-on-the-parent-row,
-- since more than one override may accumulate on the same Job Order over its lifetime.
create table app.job_order_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  snapshot_column text not null,
  field_path text not null,
  previous_value jsonb,
  new_value jsonb not null,
  reason text not null,
  overridden_by text,
  overridden_at timestamptz not null default now(),
  constraint job_order_overrides_snapshot_column_check check (
    snapshot_column in ('customer_snapshot', 'cargo_service_snapshot')
  ),
  constraint job_order_overrides_reason_check check (length(trim(reason)) > 0)
);

comment on table app.job_order_overrides is
  'OPS-168: append-only, always-reasoned evidence of a bounded post-conversion correction to one operational snapshot field. Only customer_snapshot/cargo_service_snapshot may be overridden -- revenue_snapshot/contract_snapshot/credit_snapshot/acceptance_snapshot remain immutable financial/acceptance evidence, never correctable through this path (a pricing or acceptance correction is a new Commercial quotation version, COM-152, not an Operations override).';

create index job_order_overrides_job_order_idx on app.job_order_overrides (job_order_id);

-- Narrow, tenant-scoped read: "has this Commercial handoff already been converted."
-- Advisory/idempotency-preview only, mirrors app.get_account_conversion_readiness's own
-- (COM-155) "structural readiness check" shape.
create function app.get_job_order_conversion_readiness(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (ready boolean, blocking_reasons text[], existing_job_order_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_reasons text[] := array[]::text[];
  v_existing uuid;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  if not app.has_active_tenant_membership(v_handoff.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if v_existing is not null then
    v_reasons := array_append(v_reasons, 'already_converted');
  end if;

  if v_handoff.payload is null then
    v_reasons := array_append(v_reasons, 'handoff_payload_unavailable');
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons, v_existing;
end;
$$;

comment on function app.get_job_order_conversion_readiness is
  'OPS-168: structural pre-check only -- already-converted or a missing payload both block, mirroring app.get_account_conversion_readiness/app.get_quotation_submission_readiness''s own reason-codes-only shape. Never exposes a dollar figure.';

-- The one atomic, idempotent conversion action (Prompt 168 §20 task 2/§21/§33). Gated on
-- OPS:Create (an Operations action, independent of whether the actor can see Commercial
-- pricing -- masking happens at read time via app.job_orders_directory, never here).
create function app.prepare_job_order(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_decision app.rbac_decision;
  v_existing app.job_orders;
  v_job_order app.job_orders;
  v_number text;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_handoff.payload is null then
    raise exception 'handoff_payload_unavailable: handoff % carries no payload to convert', p_source_handoff_id
      using errcode = 'check_violation';
  end if;

  v_number := app.next_job_order_number(v_handoff.tenant_id);

  begin
    insert into app.job_orders (
      tenant_id, job_number, source_handoff_id, quotation_id, account_id,
      customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot, credit_snapshot, acceptance_snapshot,
      owner_user_id, created_by
    ) values (
      v_handoff.tenant_id, v_number, v_handoff.id, v_handoff.quotation_id, v_handoff.account_id,
      v_handoff.payload -> 'customer', v_handoff.payload -> 'cargoService', v_handoff.payload -> 'pricing',
      v_handoff.payload -> 'contract', v_handoff.payload -> 'credit', v_handoff.payload -> 'acceptance',
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job_order;
  exception
    when unique_violation then
      select * into v_job_order from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
      return v_job_order;
  end;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null,
    jsonb_build_object('source_handoff_id', p_source_handoff_id, 'job_number', v_number)
  );

  return v_job_order;
end;
$$;

comment on function app.prepare_job_order is
  'OPS-168: idempotent on (tenant_id, source_handoff_id) -- a repeated call, including under a concurrent-insert race (the unique_violation handler re-selects rather than raising), returns the exact same Job Order row, never a duplicate. Every snapshot column is copied verbatim from the handoff''s own already-canonical payload -- no field is derived, recomputed, or re-typed here.';

-- Draft -> confirmed. OPS:Edit-gated (the same "ordinary edit authority, not a routed
-- approval" weight app.submit_quotation, COM-151, uses for its own draft->submitted move).
create function app.confirm_job_order(
  p_job_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
begin
  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status <> 'draft' then
    raise exception 'invalid_transition: job order % is % and cannot be confirmed', p_job_order_id, v_job_order.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.job_orders
  set status = 'confirmed'
  where id = p_job_order_id and record_version = p_expected_version
  returning * into v_job_order;

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null, jsonb_build_object('status', v_job_order.status)
  );

  return v_job_order;
end;
$$;

comment on function app.confirm_job_order is
  'OPS-168: draft -> confirmed, the one gate that makes a Job Order eligible for bounded Shipment Order creation (OPS-169). Optimistic-concurrency-checked (p_expected_version) and record-scope-checked, matching every prior Commercial lifecycle transition''s own discipline.';

-- The one bounded post-conversion correction path (Prompt 168 §22). OPS:Override-gated,
-- mandatory reason, restricted to the two non-financial/non-acceptance snapshot columns
-- (see app.job_order_overrides' own comment for why).
create function app.override_job_order_field(
  p_job_order_id uuid,
  p_expected_version integer,
  p_snapshot_column text,
  p_field_path text,
  p_new_value jsonb,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
  v_previous_value jsonb;
begin
  if p_snapshot_column not in ('customer_snapshot', 'cargo_service_snapshot') then
    raise exception 'invalid_snapshot_column: % is not an overridable snapshot', p_snapshot_column using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'override_reason_required: a non-empty reason is required to override a Job Order snapshot field' using errcode = 'check_violation';
  end if;

  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status = 'cancelled' then
    raise exception 'invalid_transition: job order % is cancelled and cannot be overridden', p_job_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_snapshot_column = 'customer_snapshot' then
    v_previous_value := v_job_order.customer_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set customer_snapshot = jsonb_set(customer_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
  else
    v_previous_value := v_job_order.cargo_service_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set cargo_service_snapshot = jsonb_set(cargo_service_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
  end if;

  insert into app.job_order_overrides (
    tenant_id, job_order_id, snapshot_column, field_path, previous_value, new_value, reason, overridden_by
  ) values (
    v_job_order.tenant_id, p_job_order_id, p_snapshot_column, p_field_path, v_previous_value, p_new_value, p_reason, p_actor_label
  );

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_job_order_field',
    'app.job_orders', v_job_order.id, 'success', null,
    jsonb_build_object('field_path', p_field_path, 'previous_value', v_previous_value),
    jsonb_build_object('field_path', p_field_path, 'new_value', p_new_value, 'reason', p_reason)
  );

  return v_job_order;
end;
$$;

comment on function app.override_job_order_field is
  'OPS-168: the one bounded, reasoned, audited correction path -- never a silent re-entry. Every override is recorded append-only in app.job_order_overrides (previous and new value, actor, reason, timestamp), never merely overwritten in place without evidence.';

-- Field-masked projection (Prompt 168 §16) -- revenue_snapshot/credit_snapshot are nulled
-- out for any caller lacking the reused COM:View selling price / COM:View cost
-- permissions respectively. security_invoker=false (view-owner mode) is required for the
-- masking to work at all, mirroring app.quotations_directory''s own established shape;
-- this view compensates with its own explicit app.can_access_record(...) row filter.
create view app.job_orders_directory
as
select
  jo.id, jo.tenant_id, jo.job_number, jo.source_handoff_id, jo.quotation_id, jo.account_id,
  jo.customer_snapshot, jo.cargo_service_snapshot,
  case when app.has_view_selling_price(jo.tenant_id) then jo.revenue_snapshot else null end as revenue_snapshot,
  not app.has_view_selling_price(jo.tenant_id) as revenue_masked,
  jo.contract_snapshot,
  case when app.has_view_cost(jo.tenant_id) then jo.credit_snapshot else null end as credit_snapshot,
  not app.has_view_cost(jo.tenant_id) as credit_masked,
  jo.acceptance_snapshot, jo.status, jo.owner_user_id, jo.org_unit_id, jo.record_version,
  jo.created_by, jo.created_at, jo.updated_at
from app.job_orders jo
where app.can_access_record(auth.uid(), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null);

comment on view app.job_orders_directory is
  'OPS-168: field-masked projection of app.job_orders -- revenue_snapshot nulled out (revenue_masked=true) without COM:View selling price, credit_snapshot nulled out (credit_masked=true) without COM:View cost. The database guarantee: authenticated has no direct column-level grant on those two columns on app.job_orders itself, forcing every read through this view. Reuses Commercial''s own two entitlement dimensions rather than inventing a redundant OPS-level pair -- "conversion never broadens Commercial access" (Prompt 168 §16).';

alter table app.job_orders enable row level security;
alter table app.job_order_overrides enable row level security;

create policy job_orders_select_scoped on app.job_orders
  for select to authenticated
  using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));

create policy job_order_overrides_select_scoped on app.job_order_overrides
  for select to authenticated
  using (
    exists (
      select 1 from app.job_orders jo
      where jo.id = job_order_overrides.job_order_id
        and app.can_access_record((select auth.uid()), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

-- Same table-level-revoke-then-explicit-column-grant technique as app.quotations
-- (COM-151)/app.margin_calculations (COM-150) -- a bare column-level REVOKE cannot carve
-- an exception out of a broader table-level GRANT, so the grant below is explicit-column
-- from the start rather than grant-all-then-revoke-two.
grant select (
  id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
  customer_snapshot, cargo_service_snapshot, contract_snapshot, acceptance_snapshot,
  status, owner_user_id, org_unit_id, record_version, created_by, created_at, updated_at
) on app.job_orders to authenticated;
grant select on app.job_orders to service_role;
grant insert, update, delete on app.job_orders to service_role;
grant select on app.job_order_overrides to authenticated, service_role;
grant insert, update, delete on app.job_order_overrides to service_role;
grant select on app.job_orders_directory to authenticated, service_role;

grant execute on function app.next_job_order_number(uuid) to service_role;
grant execute on function app.get_job_order_conversion_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.prepare_job_order(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_job_order(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.override_job_order_field(uuid, integer, text, text, jsonb, text, uuid, text) to authenticated, service_role;
