-- Finance capability FIN-212 (Job, Customer and Service Profitability, CG-S9-FIN-023)
-- Finance-grade, versioned profitability by Job Order using source-linked billed
-- revenue (FIN-197's own issued invoices) and governed actual cost (OPS-178's own
-- approved actual-cost versions) -- never an editable summary figure.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **This is the Finance-grade counterpart of OPS-179's own operational
--   snapshot, deliberately reading a different revenue basis.** OPS-179's
--   `app.job_profitability_snapshots` reads `app.job_orders.revenue_snapshot`
--   verbatim -- the Commercial-accepted *sell price*, an operational estimate,
--   never re-derived here. This capability reads the actual *billed* amount
--   from every `status = 'issued'` `app.finance_invoices` row for the Job
--   Order (`subtotal_amount`, excluding tax -- tax is a pass-through liability,
--   never a component of margin) -- the exact accounting-truth basis Prompt
--   212 section 24's "revenue/cost derives from source/subledger/GL under
--   captured policy" requires. `revenue_basis` is recorded on every fact row
--   (fixed to `'billed'` this checkpoint, a real single-value CHECK constraint,
--   not a fabricated enum of bases nothing here computes) so operational
--   estimate and accounting P&L are never conflated (section 24's own
--   explicit requirement).
-- * **Cost is the identical source OPS-179 already established: the sum of
--   every currently-approved OPS-178 actual-cost version** across every
--   Shipment Order belonging to the Job Order (`is_current = true and status
--   = 'approved'` only). No separate Finance-posted, job-dimensioned cost
--   source exists anywhere in this repository yet -- `app.finance_vendor_bills`
--   (FIN-199/200) carries no Job Order or Shipment Order linkage -- so this
--   migration reuses OPS-178's own governed cost evidence rather than
--   inventing a duplicate, ungoverned second cost source. A real AP-to-job
--   cost linkage is left for a later capability, the same class of disclosed,
--   bounded scope decision this checkpoint's own prompt package already
--   establishes throughout Phase 4.
-- * **No shared-cost/overhead allocation engine is implemented this
--   checkpoint.** Every OPS-178 cost component is already directly
--   attributable to exactly one Shipment Order (and therefore exactly one
--   Job Order) -- there is no indirect/shared-cost table anywhere in this
--   repository for an allocation engine to distribute. `revenue_basis` and
--   this header comment are the disclosed bound (Prompt 212 section 24's
--   "governed allocation" requirement is therefore satisfied by direct,
--   versioned attribution of every source line, not by a rule engine that
--   would otherwise have nothing real to allocate). A genuine shared-cost
--   allocation-rule engine is left for a later capability once an indirect
--   cost source exists to allocate.
-- * **Currency discipline mirrors OPS-179 exactly, extended to a second
--   source.** No FX conversion is performed. A currency mismatch across
--   multiple issued invoices for the same Job Order, or between the resolved
--   revenue currency and any contributing cost version, makes the whole fact
--   `unavailable` with a named `blocked_reason` (`no_billed_revenue`,
--   `no_approved_cost`, or `mixed_currency`) -- never a silently-wrong
--   cross-currency subtraction or a fabricated zero.
-- * **Versioned fact, historical versions remain linked, never rewritten in
--   place** (section 24): `app.finance_job_profitability_facts` is
--   `is_current`-exclusive (partial unique index); the first calculation for
--   a Job Order needs no reason, but every subsequent recalculation while a
--   current fact already exists requires a non-empty `recalculation_reason`
--   -- the identical "adjustment preserves lineage" discipline OPS-179's own
--   `app.calculate_job_profitability` already established.
-- * **Explainability reuses `source_invoice_ids`/`source_cost_version_ids`,
--   no second read path is invented.** Both arrays name the exact
--   `app.finance_invoices`/`app.shipment_actual_costs` rows summed --
--   already independently readable (governed, tenant/record-scoped) by any
--   caller who can see this fact in the first place, so no bespoke "explain"
--   RPC duplicates that existing surface (OPS-179's own precedent).
-- * **Deny outright, no partial projection -- stricter than OPS-179's own
--   base-table grant.** Every non-shell column on this fact row is
--   margin-shaped (Prompt 212 section 16: "aggregate suppression prevents
--   inference; customer users cannot see internal profitability"). Unlike
--   OPS-179's `job_profitability_snapshots` (which grants `authenticated`
--   direct, RLS-scoped select against the base table alongside its own masked
--   directory view), this table grants `authenticated` no table privilege at
--   all -- the only read paths are `app.get_finance_job_profitability` and
--   `app.get_finance_profitability_summary`, both of which deny outright
--   (raise, no partial result) to an actor lacking `FIN:View margin`, the
--   same "either fully visible or fully hidden" precedent OPS-178's own
--   `app.shipment_actual_cost_components` established for a fully
--   cost-shaped row.
-- * **`FIN:View margin` is already a seeded permission action** -- the base
--   permission catalogue (`20260716103445_create_roles_permissions.sql`)
--   registers `('View margin', 'FIN', 'sensitive', true)` from day one, so
--   this migration registers no new catalogue row; `app.has_view_finance_margin`
--   is simply this capability's own thin wrapper, the same
--   one-shared-permission-action/one-wrapper-per-capability precedent
--   `COM-156`/`OPS-179` already established for their own modules.
-- * **Aggregation is grouped, never a raw per-row export.** `job_order_id`,
--   `account_id` (customer), `org_unit_id` (branch) and the Job Order's own
--   `cargo_service_snapshot ->> 'service_type'` (service) are the only
--   grouping dimensions this checkpoint supports -- exactly the "job,
--   customer, service, branch" set Prompt 212 section 3 names. A currency
--   mismatch within a group is never silently summed across currencies:
--   the aggregation itself groups by `(dimension, currency)`, so a
--   multi-currency book of business surfaces as separate rows per currency,
--   never a blended, meaningless total.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--   carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
--   FROM PUBLIC` statement before its final grants, the standing
--   per-migration convention since `PLT-118`.

create function app.has_view_finance_margin(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'FIN', 'View margin')).allowed;
$$;

comment on function app.has_view_finance_margin is
  'FIN-212: thin wrapper over app.evaluate_permission(..., ''FIN'', ''View margin'') -- the same fixed 19-action PLT-111 vocabulary already seeded for the FIN module at 20260716103445, reused here rather than registering a duplicate catalogue row.';

create function app.check_finance_profitability_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_profitability_authority is
  'FIN-212: FIN:Edit (paired with FIN:View margin) gates app.calculate_finance_job_profitability -- a governed recalculation, not a routine edit of an editable figure.';

create table app.finance_job_profitability_facts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  status text not null,
  blocked_reason text,
  revenue_basis text not null default 'billed',
  revenue_currency text,
  revenue_amount numeric(14, 2),
  cost_currency text,
  cost_amount numeric(14, 2),
  profit_amount numeric(14, 2),
  margin_percent numeric(9, 4),
  source_invoice_ids uuid[] not null default '{}',
  source_cost_version_ids uuid[] not null default '{}',
  recalculation_reason text,
  calculated_by_auth_user_id uuid not null,
  calculated_at timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_job_profitability_facts_status_check check (status in ('calculated', 'unavailable')),
  constraint finance_job_profitability_facts_blocked_reason_check check (status <> 'unavailable' or (blocked_reason is not null and length(trim(blocked_reason)) > 0)),
  constraint finance_job_profitability_facts_basis_check check (revenue_basis = 'billed'),
  constraint finance_job_profitability_facts_version_number_check check (version_number > 0)
);

comment on table app.finance_job_profitability_facts is
  'FIN-212: one versioned, deterministic Finance profitability fact per Job Order (is_current exclusive via partial unique index). revenue_basis is fixed to ''billed'' this checkpoint -- the actual issued-invoice amount, never the Commercial revenue_snapshot estimate OPS-179''s own operational snapshot reads. status=unavailable (with a named blocked_reason) whenever no issued invoice exists, no approved cost exists, or currencies do not reconcile -- never a fabricated zero/guessed value. Grants no authenticated table privilege at all (deny outright) -- app.get_finance_job_profitability/app.get_finance_profitability_summary are the only read paths, both gated on FIN:View margin.';

create unique index finance_job_profitability_facts_one_current_idx on app.finance_job_profitability_facts (job_order_id) where is_current;
create index finance_job_profitability_facts_tenant_job_idx on app.finance_job_profitability_facts (tenant_id, job_order_id);

create function app.touch_finance_job_profitability_facts_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_job_profitability_facts_touch_row
  before update on app.finance_job_profitability_facts
  for each row
  execute function app.touch_finance_job_profitability_facts_row();

-- The one calculation path (Prompt 212 section 21/24). Revenue is resolved
-- first (every issued invoice for the Job Order); cost is only evaluated once
-- revenue resolves to a single currency, mirroring OPS-179's own two-source
-- reconciliation discipline extended to a second, genuinely-optional source.
create function app.calculate_finance_job_profitability(
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

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_finance_job_profitability',
    'app.finance_job_profitability_facts', v_fact.id, 'success', p_recalculation_reason, null, to_jsonb(v_fact)
  );

  return v_fact;
end;
$$;

-- Drill-down read (Prompt 212 section 21's own "permits drill-down to
-- transaction/journal evidence"): source_invoice_ids/source_cost_version_ids
-- name the exact rows already independently readable through FIN-197's own
-- invoice reads and OPS-178's own actual-cost reads -- no second copy of that
-- evidence is stored or exposed here. Deny outright without FIN:View margin.
create function app.get_finance_job_profitability(p_job_order_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_job_profitability_facts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;
  if not app.has_view_finance_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_job_profitability_facts where job_order_id = p_job_order_id and is_current;
end;
$$;

-- Grouped, field-safe aggregation (Prompt 212 section 17/25: bounded
-- aggregates, no SELECT * / raw per-row export). Groups by (dimension,
-- currency) -- a multi-currency book of business surfaces as separate rows,
-- never a silently blended cross-currency total. Only calculated, current
-- facts contribute; a blocked fact is excluded, never guessed into a total.
create function app.get_finance_profitability_summary(
  p_tenant_id uuid,
  p_group_by text,
  p_actor_auth_user_id uuid
)
returns table (
  dimension_key text,
  dimension_label text,
  currency text,
  job_count bigint,
  revenue_amount numeric,
  cost_amount numeric,
  profit_amount numeric,
  margin_percent numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.has_view_finance_margin(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_group_by not in ('customer', 'branch', 'service') then
    raise exception 'finance_profitability_invalid_group_by: % is not a supported grouping dimension', p_group_by
      using errcode = 'check_violation';
  end if;

  if p_group_by = 'customer' then
    return query
      select
        jo.account_id::text, a.legal_name, f.revenue_currency, count(*)::bigint,
        sum(f.revenue_amount), sum(f.cost_amount), sum(f.profit_amount),
        case when sum(f.revenue_amount) <> 0 then round((sum(f.profit_amount) / sum(f.revenue_amount)) * 100, 4) else null end
      from app.finance_job_profitability_facts f
      join app.job_orders jo on jo.id = f.job_order_id
      join app.accounts a on a.id = jo.account_id
      where f.tenant_id = p_tenant_id and f.is_current and f.status = 'calculated'
      group by jo.account_id, a.legal_name, f.revenue_currency
      order by sum(f.profit_amount) desc nulls last;
  elsif p_group_by = 'branch' then
    return query
      select
        jo.org_unit_id::text, ou.name, f.revenue_currency, count(*)::bigint,
        sum(f.revenue_amount), sum(f.cost_amount), sum(f.profit_amount),
        case when sum(f.revenue_amount) <> 0 then round((sum(f.profit_amount) / sum(f.revenue_amount)) * 100, 4) else null end
      from app.finance_job_profitability_facts f
      join app.job_orders jo on jo.id = f.job_order_id
      left join app.org_units ou on ou.id = jo.org_unit_id
      where f.tenant_id = p_tenant_id and f.is_current and f.status = 'calculated'
      group by jo.org_unit_id, ou.name, f.revenue_currency
      order by sum(f.profit_amount) desc nulls last;
  else
    return query
      select
        coalesce(jo.cargo_service_snapshot ->> 'service_type', 'unspecified'),
        coalesce(jo.cargo_service_snapshot ->> 'service_type', 'unspecified'),
        f.revenue_currency, count(*)::bigint,
        sum(f.revenue_amount), sum(f.cost_amount), sum(f.profit_amount),
        case when sum(f.revenue_amount) <> 0 then round((sum(f.profit_amount) / sum(f.revenue_amount)) * 100, 4) else null end
      from app.finance_job_profitability_facts f
      join app.job_orders jo on jo.id = f.job_order_id
      where f.tenant_id = p_tenant_id and f.is_current and f.status = 'calculated'
      group by coalesce(jo.cargo_service_snapshot ->> 'service_type', 'unspecified'), f.revenue_currency
      order by sum(f.profit_amount) desc nulls last;
  end if;
end;
$$;

alter table app.finance_job_profitability_facts enable row level security;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

-- No authenticated table privilege at all (deny outright, this migration's
-- own header) -- service_role only.
grant select on app.finance_job_profitability_facts to service_role;
grant insert, update, delete on app.finance_job_profitability_facts to service_role;

grant execute on function app.has_view_finance_margin(uuid, uuid) to authenticated, service_role;
grant execute on function app.check_finance_profitability_authority(text, uuid, uuid) to service_role;
grant execute on function app.calculate_finance_job_profitability(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_finance_job_profitability(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_profitability_summary(uuid, text, uuid) to authenticated, service_role;
