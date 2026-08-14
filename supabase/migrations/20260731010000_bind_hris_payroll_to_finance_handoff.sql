-- HRIS capability HRT-282 (Prompt 282, CG-S12-HRT-010) -- Payroll Foundation,
-- Benefit and Reimbursement, migration 2 of 2: the Finance handoff boundary.
--
-- See `20260731000000_create_hris_payroll_foundation.sql`'s own header
-- decision 1 for the full ownership-boundary reasoning (mandatory reading
-- item 6) -- summarized here for this migration's own scope:
--
-- * Every table this migration creates is still Payroll-OWNED (`app.
--   payroll_finance_handoff_*`), never a `app.finance_*` table. Zero
--   `GRANT`/`INSERT`/`UPDATE`/`DELETE` anywhere in this file against any
--   `app.finance_*` table, `app.journal_entries`, `app.finance_settlements`,
--   or `app.finance_payments` -- grep-verified, recorded in the build log.
-- * `app.prepare_finance_payroll_disbursement_handoff_from_payroll_run`
--   mirrors `app.prepare_finance_vendor_bill_from_actual_cost` (FIN-200)'s
--   own naming/behavior shape exactly: it turns an approved, IMMUTABLE
--   upstream record (here, a `finalized` `app.payroll_runs` row) into a
--   structured, reconciled intake package, callable only once per run
--   (idempotent on `payroll_run_id`), never re-typing a figure.
-- * `app.search_payroll_finance_handoffs_pending_acknowledgement` mirrors
--   `app.search_finance_ap_candidates_for_settlement` (FIN-201)'s own "how
--   the OTHER domain discovers candidates prepared by this one" shape --
--   gated on `FIN:View`, so a genuinely Finance-authorized actor (or a
--   future Finance-side capability built directly on top of this function)
--   can discover what Payroll has prepared without Payroll ever reaching
--   into a Finance table.
-- * `app.acknowledge_payroll_finance_handoff_batch` is gated on `FIN:Edit`
--   -- the ONE place in this whole checkpoint the calling actor must hold
--   Finance authority, not Payroll authority -- proving the acknowledging
--   actor is genuinely Finance-side. This is "handoff is acknowledged and
--   reconcilable" (Prompt 282 section 33), enforced, not merely claimed.
-- * `app.get_payroll_finance_handoff_reconciliation` is a pure READ
--   function comparing the GL-line aggregate against the payment-
--   instruction aggregate against the run's own employee-result totals --
--   proves the handoff is internally reconciled before Finance ever acts
--   on it, without positing what Finance's own future posting/payment
--   entities will look like.
--
-- Compensation privacy at the handoff boundary: `app.payroll_finance_
-- handoff_gl_lines` is AGGREGATE ONLY (grouped by component_type/
-- gl_mapping_category, zero `employee_id` column) -- Finance receives
-- postable GL totals, never a per-employee compensation breakdown, for the
-- journal side. `app.payroll_finance_handoff_payment_instructions` IS
-- employee-level (Finance genuinely needs employee+net_pay+bank reference
-- to execute payment) -- gated identically to every other payroll person-
-- scoped table (`app.can_view_hris_payroll_row`, decision 5) PLUS `FIN:View`
-- for a Finance-side reader, and the bank reference itself is a masked
-- reference to the employee's own already-governed record, never a raw
-- account number column duplicated here.
--
-- Per ERR-2026-004: explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` before this migration's own final grants.

create table app.payroll_finance_handoff_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_run_id uuid not null references app.payroll_runs (id),
  payroll_period_id uuid not null references app.payroll_periods (id),
  currency text not null,
  gross_earnings_total numeric(14, 2) not null,
  total_deductions_total numeric(14, 2) not null,
  total_tax_total numeric(14, 2) not null,
  total_benefit_employer_cost_total numeric(14, 2) not null,
  total_reimbursement_total numeric(14, 2) not null,
  total_loan_repayment_total numeric(14, 2) not null,
  net_pay_total numeric(14, 2) not null,
  employee_count integer not null,
  status text not null default 'pending_acknowledgement',
  generated_by text,
  generated_at timestamptz not null default now(),
  acknowledged_by text,
  acknowledged_at timestamptz,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint payroll_finance_handoff_batches_status_check check (status in ('pending_acknowledgement', 'acknowledged')),
  constraint payroll_finance_handoff_batches_totals_nonneg_check check (
    gross_earnings_total >= 0 and total_deductions_total >= 0 and total_tax_total >= 0 and total_benefit_employer_cost_total >= 0
    and total_reimbursement_total >= 0 and total_loan_repayment_total >= 0 and net_pay_total >= 0
  ),
  constraint payroll_finance_handoff_batches_ack_shape_check check (
    (status = 'pending_acknowledgement' and acknowledged_by is null and acknowledged_at is null)
    or (status = 'acknowledged' and acknowledged_by is not null and acknowledged_at is not null)
  ),
  constraint payroll_finance_handoff_batches_run_unique unique (payroll_run_id)
);

comment on table app.payroll_finance_handoff_batches is
  'HRT-282 migration 2 (decision 1): the ONE handoff artifact per finalized payroll run -- still Payroll-owned, never a app.finance_* table. Generated ONLY from a run whose status=finalized (business rule: finalized history never silently recalculates -- these totals are copied once from app.payroll_run_employee_results, never recomputed live). acknowledged_by/acknowledged_at are set ONLY by an actor holding FIN:Edit (app.acknowledge_payroll_finance_handoff_batch) -- the concrete, enforced shape of "Finance receives only contracted approved data."';

create index payroll_finance_handoff_batches_tenant_status_idx on app.payroll_finance_handoff_batches (tenant_id, status);

create trigger payroll_finance_handoff_batches_touch before update on app.payroll_finance_handoff_batches
  for each row execute function app.touch_payroll_row();

create table app.payroll_finance_handoff_gl_lines (
  id uuid primary key default gen_random_uuid(),
  handoff_batch_id uuid not null references app.payroll_finance_handoff_batches (id),
  tenant_id uuid not null references app.tenants (id),
  line_type text not null,
  gl_mapping_category text not null,
  amount numeric(14, 2) not null,
  currency text not null,
  constraint payroll_finance_handoff_gl_lines_line_type_check check (
    line_type in ('earning', 'deduction', 'benefit_employer_cost', 'tax', 'loan_repayment', 'reimbursement')
  ),
  constraint payroll_finance_handoff_gl_lines_amount_nonneg_check check (amount >= 0)
);

comment on table app.payroll_finance_handoff_gl_lines is
  'HRT-282 migration 2: AGGREGATE ONLY -- grouped by (line_type, gl_mapping_category) across every employee in the run, zero employee_id column anywhere on this table. This is the postable-GL-total side of the handoff -- Finance receives what it needs to balance a journal, never a per-employee compensation breakdown, structurally, not merely by convention.';

create index payroll_finance_handoff_gl_lines_batch_idx on app.payroll_finance_handoff_gl_lines (handoff_batch_id);

create table app.payroll_finance_handoff_payment_instructions (
  id uuid primary key default gen_random_uuid(),
  handoff_batch_id uuid not null references app.payroll_finance_handoff_batches (id),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  net_pay_amount numeric(14, 2) not null,
  currency text not null,
  bank_reference_masked text,
  constraint payroll_finance_handoff_payment_instructions_amount_check check (net_pay_amount >= 0),
  constraint payroll_finance_handoff_pay_instr_batch_employee_unique unique (handoff_batch_id, employee_id)
);

comment on table app.payroll_finance_handoff_payment_instructions is
  'HRT-282 migration 2: employee-level net-pay disbursement instruction -- Finance genuinely needs employee + amount (+ a bank reference) to execute payment, so this table IS person-scoped, unlike the GL-lines table beside it. bank_reference_masked is a bounded, disclosed placeholder (this repository has no employee bank-account column anywhere yet, see the build log''s residual-gaps section) -- never a raw account number. Gated identically to every other person-scoped payroll table (app.can_view_hris_payroll_row) PLUS FIN:View for a genuinely Finance-side reader.';

create index payroll_finance_handoff_payment_instructions_batch_idx on app.payroll_finance_handoff_payment_instructions (handoff_batch_id);
create index payroll_finance_handoff_payment_instructions_employee_idx on app.payroll_finance_handoff_payment_instructions (employee_id);

-- ===========================================================================
-- The prepare_finance_*_from_*-shaped generation function (decision 1).
-- ===========================================================================

create function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_existing app.payroll_finance_handoff_batches;
  v_batch app.payroll_finance_handoff_batches;
  v_gross numeric(14, 2);
  v_deductions numeric(14, 2);
  v_tax numeric(14, 2);
  v_benefit numeric(14, 2);
  v_reimb numeric(14, 2);
  v_loan numeric(14, 2);
  v_net numeric(14, 2);
  v_count integer;
begin
  -- Payroll's OWN authority (HRS:Approve) generates the handoff -- this is
  -- still Payroll acting on its own finalized data, never a Finance action.
  if not app.check_payroll_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.payroll_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if v_run.status <> 'finalized' then
    raise exception 'payroll_run_not_finalized: run % is % -- only a finalized run may generate a Finance handoff', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.payroll_finance_handoff_batches where payroll_run_id = p_run_id;
  if found then
    return v_existing;
  end if;

  select
    coalesce(sum(gross_earnings), 0), coalesce(sum(total_deductions), 0), coalesce(sum(total_tax), 0),
    coalesce(sum(total_benefit_employer_cost), 0), coalesce(sum(total_reimbursement), 0), coalesce(sum(total_loan_repayment), 0),
    coalesce(sum(net_pay), 0), count(*)
  into v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count
  from app.payroll_run_employee_results where payroll_run_id = p_run_id;

  insert into app.payroll_finance_handoff_batches (
    tenant_id, payroll_run_id, payroll_period_id, currency, gross_earnings_total, total_deductions_total, total_tax_total,
    total_benefit_employer_cost_total, total_reimbursement_total, total_loan_repayment_total, net_pay_total, employee_count, generated_by
  ) values (
    p_tenant_id, p_run_id, v_run.payroll_period_id, v_run.currency, v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count, p_actor_label
  )
  returning * into v_batch;

  insert into app.payroll_finance_handoff_gl_lines (handoff_batch_id, tenant_id, line_type, gl_mapping_category, amount, currency)
  select v_batch.id, p_tenant_id, l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), sum(l.amount), l.currency
  from app.payroll_calculation_lines l
  left join app.payroll_components c on c.id = l.component_id
  where l.payroll_run_id = p_run_id
  group by l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), l.currency;

  insert into app.payroll_finance_handoff_payment_instructions (handoff_batch_id, tenant_id, employee_id, net_pay_amount, currency, bank_reference_masked)
  select v_batch.id, p_tenant_id, r.employee_id, r.net_pay, r.currency, null
  from app.payroll_run_employee_results r
  where r.payroll_run_id = p_run_id;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_payroll_disbursement_handoff_from_payroll_run',
    'app.payroll_finance_handoff_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('payroll_run_id', p_run_id, 'net_pay_total', v_net, 'employee_count', v_count)
  );

  return v_batch;
end;
$$;

comment on function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run is
  'HRT-282 (decision 1): mirrors app.prepare_finance_vendor_bill_from_actual_cost (FIN-200) exactly -- idempotent on payroll_run_id (a replay returns the existing batch unchanged, never a second batch for the same run); sums this run''s ALREADY-COMPUTED, immutable app.payroll_run_employee_results/app.payroll_calculation_lines -- never re-derives or re-calculates a figure. Zero write to any app.finance_* table -- grep-verified.';

-- ===========================================================================
-- Finance-side discovery and acknowledgement (decision 1).
-- ===========================================================================

create function app.search_payroll_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_finance_handoff_batches
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.payroll_finance_handoff_batches
    where tenant_id = p_tenant_id and status = 'pending_acknowledgement'
    order by generated_at asc
    limit 200;
end;
$$;

comment on function app.search_payroll_finance_handoffs_pending_acknowledgement is
  'HRT-282 (decision 1): mirrors app.search_finance_ap_candidates_for_settlement (FIN-201) exactly -- "how the OTHER domain discovers candidates prepared by this one." Gated on FIN:View, the ONE cross-module gate this migration adds -- a genuinely Finance-authorized actor, or a future Finance-side capability built directly on top of this function, can find every payroll handoff awaiting acknowledgement without Payroll ever reaching into a Finance table.';

create function app.acknowledge_payroll_finance_handoff_batch(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id for update;
  if not found then
    raise exception 'payroll_finance_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  -- The ONE place in this entire checkpoint the calling actor must hold
  -- FINANCE authority, not Payroll authority -- proves the acknowledging
  -- actor is genuinely Finance-side (decision 1).
  if not (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'Edit')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_batch.status = 'acknowledged' then
    -- Idempotent no-op: a second acknowledgement of an already-acknowledged
    -- batch (by the same or a different Finance-authorized actor) returns
    -- the ORIGINAL acknowledgement unchanged, never overwrites who/when.
    return v_batch;
  end if;
  if v_batch.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_batch.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.payroll_finance_handoff_batches set status = 'acknowledged', acknowledged_by = p_actor_label, acknowledged_at = now()
  where id = p_batch_id and record_version = p_expected_version
  returning * into v_batch;
  if not found then
    raise exception 'stale_version: concurrent update detected for handoff batch %', p_batch_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_batch.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_payroll_finance_handoff_batch',
    'app.payroll_finance_handoff_batches', v_batch.id, 'success', null, null, jsonb_build_object('status', v_batch.status)
  );

  return v_batch;
end;
$$;

comment on function app.acknowledge_payroll_finance_handoff_batch is
  'HRT-282 (decision 1): FIN:Edit-gated -- the enforced shape of "Finance receives only contracted approved data" (Prompt 282 section 26) and "handoff is acknowledged and reconcilable" (section 33). Idempotent: a repeat acknowledgement of an already-acknowledged batch is a safe no-op, never a silently overwritten acknowledged_by/acknowledged_at.';

create function app.get_payroll_finance_handoff_reconciliation(p_batch_id uuid, p_actor_auth_user_id uuid)
returns table (
  gl_lines_net numeric, payment_instructions_total numeric, run_results_net_total numeric, is_reconciled boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
  v_gl_net numeric(14, 2);
  v_pay_total numeric(14, 2);
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id;
  if not found then
    raise exception 'payroll_finance_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  if not (
    (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'HRS', 'View payroll')).allowed
    or (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed
  ) then
    raise exception 'insufficient_authority: identity % lacks HRS:View payroll or FIN:View for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(amount) filter (where line_type in ('earning', 'reimbursement')), 0)
       - coalesce(sum(amount) filter (where line_type in ('deduction', 'tax', 'loan_repayment')), 0)
  into v_gl_net
  from app.payroll_finance_handoff_gl_lines where handoff_batch_id = p_batch_id;

  select coalesce(sum(net_pay_amount), 0) into v_pay_total from app.payroll_finance_handoff_payment_instructions where handoff_batch_id = p_batch_id;

  gl_lines_net := v_gl_net;
  payment_instructions_total := v_pay_total;
  run_results_net_total := v_batch.net_pay_total;
  is_reconciled := (v_gl_net = v_batch.net_pay_total) and (v_pay_total = v_batch.net_pay_total);
  return next;
end;
$$;

comment on function app.get_payroll_finance_handoff_reconciliation is
  'HRT-282 (decision 1, acceptance criteria "handoff is acknowledged and reconcilable"): proves the handoff is internally consistent across all three of its own facets (GL-line aggregate, payment-instruction aggregate, the run''s own already-computed totals) BEFORE Finance ever acts on it -- a pure read/verify function, never a posting.';

create function app.get_payroll_finance_handoff_batch(p_batch_id uuid, p_actor_auth_user_id uuid)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id;
  if not found or not (
    (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'HRS', 'View payroll')).allowed
    or (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed
  ) then
    raise exception 'payroll_finance_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  return v_batch;
end;
$$;

create function app.list_payroll_finance_handoff_gl_lines(p_batch_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_finance_handoff_gl_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id;
  if not found or not (
    (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'HRS', 'View payroll')).allowed
    or (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed
  ) then
    return;
  end if;
  return query select * from app.payroll_finance_handoff_gl_lines where handoff_batch_id = p_batch_id order by line_type;
end;
$$;

create function app.list_payroll_finance_handoff_payment_instructions(p_batch_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_finance_handoff_payment_instructions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
  v_has_fin boolean;
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id;
  if not found then
    return;
  end if;
  v_has_fin := (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed;
  if v_has_fin then
    return query select * from app.payroll_finance_handoff_payment_instructions where handoff_batch_id = p_batch_id order by employee_id;
    return;
  end if;
  -- No FIN:View -- fall back to the same self-or-HRS:View-payroll bar every
  -- other person-scoped payroll row uses (decision 5), applied per row.
  return query select pi.* from app.payroll_finance_handoff_payment_instructions pi
    where pi.handoff_batch_id = p_batch_id and app.can_view_hris_payroll_row(pi.tenant_id, pi.employee_id, p_actor_auth_user_id)
    order by pi.employee_id;
end;
$$;

-- ===========================================================================
-- RLS.
-- ===========================================================================

alter table app.payroll_finance_handoff_batches enable row level security;
alter table app.payroll_finance_handoff_gl_lines enable row level security;
alter table app.payroll_finance_handoff_payment_instructions enable row level security;

create policy payroll_finance_handoff_batches_select_scoped on app.payroll_finance_handoff_batches
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_payroll_authority('View payroll', tenant_id, auth.uid())
    or (app.evaluate_permission(auth.uid(), tenant_id, 'FIN', 'View')).allowed
  );

create policy payroll_finance_handoff_gl_lines_select_scoped on app.payroll_finance_handoff_gl_lines
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_payroll_authority('View payroll', tenant_id, auth.uid())
    or (app.evaluate_permission(auth.uid(), tenant_id, 'FIN', 'View')).allowed
  );

create policy payroll_finance_handoff_payment_instructions_select_scoped on app.payroll_finance_handoff_payment_instructions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid())
    or (app.evaluate_permission(auth.uid(), tenant_id, 'FIN', 'View')).allowed
  );

comment on policy payroll_finance_handoff_batches_select_scoped on app.payroll_finance_handoff_batches is
  'HRT-282 migration 2: readable by either side of the handoff boundary -- Payroll (HRS:View payroll) or Finance (FIN:View) -- never by plain tenant membership.';

-- ===========================================================================
-- Grants. Per ERR-2026-004: explicit REVOKE before this migration's own
-- final grants. Re-stated explicitly (decision 1's own primary claim):
-- zero GRANT of any kind, anywhere in this migration, on any app.finance_*
-- table, app.journal_entries, app.finance_settlements, or app.finance_
-- payments.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.payroll_finance_handoff_batches to authenticated, service_role;
grant select on app.payroll_finance_handoff_gl_lines to authenticated, service_role;
grant select on app.payroll_finance_handoff_payment_instructions to authenticated, service_role;

grant insert, update, delete on app.payroll_finance_handoff_batches to service_role;
grant insert, update, delete on app.payroll_finance_handoff_gl_lines to service_role;
grant insert, update, delete on app.payroll_finance_handoff_payment_instructions to service_role;

grant execute on function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.search_payroll_finance_handoffs_pending_acknowledgement(uuid, uuid) to authenticated, service_role;
grant execute on function app.acknowledge_payroll_finance_handoff_batch(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_payroll_finance_handoff_reconciliation(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_payroll_finance_handoff_batch(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_finance_handoff_gl_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_finance_handoff_payment_instructions(uuid, uuid) to authenticated, service_role;
