-- Finance capability FIN-193 (Fiscal Period, CG-S9-FIN-004)
-- Tenant/company fiscal calendars and a governed period lifecycle
-- (open -> soft_closed -> closed, plus a governed reopen) so every later
-- Finance transaction posts into a valid, controlled period.
--
-- Reuse decision (disclosed, matching FIN-192's own header discipline): like
-- Chart of Accounts, a fiscal calendar/period is real domain data with its
-- own non-overlapping-date-range and lifecycle-transition concerns --
-- structurally unlike a flat key/value policy set, so this is a real table
-- family with its own authority model (`app.evaluate_permission` via
-- `FIN:Edit`/`FIN:Approve`), not layered on `PLT-121`'s Configuration Engine.
--
-- Closes FIN-191's own `finance_close_policy` config class into a real
-- consumer for the first time: generating a fiscal period pins (snapshots)
-- the tenant's currently-effective `finance_close_policy` items as this
-- period's own close checklist -- a governed snapshot, the same "read the
-- governed snapshot verbatim, never re-derive" discipline this repository's
-- Commercial/Operations capabilities already established (e.g. `OPS-179`'s
-- own `revenue_snapshot`). A later republish of `finance_close_policy` never
-- silently changes an already-generated period's own checklist.
--
-- Explicit scope boundary (Prompt 193 section 14): **hard lock enforcement at the
-- posting boundary is `FIN-207`'s own scope, not built here** -- no
-- posting/journal table exists anywhere in this repository yet. This
-- migration defines the canonical lifecycle, the deterministic date-to-period
-- resolver (`app.resolve_finance_period_for_date`, the exact forward seam
-- `FIN-207`/`FIN-2xx` posting capabilities will call), and a `posting_eligible`
-- read-only projection (true only while `status='open'`) -- but enforces
-- nothing at a posting call site, because none exists yet. Disclosed, not
-- silently promised.
--
-- Money/decimal discipline: this migration introduces zero money-shaped
-- column (a fiscal period carries no balance).
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_fiscal_calendars (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  code text not null,
  name text not null,
  created_by text,
  created_at timestamptz not null default now()
);

comment on table app.finance_fiscal_calendars is
  'FIN-193: one fiscal calendar per tenant/company scope (company_id null = tenant-wide, mirroring FIN-192''s own app.finance_accounts scope convention). Periods belong to exactly one calendar.';

create unique index finance_fiscal_calendars_tenant_company_code_unique on app.finance_fiscal_calendars (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), code
);

create table app.finance_fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  calendar_id uuid not null references app.finance_fiscal_calendars (id),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  period_code text not null,
  name text not null,
  start_date date not null,
  end_date date not null,
  sequence_number integer not null,
  status text not null default 'open',
  closed_at timestamptz,
  closed_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_fiscal_periods_status_check check (status in ('open', 'soft_closed', 'closed')),
  constraint finance_fiscal_periods_date_order_check check (end_date >= start_date)
);

comment on table app.finance_fiscal_periods is
  'FIN-193: a governed fiscal period. status is the canonical lifecycle (open/soft_closed/closed) -- hard-lock enforcement at a real posting boundary is FIN-207''s own scope (this migration''s own header); status here is the readiness/reporting signal only.';

create unique index finance_fiscal_periods_calendar_code_unique on app.finance_fiscal_periods (calendar_id, period_code);
create index finance_fiscal_periods_tenant_id_idx on app.finance_fiscal_periods (tenant_id);
create index finance_fiscal_periods_date_range_idx on app.finance_fiscal_periods (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), start_date, end_date);

create function app.touch_finance_fiscal_period_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_fiscal_periods_touch_row
  before update on app.finance_fiscal_periods
  for each row
  execute function app.touch_finance_fiscal_period_row();

-- One pinned close-checklist item per period, snapshotted from the tenant's
-- currently-effective finance_close_policy config at generation time (this
-- migration's own header) -- never re-read live once pinned.
create table app.finance_period_close_checklist_items (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references app.finance_fiscal_periods (id),
  item_key text not null,
  label text not null,
  required boolean not null,
  source_capability text,
  satisfied boolean not null default false,
  satisfied_reason text,
  satisfied_by text,
  satisfied_at timestamptz,
  created_at timestamptz not null default now(),
  constraint finance_period_close_checklist_items_period_key_unique unique (period_id, item_key)
);

comment on table app.finance_period_close_checklist_items is
  'FIN-193: a governed snapshot of the tenant''s finance_close_policy (FIN-191) items at the moment this period was generated -- never re-read live, so a later republish of finance_close_policy never silently changes an already-generated period''s own checklist.';

-- Append-only lifecycle/reopen evidence (mirrors OPS-170's own
-- app.shipment_status_transitions shape for the same "real history, never
-- overwritten" reason).
create table app.finance_period_transitions (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references app.finance_fiscal_periods (id),
  tenant_id uuid not null references app.tenants (id),
  from_status text not null,
  to_status text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default now()
);

comment on table app.finance_period_transitions is
  'FIN-193: append-only lifecycle/reopen evidence. A governed reopen (closed -> open) always carries a non-empty reason -- Prompt 193 section 25''s "close/reopen requests capture reason, scope, approval and evidence."';

create index finance_period_transitions_period_id_idx on app.finance_period_transitions (period_id);

create function app.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_period_authority is
  'FIN-193: FIN:Edit gates calendar generation/soft-close/checklist acknowledgment ("prepare"); FIN:Approve gates close/reopen ("separately authorized close/reopen approvers", Prompt 193 section 26); FIN:View gates read.';

-- Calendar generation (Prompt 192... Prompt 193 section 14's own "calendar generation"
-- operation): creates a calendar plus N sequential, non-overlapping monthly
-- periods starting at p_start_date, each pinning the tenant's currently-
-- effective finance_close_policy items as its own checklist snapshot.
create function app.generate_finance_fiscal_calendar(
  p_tenant_id uuid,
  p_company_id uuid,
  p_code text,
  p_name text,
  p_start_date date,
  p_period_count integer,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.finance_fiscal_calendars
language plpgsql
as $$
declare
  v_calendar app.finance_fiscal_calendars;
  v_period app.finance_fiscal_periods;
  v_period_start date;
  v_period_end date;
  v_seq integer;
  v_policy_row record;
  v_item record;
  v_found_policy boolean := false;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_period_count is null or p_period_count < 1 or p_period_count > 24 then
    raise exception 'finance_calendar_invalid_period_count: period count % must be between 1 and 24', p_period_count
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_fiscal_calendars (tenant_id, company_id, code, name, created_by)
    values (p_tenant_id, p_company_id, p_code, p_name, p_created_by)
    returning * into v_calendar;
  exception
    when unique_violation then
      raise exception 'finance_calendar_duplicate_code: code % already exists in this tenant/company scope', p_code
        using errcode = 'unique_violation';
  end;

  -- Resolve the tenant's currently-effective finance_close_policy once, then
  -- pin an identical checklist snapshot onto every generated period.
  for v_policy_row in select * from app.resolve_finance_config('finance_close_policy', p_tenant_id) loop
    v_found_policy := true;
  end loop;

  v_period_start := p_start_date;
  for v_seq in 1..p_period_count loop
    v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;

    if exists (
      select 1 from app.finance_fiscal_periods
      where tenant_id = p_tenant_id
        and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid)
        and start_date <= v_period_end and end_date >= v_period_start
    ) then
      raise exception 'finance_period_overlap: the period starting % would overlap an existing period in this tenant/company scope', v_period_start
        using errcode = 'check_violation';
    end if;

    insert into app.finance_fiscal_periods (calendar_id, tenant_id, company_id, period_code, name, start_date, end_date, sequence_number, created_by)
    values (
      v_calendar.id, p_tenant_id, p_company_id, to_char(v_period_start, 'YYYY-MM'), to_char(v_period_start, 'YYYY-MM'),
      v_period_start, v_period_end, v_seq, p_created_by
    )
    returning * into v_period;

    if v_found_policy then
      for v_item in select key, value from jsonb_each(v_policy_row.items) loop
        insert into app.finance_period_close_checklist_items (period_id, item_key, label, required, source_capability)
        values (v_period.id, v_item.key, v_item.value ->> 'label', coalesce((v_item.value ->> 'required')::boolean, false), v_item.value ->> 'sourceCapability');
      end loop;
    end if;

    insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
    values (v_period.id, p_tenant_id, 'none', 'open', null, p_actor_auth_user_id, p_created_by);

    v_period_start := v_period_start + interval '1 month';
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'generate_finance_fiscal_calendar',
    'app.finance_fiscal_calendars', v_calendar.id, 'success', null, null, jsonb_build_object('period_count', p_period_count, 'start_date', p_start_date)
  );

  return v_calendar;
end;
$$;

-- Deterministic date -> period resolver (Prompt 193 section 24's own "each transaction
-- date resolves to exactly one eligible fiscal period" business rule) -- the
-- exact forward seam FIN-207/later posting capabilities will call.
-- posting_eligible is a read-only projection (true only while status='open')
-- -- no real posting call site exists yet to enforce it against (this
-- migration's own header).
create function app.resolve_finance_period_for_date(
  p_tenant_id uuid,
  p_company_id uuid,
  p_transaction_date date
)
returns table (
  period_id uuid,
  period_code text,
  status text,
  posting_eligible boolean
)
language sql
stable
as $$
  select p.id, p.period_code, p.status, (p.status = 'open')
  from app.finance_fiscal_periods p
  where p.tenant_id = p_tenant_id
    and coalesce(p.company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and p.start_date <= p_transaction_date and p.end_date >= p_transaction_date
  limit 1;
$$;

comment on function app.resolve_finance_period_for_date is
  'FIN-193: deterministic date-to-period resolution. Returns zero rows if no generated period covers the date -- callers must treat that as "no valid period," never assume one. posting_eligible is disclosed as a read-only projection, not an enforced gate (FIN-207''s own scope).';

create function app.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied jsonb;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(item_key), '[]'::jsonb) into v_unsatisfied
  from app.finance_period_close_checklist_items
  where period_id = p_period_id and required and not satisfied;

  return jsonb_build_object(
    'periodId', p_period_id,
    'status', v_period.status,
    'ready', (v_unsatisfied = '[]'::jsonb),
    'unsatisfiedRequiredItems', v_unsatisfied
  );
end;
$$;

create function app.acknowledge_finance_period_checklist_item(
  p_period_id uuid,
  p_item_key text,
  p_satisfied boolean,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_close_checklist_items
language plpgsql
as $$
declare
  v_period app.finance_fiscal_periods;
  v_item app.finance_period_close_checklist_items;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.status = 'closed' then
    raise exception 'finance_period_closed: period % is closed -- checklist items on a closed period cannot be changed', p_period_id
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_period_close_checklist_items
  set satisfied = p_satisfied,
      satisfied_reason = p_reason,
      satisfied_by = case when p_satisfied then p_actor_label else null end,
      satisfied_at = case when p_satisfied then now() else null end
  where period_id = p_period_id and item_key = p_item_key
  returning * into v_item;

  if not found then
    raise exception 'finance_period_checklist_item_not_found: % on period %', p_item_key, p_period_id
      using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_finance_period_checklist_item',
    'app.finance_period_close_checklist_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

create function app.soft_close_finance_period(
  p_period_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_fiscal_periods
language plpgsql
as $$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'open' then
    raise exception 'finance_period_not_open: period % is %, only an open period may be soft-closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_fiscal_periods
  set status = 'soft_closed'
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'open', 'soft_closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'soft_close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$$;

-- Requires all required checklist items satisfied (Prompt 193 section 24's own "close
-- readiness includes configured budget, accrual, revenue/cost recognition
-- and reconciliation dependencies"). FIN:Approve-gated -- "close/reopen
-- approvers are separately authorized" (Prompt 193 section 26).
create function app.close_finance_period(
  p_period_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_fiscal_periods
language plpgsql
as $$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied_count integer;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'soft_closed' then
    raise exception 'finance_period_not_soft_closed: period % is %, only a soft-closed period may be closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_unsatisfied_count from app.finance_period_close_checklist_items
    where period_id = p_period_id and required and not satisfied;
  if v_unsatisfied_count > 0 then
    raise exception 'finance_period_checklist_incomplete: period % has % unsatisfied required close-checklist item(s)', p_period_id, v_unsatisfied_count
      using errcode = 'check_violation';
  end if;

  update app.finance_fiscal_periods
  set status = 'closed', closed_at = now(), closed_by = p_actor_label
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'soft_closed', 'closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$$;

-- Governed reopen (Prompt 193 section 22/25: "submit a governed reopen request";
-- "close/reopen requests capture reason, scope, approval and evidence").
-- FIN:Approve-gated, reason mandatory. Hard-lock enforcement against any real
-- posting made while closed is FIN-207's own scope -- no posting exists yet.
create function app.reopen_finance_period(
  p_period_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_fiscal_periods
language plpgsql
as $$
declare
  v_period app.finance_fiscal_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_reopen_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'closed' then
    raise exception 'finance_period_not_closed: period % is %, only a closed period may be reopened', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_fiscal_periods
  set status = 'open', closed_at = null, closed_by = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'closed', 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', p_reason, null, to_jsonb(v_period)
  );

  return v_period;
end;
$$;

create function app.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_fiscal_periods
language plpgsql
stable
as $$
begin
  if not app.check_finance_period_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_fiscal_periods
    where tenant_id = p_tenant_id
      and company_id is not distinct from p_company_id
      and (p_calendar_id is null or calendar_id = p_calendar_id)
    order by sequence_number asc;
end;
$$;

create function app.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_period_transitions
language plpgsql
stable
as $$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.finance_period_transitions where period_id = p_period_id order by created_at asc;
end;
$$;

alter table app.finance_fiscal_calendars enable row level security;
alter table app.finance_fiscal_periods enable row level security;
alter table app.finance_period_close_checklist_items enable row level security;
alter table app.finance_period_transitions enable row level security;

create policy finance_fiscal_calendars_select_scoped on app.finance_fiscal_calendars
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_fiscal_periods_select_scoped on app.finance_fiscal_periods
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_period_close_checklist_items_select_scoped on app.finance_period_close_checklist_items
  for select to authenticated
  using (
    exists (
      select 1 from app.finance_fiscal_periods p
      where p.id = finance_period_close_checklist_items.period_id
        and (app.has_active_tenant_membership(p.tenant_id) or app.is_supreme_admin())
    )
  );

create policy finance_period_transitions_select_scoped on app.finance_period_transitions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_fiscal_calendars to authenticated, service_role;
grant select on app.finance_fiscal_periods to authenticated, service_role;
grant select on app.finance_period_close_checklist_items to authenticated, service_role;
grant select on app.finance_period_transitions to authenticated, service_role;
grant insert, update, delete on app.finance_fiscal_calendars to service_role;
grant insert, update, delete on app.finance_fiscal_periods to service_role;
grant insert, update, delete on app.finance_period_close_checklist_items to service_role;
grant insert, update, delete on app.finance_period_transitions to service_role;

grant execute on function app.touch_finance_fiscal_period_row() to service_role;
grant execute on function app.check_finance_period_authority(text, uuid, uuid) to service_role;
grant execute on function app.generate_finance_fiscal_calendar(uuid, uuid, text, text, date, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_finance_period_for_date(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.get_finance_period_close_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.acknowledge_finance_period_checklist_item(uuid, text, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.soft_close_finance_period(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.close_finance_period(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_finance_period(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_fiscal_periods(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_period_transition_history(uuid, uuid) to authenticated, service_role;
