-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 3
-- (operations-tms-core) batch 3 of ~N
-- (supabase/migrations/20260911030000_close_o1_query_layer_cluster3_batch3_route_planning.sql).
--
-- Proves, against a real disposable database, that all 8 new functions -- ALL
-- SECURITY INVOKER with ZERO actor parameter, relying entirely on the CALLING
-- SESSION's own live RLS (forced via `set local role authenticated; set local
-- request.jwt.claims = '{"sub": ..., "role": "authenticated"}'`, this repo's own
-- established idiom, mirroring cluster 3 batch 2's own PART 1 tests) -- return
-- exactly what their own comments and this migration's own header claim:
--
--   * app.list_route_planning_scenarios / app.get_route_planning_scenario /
--     app.list_route_planning_constraints / app.list_route_planning_candidate_plans
--     (1/2-hop through app.shipment_orders) and app.list_route_planning_score_components
--     (3-hop through app.route_planning_candidate_plans -> app.route_planning_scenarios
--     -> app.shipment_orders) / app.get_current_route_planning_selection /
--     app.list_route_planning_selections / app.list_route_planning_replan_events
--     (2-hop) all return the real rows an owner or a shared-org-unit member (same
--     org unit, not the owner) can see; a real tenant member with no owner/org-unit
--     relationship to the underlying shipment order, and a cross-tenant member,
--     both get zero rows from every one of the 8 functions, never an exception; a
--     Supreme Admin with ZERO tenant membership anywhere still sees the real rows
--     (app.can_access_record's own is_supreme_admin branch).
--   * app.get_route_planning_scenario and app.get_current_route_planning_selection,
--     the two 0-or-1-row lookups this migration's own header singles out for the
--     SETOF-vs-BARE-COMPOSITE defect class: a nonexistent id (resp. a real scenario
--     with no current selection yet) comes back as a GENUINELY EMPTY result --
--     count(*)=0 AND no row at all via exists() -- never one row of all-NULL columns.
--   * Ordering fidelity: list_route_planning_scenarios (created_at desc),
--     list_route_planning_candidate_plans (plan_rank asc), and
--     list_route_planning_selections (selected_at desc) all come back in the
--     documented order -- verified against rows inserted deliberately OUT of that
--     order, with no extra ORDER BY added at the call site (so the assertion
--     genuinely exercises the function body's own ORDER BY, not a re-sort of the
--     result); list_route_planning_constraints/list_route_planning_score_components/
--     list_route_planning_replan_events are only checked for row-set membership (no
--     ordering claimed by either the migration or the original .from() calls).
--   * Column-semantics proof for app.route_planning_replan_events: filtering on
--     `scenario_id` (the freshly created replan target) returns the fixture row,
--     filtering on `previous_scenario_id` (the old scenario being replaced) returns
--     zero rows -- confirming the migration's own derivation that this function
--     answers "what was I replanned FROM", not "what did I get replanned INTO".
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any
-- of the 16 new functions in EITHER schema (app or public) -- a real call attempt
-- against every one of the 8 public.* wrappers, not merely an information_schema
-- read -- and (spot-checked on 3 of the 8 pairs) authenticated/service_role hold
-- EXECUTE on both the app.* function and its public.* wrapper, exactly as this
-- migration's own GRANT PARITY section declares; and a quick service_role
-- (BYPASSRLS) smoke check confirms it can read via the function too, granting no
-- new capability beyond its own pre-existing direct table grants (this migration's
-- own header already argues why).

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c3b3 with an owner (org_user), a shared-org-unit member (same org unit, not the owner), a non-owning/non-org-unit member, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant gizmoo1c3b3 with its own admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998901', 'ownero1c3b3@example.test'),
    ('00000000-0000-0000-0000-000000998902', 'sharedvieweramo1c3b3@example.test'),
    ('00000000-0000-0000-0000-000000998903', 'deniedmembero1c3b3@example.test'),
    ('00000000-0000-0000-0000-000000998904', 'supremeo1c3b3@example.test'),
    ('00000000-0000-0000-0000-000000998905', 'othertenanto1c3b3@example.test');

  perform app.provision_tenant('acmeo1c3b3', 'Acme O1C3B3 Co', 'idem-acmeo1c3b3', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c3b3');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C3B3-CO', 'Acme O1C3B3 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B3-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998901', 'ownero1c3b3@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c3b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998901', 'org_user', v_tenant_id, null, 'tester');

  -- Same org_unit_id as the owner -- app.can_access_record's shared-org-unit branch
  -- admits this identity to every row owned by 998901 in this org unit, without being
  -- the owner itself.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998902', 'sharedvieweramo1c3b3@example.test', 'Shared Viewer', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sharedvieweramo1c3b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998902', 'org_user', v_tenant_id, null, 'tester');

  -- A real active org_user member of the SAME tenant, but no org_unit (so the
  -- shared-org-unit branch never matches), not the owner of anything, and no
  -- customer-account membership -- the exact per-row denial (not tenant-membership
  -- denial) app.can_access_record's own coalesce(..., false) is meant to produce.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998903', 'deniedmembero1c3b3@example.test', 'Denied Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'deniedmembero1c3b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998903', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998904', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c3b3', 'Gizmo O1C3B3 Co', 'idem-gizmoo1c3b3', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c3b3');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998905', 'othertenanto1c3b3@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c3b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998905', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors cluster 3 batch 1/batch 2's own
-- job-order-chain helpers, trimmed to just what a Shipment Order needs
-- (app.shipment_orders.job_order_id is NOT NULL): the
-- lead->prospect->opportunity->quotation->job_order_handoff->job_order chain, real
-- rows throughout, never a raw shortcut into app.job_orders alone.
create function app._o1c3b3_test_make_job_order_chain(p_tenant uuid, p_org_unit uuid, p_owner uuid, p_tag text)
returns table (job_order_id uuid, handoff_id uuid, quotation_id uuid, account_id uuid)
language plpgsql
as $$
declare
  v_lead uuid;
  v_prospect uuid;
  v_opportunity uuid;
  v_quotation uuid;
  v_handoff uuid;
  v_account uuid;
  v_job_order uuid;
begin
  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c3b3-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c3b3.test', 'fp-o1c3b3-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c3b3-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C3B3-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, jsonb_build_object('note', 'o1c3b3 handoff ' || p_tag), 'hash-o1c3b3-' || p_tag, p_owner, p_owner, p_org_unit, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot,
    credit_snapshot, acceptance_snapshot, status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C3B3-' || p_tag, v_handoff, v_quotation, v_account,
    jsonb_build_object('legalName', p_tag || ' Account'), '{}'::jsonb,
    jsonb_build_object('totalAmount', 1000000, 'currency', 'IDR'), '{}'::jsonb,
    jsonb_build_object('creditTermsDays', 30), '{}'::jsonb,
    'confirmed', p_owner, p_org_unit, 'tester'
  )
  returning id into v_job_order;

  return query select v_job_order, v_handoff, v_quotation, v_account;
end;
$$;

\echo '>> fixture: one shipment order (SHP-O1C3B3-1, owned by 998901) on a real job order chain, and 3 route planning scenarios hung off it -- SCENARIO-A (oldest, created_at=now()-3d, carries 2 constraints + 3 candidate plans inserted OUT of plan_rank order + 3 score components on the rank-1 plan + 2 selected-plan rows where the older one is superseded by the newer current one), SCENARIO-B (created_at=now()-2d, deliberately carries NO constraints/candidates/selection at all -- the "no current selection yet" fixture for get_current_route_planning_selection), and SCENARIO-C (newest, created_at=now()-1d, the replan TARGET linked back to SCENARIO-A via one route_planning_replan_events row)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b3');
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B3-CO');
  v_chain record;
  v_shipment_order_id uuid;
  v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
  v_scenario_b uuid := '00000000-0000-0000-0000-0000aaaa0002';
  v_scenario_c uuid := '00000000-0000-0000-0000-0000aaaa0003';
  v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
  v_candidate_rank2 uuid := '00000000-0000-0000-0000-0000cccc0002';
  v_candidate_rank3 uuid := '00000000-0000-0000-0000-0000cccc0003';
  v_selection_old uuid := '00000000-0000-0000-0000-0000eeee0001';
  v_selection_current uuid := '00000000-0000-0000-0000-0000eeee0002';
begin
  select * into v_chain from app._o1c3b3_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000998901', 'A');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C3B3-1', 'idem-shp-o1c3b3-1', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', '00000000-0000-0000-0000-000000998901', v_org_unit_id, 'tester'
  ) returning id into v_shipment_order_id;

  -- SCENARIO-A: oldest by created_at, carries the constraints/candidates/
  -- score-components/selection fixtures below.
  insert into app.route_planning_scenarios (id, tenant_id, shipment_order_id, idempotency_key, status, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by, created_at, updated_at)
  values (v_scenario_a, v_tenant_id, v_shipment_order_id, 'idem-scenario-a-o1c3b3', 'ready', 5000, 25, '00000000-0000-0000-0000-000000998901', 'tester', now() - interval '3 days', now() - interval '3 days');

  -- SCENARIO-B: middle by created_at, deliberately carries NO selected_plans row at
  -- all -- the "no current selection yet" fixture for
  -- get_current_route_planning_selection.
  insert into app.route_planning_scenarios (id, tenant_id, shipment_order_id, idempotency_key, status, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by, created_at, updated_at)
  values (v_scenario_b, v_tenant_id, v_shipment_order_id, 'idem-scenario-b-o1c3b3', 'draft', 3000, 15, '00000000-0000-0000-0000-000000998901', 'tester', now() - interval '2 days', now() - interval '2 days');

  -- SCENARIO-C: newest by created_at, the replan TARGET (freshly created scenario) --
  -- linked back to SCENARIO-A via the route_planning_replan_events row below.
  insert into app.route_planning_scenarios (id, tenant_id, shipment_order_id, idempotency_key, status, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by, created_at, updated_at)
  values (v_scenario_c, v_tenant_id, v_shipment_order_id, 'idem-scenario-c-o1c3b3', 'draft', 5000, 25, '00000000-0000-0000-0000-000000998901', 'tester', now() - interval '1 day', now() - interval '1 day');

  -- 2 constraints on SCENARIO-A (unordered per the migration's own design).
  insert into app.route_planning_constraints (id, tenant_id, scenario_id, constraint_type, constraint_key, constraint_value, created_by) values
    ('00000000-0000-0000-0000-0000bbbb0001', v_tenant_id, v_scenario_a, 'hard', 'max_weight_kg', jsonb_build_object('value', 5000), 'tester'),
    ('00000000-0000-0000-0000-0000bbbb0002', v_tenant_id, v_scenario_a, 'hard', 'max_distance_km', jsonb_build_object('value', 800), 'tester');

  -- 3 candidate plans on SCENARIO-A, inserted deliberately OUT of plan_rank order (2,
  -- 3, 1) so the function's own `order by plan_rank asc` is genuinely proven, not
  -- merely reproducing insertion order.
  insert into app.route_planning_candidate_plans (id, tenant_id, scenario_id, plan_rank, feasible, total_distance_km, estimated_duration_minutes, capacity_utilization_pct)
  values (v_candidate_rank2, v_tenant_id, v_scenario_a, 2, true, 150, 220, 60);
  insert into app.route_planning_candidate_plans (id, tenant_id, scenario_id, plan_rank, feasible, infeasibility_reasons)
  values (v_candidate_rank3, v_tenant_id, v_scenario_a, 3, false, jsonb_build_array('capacity_exceeded'));
  insert into app.route_planning_candidate_plans (id, tenant_id, scenario_id, plan_rank, feasible, total_distance_km, estimated_duration_minutes, capacity_utilization_pct)
  values (v_candidate_rank1, v_tenant_id, v_scenario_a, 1, true, 120, 180, 75);

  -- 3 score components on the rank-1 candidate plan (the explainability breakdown --
  -- unordered per the migration's own design).
  insert into app.route_planning_score_components (id, tenant_id, candidate_plan_id, component_key, component_value) values
    ('00000000-0000-0000-0000-0000dddd0001', v_tenant_id, v_candidate_rank1, 'total_distance_km', 120),
    ('00000000-0000-0000-0000-0000dddd0002', v_tenant_id, v_candidate_rank1, 'estimated_duration_minutes', 180),
    ('00000000-0000-0000-0000-0000dddd0003', v_tenant_id, v_candidate_rank1, 'capacity_utilization_pct', 75);

  -- 2 selected-plan rows on SCENARIO-A: the older one (rank-2 candidate, selected 2
  -- hours ago) is superseded by the newer one (rank-1 candidate, selected 1 hour ago,
  -- is_current=true) -- proves list_route_planning_selections' own `order by
  -- selected_at desc` and get_current_route_planning_selection's own is_current
  -- filter pick the right one.
  -- superseded_by_id references this same table's own id, so the CURRENT row (the
  -- target of the reference) must be inserted first, then the OLD row referencing it
  -- -- both still carry their own true selected_at (2 hours ago / 1 hour ago), the
  -- insert order here is purely to satisfy the foreign key.
  insert into app.route_planning_selected_plans (id, tenant_id, scenario_id, candidate_plan_id, is_current, selected_by, selected_at)
  values (v_selection_current, v_tenant_id, v_scenario_a, v_candidate_rank1, true, 'tester', now() - interval '1 hour');
  insert into app.route_planning_selected_plans (id, tenant_id, scenario_id, candidate_plan_id, is_current, superseded_by_id, selected_by, selected_at)
  values (v_selection_old, v_tenant_id, v_scenario_a, v_candidate_rank2, false, v_selection_current, 'tester', now() - interval '2 hours');

  -- 1 replan event: scenario_id = SCENARIO-C (the freshly created replan target),
  -- previous_scenario_id = SCENARIO-A (the scenario being replaced) -- proves the
  -- migration's own column-semantics derivation (this function filters on
  -- scenario_id, not previous_scenario_id).
  insert into app.route_planning_replan_events (id, tenant_id, scenario_id, previous_scenario_id, trigger_reason, triggered_by, triggered_at)
  values ('00000000-0000-0000-0000-0000ffff0001', v_tenant_id, v_scenario_c, v_scenario_a, 'o1c3b3 test replan: canonical position changed materially', 'tester', now() - interval '30 minutes');
end $$;

\echo '>> owner session (998901): all 8 functions return the expected rows -- list_route_planning_scenarios comes back [C, B, A] (created_at desc); get_route_planning_scenario resolves SCENARIO-A by id and returns a GENUINELY EMPTY result (count=0, no row at all) for a nonexistent id; list_route_planning_constraints returns both SCENARIO-A constraint keys; list_route_planning_candidate_plans comes back [rank1, rank2, rank3] (plan_rank asc, proving the out-of-order insert was truly re-sorted); list_route_planning_score_components returns all 3 component keys for the rank-1 candidate; get_current_route_planning_selection resolves SCENARIO-A to the rank-1 (current) selection and returns a GENUINELY EMPTY result for SCENARIO-B (no selection made yet); list_route_planning_selections returns SCENARIO-A''s 2 selections newest-first; list_route_planning_replan_events resolves SCENARIO-C to its 1 replan row and returns zero rows for SCENARIO-A (column-semantics: filters on scenario_id, not previous_scenario_id)'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998901", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_scenario_b uuid := '00000000-0000-0000-0000-0000aaaa0002';
    v_scenario_c uuid := '00000000-0000-0000-0000-0000aaaa0003';
    v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
    v_nonexistent uuid := gen_random_uuid();
    v_scenario_ids uuid[];
    v_row record;
    v_count integer;
    v_keys text[];
    v_ranks integer[];
    v_selected_ids uuid[];
  begin
    -- 1. list_route_planning_scenarios: newest-first. No ORDER BY added at the call
    -- site -- this genuinely exercises the function body's own `order by created_at
    -- desc`, not a re-sort of the result.
    select array_agg(id) into v_scenario_ids from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_scenario_ids <> array[v_scenario_c, v_scenario_b, v_scenario_a] then
      raise exception 'assertion failed: list_route_planning_scenarios must return [C, B, A] (created_at desc), got %', v_scenario_ids;
    end if;

    -- 2. get_route_planning_scenario: real row by primary key.
    select * into v_row from app.get_route_planning_scenario(v_scenario_a);
    if v_row.id is null or v_row.id <> v_scenario_a or v_row.status <> 'ready' then
      raise exception 'assertion failed: get_route_planning_scenario(SCENARIO-A) must return the real row, got %', v_row;
    end if;

    -- 2b. get_route_planning_scenario: a nonexistent id is a GENUINELY EMPTY result --
    -- zero rows, never one row of all-NULL columns (this migration's own
    -- SETOF-vs-BARE-COMPOSITE defect class).
    select count(*) into v_count from app.get_route_planning_scenario(v_nonexistent);
    if v_count <> 0 then
      raise exception 'assertion failed: get_route_planning_scenario(nonexistent) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_route_planning_scenario(v_nonexistent)) then
      raise exception 'assertion failed: get_route_planning_scenario(nonexistent) must be a genuinely empty row set, found at least one row';
    end if;

    -- 3. list_route_planning_constraints: both constraint keys present (unordered --
    -- sorted here purely for a deterministic comparison, not testing row order).
    select array_agg(constraint_key order by constraint_key) into v_keys from app.list_route_planning_constraints(v_scenario_a);
    if v_keys <> array['max_distance_km', 'max_weight_kg'] then
      raise exception 'assertion failed: list_route_planning_constraints(SCENARIO-A) must return both constraint keys, got %', v_keys;
    end if;

    -- 4. list_route_planning_candidate_plans: plan_rank ascending, no ORDER BY added
    -- at the call site -- proving the deliberately out-of-order insert (2, 3, 1) was
    -- truly re-sorted by the function body's own `order by plan_rank asc`.
    select array_agg(plan_rank) into v_ranks from app.list_route_planning_candidate_plans(v_scenario_a);
    if v_ranks <> array[1, 2, 3] then
      raise exception 'assertion failed: list_route_planning_candidate_plans(SCENARIO-A) must return plan_rank ascending [1,2,3], got %', v_ranks;
    end if;

    -- 5. list_route_planning_score_components: all 3 component keys for the rank-1
    -- candidate (unordered -- sorted here purely for a deterministic comparison).
    select array_agg(component_key order by component_key) into v_keys from app.list_route_planning_score_components(v_candidate_rank1);
    if v_keys <> array['capacity_utilization_pct', 'estimated_duration_minutes', 'total_distance_km'] then
      raise exception 'assertion failed: list_route_planning_score_components(rank-1 candidate) must return all 3 component keys, got %', v_keys;
    end if;

    -- 6. get_current_route_planning_selection: SCENARIO-A resolves to the rank-1
    -- (current) selection, never the superseded rank-2 one.
    select * into v_row from app.get_current_route_planning_selection(v_scenario_a);
    if v_row.id is null or v_row.candidate_plan_id <> v_candidate_rank1 or v_row.is_current is not true then
      raise exception 'assertion failed: get_current_route_planning_selection(SCENARIO-A) must resolve to the rank-1 current selection, got %', v_row;
    end if;

    -- 6b. get_current_route_planning_selection: SCENARIO-B has no selection made yet
    -- -- a GENUINELY EMPTY result, never one row of all-NULL columns.
    select count(*) into v_count from app.get_current_route_planning_selection(v_scenario_b);
    if v_count <> 0 then
      raise exception 'assertion failed: get_current_route_planning_selection(SCENARIO-B, no selection yet) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_current_route_planning_selection(v_scenario_b)) then
      raise exception 'assertion failed: get_current_route_planning_selection(SCENARIO-B) must be a genuinely empty row set, found at least one row';
    end if;

    -- 7. list_route_planning_selections: both of SCENARIO-A's selections, newest
    -- first. No ORDER BY added at the call site -- genuinely exercises the function
    -- body's own `order by selected_at desc`.
    select array_agg(id) into v_selected_ids from app.list_route_planning_selections(v_scenario_a);
    if v_selected_ids <> array['00000000-0000-0000-0000-0000eeee0002'::uuid, '00000000-0000-0000-0000-0000eeee0001'::uuid] then
      raise exception 'assertion failed: list_route_planning_selections(SCENARIO-A) must return [current, superseded] (selected_at desc), got %', v_selected_ids;
    end if;
    select count(*) into v_count from app.list_route_planning_selections(v_scenario_b);
    if v_count <> 0 then
      raise exception 'assertion failed: list_route_planning_selections(SCENARIO-B) must return zero rows, got %', v_count;
    end if;

    -- 8. list_route_planning_replan_events: SCENARIO-C (the freshly created replan
    -- target) resolves to the 1 fixture row; SCENARIO-A (the OLD scenario, linked via
    -- previous_scenario_id, not scenario_id) resolves to zero -- the migration's own
    -- column-semantics derivation, confirmed directly.
    select count(*) into v_count from app.list_route_planning_replan_events(v_scenario_c);
    if v_count <> 1 then
      raise exception 'assertion failed: list_route_planning_replan_events(SCENARIO-C) must return exactly 1 row, got %', v_count;
    end if;
    select count(*) into v_count from app.list_route_planning_replan_events(v_scenario_a);
    if v_count <> 0 then
      raise exception 'assertion failed: list_route_planning_replan_events(SCENARIO-A) must return zero rows (filters on scenario_id, not previous_scenario_id), got %', v_count;
    end if;

    raise notice 'owner proof: all 8 functions return the expected rows/order; both 0-or-1-row getters return a genuinely empty result (not a row of nulls) on their respective miss case';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> shared-org-unit viewer session (998902, same org unit as the owner, not the owner): also sees all 3 scenarios, the real current selection, and the correctly ordered candidate plans -- proves the RLS predicate''s shared-org-unit branch, not merely exact-owner-match'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998902", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
    v_count integer;
    v_row record;
    v_ranks integer[];
  begin
    select count(*) into v_count from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 3 then
      raise exception 'assertion failed: shared-org-unit viewer must see all 3 scenarios, got %', v_count;
    end if;

    select * into v_row from app.get_current_route_planning_selection(v_scenario_a);
    if v_row.id is null or v_row.candidate_plan_id <> v_candidate_rank1 then
      raise exception 'assertion failed: shared-org-unit viewer must see the real current selection on SCENARIO-A, got %', v_row;
    end if;

    select array_agg(plan_rank) into v_ranks from app.list_route_planning_candidate_plans(v_scenario_a);
    if v_ranks <> array[1, 2, 3] then
      raise exception 'assertion failed: shared-org-unit viewer must see candidate plans plan_rank ascending, got %', v_ranks;
    end if;

    raise notice 'shared-org-unit viewer proof: real scenarios/current selection/ordered candidate plans returned via the RLS shared-org-unit branch';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> denied member session (998903, real acmeo1c3b3 tenant member, no owner/org-unit/customer-account relationship to SHP-O1C3B3-1): zero rows from all 8 functions, never an exception'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998903", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_scenario_c uuid := '00000000-0000-0000-0000-0000aaaa0003';
    v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
    v_count integer;
  begin
    select count(*) into v_count from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_scenarios, got %', v_count; end if;

    select count(*) into v_count from app.get_route_planning_scenario(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from get_route_planning_scenario, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_constraints(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_constraints, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_candidate_plans(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_candidate_plans, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_score_components(v_candidate_rank1);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_score_components, got %', v_count; end if;

    select count(*) into v_count from app.get_current_route_planning_selection(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from get_current_route_planning_selection, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_selections(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_selections, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_replan_events(v_scenario_c);
    if v_count <> 0 then raise exception 'assertion failed: denied member must see zero rows from list_route_planning_replan_events, got %', v_count; end if;

    raise notice 'denied member proof: zero rows from all 8 functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> cross-tenant session (998905, gizmoo1c3b3''s own tenant_admin, no standing in acmeo1c3b3 at all): zero rows from all 8 functions'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998905", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_scenario_c uuid := '00000000-0000-0000-0000-0000aaaa0003';
    v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
    v_count integer;
  begin
    select count(*) into v_count from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_scenarios, got %', v_count; end if;

    select count(*) into v_count from app.get_route_planning_scenario(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_route_planning_scenario, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_constraints(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_constraints, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_candidate_plans(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_candidate_plans, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_score_components(v_candidate_rank1);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_score_components, got %', v_count; end if;

    select count(*) into v_count from app.get_current_route_planning_selection(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_current_route_planning_selection, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_selections(v_scenario_a);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_selections, got %', v_count; end if;

    select count(*) into v_count from app.list_route_planning_replan_events(v_scenario_c);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_route_planning_replan_events, got %', v_count; end if;

    raise notice 'cross-tenant proof: zero rows from all 8 functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (998904, ZERO tenant membership anywhere): still sees the real rows via app.can_access_record''s own is_supreme_admin branch, evaluated by the RLS policy under the real session identity -- spot-checked across a representative subset of the 8 functions'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998904", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_scenario_c uuid := '00000000-0000-0000-0000-0000aaaa0003';
    v_candidate_rank1 uuid := '00000000-0000-0000-0000-0000cccc0001';
    v_count integer;
    v_row record;
  begin
    select count(*) into v_count from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 3 then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see all 3 scenarios, got %', v_count;
    end if;

    select * into v_row from app.get_route_planning_scenario(v_scenario_a);
    if v_row.id is null then
      raise exception 'assertion failed: Supreme Admin with zero membership must still reach SCENARIO-A via get_route_planning_scenario';
    end if;

    select count(*) into v_count from app.list_route_planning_score_components(v_candidate_rank1);
    if v_count <> 3 then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see all 3 score components, got %', v_count;
    end if;

    select * into v_row from app.get_current_route_planning_selection(v_scenario_a);
    if v_row.id is null then
      raise exception 'assertion failed: Supreme Admin with zero membership must still reach the current selection via get_current_route_planning_selection';
    end if;

    select count(*) into v_count from app.list_route_planning_replan_events(v_scenario_c);
    if v_count <> 1 then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the 1 replan event, got %', v_count;
    end if;

    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via app.can_access_record''s own is_supreme_admin branch and sees the real rows';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> anon defense in depth: all 8 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_route_planning_scenarios(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_scenarios';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_scenarios correctly rejected anon';
    end;

    begin
      perform public.get_route_planning_scenario(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_route_planning_scenario';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_route_planning_scenario correctly rejected anon';
    end;

    begin
      perform public.list_route_planning_constraints(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_constraints';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_constraints correctly rejected anon';
    end;

    begin
      perform public.list_route_planning_candidate_plans(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_candidate_plans';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_candidate_plans correctly rejected anon';
    end;

    begin
      perform public.list_route_planning_score_components(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_score_components';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_score_components correctly rejected anon';
    end;

    begin
      perform public.get_current_route_planning_selection(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_current_route_planning_selection';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_current_route_planning_selection correctly rejected anon';
    end;

    begin
      perform public.list_route_planning_selections(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_selections';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_selections correctly rejected anon';
    end;

    begin
      perform public.list_route_planning_replan_events(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_route_planning_replan_events';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_route_planning_replan_events correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: BYPASSRLS reads via 3 of the 8 functions (both app.* and public.*) succeed and see the real fixture rows -- a quick confirmation only, not exhaustive, since this migration''s own header already argues service_role''s pre-existing direct table grants already cover this and a SECURITY INVOKER function grants no new capability'
begin;
  set local role service_role;
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B3-1');
    v_scenario_a uuid := '00000000-0000-0000-0000-0000aaaa0001';
    v_count integer;
  begin
    select count(*) into v_count from app.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 3 then
      raise exception 'assertion failed: service_role must see all 3 scenarios via app.list_route_planning_scenarios, got %', v_count;
    end if;

    select count(*) into v_count from public.list_route_planning_scenarios(v_shipment_order_id);
    if v_count <> 3 then
      raise exception 'assertion failed: service_role must see all 3 scenarios via public.list_route_planning_scenarios, got %', v_count;
    end if;

    select count(*) into v_count from app.get_current_route_planning_selection(v_scenario_a);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see the real current selection via app.get_current_route_planning_selection, got %', v_count;
    end if;

    select count(*) into v_count from public.get_current_route_planning_selection(v_scenario_a);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see the real current selection via public.get_current_route_planning_selection, got %', v_count;
    end if;

    raise notice 'service_role proof: BYPASSRLS reads succeed via both app.* and public.* on the spot-checked functions, matching the migration''s own no-new-capability argument';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 8 new cluster-3-batch-3 function pairs (16 functions) in EITHER schema (app or public); authenticated/service_role (spot-checked on 3 of the 8 pairs) hold EXECUTE on both the app.* function and its public.* wrapper, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_route_planning_scenarios',
      'get_route_planning_scenario',
      'list_route_planning_constraints',
      'list_route_planning_candidate_plans',
      'list_route_planning_score_components',
      'get_current_route_planning_selection',
      'list_route_planning_selections',
      'list_route_planning_replan_events'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 8 cluster-3-batch-3 function pairs (16 functions, either schema), found % grants', v_count;
  end if;

  -- Spot-check 3 of the 8: authenticated AND service_role both hold EXECUTE on the
  -- app.* function AND its public.* wrapper (grant parity, ISS-2026-309).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in ('list_route_planning_scenarios', 'get_current_route_planning_selection', 'list_route_planning_replan_events')
    and grantee in ('authenticated', 'service_role');
  if v_count <> 3 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 12 grants (3 functions x 2 schemas x 2 grantees) for the spot-checked functions, found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 16 new cluster-3-batch-3 functions; authenticated/service_role hold the declared grant on both the app.* and public.* spot-checked functions';
end $$;

drop function app._o1c3b3_test_make_job_order_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster3-batch3.sql test suite passed -- cluster 3 batch 3 (route/load planning scenarios, constraints, candidate plans, score components, selections, and replan events, 8/8 call sites) is now fully DONE'
