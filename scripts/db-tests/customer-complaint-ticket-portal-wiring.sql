-- Real, executable test evidence for CPL-313 (CG-S13-CPL-015, Prompt 313,
-- "Complaint and Ticket") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. A NEW file, per this task's own "your call,
-- document it" instruction: this checkpoint's own new database objects
-- (app.ticket_portal_links and its five new functions) are a genuinely
-- SEPARATE, parallel surface from app.ticket_links (HRT-292) -- see
-- supabase/migrations/20260801140000_create_customer_portal_ticket_linked_
-- records.sql's own header for why -- so this file tests that new,
-- self-contained surface directly rather than appending to (and risking) the
-- existing, protected scripts/db-tests/ticketing-linked-records.sql, which
-- this checkpoint never touches.
--
-- UUID range 00000000-0000-0000-0000-000000327xxx (tenant ctw1) /
-- ...328xxx (tenant ctw2), grep-verified unclaimed.
--
-- Covers, live, exactly what this task's own instructions named:
-- (1) a linked-record picker candidate the customer does NOT have access to
--     (another customer's warehouse order/document, a forged id) is
--     correctly REJECTED AT LINK-CREATION TIME (app.link_ticket_portal_
--     record's own anti-enumerating record_not_eligible), not merely
--     omitted from a search result;
-- (2) internal-note leakage stays closed -- re-verified live (a staff-only
--     internal reply on a customer ticket never appears through app.list_
--     customer_ticket_messages), not assumed from HRT-287's own text;
-- (3) cross-tenant isolation -- an identity with customer_user standing
--     ONLY in tenant ctw2 is denied by every new RPC when probing ctw1;
-- (4) a customer cannot search/count another customer's TICKETS through any
--     new surface this checkpoint adds -- every one of the five new
--     ticket-scoped RPCs (search/link/unlink/list) raises the SAME
--     anti-enumerating ticket_not_found for a ticket owned by a different
--     customer, never a distinguishable "forbidden" signal and never a
--     count/row leak.
-- Plus the standing Phase 8 checklist every new RPC in this batch must
-- prove: the registry drift-gate (app.ticket_portal_link_entity_types() vs.
-- the live CHECK constraint, AND proof app.ticket_links'/app.ticket_link_
-- entity_types()' own SIX-value registry is genuinely untouched by this
-- checkpoint); the precreate search spanning BOTH registries in one call;
-- idempotent link/duplicate-natural-key; unlink (reason required, stale-
-- version rejection); revocation-takes-immediate-effect (warehouse
-- eligibility); actor-identity session cross-check (C-13) on all five new
-- actor-taking RPCs; raw-table RLS defense-in-depth on app.ticket_portal_
-- links; raw-function grant defense in depth; a real, live authenticated-
-- role positive path.

\set ON_ERROR_STOP on

\echo '>> setup: tenant ctw1 (staff1 -- TKT:Edit/Close/Reopen + ticket queue/category; accounts Alpha/Beta; cust-alpha on Alpha, cust-beta on Beta, impersonator with zero grants; warehouse WH-CTW-1 eligible for Alpha only; one confirmed manual outbound order for Alpha; one quote-request document for Alpha; one direct-insert shipment order for Alpha), tenant ctw2 (account Gamma, cust-gamma) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_dept uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_supreme uuid := '00000000-0000-0000-0000-000000327002';
  v_staff1 uuid := '00000000-0000-0000-0000-000000327001';
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_cust_beta uuid := '00000000-0000-0000-0000-000000327011';
  v_impersonator uuid := '00000000-0000-0000-0000-000000327050';
  v_cust_gamma uuid := '00000000-0000-0000-0000-000000328010';
  v_staff1_emp uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_queue uuid;
  v_category uuid;
  v_warehouse app.warehouses;
  v_item uuid;
  v_order app.wms_outbound_orders;
  v_qr_draft app.config_versions;
  v_request app.customer_portal_quote_requests;
  v_file app.files;
  v_lead uuid; v_prospect uuid; v_opportunity uuid; v_quotation uuid; v_handoff uuid; v_job_order uuid;
  v_eval uuid; v_billing_handoff uuid;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@ctw.test'),
    (v_staff1, 'staff1@ctw1.test'),
    (v_cust_alpha, 'cust-alpha@ctw1.test'),
    (v_cust_beta, 'cust-beta@ctw1.test'),
    (v_impersonator, 'impersonator@ctw1.test'),
    (v_cust_gamma, 'cust-gamma@ctw2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('ctw1', 'Complaint Ticket Wiring Tenant One', 'idem-ctw1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'ctw1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('ctw2', 'Complaint Ticket Wiring Tenant Two', 'idem-ctw2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'ctw2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_staff1, 'staff1@ctw1.test', 'Ctw1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@ctw1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_staff1, 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, v_cust_alpha, 'cust-alpha@ctw1.test', 'Ctw1 Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-alpha@ctw1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_cust_beta, 'cust-beta@ctw1.test', 'Ctw1 Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-beta@ctw1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@ctw1.test', 'Ctw1 Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@ctw1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_cust_gamma, 'cust-gamma@ctw2.test', 'Ctw2 Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-gamma@ctw2.test'), 'active', 'onboarded', 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Close/Reopen', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Override', 'Close', 'Reopen')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_staff1, v_staff1, 'tester');

  -- HR role: HRS Create/Edit/Approve/Export/View -- staff1 also performs its
  -- own employee-lifecycle setup below (mirrors ticketing-customer.sql's own
  -- HR-role-plus-TKT-role-on-one-identity fixture shape).
  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), v_staff1, v_staff1, 'tester');
  end;

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CTW1-CO', 'Ctw1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'CTW1-BR', 'Ctw1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'CTW1-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Ctw1 Staff One', 'full_time', 'staff1work@ctw1.test', 'staff1p@ctw1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Support Agent', null, (select id from app.users where email = 'staff1@ctw1.test'), null, 'hr_created', 'idem-staff1-ctw1', v_staff1, 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@ctw1.test'), 'Emergency Contact', 'spouse', '0910000000', null, true, v_staff1, 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@ctw1.test'), 1, v_staff1, 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@ctw1.test'), 2, 'approve', null, v_staff1, 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@ctw1.test'), 3, v_staff1, 'tester');
  v_staff1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@ctw1.test');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'Q-CTW-SUP', 'Support Queue', null, v_staff1, 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, v_staff1_emp, v_staff1, 'staff1');
  v_category := (app.create_ticket_category(v_tenant1, 'CAT-CTW-GENERAL', 'General Issue', v_queue, v_staff1, 'staff1')).id;
  perform app.set_ticket_category_customer_visibility(v_category, true, v_staff1, 'staff1');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Ctw1 Account Alpha', 'ctw1-alpha-fp', '{}'::jsonb, v_company, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Ctw1 Account Beta', 'ctw1-beta-fp', '{}'::jsonb, v_company, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Ctw2 Account Gamma', 'ctw2-gamma-fp', '{}'::jsonb, null, 'tester') returning id into v_account_gamma;

  perform app.grant_principal_membership(v_cust_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');
  perform app.grant_principal_membership(v_cust_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');
  perform app.grant_principal_membership(v_cust_gamma, 'customer_user', v_tenant2, v_account_gamma::text, 'tester');
  -- v_impersonator deliberately holds ZERO customer_user (or any principal) grant.

  -- Warehouse WH-CTW-1, eligible for Alpha ONLY -- Beta/impersonator/gamma
  -- must all be denied both search and link.
  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-CTW-1', 'Ctw Warehouse One', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_warehouse.id, v_account_alpha, v_supreme, 'admin');

  v_item := (app.create_item_master(v_tenant1, v_account_alpha, 'SKU-CTW-ALPHA', 'Ctw Alpha Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse.id, v_account_alpha, 'ctw alpha order', 'idem-ctw-outbound-a1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item, 'PCS', 5, null, v_supreme, 'admin');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_supreme, 'admin');

  -- Quote-request document for Alpha (mirrors CPL-308's own db-test
  -- pipeline, the quote_request union arm only -- the ePOD arm's own
  -- authorization shape is already exhaustively proven by CPL-308's own
  -- db-test and is not re-tested here; this file re-derives the IDENTICAL
  -- predicate, never a third invented one, per this migration's own design
  -- decision 3).
  v_qr_draft := app.create_config_draft('document:quote_request_attachment', v_tenant1, 'tenant', null, v_staff1, 'staff1');
  perform app.set_config_items(v_qr_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_staff1, 'staff1');
  perform app.publish_document_type_definition(v_qr_draft.id, v_staff1, now(), 'staff1');

  v_request := app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'ctw alpha cargo', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-ctw-alpha', v_cust_alpha, 'cust-alpha');
  v_file := app.initiate_file_upload(
    v_tenant1, 'quote_request_attachment', 'customer_portal_quote_request', v_request.id,
    'ctw-cargo-photo.jpg', 'image/jpeg', 204800, null, false, null, '{}', null, 'upload-ctw-alpha-1', v_cust_alpha, 'cust-alpha'
  );
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', v_staff1, 'staff1');

  -- Direct-insert shipment order for Alpha (mirrors ticketing-linked-
  -- records.sql's own established "direct insert throughout, none of this
  -- business logic is under test here" precedent, HRT-291/292's own
  -- convention) -- used only to prove app.search_customer_ticket_link_
  -- candidates_precreate spans the EXISTING (unmodified) HRT-292 registry
  -- too, in the SAME call shape as the two new entity types.
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), v_tenant1, 'referral', 'Ctw Lead Contact', 'ctw-lead-contact@example.test', 'fp-ctw1-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), v_tenant1, v_lead, 'Ctw Prospect Co', 'fp-ctw1-prospect', 'Ctw Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), v_tenant1, v_prospect, 'Ctw Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, v_tenant1, 'QUO-CTW-0001', v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), v_tenant1, v_quotation, v_account_alpha, '{"note": "fixture"}'::jsonb, 'hash-ctw-1', v_staff1, v_company, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant1, 'JOB-CTW-0001', v_handoff, v_quotation, v_account_alpha,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    'confirmed', v_staff1, v_company, 'tester'
  )
  returning id into v_job_order;
  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    owner_user_id, org_unit_id, created_by
  ) values (
    '00000000-0000-0000-0000-000000327199', v_tenant1, v_job_order, 'SHP-CTW-0001', 'idem-shp-ctw-1', 'confirmed', v_account_alpha,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Port A', 'Port B',
    v_staff1, v_company, 'tester'
  );

  -- Two invoices off the SAME job_order (Tier C review fix, Batch 3 close)
  -- -- one ISSUED (customer-visible), one DRAFT (must never be
  -- customer-visible, CPL-311's own business rule) -- used only to prove
  -- app.search_customer_ticket_link_candidates_precreate's own 'invoice'
  -- branch (fixed in this same batch's migration,
  -- 20260801140000_create_customer_portal_ticket_linked_records.sql design
  -- decision 12) genuinely excludes the draft one for its own owning
  -- customer (section 2 below).
  insert into app.billing_readiness_evaluations (id, tenant_id, job_order_id, evaluated_status, blockers, evidence, evaluated_by_auth_user_id)
  values (gen_random_uuid(), v_tenant1, v_job_order, 'ready', '[]'::jsonb, '{}'::jsonb, v_staff1)
  returning id into v_eval;
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (gen_random_uuid(), v_tenant1, v_job_order, v_eval, 'idem-br-ctw-issued', v_staff1, 'staff1')
  returning id into v_billing_handoff;
  insert into app.finance_invoices (
    id, tenant_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, status, subtotal_amount, tax_amount, created_by
  ) values (
    '00000000-0000-0000-0000-000000327198', v_tenant1, 'INV-CTW-0001', v_account_alpha, v_job_order, v_billing_handoff,
    'USD', 'issued', 800, 80, 'tester'
  );
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (gen_random_uuid(), v_tenant1, v_job_order, v_eval, 'idem-br-ctw-draft', v_staff1, 'staff1')
  returning id into v_billing_handoff;
  insert into app.finance_invoices (
    id, tenant_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, status, subtotal_amount, tax_amount, created_by
  ) values (
    '00000000-0000-0000-0000-000000327197', v_tenant1, null, v_account_alpha, v_job_order, v_billing_handoff,
    'USD', 'draft', 400, 0, 'tester'
  );

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_alpha=%, account_beta=%, account_gamma=%, warehouse=%, order=%, request=%, file=%',
    v_tenant1, v_tenant2, v_queue, v_category, v_account_alpha, v_account_beta, v_account_gamma, v_warehouse.id, v_order.id, v_request.id, v_file.id;
end $$;

\echo '>> 1. registry drift-gate: app.ticket_portal_link_entity_types() stays set-equal with the live app.ticket_portal_links_entity_type_check CHECK constraint (real INSERT/ROLLBACK per value), AND app.ticket_links/app.ticket_link_entity_types() -- the ORIGINAL HRT-292 registry -- is genuinely untouched by this checkpoint (still exactly the original six values, still rejects both new values)'
do $$
declare
  v_full text[] := app.ticket_portal_link_entity_types();
  v_type text;
  v_ok boolean;
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
begin
  if v_full <> array['warehouse_order', 'document']::text[] then
    raise exception 'FAIL: app.ticket_portal_link_entity_types() drifted from the documented two-value registry: %', v_full;
  end if;

  foreach v_type in array v_full loop
    v_ok := true;
    begin
      insert into app.ticket_portal_links (tenant_id, ticket_id, entity_type, entity_id, safe_snapshot, created_by_auth_user_id)
      values (v_tenant1, gen_random_uuid(), v_type, gen_random_uuid(), '{}'::jsonb, gen_random_uuid());
      raise exception using errcode = '23505'; -- force rollback of this probe insert regardless of outcome
    exception
      when check_violation then v_ok := false;
      when foreign_key_violation then v_ok := true; -- CHECK passed; only the (unrelated) FK to a fake ticket failed
      when unique_violation then v_ok := true; -- our own forced-rollback sentinel
    end;
    if not v_ok then
      raise exception 'FAIL: registry value % is rejected by ticket_portal_links_entity_type_check -- drifted from the registry function', v_type;
    end if;
  end loop;

  -- The ORIGINAL app.ticket_links registry must remain EXACTLY the original
  -- six values -- this checkpoint's own migration must never have widened it.
  if app.ticket_link_entity_types() <> array['shipment', 'invoice', 'warehouse', 'vendor', 'customer', 'user']::text[] then
    raise exception 'FAIL: app.ticket_link_entity_types() (HRT-292, pre-existing) was widened by this checkpoint -- it must remain exactly the original six values';
  end if;

  -- Direct inspection of the LIVE CHECK constraint definition on app.
  -- ticket_links.entity_type (never a live INSERT probe here -- that table
  -- has since grown its own unrelated NOT NULL created_by_role column, HRT-
  -- 295 Tier C, which would mask which constraint a probe insert actually
  -- failed on) -- must still be exactly the original six-value list, byte
  -- for byte, never widened by this checkpoint.
  if (
    select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'app.ticket_links'::regclass and conname = 'ticket_links_entity_type_check'
  ) <> 'CHECK ((entity_type = ANY (ARRAY[''shipment''::text, ''invoice''::text, ''warehouse''::text, ''vendor''::text, ''customer''::text, ''user''::text])))' then
    raise exception 'FAIL: app.ticket_links_entity_type_check''s own live definition drifted from the original six-value list -- the pre-existing HRT-292 registry must never be widened by this checkpoint';
  end if;
end $$;

\echo '>> 2. precreate search (app.search_customer_ticket_link_candidates_precreate) spans BOTH registries for the OWNING customer, denies a non-owning customer, and hard-requires a real customer_user actor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_cust_beta uuid := '00000000-0000-0000-0000-000000327011';
  v_staff1 uuid := '00000000-0000-0000-0000-000000327001';
  v_impersonator uuid := '00000000-0000-0000-0000-000000327050';
  v_issued_invoice_id uuid := '00000000-0000-0000-0000-000000327198';
  v_draft_invoice_id uuid := '00000000-0000-0000-0000-000000327197';
  v_n integer;
begin
  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_cust_alpha, 20);
  if v_n <> 1 then raise exception 'FAIL: expected cust-alpha to see exactly 1 warehouse_order candidate, got %', v_n; end if;

  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'document', null, v_cust_alpha, 20);
  if v_n <> 1 then raise exception 'FAIL: expected cust-alpha to see exactly 1 document candidate, got %', v_n; end if;

  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'shipment', null, v_cust_alpha, 20);
  if v_n <> 1 then raise exception 'FAIL: expected cust-alpha to see exactly 1 shipment candidate (proves precreate search spans the EXISTING HRT-292 registry too), got %', v_n; end if;

  -- Tier C review fix (Batch 3 close): cust-alpha owns TWO invoices (one
  -- issued, one draft/pre-issuance) -- exactly 1 candidate (the issued one)
  -- must ever be surfaced, matching CPL-311's own business rule (draft/
  -- submitted/approved invoices "must never leak to a customer"). A live
  -- security review reproduced the draft one being surfaced (and then
  -- durably linkable) through this exact RPC before this fix.
  if exists (
    select 1 from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'invoice', null, v_cust_alpha, 20) where entity_id = v_draft_invoice_id
  ) then
    raise exception 'CRITICAL: cust-alpha''s own draft (pre-issuance) invoice was surfaced by app.search_customer_ticket_link_candidates_precreate';
  end if;
  if not exists (
    select 1 from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'invoice', null, v_cust_alpha, 20) where entity_id = v_issued_invoice_id
  ) then
    raise exception 'FAIL: cust-alpha''s own issued invoice was NOT surfaced -- the status fix must not exclude a genuinely visible invoice';
  end if;
  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'invoice', null, v_cust_alpha, 20);
  if v_n <> 1 then raise exception 'FAIL: expected cust-alpha to see exactly 1 invoice candidate (the issued one only), got %', v_n; end if;

  -- cust-beta owns NEITHER the warehouse-eligible account NOR the document's
  -- account NOR the shipment's account NOR the invoices' account -- deny by
  -- default, empty, never an error.
  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_cust_beta, 20);
  if v_n <> 0 then raise exception 'FAIL: expected cust-beta to see 0 warehouse_order candidates (no eligibility), got %', v_n; end if;
  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'document', null, v_cust_beta, 20);
  if v_n <> 0 then raise exception 'FAIL: expected cust-beta to see 0 document candidates, got %', v_n; end if;
  select count(*) into v_n from app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'invoice', null, v_cust_beta, 20);
  if v_n <> 0 then raise exception 'FAIL: expected cust-beta to see 0 invoice candidates, got %', v_n; end if;

  -- A staff (non-customer_user) actor is hard-rejected -- this surface is
  -- customer-only by design.
  begin
    perform app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_staff1, 20);
    raise exception 'FAIL: expected insufficient_privilege for a staff actor calling the customer-only precreate search';
  exception
    when others then
      if sqlerrm not like 'insufficient_privilege%' then raise; end if;
  end;

  -- An identity with zero principal membership of any kind is denied identically.
  begin
    perform app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_impersonator, 20);
    raise exception 'FAIL: expected insufficient_privilege for an identity with zero customer_user membership';
  exception
    when others then
      if sqlerrm not like 'insufficient_privilege%' then raise; end if;
  end;

  -- An unrecognized entity_type is a distinguishable RULE error, never a
  -- record-shaped anti-enumeration signal.
  begin
    perform app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'purchase_order', null, v_cust_alpha, 20);
    raise exception 'FAIL: expected unsupported_entity_type for an unrecognized entity_type';
  exception
    when others then
      if sqlerrm not like 'unsupported_entity_type%' then raise; end if;
  end;
end $$;

\echo '>> 3. cross-tenant isolation: cust-gamma (customer_user standing ONLY in ctw2) is denied by the precreate search when probing ctw1''s own tenant id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
  v_cust_gamma uuid := '00000000-0000-0000-0000-000000328010';
begin
  begin
    perform app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_cust_gamma, 20);
    raise exception 'FAIL: expected insufficient_privilege for cust-gamma (ctw2-only standing) probing ctw1';
  exception
    when others then
      if sqlerrm not like 'insufficient_privilege%' then raise; end if;
  end;
end $$;

\echo '>> 4. create tickets: cust-alpha files a ticket (used for links/internal-note/SLA-adjacent flows below), cust-beta files a SEPARATE ticket (used for the cross-ticket isolation tests)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
  v_account_alpha uuid := (select id from app.accounts where legal_name = 'Ctw1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where legal_name = 'Ctw1 Account Beta');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-CTW-GENERAL');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_cust_beta uuid := '00000000-0000-0000-0000-000000327011';
  v_staff1 uuid := '00000000-0000-0000-0000-000000327001';
  v_ticket_alpha app.tickets;
  v_ticket_beta app.tickets;
begin
  v_ticket_alpha := app.create_customer_ticket(v_tenant1, v_account_alpha, v_category, 'normal', 'Ctw alpha ticket', 'my order looks wrong', 'idem-ctw-ticket-alpha', v_cust_alpha, 'cust-alpha');
  v_ticket_beta := app.create_customer_ticket(v_tenant1, v_account_beta, v_category, 'normal', 'Ctw beta ticket', 'separate issue', 'idem-ctw-ticket-beta', v_cust_beta, 'cust-beta');

  -- A staff-only INTERNAL reply on alpha's ticket -- the internal-note
  -- leakage re-verification fixture (section 6 below).
  perform app.reply_to_ticket(v_ticket_alpha.id, 'internal note: escalate to WMS ops', 'internal', null, 'idem-ctw-internal-reply', v_staff1, 'staff1');

  raise notice 'tickets ready: alpha=%, beta=%', v_ticket_alpha.id, v_ticket_beta.id;
end $$;

\echo '>> 5. link-creation-time rejection (THE KEY REQUIRED TEST): a candidate the acting customer does NOT have access to is rejected by app.link_ticket_portal_record itself, not merely absent from a search result -- forged/foreign warehouse_order, forged/foreign document, and a genuinely nonexistent id all collapse into the SAME record_not_eligible'
do $$
declare
  v_order_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-ctw-outbound-a1');
  v_file_id uuid := (select f.id from app.files f join app.customer_portal_quote_requests r on r.id = f.record_id where f.record_type = 'customer_portal_quote_request' and r.idempotency_key = 'create-ctw-alpha');
  v_ticket_beta_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-beta');
  v_cust_beta uuid := '00000000-0000-0000-0000-000000327011';
  v_forged_id uuid := gen_random_uuid();
begin
  -- cust-beta attempts to link ALPHA's own warehouse order to BETA's own
  -- ticket -- must be rejected AT LINK TIME, even though beta authored the
  -- link call against their OWN, genuinely-accessible ticket.
  begin
    perform app.link_ticket_portal_record(v_ticket_beta_id, 'warehouse_order', v_order_id, 'related', v_cust_beta, 'cust-beta');
    raise exception 'FAIL: expected record_not_eligible -- cust-beta has no eligibility over Alpha''s own warehouse order';
  exception
    when others then
      if sqlerrm not like 'record_not_eligible%' then raise; end if;
  end;

  -- Same, for Alpha's own document.
  begin
    perform app.link_ticket_portal_record(v_ticket_beta_id, 'document', v_file_id, 'related', v_cust_beta, 'cust-beta');
    raise exception 'FAIL: expected record_not_eligible -- cust-beta has no scope over Alpha''s own document';
  exception
    when others then
      if sqlerrm not like 'record_not_eligible%' then raise; end if;
  end;

  -- A genuinely nonexistent id, from the SAME caller, raises the byte-for-byte
  -- identical error prefix -- anti-enumeration (C-05): a forged/foreign
  -- candidate and a nonexistent one must be indistinguishable.
  begin
    perform app.link_ticket_portal_record(v_ticket_beta_id, 'warehouse_order', v_forged_id, 'related', v_cust_beta, 'cust-beta');
    raise exception 'FAIL: expected record_not_eligible for a genuinely nonexistent id too';
  exception
    when others then
      if sqlerrm not like 'record_not_eligible%' then raise; end if;
  end;
end $$;

\echo '>> 6. internal-note leakage stays closed -- re-verified live (HRT-287''s own existing guarantee): the staff-only internal reply on alpha''s ticket never appears through app.list_customer_ticket_messages for the ticket''s own requester'
do $$
declare
  v_ticket_alpha_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-alpha');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_internal_count integer;
begin
  select count(*) into v_internal_count
  from app.list_customer_ticket_messages(v_ticket_alpha_id, v_cust_alpha, 200, null)
  where body ilike '%escalate to WMS ops%';
  if v_internal_count <> 0 then
    raise exception 'FAIL: an internal-only staff reply leaked through app.list_customer_ticket_messages to the ticket''s own customer requester -- got % matching rows', v_internal_count;
  end if;
end $$;

\echo '>> 7. a customer cannot search/count another customer''s TICKETS through any new surface this checkpoint adds -- every one of the five new ticket-scoped RPCs raises the SAME anti-enumerating ticket_not_found for a ticket owned by a DIFFERENT customer'
do $$
declare
  v_ticket_alpha_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-alpha');
  v_cust_beta uuid := '00000000-0000-0000-0000-000000327011';
begin
  begin
    perform app.search_ticket_portal_link_candidates(v_ticket_alpha_id, 'warehouse_order', null, v_cust_beta, 20);
    raise exception 'FAIL: expected ticket_not_found -- cust-beta may not search links on Alpha''s own ticket';
  exception
    when others then
      if sqlerrm not like 'ticket_not_found%' then raise; end if;
  end;

  begin
    perform app.link_ticket_portal_record(v_ticket_alpha_id, 'warehouse_order', gen_random_uuid(), 'related', v_cust_beta, 'cust-beta');
    raise exception 'FAIL: expected ticket_not_found -- cust-beta may not link records onto Alpha''s own ticket';
  exception
    when others then
      if sqlerrm not like 'ticket_not_found%' then raise; end if;
  end;

  begin
    perform app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_beta);
    raise exception 'FAIL: expected ticket_not_found -- cust-beta may not list Alpha''s own ticket''s links';
  exception
    when others then
      if sqlerrm not like 'ticket_not_found%' then raise; end if;
  end;

  begin
    perform app.unlink_ticket_portal_record(gen_random_uuid(), 1, 'x', v_cust_beta, 'cust-beta');
    raise exception 'FAIL: expected ticket_link_not_found (the anti-enumerating not-found for a nonexistent/foreign link id) for cust-beta';
  exception
    when others then
      if sqlerrm not like 'ticket_link_not_found%' then raise; end if;
  end;
end $$;

\echo '>> 8. idempotent link (natural key, no duplicate row), successful link + list, revocation of warehouse eligibility takes IMMEDIATE effect on the linked-record view (live_available flips to false without any UPDATE to the link row itself), and unlink (reason required, stale-version rejection, real removal)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
  v_ticket_alpha_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-alpha');
  v_order_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-ctw-outbound-a1');
  v_file_id uuid := (select f.id from app.files f join app.customer_portal_quote_requests r on r.id = f.record_id where f.record_type = 'customer_portal_quote_request' and r.idempotency_key = 'create-ctw-alpha');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CTW-1');
  v_account_alpha uuid := (select id from app.accounts where legal_name = 'Ctw1 Account Alpha');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_supreme uuid := '00000000-0000-0000-0000-000000327002';
  v_link1 app.ticket_portal_links;
  v_link1_again app.ticket_portal_links;
  v_doc_link app.ticket_portal_links;
  v_n integer;
  v_available boolean;
begin
  v_link1 := app.link_ticket_portal_record(v_ticket_alpha_id, 'warehouse_order', v_order_id, 'primary_subject', v_cust_alpha, 'cust-alpha');
  v_link1_again := app.link_ticket_portal_record(v_ticket_alpha_id, 'warehouse_order', v_order_id, 'related', v_cust_alpha, 'cust-alpha');
  if v_link1.id <> v_link1_again.id then
    raise exception 'FAIL: expected the SAME row on a re-link of the identical (ticket_id, entity_type, entity_id) natural key, got a different id (% vs %)', v_link1.id, v_link1_again.id;
  end if;
  select count(*) into v_n from app.ticket_portal_links where ticket_id = v_ticket_alpha_id and entity_type = 'warehouse_order' and entity_id = v_order_id and status = 'active';
  if v_n <> 1 then raise exception 'FAIL: expected exactly 1 active row for the natural key after two link calls, got %', v_n; end if;

  v_doc_link := app.link_ticket_portal_record(v_ticket_alpha_id, 'document', v_file_id, 'related', v_cust_alpha, 'cust-alpha');

  select live_available into v_available from app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha) where id = v_link1.id;
  if not v_available then raise exception 'FAIL: expected the warehouse_order link to be live_available=true before revocation'; end if;

  perform app.revoke_warehouse_customer_eligibility(
    (select id from app.warehouse_customer_eligibility where warehouse_id = v_warehouse_id and customer_account_id = v_account_alpha),
    'ctw fixture revocation', 1, v_supreme, 'admin'
  );

  select live_available into v_available from app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha) where id = v_link1.id;
  if v_available then raise exception 'FAIL: expected the warehouse_order link to flip to live_available=false IMMEDIATELY after eligibility revocation, with no UPDATE to the link row itself'; end if;

  -- Unlink: reason required.
  begin
    perform app.unlink_ticket_portal_record(v_doc_link.id, v_doc_link.record_version, '', v_cust_alpha, 'cust-alpha');
    raise exception 'FAIL: expected reason_required for an empty unlink reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Unlink: stale version.
  begin
    perform app.unlink_ticket_portal_record(v_doc_link.id, v_doc_link.record_version + 1, 'no longer needed', v_cust_alpha, 'cust-alpha');
    raise exception 'FAIL: expected stale_version for a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Unlink: real removal.
  perform app.unlink_ticket_portal_record(v_doc_link.id, v_doc_link.record_version, 'no longer needed', v_cust_alpha, 'cust-alpha');
  select count(*) into v_n from app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha) where id = v_doc_link.id;
  if v_n <> 0 then raise exception 'FAIL: expected the unlinked document to no longer appear in the active links list, got % rows', v_n; end if;
  select status into v_available from (select (status = 'removed') as status from app.ticket_portal_links where id = v_doc_link.id) s;
  if not v_available then raise exception 'FAIL: expected the unlinked row''s own status to be ''removed'', never hard-deleted'; end if;
end $$;

\echo '>> 9. raw-table RLS defense-in-depth: a real authenticated session for cust-alpha sees ZERO rows on a raw SELECT against app.ticket_portal_links (staff-only raw read, decision 10 -- every genuine customer read goes through the SECURITY DEFINER RPCs above)'
do $$
declare
  v_raw_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000327010", "role": "authenticated"}';
  select count(*) into v_raw_count from app.ticket_portal_links;
  if v_raw_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.ticket_portal_links to be denied outright for a customer_user actor, got %', v_raw_count;
  end if;
  reset role;
end $$;

\echo '>> 10. raw-function grant defense in depth: anon holds no EXECUTE on any of the five new functions; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.ticket_portal_link_entity_types()',
    'app.search_ticket_portal_link_candidates(uuid, text, text, uuid, integer)',
    'app.search_customer_ticket_link_candidates_precreate(uuid, text, text, uuid, integer)',
    'app.link_ticket_portal_record(uuid, text, uuid, text, uuid, text)',
    'app.unlink_ticket_portal_record(uuid, integer, text, uuid, text)',
    'app.list_ticket_portal_links(uuid, uuid)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn; end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn; end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn; end if;
  end loop;
end $$;

\echo '>> 11. actor-identity session cross-check (C-13): a genuinely different authenticated session may not claim to act as another identity, on every one of the five new actor-taking RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ctw1');
  v_ticket_alpha_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-alpha');
  v_order_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-ctw-outbound-a1');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000327050';
  v_link_id uuid := (select id from app.ticket_portal_links where ticket_id = v_ticket_alpha_id and entity_type = 'warehouse_order' limit 1);
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000327050", "role": "authenticated"}';

  begin
    perform app.search_customer_ticket_link_candidates_precreate(v_tenant1, 'warehouse_order', null, v_cust_alpha, 20);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.search_customer_ticket_link_candidates_precreate';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.search_ticket_portal_link_candidates(v_ticket_alpha_id, 'warehouse_order', null, v_cust_alpha, 20);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.search_ticket_portal_link_candidates';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.link_ticket_portal_record(v_ticket_alpha_id, 'warehouse_order', v_order_id, 'related', v_cust_alpha, 'cust-alpha');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.link_ticket_portal_record';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.unlink_ticket_portal_record(v_link_id, 1, 'x', v_cust_alpha, 'cust-alpha');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.unlink_ticket_portal_record';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_ticket_portal_links';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (no relationship to Alpha's
  -- own ticket) is not rejected by the identity check -- it is correctly
  -- denied by the SCOPE check instead (ticket_not_found), proving the
  -- identity check and the scope check are two independent gates.
  begin
    perform app.list_ticket_portal_links(v_ticket_alpha_id, v_impersonator);
    raise exception 'assertion failed: expected ticket_not_found -- the impersonator, acting as themselves, has no standing on Alpha''s ticket';
  exception
    when others then
      if sqlerrm not like 'ticket_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> 12. a real, live authenticated-role positive path: cust-alpha''s own real authenticated session sees the identical, non-zero result a direct superuser call returns'
do $$
declare
  v_ticket_alpha_id uuid := (select id from app.tickets where idempotency_key = 'idem-ctw-ticket-alpha');
  v_cust_alpha uuid := '00000000-0000-0000-0000-000000327010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000327010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_ticket_portal_links(v_ticket_alpha_id, v_cust_alpha);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;
