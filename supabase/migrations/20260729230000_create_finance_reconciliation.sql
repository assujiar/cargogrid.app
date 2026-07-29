-- Finance capability FIN-209 (Reconciliation, CG-S9-FIN-020)
-- Deterministic, governed reconciliation of the AR/AP subledger against
-- its own GL control account, formalizing FIN-202's own already-real
-- live comparison (`app.get_finance_subledger_reconciliation_summary`)
-- into a persisted, as-of, certifiable run.
--
-- Baseline, already real, disclosed not rebuilt: FIN-202 already computes
-- a direct, live subledger-vs-open-item comparison for the `ar_control`/
-- `ap_control` accounts. That function is tenant-wide (no as-of date, no
-- persisted snapshot, no exception/certification workflow) -- exactly the
-- gap this checkpoint closes for Financial Close purposes: "make Finance
-- balances explainable, expose discrepancies early and prevent silent
-- close on unreconciled data" (Prompt 209 section 5).
--
-- Disclosed bound on granularity: this checkpoint reconciles one
-- aggregate control-account total against one aggregate open-item total
-- per (scope, as-of date) -- an honest reflection of the real computation
-- FIN-202 already performs, itself aggregate. A real per-transaction
-- matched/unmatched queue (joining every subledger line to its own open
-- item one-by-one) is a larger scope, not attempted here.
--
-- Disclosed bound on execution: computed synchronously inside one
-- transaction. Prompt 209 section 17 names async execution for a large
-- OLTP-wide scan; the real aggregate query this checkpoint issues is
-- indexed and bounded, so no background job is introduced this
-- checkpoint -- disclosed, not silently claimed to already be
-- asynchronous.
--
-- Reconciliation never silently writes balances to force equality
-- (Prompt 209 section 24): this migration contains no function that
-- mutates `app.finance_ar_open_items`/`app.finance_ap_open_items`/
-- `app.finance_subledger_lines` in any way -- read-only source
-- comparison, always.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  scope text not null,
  as_of_date date not null,
  tolerance_amount numeric(14, 2) not null default 0,
  control_total numeric(14, 2) not null,
  source_total numeric(14, 2) not null,
  variance_amount numeric(14, 2) generated always as (control_total - source_total) stored,
  is_within_tolerance boolean not null,
  status text not null default 'completed',
  certify_reason text,
  certified_by text,
  certified_at timestamptz,
  prepared_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_reconciliation_runs_scope_check check (scope in ('ar', 'ap')),
  constraint finance_reconciliation_runs_status_check check (status in ('completed', 'certified')),
  constraint finance_reconciliation_runs_tolerance_check check (tolerance_amount >= 0)
);

comment on table app.finance_reconciliation_runs is
  'FIN-209: one deterministic, reproducible reconciliation run of the ar/ap subledger against its own GL control account, as of a fixed date. variance_amount is a generated column (control_total - source_total), never independently mutable. Certification (status=certified) requires zero open exceptions -- reconciliation never silently forces equality.';

create index finance_reconciliation_runs_tenant_scope_idx on app.finance_reconciliation_runs (tenant_id, scope, created_at desc);

create function app.touch_finance_reconciliation_run_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_reconciliation_runs_touch_row
  before update on app.finance_reconciliation_runs
  for each row
  execute function app.touch_finance_reconciliation_run_row();

create table app.finance_reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references app.finance_reconciliation_runs (id),
  tenant_id uuid not null references app.tenants (id),
  item_type text not null default 'control_account_variance',
  description text not null,
  expected_amount numeric(14, 2) not null,
  actual_amount numeric(14, 2) not null,
  variance_amount numeric(14, 2) generated always as (actual_amount - expected_amount) stored,
  status text not null default 'open',
  owner text,
  resolution_reason text,
  resolved_by text,
  resolved_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_reconciliation_exceptions_status_check check (status in ('open', 'resolved'))
);

comment on table app.finance_reconciliation_exceptions is
  'FIN-209: one exception per run where the control-account comparison exceeded its own run''s tolerance_amount. expected_amount is the source (open-item) total, actual_amount is the control-account (subledger) total. resolution requires an explicit reason -- never a silent dismissal.';

create index finance_reconciliation_exceptions_run_idx on app.finance_reconciliation_exceptions (run_id, status);

create function app.touch_finance_reconciliation_exception_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_reconciliation_exceptions_touch_row
  before update on app.finance_reconciliation_exceptions
  for each row
  execute function app.touch_finance_reconciliation_exception_row();

create function app.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_reconciliation_authority is
  'FIN-209: FIN:Edit executes a run and resolves an exception; FIN:Approve certifies (Prompt 209 section 26: "Accounting executes/resolves; Finance Manager certifies"); FIN:View reads.';

-- The deterministic engine (Prompt 209 section 21/24/25). Read-only
-- against every source table; writes only its own run/exception rows.
create function app.execute_finance_reconciliation_run(
  p_tenant_id uuid,
  p_company_id uuid,
  p_scope text,
  p_as_of_date date,
  p_tolerance_amount numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_reconciliation_runs
language plpgsql
as $$
declare
  v_run app.finance_reconciliation_runs;
  v_control_account app.finance_accounts;
  v_control_total numeric(14, 2) := 0;
  v_source_total numeric(14, 2) := 0;
  v_within boolean;
  v_source_document_type text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_scope not in ('ar', 'ap') then
    raise exception 'finance_reconciliation_invalid_scope: % is not a supported reconciliation scope', p_scope
      using errcode = 'check_violation';
  end if;
  if p_tolerance_amount is null or p_tolerance_amount < 0 then
    raise exception 'finance_reconciliation_invalid_tolerance: % must be a non-negative amount', p_tolerance_amount
      using errcode = 'check_violation';
  end if;

  v_control_account := app.resolve_finance_posting_map_account(p_tenant_id, p_scope || '_control');
  v_source_document_type := case when p_scope = 'ar' then 'invoice' else 'vendor_bill' end;

  -- as-of bound on the GL side: app.finance_subledger_batches carries no
  -- direct business posting-date column (only posted_at, a wall-clock
  -- insert timestamp, and posting_period_id) -- disclosed bound. Bounded
  -- here by the resolved posting period's own end_date, itself derived
  -- from the real business posting date at insert time, never by
  -- posted_at.
  select coalesce(sum(case when p_scope = 'ar' then (case when l.direction = 'debit' then l.amount else -l.amount end) else (case when l.direction = 'credit' then l.amount else -l.amount end) end), 0)
    into v_control_total
    from app.finance_subledger_lines l
    join app.finance_subledger_batches b on b.id = l.batch_id
    join app.finance_fiscal_periods fp on fp.id = b.posting_period_id
    where b.tenant_id = p_tenant_id and l.account_id = v_control_account.id and fp.end_date <= p_as_of_date;

  -- as-of bound on the source (open-item) side: each domain's own real
  -- business date column (invoice_date for AR, bill_date for AP), never
  -- created_at (a wall-clock insert timestamp).
  if p_scope = 'ar' then
    select coalesce(sum(open_amount), 0) into v_source_total
      from app.finance_ar_open_items where tenant_id = p_tenant_id and source_document_type = v_source_document_type and invoice_date <= p_as_of_date;
  else
    select coalesce(sum(open_amount), 0) into v_source_total
      from app.finance_ap_open_items where tenant_id = p_tenant_id and source_document_type = v_source_document_type and bill_date <= p_as_of_date;
  end if;

  v_within := abs(v_control_total - v_source_total) <= p_tolerance_amount;

  insert into app.finance_reconciliation_runs (tenant_id, company_id, scope, as_of_date, tolerance_amount, control_total, source_total, is_within_tolerance, prepared_by)
  values (p_tenant_id, p_company_id, p_scope, p_as_of_date, p_tolerance_amount, v_control_total, v_source_total, v_within, p_actor_label)
  returning * into v_run;

  if not v_within then
    insert into app.finance_reconciliation_exceptions (run_id, tenant_id, description, expected_amount, actual_amount)
    values (v_run.id, p_tenant_id, format('%s control account (%s) balance does not match open-item total within tolerance %s', upper(p_scope), v_control_account.code, p_tolerance_amount), v_source_total, v_control_total);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

create function app.resolve_finance_reconciliation_exception(
  p_exception_id uuid,
  p_expected_version integer,
  p_resolution_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_reconciliation_exceptions
language plpgsql
as $$
declare
  v_exception app.finance_reconciliation_exceptions;
begin
  select * into v_exception from app.finance_reconciliation_exceptions where id = p_exception_id;
  if not found then
    raise exception 'finance_reconciliation_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_resolution_reason is null or length(trim(p_resolution_reason)) = 0 then
    raise exception 'finance_reconciliation_resolution_reason_required: a non-empty resolution reason is required' using errcode = 'check_violation';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'finance_reconciliation_exception_not_open: exception % is % not open', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_exceptions
    set status = 'resolved', resolution_reason = p_resolution_reason, resolved_by = p_actor_label, resolved_at = now()
    where id = p_exception_id
    returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_finance_reconciliation_exception',
    'app.finance_reconciliation_exceptions', v_exception.id, 'success', p_resolution_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

-- Certification requires an independent authority and zero open
-- exceptions (Prompt 209 section 23: "block certification for unexplained
-- material variance... incomplete run"). Never silently permitted with an
-- open exception outstanding.
create function app.certify_finance_reconciliation_run(
  p_run_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_reconciliation_runs
language plpgsql
as $$
declare
  v_run app.finance_reconciliation_runs;
  v_open_exceptions integer;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id;
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: run % expected version % but found %', p_run_id, p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_reconciliation_certify_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_run.status = 'certified' then
    return v_run;
  end if;

  select count(*) into v_open_exceptions from app.finance_reconciliation_exceptions where run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'finance_reconciliation_unexplained_variance: run % has % unresolved exception(s)', p_run_id, v_open_exceptions
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_runs
    set status = 'certified', certify_reason = p_reason, certified_by = p_actor_label, certified_at = now()
    where id = p_run_id
    returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'certify_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', p_reason, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

create function app.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid)
returns setof app.finance_reconciliation_runs
language plpgsql
stable
as $$
begin
  if not app.check_finance_reconciliation_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_reconciliation_runs
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_scope is null or scope = p_scope)
    order by created_at desc
    limit 200;
end;
$$;

create function app.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_reconciliation_exceptions
language plpgsql
stable
as $$
declare
  v_run app.finance_reconciliation_runs;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id;
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('View', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_reconciliation_exceptions where run_id = p_run_id order by created_at asc;
end;
$$;

alter table app.finance_reconciliation_runs enable row level security;
alter table app.finance_reconciliation_exceptions enable row level security;

create policy finance_reconciliation_runs_select_scoped on app.finance_reconciliation_runs
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_reconciliation_exceptions_select_scoped on app.finance_reconciliation_exceptions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_reconciliation_runs to authenticated, service_role;
grant select on app.finance_reconciliation_exceptions to authenticated, service_role;
grant insert, update, delete on app.finance_reconciliation_runs to service_role;
grant insert, update, delete on app.finance_reconciliation_exceptions to service_role;

grant execute on function app.touch_finance_reconciliation_run_row() to service_role;
grant execute on function app.touch_finance_reconciliation_exception_row() to service_role;
grant execute on function app.check_finance_reconciliation_authority(text, uuid, uuid) to service_role;
grant execute on function app.execute_finance_reconciliation_run(uuid, uuid, text, date, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_finance_reconciliation_exception(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.certify_finance_reconciliation_run(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_reconciliation_runs(uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.list_finance_reconciliation_exceptions(uuid, uuid) to authenticated, service_role;
