-- Real, executable test evidence for PRC-266 (Procurement Dashboard and Reports,
-- CG-S11-PRC-017) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Scoped to this checkpoint's own additive migration (supabase/migrations/
-- 20260730780000_create_procurement_dashboard_reports.sql). Self-contained -- builds
-- its own tenant/vendor/rate/contract/capacity/RFQ/PO/KPI pipeline from scratch,
-- mirroring procurement-vendor-performance.sql/procurement-vendor-invoice-matching.sql's
-- own disclosed convention.
--
-- Reconciliation strategy: every metric assertion below computes its own "expected"
-- aggregate via a plain, independent SQL query against the SAME source tables the
-- dashboard RPC reads, then compares that independently-derived value to the RPC's own
-- output -- never a hand-derived magic number. This is the same discipline this
-- repository's own reconciliation-shaped tests already use elsewhere.
--
-- Disclosed, not exhaustively re-tested here (bounded scope, not an oversight -- "at
-- least 2 metrics per group where feasible", Prompt 266's own required outputs §2):
--   * app.vendor_compliance_status and app.vendor_assignment_invitations rows below are
--     DIRECT inserts, not driven through their own real create RPCs -- PRC-253's
--     compliance recalculation and PRC-263's assignment-eligibility RPCs are already
--     exhaustively tested by their own db-test suites; this file only proves the
--     dashboard aggregate correctly reads whatever those tables already hold, mirroring
--     procurement-vendor-performance.sql's own identical disclosed choice for
--     vendor_compliance_status.
--   * Group 7 (match variance/exception rate) is satisfied ENTIRELY by reusing PRC-265's
--     own already-VERIFIED app.get_vendor_bill_match_reconciliation_status (design note
--     2 in this checkpoint's own migration header) -- this file proves only that this
--     dashboard's own catalog/export layer correctly cites and can enqueue it, never
--     re-derives its own vendor_bill_match_cases fixture (PRC-265's own db-test suite,
--     scripts/db-tests/procurement-vendor-invoice-matching.sql, already exhaustively
--     covers that function's own correctness/masking).
--   * A live two-process concurrent race on saved-view update/delete's own optimistic
--     lock is not reproduced here -- deferred to this batch's own Tier C
--     correctness/concurrency lens, mirroring every prior PRC-25x/26x db-test's own
--     identical disclosure for its own versioned-update races.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (pdash1, pdash2). Tenant1: tenant_admin (admin1), full-PRC staff (staff1, Create/Edit/View/View cost/Approve/Export), a view-only actor (viewer1, View only -- no View cost, no Export), a no-PRC outsider (outsider1), a second staff (staff1b, same role as staff1, for saved-view owner-isolation). Tenant2: tenant_admin (admin2, full PRC). A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_staff_role uuid;
  v_viewer_role uuid;
  v_outsider_role uuid;
  v_t2_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000266101', 'admin@pdash1.test'),
    ('00000000-0000-0000-0000-000000266102', 'staff@pdash1.test'),
    ('00000000-0000-0000-0000-000000266103', 'staffb@pdash1.test'),
    ('00000000-0000-0000-0000-000000266104', 'viewer@pdash1.test'),
    ('00000000-0000-0000-0000-000000266105', 'outsider@pdash1.test'),
    ('00000000-0000-0000-0000-000000266201', 'admin@pdash2.test'),
    ('00000000-0000-0000-0000-000000266999', 'supreme@pdash.test');

  perform app.provision_tenant('pdash1', 'Procurement Dashboard Co 1', 'idem-pdash1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'pdash1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('pdash2', 'Procurement Dashboard Co 2', 'idem-pdash2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'pdash2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000266101', 'admin@pdash1.test', 'Pdash1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pdash1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000266101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000266102', 'staff@pdash1.test', 'Pdash1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@pdash1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000266103', 'staffb@pdash1.test', 'Pdash1 Staff B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staffb@pdash1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000266104', 'viewer@pdash1.test', 'Pdash1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@pdash1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000266105', 'outsider@pdash1.test', 'Pdash1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@pdash1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000266201', 'admin@pdash2.test', 'Pdash2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pdash2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000266201', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000266999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Pdash1 Admin', 'full PRC for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve', 'Export'))
      or (resource_module_code = 'FIN' and action = 'View')
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))
      or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000266101', '00000000-0000-0000-0000-000000266999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Pdash1 Staff', 'Create/Edit/View/View cost/Approve/Export', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve', 'Export')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000266102', '00000000-0000-0000-0000-000000266101', 'admin');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000266103', '00000000-0000-0000-0000-000000266101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Pdash1 Viewer', 'View only, no View cost, no Export', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000266104', '00000000-0000-0000-0000-000000266101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Pdash1 Outsider', 'no PRC at all', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_outsider_role, 'tester')).id, array[]::uuid[], 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_outsider_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000266105', '00000000-0000-0000-0000-000000266101', 'admin');

  v_t2_role := (app.create_role(v_tenant2, 'Pdash2 Admin Role', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Approve', 'Export')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000266201', '00000000-0000-0000-0000-000000266201', 'admin');
end $$;

\echo '>> setup: three vendors in tenant1 (Good=active/compliant/competitive, Risky=active/hold/expiring, New=draft/zero-data), a Market vendor for competitiveness ranking, contracts, capacity offers+reservations, rate versions, one KPI definition (rate_validity) calculated+published for Good/Risky, and one sourcing->RFQ->comparison->PO pipeline per PO status (issued, cancelled)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000266101';
  v_good app.vendor_profiles;
  v_risky app.vendor_profiles;
  v_new app.vendor_profiles;
  v_market app.vendor_profiles;
  v_good_contract app.vendor_contracts;
  v_risky_contract app.vendor_contracts;
  v_good_offer app.vendor_capacity_offers;
  v_risky_offer app.vendor_capacity_offers;
  v_good_res app.vendor_capacity_reservations;
  v_risky_res app.vendor_capacity_reservations;
  v_good_rate app.vendor_rate_versions;
  v_risky_rate app.vendor_rate_versions;
  v_market_rate app.vendor_rate_versions;
  v_window_start timestamptz := date_trunc('day', now()) - interval '30 days';
  v_window_end timestamptz := date_trunc('day', now()) + interval '30 days';
  v_kpi_def app.vendor_kpi_definitions;
  v_request app.sourcing_requests;
  v_candidate_good app.sourcing_candidates;
  v_candidate_risky app.sourcing_candidates;
  v_rfq app.rfqs;
  v_inv_good app.rfq_invitations;
  v_inv_risky app.rfq_invitations;
  v_comparison app.vendor_comparisons;
  v_offer_row app.vendor_comparison_offers;
  v_po_issued app.purchase_orders;
  v_request2 app.sourcing_requests;
  v_candidate2 app.sourcing_candidates;
  v_rfq2 app.rfqs;
  v_inv2 app.rfq_invitations;
  v_comparison2 app.vendor_comparisons;
  v_offer_row2 app.vendor_comparison_offers;
  v_po_cancelled app.purchase_orders;
begin
  v_good := app.create_vendor_profile_draft(v_tenant1, 'PT Good Vendor', 'GOODPD', 'PT', 'REG-PDASH-GOOD', 'logistics', 30, 'staff_created', 'idem-pdash-vendor-good', v_admin1, 'admin');
  perform app.add_vendor_contact(v_good.master_record_id, 'Good Ops', 'Ops', 'ops@goodpd.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_good.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_good.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_good.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_good from app.vendor_profiles where master_record_id = v_good.master_record_id;
  v_good := app.submit_vendor_profile_for_review(v_good.master_record_id, v_good.record_version, v_admin1, 'admin');
  v_good := app.decide_vendor_profile_review(v_good.master_record_id, v_good.record_version, 'approve', null, v_admin1, 'admin');
  v_good := app.activate_vendor_profile(v_good.master_record_id, v_good.record_version, v_admin1, 'admin');

  v_risky := app.create_vendor_profile_draft(v_tenant1, 'PT Risky Vendor', 'RISKPD', 'PT', 'REG-PDASH-RISKY', 'logistics', 30, 'staff_created', 'idem-pdash-vendor-risky', v_admin1, 'admin');
  perform app.add_vendor_contact(v_risky.master_record_id, 'Risky Ops', 'Ops', 'ops@riskpd.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_risky.master_record_id, 'legal', 'Jl. Sudirman 2', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_risky.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_risky.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_risky from app.vendor_profiles where master_record_id = v_risky.master_record_id;
  v_risky := app.submit_vendor_profile_for_review(v_risky.master_record_id, v_risky.record_version, v_admin1, 'admin');
  v_risky := app.decide_vendor_profile_review(v_risky.master_record_id, v_risky.record_version, 'approve', null, v_admin1, 'admin');
  v_risky := app.activate_vendor_profile(v_risky.master_record_id, v_risky.record_version, v_admin1, 'admin');

  -- New vendor: left in 'draft' -- zero downstream evidence anywhere. Proves every
  -- summary/list function tolerates a vendor with nothing to aggregate, never crashing.
  v_new := app.create_vendor_profile_draft(v_tenant1, 'PT New Vendor', 'NEWPD', 'PT', 'REG-PDASH-NEW', 'logistics', 30, 'staff_created', 'idem-pdash-vendor-new', v_admin1, 'admin');

  v_market := app.create_vendor_profile_draft(v_tenant1, 'PT Market Vendor', 'MKTPD', 'PT', 'REG-PDASH-MKT', 'logistics', 30, 'staff_created', 'idem-pdash-vendor-mkt', v_admin1, 'admin');
  perform app.add_vendor_contact(v_market.master_record_id, 'Market Ops', 'Ops', 'ops@mktpd.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_market.master_record_id, 'legal', 'Jl. Sudirman 4', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_market.master_record_id, 'ocean_freight', v_admin1, 'admin');
  select * into v_market from app.vendor_profiles where master_record_id = v_market.master_record_id;
  v_market := app.submit_vendor_profile_for_review(v_market.master_record_id, v_market.record_version, v_admin1, 'admin');
  v_market := app.decide_vendor_profile_review(v_market.master_record_id, v_market.record_version, 'approve', null, v_admin1, 'admin');
  v_market := app.activate_vendor_profile(v_market.master_record_id, v_market.record_version, v_admin1, 'admin');

  v_good_contract := app.create_vendor_contract_draft(v_tenant1, v_good.master_record_id, 'framework', '2026-01-01'::date, null, null, 30, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-pdash-contract-good', v_admin1, 'admin');
  v_good_contract := app.submit_vendor_contract_for_approval(v_good_contract.id, v_good_contract.record_version, 'idem-pdash-contract-good-submit', v_admin1, 'admin');
  v_good_contract := app.activate_vendor_contract(v_good_contract.id, v_good_contract.record_version, v_admin1, 'admin');

  -- Risky's own contract is FIXED-TERM and expiring within 30 days of "now" -- real
  -- evidence for group 5's own contract expiring_soon_count.
  v_risky_contract := app.create_vendor_contract_draft(v_tenant1, v_risky.master_record_id, 'fixed_term', (current_date - 300), (current_date + 10), null, 30, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-pdash-contract-risky', v_admin1, 'admin');
  v_risky_contract := app.submit_vendor_contract_for_approval(v_risky_contract.id, v_risky_contract.record_version, 'idem-pdash-contract-risky-submit', v_admin1, 'admin');
  v_risky_contract := app.activate_vendor_contract(v_risky_contract.id, v_risky_contract.record_version, v_admin1, 'admin');

  v_good_offer := app.create_vendor_capacity_offer_draft(v_tenant1, v_good.master_record_id, v_good_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null, 100, 'teu', now() - interval '5 days', now() + interval '30 days', 'idem-pdash-offer-good', v_admin1, 'admin');
  v_good_offer := app.publish_vendor_capacity_offer(v_good_offer.id, v_good_offer.record_version, v_admin1, 'admin');
  v_good_res := app.reserve_vendor_capacity(v_good_offer.id, 10, now(), now() + interval '3 hours', 'manual', null, 'idem-pdash-good-res', v_admin1, 'admin');
  v_good_res := app.accept_vendor_capacity_reservation(v_good_res.id, v_good_res.record_version, v_admin1, 'admin');

  v_risky_offer := app.create_vendor_capacity_offer_draft(v_tenant1, v_risky.master_record_id, v_risky_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null, 100, 'teu', now() - interval '5 days', now() + interval '30 days', 'idem-pdash-offer-risky', v_admin1, 'admin');
  v_risky_offer := app.publish_vendor_capacity_offer(v_risky_offer.id, v_risky_offer.record_version, v_admin1, 'admin');
  v_risky_res := app.reserve_vendor_capacity(v_risky_offer.id, 10, now() + interval '1 hour', now() + interval '4 hours', 'manual', null, 'idem-pdash-risky-res', v_admin1, 'admin');
  v_risky_res := app.decline_vendor_capacity_reservation(v_risky_res.id, v_risky_res.record_version, 'capacity withdrawn', v_admin1, 'admin');

  -- Rates: Good's own rate covers the FULL [window_start, window_end) -- rate_validity
  -- 100%. Risky's own rate covers only the first 18 of 60 window days (effective_to
  -- already passed relative to "now") -- rate_validity 30%, and group 2's own validity
  -- bucket correctly reports it as 'expired' (effective_to <= now()). Market's own
  -- pricier rate on the identical lane gives rate_competitiveness a real, non-trivial
  -- market of size 2 for Good's own rate to rank against.
  v_good_rate := app.create_rate_version(v_tenant1, 'VENDOR-PDASH-GOOD', 'PT Good Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, v_window_start - interval '10 days', null, null, v_admin1, 'admin', v_good.master_record_id);
  perform app.approve_rate_version(v_good_rate.id, v_good_rate.record_version, v_admin1, 'admin');
  v_risky_rate := app.create_rate_version(v_tenant1, 'VENDOR-PDASH-RISKY', 'PT Risky Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', null, null, null, null, 'IDR', 9000000, null, '[]'::jsonb, v_window_start, v_window_start + interval '18 days', null, v_admin1, 'admin', v_risky.master_record_id);
  perform app.approve_rate_version(v_risky_rate.id, v_risky_rate.record_version, v_admin1, 'admin');
  v_market_rate := app.create_rate_version(v_tenant1, 'VENDOR-PDASH-MKT', 'PT Market Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', null, null, null, null, 'IDR', 12000000, null, '[]'::jsonb, v_window_start - interval '10 days', null, null, v_admin1, 'admin', v_market.master_record_id);
  perform app.approve_rate_version(v_market_rate.id, v_market_rate.record_version, v_admin1, 'admin');

  -- One KPI definition (rate_validity), published, calculated and scorecard-published
  -- for Good (100% -> normalized 100 -> band excellent) and Risky (30% -> normalized
  -- 37.5 -> band poor) -- group 6's own real, reconcilable evidence.
  v_kpi_def := app.create_vendor_kpi_definition_draft(v_tenant1, 'rate_validity', 'Rate Validity', null, 60, 1, 80, 'gte', 100, 'percent', null, null, 2, true, null, 'idem-pdash-kpidef-1', v_admin1, 'admin');
  v_kpi_def := app.publish_vendor_kpi_definition(v_kpi_def.id, v_kpi_def.record_version, v_admin1, 'admin');
  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_good.master_record_id, v_window_start, v_window_end, 'manual', 'idem-pdash-calc-good', v_admin1, 'admin');
  perform app.publish_vendor_kpi_scorecard(v_tenant1, v_good.master_record_id, v_window_start, v_window_end, 'idem-pdash-scorecard-good', v_admin1, 'admin');
  perform app.calculate_vendor_kpi_metrics(v_tenant1, v_risky.master_record_id, v_window_start, v_window_end, 'manual', 'idem-pdash-calc-risky', v_admin1, 'admin');
  perform app.publish_vendor_kpi_scorecard(v_tenant1, v_risky.master_record_id, v_window_start, v_window_end, 'idem-pdash-scorecard-risky', v_admin1, 'admin');

  -- Sourcing -> RFQ -> comparison -> PO #1 (Good responds, Risky invited but never
  -- responds -- real, natural response_rate < 100% and a real 'no_response' invitation
  -- once closed). PO issued for Good.
  v_request := app.create_proactive_sourcing_request(v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days', 'IDR', 50000000, v_admin1, now() + interval '20 days', 'idem-pdash-sourcing-1', v_admin1, 'admin');
  v_request := app.submit_sourcing_request(v_request.id, v_admin1, 'admin', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');
  select * into v_candidate_good from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_good.master_record_id;
  v_candidate_good := app.shortlist_sourcing_candidate(v_candidate_good.id, true, 'fit', v_admin1, 'admin', v_candidate_good.record_version);
  select * into v_candidate_risky from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_risky.master_record_id;
  v_candidate_risky := app.shortlist_sourcing_candidate(v_candidate_risky.id, true, 'fit', v_admin1, 'admin', v_candidate_risky.record_version);
  v_request := app.submit_sourcing_shortlist(v_request.id, v_admin1, 'admin', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_admin1, 'idem-pdash-rfq-1', v_admin1, 'admin');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_admin1, 'admin');
  select * into v_inv_good from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_good.master_record_id;
  select * into v_inv_risky from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_risky.master_record_id;
  -- Good responds exactly 4 hours after its own invited_at -- a deterministic,
  -- non-wall-clock-dependent cycle time for group 3's own reconciliation.
  perform app.submit_rfq_response(v_inv_good.id, 'IDR', 10000000, now() + interval '30 days', 10, '{}'::jsonb, 'offline', null, v_inv_good.invited_at + interval '4 hours', true, null, null, 'idem-pdash-resp-good', v_admin1, 'admin');
  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_admin1, 'admin');

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq.id, 'IDR', null, null, null, null, 'idem-pdash-cmp-1', v_admin1, 'admin');
  select * into v_offer_row from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_good.master_record_id;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_offer_row.id, null, v_comparison.record_version, v_admin1, 'admin');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_offer_row.id, null, v_comparison.record_version, v_admin1, 'admin');
  v_po_issued := app.draft_purchase_order_from_selection(v_tenant1, v_comparison.id, 'idem-pdash-po-1', v_admin1, 'admin', null, 30, '2026-09-01', null, null, 'FOB Jakarta', 'pdash PO fixture (issued)');
  v_po_issued := app.submit_purchase_order_for_approval(v_po_issued.id, v_po_issued.record_version, v_admin1, 'admin');
  v_po_issued := app.issue_purchase_order(v_po_issued.id, v_po_issued.record_version, v_admin1, 'admin');

  -- A second, independent sourcing->RFQ->comparison->PO pipeline for Risky, issued then
  -- cancelled -- gives group 5's own PO summary a second, distinct status/currency
  -- combination to reconcile against.
  v_request2 := app.create_proactive_sourcing_request(v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days', 'IDR', 50000000, v_admin1, now() + interval '20 days', 'idem-pdash-sourcing-2', v_admin1, 'admin');
  v_request2 := app.submit_sourcing_request(v_request2.id, v_admin1, 'admin', v_request2.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request2.id, v_admin1, 'admin');
  select * into v_candidate2 from app.sourcing_candidates where sourcing_request_id = v_request2.id and vendor_master_id = v_risky.master_record_id;
  v_candidate2 := app.shortlist_sourcing_candidate(v_candidate2.id, true, 'fit', v_admin1, 'admin', v_candidate2.record_version);
  v_request2 := app.submit_sourcing_shortlist(v_request2.id, v_admin1, 'admin', v_request2.record_version);
  v_rfq2 := app.draft_rfq_from_sourcing(v_tenant1, v_request2.id, v_admin1, 'idem-pdash-rfq-2', v_admin1, 'admin');
  v_rfq2 := app.issue_rfq(v_rfq2.id, now() + interval '5 days', v_rfq2.record_version, v_admin1, 'admin');
  select * into v_inv2 from app.rfq_invitations where rfq_id = v_rfq2.id and vendor_master_id = v_risky.master_record_id;
  perform app.submit_rfq_response(v_inv2.id, 'IDR', 9500000, now() + interval '30 days', 10, '{}'::jsonb, 'offline', null, v_inv2.invited_at + interval '10 hours', true, null, null, 'idem-pdash-resp-risky', v_admin1, 'admin');
  v_rfq2 := app.close_rfq_for_comparison(v_rfq2.id, v_rfq2.record_version, v_admin1, 'admin');
  v_comparison2 := app.create_vendor_comparison(v_tenant1, v_rfq2.id, 'IDR', null, null, null, null, 'idem-pdash-cmp-2', v_admin1, 'admin');
  select * into v_offer_row2 from app.vendor_comparison_offers where comparison_id = v_comparison2.id and vendor_master_id = v_risky.master_record_id;
  v_comparison2 := app.recommend_vendor_comparison_offer(v_comparison2.id, v_offer_row2.id, null, v_comparison2.record_version, v_admin1, 'admin');
  v_comparison2 := app.submit_vendor_comparison_for_approval(v_comparison2.id, v_offer_row2.id, null, v_comparison2.record_version, v_admin1, 'admin');
  v_po_cancelled := app.draft_purchase_order_from_selection(v_tenant1, v_comparison2.id, 'idem-pdash-po-2', v_admin1, 'admin', null, 30, '2026-09-15', null, null, 'FOB Jakarta', 'pdash PO fixture (cancelled)');
  v_po_cancelled := app.submit_purchase_order_for_approval(v_po_cancelled.id, v_po_cancelled.record_version, v_admin1, 'admin');
  v_po_cancelled := app.issue_purchase_order(v_po_cancelled.id, v_po_cancelled.record_version, v_admin1, 'admin');
  v_po_cancelled := app.cancel_purchase_order(v_po_cancelled.id, v_po_cancelled.record_version, 'no longer needed', v_admin1, 'admin');
end $$;

\echo '>> setup: minimal real CRM-through-shipment pipeline (mirrors procurement-vendor-performance.sql''s own identical chain) producing one job order with two real shipment orders, then a real assignment-invitation proposal per vendor -- Good accepted, Risky declined -- group 4-B''s own real, reconcilable evidence'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000266101';
  v_good_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Good Vendor');
  v_risky_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Risky Vendor');
  v_good_contract_id uuid := (select id from app.vendor_contracts where tenant_id = v_tenant1 and vendor_master_id = v_good_master and status = 'active');
  v_risky_contract_id uuid := (select id from app.vendor_contracts where tenant_id = v_tenant1 and vendor_master_id = v_risky_master and status = 'active');
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_internal_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_ship_good app.shipment_orders;
  v_ship_risky app.shipment_orders;
  v_inv_good app.vendor_assignment_invitations;
  v_inv_risky app.vendor_assignment_invitations;
begin
  perform app.capture_lead(v_tenant1, 'manual', null, 'Pdash Test Co', 'Jane Pdash', 'jane@pdashtest.test', '0811', v_admin1, null, v_admin1, 'tester');
  select * into v_lead from app.leads where email = 'jane@pdashtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_admin1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Pdash Test Co', 'PTC', '11.111.111.2-111.000', jsonb_build_object('line1', 'Jl. Rasuna Said 2', 'city', 'Jakarta', 'country', 'ID'), v_admin1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Jane Pdash Ops', 'Procurement Lead', 'jane@pdashtest.test', '0811', v_admin1, null, v_admin1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_admin1, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Pdash test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_admin1, null, v_admin1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_admin1, 'tester');
  select * into v_internal_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-PDASH-CRM', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_internal_rate.id, v_internal_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_internal_rate.id, false, null, null, null, v_admin1, 'tester');
  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_admin1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_admin1, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_admin1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_admin1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight pdash lane', v_calc_id, 1, 15000000, 0, 0, v_admin1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_admin1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_admin1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Pdash Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_admin1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_admin1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_admin1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_admin1, 'rep');

  select * into v_ship_good from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-pdash-ship-good', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '2 hours', now() + interval '5 hours', null, null, null, null, null, null, 'pdash good-vendor shipment', v_admin1, 'rep'
  );
  select * into v_ship_risky from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-pdash-ship-risky', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '3 hours', now() + interval '6 hours', null, null, null, null, null, null, 'pdash risky-vendor shipment', v_admin1, 'rep'
  );

  v_inv_good := app.propose_vendor_assignment_invitation(v_tenant1, v_ship_good.id, v_good_master, v_good_contract_id, null, null, null, now() + interval '2 days', 'idem-pdash-assign-good', v_admin1, 'admin');
  v_inv_good := app.accept_vendor_assignment_invitation(v_inv_good.id, v_inv_good.record_version, v_admin1, 'admin');

  v_inv_risky := app.propose_vendor_assignment_invitation(v_tenant1, v_ship_risky.id, v_risky_master, v_risky_contract_id, null, null, null, now() + interval '2 days', 'idem-pdash-assign-risky', v_admin1, 'admin');
  v_inv_risky := app.decline_vendor_assignment_invitation(v_inv_risky.id, v_inv_risky.record_version, 'temporarily overbooked', v_admin1, 'admin');
end $$;

\echo '>> setup: compliance status snapshot (Good=fully verified, no hold; Risky=one expired requirement with eligibility_hold=true, one expiring_soon) -- direct inserts (disclosed at the top of this file), deliberately sequenced AFTER every sourcing/RFQ/assignment eligibility check above so Risky''s own compliance hold never interferes with an eligibility evaluation that already ran and already succeeded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_good_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Good Vendor');
  v_risky_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Risky Vendor');
begin
  insert into app.vendor_compliance_status (tenant_id, vendor_master_record_id, requirement_family_id, status, eligibility_hold, computed_by) values
    (v_tenant1, v_good_master, gen_random_uuid(), 'verified', false, 'tester');
  insert into app.vendor_compliance_status (tenant_id, vendor_master_record_id, requirement_family_id, status, eligibility_hold, computed_by) values
    (v_tenant1, v_risky_master, gen_random_uuid(), 'expired', true, 'tester'),
    (v_tenant1, v_risky_master, gen_random_uuid(), 'expiring_soon', false, 'tester');
end $$;

-- ===========================================================================
-- Group 1 -- vendor risk/compliance-expiry.
-- ===========================================================================

\echo '>> get_procurement_dashboard_vendor_risk_summary: reconciles against an independent query; outsider/cross-tenant denied; permission check runs before any row is disclosed (C-05)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pdash2');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000266105';
  v_admin2 uuid := '00000000-0000-0000-0000-000000266201';
  v_expected_active_count bigint;
  v_actual_active_count bigint;
  v_expected_hold_count bigint;
  v_actual_hold_count bigint;
  v_failed boolean;
begin
  select count(distinct vp.master_record_id) into v_expected_active_count
  from app.vendor_profiles vp where vp.tenant_id = v_tenant1 and vp.lifecycle_status = 'active';

  select vendor_count into v_actual_active_count
  from app.get_procurement_dashboard_vendor_risk_summary(v_tenant1, v_staff1)
  where lifecycle_status = 'active';

  if v_actual_active_count is distinct from v_expected_active_count then
    raise exception 'assertion failed: vendor_risk_summary active vendor_count expected % got %', v_expected_active_count, v_actual_active_count;
  end if;

  select count(distinct vp.master_record_id) into v_expected_hold_count
  from app.vendor_profiles vp
  where vp.tenant_id = v_tenant1 and vp.lifecycle_status = 'active'
    and exists (select 1 from app.vendor_compliance_status vcs where vcs.vendor_master_record_id = vp.master_record_id and vcs.eligibility_hold);

  select compliance_hold_count into v_actual_hold_count
  from app.get_procurement_dashboard_vendor_risk_summary(v_tenant1, v_staff1)
  where lifecycle_status = 'active';

  if v_actual_hold_count is distinct from v_expected_hold_count then
    raise exception 'assertion failed: vendor_risk_summary compliance_hold_count expected % got %', v_expected_hold_count, v_actual_hold_count;
  end if;
  if v_expected_hold_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 active vendor on compliance hold (Risky), got %', v_expected_hold_count;
  end if;

  begin
    perform app.get_procurement_dashboard_vendor_risk_summary(v_tenant1, v_outsider1);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for outsider, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected outsider to be denied'; end if;

  begin
    perform app.get_procurement_dashboard_vendor_risk_summary(v_tenant1, v_admin2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for cross-tenant admin2, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected tenant2''s admin to be denied against tenant1''s own tenant_id'; end if;
end $$;

\echo '>> list_procurement_vendor_risk_dashboard_rows: reconciles row-for-row against an independent query; filters (lifecycle_status/compliance_hold_only/band/search) narrow correctly; cursor pagination is stable and exhaustive; identical field policy (no field is masked -- none is masked by any PRC-251/264 RPC either)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_good_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Good Vendor');
  v_risky_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Risky Vendor');
  v_row record;
  v_page1_count integer := 0;
  v_page2_count integer := 0;
  v_cursor timestamptz;
  v_last_id uuid;
  v_total_direct integer;
  v_total_paginated integer := 0;
  v_seen uuid[] := array[]::uuid[];
begin
  -- Reconciliation: Good has no compliance hold and 0 expiring/expired rows; Risky has
  -- a hold, 1 expired, 1 expiring_soon -- matches the direct app.vendor_compliance_status
  -- rows inserted above exactly.
  select * into v_row from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, null, null, 100, null) where vendor_master_id = v_good_master;
  if v_row.compliance_hold is distinct from false or v_row.compliance_expiring_soon_count <> 0 or v_row.compliance_expired_count <> 0 then
    raise exception 'assertion failed: Good vendor row expected no hold/no expiry, got hold=% expiring=% expired=%', v_row.compliance_hold, v_row.compliance_expiring_soon_count, v_row.compliance_expired_count;
  end if;

  select * into v_row from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, null, null, 100, null) where vendor_master_id = v_risky_master;
  if v_row.compliance_hold is distinct from true or v_row.compliance_expiring_soon_count <> 1 or v_row.compliance_expired_count <> 1 then
    raise exception 'assertion failed: Risky vendor row expected hold=true/expiring=1/expired=1, got hold=% expiring=% expired=%', v_row.compliance_hold, v_row.compliance_expiring_soon_count, v_row.compliance_expired_count;
  end if;
  if v_row.scorecard_band <> 'poor' then
    raise exception 'assertion failed: Risky vendor scorecard_band expected poor, got %', v_row.scorecard_band;
  end if;

  -- Filter: compliance_hold_only=true returns exactly Risky.
  if (select count(*) from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, true, null, null, 100, null)) <> 1 then
    raise exception 'assertion failed: compliance_hold_only filter expected exactly 1 row';
  end if;

  -- Filter: band='excellent' returns exactly Good.
  if not exists (select 1 from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, 'excellent', null, 100, null) where vendor_master_id = v_good_master) then
    raise exception 'assertion failed: band=excellent filter did not return Good vendor';
  end if;
  if exists (select 1 from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, 'excellent', null, 100, null) where vendor_master_id = v_risky_master) then
    raise exception 'assertion failed: band=excellent filter incorrectly returned Risky vendor';
  end if;

  -- Filter: search by legal_name substring.
  if (select count(*) from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, null, 'Risky', 100, null)) <> 1 then
    raise exception 'assertion failed: search=Risky expected exactly 1 row';
  end if;

  -- Cursor pagination: page size 1, walk every page, confirm the union equals the
  -- unpaginated full result with zero duplicates and zero omissions. All four vendor
  -- rows were created inside the SAME setup transaction, so app.vendor_profiles.
  -- created_at (default now()) is otherwise IDENTICAL across all of them (now() is
  -- frozen for the duration of one transaction in Postgres) -- spread them out here,
  -- test-only, so the single-column created_at cursor this function shares with every
  -- sibling PRC-25x/26x list RPC (e.g. app.list_vendor_contracts) has genuinely
  -- distinct values to walk. This is a real, disclosed, already-repository-wide
  -- simplification (no tie-breaker column) this checkpoint inherits, not introduces.
  update app.vendor_profiles set created_at = app.vendor_profiles.created_at - (ranked.rn * interval '1 minute')
  from (select master_record_id, row_number() over (order by master_record_id) as rn from app.vendor_profiles where tenant_id = v_tenant1) ranked
  where app.vendor_profiles.master_record_id = ranked.master_record_id;

  select count(*) into v_total_direct from app.vendor_profiles where tenant_id = v_tenant1;

  v_cursor := null;
  loop
    v_page1_count := 0;
    for v_row in select * from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, null, null, 1, v_cursor) loop
      v_page1_count := v_page1_count + 1;
      if v_row.vendor_master_id = any (v_seen) then
        raise exception 'assertion failed: cursor pagination returned duplicate vendor %', v_row.vendor_master_id;
      end if;
      v_seen := v_seen || v_row.vendor_master_id;
      v_cursor := v_row.created_at;
      v_total_paginated := v_total_paginated + 1;
    end loop;
    exit when v_page1_count = 0;
  end loop;

  if v_total_paginated <> v_total_direct then
    raise exception 'assertion failed: cursor-paginated walk returned % rows, expected % (every vendor in the tenant)', v_total_paginated, v_total_direct;
  end if;

  -- limit is clamped to 100 (least(coalesce(p_limit,25),100)).
  if (select count(*) from app.list_procurement_vendor_risk_dashboard_rows(v_tenant1, v_staff1, null, null, null, null, 999, null)) > 100 then
    raise exception 'assertion failed: p_limit=999 was not clamped to 100';
  end if;
end $$;

-- ===========================================================================
-- Group 2 -- rate validity/competitiveness.
-- ===========================================================================

\echo '>> get_procurement_dashboard_rate_validity_summary: reconciles against an independent bucket computation -- Good is active (open-ended), Risky is expired (effective_to already past "now")'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_active_count integer;
  v_expired_count integer;
begin
  select rate_count into v_active_count from app.get_procurement_dashboard_rate_validity_summary(v_tenant1, v_staff1) where currency = 'IDR' and validity_bucket = 'active';
  select rate_count into v_expired_count from app.get_procurement_dashboard_rate_validity_summary(v_tenant1, v_staff1) where currency = 'IDR' and validity_bucket = 'expired';

  -- Good's rate, Market's rate, and the internal CRM-pipeline rate (VENDOR-PDASH-CRM,
  -- created by the assignment-invitation fixture above) are all open-ended -> 'active';
  -- Risky's rate (effective_to already past) is 'expired'.
  if v_active_count <> 3 then
    raise exception 'assertion failed: expected 3 active IDR rate versions (Good + Market + internal CRM rate), got %', v_active_count;
  end if;
  if v_expired_count <> 1 then
    raise exception 'assertion failed: expected 1 expired IDR rate version (Risky), got %', v_expired_count;
  end if;

  -- Cross-check against a fully independent, from-scratch bucket computation.
  if v_active_count <> (
    select count(*) from app.vendor_rate_versions rv
    where rv.tenant_id = v_tenant1 and rv.currency = 'IDR' and rv.approval_status = 'approved'
      and (rv.effective_to is null or rv.effective_to > now() + interval '30 days')
  ) then
    raise exception 'assertion failed: active bucket does not reconcile against an independent query';
  end if;
end $$;

\echo '>> get_procurement_dashboard_rate_competitiveness_summary: reconciles vendor_count/avg_score against a direct read of app.vendor_kpi_metric_values -- never recomputes the formula'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_total_vendor_count bigint;
  v_expected_total bigint;
begin
  select count(*) into v_expected_total from app.vendor_profiles where tenant_id = v_tenant1;
  select sum(vendor_count) into v_total_vendor_count from app.get_procurement_dashboard_rate_competitiveness_summary(v_tenant1, v_staff1);
  if v_total_vendor_count is distinct from v_expected_total then
    raise exception 'assertion failed: competitiveness summary total vendor_count expected % got % (every vendor must appear in exactly one bucket, including not_computed)', v_expected_total, v_total_vendor_count;
  end if;
  -- New/Market vendors carry no rate_competitiveness KPI value at all -- they must land
  -- in not_computed, never silently dropped from the total above.
  if not exists (select 1 from app.get_procurement_dashboard_rate_competitiveness_summary(v_tenant1, v_staff1) where competitiveness_band = 'not_computed') then
    raise exception 'assertion failed: expected a not_computed bucket for vendors with no rate_competitiveness KPI value';
  end if;
end $$;

-- ===========================================================================
-- Group 3 -- RFQ response rate / cycle time.
-- ===========================================================================

\echo '>> get_procurement_dashboard_rfq_cycle_summary: reconciles invitation/response counts and response_rate_pct against an independent query; avg_cycle_hours matches the real invited_at->received_at delta'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_closed_row record;
  v_expected_invitations bigint;
  v_expected_responses bigint;
  v_expected_avg_hours numeric;
begin
  select
    count(inv.id), count(inv.id) filter (where inv.status = 'responded'),
    round(avg(extract(epoch from (resp.received_at - inv.invited_at)) / 3600.0) filter (where resp.received_at is not null), 2)
  into v_expected_invitations, v_expected_responses, v_expected_avg_hours
  from app.rfqs r
  join app.rfq_invitations inv on inv.rfq_id = r.id
  left join lateral (select rr.received_at from app.rfq_responses rr where rr.rfq_invitation_id = inv.id order by rr.version desc limit 1) resp on true
  where r.tenant_id = v_tenant1 and r.status = 'closed';

  select * into v_closed_row from app.get_procurement_dashboard_rfq_cycle_summary(v_tenant1, v_staff1) where rfq_status = 'closed';

  if v_closed_row.invitation_count is distinct from v_expected_invitations then
    raise exception 'assertion failed: rfq_cycle invitation_count expected % got %', v_expected_invitations, v_closed_row.invitation_count;
  end if;
  if v_closed_row.response_count is distinct from v_expected_responses then
    raise exception 'assertion failed: rfq_cycle response_count expected % got %', v_expected_responses, v_closed_row.response_count;
  end if;
  if v_closed_row.avg_cycle_hours is distinct from v_expected_avg_hours then
    raise exception 'assertion failed: rfq_cycle avg_cycle_hours expected % got %', v_expected_avg_hours, v_closed_row.avg_cycle_hours;
  end if;
  -- RFQ 1 invites both Good and Risky (Good responds, Risky never does -> no_response
  -- once closed); RFQ 2 invites Risky alone (responds) -- 3 invitations total, 2
  -- responses -- response_rate_pct = round(100 * 2/3, 2) = 66.67.
  if v_expected_invitations <> 3 or v_expected_responses <> 2 or v_closed_row.response_rate_pct <> 66.67 then
    raise exception 'assertion failed: expected 3 invitations / 2 responses / 66.67%% rate, got invitations=% responses=% rate=%', v_expected_invitations, v_expected_responses, v_closed_row.response_rate_pct;
  end if;
end $$;

-- ===========================================================================
-- Group 4 -- capacity / acceptance.
-- ===========================================================================

\echo '>> get_procurement_dashboard_capacity_reservation_summary / get_procurement_dashboard_assignment_acceptance_summary: reconcile against independent queries -- one accepted (Good), one declined (Risky) in each'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_accepted_res bigint;
  v_declined_res bigint;
  v_accepted_inv bigint;
  v_declined_inv bigint;
  v_expected_avg_hours numeric;
  v_actual_avg_hours numeric;
begin
  select reservation_count into v_accepted_res from app.get_procurement_dashboard_capacity_reservation_summary(v_tenant1, v_staff1, null, null) where status = 'accepted';
  select reservation_count into v_declined_res from app.get_procurement_dashboard_capacity_reservation_summary(v_tenant1, v_staff1, null, null) where status = 'declined';
  if v_accepted_res <> 1 or v_declined_res <> 1 then
    raise exception 'assertion failed: expected 1 accepted + 1 declined reservation, got accepted=% declined=%', v_accepted_res, v_declined_res;
  end if;

  select invitation_count into v_accepted_inv from app.get_procurement_dashboard_assignment_acceptance_summary(v_tenant1, v_staff1, null, null) where status = 'accepted';
  select invitation_count into v_declined_inv from app.get_procurement_dashboard_assignment_acceptance_summary(v_tenant1, v_staff1, null, null) where status = 'declined';
  if v_accepted_inv <> 1 or v_declined_inv <> 1 then
    raise exception 'assertion failed: expected 1 accepted + 1 declined assignment invitation, got accepted=% declined=%', v_accepted_inv, v_declined_inv;
  end if;

  select round(avg(extract(epoch from (responded_at - created_at)) / 3600.0), 2) into v_expected_avg_hours
  from app.vendor_assignment_invitations where tenant_id = v_tenant1 and status = 'accepted';
  select avg_response_hours into v_actual_avg_hours from app.get_procurement_dashboard_assignment_acceptance_summary(v_tenant1, v_staff1, null, null) where status = 'accepted';
  if v_actual_avg_hours is distinct from v_expected_avg_hours then
    raise exception 'assertion failed: assignment_acceptance avg_response_hours (accepted) expected % got %', v_expected_avg_hours, v_actual_avg_hours;
  end if;
end $$;

-- ===========================================================================
-- Group 5 -- PO / contract. committed_amount is cost-masked (PRC:View cost).
-- ===========================================================================

\echo '>> get_procurement_dashboard_po_summary: reconciles po_count/committed_amount against an independent query; a caller WITHOUT PRC:View cost sees committed_amount=null/cost_masked=true (never zero, never the real figure); a caller WITH it sees the real sum; both see the identical po_count'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000266104';
  v_expected_issued_count bigint;
  v_expected_issued_amount numeric;
  v_staff_row record;
  v_viewer_row record;
begin
  select count(*), sum(total_amount) into v_expected_issued_count, v_expected_issued_amount
  from app.purchase_orders where tenant_id = v_tenant1 and status = 'issued' and currency = 'IDR';

  select * into v_staff_row from app.get_procurement_dashboard_po_summary(v_tenant1, v_staff1) where status = 'issued' and currency = 'IDR';
  if v_staff_row.po_count is distinct from v_expected_issued_count then
    raise exception 'assertion failed: po_summary (staff) po_count expected % got %', v_expected_issued_count, v_staff_row.po_count;
  end if;
  if v_staff_row.committed_amount is distinct from v_expected_issued_amount or v_staff_row.cost_masked is distinct from false then
    raise exception 'assertion failed: po_summary (staff, holds PRC:View cost) expected real committed_amount=%/cost_masked=false, got amount=% masked=%', v_expected_issued_amount, v_staff_row.committed_amount, v_staff_row.cost_masked;
  end if;

  select * into v_viewer_row from app.get_procurement_dashboard_po_summary(v_tenant1, v_viewer1) where status = 'issued' and currency = 'IDR';
  if v_viewer_row.po_count is distinct from v_expected_issued_count then
    raise exception 'assertion failed: po_summary (viewer) po_count must be identical/never masked, expected % got %', v_expected_issued_count, v_viewer_row.po_count;
  end if;
  if v_viewer_row.committed_amount is not null or v_viewer_row.cost_masked is distinct from true then
    raise exception 'assertion failed: po_summary (viewer, lacks PRC:View cost) expected committed_amount=null/cost_masked=true, got amount=% masked=%', v_viewer_row.committed_amount, v_viewer_row.cost_masked;
  end if;

  -- Never a fabricated zero -- the masked amount is genuinely NULL, distinguishable
  -- from a real zero-value PO.
  if v_viewer_row.committed_amount = 0 then
    raise exception 'assertion failed: masked committed_amount must be NULL, never a fabricated zero';
  end if;

  -- Both statuses/currencies present: issued (Good) and cancelled (Risky).
  if not exists (select 1 from app.get_procurement_dashboard_po_summary(v_tenant1, v_staff1) where status = 'cancelled') then
    raise exception 'assertion failed: expected a cancelled PO row';
  end if;
end $$;

\echo '>> get_procurement_dashboard_contract_summary: reconciles contract_count/expiring_soon_count against an independent query; no cost-shaped field exists on app.vendor_contracts at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_expected_active bigint;
  v_expected_expiring bigint;
  v_actual_active bigint;
  v_actual_expiring bigint;
begin
  select count(*) into v_expected_active from app.vendor_contracts where tenant_id = v_tenant1 and status = 'active';
  select count(*) into v_expected_expiring from app.vendor_contracts where tenant_id = v_tenant1 and status = 'active' and effective_end is not null and effective_end between current_date and current_date + 30;

  select contract_count into v_actual_active from app.get_procurement_dashboard_contract_summary(v_tenant1, v_staff1) where status = 'active';
  select expiring_soon_count into v_actual_expiring from app.get_procurement_dashboard_contract_summary(v_tenant1, v_staff1) where status = 'active';

  if v_actual_active is distinct from v_expected_active then
    raise exception 'assertion failed: contract_summary contract_count expected % got %', v_expected_active, v_actual_active;
  end if;
  if v_actual_expiring is distinct from v_expected_expiring then
    raise exception 'assertion failed: contract_summary expiring_soon_count expected % got %', v_expected_expiring, v_actual_expiring;
  end if;
  -- Risky's own contract expires in 10 days -- must be counted.
  if v_expected_expiring < 1 then
    raise exception 'assertion failed: expected at least 1 expiring-soon contract (Risky), got %', v_expected_expiring;
  end if;
end $$;

-- ===========================================================================
-- Group 6 -- performance.
-- ===========================================================================

\echo '>> get_procurement_dashboard_performance_summary: reconciles band counts/avg_composite_score against a direct read of app.vendor_kpi_scorecards -- never a second scoring engine'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_expected_excellent bigint;
  v_actual_excellent bigint;
  v_expected_poor bigint;
  v_actual_poor bigint;
  v_expected_poor_avg numeric;
  v_actual_poor_avg numeric;
begin
  select count(*) into v_expected_excellent from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and is_current and status = 'published' and band = 'excellent';
  select count(*) into v_expected_poor from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and is_current and status = 'published' and band = 'poor';
  select round(avg(composite_score), 2) into v_expected_poor_avg from app.vendor_kpi_scorecards where tenant_id = v_tenant1 and is_current and status = 'published' and band = 'poor';

  select vendor_count into v_actual_excellent from app.get_procurement_dashboard_performance_summary(v_tenant1, v_staff1) where band = 'excellent';
  select vendor_count into v_actual_poor from app.get_procurement_dashboard_performance_summary(v_tenant1, v_staff1) where band = 'poor';
  select avg_composite_score into v_actual_poor_avg from app.get_procurement_dashboard_performance_summary(v_tenant1, v_staff1) where band = 'poor';

  if v_actual_excellent is distinct from v_expected_excellent or v_actual_excellent <> 1 then
    raise exception 'assertion failed: performance_summary excellent band expected %(=1) got %', v_expected_excellent, v_actual_excellent;
  end if;
  if v_actual_poor is distinct from v_expected_poor or v_actual_poor <> 1 then
    raise exception 'assertion failed: performance_summary poor band expected %(=1) got %', v_expected_poor, v_actual_poor;
  end if;
  if v_actual_poor_avg is distinct from v_expected_poor_avg then
    raise exception 'assertion failed: performance_summary poor avg_composite_score expected % got %', v_expected_poor_avg, v_actual_poor_avg;
  end if;

  -- New/Market vendors have no published scorecard at all -- correctly absent from
  -- this metric entirely (never a fabricated 'not_banded' zero-score row for them).
  if (select sum(vendor_count) from app.get_procurement_dashboard_performance_summary(v_tenant1, v_staff1)) <> 2 then
    raise exception 'assertion failed: performance_summary total vendor_count across all bands expected 2 (only Good+Risky have a published scorecard)';
  end if;
end $$;

-- ===========================================================================
-- Group 7 -- match variance/exception rate. Entirely reused from PRC-265 (design
-- note 2) -- a light smoke test only, never re-deriving PRC-265's own fixture/
-- correctness coverage (scripts/db-tests/procurement-vendor-invoice-matching.sql).
-- ===========================================================================

\echo '>> group 7 smoke test: app.get_vendor_bill_match_reconciliation_status (PRC-265, reused verbatim) is callable from this dashboard''s own context, PRC:View-gated, returns zero rows (no match case exists for pdash1) without error -- proves the catalog citation is a real, live function, not a stale reference'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000266105';
  v_row_count integer;
  v_failed boolean;
begin
  select count(*) into v_row_count from app.get_vendor_bill_match_reconciliation_status(v_tenant1, v_staff1);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero match-case rows for pdash1 (no vendor bill match fixture built by this checkpoint), got %', v_row_count;
  end if;

  begin
    perform app.get_vendor_bill_match_reconciliation_status(v_tenant1, v_outsider1);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for outsider, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected outsider to be denied on the reused reconciliation-status RPC too'; end if;
end $$;

-- ===========================================================================
-- Metric definition catalogue.
-- ===========================================================================

\echo '>> app.procurement_metric_definitions: eleven rows registered by this migration''s own seed, one is_current row per code, every group represented, required_action/additional_mask_action match what each RPC actually enforces'
do $$
declare
  v_count integer;
  v_group_count integer;
begin
  select count(*) into v_count from app.procurement_metric_definitions where is_current;
  if v_count <> 11 then
    raise exception 'assertion failed: expected exactly 11 current metric definitions, got %', v_count;
  end if;

  select count(distinct metric_group) into v_group_count from app.procurement_metric_definitions where is_current;
  if v_group_count <> 7 then
    raise exception 'assertion failed: expected all 7 required metric groups represented, got %', v_group_count;
  end if;

  if (select required_action from app.procurement_metric_definitions where code = 'purchase_order_pipeline_mix' and is_current) <> 'View'
    or (select additional_mask_action from app.procurement_metric_definitions where code = 'purchase_order_pipeline_mix' and is_current) <> 'View cost'
  then
    raise exception 'assertion failed: purchase_order_pipeline_mix catalogue row does not match app.get_procurement_dashboard_po_summary''s own real gate (PRC:View + PRC:View cost mask)';
  end if;

  if (select required_action from app.procurement_metric_definitions where code = 'vendor_bill_match_variance_exception_rate' and is_current) <> 'View'
    or (select additional_mask_action from app.procurement_metric_definitions where code = 'vendor_bill_match_variance_exception_rate' and is_current) <> 'View cost'
  then
    raise exception 'assertion failed: vendor_bill_match_variance_exception_rate catalogue row does not match app.get_vendor_bill_match_reconciliation_status''s own real gate';
  end if;

  -- No metric ever names 'View personal data' -- design note 1's own disclosed absence.
  if exists (select 1 from app.procurement_metric_definitions where is_current and (required_action = 'View personal data' or additional_mask_action = 'View personal data')) then
    raise exception 'assertion failed: no metric in this migration should reference PRC:View personal data (no personal-data field is read anywhere in this capability)';
  end if;
end $$;

\echo '>> app.register_procurement_metric_definition / app.retire_procurement_metric_definition: Supreme-only; idempotent-if-unchanged; a genuine change opens a real new version (supersede chain); C-13 -- a claimed actor is rejected unless the calling session really is that actor'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000000266999';
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_v1 app.procurement_metric_definitions;
  v_v1_again app.procurement_metric_definitions;
  v_v2 app.procurement_metric_definitions;
  v_failed boolean;
begin
  -- Non-Supreme actor denied.
  begin
    perform app.register_procurement_metric_definition('pdash_test_metric', 'performance', 'Test Metric', null, array['app.vendor_profiles'], array['lifecycle_status'], 'count', 'per tenant', 'live', 'View', null, 'noop', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for a non-Supreme actor, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a non-Supreme actor to be denied registering a metric definition'; end if;

  -- C-13: a genuine authenticated session (staff1) claiming to act as Supreme is
  -- rejected on IDENTITY grounds before authority is ever evaluated.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff1::text, 'role', 'authenticated')::text, true);
  begin
    perform app.register_procurement_metric_definition('pdash_test_metric', 'performance', 'Test Metric', null, array['app.vendor_profiles'], array['lifecycle_status'], 'count', 'per tenant', 'live', 'View', null, 'noop', v_supreme, 'supreme');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'actor_identity_mismatch%' then raise exception 'assertion failed: expected actor_identity_mismatch (C-13), got %', sqlerrm; end if;
  end;
  reset role;
  -- Explicitly clear the forged claim (not just the role) -- request.jwt.claims is a
  -- transaction-local GUC that would otherwise still resolve auth.uid() to staff1 for
  -- every subsequent call in this SAME do-block/transaction, breaking the real-Supreme
  -- calls immediately below.
  perform set_config('request.jwt.claims', '', true);
  if not v_failed then raise exception 'assertion failed: expected a staff1 session claiming to act as Supreme Admin to be rejected on identity grounds'; end if;

  -- Real Supreme Admin, first registration -> version 1.
  v_v1 := app.register_procurement_metric_definition('pdash_test_metric', 'performance', 'Test Metric', null, array['app.vendor_profiles'], array['lifecycle_status'], 'count', 'per tenant', 'live', 'View', null, 'noop', v_supreme, 'supreme');
  if v_v1.version_no <> 1 or not v_v1.is_current then
    raise exception 'assertion failed: expected version_no=1, is_current=true on first registration, got version_no=% is_current=%', v_v1.version_no, v_v1.is_current;
  end if;

  -- Identical re-registration -> idempotent, same row, no new version.
  v_v1_again := app.register_procurement_metric_definition('pdash_test_metric', 'performance', 'Test Metric', null, array['app.vendor_profiles'], array['lifecycle_status'], 'count', 'per tenant', 'live', 'View', null, 'noop', v_supreme, 'supreme');
  if v_v1_again.id <> v_v1.id or v_v1_again.version_no <> 1 then
    raise exception 'assertion failed: identical re-registration must return the SAME current row, not a new version -- got id=% version=%', v_v1_again.id, v_v1_again.version_no;
  end if;

  -- Genuine change (grain differs) -> a real new version, supersede chain intact.
  v_v2 := app.register_procurement_metric_definition('pdash_test_metric', 'performance', 'Test Metric', null, array['app.vendor_profiles'], array['lifecycle_status'], 'count', 'per tenant, revised grain', 'live', 'View', null, 'noop', v_supreme, 'supreme');
  if v_v2.version_no <> 2 or v_v2.supersedes_definition_id <> v_v1.id or not v_v2.is_current then
    raise exception 'assertion failed: a changed definition must open version 2 superseding version 1, got version_no=% supersedes=% is_current=%', v_v2.version_no, v_v2.supersedes_definition_id, v_v2.is_current;
  end if;
  if exists (select 1 from app.procurement_metric_definitions where id = v_v1.id and is_current) then
    raise exception 'assertion failed: version 1 must no longer be is_current once version 2 exists';
  end if;
  if (select count(*) from app.procurement_metric_definitions where code = 'pdash_test_metric') <> 2 then
    raise exception 'assertion failed: expected exactly 2 historical rows for pdash_test_metric';
  end if;

  -- Retire: Supreme-only, sets status=retired on the current row.
  begin
    perform app.retire_procurement_metric_definition('pdash_test_metric', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority retiring as a non-Supreme actor, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a non-Supreme actor to be denied retiring a metric definition'; end if;

  perform app.retire_procurement_metric_definition('pdash_test_metric', v_supreme, 'supreme');
  if (select status from app.procurement_metric_definitions where id = v_v2.id) <> 'retired' then
    raise exception 'assertion failed: expected pdash_test_metric''s current version to be retired';
  end if;
end $$;

\echo '>> app.procurement_metric_definitions: broadly readable to any authenticated session (non-sensitive platform metadata, mirrors app.report_types), never to anon'
do $$
declare
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_count integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff1::text, 'role', 'authenticated')::text, true);
  select count(*) into v_count from app.procurement_metric_definitions where is_current and status = 'active';
  reset role;
  if v_count <> 11 then
    raise exception 'assertion failed: expected authenticated to directly read exactly 11 current+active metric definitions (this suite''s own pdash_test_metric is current but retired, correctly excluded), got %', v_count;
  end if;

  set local role anon;
  begin
    perform count(*) from app.procurement_metric_definitions;
    raise exception 'assertion failed: expected anon to be denied direct select on app.procurement_metric_definitions';
  exception
    when insufficient_privilege then null;
  end;
  reset role;
end $$;

-- ===========================================================================
-- Saved views -- a user's OWN named filter/sort configuration (design note 5).
-- ===========================================================================

\echo '>> app.create_procurement_dashboard_saved_view: authority-gated; idempotency compares the FULL target tuple (C-01) -- a replay with the identical tuple returns the existing row, a replay with a DIFFERENT tuple under the SAME key is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000266105';
  v_view1 app.procurement_dashboard_saved_views;
  v_view1_replay app.procurement_dashboard_saved_views;
  v_failed boolean;
begin
  begin
    perform app.create_procurement_dashboard_saved_view(v_tenant1, 'vendor_risk_compliance', 'My hold vendors', 'quick filter', jsonb_build_object('complianceHoldOnly', true), '{}'::jsonb, 'idem-pdash-sv-outsider', v_outsider1, 'outsider');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for outsider, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected outsider to be denied creating a saved view'; end if;

  v_view1 := app.create_procurement_dashboard_saved_view(v_tenant1, 'vendor_risk_compliance', 'My hold vendors', 'quick filter', jsonb_build_object('complianceHoldOnly', true), '{}'::jsonb, 'idem-pdash-sv-1', v_staff1, 'staff');
  if v_view1.owner_auth_user_id <> v_staff1 or v_view1.name <> 'My hold vendors' then
    raise exception 'assertion failed: saved view not created with the expected owner/name';
  end if;

  -- Identical-tuple replay -> the SAME row, no duplicate.
  v_view1_replay := app.create_procurement_dashboard_saved_view(v_tenant1, 'vendor_risk_compliance', 'My hold vendors', 'quick filter', jsonb_build_object('complianceHoldOnly', true), '{}'::jsonb, 'idem-pdash-sv-1', v_staff1, 'staff');
  if v_view1_replay.id <> v_view1.id then
    raise exception 'assertion failed: identical-tuple replay must return the SAME saved view row, got a different id';
  end if;
  if (select count(*) from app.procurement_dashboard_saved_views where tenant_id = v_tenant1 and owner_auth_user_id = v_staff1 and idempotency_key = 'idem-pdash-sv-1') <> 1 then
    raise exception 'assertion failed: expected exactly 1 row for this idempotency key, replay must never create a duplicate';
  end if;

  -- C-01: SAME key, DIFFERENT target tuple (different name) -> rejected, never
  -- silently returns the wrong saved view or silently overwrites it.
  begin
    perform app.create_procurement_dashboard_saved_view(v_tenant1, 'vendor_risk_compliance', 'A totally different name', 'quick filter', jsonb_build_object('complianceHoldOnly', true), '{}'::jsonb, 'idem-pdash-sv-1', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a mismatched-tuple replay to be rejected, not silently accepted'; end if;
end $$;

\echo '>> app.update_procurement_dashboard_saved_view / app.delete_procurement_dashboard_saved_view: version-guarded (C-03, stale_version on a wrong expected_version); owner-only (staffb, a DIFFERENT user in the SAME tenant, cannot read/update/delete staff1''s own saved view -- not-found and not-owner fold into the identical error, C-05); cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_staff1b uuid := '00000000-0000-0000-0000-000000266103';
  v_admin2 uuid := '00000000-0000-0000-0000-000000266201';
  v_view app.procurement_dashboard_saved_views;
  v_updated app.procurement_dashboard_saved_views;
  v_failed boolean;
begin
  select * into v_view from app.procurement_dashboard_saved_views where tenant_id = v_tenant1 and owner_auth_user_id = v_staff1 and idempotency_key = 'idem-pdash-sv-1';

  -- Owner-isolation: staffb (same tenant, different user) cannot read/update/delete.
  begin
    perform app.get_procurement_dashboard_saved_view(v_view.id, v_staff1b);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'procurement_dashboard_saved_view_not_found%' then raise exception 'assertion failed: expected procurement_dashboard_saved_view_not_found for a non-owner get, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected staffb to be denied reading staff1''s own saved view'; end if;

  begin
    perform app.update_procurement_dashboard_saved_view(v_view.id, v_view.record_version, 'hijacked name', null, '{}'::jsonb, '{}'::jsonb, v_staff1b, 'staffb');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'procurement_dashboard_saved_view_not_found%' then raise exception 'assertion failed: expected procurement_dashboard_saved_view_not_found for a non-owner update, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected staffb to be denied updating staff1''s own saved view'; end if;

  -- Cross-tenant: tenant2's admin cannot read it either.
  begin
    perform app.get_procurement_dashboard_saved_view(v_view.id, v_admin2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'procurement_dashboard_saved_view_not_found%' then raise exception 'assertion failed: expected procurement_dashboard_saved_view_not_found for cross-tenant admin2, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected tenant2''s admin to be denied reading tenant1''s saved view'; end if;

  -- The real owner CAN update, with the CORRECT expected_version.
  v_updated := app.update_procurement_dashboard_saved_view(v_view.id, v_view.record_version, 'My hold vendors (renamed)', 'updated', jsonb_build_object('complianceHoldOnly', true, 'band', 'poor'), '{}'::jsonb, v_staff1, 'staff');
  if v_updated.name <> 'My hold vendors (renamed)' or v_updated.record_version <> v_view.record_version + 1 then
    raise exception 'assertion failed: update did not apply / did not bump record_version as expected';
  end if;

  -- C-03: stale expected_version is rejected, not silently overwritten.
  begin
    perform app.update_procurement_dashboard_saved_view(v_view.id, v_view.record_version, 'stale write', null, '{}'::jsonb, '{}'::jsonb, v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version%' then raise exception 'assertion failed: expected stale_version, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a stale expected_version update to be rejected'; end if;

  -- Delete: wrong version rejected (C-03), then real owner deletes successfully.
  begin
    perform app.delete_procurement_dashboard_saved_view(v_updated.id, v_updated.record_version + 99, v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version%' then raise exception 'assertion failed: expected stale_version on delete, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a stale expected_version delete to be rejected'; end if;

  perform app.delete_procurement_dashboard_saved_view(v_updated.id, v_updated.record_version, v_staff1, 'staff');
  if exists (select 1 from app.procurement_dashboard_saved_views where id = v_updated.id) then
    raise exception 'assertion failed: expected the saved view to be genuinely deleted';
  end if;
end $$;

\echo '>> app.list_procurement_dashboard_saved_views: always scoped to the CALLING actor''s own views only, even for another user in the same tenant; cursor-paginated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_staff1b uuid := '00000000-0000-0000-0000-000000266103';
begin
  perform app.create_procurement_dashboard_saved_view(v_tenant1, 'performance', 'Staff1 view A', null, '{}'::jsonb, '{}'::jsonb, 'idem-pdash-sv-a', v_staff1, 'staff');
  perform app.create_procurement_dashboard_saved_view(v_tenant1, 'performance', 'Staff1 view B', null, '{}'::jsonb, '{}'::jsonb, 'idem-pdash-sv-b', v_staff1, 'staff');
  perform app.create_procurement_dashboard_saved_view(v_tenant1, 'performance', 'Staff1b view', null, '{}'::jsonb, '{}'::jsonb, 'idem-pdash-sv-c', v_staff1b, 'staffb');

  if (select count(*) from app.list_procurement_dashboard_saved_views(v_tenant1, null, v_staff1, 25, null)) <> 2 then
    raise exception 'assertion failed: staff1 should see exactly their own 2 saved views, never staffb''s';
  end if;
  if (select count(*) from app.list_procurement_dashboard_saved_views(v_tenant1, null, v_staff1b, 25, null)) <> 1 then
    raise exception 'assertion failed: staffb should see exactly their own 1 saved view';
  end if;
  if exists (
    select 1 from app.list_procurement_dashboard_saved_views(v_tenant1, null, v_staff1, 25, null) where name = 'Staff1b view'
  ) then
    raise exception 'assertion failed: staff1''s own list must never include staffb''s saved view';
  end if;
end $$;

\echo '>> raw RLS on app.procurement_dashboard_saved_views: a direct select under a real authenticated session sees only rows owned by that session''s own auth.uid(), never another user''s or another tenant''s'
do $$
declare
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_staff1b uuid := '00000000-0000-0000-0000-000000266103';
  v_count integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff1::text, 'role', 'authenticated')::text, true);
  select count(*) into v_count from app.procurement_dashboard_saved_views where owner_auth_user_id = v_staff1b;
  if v_count <> 0 then
    raise exception 'assertion failed: raw RLS leak -- staff1''s own session directly selected staffb''s saved view row(s)';
  end if;
  reset role;
end $$;

-- ===========================================================================
-- Export -- reuses app.report_types/app.report_runs/app.enqueue_job (design note 6).
-- ===========================================================================

\echo '>> app.enqueue_procurement_report_export: PRC:Export required (distinct from PRC:View -- viewer1 holds View but not Export and is denied); retired report rejected; a report_type_code owned by a DIFFERENT module is rejected (module-scoping); idempotency compares the FULL target tuple (C-01), never just the key -- this migration''s own worked-around fix for the confirmed C-01 gap in the reused app.enqueue_job primitive (design note 7)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000266102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000266104';
  v_run1 app.report_runs;
  v_run1_replay app.report_runs;
  v_job app.jobs;
  v_failed boolean;
  v_other_module_code text;
begin
  begin
    perform app.enqueue_procurement_report_export(v_tenant1, 'vendor_lifecycle_risk_mix', '{}'::jsonb, 'idem-pdash-export-viewer', v_viewer1, 'viewer');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority (PRC:Export) for viewer1, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected viewer1 (PRC:View only, no PRC:Export) to be denied enqueueing an export'; end if;

  v_run1 := app.enqueue_procurement_report_export(v_tenant1, 'vendor_lifecycle_risk_mix', jsonb_build_object('lifecycleStatus', 'active'), 'idem-pdash-export-1', v_staff1, 'staff');
  if v_run1.status <> 'queued' or v_run1.run_type <> 'export' or v_run1.job_id is null then
    raise exception 'assertion failed: expected a queued export run with a linked job_id, got status=% run_type=% job_id=%', v_run1.status, v_run1.run_type, v_run1.job_id;
  end if;
  select * into v_job from app.jobs where job_id = v_run1.job_id;
  if v_job.job_type <> 'report_generation' or v_job.tenant_id <> v_tenant1 then
    raise exception 'assertion failed: expected a real app.jobs row (report_generation, correct tenant) linked to the export run';
  end if;

  -- C-01 (design note 7): identical-tuple replay -> the SAME run row, no new job.
  v_run1_replay := app.enqueue_procurement_report_export(v_tenant1, 'vendor_lifecycle_risk_mix', jsonb_build_object('lifecycleStatus', 'active'), 'idem-pdash-export-1', v_staff1, 'staff');
  if v_run1_replay.id <> v_run1.id or v_run1_replay.job_id <> v_run1.job_id then
    raise exception 'assertion failed: identical-tuple export replay must return the SAME run/job, got a different one';
  end if;
  if (select count(*) from app.jobs where tenant_id = v_tenant1 and idempotency_key = 'idem-pdash-export-1') <> 1 then
    raise exception 'assertion failed: expected exactly 1 job for this idempotency key after replay, never a duplicate';
  end if;

  -- C-01: SAME key, DIFFERENT report_type_code -> rejected (the exact confirmed gap in
  -- app.enqueue_job itself, worked around at this function's own call site).
  begin
    perform app.enqueue_procurement_report_export(v_tenant1, 'vendor_rate_validity_mix', '{}'::jsonb, 'idem-pdash-export-1', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then raise exception 'assertion failed: expected idempotency_key_conflict for a mismatched-tuple export replay, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a different report_type_code under the SAME idempotency key to be rejected, not silently mismatched'; end if;

  -- Module-scoping: a report code registered by a DIFFERENT module (if one exists in
  -- this shared catalogue) is refused through this Procurement-only entry point.
  select code into v_other_module_code from app.report_types where code not in (select code from app.procurement_metric_definitions) limit 1;
  if v_other_module_code is not null then
    begin
      perform app.enqueue_procurement_report_export(v_tenant1, v_other_module_code, '{}'::jsonb, 'idem-pdash-export-other-module', v_staff1, 'staff');
      v_failed := false;
    exception when others then
      v_failed := true;
      if sqlerrm not like 'report_type_not_procurement_owned%' then raise exception 'assertion failed: expected report_type_not_procurement_owned for a non-Procurement report code, got %', sqlerrm; end if;
    end;
    if not v_failed then raise exception 'assertion failed: expected a non-Procurement report_type_code to be refused through this entry point'; end if;
  end if;

  -- Retired report type refused.
  perform app.retire_report_type('vendor_lifecycle_risk_mix', '00000000-0000-0000-0000-000000266999', 'supreme');
  begin
    perform app.enqueue_procurement_report_export(v_tenant1, 'vendor_lifecycle_risk_mix', '{}'::jsonb, 'idem-pdash-export-retired', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'report_type_retired%' then raise exception 'assertion failed: expected report_type_retired, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a retired report type to be refused'; end if;
end $$;

-- ===========================================================================
-- Cross-tenant isolation sweep and schema-privilege defense in depth.
-- ===========================================================================

\echo '>> cross-tenant isolation sweep: every new read RPC denies tenant2''s own admin against tenant1''s tenant_id, and the reverse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pdash1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pdash2');
  v_admin2 uuid := '00000000-0000-0000-0000-000000266201';
  v_failed boolean;
begin
  begin
    perform app.get_procurement_dashboard_po_summary(v_tenant1, v_admin2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected tenant2''s admin denied on tenant1''s po_summary'; end if;

  -- tenant2's own (empty) data is genuinely empty, never tenant1's leaking through.
  if (select count(*) from app.get_procurement_dashboard_vendor_risk_summary(v_tenant2, v_admin2)) <> 0 then
    raise exception 'assertion failed: expected zero rows for tenant2 (no vendors seeded there), got a non-empty result -- possible cross-tenant leak';
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new PRC-266 function and zero direct table access; authenticated has RLS-scoped SELECT only on the two new tables, never direct INSERT/UPDATE/DELETE; service_role has full direct access'
do $$
declare
  v_leaked_to_anon text[];
  v_new_fns text[] := array[
    'register_procurement_metric_definition', 'retire_procurement_metric_definition',
    'create_procurement_dashboard_saved_view', 'update_procurement_dashboard_saved_view', 'delete_procurement_dashboard_saved_view',
    'get_procurement_dashboard_saved_view', 'list_procurement_dashboard_saved_views',
    'get_procurement_dashboard_vendor_risk_summary', 'list_procurement_vendor_risk_dashboard_rows',
    'get_procurement_dashboard_rate_validity_summary', 'get_procurement_dashboard_rate_competitiveness_summary',
    'get_procurement_dashboard_rfq_cycle_summary', 'get_procurement_dashboard_capacity_reservation_summary',
    'get_procurement_dashboard_assignment_acceptance_summary', 'get_procurement_dashboard_po_summary',
    'get_procurement_dashboard_contract_summary', 'get_procurement_dashboard_performance_summary',
    'enqueue_procurement_report_export'
  ];
  v_fn text;
  v_authenticated_write_count integer;
begin
  foreach v_fn in array v_new_fns loop
    if exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn and has_function_privilege('anon', p.oid, 'EXECUTE')
    ) then
      v_leaked_to_anon := coalesce(v_leaked_to_anon, array[]::text[]) || v_fn;
    end if;
  end loop;
  if v_leaked_to_anon is not null then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any new PRC-266 function, but does on: %', v_leaked_to_anon;
  end if;

  select count(*) into v_authenticated_write_count
  from information_schema.role_table_grants
  where table_schema = 'app' and table_name in ('procurement_metric_definitions', 'procurement_dashboard_saved_views')
    and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  if v_authenticated_write_count <> 0 then
    raise exception 'assertion failed: authenticated must hold zero direct INSERT/UPDATE/DELETE on either new table, found %', v_authenticated_write_count;
  end if;

  if not has_table_privilege('service_role', 'app.procurement_metric_definitions', 'INSERT')
    or not has_table_privilege('service_role', 'app.procurement_dashboard_saved_views', 'INSERT') then
    raise exception 'assertion failed: service_role must retain explicit write access to both new tables';
  end if;

  set local role anon;
  begin
    perform count(*) from app.procurement_dashboard_saved_views;
    raise exception 'assertion failed: expected anon to be denied direct select on app.procurement_dashboard_saved_views';
  exception
    when insufficient_privilege then null;
  end;
  reset role;
end $$;

\echo 'ALL PRC-266 db-test assertions passed.'



