-- Real, executable test evidence for PRC-263 (Vendor Assignment, CG-S11-PRC-014) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Scoped to
-- this checkpoint's own additive migration (supabase/migrations/
-- 20260730720000_create_procurement_vendor_assignment.sql). Self-contained -- builds
-- its own tenant/vendor/contract/capacity/shipment pipeline from scratch, mirroring
-- procurement-vendor-capacity.sql's own disclosed convention. Reuses the FULL
-- CRM-through-shipment-order pipeline shape scripts/db-tests/operations-resource-
-- assignment.sql already established (no shortcut/raw INSERT into app.shipment_orders
-- anywhere in this repository's own db-test suite).
--
-- Covers: propose (eligibility gate, idempotency target verification C-01) -> accept
-- -> confirm (calls the real, unmodified app.assign_resource, OPS-172; consumes a
-- linked capacity reservation inline) -> the real app.resource_assignments row;
-- decline/cancel; override (dual OPS:Assign+PRC:Override authority); reassign; the
-- PRC-261 app.terminate_vendor_contract active-dependency guard this migration adds;
-- cross-tenant/authority denial; and the service_role-only regression guard for the
-- C-12 cross-tenant disclosure this prompt's own Tier B self-check found and fixed
-- (app.evaluate_vendor_assignment_eligibility).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an org hierarchy, tenant_admin, a full-authority rep (PRC:Create/Edit/View/Override + OPS:Create/Edit/View/Assign + COM full), a PRC-only-no-OPS actor, an OPS-only-no-PRC actor, a second tenant for cross-tenant checks, a global Supreme Admin'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_rep_role uuid;
  v_prc_only_role uuid;
  v_ops_only_role uuid;
  v_t2_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000263101', 'admin@vasgn1.test'),
    ('00000000-0000-0000-0000-000000263102', 'rep@vasgn1.test'),
    ('00000000-0000-0000-0000-000000263103', 'prconly@vasgn1.test'),
    ('00000000-0000-0000-0000-000000263104', 'opsonly@vasgn1.test'),
    ('00000000-0000-0000-0000-000000263201', 'admin@vasgn2.test'),
    ('00000000-0000-0000-0000-000000263999', 'supreme@vasgn.test');

  perform app.provision_tenant('vasgn1', 'Vendor Assignment Co 1', 'idem-vasgn1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vasgn1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('vasgn2', 'Vendor Assignment Co 2', 'idem-vasgn2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vasgn2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'VASM1-CO', 'Vasm1 Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VASM1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000263101', 'admin@vasgn1.test', 'Vasm1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vasgn1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000263101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000263102', 'rep@vasgn1.test', 'Vasm1 Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@vasgn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000263103', 'prconly@vasgn1.test', 'Vasm1 PrcOnly', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'prconly@vasgn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000263104', 'opsonly@vasgn1.test', 'Vasm1 OpsOnly', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'opsonly@vasgn1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000263201', 'admin@vasgn2.test', 'Vasm2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vasgn2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000263201', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000263999', 'supreme_admin', null, null, 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Vasm1 Rep', 'full COM+PRC+OPS for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_rep_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_rep_role and status = 'draft'), now(), 'tester');
  -- admin1 also gets the full role (tenant_admin membership alone does not imply any
  -- module permission -- a role assignment is always required, mirroring PRC-261/262's
  -- own admin fixture shape) since admin1 itself performs vendor/contract/capacity
  -- setup below.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000263101', '00000000-0000-0000-0000-000000263999', 'supreme');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000263102', '00000000-0000-0000-0000-000000263101', 'admin');

  v_prc_only_role := (app.create_role(v_tenant1, 'Vasm1 PrcOnly', 'PRC:Edit/View/Override, no OPS', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_prc_only_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Edit', 'View', 'Override')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_prc_only_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_prc_only_role and status = 'published'), '00000000-0000-0000-0000-000000263103', '00000000-0000-0000-0000-000000263101', 'admin');

  v_ops_only_role := (app.create_role(v_tenant1, 'Vasm1 OpsOnly', 'OPS:Assign/View, no PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_ops_only_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Assign', 'View')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_ops_only_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_ops_only_role and status = 'published'), '00000000-0000-0000-0000-000000263104', '00000000-0000-0000-0000-000000263101', 'admin');

  v_t2_role := (app.create_role(v_tenant2, 'Vasm2 Admin Role', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000263201', '00000000-0000-0000-0000-000000263201', 'admin');
end $$;

\echo '>> setup: two ACTIVE vendors (A eligible, B left in draft to prove vendor_not_active), an active PRC-261 contract on A, a published+reserved PRC-262 capacity offer on A, and one real shipment order via the full CRM pipeline (mirrors operations-resource-assignment.sql''s own exact shape)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000263101';
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_team_a uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VASM1-CO');
  v_profile_a app.vendor_profiles;
  v_profile_b app.vendor_profiles;
  v_contract app.vendor_contracts;
  v_step_id uuid;
  v_offer app.vendor_capacity_offers;
  v_reservation app.vendor_capacity_reservations;
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
  v_shipment app.shipment_orders;
begin
  -- Vendor A: fully active, eligible.
  v_profile_a := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Assignment A', 'VASMA', 'PT', 'REG-VASM-A', 'logistics', 30, 'staff_created', 'idem-vasm-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile_a.master_record_id, 'Ani A', 'Ops', 'ani@vasma.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile_a.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile_a.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile_a.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile_a from app.vendor_profiles where master_record_id = v_profile_a.master_record_id;
  v_profile_a := app.submit_vendor_profile_for_review(v_profile_a.master_record_id, v_profile_a.record_version, v_admin1, 'admin');
  v_profile_a := app.decide_vendor_profile_review(v_profile_a.master_record_id, v_profile_a.record_version, 'approve', null, v_admin1, 'admin');
  v_profile_a := app.activate_vendor_profile(v_profile_a.master_record_id, v_profile_a.record_version, v_admin1, 'admin');

  -- Vendor B: left in draft -- never activated, for the vendor_not_active negative case.
  v_profile_b := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Assignment B', 'VASMB', 'PT', 'REG-VASM-B', 'logistics', 30, 'staff_created', 'idem-vasm-vendor-b', v_admin1, 'admin');

  -- An active PRC-261 contract governing vendor A (no rate/signature-required so it can be minimally cycled).
  v_contract := app.create_vendor_contract_draft(
    v_tenant1, v_profile_a.master_record_id, 'framework', '2026-01-01'::date, null, null, 30,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vasm-contract-a', v_admin1, 'admin'
  );
  v_contract := app.submit_vendor_contract_for_approval(v_contract.id, v_contract.record_version, 'idem-vasm-contract-submit-a', v_admin1, 'admin');
  v_contract := app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');

  -- A published PRC-262 capacity offer on vendor A, with one accepted reservation.
  v_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_profile_a.master_record_id, v_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
    50, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vasm-offer-a', v_admin1, 'admin'
  );
  v_offer := app.publish_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_admin1, 'admin');
  v_reservation := app.reserve_vendor_capacity(v_offer.id, 10, '2026-06-01'::timestamptz, '2026-06-10'::timestamptz, 'manual', null, 'idem-vasm-res-a', v_admin1, 'admin');
  v_reservation := app.accept_vendor_capacity_reservation(v_reservation.id, v_reservation.record_version, v_admin1, 'admin');

  -- Minimal real CRM-through-shipment-order pipeline (mirrors operations-resource-assignment.sql).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Vasm Test Co', 'Jane Vasm', 'jane@vasmtest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'jane@vasmtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Vasm Test Co', 'VTC', '11.111.111.1-111.000', jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Jane Vasm Ops', 'Procurement Lead', 'jane@vasmtest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep1, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vasm test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_rep1, v_team_a, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VASM-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');
  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_rep1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep1, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_rep1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight vasm lane', v_calc_id, 1, 15000000, 0, 0, v_rep1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Vasm Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vasm-shipment', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    null, null, null, null, null, null, null, null, null, v_rep1, 'rep'
  );
end $$;

\echo '>> propose: validation, eligibility gate (vendor_not_active), idempotency target-mismatch (C-01), authority'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_prconly1 uuid := '00000000-0000-0000-0000-000000263103';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_vendor_b uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment B');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment');
  v_contract_id uuid := (select id from app.vendor_contracts where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-contract-a');
  v_reservation_id uuid := (select id from app.vendor_capacity_reservations where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-res-a');
  v_invitation app.vendor_assignment_invitations;
  v_invitation2 app.vendor_assignment_invitations;
  v_failed boolean;
begin
  -- eligibility gate: vendor B is still draft, never activated
  begin
    perform app.propose_vendor_assignment_invitation(v_tenant1, v_shipment_id, v_vendor_b, null, null, null, null, now() + interval '2 days', 'idem-vasm-inv-bad', v_rep1, 'rep');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_not_eligible%' then
      raise exception 'assertion failed: expected vendor_not_eligible, got %', sqlerrm;
    end if;
    if sqlerrm not like '%vendor_not_active%' then
      raise exception 'assertion failed: expected the reason to name vendor_not_active, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected proposing an invitation for a never-activated vendor to be rejected'; end if;

  -- real, eligible proposal
  v_invitation := app.propose_vendor_assignment_invitation(
    v_tenant1, v_shipment_id, v_vendor_a, v_contract_id, null, null, v_reservation_id, now() + interval '2 days', 'idem-vasm-inv-1', v_rep1, 'rep'
  );
  if v_invitation.status <> 'invited' or v_invitation.vendor_master_id <> v_vendor_a then
    raise exception 'assertion failed: expected status=invited for vendor A, got status=% vendor=%', v_invitation.status, v_invitation.vendor_master_id;
  end if;
  if (v_invitation.eligibility_snapshot->>'compliance_hold')::boolean is distinct from false then
    raise exception 'assertion failed: expected eligibility_snapshot.compliance_hold=false, got %', v_invitation.eligibility_snapshot;
  end if;

  -- idempotency replay: identical key returns the SAME row
  v_invitation2 := app.propose_vendor_assignment_invitation(
    v_tenant1, v_shipment_id, v_vendor_a, v_contract_id, null, null, v_reservation_id, now() + interval '2 days', 'idem-vasm-inv-1', v_rep1, 'rep'
  );
  if v_invitation2.id <> v_invitation.id then
    raise exception 'assertion failed: expected the identical idempotency-key replay to return the SAME row';
  end if;

  -- a second, live (invited) invitation for the SAME shipment order is blocked by the partial unique index
  begin
    perform app.propose_vendor_assignment_invitation(v_tenant1, v_shipment_id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vasm-inv-conflict', v_rep1, 'rep');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invitation_conflict%' then
      raise exception 'assertion failed: expected invitation_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a second live invitation for the same shipment order to be rejected'; end if;
end $$;

\echo '>> accept -> confirm: dual-authority gate (PRC:Edit-only actor denied at confirm; OPS:Assign required), real app.assign_resource commitment, capacity reservation consumed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_prconly1 uuid := '00000000-0000-0000-0000-000000263103';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment');
  v_reservation_id uuid := (select id from app.vendor_capacity_reservations where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-res-a');
  v_invitation app.vendor_assignment_invitations;
  v_assignment_count integer;
  v_reservation_status text;
  v_failed boolean;
begin
  select * into v_invitation from app.vendor_assignment_invitations where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-inv-1';

  -- confirm before accept is rejected
  begin
    perform app.confirm_vendor_assignment(v_invitation.id, v_invitation.record_version, v_rep1, 'rep');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected confirming an invited (not yet accepted) invitation to be rejected'; end if;

  v_invitation := app.accept_vendor_assignment_invitation(v_invitation.id, v_invitation.record_version, v_rep1, 'rep');
  if v_invitation.status <> 'accepted' then
    raise exception 'assertion failed: expected status=accepted, got %', v_invitation.status;
  end if;

  -- a PRC:Edit-only actor (no OPS:Assign) is denied at confirm -- design note 1's own dual-authority split
  begin
    perform app.confirm_vendor_assignment(v_invitation.id, v_invitation.record_version, v_prconly1, 'prconly');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority (OPS:Assign), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a PRC:Edit-only actor (no OPS:Assign) to be denied at confirm'; end if;

  v_invitation := app.confirm_vendor_assignment(v_invitation.id, v_invitation.record_version, v_rep1, 'rep');
  if v_invitation.status <> 'assigned' or v_invitation.assignment_id is null then
    raise exception 'assertion failed: expected status=assigned with assignment_id set, got status=% assignment_id=%', v_invitation.status, v_invitation.assignment_id;
  end if;

  -- the REAL canonical app.resource_assignments row now exists (OPS-172, never re-implemented)
  select count(*) into v_assignment_count from app.resource_assignments where id = v_invitation.assignment_id and shipment_order_id = v_shipment_id and role = 'vendor' and resource_id = v_vendor_a and is_current;
  if v_assignment_count <> 1 then
    raise exception 'assertion failed: expected exactly one real, current app.resource_assignments row for this shipment/vendor, found %', v_assignment_count;
  end if;

  -- the linked capacity reservation was consumed inline (design note 2)
  select status into v_reservation_status from app.vendor_capacity_reservations where id = v_reservation_id;
  if v_reservation_status <> 'consumed' then
    raise exception 'assertion failed: expected the linked capacity reservation to be consumed, got %', v_reservation_status;
  end if;

  -- confirming again (already assigned) is rejected
  begin
    perform app.confirm_vendor_assignment(v_invitation.id, v_invitation.record_version, v_rep1, 'rep');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected re-confirming an already-assigned invitation to be rejected'; end if;
end $$;

\echo '>> decline (mandatory reason) and cancel (mandatory reason), on their own fresh shipment/invitation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_shipment2 app.shipment_orders;
  v_invitation app.vendor_assignment_invitations;
  v_failed boolean;
begin
  -- a second, independent shipment order (mirrors OPS-172's own "split fixture" pattern) so this block does not collide with the confirmed invitation above
  select * into v_shipment2 from app.create_shipment_order_from_job(
    (select job_order_id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment'),
    'idem-vasm-shipment-2', null, null, 'ocean_freight', 'land', 'Jakarta', 'Bandung', null, null, null, null, null, null, null, null, 'split: decline/cancel fixture', v_rep1, 'rep'
  );

  -- decline requires a reason
  v_invitation := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment2.id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vasm-inv-decline', v_rep1, 'rep');
  begin
    perform app.decline_vendor_assignment_invitation(v_invitation.id, v_invitation.record_version, '', v_rep1, 'rep');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required%' then
      raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty decline reason to be rejected'; end if;

  v_invitation := app.decline_vendor_assignment_invitation(v_invitation.id, v_invitation.record_version, 'vendor unavailable', v_rep1, 'rep');
  if v_invitation.status <> 'declined' or v_invitation.decline_reason is null then
    raise exception 'assertion failed: expected status=declined with a reason, got %/%', v_invitation.status, v_invitation.decline_reason;
  end if;

  -- a NEW invitation is now allowed for the same shipment (the prior one is no longer live)
  v_invitation := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment2.id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vasm-inv-cancel', v_rep1, 'rep');
  v_invitation := app.cancel_vendor_assignment_invitation(v_invitation.id, v_invitation.record_version, 'no longer needed', v_rep1, 'rep');
  if v_invitation.status <> 'cancelled' or v_invitation.cancel_reason is null then
    raise exception 'assertion failed: expected status=cancelled with a reason, got %/%', v_invitation.status, v_invitation.cancel_reason;
  end if;
end $$;

\echo '>> override_vendor_assignment: dual OPS:Assign+PRC:Override authority, direct-assign bypassing invite/accept'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_ops_only1 uuid := '00000000-0000-0000-0000-000000263104';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_shipment3 app.shipment_orders;
  v_invitation app.vendor_assignment_invitations;
  v_failed boolean;
begin
  -- release vendor A's prior (shipment1) assignment first -- app.assign_resource's own
  -- assignment_conflict guard (OPS-172, pre-existing, unmodified by this migration)
  -- rejects assigning a resource that already holds a live assignment elsewhere, and
  -- override still creates a REAL app.resource_assignments row through that same path
  -- (design note 1: override bypasses the vendor-eligibility gate, never the underlying
  -- resource-occupancy invariant).
  perform app.unassign_resource(
    (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment'),
    'vendor', 'shipment1 delivered, releasing vendor A for the override fixture', v_rep1, 'rep'
  );

  select * into v_shipment3 from app.create_shipment_order_from_job(
    (select job_order_id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment'),
    'idem-vasm-shipment-3', null, null, 'ocean_freight', 'land', 'Jakarta', 'Semarang', null, null, null, null, null, null, null, null, 'split: override fixture', v_rep1, 'rep'
  );

  -- an OPS:Assign-only actor (no PRC:Override) is denied
  begin
    perform app.override_vendor_assignment(v_tenant1, v_shipment3.id, v_vendor_a, 'emergency capacity shortfall', 'idem-vasm-override-bad', v_ops_only1, 'opsonly');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:Override), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an OPS:Assign-only actor (no PRC:Override) to be denied the override'; end if;

  v_invitation := app.override_vendor_assignment(v_tenant1, v_shipment3.id, v_vendor_a, 'emergency capacity shortfall, customer commitment at risk', 'idem-vasm-override-1', v_rep1, 'rep');
  if v_invitation.status <> 'assigned' or not v_invitation.is_override or v_invitation.override_reason is null then
    raise exception 'assertion failed: expected status=assigned is_override=true with a reason, got status=%/is_override=%/reason=%', v_invitation.status, v_invitation.is_override, v_invitation.override_reason;
  end if;
  if not exists (select 1 from app.resource_assignments where id = v_invitation.assignment_id and role = 'vendor' and is_current) then
    raise exception 'assertion failed: expected a real, current app.resource_assignments row from the override';
  end if;
end $$;

\echo '>> reassign_vendor_assignment: supersede + new assigned invitation, real app.reassign_resource commitment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000263101';
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_vendor_c app.vendor_profiles;
  v_invitation app.vendor_assignment_invitations;
  v_new_invitation app.vendor_assignment_invitations;
begin
  -- a second eligible vendor to reassign TO
  v_vendor_c := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Assignment C', 'VASMC', 'PT', 'REG-VASM-C', 'logistics', 30, 'staff_created', 'idem-vasm-vendor-c', v_admin1, 'admin');
  perform app.add_vendor_contact(v_vendor_c.master_record_id, 'Cici C', 'Ops', 'cici@vasmc.test', '0813', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_vendor_c.master_record_id, 'legal', 'Jl. Thamrin 1', 'Jakarta', 'DKI Jakarta', '10240', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_vendor_c.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_vendor_c.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_vendor_c from app.vendor_profiles where master_record_id = v_vendor_c.master_record_id;
  v_vendor_c := app.submit_vendor_profile_for_review(v_vendor_c.master_record_id, v_vendor_c.record_version, v_admin1, 'admin');
  v_vendor_c := app.decide_vendor_profile_review(v_vendor_c.master_record_id, v_vendor_c.record_version, 'approve', null, v_admin1, 'admin');
  v_vendor_c := app.activate_vendor_profile(v_vendor_c.master_record_id, v_vendor_c.record_version, v_admin1, 'admin');

  select * into v_invitation from app.vendor_assignment_invitations where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-override-1';

  v_new_invitation := app.reassign_vendor_assignment(
    v_invitation.id, v_invitation.record_version, v_vendor_c.master_record_id, null, null, null, null,
    'vendor A withdrew capacity last minute', 'idem-vasm-reassign-1', v_rep1, 'rep'
  );
  if v_new_invitation.status <> 'assigned' or v_new_invitation.vendor_master_id <> v_vendor_c.master_record_id then
    raise exception 'assertion failed: expected the new invitation status=assigned vendor=vendor C, got status=% vendor=%', v_new_invitation.status, v_new_invitation.vendor_master_id;
  end if;
  if (select status from app.vendor_assignment_invitations where id = v_invitation.id) <> 'superseded' then
    raise exception 'assertion failed: expected the prior (vendor A) invitation to be marked superseded';
  end if;
  if (select superseded_by_id from app.vendor_assignment_invitations where id = v_invitation.id) <> v_new_invitation.id then
    raise exception 'assertion failed: expected the prior invitation''s superseded_by_id to point at the new invitation';
  end if;
  -- the canonical assignment now points at vendor C, not vendor A -- app.reassign_resource''s own real effect
  if not exists (select 1 from app.resource_assignments where id = v_new_invitation.assignment_id and resource_id = v_vendor_c.master_record_id and is_current) then
    raise exception 'assertion failed: expected the current app.resource_assignments row to now reference vendor C';
  end if;
  if exists (select 1 from app.resource_assignments where shipment_order_id = (select shipment_order_id from app.vendor_assignment_invitations where id = v_invitation.id) and resource_id = v_vendor_a and role = 'vendor' and is_current) then
    raise exception 'assertion failed: expected vendor A''s own prior assignment row to no longer be current after reassignment';
  end if;
end $$;

\echo '>> app.terminate_vendor_contract (PRC-261) active-dependency guard added by this migration (design note 5): blocked while a live invitation cites the contract, succeeds once cleared'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000263101';
  v_rep1 uuid := '00000000-0000-0000-0000-000000263102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Assignment A');
  v_contract app.vendor_contracts;
  v_shipment4 app.shipment_orders;
  v_invitation app.vendor_assignment_invitations;
  v_failed boolean;
begin
  -- a SEPARATE, freshly-issued contract for this test, deliberately not the one used
  -- earlier for the confirmed shipment1 assignment ('idem-vasm-contract-a'): that
  -- contract's own governing invitation ('idem-vasm-inv-1') reached the terminal
  -- 'assigned' status and this migration has no "close out a fulfilled assignment"
  -- transition independent of reassigning it to a replacement vendor (disclosed, C-23)
  -- -- reusing it here would make the active-dependency guard permanently un-clearable
  -- and this block would never reach a genuine "succeeds once cleared" state.
  v_contract := app.create_vendor_contract_draft(
    v_tenant1, v_vendor_a, 'framework', '2026-01-01'::date, null, null, 30,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vasm-contract-a2', v_admin1, 'admin'
  );
  v_contract := app.submit_vendor_contract_for_approval(v_contract.id, v_contract.record_version, 'idem-vasm-contract-a2-submit', v_admin1, 'admin');
  v_contract := app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');

  select * into v_shipment4 from app.create_shipment_order_from_job(
    (select job_order_id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-shipment'),
    'idem-vasm-shipment-4', null, null, 'ocean_freight', 'land', 'Jakarta', 'Bogor', null, null, null, null, null, null, null, null, 'split: terminate-dependency fixture', v_rep1, 'rep'
  );
  v_invitation := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment4.id, v_vendor_a, v_contract.id, null, null, null, now() + interval '2 days', 'idem-vasm-inv-dep', v_rep1, 'rep');

  begin
    perform app.terminate_vendor_contract(v_contract.id, v_contract.record_version, 'vendor exited the market', 'legal-notice-ref-vasm', v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'active_dependency_exists%' then
      raise exception 'assertion failed: expected active_dependency_exists, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected terminating a contract with a live (invited) assignment invitation to be rejected'; end if;

  perform app.cancel_vendor_assignment_invitation(v_invitation.id, v_invitation.record_version, 'clearing dependency for termination test', v_rep1, 'rep');

  -- now succeeds -- the dependency is gone
  v_contract := app.terminate_vendor_contract(v_contract.id, v_contract.record_version, 'vendor exited the market', 'legal-notice-ref-vasm', v_admin1, 'admin');
  if v_contract.status <> 'terminated' then
    raise exception 'assertion failed: expected status=terminated once the dependency was cleared, got %', v_contract.status;
  end if;
end $$;

\echo '>> cross-tenant authority denial (C-05 fold) and schema-privilege defense in depth, including the service_role-only regression guard for app.evaluate_vendor_assignment_eligibility (the real cross-tenant disclosure this prompt''s own Tier B self-check found and fixed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasgn1');
  v_admin2 uuid := '00000000-0000-0000-0000-000000263201';
  v_invitation_id uuid := (select id from app.vendor_assignment_invitations where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-inv-1');
  v_failed boolean;
  v_count integer;
begin
  begin
    perform app.get_vendor_assignment_invitation(v_invitation_id, v_admin2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_assignment_invitation_not_found%' then
      raise exception 'assertion failed: expected vendor_assignment_invitation_not_found (never insufficient_authority, which would disclose existence) for a cross-tenant read, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant get_vendor_assignment_invitation to be denied'; end if;

  select count(*) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon' and routine_name like '%vendor_assignment%';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any vendor-assignment function, found %', v_count;
  end if;

  select count(*) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'authenticated' and routine_name = 'evaluate_vendor_assignment_eligibility';
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.evaluate_vendor_assignment_eligibility to carry NO authenticated grant (service_role-only, C-12 fix) -- found %', v_count;
  end if;
  select count(*) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'service_role' and routine_name = 'evaluate_vendor_assignment_eligibility';
  if v_count <> 1 then
    raise exception 'assertion failed: expected app.evaluate_vendor_assignment_eligibility to carry exactly one service_role grant, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every vendor-assignment mutation recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action in (
    'propose_vendor_assignment_invitation', 'accept_vendor_assignment_invitation', 'decline_vendor_assignment_invitation',
    'cancel_vendor_assignment_invitation', 'confirm_vendor_assignment', 'reassign_vendor_assignment', 'override_vendor_assignment'
  );
  if v_count < 7 then
    raise exception 'assertion failed: expected at least 7 captured vendor-assignment audit events, found %', v_count;
  end if;
end $$;

\echo 'ALL PRC-263 db-test assertions passed.'

