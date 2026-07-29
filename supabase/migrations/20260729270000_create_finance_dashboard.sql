-- Finance capability FIN-213 (Finance Dashboard and Reports, CG-S9-FIN-024)
-- Permission-safe live Finance dashboards and governed reports covering
-- billing, AR/AP aging, cash, close/reconciliation and profitability
-- (Prompt 213 section 15/21). Mirrors OPS-182/OPS-183's own "reuse an
-- already-checked read as the query engine, add only the aggregation that
-- is genuinely missing" precedent exactly.
--
-- Scope boundaries (disclosed, matching every prior checkpoint):
--
-- * **AR/AP aging (`app.get_finance_aging_summary`, FIN-210) and
--   profitability (`app.get_finance_profitability_summary`, FIN-212) are
--   reused verbatim as two of the six dashboard widgets -- no new SQL for
--   either.** Both already perform their own FIN:View / FIN:View margin
--   check; this migration adds nothing on top.
-- * **Three widgets have no existing tenant/company-wide summary to reuse
--   and are genuinely new here:** a billing/invoice funnel by status
--   (`app.get_finance_dashboard_billing_summary`), a cash summary across
--   every bank account (`app.get_finance_dashboard_cash_summary` -- loops
--   `app.get_finance_cash_position`, FIN-211, per account rather than
--   duplicating its balance arithmetic), and a per-period close/
--   reconciliation status (`app.get_finance_dashboard_close_status` --
--   joins FIN-207's own `finance_period_locks` and FIN-209's own
--   `finance_reconciliation_runs` against FIN-193's own
--   `finance_fiscal_periods`, the one genuinely new join in this
--   migration). Each still performs its own explicit FIN:View check --
--   none is `security definer`, none bypasses RLS, all three are plain
--   `stable` functions exactly like the FIN-210/FIN-211 functions they
--   sit beside.
-- * **Reports reuse `app.report_types`/`app.report_runs`/
--   `app.record_report_run` directly from `COM-159`** -- the same shared,
--   schema-wide catalogue `OPS-183` already registered its own six codes
--   into. This migration registers seven Finance codes (`finance_billing_
--   summary`, `finance_ar_aging_summary`, `finance_ap_aging_summary`,
--   `finance_cash_summary`, `finance_close_status_summary`,
--   `finance_profitability_summary`) -- one extra than the five "areas"
--   Prompt 213 section 15 names, since AR aging and AP aging are exposed
--   as two separately-runnable report codes over the one shared
--   `get_finance_aging_summary` source function (a fixed `entity_type`
--   argument the application layer supplies, not a second function).
-- * **Export is the one genuinely new mutation**: `app.enqueue_finance_
--   report_export`, gated on `FIN:Export` (already seeded in the original
--   `PLT-111` permission catalogue, previously unused by any Finance
--   capability until now). It cannot call `COM-159`'s own
--   `app.enqueue_report_export` (hard-codes `COM:Export`) or `OPS-183`'s
--   own `app.enqueue_ops_report_export` (hard-codes `OPS:Export`) --
--   both are immutable prior migrations -- so this is a distinct, parallel
--   entry point for the `FIN` module, identical body shape otherwise.
--   Enqueues the identical `report_generation` job type via `PLT-132`'s
--   own generic `app.enqueue_job` and inserts into the identical shared
--   `app.report_runs` table. **No live worker processes a
--   `report_generation` job anywhere in this repository** -- the same
--   disclosed `NOT_RUN` condition `COM-159`/`OPS-183` already carried,
--   unchanged by this checkpoint.
-- * No new table. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`):
--   this migration carries its own explicit `REVOKE EXECUTE ON ALL
--   FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final
--   grants, the standing per-migration convention since `PLT-118`.

-- Billing/invoice funnel (Prompt 213 section 15 "billing readiness/
-- invoice"): invoice count/total/open amount grouped by status and
-- currency, joined to FIN-196's own AR open item for the still-open
-- amount on an issued invoice (a draft/submitted/approved invoice has no
-- open item yet and reports open_amount=0, never a fabricated figure).
create function app.get_finance_dashboard_billing_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  status text,
  currency text,
  invoice_count bigint,
  total_amount numeric,
  open_amount numeric
)
language plpgsql
stable
as $$
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      inv.status,
      inv.currency,
      count(*)::bigint,
      sum(inv.total_amount),
      coalesce(sum(oi.open_amount), 0)
    from app.finance_invoices inv
    left join app.finance_ar_open_items oi on oi.id = inv.ar_open_item_id
    where inv.tenant_id = p_tenant_id
      and (p_company_id is null or inv.company_id = p_company_id)
    group by inv.status, inv.currency
    order by inv.status, inv.currency;
end;
$$;

comment on function app.get_finance_dashboard_billing_summary is
  'FIN-213: FIN:View-gated. Invoice count/total/open-amount grouped by (status, currency) -- open_amount is 0, never fabricated, for a not-yet-issued invoice with no AR open item.';

-- Cash summary (Prompt 213 section 15 "cash"): every active bank account's
-- own FIN-211 reconciled position, one row per account -- never a second
-- balance calculation. Loops app.get_finance_cash_position (already
-- FIN:View-checked and itself re-checked on every call, an accepted
-- redundant-but-harmless cost for a small per-tenant account count).
create function app.get_finance_dashboard_cash_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_as_of_date date,
  p_actor_auth_user_id uuid
)
returns table (
  bank_account_id uuid,
  account_name text,
  currency text,
  statement_balance numeric,
  gl_balance numeric,
  variance_amount numeric
)
language plpgsql
stable
as $$
declare
  v_account app.finance_bank_accounts;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_account in
    select * from app.finance_bank_accounts
    where tenant_id = p_tenant_id
      and status = 'active'
      and (p_company_id is null or company_id = p_company_id)
    order by account_name
  loop
    return query
      select v_account.id, v_account.account_name, p.currency, p.statement_balance, p.gl_balance, p.variance_amount
      from app.get_finance_cash_position(p_tenant_id, v_account.id, p_as_of_date, p_actor_auth_user_id) p;
  end loop;
end;
$$;

comment on function app.get_finance_dashboard_cash_summary is
  'FIN-213: FIN:View-gated. One row per active bank account, reusing app.get_finance_cash_position (FIN-211) verbatim -- never a duplicate statement-vs-GL balance calculation.';

-- Close/reconciliation status (Prompt 213 section 15 "reconciliation/
-- close"): the one genuinely new join in this migration. Most recent
-- FIN-207 lock event and most recent FIN-209 reconciliation run whose
-- as_of_date falls inside the period, per FIN-193 fiscal period, latest 12
-- periods. A period with no lock row yet reports lock_status=null (open,
-- never fabricated as "locked"); a period with no reconciliation run in
-- range reports reconciliation_status=null, never a fabricated pass.
create function app.get_finance_dashboard_close_status(
  p_tenant_id uuid,
  p_company_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  period_id uuid,
  period_code text,
  period_name text,
  end_date date,
  period_status text,
  lock_status text,
  reconciliation_status text,
  reconciliation_within_tolerance boolean
)
language plpgsql
stable
as $$
begin
  if not app.check_finance_period_lock_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_reconciliation_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      fp.id, fp.period_code, fp.name, fp.end_date, fp.status,
      lk.lock_status, rc.reconciliation_status, rc.reconciliation_within_tolerance
    from app.finance_fiscal_periods fp
    left join lateral (
      select l.status as lock_status
      from app.finance_period_locks l
      where l.period_id = fp.id
        and l.tenant_id = p_tenant_id
        and (p_company_id is null or l.company_id = p_company_id)
      order by l.created_at desc
      limit 1
    ) lk on true
    left join lateral (
      select r.status as reconciliation_status, r.is_within_tolerance as reconciliation_within_tolerance
      from app.finance_reconciliation_runs r
      where r.tenant_id = p_tenant_id
        and (p_company_id is null or r.company_id = p_company_id)
        and r.as_of_date between fp.start_date and fp.end_date
      order by r.created_at desc
      limit 1
    ) rc on true
    where fp.tenant_id = p_tenant_id
      and (p_company_id is null or fp.company_id = p_company_id)
    order by fp.end_date desc
    limit 12;
end;
$$;

comment on function app.get_finance_dashboard_close_status is
  'FIN-213: FIN:View-gated. Per fiscal period (latest 12): most recent FIN-207 lock event and most recent FIN-209 reconciliation run whose as_of_date falls inside the period. A period with no lock/run yet reports null, never a fabricated "locked"/"reconciled" state.';

insert into app.report_types (code, name, description, source_function, registered_by) values
  ('finance_billing_summary', 'Billing Summary', 'Invoice count, total and open amount by status and currency.', 'get_finance_dashboard_billing_summary', 'system'),
  ('finance_ar_aging_summary', 'AR Aging Summary', 'Open Accounts Receivable amount by aging bucket and currency.', 'get_finance_aging_summary', 'system'),
  ('finance_ap_aging_summary', 'AP Aging Summary', 'Open Accounts Payable amount by aging bucket and currency.', 'get_finance_aging_summary', 'system'),
  ('finance_cash_summary', 'Cash Summary', 'Reconciled statement-vs-GL cash position by bank account.', 'get_finance_dashboard_cash_summary', 'system'),
  ('finance_close_status_summary', 'Close and Reconciliation Status', 'Period lock and reconciliation-run status by fiscal period.', 'get_finance_dashboard_close_status', 'system'),
  ('finance_profitability_summary', 'Profitability Summary', 'Billed revenue minus approved actual cost, grouped by customer/branch/service.', 'get_finance_profitability_summary', 'system');

-- The one genuinely new mutation -- FIN:Export-gated, a parallel entry
-- point to COM-159's/OPS-183's own app.enqueue_report_export /
-- app.enqueue_ops_report_export bodies (identical shape, distinct
-- module-code RBAC check, since both are immutable prior migrations).
create function app.enqueue_finance_report_export(
  p_tenant_id uuid,
  p_report_type_code text,
  p_parameters jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_job app.jobs;
  v_run app.report_runs;
begin
  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and can no longer be exported', p_report_type_code using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'report_generation',
    jsonb_build_object('report_type_code', p_report_type_code, 'parameters', coalesce(p_parameters, '{}'::jsonb)),
    0, null, 3, p_actor_auth_user_id, p_actor_label
  );

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, job_id,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_report_type_code, 'export', 'queued', coalesce(p_parameters, '{}'::jsonb), v_job.job_id,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_run;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_finance_report_export',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.enqueue_finance_report_export is
  'FIN-213: FIN:Export-gated (Prompt 213 section 26). A parallel entry point to COM-159''s/OPS-183''s own report-export functions -- identical body shape, distinct module-code RBAC check, since both are immutable prior migrations. Enqueues a real report_generation job via PLT-132''s own app.enqueue_job (never a bespoke queue) and records the linking app.report_runs row (the same shared table COM-159 already created) at status=queued. No live worker advances it further in this environment -- disclosed, unchanged by this checkpoint.';

revoke execute on all functions in schema app from public;

grant execute on function app.get_finance_dashboard_billing_summary(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_dashboard_cash_summary(uuid, uuid, date, uuid) to authenticated, service_role;
grant execute on function app.get_finance_dashboard_close_status(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.enqueue_finance_report_export(uuid, text, jsonb, uuid, text) to authenticated, service_role;
