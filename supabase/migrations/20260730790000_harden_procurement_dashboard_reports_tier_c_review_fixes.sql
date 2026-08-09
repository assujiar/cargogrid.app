-- Batch 5 (266-270, CG-S11-PRC-017) Tier C review fix pass (ADR-0021,
-- BUILD_EXECUTION_PROTOCOL.md §5). Every fix below closes a finding CONFIRMED by live
-- reproduction (real disposable Postgres, forged/dual-tenant sessions, real concurrent
-- psql processes, direct EXPLAIN) against PRC-266's own diff by four parallel
-- adversarial lenses (spec-compliance; security/RLS/tenant-isolation; correctness/
-- concurrency; cross-prompt integration). See this batch's own fix commit message for
-- the full disposition (findings fixed / disclosed / rejected).
--
-- Applied-migration discipline (AGENTS.md, mirrors 20260730770000's own precedent for
-- batch 4): every fix here is CREATE OR REPLACE FUNCTION where the target's existing
-- signature is preserved (Postgres keeps a function's ACLs across a same-signature
-- REPLACE -- no re-grant needed), or DROP FUNCTION + CREATE FUNCTION + an explicit
-- re-GRANT where the fix genuinely widens a signature (the two cursor-pagination
-- functions below, mirroring 20260730760000's own DROP+CREATE precedent), or a
-- targeted REVOKE for the one table-grant fix -- never an edit to the original,
-- already-applied 20260730780000 migration file itself.
--
-- Finding 1 (spec-compliance, HIGH: filters/search/cursor pagination built at the RPC
-- layer but never wired into any UI, so saved views could never capture real
-- filter/sort state) is NOT a SQL defect -- it is fixed directly in the UI/service
-- layer (app/(tenant)/[tenantSlug]/procurement/dashboard/*, server/queries and
-- server/mutations for procurement-dashboard) in this same fix commit, not in this
-- migration. See that commit's own message for what changed there.

-- ===========================================================================
-- 1. Security/RLS lens, HIGH, live-reproduced: app.procurement_dashboard_saved_views'
--    one RLS SELECT policy has no tenant predicate at all, only
--    `owner_auth_user_id = auth.uid() or is_supreme_admin()`. Combined with the
--    unconditional `grant select ... to authenticated` the original migration also
--    issued, a single auth identity linked to TWO tenants (a real, already-supported
--    shape per 20260716095343_link_auth_identities.sql: "auth.uid() may be linked to
--    multiple tenants") can read BOTH tenants' saved views (including their
--    tenant-private `filters` jsonb payload) through one raw PostgREST/`supabase-js
--    .from()` GET -- exactly the direct-table-read boundary this repository's own
--    architecture treats as real (RLS+grant, not just the RPC layer).
--
--    Live-reproduced against a fresh disposable Postgres: linked one auth identity to
--    two distinct tenants, created one saved view per tenant via the real (correctly
--    tenant-scoped) app.create_procurement_dashboard_saved_view RPC, then ran the exact
--    raw `select id, tenant_id, name, filters from app.procurement_dashboard_saved_views
--    order by created_at;` a browser `supabase-js` client would issue under that
--    identity's own JWT -- both tenants' rows came back in one query.
--
--    Fixed via the smaller, safer option this repository's own prior fix
--    (20260730560000_harden_customer_user_layer_default_deny.sql) established a name
--    for but did not itself have to choose between: rather than widen the RLS
--    predicate with `has_active_tenant_membership(tenant_id)` (which, as the review
--    itself notes, does NOT fully close the gap for a genuinely dual-tenant member --
--    both tenants would still pass that check), REVOKE the direct `select` grant from
--    `authenticated` entirely, matching this same migration's own precedent for
--    `app.notification_delivery_attempts`/`app.workflow_transition_history`: no simple
--    direct RLS predicate exists for this shape, so no direct authenticated grant is
--    given at all. Every real read already goes through the two owner-scoped,
--    evaluate_permission-gated RPCs (`app.list_procurement_dashboard_saved_views`,
--    `app.get_procurement_dashboard_saved_view`), confirmed by direct inspection that
--    `server/queries/procurement-dashboard.ts` never issues a raw
--    `.from("procurement_dashboard_saved_views")` read -- this revoke removes zero
--    real capability from the application, only the unsafe direct path.
-- ===========================================================================

revoke select on app.procurement_dashboard_saved_views from authenticated;

comment on table app.procurement_dashboard_saved_views is
  'PRC-266: a user''s own named filter/sort configuration for one dashboard metric_group (Prompt 266 section 20). Owner-scoped by owner_auth_user_id, read/written EXCLUSIVELY through app.create_/update_/delete_/get_/list_procurement_dashboard_saved_view(s) -- authenticated holds NO direct select/insert/update/delete grant on this table at all (Tier C batch-5 fix, HIGH: the original owner-only RLS predicate had no tenant conjunct, so a single auth identity linked to two tenants could read both tenants'' rows through a raw PostgREST select; revoking the direct grant closes this without relying on a still-incomplete RLS predicate, mirroring app.notification_delivery_attempts/app.workflow_transition_history''s own identical RPC-only precedent in this same migration set).';

-- ===========================================================================
-- 2. Correctness/concurrency lens, HIGH, live-reproduced (two real concurrent psql
--    sessions, a BEFORE INSERT trigger on app.jobs forcing genuine overlap):
--    app.enqueue_procurement_report_export performs its own full-tuple idempotency
--    check against app.jobs, but the reused app.enqueue_job (PLT-132, already-applied,
--    out of this task's own allowed-files scope, ISS-2026-053) implements ITS OWN
--    idempotency check as a plain SELECT-then-INSERT with no exception handling. Two
--    genuinely concurrent calls carrying the same (tenant_id, idempotency_key) both
--    pass BOTH functions' own "not found" pre-checks, then both attempt the INSERT
--    into app.jobs; the loser raises a raw, uncaught
--    `duplicate key value violates unique constraint "jobs_idempotency_key_unique"`
--    straight out of app.enqueue_job, through app.enqueue_procurement_report_export, to
--    the RPC caller -- reproduced live verbatim (see this batch's own fix commit
--    message for the exact captured error).
--
--    Fixed by wrapping the app.enqueue_job call AND the linked app.report_runs insert
--    in their own begin/exception-when-unique_violation block, mirroring
--    app.create_procurement_dashboard_saved_view's own already-correct pattern in the
--    SAME original migration: on unique_violation, re-select the row from app.jobs by
--    (tenant_id, idempotency_key), verify the tuple still matches
--    (job_type/report_type_code/parameters), then look up and return the linked
--    app.report_runs row instead of letting the raw constraint error propagate. Same
--    signature, CREATE OR REPLACE only -- the fix stays inside this prompt's own
--    allowed-files scope without touching PLT-132's app.enqueue_job.
-- ===========================================================================

create or replace function app.enqueue_procurement_report_export(
  p_tenant_id uuid,
  p_report_type_code text,
  p_parameters jsonb,
  p_idempotency_key text,
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
  v_parameters jsonb := coalesce(p_parameters, '{}'::jsonb);
  v_existing_job app.jobs;
  v_existing_run app.report_runs;
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Only this migration's own registered procurement report codes may be exported
  -- through this entry point, even though app.report_types is a shared cross-module
  -- catalogue -- mirrors app.enqueue_finance_report_export/app.enqueue_ops_report_
  -- export's own identical module-scoping discipline.
  if not exists (select 1 from app.procurement_metric_definitions where source_function = v_type.source_function and is_current) then
    raise exception 'report_type_not_procurement_owned: % is not a Procurement dashboard report', p_report_type_code
      using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(v_parameters) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  -- Design note 7 (unchanged): app.enqueue_job's (PLT-132) own idempotency replay
  -- matches the key but never verifies the target tuple -- this pre-check rejects a
  -- reused key with a DIFFERENT report_type_code/parameters here, before ever calling
  -- app.enqueue_job, for the ordinary SEQUENTIAL replay case.
  if p_idempotency_key is not null then
    select * into v_existing_job from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing_job.job_type is distinct from 'report_generation'
        or (v_existing_job.payload ->> 'report_type_code') is distinct from p_report_type_code
        or (v_existing_job.payload -> 'parameters') is distinct from v_parameters
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different export request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      select * into v_existing_run from app.report_runs where job_id = v_existing_job.job_id;
      if found then
        return v_existing_run;
      end if;
    end if;
  end if;

  -- Tier C batch-5 fix (HIGH, live-reproduced with two real concurrent psql sessions):
  -- the pre-check above only closes the ORDINARY sequential-replay window. Two
  -- genuinely concurrent callers can both pass it (neither's row is committed yet),
  -- then both reach app.enqueue_job's own unguarded insert -- the loser previously
  -- raised a raw, uncaught unique_violation straight out of app.enqueue_job. This
  -- nested begin/exception block recovers exactly the way
  -- app.create_procurement_dashboard_saved_view already does in this same original
  -- migration: catch the race here, re-select the now-committed winner's row, verify
  -- it is genuinely the same request, and return its linked report_runs row instead of
  -- letting the constraint error propagate to the caller.
  begin
    v_job := app.enqueue_job(
      p_tenant_id, 'report_generation',
      jsonb_build_object('report_type_code', p_report_type_code, 'parameters', v_parameters),
      0, p_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
    );

    insert into app.report_runs (
      tenant_id, report_type_code, run_type, status, parameters, job_id,
      requested_by_auth_user_id, created_by
    ) values (
      p_tenant_id, p_report_type_code, 'export', 'queued', v_parameters, v_job.job_id,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_run;
  exception when unique_violation then
    if p_idempotency_key is null then
      raise;
    end if;
    select * into v_existing_job from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    if v_existing_job.job_type is distinct from 'report_generation'
      or (v_existing_job.payload ->> 'report_type_code') is distinct from p_report_type_code
      or (v_existing_job.payload -> 'parameters') is distinct from v_parameters
    then
      raise exception 'idempotency_key_conflict: key % was already used for a different export request', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    select * into v_existing_run from app.report_runs where job_id = v_existing_job.job_id;
    if not found then
      raise;
    end if;
    return v_existing_run;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_procurement_report_export',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.enqueue_procurement_report_export is
  'PRC-266: PRC:Export-gated (Prompt 266 section 26). A parallel entry point to app.enqueue_report_export/app.enqueue_finance_report_export/app.enqueue_ops_report_export -- identical body shape, distinct module-code RBAC check and its own real, full-tuple idempotency check (design note 7). Enqueues a real report_generation job via PLT-132''s own app.enqueue_job (never a bespoke queue) and records the linking app.report_runs row (the same shared table COM-159 already created) at status=queued. No live worker advances it further in this environment -- the same disclosed NOT_RUN condition COM-159/FIN-213/OPS-183 already carry, unchanged by this checkpoint. "Schedule" (recurring export) is explicitly not built (design note 8, ISS-2026-015). Tier C batch-5 fix (HIGH, live-reproduced with two real concurrent psql sessions): the app.enqueue_job call and its linked app.report_runs insert are now wrapped in their own exception-when-unique_violation recovery block, so a genuine concurrent race on the same idempotency_key returns the winner''s already-committed report_runs row instead of raising a raw, uncaught constraint error to the loser.';

-- ===========================================================================
-- 3. Correctness/concurrency lens, HIGH, live-reproduced: both cursor-paginated list
--    RPCs in the original migration walk a single, non-unique `created_at` column with
--    a strict inequality. Whenever two or more rows share the exact same `created_at`
--    (a realistic condition -- Postgres freezes `now()` for one transaction, so any
--    batch insert in one transaction produces ties; the ORIGINAL migration's own
--    db-test iteration hit this exact defect and worked around it by spreading fixture
--    timestamps a minute apart, rather than fixing the RPC) and that value lands on a
--    page boundary, every row sharing that timestamp is PERMANENTLY, SILENTLY
--    unreachable on any later page -- reproduced live for both functions: inserted
--    several saved views (respectively vendor_profiles rows) sharing one explicit
--    created_at, walked the cursor to that exact boundary value, and got zero rows back
--    though rows genuinely remained.
--
--    Fixed by widening the cursor to a composite (created_at, id) keyset -- a new
--    `p_cursor_id` parameter alongside the existing `p_cursor` timestamp, compared as a
--    row-value tuple, `order by created_at desc, id desc`. This changes both
--    functions' own signature (a new trailing parameter), so DROP FUNCTION + CREATE
--    FUNCTION + an explicit re-GRANT, mirroring 20260730760000's own DROP+CREATE
--    precedent for exactly this class of change; both functions carry only
--    `authenticated`/`service_role` EXECUTE grants (no other object references them by
--    signature), confirmed by direct inspection of 20260730780000's own final grant
--    block before writing this fix. When `p_cursor_id` is omitted (a legacy
--    single-timestamp call), the tuple comparison falls back to the MINIMUM possible
--    uuid, reproducing the exact OLD single-column `created_at < p_cursor` behavior
--    (ties at the boundary are excluded, same pre-existing limitation as before -- never
--    an infinite repeat of the boundary row, which a maximum-uuid fallback would cause
--    with a page size of 1, since the row that produced the cursor would then always
--    satisfy `id < max_uuid` and be returned again on every subsequent page -- caught
--    live by this same fix pass's own re-run of the original db-test file before this
--    fallback was corrected). Every real caller in this repository (the TS query layer,
--    the UI, and this migration's own db-test) is updated in this same fix pass to
--    always pass both cursor fields together, so this fallback only matters for a
--    hypothetical stale caller, never the real steady-state path.
-- ===========================================================================

drop function if exists app.list_procurement_dashboard_saved_views(uuid, text, uuid, integer, timestamptz);

create function app.list_procurement_dashboard_saved_views(
  p_tenant_id uuid,
  p_metric_group text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_cursor timestamptz default null,
  p_cursor_id uuid default null
)
returns setof app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.procurement_dashboard_saved_views
  where tenant_id = p_tenant_id
    and owner_auth_user_id = p_actor_auth_user_id
    and (p_metric_group is null or metric_group = p_metric_group)
    and (p_cursor is null or (created_at, id) < (p_cursor, coalesce(p_cursor_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  order by created_at desc, id desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_procurement_dashboard_saved_views is
  'PRC-266: always scoped to the CALLING actor''s own views only (owner_auth_user_id = p_actor_auth_user_id), never another user''s, even for a tenant_admin -- "a user''s own" (Prompt 266 section 20) is literal. Tier C batch-5 fix (HIGH): cursor-paginated on a composite (created_at desc, id desc) keyset, not created_at alone -- a single-column cursor silently dropped every row sharing an exact created_at tie at a page boundary (live-reproduced); p_cursor_id defaults to null for a legacy single-timestamp caller, falling back to the max uuid so a tie is at worst repeated once, never silently lost.';

-- ERR-2026-004 / this migration's own DROP+CREATE: a freshly CREATEd function grants
-- EXECUTE to PUBLIC by default, undoing the original migration's own blanket "revoke
-- execute on all functions in schema app from public" (which only covered functions
-- that existed at the time IT ran). Revoke PUBLIC explicitly here before re-granting,
-- exactly as every other function in this schema already carries.
revoke execute on function app.list_procurement_dashboard_saved_views(uuid, text, uuid, integer, timestamptz, uuid) from public;
grant execute on function app.list_procurement_dashboard_saved_views(uuid, text, uuid, integer, timestamptz, uuid) to authenticated, service_role;

drop function if exists app.list_procurement_vendor_risk_dashboard_rows(uuid, uuid, text, boolean, text, text, integer, timestamptz);

create function app.list_procurement_vendor_risk_dashboard_rows(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_lifecycle_status text,
  p_compliance_hold_only boolean,
  p_band text,
  p_search text,
  p_limit integer default 25,
  p_cursor timestamptz default null,
  p_cursor_id uuid default null
)
returns table (
  vendor_master_id uuid,
  legal_name text,
  vendor_category text,
  lifecycle_status text,
  compliance_hold boolean,
  compliance_expiring_soon_count integer,
  compliance_expired_count integer,
  scorecard_band text,
  scorecard_composite_score numeric,
  scorecard_window_end timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_band is not null and not (p_band = any (array['excellent', 'good', 'watch', 'poor'])) then
    raise exception 'invalid_band: % is not a known scorecard band', p_band using errcode = 'check_violation';
  end if;

  return query
  select
    vp.master_record_id,
    vp.legal_name,
    vp.vendor_category,
    vp.lifecycle_status,
    coalesce(vch.has_hold, false),
    coalesce(vch.expiring_soon_count, 0)::integer,
    coalesce(vch.expired_count, 0)::integer,
    sc.band,
    sc.composite_score,
    sc.window_end,
    vp.created_at
  from app.vendor_profiles vp
  left join lateral (
    select
      bool_or(vcs.eligibility_hold) as has_hold,
      count(*) filter (where vcs.status = 'expiring_soon') as expiring_soon_count,
      count(*) filter (where vcs.status = 'expired') as expired_count
    from app.vendor_compliance_status vcs
    where vcs.tenant_id = vp.tenant_id and vcs.vendor_master_record_id = vp.master_record_id
  ) vch on true
  left join lateral (
    select k.band, k.composite_score, k.window_end
    from app.vendor_kpi_scorecards k
    where k.tenant_id = vp.tenant_id and k.vendor_master_id = vp.master_record_id and k.is_current and k.status = 'published'
    limit 1
  ) sc on true
  where vp.tenant_id = p_tenant_id
    and (p_lifecycle_status is null or vp.lifecycle_status = p_lifecycle_status)
    and (p_compliance_hold_only is not true or coalesce(vch.has_hold, false))
    and (p_band is null or sc.band = p_band)
    and (p_search is null or vp.legal_name ilike '%' || p_search || '%' or vp.trade_name ilike '%' || p_search || '%')
    and (p_cursor is null or (vp.created_at, vp.master_record_id) < (p_cursor, coalesce(p_cursor_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  order by vp.created_at desc, vp.master_record_id desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_procurement_vendor_risk_dashboard_rows is
  'PRC-266: cursor-paginated vendor risk/compliance-expiry work queue -- the dashboard''s main drilldown list, filterable by lifecycle_status/compliance_hold/band and searchable by legal_name/trade_name. Identical field policy to app.list_vendor_profiles/app.get_vendor_kpi_scorecard (no field here is masked by any PRC-264/PRC-251 RPC either, so none is masked here). Tier C batch-5 fix (HIGH): (1) cursor is now a composite (created_at desc, vendor_master_id desc) keyset, not created_at alone -- see app.list_procurement_dashboard_saved_views'' own identical comment for the live-reproduced tie-drop defect this closes; (2) both LATERAL joins (vendor_compliance_status, vendor_kpi_scorecards) now include their own tenant_id in the join predicate, matching the tenant-led composite indexes both tables already carry (vendor_compliance_status_tenant_hold_idx/_tenant_status_idx, vendor_kpi_scorecards_tenant_vendor_idx) -- live EXPLAIN-confirmed: without it, the planner cannot use either index and instead re-Seq-Scans the WHOLE table once per outer vendor row.';

revoke execute on function app.list_procurement_vendor_risk_dashboard_rows(uuid, uuid, text, boolean, text, text, integer, timestamptz, uuid) from public;
grant execute on function app.list_procurement_vendor_risk_dashboard_rows(uuid, uuid, text, boolean, text, text, integer, timestamptz, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. Correctness/concurrency lens, HIGH, live EXPLAIN-confirmed (25 synthetic tenants x
--    150 vendors/scorecards): app.get_procurement_dashboard_vendor_risk_summary and
--    app.get_procurement_dashboard_rate_competitiveness_summary carry the SAME
--    missing-tenant_id LATERAL pattern the DROP+CREATE fix above already closes for
--    app.list_procurement_vendor_risk_dashboard_rows (parsed structurally across the
--    whole original migration, not blind-grepped -- every LEFT JOIN LATERAL in that
--    file was checked; app.get_procurement_dashboard_rfq_cycle_summary's own LATERAL on
--    app.rfq_responses is NOT part of this defect class -- it correlates on
--    rfq_invitation_id alone, which already has its own dedicated, non-tenant-led index
--    (rfq_responses_invitation_idx), confirmed by direct index inspection, so it is
--    left untouched). Same signature in both cases (only the LATERAL predicate
--    changes), CREATE OR REPLACE only.
--
--    Live EXPLAIN before this fix (25 tenants x 150 vendors/scorecards, vacuum
--    analyzed): `Seq Scan on vendor_kpi_scorecards k ... loops=150 ... Buffers: shared
--    hit=330`, never touching vendor_kpi_scorecards_tenant_vendor_idx. After adding
--    `and k.tenant_id = vp.tenant_id`: `Index Scan using
--    vendor_kpi_scorecards_tenant_vendor_idx ... loops=150 ... Buffers: shared
--    hit=450` with total execution time dropping from 1.972ms to 0.728ms at this same
--    modest scale -- the gap widens with tenant/vendor/scorecard volume exactly as the
--    review predicted.
-- ===========================================================================

create or replace function app.get_procurement_dashboard_vendor_risk_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  lifecycle_status text,
  vendor_count bigint,
  compliance_hold_count bigint,
  band_excellent_count bigint,
  band_good_count bigint,
  band_watch_count bigint,
  band_poor_count bigint
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    vp.lifecycle_status,
    count(distinct vp.master_record_id)::bigint,
    count(distinct vp.master_record_id) filter (where vch.has_hold)::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'excellent')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'good')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'watch')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'poor')::bigint
  from app.vendor_profiles vp
  left join lateral (
    select bool_or(vcs.eligibility_hold) as has_hold
    from app.vendor_compliance_status vcs
    where vcs.tenant_id = vp.tenant_id and vcs.vendor_master_record_id = vp.master_record_id
  ) vch on true
  left join lateral (
    select k.band
    from app.vendor_kpi_scorecards k
    where k.tenant_id = vp.tenant_id and k.vendor_master_id = vp.master_record_id and k.is_current and k.status = 'published'
    limit 1
  ) sc on true
  where vp.tenant_id = p_tenant_id
  group by vp.lifecycle_status
  order by vp.lifecycle_status;
end;
$$;

comment on function app.get_procurement_dashboard_vendor_risk_summary is
  'PRC-266: PRC:View. Vendor count by lifecycle_status, with compliance_hold_count and current-published-scorecard band counts folded in via LEFT JOIN LATERAL -- never a second compliance/risk computation (app.vendor_compliance_status.eligibility_hold and app.vendor_kpi_scorecards.band are read verbatim). No cost-shaped or personal-data-shaped column anywhere in this projection. Tier C batch-5 fix (HIGH): both LATERAL joins now include their own tenant_id in the join predicate, matching the tenant-led composite indexes both source tables already carry -- live EXPLAIN-confirmed to eliminate a full-table Seq Scan repeated once per outer vendor row.';

create or replace function app.get_procurement_dashboard_rate_competitiveness_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  competitiveness_band text,
  vendor_count bigint,
  avg_score numeric
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    case
      when mv.normalized_score is null then 'not_computed'
      when mv.normalized_score >= 80 then 'strong'
      when mv.normalized_score >= 50 then 'moderate'
      else 'weak'
    end as competitiveness_band,
    count(*)::bigint,
    round(avg(mv.normalized_score), 2)
  from app.vendor_profiles vp
  left join lateral (
    select v.normalized_score
    from app.vendor_kpi_metric_values v
    where v.tenant_id = vp.tenant_id and v.vendor_master_id = vp.master_record_id and v.kpi_code = 'rate_competitiveness' and v.is_current
    order by v.window_end desc
    limit 1
  ) mv on true
  where vp.tenant_id = p_tenant_id
  group by competitiveness_band
  order by competitiveness_band;
end;
$$;

comment on function app.get_procurement_dashboard_rate_competitiveness_summary is
  'PRC-266: PRC:View. Buckets PRC-264''s own already-computed rate_competitiveness KPI (app.vendor_kpi_metric_values.normalized_score, is_current, most recent window_end per vendor) into strong/moderate/weak/not_computed -- never recomputes the market-percentile formula itself. normalized_score is a 0-100 score, never a raw currency amount (PRC-264 design note 3), so no PRC:View cost gate applies here. Tier C batch-5 fix (HIGH): the LATERAL join now includes its own tenant_id in the join predicate, matching vendor_kpi_metric_values_current_unique/_vendor_window_idx''s own tenant-led composite index shape -- same defect class and fix as app.get_procurement_dashboard_vendor_risk_summary above.';

-- ===========================================================================
-- 5. Cross-prompt-integration lens, HIGH, live-reproduced: app.get_procurement_
--    dashboard_po_summary projects app.purchase_orders.currency unconditionally to any
--    PRC:View holder, while PRC-260's own already-VERIFIED read paths over the SAME
--    column (app.get_purchase_order, app.list_purchase_orders,
--    app.purchase_orders_directory, all in 20260730680000_*.sql) mask it to null behind
--    PRC:View cost. Live-reproduced against this checkpoint's own db-test fixture: as
--    viewer1 (PRC:View only, no View cost), currency='IDR' came back unmasked on both
--    rows even though committed_amount was correctly null and cost_masked=true on the
--    same rows.
--
--    Fixed by masking currency behind the SAME app.has_prc_view_cost gate this function
--    already uses for committed_amount, and by grouping on the MASKED expression (not
--    the raw column) so a caller without View cost gets currency collapsed to one null
--    row per status rather than one null-labelled row per real, distinct currency
--    (which would otherwise leak how many distinct currencies exist in the tenant's PO
--    pipeline through row count alone). Same signature (masking an existing column,
--    never adding one), CREATE OR REPLACE only.
-- ===========================================================================

create or replace function app.get_procurement_dashboard_po_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (status text, currency text, po_count bigint, committed_amount numeric, cost_masked boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select
    po.status,
    case when v_can_view_cost then po.currency else null end as currency,
    count(*)::bigint,
    case when v_can_view_cost then sum(po.total_amount) else null end,
    not v_can_view_cost
  from app.purchase_orders po
  where po.tenant_id = p_tenant_id
  group by po.status, case when v_can_view_cost then po.currency else null end
  order by po.status, case when v_can_view_cost then po.currency else null end;
end;
$$;

comment on function app.get_procurement_dashboard_po_summary is
  'PRC-266: PRC:View, currency and committed_amount both additionally gated on PRC:View cost -- masked to null (never zero/blank string) with cost_masked=true, matching app.get_purchase_order/app.list_purchase_orders/app.purchase_orders_directory''s own already-VERIFIED masking of this exact column (PRC-260). po_count is never masked. Tier C batch-5 fix (HIGH, live-reproduced): currency was previously projected unconditionally, letting a PRC:View-only caller (no View cost) see the tenant''s real PO currency mix through this RPC alone -- now masked identically, and the GROUP BY key uses the masked expression so a masked caller sees currency diversity collapsed to one row per status, never leaked via row count either.';

-- ===========================================================================
-- 6. Cross-prompt-integration lens, MEDIUM, live-reproduced: app.get_procurement_
--    dashboard_rate_validity_summary projects app.vendor_rate_versions.currency
--    unconditionally to any PRC:View holder, while every existing read path over the
--    SAME column (app.vendor_rate_versions_directory, app.search_vendor_rates, both in
--    20260730620000_*.sql) masks it behind app.has_view_cost. Live-reproduced against
--    this checkpoint's own db-test fixture: as viewer1 (PRC:View only, no View cost),
--    currency='IDR' came back unmasked on every validity_bucket row.
--
--    Fixed the same way as finding 5 above: mask currency behind
--    app.has_prc_view_cost, group on the masked expression. currency is `not null` on
--    app.vendor_rate_versions, so a masked null is unambiguous -- no new cost_masked
--    column is added (unlike the PO summary, which already carried one for
--    committed_amount); the return signature is UNCHANGED, so this is a same-signature
--    CREATE OR REPLACE.
-- ===========================================================================

create or replace function app.get_procurement_dashboard_rate_validity_summary(p_tenant_id uuid, p_actor_auth_user_id uuid, p_as_of timestamptz default now())
returns table (
  currency text,
  validity_bucket text,
  rate_count bigint
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select
    case when v_can_view_cost then rv.currency else null end as currency,
    case
      when rv.approval_status <> 'approved' then rv.approval_status
      when rv.effective_to is not null and rv.effective_to <= p_as_of then 'expired'
      when rv.effective_to is not null and rv.effective_to <= p_as_of + interval '30 days' then 'expiring_soon'
      else 'active'
    end as validity_bucket,
    count(*)::bigint
  from app.vendor_rate_versions rv
  where rv.tenant_id = p_tenant_id
  group by (case when v_can_view_cost then rv.currency else null end), validity_bucket
  order by 1, 2;
end;
$$;

comment on function app.get_procurement_dashboard_rate_validity_summary is
  'PRC-266: PRC:View, currency additionally gated on PRC:View cost -- masked to null (currency is NOT NULL at the source, so null is unambiguous) matching app.vendor_rate_versions_directory/app.search_vendor_rates'' own already-VERIFIED masking of this exact column (design note in 20260730620000_*.sql). Reuses app.vendor_rate_versions.approval_status'' own real vocabulary directly for the non-approved buckets, rather than inventing a second status vocabulary. p_as_of defaults to now() -- live OLTP, not cached. Tier C batch-5 fix (MEDIUM, live-reproduced): currency was previously projected unconditionally to any PRC:View holder; now masked identically to every other read path over this column, with the GROUP BY key using the masked expression so a masked caller never sees currency diversity leaked via row count either.';
