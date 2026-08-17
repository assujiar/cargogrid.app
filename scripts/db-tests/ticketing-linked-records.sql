-- Real, executable test evidence for HRT-292 (Typed Ticket-Linked Records,
-- CG-S12-HRT-020). Run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql).
--
-- Self-contained: own two-tenant/employee/role/queue/category fixture, own
-- fresh, unclaimed UUID range (00000000-0000-0000-0000-0000002921xx/22xx).
-- Tenant slugs `lnk1`/`lnk2` (grep-verified unclaimed).
--
-- Covers, live: the registry drift-gate (CHECK constraint vs. app.
-- ticket_link_entity_types()); happy-path link of all six entity types on an
-- internal ticket by an authorized staff actor; duplicate-link idempotency
-- (natural key, no duplicate row, one ledger row); unlink (reason required,
-- stale-version rejection, real removal, a fresh re-link creates a NEW row);
-- cross-tenant/forged-id rejection collapsing to the SAME record_not_eligible
-- as a genuinely unauthorized-but-real candidate; structural rejections
-- (unsupported entity_type, invalid relationship) staying DISTINCT from the
-- anti-enumerating bucket; a domain-denied ticket-staff actor (queue member,
-- no OPS/FIN/PRC role) linking customer/user (no permission gate) but denied
-- shipment/invoice/warehouse/vendor; the customer channel's narrower
-- registry (shipment/invoice/warehouse/customer, never vendor/user) and its
-- own account-owner-scope narrowing (a DIFFERENT customer account is denied
-- the SAME shipment/invoice); the helpdesk channel's support-grant gate (a
-- Supreme Admin with no grant is denied identically to not-eligible; the
-- SAME Supreme Admin with a live PLT-115 grant succeeds); revoked warehouse
-- eligibility making a link show unavailable without deleting the link row;
-- a hard-deleted source warehouse doing the same; a live re-read never
-- trusting the stale captured snapshot over a fresh source-table change;
-- the staff-only ledger (denials/access recorded); cross-tenant isolation
-- via RPC and raw-table RLS; actor_holds_customer_user_layer exclusion;
-- schema-privilege defense in depth (anon has zero access).

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_hr_role uuid; v_hr_draft app.role_versions;
  v_domain_role uuid; v_domain_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_queue uuid; v_category uuid;
  v_account_a uuid; v_account_b uuid;
  v_lead uuid; v_prospect uuid; v_opportunity uuid; v_quotation uuid; v_handoff uuid;
  v_job_order uuid; v_eval uuid; v_billing_handoff uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000292101', 'admin@lnk1.test'),
    ('00000000-0000-0000-0000-000000292102', 'staff1@lnk1.test'),
    ('00000000-0000-0000-0000-000000292103', 'req1@lnk1.test'),
    ('00000000-0000-0000-0000-000000292110', 'customer1@lnk1.test'),
    ('00000000-0000-0000-0000-000000292111', 'customer2@lnk1.test'),
    ('00000000-0000-0000-0000-000000292190', 'supreme@platform-lnk.test'),
    ('00000000-0000-0000-0000-000000292201', 'admin@lnk2.test');

  perform app.provision_tenant('lnk1', 'Link Co 1', 'idem-lnk1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'lnk1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('lnk2', 'Link Co 2', 'idem-lnk2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'lnk2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-LNK1', 'Lnk1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-LNK1', 'Lnk1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  -- admin's own app.users.org_unit_id is set to v_company (5th arg) --
  -- required for app.can_access_record's org-scope branch (the SAME branch
  -- app.shipment_orders/app.warehouses' own RLS policies use) to admit
  -- admin as a shipment/warehouse viewer -- never relying on a bypass.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000292101', 'admin@lnk1.test', 'Lnk1 Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@lnk1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000292101', 'tenant_admin', v_tenant1, null, 'tester');

  -- staff1 deliberately gets NO org_unit_id and NO OPS/FIN/PRC role -- a
  -- real ticket-staff actor (queue member) who is NOT independently
  -- domain-authorized for shipment/invoice/warehouse/vendor (section 9).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000292102', 'staff1@lnk1.test', 'Lnk1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@lnk1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000292103', 'req1@lnk1.test', 'Lnk1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'req1@lnk1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000292201', 'admin@lnk2.test', 'Lnk2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@lnk2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000292201', 'tenant_admin', v_tenant2, null, 'tester');
  declare
    v_tkt2_role uuid; v_tkt2_draft app.role_versions;
  begin
    v_tkt2_role := (app.create_role(v_tenant2, 'Ticket Admin 2', 'TKT Edit', 'tester')).id;
    v_tkt2_draft := app.create_role_version(v_tkt2_role, 'tester');
    perform app.set_role_version_permissions(v_tkt2_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action = 'Edit'), 'tester');
    perform app.publish_role_version(v_tkt2_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_tkt2_role and status = 'published'), '00000000-0000-0000-0000-000000292201', '00000000-0000-0000-0000-000000292201', 'tester');
  end;

  -- customer1/customer2 need a real app.tenant_user_identities linkage
  -- (via app.invite_user, the same PLT-107/108 composite-FK discipline
  -- every principal_membership requires) before app.grant_principal_
  -- membership can attach their customer_user layer below.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000292110', 'customer1@lnk1.test', 'Lnk1 Customer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer1@lnk1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000292111', 'customer2@lnk1.test', 'Lnk1 Customer Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer2@lnk1.test'), 'active', 'onboarded', 'tester');

  -- Platform-global Supreme Admin -- helpdesk channel staff/support-grant
  -- fixture (section 8). Holds NO tenant membership of any kind in lnk1.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000292190', 'supreme_admin', null, null, 'tester');

  -- HR role: needed only to drive the employee-lifecycle fixture below
  -- (unrelated to this capability itself, mirrors every prior ticketing
  -- checkpoint's own fixture precedent).
  v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000292101', '00000000-0000-0000-0000-000000292101', 'tester');

  -- TKT:Edit/Assign -- admin only (staff1 relies on queue membership alone
  -- for is_ticket_staff, decision matching section 9's own point).
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Assign', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Assign')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000292101', '00000000-0000-0000-0000-000000292101', 'tester');

  -- OPS:Create/Edit (warehouse create + eligibility grant/revoke),
  -- FIN:View (invoice), PRC:Create/View (vendor) -- admin only, the
  -- "domain-authorized staff" actor every happy-path assertion below uses.
  v_domain_role := (app.create_role(v_tenant1, 'Domain Admin', 'OPS/FIN/PRC for HRT-292 fixture', 'tester')).id;
  v_domain_draft := app.create_role_version(v_domain_role, 'tester');
  perform app.set_role_version_permissions(v_domain_draft.id, array(
    select id from app.permissions where (resource_module_code = 'OPS' and action in ('Create', 'Edit'))
      or (resource_module_code = 'FIN' and action = 'View')
      or (resource_module_code = 'PRC' and action in ('Create', 'View'))
  ), 'tester');
  perform app.publish_role_version(v_domain_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_domain_role and status = 'published'), '00000000-0000-0000-0000-000000292101', '00000000-0000-0000-0000-000000292101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lnk1 Admin', 'full_time', 'adminwork@lnk1.test', 'adminp@lnk1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Admin', null, (select id from app.users where email = 'admin@lnk1.test'), null, 'hr_created', 'idem-admin-lnk1', '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@lnk1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@lnk1.test'), 1, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@lnk1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@lnk1.test'), 3, '00000000-0000-0000-0000-000000292101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lnk1 Staff One', 'full_time', 'staff1work@lnk1.test', 'staff1p@lnk1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff1@lnk1.test'), null, 'hr_created', 'idem-staff1-lnk1', '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@lnk1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@lnk1.test'), 1, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@lnk1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@lnk1.test'), 3, '00000000-0000-0000-0000-000000292101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lnk1 Requester One', 'full_time', 'req1work@lnk1.test', 'req1p@lnk1.test', '0900000003', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Staff', null, (select id from app.users where email = 'req1@lnk1.test'), null, 'hr_created', 'idem-req1-lnk1', '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@lnk1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@lnk1.test'), 1, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@lnk1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000292101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@lnk1.test'), 3, '00000000-0000-0000-0000-000000292101', 'tester');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'SUP', 'Support', 'Support queue', '00000000-0000-0000-0000-000000292101', 'admin')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'GENERAL', 'General Issue', v_queue, '00000000-0000-0000-0000-000000292101', 'admin')).id;
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@lnk1.test'), '00000000-0000-0000-0000-000000292101', 'admin');
  perform app.set_ticket_category_customer_visibility(v_category, true, '00000000-0000-0000-0000-000000292101', 'admin');
  perform app.set_ticket_category_helpdesk_visibility(v_category, true, '00000000-0000-0000-0000-000000292101', 'admin');

  -- Two customer accounts, two customer_user principals -- account_b is
  -- used ONLY to prove customer2 (its own principal) is denied account_a's
  -- shipment/invoice (section 7), never to build a second deep chain.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lnk Customer A', 'fp-lnk1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lnk Customer B', 'fp-lnk1-b', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_b;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000292110', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000292111', 'customer_user', v_tenant1, v_account_b::text, 'tester');

  -- Deep Commercial->Operations->Finance dependency chain, direct INSERT
  -- throughout (mirrors this migration's own accounts-direct-insert
  -- precedent, HRT-291): none of leads/prospects/opportunities/quotations/
  -- job_order_handoffs/job_orders/billing_readiness_* business logic is
  -- under test here -- only that a real, FK-consistent shipment/invoice row
  -- exists, owned by account_a, to link against.
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), v_tenant1, 'referral', 'Lnk Lead Contact', 'lnk-lead-contact@example.test', 'fp-lnk1-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), v_tenant1, v_lead, 'Lnk Prospect Co', 'fp-lnk1-prospect', 'Lnk Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), v_tenant1, v_prospect, 'Lnk Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, v_tenant1, 'QUO-LNK-0001', v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), v_tenant1, v_quotation, v_account_a, '{"note": "fixture"}'::jsonb, 'hash-lnk-1', '00000000-0000-0000-0000-000000292101', v_company, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant1, 'JOB-LNK-0001', v_handoff, v_quotation, v_account_a,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    'confirmed', '00000000-0000-0000-0000-000000292101', v_company, 'tester'
  )
  returning id into v_job_order;

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    owner_user_id, org_unit_id, created_by
  ) values (
    '00000000-0000-0000-0000-000000292199', v_tenant1, v_job_order, 'SHP-LNK-0001', 'idem-shp-lnk-1', 'confirmed', v_account_a,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Port A', 'Port B',
    '00000000-0000-0000-0000-000000292101', v_company, 'tester'
  );

  insert into app.billing_readiness_evaluations (id, tenant_id, job_order_id, evaluated_status, blockers, evidence, evaluated_by_auth_user_id)
  values (gen_random_uuid(), v_tenant1, v_job_order, 'ready', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000292101')
  returning id into v_eval;
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (gen_random_uuid(), v_tenant1, v_job_order, v_eval, 'idem-br-lnk-1', '00000000-0000-0000-0000-000000292101', 'admin')
  returning id into v_billing_handoff;
  -- Tier C review fix (Batch 3 close): status is 'issued', not 'approved' --
  -- CPL-311 (Phase 8, landed after this fixture was originally authored)
  -- establishes that only status IN ('issued', 'void') is ever
  -- customer-portal-visible/customer-linkable; every existing assertion in
  -- this file that reads this fixture (sections 2, 7) only ever asserts on
  -- label/detail/successful-link, never on the status value itself, so this
  -- change does not alter any existing assertion's outcome -- it only makes
  -- the fixture consistent with a real business rule that did not exist
  -- when 'approved' was originally chosen.
  insert into app.finance_invoices (
    id, tenant_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, status, subtotal_amount, tax_amount, created_by
  ) values (
    '00000000-0000-0000-0000-000000292198', v_tenant1, 'INV-LNK-0001', v_account_a, v_job_order, v_billing_handoff,
    'USD', 'issued', 1000, 100, 'tester'
  );
  -- A SECOND, pre-issuance invoice off the SAME job_order (a second handoff
  -- row, its own idempotency_key -- billing_readiness_handoffs' own unique
  -- constraint is (tenant_id, job_order_id, idempotency_key), not
  -- per-job_order-singleton) -- new fixture, added by this same Tier C
  -- review fix, to prove the negative: a customer_user must NOT be able to
  -- see or link this one (section 7 below).
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (gen_random_uuid(), v_tenant1, v_job_order, v_eval, 'idem-br-lnk-2-draft', '00000000-0000-0000-0000-000000292101', 'admin')
  returning id into v_billing_handoff;
  insert into app.finance_invoices (
    id, tenant_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, status, subtotal_amount, tax_amount, created_by
  ) values (
    '00000000-0000-0000-0000-000000292197', v_tenant1, null, v_account_a, v_job_order, v_billing_handoff,
    'USD', 'draft', 500, 0, 'tester'
  );

  -- Two warehouses: WH-LNK1 (the real, kept-alive candidate) and
  -- WH-LNK1-DEL (a throwaway, no zones ever attached, hard-deleted in
  -- section 11 to prove a genuinely deleted source shows unavailable).
  perform app.create_warehouse(v_tenant1, v_company, 'WH-LNK1', 'Lnk Warehouse One', null, 'Asia/Jakarta', null, array['fcl']::text[], '00000000-0000-0000-0000-000000292101', 'admin');
  perform app.create_warehouse(v_tenant1, v_company, 'WH-LNK1-DEL', 'Lnk Warehouse To Delete', null, 'Asia/Jakarta', null, array['fcl']::text[], '00000000-0000-0000-0000-000000292101', 'admin');
  perform app.grant_warehouse_customer_eligibility((select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1'), v_account_a, '00000000-0000-0000-0000-000000292101', 'admin');

  perform app.create_vendor_profile_draft(v_tenant1, 'Lnk Vendor One', null, null, null, null, 30, 'staff_created', 'idem-lnk-vendor-1', '00000000-0000-0000-0000-000000292101', 'admin');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_a=%, account_b=%, job_order=%', v_tenant1, v_tenant2, v_queue, v_category, v_account_a, v_account_b, v_job_order;
end;
$$;

\echo '>> 1. registry drift-gate: app.ticket_link_entity_types()/app.ticket_link_customer_safe_entity_types() stay set-equal with the live CHECK constraint (proven by real INSERT attempts, not by parsing pg_constraint internals) and with each other (subset)'
do $$
declare
  v_full text[] := app.ticket_link_entity_types();
  v_safe text[] := app.ticket_link_customer_safe_entity_types();
  v_type text;
  v_ok boolean;
begin
  if v_full <> array['shipment', 'invoice', 'warehouse', 'vendor', 'customer', 'user']::text[] then
    raise exception 'FAIL: app.ticket_link_entity_types() drifted from the documented six-value registry: %', v_full;
  end if;
  if not (v_safe <@ v_full) then
    raise exception 'FAIL: app.ticket_link_customer_safe_entity_types() is not a subset of the full registry';
  end if;
  if v_safe && array['vendor', 'user']::text[] then
    raise exception 'FAIL: customer-safe registry must never include vendor or user (decision 7)';
  end if;

  -- Real, executable equivalent of the drift-gate: every value the
  -- registry function returns must actually be accepted by the live
  -- ticket_links_entity_type_check CHECK constraint (a real INSERT/
  -- ROLLBACK per value, inside its own subtransaction so one genuine
  -- failure does not abort this whole block).
  foreach v_type in array v_full loop
    v_ok := true;
    begin
      insert into app.ticket_links (tenant_id, ticket_id, entity_type, entity_id, created_by_auth_user_id, created_by_role, safe_snapshot)
      values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', v_type, gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'staff', '{}'::jsonb);
    exception
      when check_violation then v_ok := false;
      when foreign_key_violation then v_ok := true; -- the CHECK passed; only the (unrelated) FK to a fake tenant/ticket failed
    end;
    if not v_ok then
      raise exception 'FAIL: registry value % is rejected by ticket_links_entity_type_check -- drifted from the CHECK constraint', v_type;
    end if;
  end loop;

  begin
    insert into app.ticket_links (tenant_id, ticket_id, entity_type, entity_id, created_by_auth_user_id, created_by_role, safe_snapshot)
    values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'not_a_real_type', gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'staff', '{}'::jsonb);
    raise exception 'FAIL: a value outside the registry must be rejected by the CHECK constraint';
  exception
    when check_violation then null;
  end;

  raise notice 'PASS: registry function set matches the documented six values and the live CHECK constraint accepts exactly those six; customer-safe registry is a proper subset excluding vendor/user';
end;
$$;

\echo '>> 2. happy path: an authorized staff actor links all six entity types on an internal ticket; safe_snapshot is the bounded {label, detail, status} shape; list_ticket_links returns fresh, live data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_invoice_id uuid := '00000000-0000-0000-0000-000000292198';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'Lnk Vendor One');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_req1_user_id uuid := (select id from app.users where tenant_id = v_tenant1 and email = 'req1@lnk1.test');
  v_ticket app.tickets;
  v_link app.ticket_links;
  v_snapshot_keys text[];
  v_rows record;
  v_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, v_queue, 'normal', 'Internal Linking Test', 'body', 'idem-lnk-int-1', '00000000-0000-0000-0000-000000292103', 'req1');

  v_link := app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'primary_subject', v_admin, 'admin');
  select array_agg(key order by key) into v_snapshot_keys from jsonb_object_keys(v_link.safe_snapshot) as key;
  if v_snapshot_keys <> array['detail', 'label', 'status'] then
    raise exception 'FAIL: safe_snapshot must be exactly the bounded {label, detail, status} shape (C-07), got keys: %', v_snapshot_keys;
  end if;
  if (v_link.safe_snapshot ->> 'label') <> 'SHP-LNK-0001' then
    raise exception 'FAIL: shipment safe_snapshot label expected SHP-LNK-0001, got %', v_link.safe_snapshot ->> 'label';
  end if;

  perform app.link_ticket_record(v_ticket.id, 'invoice', v_invoice_id, 'related', v_admin, 'admin');
  perform app.link_ticket_record(v_ticket.id, 'warehouse', v_warehouse_id, 'related', v_admin, 'admin');
  perform app.link_ticket_record(v_ticket.id, 'vendor', v_vendor_id, 'related', v_admin, 'admin');
  perform app.link_ticket_record(v_ticket.id, 'customer', v_account_a, 'related', v_admin, 'admin');
  perform app.link_ticket_record(v_ticket.id, 'user', v_req1_user_id, 'context', v_admin, 'admin');

  select count(*) into v_count from app.list_ticket_links(v_ticket.id, v_admin);
  if v_count <> 6 then
    raise exception 'FAIL: expected 6 active links, got %', v_count;
  end if;

  for v_rows in select * from app.list_ticket_links(v_ticket.id, v_admin) loop
    if not v_rows.live_available then
      raise exception 'FAIL: link % (type %) expected live_available for an authorized staff actor, got false', v_rows.id, v_rows.entity_type;
    end if;
    if v_rows.label is null then
      raise exception 'FAIL: link % (%) expected a non-null live label', v_rows.id, v_rows.entity_type;
    end if;
  end loop;

  if (select label from app.list_ticket_links(v_ticket.id, v_admin) where entity_type = 'invoice') <> 'INV-LNK-0001' then
    raise exception 'FAIL: invoice link live label expected INV-LNK-0001';
  end if;
  if (select detail from app.list_ticket_links(v_ticket.id, v_admin) where entity_type = 'invoice') <> 'USD 1100.00' then
    raise exception 'FAIL: invoice link live detail expected USD 1100.00 (subtotal 1000 + tax 100), got %', (select detail from app.list_ticket_links(v_ticket.id, v_admin) where entity_type = 'invoice');
  end if;

  raise notice 'PASS: all six entity types linked; safe_snapshot bounded to {label, detail, status}; list_ticket_links returns fresh, live-authorized data for every row';
end;
$$;

\echo '>> 3. duplicate-link idempotency: the SAME natural key returns the existing row, never a duplicate, exactly one ledger row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_first app.ticket_links;
  v_second app.ticket_links;
  v_link_count integer;
  v_event_count integer;
begin
  select * into v_first from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'shipment' and status = 'active';
  v_second := app.link_ticket_record(v_ticket_id, 'shipment', v_shipment_id, 'primary_subject', v_admin, 'admin');
  if v_second.id <> v_first.id then
    raise exception 'FAIL: relinking the identical natural key must return the SAME row, got a different id';
  end if;

  select count(*) into v_link_count from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'shipment' and entity_id = v_shipment_id;
  if v_link_count <> 1 then
    raise exception 'FAIL: expected exactly 1 shipment link row after a duplicate link attempt, got %', v_link_count;
  end if;

  select count(*) into v_event_count from app.ticket_link_events where ticket_id = v_ticket_id and entity_type = 'shipment' and event_type = 'linked';
  if v_event_count <> 1 then
    raise exception 'FAIL: expected exactly 1 ''linked'' ledger row for the shipment link, got %', v_event_count;
  end if;

  raise notice 'PASS: duplicate link is a clean idempotent no-op -- one row, one ledger event';
end;
$$;

\echo '>> 4. unlink: reason required, stale-version rejection, real removal; a fresh re-link after removal creates a NEW row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'Lnk Vendor One');
  v_link app.ticket_links;
  v_relinked app.ticket_links;
begin
  select * into v_link from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'vendor' and status = 'active';

  begin
    perform app.unlink_ticket_record(v_link.id, v_link.record_version, null, v_admin, 'admin');
    raise exception 'FAIL: unlink must require a non-empty reason';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise exception 'FAIL: expected reason_required, got: %', sqlerrm; end if;
  end;

  begin
    perform app.unlink_ticket_record(v_link.id, v_link.record_version + 99, 'wrong version test', v_admin, 'admin');
    raise exception 'FAIL: unlink must reject a stale expected_version';
  exception when others then
    if sqlerrm not like 'stale_version%' then raise exception 'FAIL: expected stale_version, got: %', sqlerrm; end if;
  end;

  perform app.unlink_ticket_record(v_link.id, v_link.record_version, 'no longer relevant', v_admin, 'admin');
  if (select status from app.ticket_links where id = v_link.id) <> 'removed' then
    raise exception 'FAIL: link must be status=removed after a successful unlink';
  end if;
  if (select count(*) from app.ticket_link_events where link_id = v_link.id and event_type = 'unlinked') <> 1 then
    raise exception 'FAIL: expected exactly 1 ''unlinked'' ledger row';
  end if;

  v_relinked := app.link_ticket_record(v_ticket_id, 'vendor', v_vendor_id, 'related', v_admin, 'admin');
  if v_relinked.id = v_link.id then
    raise exception 'FAIL: a fresh re-link after removal must create a NEW row, not resurrect the removed one';
  end if;
  if (select count(*) from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'vendor') <> 2 then
    raise exception 'FAIL: expected 2 total vendor link rows (one removed, one active) after re-link';
  end if;

  raise notice 'PASS: unlink requires a real reason, rejects a stale version, genuinely removes without deleting the row, and a fresh re-link is a distinct new row preserving history';
end;
$$;

\echo '>> 5. cross-tenant/forged-id rejection collapses to the SAME record_not_eligible as a genuinely unauthorized-but-real candidate (C-05 anti-enumeration)'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'lnk2');
  v_category2 uuid;
  v_queue2 uuid;
  v_admin2 uuid := '00000000-0000-0000-0000-000000292201';
  v_admin1 uuid := '00000000-0000-0000-0000-000000292101';
  v_tenant1_shipment uuid := '00000000-0000-0000-0000-000000292199';
  v_forged_id uuid := '00000000-0000-0000-0000-00000029ffff';
  v_ticket2 app.tickets;
  v_msg1 text;
  v_msg2 text;
begin
  v_queue2 := (app.create_ticket_queue(v_tenant2, (app.create_org_unit(v_tenant2, 'company', null, 'CO-LNK2', 'Lnk2 Co', 'tester')).id, 'SUP2', 'Support', null, v_admin2, 'admin2')).id;
  v_category2 := (app.create_ticket_category(v_tenant2, 'GENERAL2', 'General', v_queue2, v_admin2, 'admin2')).id;
  perform app.set_ticket_category_helpdesk_visibility(v_category2, true, v_admin2, 'admin2');
  -- Helpdesk channel (not internal) -- avoids needing a real app.employees
  -- profile for admin2 (this section only needs a real, real-tenant2
  -- ticket the isolation check can attach to; app._is_tenant_helpdesk_
  -- authorized already admits a tenant_admin/TKT:Edit holder, which admin2
  -- is).
  v_ticket2 := app.create_helpdesk_ticket(v_tenant2, v_category2, 'normal', null, null, null, null, 'Tenant2 Linking Test', 'body', 'idem-lnk-t2-1', v_admin2, 'admin2');

  begin
    perform app.link_ticket_record(v_ticket2.id, 'shipment', v_tenant1_shipment, 'related', v_admin2, 'admin2');
    raise exception 'FAIL: linking another tenant''s real shipment id must be rejected';
  exception when others then
    v_msg1 := sqlerrm;
    if v_msg1 not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible for a cross-tenant id, got: %', v_msg1; end if;
  end;

  begin
    perform app.link_ticket_record(v_ticket2.id, 'shipment', v_forged_id, 'related', v_admin2, 'admin2');
    raise exception 'FAIL: linking a genuinely nonexistent id must be rejected';
  exception when others then
    v_msg2 := sqlerrm;
    if v_msg2 not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible for a forged id, got: %', v_msg2; end if;
  end;

  -- Same anti-enumerating error CLASS (errcode + message prefix), not
  -- necessarily byte-identical text -- both messages legitimately echo back
  -- the caller's own submitted id (mirrors app.get_customer_inventory_
  -- balance's own established shape, ATW-242, which does the same), so the
  -- real C-05 guarantee under test is that the CAUSE (cross-tenant vs.
  -- forged) is never distinguishable, never that two DIFFERENT ids somehow
  -- produce byte-identical text.
  if v_msg1 !~ '^record_not_eligible: no eligible shipment record exists for ' or v_msg2 !~ '^record_not_eligible: no eligible shipment record exists for ' then
    raise exception 'FAIL (C-05): a cross-tenant real id and a forged id must raise the SAME error class (record_not_eligible) -- got % vs %', v_msg1, v_msg2;
  end if;

  if exists (select 1 from app.search_ticket_link_candidates(v_ticket2.id, 'shipment', null, v_admin2, 20) where entity_id = v_tenant1_shipment) then
    raise exception 'CRITICAL: tenant2''s candidate search surfaced tenant1''s shipment';
  end if;

  raise notice 'PASS: cross-tenant and forged ids raise the byte-identical record_not_eligible; candidate search never surfaces a cross-tenant row';
end;
$$;

\echo '>> 6. structural rejections stay DISTINCT from the anti-enumerating bucket: unsupported entity_type, invalid relationship'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
begin
  begin
    perform app.link_ticket_record(v_ticket_id, 'purchase_order', v_shipment_id, 'related', v_admin, 'admin');
    raise exception 'FAIL: an entity_type outside the registry must be rejected';
  exception when others then
    if sqlerrm not like 'unsupported_entity_type%' then raise exception 'FAIL: expected unsupported_entity_type, got: %', sqlerrm; end if;
  end;

  begin
    perform app.link_ticket_record(v_ticket_id, 'shipment', v_shipment_id, 'blocks', v_admin, 'admin');
    raise exception 'FAIL: an out-of-enum relationship must be rejected';
  exception when others then
    if sqlerrm not like 'invalid_relationship%' then raise exception 'FAIL: expected invalid_relationship, got: %', sqlerrm; end if;
  end;

  begin
    perform app.search_ticket_link_candidates(v_ticket_id, 'purchase_order', null, v_admin, 20);
    raise exception 'FAIL: search must also reject an entity_type outside the registry';
  exception when others then
    if sqlerrm not like 'unsupported_entity_type%' then raise exception 'FAIL: expected unsupported_entity_type from search, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: structural validation errors (unsupported_entity_type, invalid_relationship) are distinguishable -- these describe a RULE, not a specific record''s existence, so disclosing them is safe';
end;
$$;

\echo '>> 7. customer channel: narrower registry (never vendor/user); account-owner-scope narrowing (a DIFFERENT account is denied)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_account_b uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer B');
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_customer2 uuid := '00000000-0000-0000-0000-000000292111';
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_invoice_id uuid := '00000000-0000-0000-0000-000000292198';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'Lnk Vendor One');
  v_draft_invoice_id uuid := '00000000-0000-0000-0000-000000292197';
  v_ticket app.tickets;
  v_ticket_b app.tickets;
  v_link app.ticket_links;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer Linking Test', 'body', 'idem-lnk-cust-1', v_customer1, 'customer1');
  -- customer2's OWN ticket (account_b) -- used below to prove a DIFFERENT
  -- account's customer_user cannot link account_a's shipment even on a
  -- ticket they genuinely have standing on.
  v_ticket_b := app.create_customer_ticket(v_tenant1, v_account_b, v_category, 'normal', 'Customer B Linking Test', 'body', 'idem-lnk-custb-1', v_customer2, 'customer2');

  -- customer1 owns account_a -- the SAME shipment/invoice/warehouse that
  -- staff already linked is independently, freshly authorized here too
  -- (decision 4's composed customer-owner-scope branch).
  v_link := app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'primary_subject', v_customer1, 'customer1');
  if v_link.entity_id <> v_shipment_id then raise exception 'FAIL: customer1 should be able to link their own account''s shipment'; end if;
  perform app.link_ticket_record(v_ticket.id, 'invoice', v_invoice_id, 'related', v_customer1, 'customer1');
  perform app.link_ticket_record(v_ticket.id, 'warehouse', v_warehouse_id, 'related', v_customer1, 'customer1');
  perform app.link_ticket_record(v_ticket.id, 'customer', v_account_a, 'related', v_customer1, 'customer1');

  begin
    perform app.link_ticket_record(v_ticket.id, 'vendor', v_vendor_id, 'related', v_customer1, 'customer1');
    raise exception 'FAIL: a customer_user caller must never be able to link a vendor record';
  exception when others then
    if sqlerrm not like 'entity_type_not_permitted%' then raise exception 'FAIL: expected entity_type_not_permitted for vendor, got: %', sqlerrm; end if;
  end;

  begin
    perform app.search_ticket_link_candidates(v_ticket.id, 'user', null, v_customer1, 20);
    raise exception 'FAIL: a customer_user caller must never be able to search user candidates';
  exception when others then
    if sqlerrm not like 'entity_type_not_permitted%' then raise exception 'FAIL: expected entity_type_not_permitted for user, got: %', sqlerrm; end if;
  end;

  -- customer2 owns account_b, NOT account_a -- on customer2's OWN ticket
  -- (real standing, can_access_ticket passes), the SAME shipment must still
  -- be denied identically to a forged id (account-owner-scope narrowing,
  -- decision 4) -- this is the account-scope gate under test, not the
  -- ticket-access gate (already covered by section 5's cross-tenant case).
  begin
    perform app.link_ticket_record(v_ticket_b.id, 'shipment', v_shipment_id, 'related', v_customer2, 'customer2');
    raise exception 'FAIL: customer2 (a different account) must not be able to link account_a''s shipment';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;
  if exists (select 1 from app.search_ticket_link_candidates(v_ticket_b.id, 'shipment', null, v_customer2, 20) where entity_id = v_shipment_id) then
    raise exception 'CRITICAL: customer2''s candidate search surfaced account_a''s shipment';
  end if;

  -- Tier C review fix (Batch 3 close, 20260801160000): customer1 genuinely
  -- OWNS the account this draft invoice belongs to (unlike the account-scope
  -- narrowing case above), yet must still be denied -- CPL-311's own
  -- business rule (draft/submitted/approved invoices "must never leak to a
  -- customer") applies through THIS surface too, not only through CPL-311's
  -- own RPCs. A live security review reproduced a customer_user searching
  -- and then durably linking their own account's draft invoice through
  -- exactly this path before this fix; both the search and the link-time
  -- gate are re-proven denied here, and the SAME caller's own already-issued
  -- invoice (linked successfully just above) is unaffected -- proving the
  -- fix is a status-scoped narrowing, not a blanket regression.
  if exists (select 1 from app.search_ticket_link_candidates(v_ticket.id, 'invoice', null, v_customer1, 20) where entity_id = v_draft_invoice_id) then
    raise exception 'CRITICAL: customer1''s own draft (pre-issuance) invoice was surfaced by app.search_ticket_link_candidates -- CPL-311''s invoice-visibility rule must hold through this surface too';
  end if;
  begin
    perform app.link_ticket_record(v_ticket.id, 'invoice', v_draft_invoice_id, 'related', v_customer1, 'customer1');
    raise exception 'CRITICAL: customer1 was able to durably link their own account''s draft (pre-issuance) invoice via app.link_ticket_record';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible for a pre-issuance invoice, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: customer channel is bounded to shipment/invoice/warehouse/customer (never vendor/user), further narrowed to the caller''s OWN account-owner scope, AND (Tier C fix) a customer''s own pre-issuance invoice is denied identically to an out-of-scope one';
end;
$$;

\echo '>> 8. helpdesk channel: the support-grant gate (decision 5) -- a Supreme Admin with no grant is denied identically to not-eligible; the SAME Supreme Admin with a live PLT-115 grant succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_supreme uuid := '00000000-0000-0000-0000-000000292190';
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_ticket app.tickets;
  v_candidate_count integer;
  v_denied_count_before integer;
  v_denied_count_after integer;
  v_link app.ticket_links;
begin
  v_ticket := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'high', 'Billing', 'production', null, 'Helpdesk Linking Test', 'body', 'idem-lnk-hd-1', v_admin, 'admin');

  select count(*) into v_denied_count_before from app.ticket_link_events where ticket_id = v_ticket.id and event_type = 'search_denied';

  select count(*) into v_candidate_count from app.search_ticket_link_candidates(v_ticket.id, 'shipment', null, v_supreme, 20);
  if v_candidate_count <> 0 then
    raise exception 'FAIL: a Supreme Admin with no support grant into lnk1 must see ZERO shipment candidates on a helpdesk ticket (decision 5)';
  end if;

  select count(*) into v_denied_count_after from app.ticket_link_events where ticket_id = v_ticket.id and event_type = 'search_denied';
  if v_denied_count_after <> v_denied_count_before + 1 then
    raise exception 'FAIL: the tenant-data-view-gate denial must be durably logged inline (no RAISE, so the log survives)';
  end if;

  begin
    perform app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'related', v_supreme, 'Supreme');
    raise exception 'FAIL: linking must also be denied without a support grant';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;

  -- A real, live PLT-115 emergency grant (self-authorized by the Supreme
  -- Admin, a genuinely allowed path per app.request_support_access''s own
  -- rule) into lnk1, case-bound (case_id is NOT NULL by construction).
  perform app.request_support_access(v_tenant1, v_supreme, 'investigating a billing case via helpdesk ticket', 'CASE-LNK-1', 60, 'Supreme', 'read_only', true, v_supreme);

  select count(*) into v_candidate_count from app.search_ticket_link_candidates(v_ticket.id, 'shipment', null, v_supreme, 20);
  if v_candidate_count <> 1 then
    raise exception 'FAIL: with a live support grant, the Supreme Admin should now see the tenant''s real shipment candidate, got % rows', v_candidate_count;
  end if;

  v_link := app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'related', v_supreme, 'Supreme');
  if v_link.entity_id <> v_shipment_id then
    raise exception 'FAIL: linking should now succeed with a live support grant';
  end if;

  raise notice 'PASS: helpdesk-channel access requires a real, case-bound support grant -- denied identically to not-eligible without one, succeeds with one';
end;
$$;

\echo '>> 9. a domain-denied ticket-staff actor (queue member, no OPS/FIN/PRC role) links customer/user (no permission gate) but is denied shipment/invoice/warehouse/vendor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000292102';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_invoice_id uuid := '00000000-0000-0000-0000-000000292198';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'Lnk Vendor One');
  v_link app.ticket_links;
begin
  if not app.is_ticket_staff(v_ticket_id, v_staff1) then
    raise exception 'FAIL (fixture bug): staff1 must be real ticket staff (queue member) for this test to mean anything';
  end if;

  v_link := app.link_ticket_record(v_ticket_id, 'customer', v_account_a, 'context', v_staff1, 'staff1');
  if v_link.entity_id <> v_account_a then raise exception 'FAIL: staff1 should be able to link a customer account (no permission gate on app.accounts)'; end if;
  perform app.unlink_ticket_record(v_link.id, v_link.record_version, 'test cleanup', v_staff1, 'staff1');

  begin
    perform app.link_ticket_record(v_ticket_id, 'shipment', v_shipment_id, 'related', v_staff1, 'staff1');
    raise exception 'FAIL: staff1 has no OPS org-scope/ownership match and must be denied the shipment';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;
  begin
    perform app.link_ticket_record(v_ticket_id, 'invoice', v_invoice_id, 'related', v_staff1, 'staff1');
    raise exception 'FAIL: staff1 lacks FIN:View and must be denied the invoice';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;
  begin
    perform app.link_ticket_record(v_ticket_id, 'warehouse', v_warehouse_id, 'related', v_staff1, 'staff1');
    raise exception 'FAIL: staff1 has no org-scope match and must be denied the warehouse';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;
  begin
    perform app.link_ticket_record(v_ticket_id, 'vendor', v_vendor_id, 'related', v_staff1, 'staff1');
    raise exception 'FAIL: staff1 lacks PRC:View and must be denied the vendor';
  exception when others then
    if sqlerrm not like 'record_not_eligible%' then raise exception 'FAIL: expected record_not_eligible, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: ticket staff status alone (queue membership) never substitutes for the linked record''s own independent domain authorization -- a link never grants access';
end;
$$;

\echo '>> 10. revoked warehouse eligibility: the link shows unavailable, the link row is NOT deleted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-cust-1');
  v_grant app.warehouse_customer_eligibility;
  v_row record;
begin
  select * into v_grant from app.warehouse_customer_eligibility where warehouse_id = v_warehouse_id and customer_account_id = v_account_a and status = 'active';
  perform app.revoke_warehouse_customer_eligibility(v_grant.id, 'test revocation', v_grant.record_version, '00000000-0000-0000-0000-000000292101', 'admin');

  select * into v_row from app.list_ticket_links(v_ticket_id, v_customer1) where entity_type = 'warehouse';
  if v_row.live_available then
    raise exception 'FAIL: after revoking eligibility, the warehouse link must show live_available=false for customer1';
  end if;
  if v_row.label is not null then
    raise exception 'FAIL: an unavailable link must never surface the stale label -- got %', v_row.label;
  end if;
  if v_row.status_label <> 'unavailable' then
    raise exception 'FAIL: expected status_label=unavailable, got %', v_row.status_label;
  end if;
  if v_row.status <> 'active' then
    raise exception 'FAIL: the link ROW itself must remain status=active (a link is never deleted merely because visibility was revoked) -- got %', v_row.status;
  end if;
  if not exists (select 1 from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'warehouse' and status = 'active') then
    raise exception 'CRITICAL: the underlying ticket_links row was deleted/altered by a mere visibility change';
  end if;

  -- Re-grant so section 12''s stale-snapshot check (which reuses this SAME
  -- warehouse link) can observe a live, authorized, FRESH read.
  perform app.grant_warehouse_customer_eligibility(v_warehouse_id, v_account_a, '00000000-0000-0000-0000-000000292101', 'admin');

  raise notice 'PASS: a revoked eligibility grant makes the link show unavailable (no leaked stale label) without touching the link row itself';
end;
$$;

\echo '>> 11. hard-deleted source record: the link shows unavailable, the link row is NOT deleted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_del_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1-DEL');
  v_link app.ticket_links;
  v_row record;
begin
  v_link := app.link_ticket_record(v_ticket_id, 'warehouse', v_del_warehouse_id, 'context', v_admin, 'admin');

  -- Direct hard delete -- service_role holds DELETE on app.warehouses;
  -- this table has no zones attached (fixture design), so the delete is
  -- FK-clean. Simulates a genuinely vanished source record.
  delete from app.warehouses where id = v_del_warehouse_id;

  select * into v_row from app.list_ticket_links(v_ticket_id, v_admin) where id = v_link.id;
  if v_row.live_available then
    raise exception 'FAIL: after hard-deleting the source warehouse, the link must show live_available=false';
  end if;
  if v_row.status_label <> 'unavailable' then
    raise exception 'FAIL: expected status_label=unavailable for a deleted source, got %', v_row.status_label;
  end if;
  if not exists (select 1 from app.ticket_links where id = v_link.id and status = 'active') then
    raise exception 'CRITICAL: deleting the SOURCE record must never cascade-delete or alter the ticket_links row itself';
  end if;

  raise notice 'PASS: a hard-deleted source record shows unavailable identically to a revoked one (decision 6, deliberately undifferentiated) -- the link row and its history survive';
end;
$$;

\echo '>> 12. stale cache: a live read NEVER trusts the captured snapshot over a fresh source-table change'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_link app.ticket_links;
  v_fresh_label text;
begin
  -- Filtered to WH-LNK1 specifically (entity_id, not just entity_type) --
  -- by this point in the suite the internal ticket also carries a SECOND
  -- active warehouse link (section 11's own WH-LNK1-DEL, deliberately left
  -- active-but-unavailable after its source was hard-deleted), so
  -- entity_type alone would non-deterministically pick either row.
  select * into v_link from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'warehouse' and entity_id = v_warehouse_id and status = 'active';
  if (v_link.safe_snapshot ->> 'label') <> 'Lnk Warehouse One' then
    raise exception 'FAIL (fixture bug): expected the captured snapshot label to be the warehouse''s original name';
  end if;

  update app.warehouses set name = 'Lnk Warehouse One RENAMED' where id = v_warehouse_id;

  select label into v_fresh_label from app.list_ticket_links(v_ticket_id, v_admin) where id = v_link.id;
  if v_fresh_label <> 'Lnk Warehouse One RENAMED' then
    raise exception 'FAIL: list_ticket_links must return the FRESH warehouse name, not the stale captured snapshot -- got %', v_fresh_label;
  end if;
  if (select safe_snapshot ->> 'label' from app.ticket_links where id = v_link.id) <> 'Lnk Warehouse One' then
    raise exception 'FAIL: the STORED snapshot column itself must remain the original captured value (history), never silently overwritten by a read';
  end if;

  raise notice 'PASS: every live read re-fetches fresh source data; the stored snapshot is preserved as history but never trusted as currently authoritative';
end;
$$;

\echo '>> 13. cross-tenant isolation via RPC; raw-table SELECT is closed entirely for authenticated (batch 291-293 Tier C fix, 20260731210000, Finding 1 CRITICAL)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin2 uuid := '00000000-0000-0000-0000-000000292201';
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_count integer;
begin
  begin
    perform app.list_ticket_links(v_ticket_id, v_admin2);
    raise exception 'FAIL: an unrelated tenant''s admin must be refused (ticket_not_found) reading links for a ticket they cannot access';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 1 CRITICAL): the
  -- original RLS-only shape (app.can_access_ticket, never re-checking the
  -- linked record's own cross-domain FIN/PRC/OPS authorization or the
  -- helpdesk tenant-data-view gate) let a same-tenant domain-denied staff
  -- member and a cross-tenant, zero-grant Supreme Admin both raw-read full
  -- safe_snapshot content -- live-reproduced by the batch review. Fixed by
  -- revoking raw table-level SELECT from authenticated entirely (mirrors how
  -- writes were already RPC-only) -- every legitimate read now goes through
  -- app.list_ticket_links/app.list_ticket_link_events (SECURITY DEFINER)
  -- only. A raw select attempt is denied at the privilege-check stage,
  -- before RLS is ever evaluated, for ANY authenticated caller regardless of
  -- tenant or customer_user layer -- a strictly stronger guarantee than the
  -- RLS-scoped-to-zero-rows assertion this section previously made.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000292201", "role": "authenticated"}', false);
  set role authenticated;
  begin
    select count(*) into v_count from app.ticket_links where tenant_id = v_tenant1;
    raise exception 'CRITICAL: raw-table SELECT on app.ticket_links must be denied to authenticated entirely, got count=%', v_count;
  exception when others then
    if sqlerrm not like '%permission denied for table ticket_links%' then raise exception 'FAIL: expected permission denied, got: %', sqlerrm; end if;
  end;
  begin
    select count(*) into v_count from app.ticket_link_events where tenant_id = v_tenant1;
    raise exception 'CRITICAL: raw-table SELECT on app.ticket_link_events must be denied to authenticated entirely, got count=%', v_count;
  exception when others then
    if sqlerrm not like '%permission denied for table ticket_link_events%' then raise exception 'FAIL: expected permission denied, got: %', sqlerrm; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000292110", "role": "authenticated"}', false);
  set role authenticated;
  begin
    select count(*) into v_count from app.ticket_links where ticket_id = v_ticket_id;
    raise exception 'CRITICAL: a customer_user-layer actor''s raw-table read of app.ticket_links must be denied entirely, got count=%', v_count;
  exception when others then
    if sqlerrm not like '%permission denied for table ticket_links%' then raise exception 'FAIL: expected permission denied, got: %', sqlerrm; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: cross-tenant isolation holds via the RPC layer; raw-table SELECT is closed entirely for authenticated on both new tables (batch review Finding 1 fix, live-verified)';
end;
$$;

\echo '>> 14. staff-only ledger: app.list_ticket_link_events is readable by staff, refused for a non-staff caller, and carries the denial/link/unlink history'
do $$
declare
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_count integer;
begin
  select count(*) into v_count from app.list_ticket_link_events(v_ticket_id, v_admin);
  if v_count = 0 then
    raise exception 'FAIL: expected at least one ledger event on the internal ticket by now';
  end if;
  if not exists (select 1 from app.list_ticket_link_events(v_ticket_id, v_admin) where event_type = 'linked') then
    raise exception 'FAIL: expected at least one linked event in the ledger';
  end if;
  if not exists (select 1 from app.list_ticket_link_events(v_ticket_id, v_admin) where event_type = 'unlinked') then
    raise exception 'FAIL: expected at least one unlinked event in the ledger';
  end if;

  begin
    perform app.list_ticket_link_events(v_ticket_id, v_customer1);
    raise exception 'FAIL: a non-staff (customer_user, requester on a DIFFERENT ticket) caller must be refused reading this ticket''s staff-only ledger';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: the link ledger is staff-only and carries real link/unlink history';
end;
$$;

\echo '>> 15. schema-privilege defense in depth: anon has zero access to any new table/function; authenticated has zero EXECUTE on internal-only helpers'
do $$
declare
  v_has_table_priv boolean;
  v_has_fn_priv boolean;
begin
  select bool_or(has_table_privilege('anon', t.oid, 'SELECT'))
  into v_has_table_priv
  from pg_class t
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'app' and t.relname in ('ticket_links', 'ticket_link_events');
  if coalesce(v_has_table_priv, false) then
    raise exception 'CRITICAL: anon has SELECT on a new HRT-292 table';
  end if;

  select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'ticket_link_entity_types', 'ticket_link_customer_safe_entity_types',
      'search_ticket_link_candidates', 'link_ticket_record', 'unlink_ticket_record',
      'list_ticket_links', 'record_ticket_link_access_denial', 'record_ticket_link_summary_access',
      'list_ticket_link_events', '_ticket_link_actor_may_view_tenant_data', '_ticket_link_resolve_candidate'
    );
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: anon has EXECUTE on a new HRT-292 function (ERR-2026-004 class)';
  end if;

  select bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in ('_ticket_link_actor_may_view_tenant_data', '_ticket_link_resolve_candidate');
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: authenticated has EXECUTE on an internal (service_role-only) HRT-292 helper function';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 1 CRITICAL): authenticated
  -- must have ZERO raw table-level SELECT on either table -- every read goes
  -- through the SECURITY DEFINER RPCs only (section 13 live-proves the
  -- resulting permission-denied behavior; this is the static grant check).
  select bool_or(has_table_privilege('authenticated', t.oid, 'SELECT'))
  into v_has_table_priv
  from pg_class t
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'app' and t.relname in ('ticket_links', 'ticket_link_events');
  if coalesce(v_has_table_priv, false) then
    raise exception 'CRITICAL: authenticated retains raw-table SELECT on app.ticket_links/app.ticket_link_events (batch review Finding 1 must close this entirely)';
  end if;

  raise notice 'PASS: anon has zero table/function access to any HRT-292 object; authenticated has zero EXECUTE on the internal-only helpers and zero raw-table SELECT on ticket_links/ticket_link_events';
end;
$$;

\echo '>> 16. app.record_ticket_link_access_denial / app.record_ticket_link_summary_access: the follow-up audit companions always succeed and durably log'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-lnk-int-1');
  v_link_id uuid := (select id from app.ticket_links where ticket_id = v_ticket_id and entity_type = 'shipment' and status = 'active');
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.ticket_link_events where ticket_id = v_ticket_id and event_type = 'link_denied';
  perform app.record_ticket_link_access_denial(v_tenant1, v_ticket_id, v_admin, 'admin', 'vendor', gen_random_uuid(), 'test-simulated-denial');
  select count(*) into v_after from app.ticket_link_events where ticket_id = v_ticket_id and event_type = 'link_denied';
  if v_after <> v_before + 1 then
    raise exception 'FAIL: app.record_ticket_link_access_denial must insert exactly one link_denied row';
  end if;

  select count(*) into v_before from app.ticket_link_events where link_id = v_link_id and event_type = 'summary_accessed';
  perform app.record_ticket_link_summary_access(v_link_id, v_admin, 'admin', 'summary_viewed');
  select count(*) into v_after from app.ticket_link_events where link_id = v_link_id and event_type = 'summary_accessed';
  if v_after <> v_before + 1 then
    raise exception 'FAIL: app.record_ticket_link_summary_access must insert exactly one summary_accessed row';
  end if;

  begin
    perform app.record_ticket_link_summary_access(v_link_id, v_admin, 'admin', 'not_a_real_access_type');
    raise exception 'FAIL: an invalid access_type must be rejected';
  exception when others then
    if sqlerrm not like 'invalid_access_type%' then raise exception 'FAIL: expected invalid_access_type, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: the denial/access audit companions durably log exactly once per call, validate their own input';
end;
$$;

\echo '>> 17. closed/cancelled tickets are mutation-inert for app.link_ticket_record (new-engagement operation); app.unlink_ticket_record remains permitted as legitimate post-closure cleanup (HRT-295 fix for ISS-2026-109, supabase/migrations/20260731270000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_invoice_id uuid := '00000000-0000-0000-0000-000000292198';
  v_close_role uuid; v_close_draft app.role_versions;
  v_ticket_closed app.tickets;
  v_ticket_cancelled app.tickets;
  v_link app.ticket_links;
  v_msg text;
begin
  -- TKT:Close/Reopen -- the main fixture only granted admin TKT:Edit/Assign
  -- (deliberately narrow, matching section 9's own careful permission
  -- scoping). Additive role assignment: admin's existing roles are
  -- untouched, this only ADDS the authority needed to drive a ticket to
  -- resolved/closed for this section's own fixture.
  v_close_role := (app.create_role(v_tenant1, 'Ticket Closer', 'TKT Close/Reopen', 'tester')).id;
  v_close_draft := app.create_role_version(v_close_role, 'tester');
  perform app.set_role_version_permissions(v_close_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Close', 'Reopen')), 'tester');
  perform app.publish_role_version(v_close_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_close_role and status = 'published'), v_admin, v_admin, 'tester');

  -- Ticket A -> driven to CLOSED (new -> open -> resolved -> closed).
  v_ticket_closed := app.create_ticket(v_tenant1, v_category, v_queue, 'normal', 'Terminal Status Guard Test A', 'body', 'idem-lnk-term-a', v_admin, 'admin');
  v_link := app.link_ticket_record(v_ticket_closed.id, 'shipment', v_shipment_id, 'primary_subject', v_admin, 'admin');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'open', null, v_admin, 'admin');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'resolved', 'done', v_admin, 'admin');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'closed', null, v_admin, 'admin');
  if v_ticket_closed.status <> 'closed' then raise exception 'FAIL (fixture bug): ticket A must be closed'; end if;

  begin
    perform app.link_ticket_record(v_ticket_closed.id, 'invoice', v_invoice_id, 'related', v_admin, 'admin');
    raise exception 'FAIL: linking a new record to a closed ticket must be rejected';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', v_msg; end if;
  end;

  -- Cleanup (unlink) of the PRE-EXISTING shipment link (linked before
  -- close) remains permitted on a closed ticket -- deliberate design
  -- decision, see the migration's own header: cleanup is not a new
  -- engagement.
  perform app.unlink_ticket_record(v_link.id, v_link.record_version, 'cleanup after close', v_admin, 'admin');
  if (select status from app.ticket_links where id = v_link.id) <> 'removed' then
    raise exception 'FAIL: unlink_ticket_record must still succeed on a closed ticket (cleanup remains permitted)';
  end if;

  -- Ticket B -> driven to CANCELLED (new -> cancelled).
  v_ticket_cancelled := app.create_ticket(v_tenant1, v_category, v_queue, 'normal', 'Terminal Status Guard Test B', 'body', 'idem-lnk-term-b', v_admin, 'admin');
  v_link := app.link_ticket_record(v_ticket_cancelled.id, 'shipment', v_shipment_id, 'related', v_admin, 'admin');
  v_ticket_cancelled := app.transition_ticket_status(v_ticket_cancelled.id, v_ticket_cancelled.record_version, 'cancelled', 'no longer needed', v_admin, 'admin');
  if v_ticket_cancelled.status <> 'cancelled' then raise exception 'FAIL (fixture bug): ticket B must be cancelled'; end if;

  begin
    perform app.link_ticket_record(v_ticket_cancelled.id, 'invoice', v_invoice_id, 'related', v_admin, 'admin');
    raise exception 'FAIL: linking a new record to a cancelled ticket must be rejected';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', v_msg; end if;
  end;

  perform app.unlink_ticket_record(v_link.id, v_link.record_version, 'cleanup after cancel', v_admin, 'admin');
  if (select status from app.ticket_links where id = v_link.id) <> 'removed' then
    raise exception 'FAIL: unlink_ticket_record must still succeed on a cancelled ticket (cleanup remains permitted)';
  end if;

  raise notice 'PASS: link_ticket_record rejects both closed and cancelled tickets with invalid_transition; unlink_ticket_record remains permitted on both as the deliberate cleanup-is-allowed design decision';
end;
$$;

\echo '>> 18. app.list_customer_ticket_links genericizes a staff creator''s identity to "Support Team" for a customer-layer caller; the staff-facing app.list_ticket_links is unaffected and keeps returning the real identity (HRT-295 fix for ISS-2026-110, supabase/migrations/20260731270000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LNK1');
  v_ticket app.tickets;
  v_staff_link app.ticket_links;
  v_customer_link app.ticket_links;
  v_row record;
  v_customer_row_count integer;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer Link Genericization Test', 'body', 'idem-lnk-cust-generic-1', v_customer1, 'customer1');

  -- Staff (admin) links the shipment -- created_by on the raw row is
  -- admin's own actor_label ('admin', this fixture's own convention). The
  -- genericization under test keys on WHO created the row (a live
  -- app.is_ticket_staff check on the creator's auth_user_id), not on the
  -- label string itself -- production passes the caller's raw internal
  -- auth_user_id as this same label (server/mutations/ticketing.ts call
  -- sites), which is exactly what this fix prevents from ever reaching a
  -- customer.
  v_staff_link := app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'primary_subject', v_admin, 'admin');

  -- Customer1 (a real requester-side party on their own ticket) links the
  -- warehouse themselves -- created_by on THIS row is genuinely customer1's
  -- own identity, not a staff identity at all.
  v_customer_link := app.link_ticket_record(v_ticket.id, 'warehouse', v_warehouse_id, 'related', v_customer1, 'customer1');

  -- Staff-facing app.list_ticket_links is UNCHANGED -- still returns the
  -- raw actor_label for both rows (this is the pre-existing, correct
  -- behavior for the staff panel, which legitimately needs to know who
  -- linked what).
  if (select created_by from app.list_ticket_links(v_ticket.id, v_admin) where id = v_staff_link.id) <> 'admin' then
    raise exception 'FAIL: app.list_ticket_links (staff-facing) must be unaffected -- expected the raw actor_label ''admin''';
  end if;

  -- Customer-facing app.list_customer_ticket_links genericizes the STAFF
  -- creator's row to the fixed label -- never the raw internal identity.
  select * into v_row from app.list_customer_ticket_links(v_ticket.id, v_customer1) where id = v_staff_link.id;
  if v_row.created_by <> 'Support Team' then
    raise exception 'FAIL: app.list_customer_ticket_links must genericize a staff creator''s identity to ''Support Team'', got %', v_row.created_by;
  end if;
  if v_row.created_by = 'admin' then
    raise exception 'CRITICAL: app.list_customer_ticket_links leaked the raw staff actor_label to a customer caller';
  end if;

  -- The customer's OWN row keeps its own real label -- genericization is
  -- staff-identity-specific, not a blanket redaction of every row.
  select * into v_row from app.list_customer_ticket_links(v_ticket.id, v_customer1) where id = v_customer_link.id;
  if v_row.created_by <> 'customer1' then
    raise exception 'FAIL: app.list_customer_ticket_links must keep a non-staff creator''s own real label, got %', v_row.created_by;
  end if;

  select count(*) into v_customer_row_count from app.list_customer_ticket_links(v_ticket.id, v_customer1);
  if v_customer_row_count <> 2 then
    raise exception 'FAIL: expected both active links visible to the customer, got %', v_customer_row_count;
  end if;

  -- Every other column stays byte-identical to the staff-facing read for
  -- the SAME row -- only created_by is genericized.
  if (select label from app.list_customer_ticket_links(v_ticket.id, v_customer1) where id = v_staff_link.id) <> 'SHP-LNK-0001' then
    raise exception 'FAIL: label must still be the real, live shipment label -- genericization is scoped to created_by only';
  end if;

  -- Schema-privilege defense in depth (C-11/C-12 self-check): the new
  -- function is deliberately EXECUTE-granted to authenticated/service_role
  -- only, never anon (mirrors this migration's own established sweep).
  if has_function_privilege('anon', 'app.list_customer_ticket_links(uuid, uuid)', 'EXECUTE') then
    raise exception 'CRITICAL: anon has EXECUTE on app.list_customer_ticket_links';
  end if;
  if not has_function_privilege('authenticated', 'app.list_customer_ticket_links(uuid, uuid)', 'EXECUTE') then
    raise exception 'FAIL: authenticated must have EXECUTE on app.list_customer_ticket_links';
  end if;

  raise notice 'PASS: app.list_customer_ticket_links genericizes a staff creator''s identity to Support Team for a customer caller, keeps a customer''s own real label, leaves every other column (including app.list_ticket_links'' own staff-facing read) unaffected, and carries the correct anon/authenticated privilege boundary';
end;
$$;

-- ===========================================================================
-- HRT-295 Tier C review fix (security lens finding, High): section 18 above
-- never sets request.jwt.claims/role authenticated for its own app.list_
-- customer_ticket_links calls -- app.assert_actor_is_session_identity is an
-- intentional no-op when auth.uid() IS NULL (the service_role/superuser/
-- db-test convention), so section 18 runs as an unauthenticated superuser
-- call and never exercises the real RLS-session-bound path this RPC runs
-- under in production. This section closes that gap with a GENUINE forged
-- customer session, live-reproducing the original defect first (before the
-- fix landed, this exact call raised actor_identity_mismatch for every
-- ordinary multi-party ticket -- 20260731270000's own line 514 passed the
-- LINK'S CREATOR, not the calling actor, into app.is_ticket_staff -> app.
-- check_ticket_authority -> app.evaluate_permission -> app.assert_actor_is_
-- session_identity, which unconditionally rejects a third-party actor).
-- Fixed by 20260731300000 (app.ticket_links.created_by_role, captured once
-- at link-creation time, never re-derived live against a third party).
-- ===========================================================================

\echo '>> 19. HRT-295 Tier C review: app.list_customer_ticket_links via a GENUINE forged customer session -- must succeed with zero actor_identity_mismatch for a ticket whose links were created by a DIFFERENT identity than the reading customer (the ordinary case, not an edge case)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_admin uuid := '00000000-0000-0000-0000-000000292101';
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lnk Customer A');
  v_shipment_id uuid := '00000000-0000-0000-0000-000000292199';
  v_ticket app.tickets;
  v_staff_link app.ticket_links;
  v_rows_json jsonb;
  v_row_count integer;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'HRT-295 Tier C forged-session regression', 'body', 'idem-lnk-cust-forged-session-1', v_customer1, 'customer1');

  -- Staff links a record -- created_by_role='staff', captured at write time
  -- by the REAL calling actor's own already-verified session (v_admin here
  -- is passed as a plain parameter in this db-test convention, matching
  -- every other call in this file -- the crosscheck engages only once a
  -- REAL forged session is present below, on the READ side, which is
  -- exactly what this section adds).
  v_staff_link := app.link_ticket_record(v_ticket.id, 'shipment', v_shipment_id, 'primary_subject', v_admin, 'admin');

  -- The read below is the one that matters: a GENUINE forged customer
  -- session, not a bare superuser call. Before the Tier C fix
  -- (20260731300000), this exact call raised actor_identity_mismatch.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000292110", "role": "authenticated"}', false);
  set role authenticated;
  begin
    select jsonb_agg(jsonb_build_object('id', l.id, 'created_by', l.created_by)) into v_rows_json
    from app.list_customer_ticket_links(v_ticket.id, v_customer1) l;
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', 'null', false);
    raise exception 'HRT-295 Tier C REGRESSION: a genuine forged customer session must be able to call app.list_customer_ticket_links on its OWN ticket without error -- got: % (sqlstate %)', sqlerrm, sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select jsonb_array_length(v_rows_json) into v_row_count;
  if v_row_count <> 1 then
    raise exception 'FAIL: expected exactly 1 link visible to the forged customer session, got %', v_row_count;
  end if;
  if (v_rows_json -> 0 ->> 'created_by') <> 'Support Team' then
    raise exception 'FAIL: expected the staff creator genericized to Support Team even under a real forged session, got %', (v_rows_json -> 0 ->> 'created_by');
  end if;

  raise notice 'PASS (HRT-295 Tier C, 20260731300000), part 1: app.list_customer_ticket_links succeeds under a GENUINE forged customer session for a ticket whose ONLY link was created by a DIFFERENT identity (staff) -- zero actor_identity_mismatch, correctly genericized to Support Team';
end;
$$;

\echo '>> 19b. HRT-295 Tier C review: the SAME forged customer session links a SECOND record themselves (a genuine requester-side write, not a third party), then re-reads via the SAME forged session -- proves the fix did not merely paper over the staff-creator case, and that a customer reading their OWN self-created link (never a third-party actor at all) still works correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lnk1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = (select id from app.tenants where slug = 'lnk1') and idempotency_key = 'idem-lnk-cust-forged-session-1');
  v_customer1 uuid := '00000000-0000-0000-0000-000000292110';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = (select id from app.tenants where slug = 'lnk1') and code = 'WH-LNK1');
  v_rows_json jsonb;
  v_row_count integer;
  v_staff_row jsonb;
  v_customer_row jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000292110", "role": "authenticated"}', false);
  set role authenticated;
  perform app.link_ticket_record(v_ticket_id, 'warehouse', v_warehouse_id, 'related', v_customer1, 'customer1');

  select jsonb_agg(jsonb_build_object('created_by', l.created_by, 'entity_type', l.entity_type)) into v_rows_json
  from app.list_customer_ticket_links(v_ticket_id, v_customer1) l;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select jsonb_array_length(v_rows_json) into v_row_count;
  if v_row_count <> 2 then
    raise exception 'FAIL: expected exactly 2 links visible (staff-created shipment + customer-created warehouse), got %', v_row_count;
  end if;

  select v into v_staff_row from jsonb_array_elements(v_rows_json) v where v ->> 'entity_type' = 'shipment';
  select v into v_customer_row from jsonb_array_elements(v_rows_json) v where v ->> 'entity_type' = 'warehouse';
  if v_staff_row ->> 'created_by' <> 'Support Team' then
    raise exception 'FAIL: expected the staff-created shipment link genericized to Support Team, got %', v_staff_row ->> 'created_by';
  end if;
  if v_customer_row ->> 'created_by' <> 'customer1' then
    raise exception 'FAIL: expected the customer''s OWN self-created warehouse link to keep its own real label, got %', v_customer_row ->> 'created_by';
  end if;

  raise notice 'PASS (HRT-295 Tier C, 20260731300000), part 2: the SAME genuine forged customer session both creates a new link AND re-reads the full list (2 rows: staff-created genericized, customer-created real label) -- durable across repeated real-session reads, never a first-call artifact';
end;
$$;

\echo '>> ticketing-linked-records.sql: ALL PASSED'
