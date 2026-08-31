-- Real, executable test evidence for IAE-011 (Vendor API, Prompt 339) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration (supabase/migrations/
-- 20260804030000_create_intelligence_vendor_api.sql). Fresh, distinctive tenant
-- fixture (iaevendorapi/iaevendorapi2), fixture id range
-- 00000000-0000-0000-0000-000013xxxxxx.
--
-- The Commercial->Operations dependency chain (lead/prospect/opportunity/
-- quotation/job_order_handoff/job_order/shipment_order) needed only so a real,
-- FK-consistent app.vendor_assignment_invitations row exists to test against is
-- built via minimal, direct INSERT throughout -- mirroring scripts/db-tests/
-- ticketing-linked-records.sql's own disclosed precedent for this exact shape:
-- none of that upstream business logic is under test here, only that a real row
-- exists, owned by a real vendor, to link against. The RFQ/invitation chain
-- similarly uses a minimal direct-insert app.sourcing_requests(source_type=
-- 'proactive')/app.sourcing_candidates/app.rfqs/app.rfq_invitations fixture rather
-- than the full shortlisting pipeline scripts/db-tests/procurement-rfq.sql already
-- covers in full -- this file tests IAE-011's own new vendor-scope authority RPCs,
-- not RFQ issuance mechanics.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaevendorapi (tenant_admin with staff authority to create vendor keys, a plain PRC:View-only staff member with no admin authority) and a second tenant iaevendorapi2 (its own tenant_admin, for cross-tenant isolation). Two vendors in tenant1 (Alpha: fully active; Beta: left in draft, for vendor_not_active) and one active vendor in tenant2 (Gamma, for cross-tenant vendor lookup denial). A real RFQ invitation and a real vendor assignment invitation for Vendor Alpha.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000013000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000013000003';
  v_staff_role uuid;
  v_admin1_role uuid;
  v_admin2_role uuid;
  v_profile_alpha app.vendor_profiles;
  v_profile_beta app.vendor_profiles;
  v_profile_gamma app.vendor_profiles;
  v_sourcing_id uuid;
  v_candidate_id uuid;
  v_rfq_id uuid;
  v_invitation_id uuid;
  v_account_a uuid;
  v_lead uuid;
  v_prospect uuid;
  v_opportunity uuid;
  v_quotation uuid;
  v_handoff uuid;
  v_job_order uuid;
  v_shipment_id uuid := '00000000-0000-0000-0000-000013000099';
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaevendorapi.test'),
    (v_staff1, 'staff@iaevendorapi.test'),
    (v_admin2, 'admin@iaevendorapi2.test');

  perform app.provision_tenant('iaevendorapi', 'IaeVendorApi Co', 'idem-iaevendorapi', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaevendorapi');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaevendorapi2', 'IaeVendorApi Co 2', 'idem-iaevendorapi2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaevendorapi2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaevendorapi.test', 'IaeVendorApi Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaevendorapi.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');
  -- tenant_admin LAYER membership alone does not imply any module permission --
  -- a role assignment is always required (mirrors procurement-rfq.sql/procurement-
  -- vendor-assignment.sql's own identical admin fixture shape) since admin1 itself
  -- performs vendor profile setup below.
  v_admin1_role := (app.create_role(v_tenant1, 'IaeVendorApi Admin Role', 'full PRC set for vendor profile setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin1_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Approve')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin1_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_admin1, 'admin');

  perform app.invite_user(v_tenant1, v_staff1, 'staff@iaevendorapi.test', 'IaeVendorApi Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@iaevendorapi.test'), 'active', 'onboarded', 'tester');
  v_staff_role := (app.create_role(v_tenant1, 'IaeVendorApi Viewer', 'PRC:View only, no admin authority', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), v_staff1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaevendorapi2.test', 'IaeVendorApi2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaevendorapi2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');
  v_admin2_role := (app.create_role(v_tenant2, 'IaeVendorApi2 Admin Role', 'full PRC set for vendor profile setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin2_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Approve')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin2_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_admin2, 'admin');

  -- Vendor Alpha: fully active.
  v_profile_alpha := app.create_vendor_profile_draft(v_tenant1, 'PT IaeVendorApi Alpha', 'IVAA', 'PT', 'REG-IVA-A', 'logistics', 30, 'staff_created', 'idem-iva-vendor-alpha', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile_alpha.master_record_id, 'Ani Alpha', 'Ops', 'ani@ivaa.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile_alpha.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile_alpha.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile_alpha.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile_alpha from app.vendor_profiles where master_record_id = v_profile_alpha.master_record_id;
  v_profile_alpha := app.submit_vendor_profile_for_review(v_profile_alpha.master_record_id, v_profile_alpha.record_version, v_admin1, 'admin');
  v_profile_alpha := app.decide_vendor_profile_review(v_profile_alpha.master_record_id, v_profile_alpha.record_version, 'approve', null, v_admin1, 'admin');
  v_profile_alpha := app.activate_vendor_profile(v_profile_alpha.master_record_id, v_profile_alpha.record_version, v_admin1, 'admin');

  -- Vendor Beta: left in draft -- proves vendor_not_active.
  v_profile_beta := app.create_vendor_profile_draft(v_tenant1, 'PT IaeVendorApi Beta', 'IVAB', 'PT', 'REG-IVA-B', 'logistics', 30, 'staff_created', 'idem-iva-vendor-beta', v_admin1, 'admin');

  -- Vendor Gamma: active, in tenant2 -- cross-tenant isolation.
  v_profile_gamma := app.create_vendor_profile_draft(v_tenant2, 'PT IaeVendorApi Gamma', 'IVAG', 'PT', 'REG-IVA-G', 'logistics', 30, 'staff_created', 'idem-iva-vendor-gamma', v_admin2, 'admin');
  perform app.add_vendor_contact(v_profile_gamma.master_record_id, 'Gita Gamma', 'Ops', 'gita@ivag.test', '0813', true, v_admin2, 'admin');
  perform app.add_vendor_address(v_profile_gamma.master_record_id, 'legal', 'Jl. Thamrin 3', 'Jakarta', 'DKI Jakarta', '10240', 'Indonesia', v_admin2, 'admin');
  perform app.add_vendor_service(v_profile_gamma.master_record_id, 'ocean_freight', v_admin2, 'admin');
  perform app.add_vendor_coverage(v_profile_gamma.master_record_id, 'Jakarta', 'Surabaya', v_admin2, 'admin');
  select * into v_profile_gamma from app.vendor_profiles where master_record_id = v_profile_gamma.master_record_id;
  v_profile_gamma := app.submit_vendor_profile_for_review(v_profile_gamma.master_record_id, v_profile_gamma.record_version, v_admin2, 'admin');
  v_profile_gamma := app.decide_vendor_profile_review(v_profile_gamma.master_record_id, v_profile_gamma.record_version, 'approve', null, v_admin2, 'admin');
  v_profile_gamma := app.activate_vendor_profile(v_profile_gamma.master_record_id, v_profile_gamma.record_version, v_admin2, 'admin');

  -- A real, minimal RFQ invitation for Vendor Alpha (direct insert -- see this
  -- file's own header for why the shortlisting pipeline is not re-derived).
  insert into app.sourcing_requests (id, tenant_id, source_type, service_type, origin_lane, destination_lane, status, idempotency_key, created_by)
  values (gen_random_uuid(), v_tenant1, 'proactive', 'ocean_freight', 'Jakarta', 'Surabaya', 'shortlisted', 'idem-iva-sourcing', 'tester')
  returning id into v_sourcing_id;
  insert into app.sourcing_candidates (id, tenant_id, sourcing_request_id, vendor_master_id, eligible, shortlisted, shortlist_reason, shortlisted_by, shortlisted_at)
  values (gen_random_uuid(), v_tenant1, v_sourcing_id, v_profile_alpha.master_record_id, true, true, 'best coverage', 'tester', now())
  returning id into v_candidate_id;
  insert into app.rfqs (id, tenant_id, sourcing_request_id, rfq_number, requirements_snapshot, service_type, origin_lane, destination_lane, status, issued_at, response_deadline_at, idempotency_key, created_by)
  values (gen_random_uuid(), v_tenant1, v_sourcing_id, 'RFQ-IVA-0001', '{}'::jsonb, 'ocean_freight', 'Jakarta', 'Surabaya', 'issued', now(), now() + interval '5 days', 'idem-iva-rfq', 'tester')
  returning id into v_rfq_id;
  insert into app.rfq_invitations (id, tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, status, invited_by)
  values (gen_random_uuid(), v_tenant1, v_rfq_id, v_candidate_id, v_profile_alpha.master_record_id, 'invited', 'tester')
  returning id into v_invitation_id;

  -- A real, minimal Commercial->Operations chain so one real, FK-consistent
  -- app.vendor_assignment_invitations row exists for Vendor Alpha.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant1, 'IaeVendorApi Shipper', 'fp-iva-shipper', '{}'::jsonb, 'tester')
  returning id into v_account_a;
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), v_tenant1, 'referral', 'Iva Lead Contact', 'iva-lead-contact@example.test', 'fp-iva-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), v_tenant1, v_lead, 'Iva Prospect Co', 'fp-iva-prospect', 'Iva Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), v_tenant1, v_prospect, 'Iva Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, v_tenant1, 'QUO-IVA-0001', v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, created_by)
  values (gen_random_uuid(), v_tenant1, v_quotation, v_account_a, '{"note": "fixture"}'::jsonb, 'hash-iva-1', v_admin1, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (id, tenant_id, job_number, source_handoff_id, quotation_id, account_id, customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot, status, owner_user_id, created_by)
  values (gen_random_uuid(), v_tenant1, 'JOB-IVA-0001', v_handoff, v_quotation, v_account_a, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'confirmed', v_admin1, 'tester')
  returning id into v_job_order;
  insert into app.shipment_orders (id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id, consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination, owner_user_id, created_by)
  values (v_shipment_id, v_tenant1, v_job_order, 'SHP-IVA-0001', 'idem-shp-iva-1', 'confirmed', v_account_a, '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya', v_admin1, 'tester');

  insert into app.vendor_assignment_invitations (id, tenant_id, shipment_order_id, vendor_master_id, status, created_by)
  values ('00000000-0000-0000-0000-000013000098', v_tenant1, v_shipment_id, v_profile_alpha.master_record_id, 'invited', 'tester');
end $$;

\echo '>> app.create_vendor_api_key: staff-only (tenant_admin) succeeds against a REAL active vendor with the fixed PRC:VendorPortal scope marker; a PRC:View-only staff member without admin authority is denied; a nonexistent vendor id gets vendor_not_found; a draft (not-yet-active) vendor gets vendor_not_active; a DIFFERENT tenant''s admin cannot create a key for this tenant''s own vendor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaevendorapi2');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000013000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000013000003';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_vendor_beta uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Beta');
  v_created record;
begin
  select * into v_created from app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Alpha Integration', null, 60, v_admin1, 'admin');
  if v_created.vendor_master_record_id <> v_vendor_alpha or v_created.scopes <> '["PRC:VendorPortal"]'::jsonb or v_created.raw_key is null then
    raise exception 'assertion failed: unexpected shape from create_vendor_api_key: %', to_jsonb(v_created);
  end if;

  begin
    perform app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Denied Attempt', null, null, v_staff1, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only staff member';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.create_vendor_api_key(v_tenant1, gen_random_uuid(), 'Nonexistent Vendor', null, null, v_admin1, 'admin');
    raise exception 'assertion failed: expected vendor_not_found for a nonexistent vendor id';
  exception when no_data_found then null;
  end;

  begin
    perform app.create_vendor_api_key(v_tenant1, v_vendor_beta, 'Draft Vendor', null, null, v_admin1, 'admin');
    raise exception 'assertion failed: expected vendor_not_active for a draft vendor';
  exception when check_violation then null;
  end;

  begin
    perform app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Cross Tenant Attempt', null, null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for tenant2''s own admin against tenant1''s own vendor';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: create_vendor_api_key -- staff-only creation against a REAL active vendor works with the fixed scope marker; a non-admin staff member, a nonexistent vendor, a draft vendor, and a cross-tenant admin are all denied';
end;
$$;

\echo '>> app.list_vendor_api_keys_for_tenant: staff-only, scoped to exactly the vendor-scoped keys in this tenant (never a staff/customer key), joined with the vendor''s own legal_name; a non-admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000013000002';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_keys app.api_keys[];
  v_row record;
  v_found boolean := false;
begin
  for v_row in select * from app.list_vendor_api_keys_for_tenant(v_tenant1, v_admin1) loop
    if v_row.vendor_master_record_id <> v_vendor_alpha then
      raise exception 'assertion failed: list_vendor_api_keys_for_tenant returned a key not scoped to a real vendor: %', to_jsonb(v_row);
    end if;
    if v_row.vendor_legal_name = 'PT IaeVendorApi Alpha' then
      v_found := true;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected to find the Alpha vendor key with its own legal_name joined in';
  end if;

  begin
    perform app.list_vendor_api_keys_for_tenant(v_tenant1, v_staff1);
    raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only staff member';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_vendor_api_keys_for_tenant is scoped to exactly the vendor-scoped keys in this tenant, joined with the vendor''s own legal_name; a non-admin is denied';
end;
$$;

\echo '>> app.authenticate_and_authorize_api_request: a vendor key resolves BOTH created_by_auth_user_id (the staff issuer) AND vendor_master_record_id (the DATA-scope binding) as two separate, non-conflated fields; forbidden_scope holds for a scope the key does not carry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_created record;
  v_auth record;
begin
  select * into v_created from app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Dispatch Proof Key', null, null, v_admin1, 'admin');

  select * into v_auth from app.authenticate_and_authorize_api_request(v_created.raw_key, 'PRC:VendorPortal');
  if v_auth.outcome <> 'ok' or v_auth.vendor_master_record_id <> v_vendor_alpha or v_auth.created_by_auth_user_id <> v_admin1 then
    raise exception 'assertion failed: expected outcome=ok, vendor_master_record_id=% (staff issuer created_by_auth_user_id=%), got %', v_vendor_alpha, v_admin1, to_jsonb(v_auth);
  end if;

  select * into v_auth from app.authenticate_and_authorize_api_request(v_created.raw_key, 'CPT:CustomerPortal');
  if v_auth.outcome <> 'forbidden_scope' then
    raise exception 'assertion failed: expected forbidden_scope for a scope this vendor key does not carry, got %', v_auth.outcome;
  end if;

  raise notice 'PASS: authenticate_and_authorize_api_request resolves a vendor key''s own vendor_master_record_id as a SEPARATE field from created_by_auth_user_id (the staff issuer), never conflated; forbidden_scope holds for an uncarried scope';
end;
$$;

\echo '>> app.get_rfq_for_vendor_api: real downstream dispatch proof -- the gateway-resolved vendor_master_record_id genuinely reaches this vendor''s own invitation; a mismatched vendor id and a nonexistent invitation id get the SAME rfq_invitation_not_found either way (anti-enumeration)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaevendorapi2');
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_vendor_gamma uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant2 and legal_name = 'PT IaeVendorApi Gamma');
  v_invitation_id uuid := (select id from app.rfq_invitations where tenant_id = v_tenant1 and vendor_master_id = v_vendor_alpha);
  v_rfq record;
begin
  select * into v_rfq from app.get_rfq_for_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id);
  if v_rfq.rfq_invitation_id <> v_invitation_id or v_rfq.invitation_status <> 'invited' or v_rfq.rfq_status <> 'issued' then
    raise exception 'assertion failed: unexpected rfq shape from get_rfq_for_vendor_api: %', to_jsonb(v_rfq);
  end if;

  begin
    perform app.get_rfq_for_vendor_api(v_tenant1, v_vendor_gamma, v_invitation_id);
    raise exception 'assertion failed: expected rfq_invitation_not_found for a vendor with zero relationship to this invitation';
  exception when no_data_found then null;
  end;

  begin
    perform app.get_rfq_for_vendor_api(v_tenant1, v_vendor_alpha, gen_random_uuid());
    raise exception 'assertion failed: expected rfq_invitation_not_found for a nonexistent invitation id';
  exception when no_data_found then null;
  end;

  raise notice 'PASS: get_rfq_for_vendor_api reaches this vendor''s own real invitation end to end; a mismatched vendor and a nonexistent invitation id both get the same rfq_invitation_not_found, never disclosing which';
end;
$$;

\echo '>> app.submit_rfq_response_via_vendor_api: a real vendor submits a response into the SAME app.rfq_responses table app.submit_rfq_response already writes into; a mismatched vendor is denied; idempotent replay returns the SAME row; a conflicting replay raises idempotency_key_conflict; capture_mode=vendor_api, actor_auth_user_id is null'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaevendorapi2');
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_vendor_gamma uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant2 and legal_name = 'PT IaeVendorApi Gamma');
  v_invitation_id uuid := (select id from app.rfq_invitations where tenant_id = v_tenant1 and vendor_master_id = v_vendor_alpha);
  v_response app.rfq_responses;
  v_replay app.rfq_responses;
begin
  v_response := app.submit_rfq_response_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 'USD', 15000.00, now() + interval '10 days', 21, '{"note": "best rate"}'::jsonb, true, 'idem-iva-response-1');
  if v_response.capture_mode <> 'vendor_api' or v_response.actor_auth_user_id is not null or v_response.actor_label <> 'Vendor API' or v_response.total_amount <> 15000.00 then
    raise exception 'assertion failed: unexpected rfq_response shape: %', to_jsonb(v_response);
  end if;

  begin
    perform app.submit_rfq_response_via_vendor_api(v_tenant1, v_vendor_gamma, v_invitation_id, 'USD', 9999.00, now() + interval '10 days', 21, '{}'::jsonb, true, 'idem-iva-response-cross');
    raise exception 'assertion failed: expected rfq_invitation_not_found for a vendor with zero relationship to this invitation';
  exception when no_data_found then null;
  end;

  v_replay := app.submit_rfq_response_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 'USD', 15000.00, now() + interval '10 days', 21, '{"note": "best rate"}'::jsonb, true, 'idem-iva-response-1');
  if v_replay.id <> v_response.id then
    raise exception 'assertion failed: expected the idempotent replay to return the identical row';
  end if;

  begin
    perform app.submit_rfq_response_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 'USD', 20000.00, now() + interval '10 days', 21, '{}'::jsonb, true, 'idem-iva-response-1');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different amount';
  exception when unique_violation then null;
  end;

  raise notice 'PASS: submit_rfq_response_via_vendor_api writes a real, vendor-scope-authorized response into the SAME app.rfq_responses table -- a mismatched vendor is denied, replay is idempotent, a conflicting replay is rejected, capture_mode/actor shape is correct';
end;
$$;

\echo '>> app.submit_rfq_response_via_vendor_api: a late response (past response_deadline_at) is rejected outright -- a vendor key holds no PRC:Override authority to silently capture it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_sourcing_id uuid;
  v_candidate_id uuid;
  v_rfq_id uuid;
  v_invitation_id uuid;
begin
  insert into app.sourcing_requests (id, tenant_id, source_type, service_type, origin_lane, destination_lane, status, idempotency_key, created_by)
  values (gen_random_uuid(), v_tenant1, 'proactive', 'ocean_freight', 'Jakarta', 'Surabaya', 'shortlisted', 'idem-iva-sourcing-late', 'tester')
  returning id into v_sourcing_id;
  insert into app.sourcing_candidates (id, tenant_id, sourcing_request_id, vendor_master_id, eligible, shortlisted, shortlist_reason, shortlisted_by, shortlisted_at)
  values (gen_random_uuid(), v_tenant1, v_sourcing_id, v_vendor_alpha, true, true, 'best coverage', 'tester', now())
  returning id into v_candidate_id;
  insert into app.rfqs (id, tenant_id, sourcing_request_id, rfq_number, requirements_snapshot, service_type, origin_lane, destination_lane, status, issued_at, response_deadline_at, idempotency_key, created_by)
  values (gen_random_uuid(), v_tenant1, v_sourcing_id, 'RFQ-IVA-LATE-0001', '{}'::jsonb, 'ocean_freight', 'Jakarta', 'Surabaya', 'issued', now() - interval '10 days', now() - interval '1 day', 'idem-iva-rfq-late', 'tester')
  returning id into v_rfq_id;
  insert into app.rfq_invitations (id, tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, status, invited_by)
  values (gen_random_uuid(), v_tenant1, v_rfq_id, v_candidate_id, v_vendor_alpha, 'invited', 'tester')
  returning id into v_invitation_id;

  begin
    perform app.submit_rfq_response_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 'USD', 15000.00, now() + interval '10 days', 21, '{}'::jsonb, true, 'idem-iva-response-late');
    raise exception 'assertion failed: expected rfq_response_deadline_passed for a response submitted after the deadline';
  exception when check_violation then
    if sqlerrm !~ 'rfq_response_deadline_passed' then raise; end if;
  end;

  raise notice 'PASS: a late RFQ response is rejected outright via the Vendor API -- no PRC:Override path exists for a vendor key';
end;
$$;

\echo '>> app.accept_vendor_assignment_invitation_via_vendor_api / decline_...: a real vendor accepts/declines its OWN invitation into the SAME app.vendor_assignment_invitations table the staff-only functions already write into; a mismatched vendor is denied; stale_version on a concurrent mismatch; decline requires a non-empty reason'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaevendorapi2');
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_vendor_gamma uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant2 and legal_name = 'PT IaeVendorApi Gamma');
  v_invitation_id uuid := '00000000-0000-0000-0000-000013000098';
  v_invitation app.vendor_assignment_invitations;
begin
  begin
    perform app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_gamma, v_invitation_id, 1);
    raise exception 'assertion failed: expected vendor_assignment_invitation_not_found for a vendor with zero relationship to this invitation';
  exception when no_data_found then null;
  end;

  begin
    perform app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 99);
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception when serialization_failure then null;
  end;

  v_invitation := app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, 1);
  if v_invitation.status <> 'accepted' then
    raise exception 'assertion failed: expected status=accepted, got %', v_invitation.status;
  end if;

  begin
    perform app.decline_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, v_invitation.record_version, '');
    raise exception 'assertion failed: expected reason_required for an empty decline reason';
  exception when check_violation then
    if sqlerrm !~ 'reason_required' then raise; end if;
  end;

  begin
    perform app.decline_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_invitation_id, v_invitation.record_version, 'changed my mind');
    raise exception 'assertion failed: expected invalid_transition -- an already-accepted invitation cannot be declined';
  exception when check_violation then
    if sqlerrm !~ 'invalid_transition' then raise; end if;
  end;

  raise notice 'PASS: accept/decline_vendor_assignment_invitation_via_vendor_api write into the SAME app.vendor_assignment_invitations table -- a mismatched vendor and a stale version are both denied, decline requires a real reason';
end;
$$;

\echo '>> app.rotate_api_key / app.revoke_api_key (PLT-129, extended by IAE-010 then IAE-011): a rotated vendor key carries vendor_master_record_id forward; staff can revoke a vendor key; a cross-tenant admin cannot manage this tenant''s own vendor key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_admin2 uuid := '00000000-0000-0000-0000-000013000003';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_created record;
  v_rotated record;
  v_revoked app.api_keys;
begin
  select * into v_created from app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Rotate Proof Key', null, null, v_admin1, 'admin');

  begin
    -- ISS-2026-167 (Track B Batch 1): v_admin2 has no relationship at all to
    -- v_tenant1 (a genuine stranger, not merely an unauthorized same-tenant
    -- member), so this now raises the generic api_key_not_found -- closing
    -- the cross-tenant existence oracle app.rotate_api_key's own error text
    -- previously leaked (a distinct insufficient_authority naming the real
    -- tenant_id). A same-tenant member lacking manage authority still gets
    -- the specific insufficient_authority error (see api-key-webhook.sql's
    -- own regression for that case) -- not a leak, since they already
    -- belong to that tenant.
    perform app.rotate_api_key(v_created.id, 0, v_admin2, 'admin2');
    raise exception 'assertion failed: expected api_key_not_found for a genuinely cross-tenant admin against tenant1''s own vendor key';
  exception when no_data_found then null;
  end;

  select * into v_rotated from app.rotate_api_key(v_created.id, 0, v_admin1, 'admin');
  if v_rotated.id = v_created.id then
    raise exception 'assertion failed: expected rotation to mint a genuinely new key row';
  end if;
  if (select vendor_master_record_id from app.api_keys where id = v_rotated.id) <> v_vendor_alpha then
    raise exception 'assertion failed: expected the rotated key to carry vendor_master_record_id forward';
  end if;

  select * into v_revoked from app.revoke_api_key(v_rotated.id, 'self-cleanup', v_admin1, 'admin');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected the rotated key to be genuinely revocable by tenant1''s own admin, got status=%', v_revoked.status;
  end if;

  raise notice 'PASS: a rotated vendor key carries vendor_master_record_id forward; staff can revoke a vendor key; a cross-tenant admin is denied';
end;
$$;

\echo '>> app.api_keys_customer_vendor_mutually_exclusive_check: a single key row can never be BOTH a customer key and a vendor key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_account uuid;
begin
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant1, 'Iva Malformed Account', 'fp-iva-malformed', '{}'::jsonb, 'tester')
  returning id into v_account;

  begin
    insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id, vendor_master_record_id)
    values (v_tenant1, 'Malformed Key', 'cgk_malformed2', 'deadbeef2', '["CPT:CustomerPortal"]'::jsonb, '00000000-0000-0000-0000-000013000001', v_account, '00000000-0000-0000-0000-000013000001', v_vendor_alpha);
    raise exception 'assertion failed: expected api_keys_customer_vendor_mutually_exclusive_check to reject a key scoped to both a customer account and a vendor';
  exception
    when check_violation then null;
  end;

  raise notice 'PASS: api_keys_customer_vendor_mutually_exclusive_check rejects a key scoped to both a customer account and a vendor';
end;
$$;

\echo '>> live forged-session proof (request.jwt.claims + set role authenticated): the REAL tenant_admin, acting through a genuine authenticated session (not the connecting superuser), can create and revoke a vendor key end to end'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_admin1 uuid := '00000000-0000-0000-0000-000013000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000013000002';
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_created record;
  v_revoked app.api_keys;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000013000001", "role": "authenticated"}', false);
  set role authenticated;

  select * into v_created from app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Forged Session Key', null, null, v_admin1, 'admin');
  select * into v_revoked from app.revoke_api_key(v_created.id, 'forged-session cleanup', v_admin1, 'admin');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected a genuine authenticated session to revoke its own just-created vendor key';
  end if;

  -- ATW-032: the same genuine session may not claim to act as a DIFFERENT identity.
  begin
    perform app.create_vendor_api_key(v_tenant1, v_vendor_alpha, 'Impersonation Attempt', null, null, v_staff1, 'staff');
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_admin1, v_staff1;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: a real forged authenticated session, not the connecting superuser, creates and revokes its own vendor key end to end; the same session cannot claim a different identity';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-011 function'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'create_vendor_api_key', 'list_vendor_api_keys_for_tenant', 'get_rfq_for_vendor_api',
    'submit_rfq_response_via_vendor_api', 'accept_vendor_assignment_invitation_via_vendor_api',
    'decline_vendor_assignment_invitation_via_vendor_api'
  ];
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-011 function';
end;
$$;

\echo '>> ISS-2026-208: a lost-response retry of accept/decline replays to the row instead of a 409, and ONLY on an exact replay signature -- a genuinely stale client still gets stale_version'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaevendorapi');
  v_vendor_alpha uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT IaeVendorApi Alpha');
  v_base_ship uuid := (select shipment_order_id from app.vendor_assignment_invitations where id = '00000000-0000-0000-0000-000013000098');
  v_accept_id uuid := '00000000-0000-0000-0000-000013000208';
  v_decline_id uuid := '00000000-0000-0000-0000-000013000209';
  v_stale_id uuid := '00000000-0000-0000-0000-000013000210';
  v_ship_accept uuid := '00000000-0000-0000-0000-000013000308';
  v_ship_decline uuid := '00000000-0000-0000-0000-000013000309';
  v_ship_stale uuid := '00000000-0000-0000-0000-000013000310';
  v_first app.vendor_assignment_invitations;
  v_replay app.vendor_assignment_invitations;
  v_audit_count integer;
  v_failed boolean;
begin
  -- One shipment per invitation: vendor_assignment_invitations_one_live_per_shipment_unique
  -- permits a single invited/accepted invitation per (tenant, shipment), and the fixture's own
  -- shipment already holds one. Each new shipment is copied from that same real row rather than
  -- invented, so nothing here depends on values this test made up.
  insert into app.shipment_orders (id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id, consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination, owner_user_id, created_by)
  select v.new_id, s.tenant_id, s.job_order_id, v.number, v.idem, s.status, s.shipper_account_id, s.consignee_snapshot, s.cargo_service_snapshot, s.service_type, s.mode, s.origin, s.destination, s.owner_user_id, 'tester'
  from app.shipment_orders s
  cross join (values
    (v_ship_accept, 'SHP-IVA-0208A', 'idem-shp-iva-208a'),
    (v_ship_decline, 'SHP-IVA-0208B', 'idem-shp-iva-208b'),
    (v_ship_stale, 'SHP-IVA-0208C', 'idem-shp-iva-208c')
  ) as v(new_id, number, idem)
  where s.id = v_base_ship;

  insert into app.vendor_assignment_invitations (id, tenant_id, shipment_order_id, vendor_master_id, status, created_by) values
    (v_accept_id, v_tenant1, v_ship_accept, v_vendor_alpha, 'invited', 'tester'),
    (v_decline_id, v_tenant1, v_ship_decline, v_vendor_alpha, 'invited', 'tester'),
    (v_stale_id, v_tenant1, v_ship_stale, v_vendor_alpha, 'invited', 'tester');

  -- The scenario the entry live-forced: accept once (1 -> 2), then replay the ORIGINAL
  -- expected_version, exactly as a client would after losing the first response.
  v_first := app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_accept_id, 1);
  if v_first.status <> 'accepted' or v_first.record_version <> 2 then
    raise exception 'assertion failed: expected the first accept to land as accepted/version 2, got %/%', v_first.status, v_first.record_version;
  end if;

  v_replay := app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_accept_id, 1);
  if v_replay.id <> v_first.id or v_replay.status <> 'accepted' or v_replay.record_version <> v_first.record_version then
    raise exception 'assertion failed: expected the retry to replay the SAME accepted row unchanged, got id=% status=% version=%', v_replay.id, v_replay.status, v_replay.record_version;
  end if;

  -- The replay must not claim a second acceptance. Nothing was accepted twice, and a trail
  -- saying otherwise is worse than one saying nothing -- so it is recorded, and labelled.
  select count(*) into v_audit_count from app.audit_logs
  where action = 'accept_vendor_assignment_invitation_via_vendor_api' and resource_id = v_accept_id
    and (after_value ->> 'idempotent_replay')::boolean is true;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one audit event tagged idempotent_replay for the retried accept, found %', v_audit_count;
  end if;

  -- Decline replays on the same signature, plus the stored reason matching the retried one.
  v_first := app.decline_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_decline_id, 1, 'no capacity that week');
  v_replay := app.decline_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_decline_id, 1, 'no capacity that week');
  if v_replay.status <> 'declined' or v_replay.record_version <> v_first.record_version or v_replay.decline_reason <> 'no capacity that week' then
    raise exception 'assertion failed: expected the decline retry to replay the same declined row, got %/%/%', v_replay.status, v_replay.record_version, v_replay.decline_reason;
  end if;

  -- A DIFFERENT reason is a different request, not a retry of this one. Treating it as a replay
  -- would silently discard what the caller actually said, so it must still be refused.
  begin
    perform app.decline_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_decline_id, 1, 'actually, the price was wrong');
    v_failed := false;
  exception when serialization_failure then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected stale_version when a decline retry carries a DIFFERENT reason -- that is a different request, not a replay';
  end if;

  -- And the case the narrow signature exists to protect: a client whose view is stale by MORE
  -- than their own write. "Already accepted" alone would wrongly tell them everything is fine.
  perform app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_stale_id, 1);
  update app.vendor_assignment_invitations set decline_reason = null where id = v_stale_id;  -- a second, unrelated bump: version is now 3
  begin
    perform app.accept_vendor_assignment_invitation_via_vendor_api(v_tenant1, v_vendor_alpha, v_stale_id, 1);
    v_failed := false;
  exception when serialization_failure then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected stale_version for a client stale by more than their own write -- the replay signature must be exactly one version, never merely "already accepted"';
  end if;

  raise notice 'PASS: ISS-2026-208 -- accept/decline replay a lost-response retry to the row, and only on an exact signature; a different decline reason and a doubly-stale client both still get stale_version';
end;
$$;

\echo '>> vendor-api.sql: ALL PASSED'
