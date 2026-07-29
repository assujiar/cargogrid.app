-- Finance capability FIN-214 (Financial Field-Level Security, CG-S9-FIN-025)
-- One real, closeable field-level-security gap found and fixed during the audit
-- this checkpoint performed of every Finance capability's own field/record policy
-- (FIN-191..213) against the six surfaces Prompt 214 section 24 names (database,
-- service, API, UI, report/export, log): a log-channel inference leak.
--
-- The finding: `app.finance_job_profitability_facts` and its two read RPCs
-- (`app.get_finance_job_profitability`/`app.get_finance_profitability_summary`,
-- FIN-212) already deny outright without `FIN:View margin`. But FIN-212's own
-- `app.calculate_finance_job_profitability` recorded the *entire* calculated fact
-- (`to_jsonb(v_fact)` -- revenue_amount, cost_amount, profit_amount,
-- margin_percent, source_invoice_ids, source_cost_version_ids) into
-- `app.audit_logs.after_value`. `app.audit_logs` grants `authenticated` no direct
-- table privilege (PLT-116) -- the only read paths are
-- `app.query_audit_logs`/`app.export_audit_logs` (`20260716113048_create_audit_
-- trail.sql`), and both gate on `app.is_support_grant_authority()` (Supreme Admin
-- OR tenant_admin) alone, never on `FIN:View margin`. A `tenant_admin` who has
-- never been granted the protected `FIN:View margin` permission (confirmed a real,
-- distinct grant by FIN-212's own db-test `self_escalation` guard evidence) could
-- therefore read every Job Order's full revenue/cost/profit/margin figures via the
-- generic audit-log export -- an inference leak through the log channel, exactly
-- Prompt 214 section 23's named "critical/high blocker" class ("leakage through ...
-- log"). Supreme Admin's own unrestricted visibility is unaffected and expected
-- (RPD-022, restated in this prompt's own section 24) -- this fix narrows a
-- `tenant_admin`-only channel, not Supreme Admin's.
--
-- The fix: `create or replace function app.calculate_finance_job_profitability`,
-- identical signature and body, except the audit payload is now built from an
-- explicit allowlist of non-sensitive fields (id, job_order_id, version_number,
-- is_current, status, blocked_reason, revenue_basis, calculated_at) -- never the
-- financial figures or the source-document id arrays (which would themselves leak
-- scale/existence information). This is the one function in the entire Finance
-- module whose audit payload carried `FIN:View margin`-gated data; confirmed by
-- direct `grep` of every `capture_audit_event`/`to_jsonb` pairing across every
-- Finance migration before authoring this fix (docs/build-log/phase-04/FIN-214.md
-- section 3.1 records the full audit).
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its
-- own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC`
-- statement before its final grants, the standing per-migration convention since
-- `PLT-118`.

create or replace function app.calculate_finance_job_profitability(
  p_job_order_id uuid,
  p_recalculation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_job_profitability_facts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_existing_current app.finance_job_profitability_facts;
  v_revenue_currency_count integer;
  v_invoice_count integer;
  v_raw_revenue_amount numeric(14, 2);
  v_invoice_ids uuid[];
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_count integer;
  v_raw_cost_amount numeric(14, 2);
  v_cost_version_ids uuid[];
  v_cost_currency_check text;
  v_status text;
  v_blocked_reason text;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_profit_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_fact app.finance_job_profitability_facts;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_profitability_authority('Edit', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_finance_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.finance_job_profitability_facts where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'finance_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability fact' using errcode = 'check_violation';
  end if;

  select count(distinct currency), count(*), sum(subtotal_amount), coalesce(array_agg(id), '{}'::uuid[])
  into v_revenue_currency_count, v_invoice_count, v_raw_revenue_amount, v_invoice_ids
  from app.finance_invoices
  where job_order_id = p_job_order_id and status = 'issued';

  select count(distinct sac.currency), count(*), sum(sac.total_amount), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_raw_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_invoice_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_billed_revenue';
  elsif v_revenue_currency_count > 1 then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
  else
    select currency into v_revenue_currency from app.finance_invoices where id = v_invoice_ids[1];
    v_revenue_amount := v_raw_revenue_amount;
  end if;

  if v_status is null then
    if v_cost_count = 0 then
      v_status := 'unavailable';
      v_blocked_reason := 'no_approved_cost';
    else
      select sac.currency into v_cost_currency_check from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1];
      if v_cost_currency_count > 1 or v_cost_currency_check <> v_revenue_currency then
        v_status := 'unavailable';
        v_blocked_reason := 'mixed_currency';
      else
        v_status := 'calculated';
        v_cost_currency := v_revenue_currency;
        v_cost_amount := v_raw_cost_amount;
        v_profit_amount := v_revenue_amount - v_cost_amount;
        v_margin_percent := case when v_revenue_amount <> 0 then round((v_profit_amount / v_revenue_amount) * 100, 4) else null end;
      end if;
    end if;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.finance_job_profitability_facts set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.finance_job_profitability_facts (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason, revenue_basis,
    revenue_currency, revenue_amount, cost_currency, cost_amount, profit_amount, margin_percent,
    source_invoice_ids, source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason, 'billed',
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_profit_amount, v_margin_percent,
    v_invoice_ids, v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_fact;

  -- FIN-214: redacted audit payload -- an explicit allowlist of non-sensitive
  -- fields only, never the financial figures or source-document id arrays.
  -- Byte-for-byte identical to FIN-212's own body above this line.
  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_finance_job_profitability',
    'app.finance_job_profitability_facts', v_fact.id, 'success', p_recalculation_reason, null,
    jsonb_build_object(
      'id', v_fact.id,
      'job_order_id', v_fact.job_order_id,
      'version_number', v_fact.version_number,
      'is_current', v_fact.is_current,
      'status', v_fact.status,
      'blocked_reason', v_fact.blocked_reason,
      'revenue_basis', v_fact.revenue_basis,
      'calculated_at', v_fact.calculated_at
    )
  );

  return v_fact;
end;
$$;

comment on function app.calculate_finance_job_profitability is
  'FIN-212, redacted at FIN-214: FIN:Edit + FIN:View margin gated. Recalculates the current Job Order profitability fact (billed revenue minus approved actual cost); a currency mismatch or missing revenue/cost yields status=unavailable with a named blocked_reason, never a fabricated figure. Its own audit event carries only non-sensitive metadata (id/job_order_id/version/status/blocked_reason) -- never the revenue/cost/profit/margin figures or source-document id arrays -- since app.audit_logs is readable by any tenant_admin via app.query_audit_logs/app.export_audit_logs without holding FIN:View margin (FIN-214''s own finding).';

revoke execute on all functions in schema app from public;

grant execute on function app.calculate_finance_job_profitability(uuid, text, uuid, text) to authenticated, service_role;
