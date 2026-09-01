-- ISS-2026-197 labeling fragment (docs/runtime/KNOWN_ISSUES.md) -- purely additive fix.
--
-- `app.calculate_job_profitability` (Operations, OPS-179) is, and remains, a deliberate
-- planned-vs-actual split: it reports the Job Order's own quote-time
-- `revenue_snapshot.totalAmount`, never a re-derived or actual-billed figure -- that design
-- is correct and unchanged by this migration (see `20260728120000_create_operations_job_
-- profitability.sql`'s own header). What was genuinely missing is a marker: unlike its
-- Finance-side sibling `app.finance_job_profitability_facts` (FIN-212), which already
-- self-labels its own basis via a `revenue_basis` column fixed to `'billed'` (a real
-- single-value CHECK constraint, a table comment, a Zod `z.literal('billed')`, and UI copy
-- that shows the basis next to the figure), the Operations snapshot carried no equivalent
-- anywhere -- not on the table, not in its Zod contract, not in the exposing view, not in
-- the UI. An API consumer or a screen reading `app.job_profitability_snapshots` had zero
-- indication its revenue figure is a quote-time estimate rather than a billed amount. This
-- migration gives Operations the identical self-describing marker Finance already has,
-- fixed to a single literal value (`'quoted'`) -- never a fabricated multi-value enum,
-- since nothing here computes a second basis for this table. Scope is the labeling gap
-- only; the FX/currency-conversion behavior this same KNOWN_ISSUES entry also disclosed
-- (no FX conversion anywhere in the revenue chain; a currency mismatch makes the whole
-- calculation `unavailable`/`mixed_currency` rather than converting) is untouched --
-- `scripts/db-tests/operations-job-profitability.sql`'s own deliberate mixed-currency
-- fixture and its assertions are not edited here, only appended to.
--
-- Four objects touched, all additive:
--  1. `app.job_profitability_snapshots` gains `revenue_basis text not null default 'quoted'`
--     plus a single-value CHECK constraint (`= 'quoted'`), mirroring FIN-212's own
--     `finance_job_profitability_facts_basis_check` shape exactly. Table/column comments
--     updated to name the contrast with Finance's own `'billed'` basis.
--  2. `app.calculate_job_profitability` is rebuilt via `CREATE OR REPLACE FUNCTION`, body
--     copied verbatim from the LIVE `pg_get_functiondef` output (re-verified identical to
--     the original migration -- no drift since `20260728120000`), with `revenue_basis`
--     added to its one INSERT. `language plpgsql`, `security definer`, and the exact
--     `set search_path = app, pg_temp` clause are restated explicitly -- omitting any of
--     these on a bare `CREATE OR REPLACE FUNCTION` silently resets the attribute to its
--     default (`security invoker`, default search_path), a real, previously-fixed
--     recurrence in this exact codebase (`ISS-2026-318`, repaired at
--     `20260831290000_restore_security_definer_on_drifted_finance_wrappers.sql`; that
--     migration's own header documents exactly this failure mode -- "replacing a function
--     does not reliably reset its security attribute" -- for a bare wrapper missing the
--     flag altogether, the same class of drift this migration deliberately avoids by
--     restating every attribute explicitly).
--  3. `app.job_profitability_directory` is rebuilt via `CREATE OR REPLACE VIEW`,
--     `revenue_basis` appended as the LAST column in the SELECT list (`CREATE OR REPLACE
--     VIEW` fails on a reordered/mid-list column set) and deliberately placed OUTSIDE the
--     `app.has_view_job_margin(...)`-gated CASE expressions that mask revenue/cost/margin
--     -- a viewer who cannot see the margin figures still needs to know which basis a row
--     represents, the same way `status`/`blocked_reason` are already unmasked. `CREATE OR
--     REPLACE VIEW` preserves the view's existing ACL, but the `authenticated`/
--     `service_role` grant is re-asserted below anyway, defensively.
--  4. `public.calculate_job_profitability` (the PostgREST wrapper, `RGL-394` Option-2,
--     `20260826000000_create_public_api_data_wrappers.sql`) is left untouched -- verified
--     live: it `returns app.job_profitability_snapshots` by type reference, not an explicit
--     column list, so the new column flows through automatically.
--
-- Verified live before writing this migration (against a disposable database built from
-- every migration up to and including `20260901040000`):
--  * `app.trg_capture_lineage_job_to_profitability` (the transaction-lineage capture
--    trigger on this table, `20260728170000_create_operations_transaction_lineage.sql`)
--    digests four explicitly-named columns only (`revenue_amount`, `cost_amount`,
--    `margin_amount`, `status`) -- it does not `select *`, so this new column changes
--    nothing about its lineage hash/digest. No edit needed there, and none made.
--  * `app.calculate_job_profitability`'s live body was byte-for-byte identical to the
--    original `20260728120000` migration -- no drift to reconcile.

alter table app.job_profitability_snapshots
  add column revenue_basis text not null default 'quoted';

alter table app.job_profitability_snapshots
  add constraint job_profitability_snapshots_basis_check check (revenue_basis = 'quoted');

comment on column app.job_profitability_snapshots.revenue_basis is
  'ISS-2026-197: fixed single-value marker (''quoted'' only, CHECK-enforced) distinguishing this table''s quote-time operational estimate from app.finance_job_profitability_facts.revenue_basis (''billed'', the actual invoiced amount for the same Job Order) -- never a computed multi-value enum, since nothing on this table computes a second basis. Never masked alongside revenue/cost/margin in app.job_profitability_directory -- a viewer without OPS:View margin still needs to know which basis a row represents.';

comment on table app.job_profitability_snapshots is
  'OPS-179: one versioned, deterministic operational-margin snapshot per Job Order (is_current exclusive via partial unique index). status=unavailable (with a named blocked_reason) whenever no approved cost exists or currencies do not reconcile -- never a fabricated zero/guessed value. source_cost_version_ids names the exact app.shipment_actual_costs rows summed, the capability''s own explainability seam (already independently readable, no second read path invented). ISS-2026-197: revenue_basis is fixed to ''quoted'' -- the Commercial-accepted, quote-time sell price read verbatim from app.job_orders.revenue_snapshot, an operational estimate, never re-derived or reconciled against actual billing. Contrast: app.finance_job_profitability_facts (FIN-212) is the accounting-truth counterpart, revenue_basis fixed to ''billed'' there -- the actual amount from every issued app.finance_invoices row for the same Job Order. The two figures are deliberately independent, can legitimately differ (e.g. this table''s revenue is the quote''s tax-inclusive total, Finance''s is the pre-tax billed subtotal), and neither is wrong.';

-- Rebuilt via CREATE OR REPLACE FUNCTION -- body copied verbatim from the LIVE
-- pg_get_functiondef output (re-verified byte-for-byte identical to the original
-- 20260728120000 migration before this edit), with revenue_basis added to the one INSERT.
-- language/security definer/search_path restated explicitly (see header).
create or replace function app.calculate_job_profitability(
  p_job_order_id uuid,
  p_recalculation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_profitability_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing_current app.job_profitability_snapshots;
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_cost_count integer;
  v_cost_version_ids uuid[];
  v_status text;
  v_blocked_reason text;
  v_margin_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_snapshot app.job_profitability_snapshots;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_job_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'job_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability snapshot' using errcode = 'check_violation';
  end if;

  v_revenue_currency := v_job.revenue_snapshot ->> 'currency';
  v_revenue_amount := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);

  select count(distinct sac.currency), count(*), coalesce(sum(sac.total_amount), 0), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_cost_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_approved_cost';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  elsif v_cost_currency_count > 1 or (select sac.currency from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1]) <> v_revenue_currency then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  else
    v_status := 'calculated';
    v_blocked_reason := null;
    v_cost_currency := v_revenue_currency;
    v_margin_amount := v_revenue_amount - v_cost_amount;
    v_margin_percent := case when v_revenue_amount <> 0 then round((v_margin_amount / v_revenue_amount) * 100, 4) else null end;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.job_profitability_snapshots set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.job_profitability_snapshots (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason, revenue_basis,
    revenue_currency, revenue_amount, cost_currency, cost_amount, margin_amount, margin_percent,
    source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason, 'quoted',
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_margin_amount, v_margin_percent,
    v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_job_profitability',
    'app.job_profitability_snapshots', v_snapshot.id, 'success', p_recalculation_reason, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$$;

-- Rebuilt via CREATE OR REPLACE VIEW -- revenue_basis appended as the LAST column,
-- deliberately outside every app.has_view_job_margin(...) masking CASE (see header).
create or replace view app.job_profitability_directory
as
select
  jps.id, jps.tenant_id, jps.job_order_id, jps.version_number, jps.is_current, jps.status, jps.blocked_reason,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_currency else null end as revenue_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_amount else null end as revenue_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_currency else null end as cost_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_amount else null end as cost_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_amount else null end as margin_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_percent else null end as margin_percent,
  case when app.has_view_job_margin(jps.tenant_id) then jps.source_cost_version_ids else '{}'::uuid[] end as source_cost_version_ids,
  not app.has_view_job_margin(jps.tenant_id) as margin_masked,
  jps.recalculation_reason, jps.calculated_by_auth_user_id, jps.calculated_at, jps.record_version, jps.created_by, jps.created_at, jps.updated_at,
  jps.revenue_basis
from app.job_profitability_snapshots jps
join app.job_orders jo on jo.id = jps.job_order_id
where app.can_access_record(auth.uid(), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null);

comment on view app.job_profitability_directory is
  'OPS-179: field-masked projection of app.job_profitability_snapshots -- revenue/cost/margin amounts and source_cost_version_ids nulled/emptied (margin_masked=true) without OPS:View margin. ISS-2026-197: revenue_basis (fixed ''quoted'') is metadata, never a computed figure, so it is exposed unconditionally, even when margin_masked=true or status=unavailable.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant execute on function app.calculate_job_profitability(uuid, text, uuid, text) to authenticated, service_role;
grant select on app.job_profitability_directory to authenticated, service_role;
