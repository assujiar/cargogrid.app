-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 6
-- (platform-intelligence-reports) batch 4 of 4 -- the FINAL batch of cluster 6
-- (supabase/migrations/20260913040000_close_o1_query_layer_cluster6_batch4_scheduled_reports_dashboards.sql).
--
-- Proves, against a real disposable database, that all 10 new function pairs (20
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim.
--
-- Two RLS shapes:
--
-- SHAPE 1 (6 tables: scheduled_reports/scheduled_report_recipients/
-- scheduled_report_runs/tenant_dashboards/tenant_dashboard_versions/
-- tenant_dashboard_widgets) -- a tenant-membership predicate WITH an explicit
-- OR is_supreme_admin() disjunct at the policy level. Exercised with the SAME
-- 5-persona sweep this series has used many times before: the OWNER, a real
-- non-owner tenant member (proving tenant-wide, not owner-scoped, visibility --
-- app.report_runs' own precedent, cited by the dashboard_builder migration's own
-- header), a customer_user-layer principal with real active membership (denied
-- despite membership), a cross-tenant admin (denied), and a global Supreme Admin
-- with ZERO membership in this tenant (sees everything via the explicit
-- policy-level disjunct).
--
-- SHAPE 2 (app.list_supreme_tenants over app.tenants) -- NO explicit
-- is_supreme_admin() disjunct at the policy level (tenants_select_own_tenant's
-- CURRENT text, re-verified live: `has_active_tenant_membership(id) AND NOT
-- actor_holds_customer_user_layer(id)`), relying entirely on
-- has_active_tenant_membership's own internal Supreme Admin coverage. Proven
-- without assuming how many OTHER tenants the shared full-suite database
-- happens to contain (267+ other db-test files each provision their own): the
-- Supreme Admin persona's own expected page count is computed dynamically from
-- a raw `count(*)` under that SAME session (which itself already proves
-- has_active_tenant_membership resolves true platform-wide for a Supreme
-- Admin), never hardcoded; a non-Supreme member is proven to see EXACTLY their
-- own one tenant row, never a leak -- the one assertion this shape actually
-- needs, and the one a global fixture count could never make fragile.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c6b4 with an owner (999701) and a second real active org_user member (999702, NOT the owner), a customer_user-layer principal in the SAME tenant (999703), a global Supreme Admin with ZERO membership in this tenant (999704), and a second, isolated tenant gizmoo1c6b4 with its own tenant_admin (999705)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999701', 'ownero1c6b4@example.test'),
    ('00000000-0000-0000-0000-000000999702', 'membero1c6b4@example.test'),
    ('00000000-0000-0000-0000-000000999703', 'customerusero1c6b4@example.test'),
    ('00000000-0000-0000-0000-000000999704', 'supremeo1c6b4@example.test'),
    ('00000000-0000-0000-0000-000000999705', 'othertenanto1c6b4@example.test');

  perform app.provision_tenant('acmeo1c6b4', 'Acme O1C6B4 Co', 'idem-acmeo1c6b4', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c6b4');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999701', 'ownero1c6b4@example.test', 'Owner', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c6b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999701', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999702', 'membero1c6b4@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c6b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999702', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000999703', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999703', 'customer_user', v_tenant_id, 'fake-account-ref-o1c6b4', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999704', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c6b4', 'Gizmo O1C6B4 Co', 'idem-gizmoo1c6b4', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c6b4');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999705', 'othertenanto1c6b4@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c6b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999705', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: 2 app.scheduled_reports rows for acmeo1c6b4 (owned by 999701, report_type_code finance_billing_summary -- pre-existing, never retired by any fixture), inserted with updated_at ASCENDING (so updated_at desc output is proven, not coincidental); 2 recipients on schedule one (999701, 999702) inserted with created_at ASCENDING; 2 runs on schedule one inserted with started_at ASCENDING'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_sched1_id uuid := gen_random_uuid();
  v_sched2_id uuid := gen_random_uuid();
begin
  insert into app.scheduled_reports (
    id, tenant_id, report_type_code, owner_auth_user_id, name, description,
    cron_minute, cron_hour, cron_day_of_month, cron_day_of_week, timezone, filters,
    status, next_run_at, created_by, created_at, updated_at
  ) values
    (v_sched1_id, v_tenant_id, 'finance_billing_summary', '00000000-0000-0000-0000-000000999701', 'O1C6B4 Schedule One', '',
     0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, 'active', now() + interval '1 day', 'tester', now() - interval '2 hours', now() - interval '2 hours'),
    (v_sched2_id, v_tenant_id, 'finance_billing_summary', '00000000-0000-0000-0000-000000999701', 'O1C6B4 Schedule Two', '',
     30, 10, null, null, 'Asia/Jakarta', '{}'::jsonb, 'active', now() + interval '1 day', 'tester', now() - interval '1 hour', now() - interval '1 hour');

  insert into app.scheduled_report_recipients (id, scheduled_report_id, recipient_auth_user_id, added_by_auth_user_id, created_at)
  values
    (gen_random_uuid(), v_sched1_id, '00000000-0000-0000-0000-000000999701', '00000000-0000-0000-0000-000000999701', now() - interval '2 hours'),
    (gen_random_uuid(), v_sched1_id, '00000000-0000-0000-0000-000000999702', '00000000-0000-0000-0000-000000999701', now() - interval '1 hour');

  insert into app.scheduled_report_runs (id, scheduled_report_id, occurrence_at, status, triggered_by_auth_user_id, triggered_by_label, started_at)
  values
    (gen_random_uuid(), v_sched1_id, now() - interval '2 hours', 'completed', '00000000-0000-0000-0000-000000999701', 'tester', now() - interval '2 hours'),
    (gen_random_uuid(), v_sched1_id, now() - interval '1 hour', 'queued', '00000000-0000-0000-0000-000000999701', 'tester', now() - interval '1 hour');
end $$;

\echo '>> app.list_scheduled_reports/app.get_scheduled_report_by_id: ordering fidelity (updated_at desc) and not-found is genuinely empty; app.list_scheduled_report_recipients: ordering fidelity (created_at asc); app.list_scheduled_report_runs: ordering fidelity (started_at desc)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_sched1_id uuid := (select id from app.scheduled_reports where tenant_id = v_tenant_id and name = 'O1C6B4 Schedule One');
  v_sched2_id uuid := (select id from app.scheduled_reports where tenant_id = v_tenant_id and name = 'O1C6B4 Schedule Two');
  v_names text[];
  v_recipients uuid[];
  v_run_statuses text[];
  v_count integer;
begin
  select array_agg(name) into v_names from app.list_scheduled_reports(v_tenant_id);
  if v_names <> array['O1C6B4 Schedule Two', 'O1C6B4 Schedule One'] then
    raise exception 'assertion failed: list_scheduled_reports must return [Two, One] (updated_at desc), got %', v_names;
  end if;

  if (select id from app.get_scheduled_report_by_id(v_sched1_id)) <> v_sched1_id then
    raise exception 'assertion failed: get_scheduled_report_by_id must resolve schedule one';
  end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent schedule id must return a genuinely empty result, got %', v_count; end if;

  select array_agg(recipient_auth_user_id) into v_recipients from app.list_scheduled_report_recipients(v_sched1_id);
  if v_recipients <> array['00000000-0000-0000-0000-000000999701'::uuid, '00000000-0000-0000-0000-000000999702'::uuid] then
    raise exception 'assertion failed: list_scheduled_report_recipients must return [999701, 999702] (created_at asc), got %', v_recipients;
  end if;

  select array_agg(status) into v_run_statuses from app.list_scheduled_report_runs(v_sched1_id);
  if v_run_statuses <> array['queued', 'completed'] then
    raise exception 'assertion failed: list_scheduled_report_runs must return [queued, completed] (started_at desc), got %', v_run_statuses;
  end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id, 1);
  if v_count <> 1 then raise exception 'assertion failed: list_scheduled_report_runs must honor p_limit, got %', v_count; end if;

  perform 1 from app.scheduled_reports where id = v_sched2_id;

  raise notice 'app.scheduled_reports/recipients/runs proof: ordering fidelity correct for all 3 functions, not-found genuinely empty, p_limit honored';
end $$;

\echo '>> 5-persona RLS sweep across the 4 scheduled-report functions: OWNER (999701) and a real non-owner tenant MEMBER (999702) both see everything (tenant-wide, not owner-scoped); a customer_user-layer principal (999703, real active membership) sees nothing; a cross-tenant admin (999705) sees nothing; the Supreme Admin (999704, ZERO membership) sees everything via the explicit policy-level OR is_supreme_admin()'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_sched1_id uuid := (select id from app.scheduled_reports where tenant_id = v_tenant_id and name = 'O1C6B4 Schedule One');
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999701", "role": "authenticated"}';
  select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 2 then raise exception 'owner: expected 2 schedules, got %', v_count; end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 1 then raise exception 'owner: expected schedule to resolve'; end if;
  select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 2 then raise exception 'owner: expected 2 recipients, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 2 then raise exception 'owner: expected 2 runs, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999702", "role": "authenticated"}';
  select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 schedules (tenant-wide visibility), got %', v_count; end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 1 then raise exception 'non-owner member: expected schedule to resolve'; end if;
  select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 recipients, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 runs, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999703", "role": "authenticated"}';
  select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 schedules, got %', v_count; end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected schedule to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 recipients, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 runs, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999705", "role": "authenticated"}';
  select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 schedules, got %', v_count; end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected schedule to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 recipients, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 runs, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999704", "role": "authenticated"}';
  select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 schedules via explicit OR is_supreme_admin(), got %', v_count; end if;
  select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 1 then raise exception 'supreme admin: expected schedule to resolve'; end if;
  select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 recipients, got %', v_count; end if;
  select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 runs, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'scheduled-report family RLS proof: owner and a real non-owner tenant member both see everything (tenant-wide), customer_user-layer/cross-tenant both denied on all 4 functions, Supreme Admin (zero membership) sees everything via the explicit policy-level disjunct';
end $$;

\echo '>> app.list_supreme_tenants: dynamic pagination proof (never assumes a fixed global tenant count -- 267+ other db-test files each provision their own tenants under the shared full-suite database)'
do $$
declare
  v_supreme_total integer;
  v_expected_page integer;
  v_page_count integer;
  v_distinct_total_count integer;
  v_single_total_count bigint;
  v_names text[];
  v_page1_name text;
  v_page2_name text;
  v_page1_total bigint;
  v_page2_total bigint;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999704", "role": "authenticated"}';

  select count(*) into v_supreme_total from app.tenants;
  if v_supreme_total < 2 then
    raise exception 'assertion failed: expected the Supreme Admin to see at least the 2 fixture tenants, got %', v_supreme_total;
  end if;

  v_expected_page := least(v_supreme_total, 100);
  select count(*) into v_page_count from app.list_supreme_tenants(1, 100);
  if v_page_count <> v_expected_page then
    raise exception 'assertion failed: expected page 1 (size 100) to return least(total, 100) = % rows, got %', v_expected_page, v_page_count;
  end if;

  select count(distinct total_count) into v_distinct_total_count from app.list_supreme_tenants(1, 100);
  if v_distinct_total_count <> 1 then
    raise exception 'assertion failed: every row of one page must carry the SAME total_count (count(*) over() is computed over the full visible set before limit/offset), got % distinct values', v_distinct_total_count;
  end if;
  select total_count into v_single_total_count from app.list_supreme_tenants(1, 100) limit 1;
  if v_single_total_count <> v_supreme_total then
    raise exception 'assertion failed: total_count must equal the raw platform-wide count seen by this Supreme Admin (%), got %', v_supreme_total, v_single_total_count;
  end if;

  select array_agg(name) into v_names from app.list_supreme_tenants(1, 100);
  if v_names <> (select array_agg(x order by x) from unnest(v_names) as x) then
    raise exception 'assertion failed: expected list_supreme_tenants to be sorted ascending by name, got %', v_names;
  end if;

  select name, total_count into v_page1_name, v_page1_total from app.list_supreme_tenants(1, 1);
  select name, total_count into v_page2_name, v_page2_total from app.list_supreme_tenants(2, 1);
  if v_page1_name >= v_page2_name then
    raise exception 'assertion failed: expected page 2 (offset 1) to return a strictly later name than page 1, got % then %', v_page1_name, v_page2_name;
  end if;
  if v_page1_total <> v_supreme_total or v_page2_total <> v_supreme_total then
    raise exception 'assertion failed: total_count must be identical across pages (% vs % vs raw %)', v_page1_total, v_page2_total, v_supreme_total;
  end if;

  reset role; reset request.jwt.claims;

  raise notice 'app.list_supreme_tenants (Supreme Admin) proof: dynamic page-count/offset/total_count/ordering all correct regardless of the shared suite''s own global tenant count (%)', v_supreme_total;
end $$;

\echo '>> app.list_supreme_tenants: a non-Supreme member sees EXACTLY their own one tenant (never a leak); a cross-tenant admin sees EXACTLY their own one tenant; a customer_user-layer principal (denied membership visibility) sees zero'
do $$
declare
  v_count integer;
  v_slug text;
  v_total bigint;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999701", "role": "authenticated"}';
  select count(*) into v_count from app.list_supreme_tenants(1, 100);
  if v_count <> 1 then raise exception 'assertion failed: a non-Supreme tenant member must see EXACTLY 1 tenant (their own), got %', v_count; end if;
  select slug, total_count into v_slug, v_total from app.list_supreme_tenants(1, 100);
  if v_slug <> 'acmeo1c6b4' or v_total <> 1 then
    raise exception 'assertion failed: expected the single visible row to be acmeo1c6b4 with total_count=1, got slug=% total_count=%', v_slug, v_total;
  end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999705", "role": "authenticated"}';
  select count(*) into v_count from app.list_supreme_tenants(1, 100);
  if v_count <> 1 then raise exception 'assertion failed: a cross-tenant admin must see EXACTLY 1 tenant (their own), got %', v_count; end if;
  select slug into v_slug from app.list_supreme_tenants(1, 100);
  if v_slug <> 'gizmoo1c6b4' then raise exception 'assertion failed: expected the single visible row to be gizmoo1c6b4, got %', v_slug; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999703", "role": "authenticated"}';
  select count(*) into v_count from app.list_supreme_tenants(1, 100);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero tenants, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'app.list_supreme_tenants (non-Supreme personas) proof: a real tenant member/cross-tenant admin each see EXACTLY their own one tenant, never a leak; customer_user-layer sees zero -- the same safe-by-construction behavior the original .from() read already had, merely restored';
end $$;

\echo '>> fixture: 2 app.tenant_dashboards rows for acmeo1c6b4 (created_by 999701), inserted with updated_at ASCENDING; 2 app.tenant_dashboard_versions rows on dashboard one -- version 2 inserted BEFORE version 1, proving the real ORDER BY version_number desc, not insertion order; 2 app.tenant_dashboard_widgets rows on version one -- display_order=1 inserted BEFORE display_order=0, proving the real ORDER BY display_order asc'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_dash1_id uuid := gen_random_uuid();
  v_dash2_id uuid := gen_random_uuid();
  v_version1_id uuid := gen_random_uuid();
  v_version2_id uuid := gen_random_uuid();
begin
  insert into app.tenant_dashboards (id, tenant_id, name, description, status, created_by_auth_user_id, created_by, created_at, updated_at)
  values
    (v_dash1_id, v_tenant_id, 'O1C6B4 Dashboard One', '', 'draft', '00000000-0000-0000-0000-000000999701', 'tester', now() - interval '2 hours', now() - interval '2 hours'),
    (v_dash2_id, v_tenant_id, 'O1C6B4 Dashboard Two', '', 'draft', '00000000-0000-0000-0000-000000999701', 'tester', now() - interval '1 hour', now() - interval '1 hour');

  insert into app.tenant_dashboard_versions (id, dashboard_id, version_number, layout, status, created_at)
  values
    (v_version2_id, v_dash1_id, 2, '{}'::jsonb, 'draft', now() - interval '1 day'),
    (v_version1_id, v_dash1_id, 1, '{}'::jsonb, 'draft', now() - interval '2 days');

  insert into app.tenant_dashboard_widgets (id, dashboard_version_id, report_type_code, title, position, parameter_overrides, display_order, created_at)
  values
    (gen_random_uuid(), v_version1_id, 'finance_billing_summary', 'O1C6B4 Widget Two', '{}'::jsonb, '{}'::jsonb, 1, now() - interval '1 hour'),
    (gen_random_uuid(), v_version1_id, 'finance_billing_summary', 'O1C6B4 Widget One', '{}'::jsonb, '{}'::jsonb, 0, now() - interval '2 hours');
end $$;

\echo '>> app.list_tenant_dashboards/app.get_tenant_dashboard_by_id: ordering fidelity (updated_at desc) and not-found is genuinely empty; app.list_tenant_dashboard_versions/app.get_tenant_dashboard_version_by_id: ordering fidelity (version_number desc); app.list_dashboard_widgets: ordering fidelity (display_order asc)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_dash1_id uuid := (select id from app.tenant_dashboards where tenant_id = v_tenant_id and name = 'O1C6B4 Dashboard One');
  v_version1_id uuid := (select id from app.tenant_dashboard_versions where dashboard_id = v_dash1_id and version_number = 1);
  v_names text[];
  v_versions integer[];
  v_titles text[];
  v_count integer;
begin
  select array_agg(name) into v_names from app.list_tenant_dashboards(v_tenant_id);
  if v_names <> array['O1C6B4 Dashboard Two', 'O1C6B4 Dashboard One'] then
    raise exception 'assertion failed: list_tenant_dashboards must return [Two, One] (updated_at desc), got %', v_names;
  end if;

  if (select id from app.get_tenant_dashboard_by_id(v_dash1_id)) <> v_dash1_id then
    raise exception 'assertion failed: get_tenant_dashboard_by_id must resolve dashboard one';
  end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent dashboard id must return a genuinely empty result, got %', v_count; end if;

  select array_agg(version_number) into v_versions from app.list_tenant_dashboard_versions(v_dash1_id);
  if v_versions <> array[2, 1] then
    raise exception 'assertion failed: list_tenant_dashboard_versions must return [2, 1] (version_number desc), got %', v_versions;
  end if;

  if (select id from app.get_tenant_dashboard_version_by_id(v_version1_id)) <> v_version1_id then
    raise exception 'assertion failed: get_tenant_dashboard_version_by_id must resolve version one';
  end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent version id must return a genuinely empty result, got %', v_count; end if;

  select array_agg(title) into v_titles from app.list_dashboard_widgets(v_version1_id);
  if v_titles <> array['O1C6B4 Widget One', 'O1C6B4 Widget Two'] then
    raise exception 'assertion failed: list_dashboard_widgets must return [Widget One, Widget Two] (display_order asc), got %', v_titles;
  end if;

  raise notice 'app.tenant_dashboards/versions/widgets proof: ordering fidelity correct for all 3 functions, not-found genuinely empty regardless of physical insertion order';
end $$;

\echo '>> 5-persona RLS sweep across the 5 tenant-dashboard functions: OWNER (999701) and a real non-owner tenant MEMBER (999702) both see everything (tenant-wide, not owner-scoped); a customer_user-layer principal (999703) sees nothing; a cross-tenant admin (999705) sees nothing; the Supreme Admin (999704, ZERO membership) sees everything via the explicit policy-level OR is_supreme_admin()'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
  v_dash1_id uuid := (select id from app.tenant_dashboards where tenant_id = v_tenant_id and name = 'O1C6B4 Dashboard One');
  v_version1_id uuid := (select id from app.tenant_dashboard_versions where dashboard_id = v_dash1_id and version_number = 1);
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999701", "role": "authenticated"}';
  select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 2 then raise exception 'owner: expected 2 dashboards, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 1 then raise exception 'owner: expected dashboard to resolve'; end if;
  select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 2 then raise exception 'owner: expected 2 versions, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 1 then raise exception 'owner: expected version to resolve'; end if;
  select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 2 then raise exception 'owner: expected 2 widgets, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999702", "role": "authenticated"}';
  select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 dashboards (tenant-wide visibility), got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 1 then raise exception 'non-owner member: expected dashboard to resolve'; end if;
  select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 versions, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 1 then raise exception 'non-owner member: expected version to resolve'; end if;
  select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 2 then raise exception 'non-owner member: expected 2 widgets, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999703", "role": "authenticated"}';
  select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 dashboards, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected dashboard to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 versions, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected version to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 0 then raise exception 'customer_user-layer: expected 0 widgets, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999705", "role": "authenticated"}';
  select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 dashboards, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected dashboard to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 versions, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected version to NOT resolve, got %', v_count; end if;
  select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 0 then raise exception 'cross-tenant admin: expected 0 widgets, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999704", "role": "authenticated"}';
  select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 dashboards via explicit OR is_supreme_admin(), got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 1 then raise exception 'supreme admin: expected dashboard to resolve'; end if;
  select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 versions, got %', v_count; end if;
  select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 1 then raise exception 'supreme admin: expected version to resolve'; end if;
  select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 2 then raise exception 'supreme admin: expected 2 widgets, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'tenant-dashboard family RLS proof: owner and a real non-owner tenant member both see everything (tenant-wide), customer_user-layer/cross-tenant both denied on all 5 functions, Supreme Admin (zero membership) sees everything via the explicit policy-level disjunct, including through the TWO-LEVEL EXISTS join for widgets';
end $$;

\echo '>> anon defense in depth: all 10 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_scheduled_reports(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_scheduled_reports';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_scheduled_reports correctly rejected anon';
    end;

    begin
      perform public.get_scheduled_report_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_scheduled_report_by_id';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_scheduled_report_by_id correctly rejected anon';
    end;

    begin
      perform public.list_scheduled_report_recipients(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_scheduled_report_recipients';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_scheduled_report_recipients correctly rejected anon';
    end;

    begin
      perform public.list_scheduled_report_runs(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_scheduled_report_runs';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_scheduled_report_runs correctly rejected anon';
    end;

    begin
      perform public.list_supreme_tenants(1, 10);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_supreme_tenants';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_supreme_tenants correctly rejected anon';
    end;

    begin
      perform public.list_tenant_dashboards(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_tenant_dashboards';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_tenant_dashboards correctly rejected anon';
    end;

    begin
      perform public.get_tenant_dashboard_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_tenant_dashboard_by_id';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_tenant_dashboard_by_id correctly rejected anon';
    end;

    begin
      perform public.list_tenant_dashboard_versions(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_tenant_dashboard_versions';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_tenant_dashboard_versions correctly rejected anon';
    end;

    begin
      perform public.get_tenant_dashboard_version_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_tenant_dashboard_version_by_id';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_tenant_dashboard_version_by_id correctly rejected anon';
    end;

    begin
      perform public.list_dashboard_widgets(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_dashboard_widgets';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_dashboard_widgets correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: all 10 SECURITY INVOKER functions succeed via service_role''s own direct grant / BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b4');
    v_sched1_id uuid := (select id from app.scheduled_reports where tenant_id = v_tenant_id and name = 'O1C6B4 Schedule One');
    v_dash1_id uuid := (select id from app.tenant_dashboards where tenant_id = v_tenant_id and name = 'O1C6B4 Dashboard One');
    v_version1_id uuid := (select id from app.tenant_dashboard_versions where dashboard_id = v_dash1_id and version_number = 1);
    v_count integer;
  begin
    select count(*) into v_count from app.list_scheduled_reports(v_tenant_id); if v_count <> 2 then raise exception 'service_role: expected 2 schedules, got %', v_count; end if;
    select count(*) into v_count from app.get_scheduled_report_by_id(v_sched1_id); if v_count <> 1 then raise exception 'service_role: expected schedule to resolve'; end if;
    select count(*) into v_count from app.list_scheduled_report_recipients(v_sched1_id); if v_count <> 2 then raise exception 'service_role: expected 2 recipients, got %', v_count; end if;
    select count(*) into v_count from app.list_scheduled_report_runs(v_sched1_id); if v_count <> 2 then raise exception 'service_role: expected 2 runs, got %', v_count; end if;
    select count(*) into v_count from app.list_supreme_tenants(1, 100); if v_count < 2 then raise exception 'service_role: expected at least 2 tenants, got %', v_count; end if;
    select count(*) into v_count from app.list_tenant_dashboards(v_tenant_id); if v_count <> 2 then raise exception 'service_role: expected 2 dashboards, got %', v_count; end if;
    select count(*) into v_count from app.get_tenant_dashboard_by_id(v_dash1_id); if v_count <> 1 then raise exception 'service_role: expected dashboard to resolve'; end if;
    select count(*) into v_count from app.list_tenant_dashboard_versions(v_dash1_id); if v_count <> 2 then raise exception 'service_role: expected 2 versions, got %', v_count; end if;
    select count(*) into v_count from app.get_tenant_dashboard_version_by_id(v_version1_id); if v_count <> 1 then raise exception 'service_role: expected version to resolve'; end if;
    select count(*) into v_count from app.list_dashboard_widgets(v_version1_id); if v_count <> 2 then raise exception 'service_role: expected 2 widgets, got %', v_count; end if;

    raise notice 'service_role proof: all 10 SECURITY INVOKER functions succeed regardless of membership (BYPASSRLS)';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 10 new cluster-6-batch-4 function pairs (20 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 10 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_scheduled_reports', 'get_scheduled_report_by_id', 'list_scheduled_report_recipients',
      'list_scheduled_report_runs', 'list_supreme_tenants', 'list_tenant_dashboards',
      'get_tenant_dashboard_by_id', 'list_tenant_dashboard_versions', 'get_tenant_dashboard_version_by_id',
      'list_dashboard_widgets'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 10 cluster-6-batch-4 function pairs (20 functions, either schema), found % grants', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_scheduled_reports', 'get_scheduled_report_by_id', 'list_scheduled_report_recipients',
      'list_scheduled_report_runs', 'list_supreme_tenants', 'list_tenant_dashboards',
      'get_tenant_dashboard_by_id', 'list_tenant_dashboard_versions', 'get_tenant_dashboard_version_by_id',
      'list_dashboard_widgets'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 10 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 40 grants (10 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 20 new cluster-6-batch-4 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 10 pairs';
end $$;

\echo '>> o1-query-layer-cluster6-batch4.sql test suite passed -- cluster 6 batch 4 (scheduled reports, supreme tenants, tenant dashboards -- 10/30 call sites, 30/30 cumulative) is now fully DONE. Cluster 6 (platform-intelligence-reports) is now FULLY DONE.'
