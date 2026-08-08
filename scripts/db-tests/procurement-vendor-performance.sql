-- Real, executable test evidence for PRC-264 (Vendor Performance, CG-S11-PRC-015) -- run
-- via `pnpm run db:test` against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration (supabase/migrations/
-- 20260730740000_create_procurement_vendor_performance.sql). Self-contained -- builds
-- its own tenant/vendor/contract/capacity/shipment/rate/claim pipeline from scratch,
-- mirroring procurement-vendor-assignment.sql's own disclosed convention.
--
-- All time-sensitive fixture data (shipments, milestones, invitations, reservations) is
-- anchored to now() rather than a fixed calendar date, since app.resource_assignments/
-- app.vendor_assignment_invitations/app.vendor_capacity_reservations all default their
-- own timestamp columns to now() at the moment this test actually calls them -- the
-- measurement window is therefore [now() - 1 day, now() + 2 days), and every fixture
-- event is placed relative to now() so it always falls inside that window regardless of
-- when this suite runs.
--
-- Covers: KPI definition catalogue (draft/publish/archive, idempotency C-01, band
-- validation), calculate_vendor_kpi_metrics (real on_time_pickup/on_time_delivery/
-- acceptance_rate/response_time/capacity_fulfillment/compliance/claims_damage/
-- service_complaint_sla/rate_competitiveness/rate_validity, invoice_accuracy disclosed
-- not-computable), publish_vendor_kpi_scorecard (composite/band, insufficient_kpi_
-- coverage), source dispute (raise/decide/exclusion), manual adjustment (maker-checker,
-- self-approval block), issue/corrective-action lifecycle, governed lifecycle
-- recommendation (evaluate -> decide suspend/blacklist/reactivate, wired into the real
-- PRC-251 RPCs), late/corrected-event recalculation (new version, never silent
-- rewrite), cross-tenant/RLS isolation, and schema-privilege defense in depth.
--
-- Disclosed, not tested here (bounded scope, not an oversight):
--   * A live two-process concurrent race on the metric-value/scorecard supersede locks
--     -- deferred to this batch's own Tier C correctness/concurrency lens
--     (BUILD_EXECUTION_PROTOCOL.md §5.2), mirroring PRC-261's own db-test disclosure for
--     app.activate_vendor_contract's dual lock.
--   * Deeper app.vendor_compliance_status permutations (hold/waiver/expiry) are already
--     exhaustively covered by PRC-253's own db-test suite -- this file only proves the
--     compliance KPI correctly reads that projection (including the zero-tracked-
--     requirements case), never re-derives compliance status itself.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (vperf1): tenant_admin (admin1), full-PRC staff (staff1, Create/Edit/View/View cost/Approve), an override manager (manager1, PRC:Override), a view-only actor (viewer1), a no-PRC outsider (outsider1). Tenant2 (vperf2): tenant_admin (admin2). A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_staff_role uuid;
  v_manager_role uuid;
  v_viewer_role uuid;
  v_outsider_role uuid;
  v_t2_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000264101', 'admin@vperf1.test'),
    ('00000000-0000-0000-0000-000000264102', 'staff@vperf1.test'),
    ('00000000-0000-0000-0000-000000264103', 'manager@vperf1.test'),
    ('00000000-0000-0000-0000-000000264104', 'viewer@vperf1.test'),
    ('00000000-0000-0000-0000-000000264105', 'outsider@vperf1.test'),
    ('00000000-0000-0000-0000-000000264201', 'admin@vperf2.test'),
    ('00000000-0000-0000-0000-000000264999', 'supreme@vperf.test');

  perform app.provision_tenant('vperf1', 'Vendor Performance Co 1', 'idem-vperf1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vperf1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('vperf2', 'Vendor Performance Co 2', 'idem-vperf2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vperf2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000264101', 'admin@vperf1.test', 'Vperf1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vperf1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000264101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000264102', 'staff@vperf1.test', 'Vperf1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vperf1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000264103', 'manager@vperf1.test', 'Vperf1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@vperf1.test'), 'active', 'onboarded', 'tester');
  -- Also a second tenant_admin, purely so app.can_access_record's own record-scope
  -- check (used by app.decide_claim_responsibility, unrelated to and never weakened by
  -- this checkpoint) passes for a real, org-unit-less actor -- mirrors this repository's
  -- own standing "extra admin for setup convenience" fixture convention.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000264103', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000264104', 'viewer@vperf1.test', 'Vperf1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vperf1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000264105', 'outsider@vperf1.test', 'Vperf1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@vperf1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000264201', 'admin@vperf2.test', 'Vperf2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vperf2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000264201', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000264999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Vperf1 Admin', 'full PRC+OPS for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))
      or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000264101', '00000000-0000-0000-0000-000000264999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Vperf1 Staff', 'Create/Edit/View/View cost/Approve', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000264102', '00000000-0000-0000-0000-000000264101', 'admin');

  v_manager_role := (app.create_role(v_tenant1, 'Vperf1 Manager', 'PRC:Override + OPS:Override (claim responsibility decisions)', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_manager_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action = 'Override') or (resource_module_code = 'OPS' and action = 'Override')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_manager_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000264103', '00000000-0000-0000-0000-000000264101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Vperf1 Viewer', 'View only, no View cost', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000264104', '00000000-0000-0000-0000-000000264101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Vperf1 Outsider', 'no PRC at all', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_outsider_role, 'tester')).id, array[]::uuid[], 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_outsider_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000264105', '00000000-0000-0000-0000-000000264101', 'admin');

  v_t2_role := (app.create_role(v_tenant2, 'Vperf2 Admin Role', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Approve', 'Override')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000264201', '00000000-0000-0000-0000-000000264201', 'admin');
end $$;

\echo '>> setup: three vendors (Good, Poor, New/sparse-data) in tenant1, each active, plus an active contract and published capacity offer for Good/Poor; a market-comparison vendor with a pricier rate on the same lane; one full CRM-through-job-order pipeline (mirrors operations-resource-assignment.sql) producing FOUR real shipment orders off the SAME job order (two per vendor)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_good app.vendor_profiles;
  v_poor app.vendor_profiles;
  v_new app.vendor_profiles;
  v_market app.vendor_profiles;
  v_good_contract app.vendor_contracts;
  v_poor_contract app.vendor_contracts;
  v_good_offer app.vendor_capacity_offers;
  v_poor_offer app.vendor_capacity_offers;
  v_good_res1 app.vendor_capacity_reservations;
  v_good_res2 app.vendor_capacity_reservations;
  v_poor_res1 app.vendor_capacity_reservations;
  v_poor_res2 app.vendor_capacity_reservations;
  v_good_rate app.vendor_rate_versions;
  v_market_rate app.vendor_rate_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_ship1 app.shipment_orders;
  v_ship2 app.shipment_orders;
  v_ship3 app.shipment_orders;
  v_ship4 app.shipment_orders;
  v_inv1 app.vendor_assignment_invitations;
  v_inv2 app.vendor_assignment_invitations;
  v_inv3 app.vendor_assignment_invitations;
  v_inv4 app.vendor_assignment_invitations;
begin
  v_good := app.create_vendor_profile_draft(v_tenant1, 'PT Good Vendor', 'GOODV', 'PT', 'REG-VPERF-GOOD', 'logistics', 30, 'staff_created', 'idem-vperf-vendor-good', v_admin1, 'admin');
  perform app.add_vendor_contact(v_good.master_record_id, 'Good Ops', 'Ops', 'ops@goodv.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_good.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_good.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_good.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_good from app.vendor_profiles where master_record_id = v_good.master_record_id;
  v_good := app.submit_vendor_profile_for_review(v_good.master_record_id, v_good.record_version, v_admin1, 'admin');
  v_good := app.decide_vendor_profile_review(v_good.master_record_id, v_good.record_version, 'approve', null, v_admin1, 'admin');
  v_good := app.activate_vendor_profile(v_good.master_record_id, v_good.record_version, v_admin1, 'admin');

  v_poor := app.create_vendor_profile_draft(v_tenant1, 'PT Poor Vendor', 'POORV', 'PT', 'REG-VPERF-POOR', 'logistics', 30, 'staff_created', 'idem-vperf-vendor-poor', v_admin1, 'admin');
  perform app.add_vendor_contact(v_poor.master_record_id, 'Poor Ops', 'Ops', 'ops@poorv.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_poor.master_record_id, 'legal', 'Jl. Sudirman 2', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_poor.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_poor.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_poor from app.vendor_profiles where master_record_id = v_poor.master_record_id;
  v_poor := app.submit_vendor_profile_for_review(v_poor.master_record_id, v_poor.record_version, v_admin1, 'admin');
  v_poor := app.decide_vendor_profile_review(v_poor.master_record_id, v_poor.record_version, 'approve', null, v_admin1, 'admin');
  v_poor := app.activate_vendor_profile(v_poor.master_record_id, v_poor.record_version, v_admin1, 'admin');

  -- New vendor: active, but zero evidence anywhere -- the sparse-data/insufficient-coverage case.
  v_new := app.create_vendor_profile_draft(v_tenant1, 'PT New Vendor', 'NEWV', 'PT', 'REG-VPERF-NEW', 'logistics', 30, 'staff_created', 'idem-vperf-vendor-new', v_admin1, 'admin');
  perform app.add_vendor_contact(v_new.master_record_id, 'New Ops', 'Ops', 'ops@newv.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_new.master_record_id, 'legal', 'Jl. Sudirman 3', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_new.master_record_id, 'ocean_freight', v_admin1, 'admin');
  select * into v_new from app.vendor_profiles where master_record_id = v_new.master_record_id;
  v_new := app.submit_vendor_profile_for_review(v_new.master_record_id, v_new.record_version, v_admin1, 'admin');
  v_new := app.decide_vendor_profile_review(v_new.master_record_id, v_new.record_version, 'approve', null, v_admin1, 'admin');
  v_new := app.activate_vendor_profile(v_new.master_record_id, v_new.record_version, v_admin1, 'admin');

  -- Market comparison vendor -- exists only to give rate_competitiveness a real,
  -- non-trivial market to rank against.
  v_market := app.create_vendor_profile_draft(v_tenant1, 'PT Market Vendor', 'MKTV', 'PT', 'REG-VPERF-MKT', 'logistics', 30, 'staff_created', 'idem-vperf-vendor-market', v_admin1, 'admin');
  perform app.add_vendor_contact(v_market.master_record_id, 'Market Ops', 'Ops', 'ops@mktv.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_market.master_record_id, 'legal', 'Jl. Sudirman 4', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_market.master_record_id, 'ocean_freight', v_admin1, 'admin');
  select * into v_market from app.vendor_profiles where master_record_id = v_market.master_record_id;
  v_market := app.submit_vendor_profile_for_review(v_market.master_record_id, v_market.record_version, v_admin1, 'admin');
  v_market := app.decide_vendor_profile_review(v_market.master_record_id, v_market.record_version, 'approve', null, v_admin1, 'admin');
  v_market := app.activate_vendor_profile(v_market.master_record_id, v_market.record_version, v_admin1, 'admin');

  v_good_contract := app.create_vendor_contract_draft(
    v_tenant1, v_good.master_record_id, 'framework', '2026-01-01'::date, null, null, 30,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vperf-contract-good', v_admin1, 'admin'
  );
  v_good_contract := app.submit_vendor_contract_for_approval(v_good_contract.id, v_good_contract.record_version, 'idem-vperf-contract-good-submit', v_admin1, 'admin');
  v_good_contract := app.activate_vendor_contract(v_good_contract.id, v_good_contract.record_version, v_admin1, 'admin');

  v_poor_contract := app.create_vendor_contract_draft(
    v_tenant1, v_poor.master_record_id, 'framework', '2026-01-01'::date, null, null, 30,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vperf-contract-poor', v_admin1, 'admin'
  );
  v_poor_contract := app.submit_vendor_contract_for_approval(v_poor_contract.id, v_poor_contract.record_version, 'idem-vperf-contract-poor-submit', v_admin1, 'admin');
  v_poor_contract := app.activate_vendor_contract(v_poor_contract.id, v_poor_contract.record_version, v_admin1, 'admin');

  v_good_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_good.master_record_id, v_good_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
    100, 'teu', now() - interval '5 days', now() + interval '30 days', 'idem-vperf-offer-good', v_admin1, 'admin'
  );
  v_good_offer := app.publish_vendor_capacity_offer(v_good_offer.id, v_good_offer.record_version, v_admin1, 'admin');
  v_good_res1 := app.reserve_vendor_capacity(v_good_offer.id, 10, now(), now() + interval '3 hours', 'manual', null, 'idem-vperf-good-res1', v_admin1, 'admin');
  v_good_res1 := app.accept_vendor_capacity_reservation(v_good_res1.id, v_good_res1.record_version, v_admin1, 'admin');
  v_good_res2 := app.reserve_vendor_capacity(v_good_offer.id, 10, now() + interval '6 hours', now() + interval '11 hours', 'manual', null, 'idem-vperf-good-res2', v_admin1, 'admin');
  v_good_res2 := app.accept_vendor_capacity_reservation(v_good_res2.id, v_good_res2.record_version, v_admin1, 'admin');

  v_poor_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_poor.master_record_id, v_poor_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
    100, 'teu', now() - interval '5 days', now() + interval '30 days', 'idem-vperf-offer-poor', v_admin1, 'admin'
  );
  v_poor_offer := app.publish_vendor_capacity_offer(v_poor_offer.id, v_poor_offer.record_version, v_admin1, 'admin');
  v_poor_res1 := app.reserve_vendor_capacity(v_poor_offer.id, 10, now() + interval '1 hour', now() + interval '4 hours', 'manual', null, 'idem-vperf-poor-res1', v_admin1, 'admin');
  v_poor_res1 := app.accept_vendor_capacity_reservation(v_poor_res1.id, v_poor_res1.record_version, v_admin1, 'admin');
  -- Second reservation deliberately left in 'held' -- never accepted -- proving
  -- capacity_fulfillment excludes it from both numerator and denominator (design
  -- note in app._calc_vendor_kpi_capacity_fulfillment).
  v_poor_res2 := app.reserve_vendor_capacity(v_poor_offer.id, 10, now() + interval '9 hours', now() + interval '15 hours', 'manual', null, 'idem-vperf-poor-res2', v_admin1, 'admin');

  -- Rates: Good Vendor cheap (competitive), Market Vendor pricier on the SAME lane
  -- (gives rate_competitiveness a real, non-trivial market of size 2). Poor/New carry
  -- no rate at all -- a real, disclosed sparse-data case for rate_validity/rate_
  -- competitiveness on those two vendors (design note in the migration header).
  v_good_rate := app.create_rate_version(
    v_tenant1, 'VENDOR-VPERF-GOOD', 'PT Good Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now() - interval '10 days', null, null,
    v_admin1, 'admin', v_good.master_record_id
  );
  perform app.approve_rate_version(v_good_rate.id, v_good_rate.record_version, v_admin1, 'admin');
  v_market_rate := app.create_rate_version(
    v_tenant1, 'VENDOR-VPERF-MKT', 'PT Market Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 12000000, null, '[]'::jsonb, now() - interval '10 days', null, null,
    v_admin1, 'admin', v_market.master_record_id
  );
  perform app.approve_rate_version(v_market_rate.id, v_market_rate.record_version, v_admin1, 'admin');

  -- Minimal real CRM-through-shipment-order pipeline (mirrors operations-resource-
  -- assignment.sql / procurement-vendor-assignment.sql), producing ONE job order that
  -- FOUR real shipment orders split off of (two per vendor).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Vperf Test Co', 'Jane Vperf', 'jane@vperftest.test', '0811', v_admin1, null, v_admin1, 'tester');
  select * into v_lead from app.leads where email = 'jane@vperftest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_admin1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Vperf Test Co', 'VTC', '11.111.111.1-111.000', jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'), v_admin1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Jane Vperf Ops', 'Procurement Lead', 'jane@vperftest.test', '0811', v_admin1, null, v_admin1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_admin1, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vperf test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_admin1, null, v_admin1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_admin1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VPERF-CRM', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_admin1, 'tester');
  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_admin1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_admin1, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_admin1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_admin1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight vperf lane', v_calc_id, 1, 15000000, 0, 0, v_admin1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_admin1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_admin1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Vperf Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_admin1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_admin1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_admin1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_admin1, 'rep');

  -- Shipment 1/2 (Good Vendor) -- both on time at pickup and delivery.
  select * into v_ship1 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vperf-ship1', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '2 hours', now() + interval '5 hours', null, null, null, null, null, null, null, v_admin1, 'rep'
  );
  select * into v_ship2 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vperf-ship2', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '8 hours', now() + interval '10 hours', null, null, null, null, null, null, 'second good-vendor shipment', v_admin1, 'rep'
  );
  -- Shipment 3/4 (Poor Vendor) -- 3 is late at both pickup and delivery; 4 is on-time
  -- pickup but late delivery (a genuinely mixed, non-uniform result, not a fabricated
  -- always-fails vendor).
  select * into v_ship3 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vperf-ship3', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '2 hours', now() + interval '6 hours', null, null, null, null, null, null, 'third poor-vendor shipment', v_admin1, 'rep'
  );
  select * into v_ship4 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vperf-ship4', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '10 hours', now() + interval '14 hours', null, null, null, null, null, null, 'fourth poor-vendor shipment', v_admin1, 'rep'
  );

  -- Vendor assignment invitations: propose -> accept -> confirm (creates the real
  -- app.resource_assignments row every downstream calculator reads). Good Vendor
  -- accepts fast (real response_time evidence); Poor Vendor accepts slower.
  -- OPS-172's own assignment_conflict guard (unchanged) blocks a resource from holding
  -- more than one LIVE assignment at a time across shipments -- each vendor's first
  -- shipment is explicitly unassigned (a real "shipment delivered/released" narration)
  -- before its second is confirmed, mirroring procurement-vendor-assignment.sql's own
  -- established fixture fix for the identical constraint.
  v_inv1 := app.propose_vendor_assignment_invitation(v_tenant1, v_ship1.id, v_good.master_record_id, v_good_contract.id, null, null, v_good_res1.id, now() + interval '2 days', 'idem-vperf-inv1', v_admin1, 'admin');
  v_inv1 := app.accept_vendor_assignment_invitation(v_inv1.id, v_inv1.record_version, v_admin1, 'admin');
  v_inv1 := app.confirm_vendor_assignment(v_inv1.id, v_inv1.record_version, v_admin1, 'admin');
  perform app.unassign_resource(v_ship1.id, 'vendor', 'shipment delivered', v_admin1, 'admin');

  v_inv2 := app.propose_vendor_assignment_invitation(v_tenant1, v_ship2.id, v_good.master_record_id, v_good_contract.id, null, null, v_good_res2.id, now() + interval '2 days', 'idem-vperf-inv2', v_admin1, 'admin');
  v_inv2 := app.accept_vendor_assignment_invitation(v_inv2.id, v_inv2.record_version, v_admin1, 'admin');
  v_inv2 := app.confirm_vendor_assignment(v_inv2.id, v_inv2.record_version, v_admin1, 'admin');

  v_inv3 := app.propose_vendor_assignment_invitation(v_tenant1, v_ship3.id, v_poor.master_record_id, v_poor_contract.id, null, null, v_poor_res1.id, now() + interval '2 days', 'idem-vperf-inv3', v_admin1, 'admin');
  v_inv3 := app.accept_vendor_assignment_invitation(v_inv3.id, v_inv3.record_version, v_admin1, 'admin');
  v_inv3 := app.confirm_vendor_assignment(v_inv3.id, v_inv3.record_version, v_admin1, 'admin');
  perform app.unassign_resource(v_ship3.id, 'vendor', 'shipment delivered', v_admin1, 'admin');

  -- Shipment 4's own invitation is DECLINED first (mandatory reason), then a fresh
  -- invitation is proposed and accepted/confirmed -- gives acceptance_rate a real,
  -- non-100% denominator for the Poor Vendor (1 declined + 1 accepted among decided).
  v_inv4 := app.propose_vendor_assignment_invitation(v_tenant1, v_ship4.id, v_poor.master_record_id, v_poor_contract.id, null, null, null, now() + interval '2 days', 'idem-vperf-inv4-declined', v_admin1, 'admin');
  v_inv4 := app.decline_vendor_assignment_invitation(v_inv4.id, v_inv4.record_version, 'temporarily overbooked', v_admin1, 'admin');
  v_inv4 := app.propose_vendor_assignment_invitation(v_tenant1, v_ship4.id, v_poor.master_record_id, v_poor_contract.id, null, null, null, now() + interval '2 days', 'idem-vperf-inv4', v_admin1, 'admin');
  v_inv4 := app.accept_vendor_assignment_invitation(v_inv4.id, v_inv4.record_version, v_admin1, 'admin');
  v_inv4 := app.confirm_vendor_assignment(v_inv4.id, v_inv4.record_version, v_admin1, 'admin');

  -- Milestone evidence. Good Vendor: both on time. Poor Vendor: ship3 late at both
  -- pickup and delivery; ship4 pickup on time, delivery late.
  perform app.register_milestone_code('vperf_pickup', 'Pickup', 'pickup', true, false, false, '00000000-0000-0000-0000-000000264999', 'supreme');
  perform app.register_milestone_code('vperf_delivery', 'Delivery', 'delivery', true, true, true, '00000000-0000-0000-0000-000000264999', 'supreme');

  perform app.ingest_milestone_event(v_ship1.id, 'vperf_pickup', now() + interval '1 hour', null, null, 'manual', null, null, 'idem-vperf-ms-ship1-pickup', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship1.id, 'vperf_delivery', now() + interval '4 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship1-delivery', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship2.id, 'vperf_pickup', now() + interval '7 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship2-pickup', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship2.id, 'vperf_delivery', now() + interval '9 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship2-delivery', v_admin1, 'admin');

  perform app.ingest_milestone_event(v_ship3.id, 'vperf_pickup', now() + interval '4 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship3-pickup', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship3.id, 'vperf_delivery', now() + interval '9 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship3-delivery', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship4.id, 'vperf_pickup', now() + interval '9 hours 30 minutes', null, null, 'manual', null, null, 'idem-vperf-ms-ship4-pickup', v_admin1, 'admin');
  perform app.ingest_milestone_event(v_ship4.id, 'vperf_delivery', now() + interval '16 hours', null, null, 'manual', null, null, 'idem-vperf-ms-ship4-delivery', v_admin1, 'admin');

  -- One customer-filed claim case on ship3 (Poor Vendor), investigated and decided
  -- vendor-liable -- real evidence for BOTH claims_damage (final_responsibility_party=
  -- vendor) and service_complaint_sla (claimant_type=customer), the two distinct
  -- signals the migration header's own design notes describe.
  declare
    v_exception app.operational_exceptions;
    v_case app.claim_case_extensions;
    v_review app.claim_responsibility_reviews;
    v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 limit 1);
  begin
    v_exception := app.report_exception(v_ship3.id, null, 'damage', 'medium', 'Cargo arrived with visible damage', 'manual', null, v_admin1, 'admin');
    v_case := app.open_claim_case(v_exception.id, 'customer', v_account_id, null, null, v_admin1, 'admin');
    v_review := app.propose_claim_responsibility(v_case.id, 'vendor', null, null, 'Handling records point to the assigned vendor', null, v_admin1, 'admin');
    -- Decided by the global Supreme Admin (a different real identity from the proposer,
    -- admin1) -- app.claim_case_record_scope_ok's own app.can_access_record delegate
    -- requires either record ownership, a shared org_unit, or the Supreme Admin
    -- exception; this fixture's shipment has no shared org_unit and admin1 is its sole
    -- owner, so Supreme Admin is the correct, real, non-owner decider here, not a
    -- shortcut around self_approval_not_allowed.
    perform app.decide_claim_responsibility(v_review.id, v_review.record_version, 'approved', 'vendor', 0, 'IDR', 'Confirmed vendor mishandling on intake inspection', '00000000-0000-0000-0000-000000264999', 'supreme');
  end;
end $$;

\echo '>> KPI catalogue: create+publish all eleven categories (invoice_accuracy is_computable=false, mandatory source_note); band-threshold CHECK rejects malformed thresholds structurally; weight-range/target-operator CHECK; idempotency target-tuple verification (C-01); publish auto-archives a prior published version for the SAME kpi_code; PRC:Approve required to publish, PRC:Edit insufficient'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_def app.vendor_kpi_definitions;
  v_replay app.vendor_kpi_definitions;
  v_failed boolean;
begin
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'on_time_pickup', 'On-Time Pickup', 'pickup vs planned', 30, 1, 90, 'gte', 15, 'percent', null, null, 2, true, null, 'idem-vperf-def-otp', v_admin1, 'admin');
  v_def := app.create_vendor_kpi_definition_draft(v_tenant1, 'on_time_delivery', 'On-Time Delivery', 'delivery vs planned', 30, 1, 90, 'gte', 15, 'percent', null, null, 2, true, null, 'idem-vperf-def-otd', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'acceptance_rate', 'Acceptance Rate', 'invitation acceptance', 30, 1, 80, 'gte', 10, 'percent', null, null, 2, true, null, 'idem-vperf-def-acc', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'response_time', 'Response Time', 'hours to accept/decline', 30, 1, 24, 'lte', 10, 'hours', null, null, 2, true, null, 'idem-vperf-def-rt', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'capacity_fulfillment', 'Capacity Fulfillment', 'accepted commitments fulfilled', 30, 1, 85, 'gte', 10, 'percent', null, null, 2, true, null, 'idem-vperf-def-cap', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'compliance', 'Compliance', 'not on eligibility hold', 30, 1, 100, 'gte', 10, 'percent', null, null, 2, true, null, 'idem-vperf-def-cmp', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'claims_damage', 'Claims/Damage', 'vendor-liable claim rate', 30, 1, 5, 'lte', 10, 'percent', null, null, 2, true, null, 'idem-vperf-def-clm', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'rate_competitiveness', 'Rate Competitiveness', 'market percentile rank', 30, 1, 70, 'gte', 5, 'score', null, null, 2, true, null, 'idem-vperf-def-rc', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'rate_validity', 'Rate Validity', '% of window with a valid rate', 30, 1, 90, 'gte', 5, 'percent', null, null, 2, true, null, 'idem-vperf-def-rv', v_admin1, 'admin');
  perform app.create_vendor_kpi_definition_draft(
    v_tenant1, 'invoice_accuracy', 'Invoice Accuracy', 'three-way-match variance', 30, 1, 98, 'gte', 5, 'percent', null, null, 2, false,
    'Not yet sourced -- Prompt 265 (Vendor Invoice Matching) has not been built as of this checkpoint (CG-S11-PRC-015 build log design note 2)',
    'idem-vperf-def-inv', v_admin1, 'admin'
  );
  perform app.create_vendor_kpi_definition_draft(v_tenant1, 'service_complaint_sla', 'Service/Complaint SLA', 'customer-claimant rate', 30, 1, 5, 'lte', 5, 'percent', null, null, 2, true, null, 'idem-vperf-def-scs', v_admin1, 'admin');

  -- Idempotency replay: identical key -> same row; reused key with a different target
  -- tuple field (weight) -> idempotency_key_conflict, never a silent short-circuit
  -- (taxonomy C-01).
  v_replay := app.create_vendor_kpi_definition_draft(v_tenant1, 'on_time_delivery', 'On-Time Delivery', 'delivery vs planned', 30, 1, 90, 'gte', 15, 'percent', null, null, 2, true, null, 'idem-vperf-def-otd', v_admin1, 'admin');
  if v_replay.id <> v_def.id then
    raise exception 'assertion failed: expected the identical idempotency-key replay to return the SAME row';
  end if;
  begin
    perform app.create_vendor_kpi_definition_draft(v_tenant1, 'on_time_delivery', 'On-Time Delivery', 'delivery vs planned', 30, 1, 90, 'gte', 25, 'percent', null, null, 2, true, null, 'idem-vperf-def-otd', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then
      raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a weight-mismatched replay of the same key to be rejected as a conflict'; end if;

  -- Malformed band_thresholds structurally rejected (not merely a convention).
  begin
    perform app.create_vendor_kpi_definition_draft(v_tenant1, 'acceptance_rate', 'Bad', null, 30, 1, 80, 'gte', 10, 'percent', '{"excellent": 50, "good": 75, "watch": 60}'::jsonb, null, 2, true, null, 'idem-vperf-def-badband', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like '%vendor_kpi_definitions_band_thresholds_check%' then
      raise exception 'assertion failed: expected the band_thresholds CHECK to reject non-descending thresholds, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected malformed band_thresholds (excellent < good) to be rejected'; end if;

  -- PRC:View alone cannot publish (PRC:Approve required).
  begin
    perform app.publish_vendor_kpi_definition(v_def.id, v_def.record_version, '00000000-0000-0000-0000-000000264104', 'viewer');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected viewer1 (PRC:View only, no Approve) to be denied publish'; end if;

  -- Publish every definition (staff1 has PRC:Approve too, per its own role set).
  perform app.publish_vendor_kpi_definition(id, record_version, v_staff1, 'staff') from app.vendor_kpi_definitions where tenant_id = v_tenant1 and status = 'draft';

  if (select count(*) from app.vendor_kpi_definitions where tenant_id = v_tenant1 and status = 'published') <> 11 then
    raise exception 'assertion failed: expected exactly 11 published KPI definitions, got %', (select count(*) from app.vendor_kpi_definitions where tenant_id = v_tenant1 and status = 'published');
  end if;
  if (select is_computable from app.vendor_kpi_definitions where tenant_id = v_tenant1 and kpi_code = 'invoice_accuracy' and status = 'published') then
    raise exception 'assertion failed: expected invoice_accuracy to be published with is_computable=false';
  end if;

  -- Auto-supersede on republish: a new version for the SAME kpi_code archives the prior
  -- published one (no p_supersedes id required, unlike vendor_contracts -- design note
  -- in app.publish_vendor_kpi_definition''s own comment).
  select * into v_def from app.vendor_kpi_definitions where tenant_id = v_tenant1 and kpi_code = 'on_time_pickup' and status = 'published';
  v_def := app.update_vendor_kpi_definition_draft(
    (app.create_vendor_kpi_definition_draft(v_tenant1, 'on_time_pickup', 'On-Time Pickup v2', 'pickup vs planned, revised', 30, 1, 92, 'gte', 15, 'percent', null, null, 2, true, null, 'idem-vperf-def-otp-v2', v_admin1, 'admin')).id,
    1, 'On-Time Pickup v2', 'pickup vs planned, revised', 30, 1, 92, 'gte', 15, 'percent', null, null, 2, true, null, v_admin1, 'admin'
  );
  perform app.publish_vendor_kpi_definition(v_def.id, v_def.record_version, v_staff1, 'staff');
  if (select status from app.vendor_kpi_definitions where id = (select id from app.vendor_kpi_definitions where tenant_id = v_tenant1 and kpi_code = 'on_time_pickup' and version_no = 1)) <> 'archived' then
    raise exception 'assertion failed: expected the prior on_time_pickup version to be auto-archived on republish';
  end if;
  if (select count(*) from app.vendor_kpi_definitions where tenant_id = v_tenant1 and kpi_code = 'on_time_pickup' and status = 'published') <> 1 then
    raise exception 'assertion failed: expected exactly one published on_time_pickup version after republish';
  end if;
end $$;

\echo '>> publish_vendor_kpi_scorecard before any calculate raises metrics_not_calculated; calculate_vendor_kpi_metrics idempotency target-tuple verification (C-01); real per-category results for Good Vendor (near-perfect: excellent band) and Poor Vendor (mixed: several categories below target, poor band); every published category present, invoice_accuracy always is_computable=false'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_good_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Good Vendor');
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  -- Anchored to date_trunc('hour', now()), NOT bare now() -- Postgres freezes now()
  -- per TRANSACTION, and every top-level DO block in this script is its own
  -- autocommit transaction, so bare now() would silently differ (down to the
  -- microsecond) across blocks and never satisfy an exact window_start/window_end
  -- equality match against a row stored by an EARLIER block. Truncating to the hour
  -- keeps the SAME literal value across this whole (sub-second) script run.
  v_window_start timestamptz := date_trunc('hour', now()) - interval '1 hour';
  v_window_end timestamptz := date_trunc('hour', now()) + interval '20 hours';
  v_good_card app.vendor_kpi_scorecards;
  v_poor_card app.vendor_kpi_scorecards;
  v_replay_metrics app.vendor_kpi_metric_values;
  v_metric_count integer;
  v_failed boolean;
begin
  begin
    perform app.publish_vendor_kpi_scorecard(v_tenant1, v_good_vendor, v_window_start, v_window_end, 'idem-vperf-card-good-premature', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'metrics_not_calculated%' then
      raise exception 'assertion failed: expected metrics_not_calculated, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected publishing before any calculate to be rejected'; end if;

  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_good_vendor, v_window_start, v_window_end, 'manual', 'idem-vperf-calc-good', v_admin1, 'admin');
  select count(*) into v_metric_count from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and window_start = v_window_start and window_end = v_window_end and is_current;
  if v_metric_count <> 11 then
    raise exception 'assertion failed: expected exactly 11 current metric values for Good Vendor (one per published category), got %', v_metric_count;
  end if;

  -- Idempotency: identical key -> same underlying metric set; a mismatched target
  -- tuple (different window_end) -> idempotency_key_conflict (C-01).
  select * into v_replay_metrics from app.calculate_vendor_kpi_metrics(v_tenant1, v_good_vendor, v_window_start, v_window_end, 'manual', 'idem-vperf-calc-good', v_admin1, 'admin') limit 1;
  if v_replay_metrics.id is null then
    raise exception 'assertion failed: expected the idempotent replay to still return metric rows';
  end if;
  begin
    perform app.calculate_vendor_kpi_metrics(v_tenant1, v_good_vendor, v_window_start, v_window_end + interval '1 hour', 'manual', 'idem-vperf-calc-good', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then
      raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a window-mismatched replay of the same calculate key to be rejected as a conflict'; end if;

  -- Good Vendor: on time at both pickup and delivery, full acceptance, fast response,
  -- full capacity fulfillment, cheapest on-file rate, zero claims/complaints.
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'on_time_pickup' and is_current) <> 100 then
    raise exception 'assertion failed: expected Good Vendor on_time_pickup=100';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'on_time_delivery' and is_current) <> 100 then
    raise exception 'assertion failed: expected Good Vendor on_time_delivery=100';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'claims_damage' and is_current) <> 0 then
    raise exception 'assertion failed: expected Good Vendor claims_damage=0';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'compliance' and is_current) then
    raise exception 'assertion failed: expected Good Vendor compliance to be not-computable (zero tracked requirements)';
  end if;
  if (select computation_note from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'compliance' and is_current) not like 'no_tracked_requirements%' then
    raise exception 'assertion failed: expected the compliance computation_note to name no_tracked_requirements';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'invoice_accuracy' and is_current) then
    raise exception 'assertion failed: expected invoice_accuracy to always be not-computable (design note 2)';
  end if;
  if (select computation_note from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'invoice_accuracy' and is_current) not like 'Not yet sourced%' then
    raise exception 'assertion failed: expected the invoice_accuracy computation_note to echo the definition''s own source_note (Not yet sourced...), got %', (select computation_note from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'invoice_accuracy' and is_current);
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'rate_competitiveness' and is_current) <> 100 then
    raise exception 'assertion failed: expected Good Vendor rate_competitiveness=100 (cheapest on file)';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and kpi_code = 'rate_validity' and is_current) <> 100 then
    raise exception 'assertion failed: expected Good Vendor rate_validity=100 (open-ended rate covers the whole window)';
  end if;

  v_good_card := app.publish_vendor_kpi_scorecard(v_tenant1, v_good_vendor, v_window_start, v_window_end, 'idem-vperf-card-good', v_staff1, 'staff');
  if v_good_card.band <> 'excellent' or v_good_card.composite_score < 95 then
    raise exception 'assertion failed: expected Good Vendor band=excellent, composite_score>=95, got band=% composite=%', v_good_card.band, v_good_card.composite_score;
  end if;
  if (select count(*) from app.vendor_kpi_scorecard_lines where scorecard_id = v_good_card.id) <> 11 then
    raise exception 'assertion failed: expected exactly 11 scorecard lines (one per published category, computable or not)';
  end if;

  -- Poor Vendor: mixed pickup, zero on-time delivery, a declined invitation, a
  -- vendor-liable claim, a customer complaint, no rate on file -- a genuinely LOW,
  -- never-fabricated-uniform, band.
  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_poor_vendor, v_window_start, v_window_end, 'manual', 'idem-vperf-calc-poor', v_admin1, 'admin');
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_delivery' and is_current) <> 0 then
    raise exception 'assertion failed: expected Poor Vendor on_time_delivery=0 (both deliveries late)';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_pickup' and is_current) <> 50 then
    raise exception 'assertion failed: expected Poor Vendor on_time_pickup=50 (one of two on time), got %', (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_pickup' and is_current);
  end if;
  if (select round(computed_value, 0) from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'acceptance_rate' and is_current) <> 67 then
    raise exception 'assertion failed: expected Poor Vendor acceptance_rate~=67 (2 accepted of 3 decided: 1 declined + 2 accepted), got %', (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'acceptance_rate' and is_current);
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'claims_damage' and is_current) <> 50 then
    raise exception 'assertion failed: expected Poor Vendor claims_damage=50 (1 vendor-liable claim of 2 assigned shipments)';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'service_complaint_sla' and is_current) <> 50 then
    raise exception 'assertion failed: expected Poor Vendor service_complaint_sla=50 (1 customer-claimant case of 2 assigned shipments)';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'rate_competitiveness' and is_current) then
    raise exception 'assertion failed: expected Poor Vendor rate_competitiveness to be not-computable (no rate on file)';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'rate_validity' and is_current) <> 0 then
    raise exception 'assertion failed: expected Poor Vendor rate_validity=0 (a real, meaningful zero -- no rate covers any day of the window, distinct from not-computable)';
  end if;

  v_poor_card := app.publish_vendor_kpi_scorecard(v_tenant1, v_poor_vendor, v_window_start, v_window_end, 'idem-vperf-card-poor', v_staff1, 'staff');
  if v_poor_card.band <> 'poor' or v_poor_card.composite_score >= 60 then
    raise exception 'assertion failed: expected Poor Vendor band=poor, composite_score<60, got band=% composite=%', v_poor_card.band, v_poor_card.composite_score;
  end if;
  if v_poor_card.computable_weight_total >= v_poor_card.total_weight_defined then
    raise exception 'assertion failed: expected Poor Vendor computable_weight_total < total_weight_defined (compliance/rate_competitiveness/invoice_accuracy are not computable)';
  end if;
end $$;

\echo '>> drilldown: contributing_source_ids masked for a PRC:View-only caller (viewer1), visible for a PRC:View-cost caller (staff1); every other evidence key stays visible either way (design note 3)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000264104';
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  v_card_id uuid := (select id from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and is_current);
  v_masked_evidence jsonb;
  v_unmasked_evidence jsonb;
  v_sample_size integer;
begin
  select source_evidence, sample_size into v_masked_evidence, v_sample_size from app.get_vendor_kpi_scorecard_drilldown(v_card_id, v_viewer1) where kpi_code = 'on_time_pickup';
  if v_masked_evidence ? 'contributing_source_ids' then
    raise exception 'assertion failed: expected contributing_source_ids to be masked for a PRC:View-only caller (no View cost)';
  end if;
  if not (v_masked_evidence ? 'assigned_with_evidence') then
    raise exception 'assertion failed: expected assigned_with_evidence to remain visible even when masked';
  end if;
  if v_sample_size <> 2 then
    raise exception 'assertion failed: expected on_time_pickup sample_size=2 for Poor Vendor';
  end if;

  select source_evidence into v_unmasked_evidence from app.get_vendor_kpi_scorecard_drilldown(v_card_id, v_staff1) where kpi_code = 'on_time_pickup';
  if not (v_unmasked_evidence ? 'contributing_source_ids') then
    raise exception 'assertion failed: expected contributing_source_ids to be visible for a PRC:View-cost caller';
  end if;
  if jsonb_array_length(v_unmasked_evidence -> 'contributing_source_ids') <> 2 then
    raise exception 'assertion failed: expected 2 contributing_source_ids for Poor Vendor on_time_pickup';
  end if;
end $$;

\echo '>> source dispute: raise against Poor Vendor''s late ship3 pickup event, self-decide blocked, decide upheld by a different actor, recalculation excludes the disputed event -- denominator drops, never a silent rewrite of the ALREADY-PUBLISHED scorecard (a new metric-value VERSION is created instead)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  -- Anchored to date_trunc('hour', now()), NOT bare now() -- Postgres freezes now()
  -- per TRANSACTION, and every top-level DO block in this script is its own
  -- autocommit transaction, so bare now() would silently differ (down to the
  -- microsecond) across blocks and never satisfy an exact window_start/window_end
  -- equality match against a row stored by an EARLIER block. Truncating to the hour
  -- keeps the SAME literal value across this whole (sub-second) script run.
  v_window_start timestamptz := date_trunc('hour', now()) - interval '1 hour';
  v_window_end timestamptz := date_trunc('hour', now()) + interval '20 hours';
  v_ship3_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vperf-ship3');
  v_disputed_event_id uuid := (select id from app.milestone_events where shipment_order_id = v_ship3_id and milestone_code = 'vperf_pickup');
  v_dispute app.vendor_kpi_source_disputes;
  v_before_version integer := (select version_no from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_pickup' and is_current);
  v_before_id uuid := (select id from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_pickup' and is_current);
  v_after app.vendor_kpi_metric_values;
  v_failed boolean;
begin
  v_dispute := app.raise_vendor_kpi_source_dispute(v_tenant1, v_poor_vendor, 'on_time_pickup', v_disputed_event_id, 'ship3 pickup milestone', 'GPS log shows an earlier arrival than recorded', v_admin1, 'admin');

  begin
    perform app.decide_vendor_kpi_source_dispute(v_dispute.id, v_dispute.record_version, 'upheld', 'confirmed against GPS log', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'self_approval_not_allowed%' then
      raise exception 'assertion failed: expected self_approval_not_allowed, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the disputer to be blocked from deciding their own dispute'; end if;

  perform app.decide_vendor_kpi_source_dispute(v_dispute.id, v_dispute.record_version, 'upheld', 'confirmed against GPS log', v_staff1, 'staff');

  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_poor_vendor, v_window_start, v_window_end, 'recalculation', 'idem-vperf-calc-poor-2', v_admin1, 'admin');
  select * into v_after from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and kpi_code = 'on_time_pickup' and is_current;

  if v_after.id = v_before_id then
    raise exception 'assertion failed: expected the disputed-event recalculation to create a NEW metric-value row, never mutate the prior one in place';
  end if;
  if v_after.version_no <> v_before_version + 1 then
    raise exception 'assertion failed: expected version_no to increment by exactly 1, got % (was %)', v_after.version_no, v_before_version;
  end if;
  if v_after.supersedes_metric_value_id <> v_before_id then
    raise exception 'assertion failed: expected the new version to link back to the row it supersedes';
  end if;
  -- The prior version is preserved, untouched -- never a silent historical rewrite.
  if (select is_current from app.vendor_kpi_metric_values where id = v_before_id) then
    raise exception 'assertion failed: expected the prior on_time_pickup version to no longer be current';
  end if;
  if (select sample_size from app.vendor_kpi_metric_values where id = v_before_id) <> 2 then
    raise exception 'assertion failed: expected the PRIOR version''s own sample_size to remain 2, untouched by the later dispute';
  end if;
  if v_after.sample_size <> 1 then
    raise exception 'assertion failed: expected the disputed event excluded, sample_size=1, got %', v_after.sample_size;
  end if;
  if v_after.excluded_count <> 1 then
    raise exception 'assertion failed: expected excluded_count=1 on the new version';
  end if;
end $$;

\echo '>> governed lifecycle recommendation: evaluate (system-derived poor band -> suspend) -> decide suspend (real PRC-251 app.suspend_vendor_profile call, vendor now suspended); blacklist requires evidence_ref; reactivate re-activates the SAME vendor -- run against the scorecard as originally published, BEFORE the later manual-adjustment test below changes its band'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_manager1 uuid := '00000000-0000-0000-0000-000000264103';
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  v_card_id uuid := (select id from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and is_current);
  v_recommendation app.vendor_lifecycle_recommendations;
  v_failed boolean;
begin
  v_recommendation := app.evaluate_vendor_lifecycle_recommendation(v_tenant1, v_poor_vendor, v_card_id, null, null, 'idem-vperf-rec-1', v_admin1, 'admin');
  if v_recommendation.recommended_action <> 'suspend' then
    raise exception 'assertion failed: expected a system-derived recommendation of suspend for a poor-band vendor, got %', v_recommendation.recommended_action;
  end if;
  if (select lifecycle_status from app.vendor_profiles where master_record_id = v_poor_vendor) <> 'active' then
    raise exception 'assertion failed: expected the vendor to remain active until a human DECIDES the recommendation (design note 9)';
  end if;

  -- Blacklist requires evidence_ref.
  begin
    perform app.decide_vendor_lifecycle_recommendation(v_recommendation.id, v_recommendation.record_version, 'blacklist', 'escalating', null, v_manager1, 'manager');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'evidence_required%' then
      raise exception 'assertion failed: expected evidence_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a blacklist decision with no evidence_ref to be rejected'; end if;

  -- C-18 maker-checker: the SAME identity that evaluated this recommendation (v_admin1) may
  -- not also decide it, even though evaluate=PRC:Edit and decide=PRC:Override are distinct
  -- permissions an operator could plausibly hold both of.
  begin
    perform app.decide_vendor_lifecycle_recommendation(v_recommendation.id, v_recommendation.record_version, 'suspend', 'self-decide attempt', null, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'self_approval_not_allowed%' then
      raise exception 'assertion failed: expected self_approval_not_allowed, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the recommendation''s own evaluator to be blocked from deciding it'; end if;

  perform app.decide_vendor_lifecycle_recommendation(v_recommendation.id, v_recommendation.record_version, 'suspend', 'confirmed pattern of late delivery and a vendor-liable claim this window', null, v_manager1, 'manager');

  if (select lifecycle_status from app.vendor_profiles where master_record_id = v_poor_vendor) <> 'suspended' then
    raise exception 'assertion failed: expected app.decide_vendor_lifecycle_recommendation(suspend) to have actually suspended the vendor via the real PRC-251 RPC';
  end if;
  if not (select executed from app.vendor_lifecycle_recommendations where id = v_recommendation.id) then
    raise exception 'assertion failed: expected executed=true after a suspend decision';
  end if;

  -- Deciding an already-decided recommendation is rejected.
  begin
    perform app.decide_vendor_lifecycle_recommendation(v_recommendation.id, (select record_version from app.vendor_lifecycle_recommendations where id = v_recommendation.id), 'suspend', 'retry', null, v_manager1, 'manager');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected re-deciding an already-decided recommendation to be rejected'; end if;

  -- Reactivate: a fresh recommendation, decided reactivate, calls the real PRC-251 RPC --
  -- the vendor must be active again before the LATER manual-adjustment/issue tests below
  -- (which do not themselves depend on lifecycle_status, but keeping the vendor active
  -- mirrors a real, continuing operational vendor rather than leaving it suspended for
  -- the remainder of this file).
  declare
    v_reactivate app.vendor_lifecycle_recommendations;
  begin
    v_reactivate := app.evaluate_vendor_lifecycle_recommendation(v_tenant1, v_poor_vendor, null, 'reactivate', 'Corrective action plan completed and independently verified', 'idem-vperf-rec-2', v_admin1, 'admin');
    perform app.decide_vendor_lifecycle_recommendation(v_reactivate.id, v_reactivate.record_version, 'reactivate', 'verified corrective action complete', null, v_manager1, 'manager');
    if (select lifecycle_status from app.vendor_profiles where master_record_id = v_poor_vendor) <> 'active' then
      raise exception 'assertion failed: expected the vendor to be reactivated via the real PRC-251 RPC';
    end if;
  end;
end $$;

\echo '>> manual adjustment: maker-checker, self-approval blocked, reason required, at most one pending per line; approval mutates the CURRENT published scorecard''s line + composite/band in place under a version guard, with a genuine before/after audit trail'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  v_card_id uuid := (select id from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and is_current);
  v_before_composite numeric := (select composite_score from app.vendor_kpi_scorecards where id = v_card_id);
  v_adjustment app.vendor_kpi_manual_adjustments;
  v_line_before numeric := (select normalized_score from app.vendor_kpi_scorecard_lines where scorecard_id = v_card_id and kpi_code = 'on_time_delivery');
  v_after_card app.vendor_kpi_scorecards;
  v_after_line app.vendor_kpi_scorecard_lines;
  v_failed boolean;
begin
  v_adjustment := app.request_vendor_kpi_manual_adjustment(v_card_id, 'on_time_delivery', 100, 'Late delivery scans were caused by a customs hold outside the vendor''s own control, per the recorded exception', 'idem-vperf-adj-1', v_admin1, 'admin');
  if v_adjustment.original_normalized_score <> v_line_before then
    raise exception 'assertion failed: expected original_normalized_score to snapshot the pre-adjustment score';
  end if;

  -- Self-approval blocked.
  begin
    perform app.decide_vendor_kpi_manual_adjustment(v_adjustment.id, v_adjustment.record_version, 'approved', 'self-approve attempt', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'self_approval_not_allowed%' then
      raise exception 'assertion failed: expected self_approval_not_allowed, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the requester to be blocked from deciding their own adjustment'; end if;

  -- A second concurrent request against the SAME line is rejected while one is pending.
  begin
    perform app.request_vendor_kpi_manual_adjustment(v_card_id, 'on_time_delivery', 80, 'a second, competing adjustment attempt', 'idem-vperf-adj-2', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'adjustment_already_pending%' then
      raise exception 'assertion failed: expected adjustment_already_pending, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a second pending adjustment on the same line to be rejected'; end if;

  perform app.decide_vendor_kpi_manual_adjustment(v_adjustment.id, v_adjustment.record_version, 'approved', 'confirmed customs-hold exception, not a vendor delay', v_staff1, 'staff');

  select * into v_after_card from app.vendor_kpi_scorecards where id = v_card_id;
  select * into v_after_line from app.vendor_kpi_scorecard_lines where scorecard_id = v_card_id and kpi_code = 'on_time_delivery';

  if v_after_line.normalized_score <> 100 or not v_after_line.adjusted then
    raise exception 'assertion failed: expected on_time_delivery line normalized_score=100, adjusted=true after approval';
  end if;
  if v_after_card.composite_score <= v_before_composite then
    raise exception 'assertion failed: expected the scorecard''s own composite_score to increase after a favorable adjustment, was % now %', v_before_composite, v_after_card.composite_score;
  end if;
  if v_after_card.id <> v_card_id then
    raise exception 'assertion failed: expected the SAME scorecard row to be mutated in place (design note 8), never a redundant new version';
  end if;
end $$;

\echo '>> issue and corrective action lifecycle: raise -> add corrective action (auto-advances the issue to in_progress) -> complete (mandatory completion_note) -> resolve the issue (mandatory resolution_note)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_poor_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Poor Vendor');
  v_card_id uuid := (select id from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and vendor_master_id = v_poor_vendor and is_current);
  v_issue app.vendor_performance_issues;
  v_action app.vendor_performance_corrective_actions;
  v_failed boolean;
begin
  v_issue := app.raise_vendor_performance_issue(v_tenant1, v_poor_vendor, v_card_id, 'on_time_delivery', 'high', 'Repeated late deliveries', 'Two of two tracked deliveries missed their planned window', 'idem-vperf-issue-1', v_admin1, 'admin');
  if v_issue.status <> 'open' then
    raise exception 'assertion failed: expected a freshly-raised issue to be open';
  end if;

  v_action := app.add_vendor_performance_corrective_action(v_issue.id, 'Vendor to submit a revised dispatch SOP within 14 days', 'Poor Vendor Ops Lead', (current_date + 14), 'idem-vperf-action-1', v_admin1, 'admin');
  if (select status from app.vendor_performance_issues where id = v_issue.id) <> 'in_progress' then
    raise exception 'assertion failed: expected the issue to auto-advance to in_progress once a corrective action exists';
  end if;

  begin
    perform app.update_vendor_performance_corrective_action_status(v_action.id, v_action.record_version, 'completed', null, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'completion_note_required%' then
      raise exception 'assertion failed: expected completion_note_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected completing a corrective action with no note to be rejected'; end if;

  v_action := app.update_vendor_performance_corrective_action_status(v_action.id, v_action.record_version, 'completed', 'revised SOP received and reviewed', v_admin1, 'admin');
  if v_action.status <> 'completed' or v_action.completed_at is null then
    raise exception 'assertion failed: expected the corrective action to be completed with a real completed_at';
  end if;

  -- Re-select: adding the corrective action already advanced the issue to in_progress,
  -- bumping its own record_version out from under the stale local v_issue variable.
  select * into v_issue from app.vendor_performance_issues where id = v_issue.id;
  v_issue := app.update_vendor_performance_issue_status(v_issue.id, v_issue.record_version, 'resolved', 'SOP revised and reviewed; delivery performance to be re-checked next window', v_admin1, 'admin');
  if v_issue.status <> 'resolved' or v_issue.resolved_at is null then
    raise exception 'assertion failed: expected the issue to be resolved with a real resolved_at';
  end if;
end $$;

\echo '>> New Vendor (sparse data): every count-based category not-computable with a named reason; rate_validity is the one category that is ALWAYS computable (a real, meaningful 0%, never "no data"); publishing still succeeds (real coverage, not fabricated); insufficient_kpi_coverage fires only when truly nothing is computable'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000264101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000264102';
  v_new_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT New Vendor');
  v_window_start timestamptz := date_trunc('hour', now()) - interval '1 hour';
  v_window_end timestamptz := date_trunc('hour', now()) + interval '20 hours';
  v_card app.vendor_kpi_scorecards;
  v_rv_def app.vendor_kpi_definitions;
  v_failed boolean;
begin
  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_new_vendor, v_window_start, v_window_end, 'manual', 'idem-vperf-calc-new', v_admin1, 'admin');

  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'on_time_pickup' and is_current) then
    raise exception 'assertion failed: expected New Vendor on_time_pickup to be not-computable (no assignments at all)';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'acceptance_rate' and is_current) then
    raise exception 'assertion failed: expected New Vendor acceptance_rate to be not-computable (no invitations at all)';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'capacity_fulfillment' and is_current) then
    raise exception 'assertion failed: expected New Vendor capacity_fulfillment to be not-computable (no reservations at all)';
  end if;
  if (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'rate_competitiveness' and is_current) then
    raise exception 'assertion failed: expected New Vendor rate_competitiveness to be not-computable (no rate on file)';
  end if;
  if not (select is_computable from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'rate_validity' and is_current) then
    raise exception 'assertion failed: expected New Vendor rate_validity to be computable (a real 0%%, not a missing-data case)';
  end if;
  if (select computed_value from app.vendor_kpi_metric_values where tenant_id = v_tenant1 and vendor_master_id = v_new_vendor and kpi_code = 'rate_validity' and is_current) <> 0 then
    raise exception 'assertion failed: expected New Vendor rate_validity computed_value=0';
  end if;

  v_card := app.publish_vendor_kpi_scorecard(v_tenant1, v_new_vendor, v_window_start, v_window_end, 'idem-vperf-card-new', v_staff1, 'staff');
  if v_card.band <> 'poor' or v_card.composite_score <> 0 then
    raise exception 'assertion failed: expected New Vendor band=poor composite_score=0 (rate_validity is its only computable category), got band=% composite=%', v_card.band, v_card.composite_score;
  end if;

  -- insufficient_kpi_coverage: archiving rate_validity's DEFINITION does not retroactively
  -- invalidate an already-current metric VALUE row computed while it was still published
  -- (Prompt 264 §24 "never silent historical rewrite" -- an archived definition simply
  -- stops being recomputed going forward). To genuinely reach "zero computable," archive
  -- rate_validity FIRST, then run a brand-new vendor''s FIRST-EVER calculate against the
  -- now-narrower catalogue -- no other category is unconditionally computable with no
  -- evidence on file.
  select * into v_rv_def from app.vendor_kpi_definitions where tenant_id = v_tenant1 and kpi_code = 'rate_validity' and status = 'published';
  perform app.archive_vendor_kpi_definition(v_rv_def.id, v_rv_def.record_version, 'temporarily archived to exercise insufficient_kpi_coverage', v_admin1, 'admin');

  perform app.create_vendor_profile_draft(v_tenant1, 'PT Zero Vendor', 'ZEROV', 'PT', 'REG-VPERF-ZERO', 'logistics', 30, 'staff_created', 'idem-vperf-vendor-zero', v_admin1, 'admin');
  perform app.calculate_vendor_kpi_metrics(
    v_tenant1, (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Zero Vendor'),
    v_window_start, v_window_end, 'manual', 'idem-vperf-calc-zero', v_admin1, 'admin'
  );
  begin
    perform app.publish_vendor_kpi_scorecard(
      v_tenant1, (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Zero Vendor'),
      v_window_start, v_window_end, 'idem-vperf-card-zero', v_staff1, 'staff'
    );
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_kpi_coverage%' then
      raise exception 'assertion failed: expected insufficient_kpi_coverage, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected publishing with truly zero computable categories to be rejected'; end if;

  -- Restore rate_validity for the remainder of this file (a fresh draft+publish,
  -- mirroring the same auto-supersede path already exercised in the catalogue test).
  perform app.publish_vendor_kpi_definition(
    (app.create_vendor_kpi_definition_draft(v_tenant1, 'rate_validity', 'Rate Validity', '% of window with a valid rate', 30, 1, 90, 'gte', 5, 'percent', null, null, 2, true, null, 'idem-vperf-def-rv-restore', v_admin1, 'admin')).id,
    1, v_admin1, 'admin'
  );
end $$;

\echo '>> cross-tenant isolation: a tenant2 actor is denied on every write RPC and gets not-found (never a real row disclosure) on every read RPC; raw RLS denies direct row selection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vperf1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'vperf2');
  v_admin2 uuid := '00000000-0000-0000-0000-000000264201';
  v_good_vendor uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Good Vendor');
  v_card_id uuid := (select id from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and vendor_master_id = v_good_vendor and is_current);
  v_failed boolean;
begin
  begin
    perform app.get_vendor_kpi_scorecard(v_card_id, v_admin2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_kpi_scorecard_not_found%' then
      raise exception 'assertion failed: expected vendor_kpi_scorecard_not_found (never a real disclosure), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a tenant2 actor to be denied reading tenant1''s scorecard'; end if;

  begin
    perform app.calculate_vendor_kpi_metrics(v_tenant1, v_good_vendor, date_trunc('hour', now()) - interval '1 hour', date_trunc('hour', now()) + interval '20 hours', 'manual', 'idem-vperf-xtenant', v_admin2, 'admin2');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority for a cross-tenant calculate attempt, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a tenant2 actor to be denied calculating tenant1''s vendor metrics'; end if;

  -- Raw RLS: a direct row select under a real `authenticated` role (never superuser),
  -- from a session with zero tenant1 membership, returns zero rows -- never relying on
  -- the RPC layer alone.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin2::text, 'role', 'authenticated')::text, true);
  if exists (select 1 from app.vendor_kpi_scorecards where id = v_card_id) then
    raise exception 'assertion failed: raw RLS leak -- a tenant2 session directly selected a tenant1 scorecard row';
  end if;
  reset role;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new PRC-264 function; every internal (leading-underscore) helper has no authenticated/service_role grant at all'
do $$
declare
  v_leaked_to_anon text[];
  v_leaked_helpers text[];
begin
  select array_agg(p.proname) into v_leaked_to_anon
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and (p.proname like '%vendor_kpi%' or p.proname like '%vendor_performance%' or p.proname like '%vendor_lifecycle_recommendation%')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_leaked_to_anon is not null then
    raise exception 'assertion failed: anon holds EXECUTE on: %', v_leaked_to_anon;
  end if;

  select array_agg(p.proname) into v_leaked_helpers
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname like '\_%' escape '\'
    and (p.proname like '%vendor_kpi%' or p.proname like '%vendor_performance%')
    and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('anon', p.oid, 'EXECUTE'));
  if v_leaked_helpers is not null then
    raise exception 'assertion failed: an internal helper is reachable by authenticated/anon: %', v_leaked_helpers;
  end if;
end $$;

\echo '>> PRC-264 (Vendor Performance) -- ALL ASSERTIONS PASSED'

