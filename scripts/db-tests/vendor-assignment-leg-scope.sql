-- Real, executable regression evidence for ISS-2026-062 (vendor assignment has no
-- shipment-leg/task granularity) -- run via `pnpm run db:test` /
-- `bash scripts/db-tests/run.sh` against a real, disposable Postgres database.
-- Scoped to supabase/migrations/20260902031000_add_vendor_assignment_leg_scope_
-- iss2026062.sql. Self-contained -- builds its own tenant/role/vendor/shipment-leg
-- fixtures from scratch, mirroring scripts/db-tests/procurement-vendor-assignment.sql's
-- own disclosed CRM-through-shipment-order pipeline shape. Left untouched by this
-- file: procurement-vendor-assignment.sql itself re-runs unchanged in the same shared
-- disposable database (a whole-shipment invitation is exactly what it already
-- exercises, and this file's own whole-shipment block below re-proves the identical
-- invariant on its own fixtures).
--
-- Covers exactly the three acceptance criteria named in the issue:
-- 1. a leg-scoped assignment is created and correctly scoped (propose/accept/confirm
--    against one specific leg commits to that leg's own app.shipment_legs.
--    carrier_master_id, never to the canonical whole-shipment app.resource_
--    assignments);
-- 2. a whole-shipment assignment (no leg reference) behaves EXACTLY as before (calls
--    the real, unmodified app.assign_resource/app.reassign_resource, OPS-172);
-- 3. a query for "assignments on this leg" returns only the correctly-scoped ones,
--    never a whole-shipment row or a different leg's row.
--
-- Also covers: two DIFFERENT vendors concurrently live-assigned to two DIFFERENT legs
-- of the SAME shipment order (the actual multi-leg capability gap this issue names);
-- a structurally invalid leg reference (wrong shipment order) refused at propose
-- time; leg_already_assigned at confirm time when a leg's carrier is already set;
-- and a real leg-scoped reassignment.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an org unit, tenant_admin, a full-authority rep (PRC:Edit + OPS:Assign + COM full), a global Supreme Admin'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_rep_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000622101', 'admin@vlegsc1.test'),
    ('00000000-0000-0000-0000-000000622102', 'rep@vlegsc1.test'),
    ('00000000-0000-0000-0000-000000622999', 'supreme@vlegsc.test');

  perform app.provision_tenant('vlegsc1', 'Vendor Leg Scope Co 1', 'idem-vlegsc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vlegsc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'VLEG1-CO', 'Vleg1 Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VLEG1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000622101', 'admin@vlegsc1.test', 'Vleg1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vlegsc1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000622101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000622102', 'rep@vlegsc1.test', 'Vleg1 Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@vlegsc1.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000622999', 'supreme_admin', null, null, 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Vleg1 Rep', 'full COM+PRC+OPS for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_rep_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_rep_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000622101', '00000000-0000-0000-0000-000000622999', 'supreme');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000622102', '00000000-0000-0000-0000-000000622101', 'admin');
end $$;

\echo '>> setup: two ACTIVE vendors (A and B), a real shipment order via the full CRM pipeline (mirrors procurement-vendor-assignment.sql''s own exact shape), and a real two-leg network on it (app.add_shipment_leg, ATW-221) -- leg1 Jakarta->Bandung, leg2 Bandung->Surabaya'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000622101';
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_team_a uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VLEG1-CO');
  v_profile_a app.vendor_profiles;
  v_profile_b app.vendor_profiles;
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
  v_other_shipment app.shipment_orders;
  v_leg1 app.shipment_legs;
  v_leg2 app.shipment_legs;
begin
  v_profile_a := app.create_vendor_profile_draft(v_tenant1, 'PT Leg Scope Vendor A', 'VLEGA', 'PT', 'REG-VLEG-A', 'logistics', 30, 'staff_created', 'idem-vleg-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile_a.master_record_id, 'Ani A', 'Ops', 'ani@vlega.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile_a.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile_a.master_record_id, 'trucking', v_admin1, 'admin');
  select * into v_profile_a from app.vendor_profiles where master_record_id = v_profile_a.master_record_id;
  v_profile_a := app.submit_vendor_profile_for_review(v_profile_a.master_record_id, v_profile_a.record_version, v_admin1, 'admin');
  v_profile_a := app.decide_vendor_profile_review(v_profile_a.master_record_id, v_profile_a.record_version, 'approve', null, v_admin1, 'admin');
  v_profile_a := app.activate_vendor_profile(v_profile_a.master_record_id, v_profile_a.record_version, v_admin1, 'admin');

  v_profile_b := app.create_vendor_profile_draft(v_tenant1, 'PT Leg Scope Vendor B', 'VLEGB', 'PT', 'REG-VLEG-B', 'logistics', 30, 'staff_created', 'idem-vleg-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile_b.master_record_id, 'Budi B', 'Ops', 'budi@vlegb.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile_b.master_record_id, 'legal', 'Jl. Thamrin 1', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile_b.master_record_id, 'trucking', v_admin1, 'admin');
  select * into v_profile_b from app.vendor_profiles where master_record_id = v_profile_b.master_record_id;
  v_profile_b := app.submit_vendor_profile_for_review(v_profile_b.master_record_id, v_profile_b.record_version, v_admin1, 'admin');
  v_profile_b := app.decide_vendor_profile_review(v_profile_b.master_record_id, v_profile_b.record_version, 'approve', null, v_admin1, 'admin');
  v_profile_b := app.activate_vendor_profile(v_profile_b.master_record_id, v_profile_b.record_version, v_admin1, 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Vleg Test Co', 'Jane Vleg', 'jane@vlegtest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'jane@vlegtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Vleg Test Co', 'VTC', '11.111.111.1-222.000', jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Jane Vleg Ops', 'Procurement Lead', 'jane@vlegtest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep1, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vleg test multi-leg lane',
    jsonb_build_object('service_type', 'trucking', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_rep1, v_team_a, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VLEG-1', 'Contoso Multi-Leg Line', 'trucking', null, 'Jakarta', 'Surabaya', null,
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');
  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_rep1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep1, 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, v_rep1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Multi-leg trucking lane', v_calc_id, 1, 6000000, 0, 0, v_rep1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Vleg Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vleg-shipment', null, null, 'trucking', 'land', 'Jakarta', 'Surabaya',
    null, null, null, null, null, null, null, null, null, v_rep1, 'rep'
  );

  -- A real two-leg network on this shipment order (ATW-221, app.add_shipment_leg).
  v_leg1 := app.add_shipment_leg(v_shipment.id, 'idem-vleg-leg-1', 1, 'land', null, null, null, v_rep1, 'rep');
  v_leg2 := app.add_shipment_leg(v_shipment.id, 'idem-vleg-leg-2', 2, 'land', null, null, null, v_rep1, 'rep');

  -- A second, wholly independent shipment order -- app.prepare_job_order_handoff is
  -- idempotent PER QUOTATION (returns the SAME handoff for a repeat call on v_quote),
  -- so this reuses the existing prospect/contact but drives a genuinely SECOND
  -- opportunity/costing/quote/account/job-order chain through to its own shipment
  -- order, to prove a cross-shipment leg reference is refused at propose time and
  -- (later) that a whole-shipment assignment is unaffected on its own, separate
  -- shipment order.
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vleg second lane',
    jsonb_build_object('service_type', 'trucking', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-15'),
    v_rep1, v_team_a, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, v_rep1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Second trucking lane', v_calc_id, 1, 6000000, 0, 0, v_rep1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Vleg Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');
  select * into v_other_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vleg-other-shipment', null, null, 'trucking', 'land', 'Jakarta', 'Surabaya',
    null, null, null, null, null, null, null, null, null, v_rep1, 'rep'
  );
end $$;

\echo '>> invalid_leg_reference: proposing against a leg that belongs to a DIFFERENT shipment order is refused at propose time (explicit check, backed by the structural trigger)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor A');
  v_other_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-other-shipment');
  v_leg1_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-1');
begin
  begin
    perform app.propose_vendor_assignment_invitation(
      v_tenant1, v_other_shipment_id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vleg-badleg', v_rep1, 'rep', v_leg1_id
    );
    raise exception 'assertion failed: expected invalid_leg_reference -- leg1 belongs to the FIRST shipment order, not the other one';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_leg_reference%' then raise; end if;
  end;
end $$;

\echo '>> acceptance criterion 1 + the actual multi-leg capability: two DIFFERENT vendors, each proposed/accepted/confirmed against a DIFFERENT leg of the SAME shipment order -- both live simultaneously, each commits to its own leg''s app.shipment_legs.carrier_master_id, assignment_id stays null on both (no canonical app.resource_assignments row for either)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor A');
  v_vendor_b uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor B');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-shipment');
  v_leg1_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-1');
  v_leg2_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-2');
  v_inv1 app.vendor_assignment_invitations;
  v_inv2 app.vendor_assignment_invitations;
  v_leg1 app.shipment_legs;
  v_leg2 app.shipment_legs;
  v_resource_assignment_count integer;
begin
  v_inv1 := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment_id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vleg-inv-leg1', v_rep1, 'rep', v_leg1_id);
  if v_inv1.shipment_leg_id <> v_leg1_id then
    raise exception 'assertion failed: expected the invitation to carry shipment_leg_id=%, got %', v_leg1_id, v_inv1.shipment_leg_id;
  end if;
  v_inv1 := app.accept_vendor_assignment_invitation(v_inv1.id, v_inv1.record_version, v_rep1, 'rep');
  v_inv1 := app.confirm_vendor_assignment(v_inv1.id, v_inv1.record_version, v_rep1, 'rep');
  if v_inv1.status <> 'assigned' or v_inv1.assignment_id is not null then
    raise exception 'assertion failed: expected a leg-scoped confirm to reach status=assigned with assignment_id=null (no canonical resource_assignments row), got status=% assignment_id=%', v_inv1.status, v_inv1.assignment_id;
  end if;

  -- The SAME shipment order, a DIFFERENT leg, a DIFFERENT vendor -- proposed/accepted/
  -- confirmed WHILE inv1 is already live (assigned) on leg1. This is the actual
  -- capability gap: PRE-migration, app.assign_resource's own shipment-order-scoped
  -- already_assigned check would have blocked this second confirm outright.
  v_inv2 := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment_id, v_vendor_b, null, null, null, null, now() + interval '2 days', 'idem-vleg-inv-leg2', v_rep1, 'rep', v_leg2_id);
  v_inv2 := app.accept_vendor_assignment_invitation(v_inv2.id, v_inv2.record_version, v_rep1, 'rep');
  v_inv2 := app.confirm_vendor_assignment(v_inv2.id, v_inv2.record_version, v_rep1, 'rep');
  if v_inv2.status <> 'assigned' then
    raise exception 'assertion failed: expected leg2''s invitation to reach status=assigned concurrently with leg1''s, got %', v_inv2.status;
  end if;

  select * into v_leg1 from app.shipment_legs where id = v_leg1_id;
  select * into v_leg2 from app.shipment_legs where id = v_leg2_id;
  if v_leg1.carrier_master_id <> v_vendor_a then
    raise exception 'assertion failed: expected leg1.carrier_master_id=% (vendor A), got %', v_vendor_a, v_leg1.carrier_master_id;
  end if;
  if v_leg2.carrier_master_id <> v_vendor_b then
    raise exception 'assertion failed: expected leg2.carrier_master_id=% (vendor B) -- a DIFFERENT vendor than leg1, proving true per-leg granularity, got %', v_vendor_b, v_leg2.carrier_master_id;
  end if;

  -- Design note 2: neither leg-scoped confirm ever touched the canonical OPS-172
  -- table -- zero app.resource_assignments rows exist for this shipment order.
  select count(*) into v_resource_assignment_count from app.resource_assignments where shipment_order_id = v_shipment_id;
  if v_resource_assignment_count <> 0 then
    raise exception 'assertion failed: expected zero app.resource_assignments rows for this shipment order (both commits were leg-scoped), found %', v_resource_assignment_count;
  end if;
end $$;

\echo '>> leg_already_assigned: a THIRD invitation proposed/accepted for leg1 (already carrying vendor A) is refused AT CONFIRM TIME with a clear, named error -- never silently overwrites the leg''s existing carrier'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_vendor_b uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor B');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-shipment');
  v_leg1_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-1');
  v_inv3 app.vendor_assignment_invitations;
  v_leg1 app.shipment_legs;
begin
  -- Note: inv1 (leg1, vendor A) is already status=assigned, so it no longer holds the
  -- "one live invited/accepted per scope" slot -- a fresh propose against the SAME
  -- leg is structurally allowed (mirrors the pre-existing whole-shipment behavior:
  -- the invitation-level uniqueness only ever guarded invited/accepted, never
  -- already-assigned; app.assign_resource's own already_assigned check is what
  -- refused a second whole-shipment confirm -- this leg-scoped path needs, and gets,
  -- the equivalent guard at confirm time instead).
  v_inv3 := app.propose_vendor_assignment_invitation(v_tenant1, v_shipment_id, v_vendor_b, null, null, null, null, now() + interval '2 days', 'idem-vleg-inv-leg1-dup', v_rep1, 'rep', v_leg1_id);
  v_inv3 := app.accept_vendor_assignment_invitation(v_inv3.id, v_inv3.record_version, v_rep1, 'rep');

  begin
    perform app.confirm_vendor_assignment(v_inv3.id, v_inv3.record_version, v_rep1, 'rep');
    raise exception 'assertion failed: expected leg_already_assigned -- leg1 already carries vendor A';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'leg_already_assigned%' then raise; end if;
  end;

  -- The leg's existing carrier is untouched by the refused attempt.
  select * into v_leg1 from app.shipment_legs where id = v_leg1_id;
  if v_leg1.carrier_master_id <> (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor A') then
    raise exception 'assertion failed: expected leg1''s carrier to remain vendor A after the refused confirm attempt, got %', v_leg1.carrier_master_id;
  end if;
end $$;

\echo '>> leg-scoped reassignment: app.reassign_vendor_assignment on leg2''s own live invitation updates app.shipment_legs.carrier_master_id directly, never calling app.reassign_resource (no resource_assignments row exists to reassign)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor A');
  v_leg2_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-2');
  v_inv2 app.vendor_assignment_invitations;
  v_inv2_new app.vendor_assignment_invitations;
  v_leg2 app.shipment_legs;
begin
  select * into v_inv2 from app.vendor_assignment_invitations where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-inv-leg2';

  v_inv2_new := app.reassign_vendor_assignment(v_inv2.id, v_inv2.record_version, v_vendor_a, null, null, null, null, 'vendor B underperformed on leg2', 'idem-vleg-reassign-leg2', v_rep1, 'rep');
  if v_inv2_new.shipment_leg_id <> v_leg2_id or v_inv2_new.vendor_master_id <> v_vendor_a or v_inv2_new.status <> 'assigned' then
    raise exception 'assertion failed: expected the reassignment to stay scoped to leg2 with the new vendor A, got leg=% vendor=% status=%', v_inv2_new.shipment_leg_id, v_inv2_new.vendor_master_id, v_inv2_new.status;
  end if;

  select * into v_leg2 from app.shipment_legs where id = v_leg2_id;
  if v_leg2.carrier_master_id <> v_vendor_a then
    raise exception 'assertion failed: expected leg2.carrier_master_id to now be vendor A after reassignment, got %', v_leg2.carrier_master_id;
  end if;

  select * into v_inv2 from app.vendor_assignment_invitations where id = v_inv2.id;
  if v_inv2.status <> 'superseded' or v_inv2.superseded_by_id <> v_inv2_new.id then
    raise exception 'assertion failed: expected the prior leg2 invitation to be superseded, got status=% superseded_by=%', v_inv2.status, v_inv2.superseded_by_id;
  end if;
end $$;

\echo '>> acceptance criterion 3: app.list_vendor_assignment_invitations(p_shipment_leg_id=leg1) returns ONLY the leg1-scoped row, never leg2''s or a whole-shipment one; the unfiltered call (p_shipment_leg_id omitted, every pre-existing caller''s shape) is unaffected and returns every scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-shipment');
  v_leg1_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-1');
  v_leg2_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-leg-2');
  v_leg1_rows uuid[];
  v_unfiltered_count integer;
  v_leg_null_count integer;
begin
  select array_agg(id) into v_leg1_rows from app.list_vendor_assignment_invitations(v_tenant1, v_shipment_id, null, null, v_rep1, 25, v_leg1_id);
  if array_length(v_leg1_rows, 1) is null then
    raise exception 'assertion failed: expected at least one row scoped to leg1';
  end if;
  if exists (select 1 from app.vendor_assignment_invitations where id = any(v_leg1_rows) and shipment_leg_id is distinct from v_leg1_id) then
    raise exception 'assertion failed: a leg1-filtered query returned a row NOT scoped to leg1 (leaked a different leg or a whole-shipment row)';
  end if;
  -- Structural sanity: leg2 rows genuinely exist in this fixture (guards against a
  -- vacuously-true test above if leg2 had somehow been left empty).
  if not exists (select 1 from app.vendor_assignment_invitations where tenant_id = v_tenant1 and shipment_leg_id = v_leg2_id) then
    raise exception 'assertion failed: test setup error -- expected at least one leg2-scoped row to exist';
  end if;

  -- The unfiltered call (p_shipment_leg_id omitted -- every pre-existing caller's
  -- own positional-argument shape, 6 args) is completely unaffected: it still
  -- returns rows across every scope, leg-filtered or not.
  select count(*) into v_unfiltered_count from app.list_vendor_assignment_invitations(v_tenant1, v_shipment_id, null, null, v_rep1, 25);
  select count(*) into v_leg_null_count from app.vendor_assignment_invitations where tenant_id = v_tenant1 and shipment_order_id = v_shipment_id;
  if v_unfiltered_count <> v_leg_null_count then
    raise exception 'assertion failed: expected the unfiltered (6-arg) call to return every row for this shipment order (%), got %', v_leg_null_count, v_unfiltered_count;
  end if;
end $$;

\echo '>> acceptance criterion 2: a whole-shipment invitation (no leg reference) behaves EXACTLY as before -- confirm calls the real, unmodified app.assign_resource, and app.resource_assignments gains a real row scoped to the whole shipment order (a SECOND, independent shipment order, so it never collides with the leg-scoped rows already committed above)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vlegsc1');
  v_rep1 uuid := '00000000-0000-0000-0000-000000622102';
  v_vendor_a uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor A');
  v_other_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vleg-other-shipment');
  v_inv app.vendor_assignment_invitations;
  v_ra_count integer;
begin
  -- p_shipment_leg_id omitted entirely (positional call with 11 args, the exact
  -- pre-existing shape) -- shipment_leg_id defaults to null.
  v_inv := app.propose_vendor_assignment_invitation(
    v_tenant1, v_other_shipment_id, v_vendor_a, null, null, null, null, now() + interval '2 days', 'idem-vleg-inv-wholeshipment', v_rep1, 'rep'
  );
  if v_inv.shipment_leg_id is not null then
    raise exception 'assertion failed: expected shipment_leg_id=null for a whole-shipment invitation, got %', v_inv.shipment_leg_id;
  end if;
  v_inv := app.accept_vendor_assignment_invitation(v_inv.id, v_inv.record_version, v_rep1, 'rep');
  v_inv := app.confirm_vendor_assignment(v_inv.id, v_inv.record_version, v_rep1, 'rep');

  if v_inv.status <> 'assigned' or v_inv.assignment_id is null then
    raise exception 'assertion failed: expected a whole-shipment confirm to reach status=assigned WITH a real assignment_id (app.resource_assignments), got status=% assignment_id=%', v_inv.status, v_inv.assignment_id;
  end if;

  select count(*) into v_ra_count from app.resource_assignments where id = v_inv.assignment_id and shipment_order_id = v_other_shipment_id and role = 'vendor' and resource_id = v_vendor_a and is_current;
  if v_ra_count <> 1 then
    raise exception 'assertion failed: expected exactly one real, current app.resource_assignments row for this whole-shipment confirm (byte-identical to pre-ISS-2026-062 behavior), found %', v_ra_count;
  end if;

  -- Whole-shipment uniqueness is unchanged by this migration: the coalesce-to-
  -- sentinel index still permits at most one LIVE (invited/accepted) whole-shipment
  -- invitation at a time (byte-identical to before ISS-2026-062 -- the same
  -- vendor_assignment_invitations_one_live_per_shipment_unique invariant the
  -- ORIGINAL index enforced, just renamed and widened to also cover legs). A second
  -- propose against the SAME whole-shipment scope while inv1 is already ASSIGNED
  -- (not merely invited/accepted, so outside the index's own WHERE clause) is
  -- correctly permitted to propose/accept -- but its CONFIRM still hits the real,
  -- unmodified app.assign_resource's own already_assigned guard, exactly as it
  -- always has (this migration adds no new behavior here -- proving it stays
  -- unchanged is the point).
  declare
    v_vendor_b uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Leg Scope Vendor B');
    v_inv_dup app.vendor_assignment_invitations;
  begin
    v_inv_dup := app.propose_vendor_assignment_invitation(
      v_tenant1, v_other_shipment_id, v_vendor_b, null, null, null, null, now() + interval '2 days', 'idem-vleg-inv-wholeshipment-dup', v_rep1, 'rep'
    );
    v_inv_dup := app.accept_vendor_assignment_invitation(v_inv_dup.id, v_inv_dup.record_version, v_rep1, 'rep');
    begin
      perform app.confirm_vendor_assignment(v_inv_dup.id, v_inv_dup.record_version, v_rep1, 'rep');
      raise exception 'assertion failed: expected already_assigned -- app.assign_resource itself (unmodified) still refuses a second whole-shipment vendor commit';
    exception
      when sqlstate '23514' then
        if sqlerrm not like 'already_assigned%' then raise; end if;
    end;
  end;
end $$;
