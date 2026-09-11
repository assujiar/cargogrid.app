-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 3
-- (operations-tms-core) batch 1 of ~N
-- (supabase/migrations/20260911000000_close_o1_query_layer_cluster3_batch1_dispatch_job_order_views.sql).
--
-- Proves, against a real disposable database: app.list_dispatch_ready_queue/
-- app.count_dispatch_ready_shipment_orders (status='assigned' only) and
-- app.list_dispatch_board/app.count_dispatch_board_shipment_orders (status in assigned/
-- dispatched/in_transit) both return the real shipment orders an owner or a
-- shared-org-unit member can see, with correct is_ready/blockers (a genuinely-ready
-- shipment order, cross-checked against a live app.evaluate_dispatch_readiness call) and
-- honest coalesce-to-default board columns (tracking_status='not_tracked' etc. when no
-- app.shipment_tracking_health row exists) for a shipment the board includes but the ready
-- queue excludes; a tenant member with no owner/org-unit/customer-account relationship to
-- the row sees zero rows/a zero count from every one of the four functions, never an
-- exception; a cross-tenant member sees zero; a Supreme Admin with ZERO tenant membership
-- bypasses; pagination (page_size=1 over 2 matching rows) is exact; and RULE A rejects a
-- claimed actor that does not match the real session identity.
--
-- app.get_job_order/app.get_job_order_for_handoff/app.list_job_orders and
-- app.get_job_order_handoff_for_quotation/app.list_job_order_handoffs all return the real
-- data an owner/shared-org-unit member can see; revenue_snapshot/credit_snapshot/payload/
-- payload_hash masking toggles correctly on COM:View selling price/COM:View cost (owner
-- lacks both -> masked; a shared-org-unit viewer holding both -> unmasked); a non-owning,
-- non-shared-org-unit, non-customer-account tenant member gets null/zero rows from every
-- one of the five functions, never an exception; cross-tenant denial and a Supreme Admin
-- zero-membership bypass both hold; list_job_orders' pagination (page_size=1, total_count
-- exact) and list_job_order_handoffs' p_limit clamp are exercised; RULE A is spot-checked
-- on two of the five functions; and -- the single most safety-critical assertion in this
-- batch -- app.get_job_order_for_handoff and app.get_job_order_handoff_for_quotation both
-- genuinely RAISE an exception whose message contains `ambiguous_context` once a second,
-- adversarially-inserted row (a raw INSERT bypassing app.prepare_job_order/
-- app.prepare_job_order_handoff entirely, exactly the schema-legal-but-application-
-- unreachable gap this migration's own header discloses) shares the same
-- source_handoff_id/quotation_id across two different tenants and a real actor (a Supreme
-- Admin) can see both matching rows.
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any of the 9
-- new functions in EITHER schema (app or public) -- the only defense that still holds if
-- PostgREST's own schema-exposure config were ever misconfigured to expose "app" -- and
-- (spot-checked on 3 of the 9) authenticated/service_role hold EXECUTE on both the app.*
-- function and its public.* wrapper, exactly as this migration's own GRANT PARITY section
-- declares.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c3 with an owner (org_user), a shared-org-unit viewer granted COM:View selling price + COM:View cost, a non-owning/non-shared-org-unit/non-customer-account member, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant gizmoo1c3 with its own admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
  v_com_role_id uuid;
  v_com_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998701', 'ownero1c3@example.test'),
    ('00000000-0000-0000-0000-000000998702', 'sharedvieweramo1c3@example.test'),
    ('00000000-0000-0000-0000-000000998703', 'deniedmembero1c3@example.test'),
    ('00000000-0000-0000-0000-000000998704', 'supremeo1c3@example.test'),
    ('00000000-0000-0000-0000-000000998705', 'othertenanto1c3@example.test');

  perform app.provision_tenant('acmeo1c3', 'Acme O1C3 Co', 'idem-acmeo1c3', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c3');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C3-CO', 'Acme O1C3 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998701', 'ownero1c3@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998701', 'org_user', v_tenant_id, null, 'tester');

  -- Same org_unit_id as the owner -- app.can_access_record's shared-org-unit branch
  -- admits this identity to every row owned by 998701 in this org unit, without being the
  -- owner itself. Also the masking-privileged identity below (COM:View selling price +
  -- COM:View cost) -- mirrors cluster 1 batch 1's own "owner lacks the permission, the
  -- shared-org-unit viewer holds it" fixture shape.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998702', 'sharedvieweramo1c3@example.test', 'Shared Viewer', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sharedvieweramo1c3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998702', 'org_user', v_tenant_id, null, 'tester');

  v_com_role_id := (app.create_role(v_tenant_id, 'COM Revenue Viewer', 'COM:View selling price + COM:View cost', 'tester')).id;
  v_com_draft := app.create_role_version(v_com_role_id, 'tester');
  perform app.set_role_version_permissions(v_com_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('View selling price', 'View cost')), 'tester');
  perform app.publish_role_version(v_com_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_com_role_id and status = 'published'), '00000000-0000-0000-0000-000000998702', '00000000-0000-0000-0000-000000998701', 'tester');

  -- A real active org_user member of the SAME tenant, but no org_unit (so the
  -- shared-org-unit branch never matches), not the owner of anything, and no
  -- customer-account membership -- the exact per-row denial (not tenant-membership
  -- denial) app.can_access_record's own coalesce(..., false) is meant to produce.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998703', 'deniedmembero1c3@example.test', 'Denied Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'deniedmembero1c3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998703', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998704', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c3', 'Gizmo O1C3 Co', 'idem-gizmoo1c3', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c3');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998705', 'othertenanto1c3@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998705', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors cluster 1 batch 1's own
-- app._o1c1b1_test_make_chain (scripts/db-tests/o1-query-layer-cluster1-batch1.sql),
-- trimmed to the lead->prospect->opportunity->quotation->job_order_handoff->job_order
-- chain this batch's own job-order functions need (no shipment_actual_costs/
-- job_profitability_snapshots/billing_readiness rows -- out of this batch's scope).
-- revenue_snapshot/credit_snapshot/payload both carry real, distinguishable jsonb content
-- (never '{}') so the masking assertions below can tell "masked" (null) apart from a
-- merely-empty-but-visible object.
create function app._o1c3b1_test_make_job_order_chain(p_tenant uuid, p_org_unit uuid, p_owner uuid, p_tag text)
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
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c3-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c3.test', 'fp-o1c3-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c3-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C3-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, jsonb_build_object('note', 'o1c3b1 handoff ' || p_tag, 'lineItemCount', 3), 'hash-o1c3-' || p_tag, p_owner, p_owner, p_org_unit, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot,
    credit_snapshot, acceptance_snapshot, status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C3-' || p_tag, v_handoff, v_quotation, v_account,
    jsonb_build_object('legalName', p_tag || ' Account'), '{}'::jsonb,
    jsonb_build_object('totalAmount', 5000000, 'currency', 'IDR'), '{}'::jsonb,
    jsonb_build_object('creditTermsDays', 30), '{}'::jsonb,
    'confirmed', p_owner, p_org_unit, 'tester'
  )
  returning id into v_job_order;

  return query select v_job_order, v_handoff, v_quotation, v_account;
end;
$$;

\echo '>> fixture: two job-order chains for acmeo1c3 (JOB-O1C3-A, JOB-O1C3-B -- both owned by 998701) and one for gizmoo1c3 (JOB-O1C3-G, owned by the other tenant''s admin), plus 3 shipment orders hung off JOB-O1C3-A (SO1/SO2 status=assigned + a real active resource assignment + planned_pickup_at -- trivially ready; SO3 status=in_transit, deliberately no resource assignment and no shipment_tracking_health row, to exercise the board''s own coalesce-to-honest-default columns)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_other_tenant_id uuid := (select id from app.tenants where slug = 'gizmoo1c3');
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3-CO');
  v_chain_a record;
  v_chain_b record;
  v_chain_g record;
  v_driver1_id uuid;
  v_driver2_id uuid;
  v_so1 uuid;
  v_so2 uuid;
  v_so3 uuid;
begin
  select * into v_chain_a from app._o1c3b1_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000998701', 'A');
  select * into v_chain_b from app._o1c3b1_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000998701', 'B');
  select * into v_chain_g from app._o1c3b1_test_make_job_order_chain(v_other_tenant_id, null, '00000000-0000-0000-0000-000000998705', 'G');

  -- Two distinct driver master records -- resource_assignments_active_resource_unique
  -- (ISS-2026-E2) allows at most one CURRENT, ACTIVE assignment per (tenant_id,
  -- resource_id), so SO1 and SO2 each need their own resource to both be genuinely ready
  -- at the same time.
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C3-1', 'O1C3 Driver 1', 'active', 'tester')
  returning id into v_driver1_id;
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C3-2', 'O1C3 Driver 2', 'active', 'tester')
  returning id into v_driver2_id;

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain_a.job_order_id, 'SHP-O1C3-1', 'idem-shp-o1c3-1', 'assigned', v_chain_a.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', '00000000-0000-0000-0000-000000998701', v_org_unit_id, 'tester'
  ) returning id into v_so1;
  insert into app.resource_assignments (id, tenant_id, shipment_order_id, role, resource_id, resource_snapshot, status, is_current, created_by)
  values (gen_random_uuid(), v_tenant_id, v_so1, 'driver', v_driver1_id, jsonb_build_object('code', 'DRV-O1C3-1', 'name', 'O1C3 Driver 1'), 'active', true, 'tester');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain_a.job_order_id, 'SHP-O1C3-2', 'idem-shp-o1c3-2', 'assigned', v_chain_a.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Bandung',
    now() + interval '2 days', '00000000-0000-0000-0000-000000998701', v_org_unit_id, 'tester'
  ) returning id into v_so2;
  insert into app.resource_assignments (id, tenant_id, shipment_order_id, role, resource_id, resource_snapshot, status, is_current, created_by)
  values (gen_random_uuid(), v_tenant_id, v_so2, 'driver', v_driver2_id, jsonb_build_object('code', 'DRV-O1C3-2', 'name', 'O1C3 Driver 2'), 'active', true, 'tester');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain_a.job_order_id, 'SHP-O1C3-3', 'idem-shp-o1c3-3', 'in_transit', v_chain_a.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Semarang',
    now() + interval '3 days', '00000000-0000-0000-0000-000000998701', v_org_unit_id, 'tester'
  ) returning id into v_so3;
end $$;

\echo '>> app.evaluate_dispatch_readiness: SHP-O1C3-1/2 are genuinely ready (status=assigned + active resource assignment + planned pickup, zero blocking exceptions) -- establishes the expected is_ready/blockers baseline the dispatch functions below must reproduce exactly'
do $$
declare
  v_so1 uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3-1');
  v_readiness record;
begin
  select * into v_readiness from app.evaluate_dispatch_readiness(v_so1);
  if v_readiness.is_ready is not true or v_readiness.blockers <> '[]'::jsonb then
    raise exception 'assertion failed (test setup bug): SHP-O1C3-1 must be trivially ready, got is_ready=% blockers=%', v_readiness.is_ready, v_readiness.blockers;
  end if;
  raise notice 'app.evaluate_dispatch_readiness proof: SHP-O1C3-1 is genuinely ready (is_ready=true, blockers=[])';
end $$;

\echo '>> app.count_dispatch_ready_shipment_orders / app.list_dispatch_ready_queue: owner and shared-org-unit viewer both see exactly 2 ready rows (correct is_ready/blockers); the denied member and a cross-tenant actor both see zero rows/a zero count (never an exception); Supreme Admin with zero membership bypasses'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_count bigint;
  v_row record;
begin
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701') into v_count;
  if v_count <> 2 then
    raise exception 'assertion failed: owner expected count=2 ready shipment orders, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998701');
  if v_count <> 2 then
    raise exception 'assertion failed: owner expected 2 rows from list_dispatch_ready_queue, got %', v_count;
  end if;
  select * into v_row from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998701') where shipment_number = 'SHP-O1C3-1';
  if v_row.is_ready is not true or v_row.blockers <> '[]'::jsonb then
    raise exception 'assertion failed: SHP-O1C3-1 must come back is_ready=true, blockers=[] from list_dispatch_ready_queue, got is_ready=% blockers=%', v_row.is_ready, v_row.blockers;
  end if;

  -- Shared-org-unit viewer (998702, not the owner) -- same 2 rows.
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998702') into v_count;
  if v_count <> 2 then
    raise exception 'assertion failed: shared-org-unit viewer expected count=2, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998702');
  if v_count <> 2 then
    raise exception 'assertion failed: shared-org-unit viewer expected 2 rows, got %', v_count;
  end if;

  -- Denied member: real acmeo1c3 tenant member, but no owner/org-unit/customer-account
  -- relationship to either row -- per-row denial, zero rows/zero count, no exception.
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998703') into v_count;
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must get count=0, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998703');
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows, got %', v_count;
  end if;

  -- Cross-tenant: gizmoo1c3's own admin has no standing in acmeo1c3 at all.
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998705') into v_count;
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must get count=0, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998705');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows, got %', v_count;
  end if;

  -- Supreme Admin, zero tenant membership anywhere -- bypasses.
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998704') into v_count;
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see count=2, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998704');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see 2 rows, got %', v_count;
  end if;

  raise notice 'app.count_dispatch_ready_shipment_orders/app.list_dispatch_ready_queue proof: owner + shared-org-unit viewer see 2 correctly-ready rows, denied member/cross-tenant actor see zero (no exception), Supreme Admin bypasses';
end $$;

\echo '>> app.count_dispatch_board_shipment_orders / app.list_dispatch_board: owner sees all 3 rows (assigned + assigned + in_transit -- the ready queue''s own status=assigned-only scope excludes SHP-O1C3-3, the board does not); SHP-O1C3-3''s is_ready/blockers are null (status <> assigned) and its tracking columns come back at their honest coalesce-to-default values (no app.shipment_tracking_health row exists for it); denied member/cross-tenant see zero; Supreme Admin bypasses'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_count bigint;
  v_row record;
begin
  select app.count_dispatch_board_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701') into v_count;
  if v_count <> 3 then
    raise exception 'assertion failed: owner expected count=3 board shipment orders, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_board(v_tenant_id, '00000000-0000-0000-0000-000000998701');
  if v_count <> 3 then
    raise exception 'assertion failed: owner expected 3 rows from list_dispatch_board, got %', v_count;
  end if;

  select * into v_row from app.list_dispatch_board(v_tenant_id, '00000000-0000-0000-0000-000000998701') where shipment_number = 'SHP-O1C3-3';
  if v_row.is_ready is not null or v_row.blockers is not null then
    raise exception 'assertion failed: SHP-O1C3-3 (status=in_transit) must carry null is_ready/blockers, got is_ready=% blockers=%', v_row.is_ready, v_row.blockers;
  end if;
  if v_row.has_active_assignment is not false then
    raise exception 'assertion failed: SHP-O1C3-3 has no resource assignment, expected has_active_assignment=false, got %', v_row.has_active_assignment;
  end if;
  if v_row.tracking_status <> 'not_tracked' or v_row.freshness_status <> 'unknown' or v_row.fallback_active is not false or v_row.tracking_exception_count <> 0 or v_row.authoritative_source_type is not null or v_row.last_position_at is not null or v_row.accuracy_meters is not null then
    raise exception 'assertion failed: SHP-O1C3-3 has no app.shipment_tracking_health row -- expected the honest coalesce-to-default projection, got tracking_status=% freshness_status=% fallback_active=% tracking_exception_count=% authoritative_source_type=% last_position_at=% accuracy_meters=%', v_row.tracking_status, v_row.freshness_status, v_row.fallback_active, v_row.tracking_exception_count, v_row.authoritative_source_type, v_row.last_position_at, v_row.accuracy_meters;
  end if;
  if v_row.tracking_entitled is not false then
    raise exception 'assertion failed: app.is_shipment_tracking_entitled is still the disclosed always-false stub -- expected tracking_entitled=false, got %', v_row.tracking_entitled;
  end if;

  select * into v_row from app.list_dispatch_board(v_tenant_id, '00000000-0000-0000-0000-000000998701') where shipment_number = 'SHP-O1C3-1';
  if v_row.is_ready is not true or v_row.has_active_assignment is not true then
    raise exception 'assertion failed: SHP-O1C3-1 (status=assigned, real active assignment) must carry is_ready=true, has_active_assignment=true on the board too, got is_ready=% has_active_assignment=%', v_row.is_ready, v_row.has_active_assignment;
  end if;

  select app.count_dispatch_board_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998703') into v_count;
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must get count=0 on the board, got %', v_count;
  end if;
  select count(*) into v_count from app.list_dispatch_board(v_tenant_id, '00000000-0000-0000-0000-000000998703');
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero board rows, got %', v_count;
  end if;

  select app.count_dispatch_board_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998705') into v_count;
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must get count=0 on the board, got %', v_count;
  end if;

  select app.count_dispatch_board_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998704') into v_count;
  if v_count <> 3 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see count=3 on the board, got %', v_count;
  end if;

  raise notice 'app.count_dispatch_board_shipment_orders/app.list_dispatch_board proof: owner sees all 3 rows (ready-queue-excluded SHP-O1C3-3 included), null is_ready/blockers + honest default tracking columns for the non-assigned/non-tracked row, denied member/cross-tenant see zero, Supreme Admin bypasses';
end $$;

\echo '>> pagination: app.list_dispatch_ready_queue with p_page_size=1 returns exactly 1 row per page across both pages of the owner''s 2 ready shipment orders, and app.count_dispatch_ready_shipment_orders still reports the true total (2)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_count bigint;
  v_page1_count integer;
  v_page2_count integer;
  v_page1_id uuid;
  v_page2_id uuid;
begin
  select app.count_dispatch_ready_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701') into v_count;
  if v_count <> 2 then
    raise exception 'assertion failed (test setup bug): expected exactly 2 ready shipment orders total, got %', v_count;
  end if;

  select count(*), (array_agg(id))[1] into v_page1_count, v_page1_id from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998701', 1, 1);
  if v_page1_count <> 1 then
    raise exception 'assertion failed: p_page=1/p_page_size=1 must return exactly 1 row, got %', v_page1_count;
  end if;

  select count(*), (array_agg(id))[1] into v_page2_count, v_page2_id from app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998701', 2, 1);
  if v_page2_count <> 1 then
    raise exception 'assertion failed: p_page=2/p_page_size=1 must return exactly 1 row, got %', v_page2_count;
  end if;

  if v_page1_id = v_page2_id then
    raise exception 'assertion failed: page 1 and page 2 (page_size=1) returned the SAME row -- pagination is not advancing';
  end if;

  raise notice 'app.list_dispatch_ready_queue pagination proof: page_size=1 returns exactly 1 distinct row per page across both pages, count reports the true total (2)';
end $$;

\echo '>> RULE A: app.list_dispatch_ready_queue and app.count_dispatch_board_shipment_orders both genuinely reject a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998705", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  begin
    begin
      -- Real session is 998705 (gizmoo1c3's own admin); claims to be 998701 (acmeo1c3's
      -- own owner, who WOULD otherwise see 2 rows) -- must still be rejected.
      perform app.list_dispatch_ready_queue(v_tenant_id, '00000000-0000-0000-0000-000000998701');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_dispatch_ready_queue)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_dispatch_ready_queue impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.count_dispatch_board_shipment_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (count_dispatch_board_shipment_orders)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: count_dispatch_board_shipment_orders impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_job_order / app.get_job_order_for_handoff / app.list_job_orders: owner and shared-org-unit viewer both reach JOB-O1C3-A; revenue_snapshot/credit_snapshot are masked (null, *_masked=true) for the owner (no COM:View selling price/cost) and unmasked (real values, *_masked=false) for the shared-org-unit viewer (holds both permissions); the denied member gets null/zero rows; cross-tenant denied; Supreme Admin bypasses'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_job_order_id uuid := (select id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_handoff_id uuid := (select source_handoff_id from app.job_orders where id = v_job_order_id);
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998701');
  if v_row.id is null or v_row.revenue_masked is not true or v_row.revenue_snapshot is not null or v_row.credit_masked is not true or v_row.credit_snapshot is not null then
    raise exception 'assertion failed: owner (no COM:View selling price/cost) must see JOB-O1C3-A masked, got revenue_masked=% revenue_snapshot=% credit_masked=% credit_snapshot=%', v_row.revenue_masked, v_row.revenue_snapshot, v_row.credit_masked, v_row.credit_snapshot;
  end if;

  select * into v_row from app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998702');
  if v_row.revenue_masked is not false or v_row.revenue_snapshot <> jsonb_build_object('totalAmount', 5000000, 'currency', 'IDR') or v_row.credit_masked is not false or v_row.credit_snapshot <> jsonb_build_object('creditTermsDays', 30) then
    raise exception 'assertion failed: shared-org-unit viewer (holds COM:View selling price/cost) must see JOB-O1C3-A unmasked, got revenue_masked=% revenue_snapshot=% credit_masked=% credit_snapshot=%', v_row.revenue_masked, v_row.revenue_snapshot, v_row.credit_masked, v_row.credit_snapshot;
  end if;

  select * into v_row from app.get_job_order_for_handoff(v_handoff_id, '00000000-0000-0000-0000-000000998701');
  if v_row.id is null or v_row.id <> v_job_order_id then
    raise exception 'assertion failed: owner must reach JOB-O1C3-A via get_job_order_for_handoff';
  end if;

  select count(*) into v_count from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701');
  if v_count <> 2 then
    raise exception 'assertion failed: owner expected 2 visible job orders (A, B) from list_job_orders, got %', v_count;
  end if;

  -- Denied member: real tenant member, but no owner/org-unit/customer-account
  -- relationship to JOB-O1C3-A -- null/zero, never an exception.
  if exists (select 1 from app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998703')) then
    raise exception 'assertion failed: denied member must get zero rows from get_job_order';
  end if;
  if exists (select 1 from app.get_job_order_for_handoff(v_handoff_id, '00000000-0000-0000-0000-000000998703')) then
    raise exception 'assertion failed: denied member must get zero rows from get_job_order_for_handoff';
  end if;
  select count(*) into v_count from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998703');
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows from list_job_orders, got %', v_count;
  end if;

  -- Cross-tenant: gizmoo1c3's own admin.
  if exists (select 1 from app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998705')) then
    raise exception 'assertion failed: cross-tenant actor must get zero rows from get_job_order';
  end if;
  select count(*) into v_count from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998705');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows from list_job_orders, got %', v_count;
  end if;

  -- Supreme Admin, zero tenant membership anywhere -- bypasses.
  select * into v_row from app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998704');
  if v_row.id is null then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must still reach JOB-O1C3-A via get_job_order';
  end if;
  select count(*) into v_count from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998704');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see 2 job orders, got %', v_count;
  end if;

  raise notice 'app.get_job_order/app.get_job_order_for_handoff/app.list_job_orders proof: masking toggles correctly on COM:View selling price/cost, denied member/cross-tenant actor get null/zero (no exception), Supreme Admin bypasses';
end $$;

\echo '>> pagination: app.list_job_orders with p_page_size=1 returns exactly 1 row and total_count=2 on BOTH page 1 and page 2 of the owner''s 2 visible job orders'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_row record;
  v_page1_id uuid;
  v_page2_id uuid;
begin
  select * into v_row from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701', 1, 1);
  if v_row.id is null or v_row.total_count <> 2 then
    raise exception 'assertion failed: page 1 (page_size=1) must return exactly 1 row with total_count=2, got id=% total_count=%', v_row.id, v_row.total_count;
  end if;
  v_page1_id := v_row.id;

  select * into v_row from app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701', 2, 1);
  if v_row.id is null or v_row.total_count <> 2 then
    raise exception 'assertion failed: page 2 (page_size=1) must return exactly 1 row with total_count=2, got id=% total_count=%', v_row.id, v_row.total_count;
  end if;
  v_page2_id := v_row.id;

  if v_page1_id = v_page2_id then
    raise exception 'assertion failed: page 1 and page 2 (page_size=1) returned the SAME job order -- pagination is not advancing';
  end if;

  raise notice 'app.list_job_orders pagination proof: page_size=1 returns exactly 1 distinct row with the correct exact total_count=2 on both pages';
end $$;

\echo '>> app.get_job_order_handoff_for_quotation / app.list_job_order_handoffs: owner and shared-org-unit viewer both reach the JOB-O1C3-A handoff; payload/payload_hash masking toggles the same way as revenue/credit above; denied member/cross-tenant get null/zero; Supreme Admin bypasses; p_limit clamp does not break a normal-sized result'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_quotation_id uuid := (select quotation_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998701');
  if v_row.id is null or v_row.payload_masked is not true or v_row.payload is not null or v_row.payload_hash is not null then
    raise exception 'assertion failed: owner (no COM:View selling price) must see the handoff masked, got payload_masked=% payload=% payload_hash=%', v_row.payload_masked, v_row.payload, v_row.payload_hash;
  end if;

  select * into v_row from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998702');
  if v_row.payload_masked is not false or v_row.payload <> jsonb_build_object('note', 'o1c3b1 handoff A', 'lineItemCount', 3) or v_row.payload_hash <> 'hash-o1c3-A' then
    raise exception 'assertion failed: shared-org-unit viewer (holds COM:View selling price) must see the handoff unmasked, got payload_masked=% payload=% payload_hash=%', v_row.payload_masked, v_row.payload, v_row.payload_hash;
  end if;

  select count(*) into v_count from app.list_job_order_handoffs(v_tenant_id, '00000000-0000-0000-0000-000000998701');
  if v_count <> 2 then
    raise exception 'assertion failed: owner expected 2 visible handoffs (A, B) from list_job_order_handoffs, got %', v_count;
  end if;

  -- p_limit clamp: a deliberately oversized p_limit=500 must not error, and must still
  -- return only the (small) real visible set -- not a literal 200-row stress test, just
  -- confirmation the least/greatest clamp logic does not break a normal-sized call.
  select count(*) into v_count from app.list_job_order_handoffs(v_tenant_id, '00000000-0000-0000-0000-000000998701', 500);
  if v_count <> 2 then
    raise exception 'assertion failed: p_limit=500 must still return exactly the 2 real visible handoffs (clamped, not erroring), got %', v_count;
  end if;

  if exists (select 1 from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998703')) then
    raise exception 'assertion failed: denied member must get zero rows from get_job_order_handoff_for_quotation';
  end if;
  select count(*) into v_count from app.list_job_order_handoffs(v_tenant_id, '00000000-0000-0000-0000-000000998703');
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows from list_job_order_handoffs, got %', v_count;
  end if;

  if exists (select 1 from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998705')) then
    raise exception 'assertion failed: cross-tenant actor must get zero rows from get_job_order_handoff_for_quotation';
  end if;
  select count(*) into v_count from app.list_job_order_handoffs(v_tenant_id, '00000000-0000-0000-0000-000000998705');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows from list_job_order_handoffs, got %', v_count;
  end if;

  select * into v_row from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998704');
  if v_row.id is null then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must still reach the handoff via get_job_order_handoff_for_quotation';
  end if;
  select count(*) into v_count from app.list_job_order_handoffs(v_tenant_id, '00000000-0000-0000-0000-000000998704');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see 2 handoffs, got %', v_count;
  end if;

  raise notice 'app.get_job_order_handoff_for_quotation/app.list_job_order_handoffs proof: payload masking toggles correctly, p_limit=500 clamp does not break a normal result, denied member/cross-tenant get null/zero, Supreme Admin bypasses';
end $$;

\echo '>> fixture: adversarial duplicate rows for the ambiguous_context tests below -- inserted only now (after every "exactly 1 match" assertion above has already run) so the Supreme Admin bypass checks above see a genuinely unambiguous single row, exactly like every other actor'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
  v_other_tenant_id uuid := (select id from app.tenants where slug = 'gizmoo1c3');
  v_handoff_a_id uuid := (select source_handoff_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_quotation_a_id uuid := (select quotation_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_quotation_g_id uuid := (select quotation_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'gizmoo1c3') and job_number = 'JOB-O1C3-G');
  v_account_g_id uuid := (select account_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'gizmoo1c3') and job_number = 'JOB-O1C3-G');
begin
  -- Adversarial fixture (this migration's own disclosed, schema-legal-but-application-
  -- unreachable gap): a raw INSERT into app.job_orders, bypassing app.prepare_job_order
  -- entirely, reusing chain A's own source_handoff_id but with tenant_id/quotation_id/
  -- account_id from the UNRELATED gizmoo1c3 tenant. Only a real Supreme Admin (bypasses
  -- has_active_tenant_membership for BOTH tenants) can ever see both this row and chain
  -- A's own job order -- an ordinary acmeo1c3-only actor still resolves to exactly 1 match.
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_other_tenant_id, 'JOB-O1C3-AMBIG', v_handoff_a_id, v_quotation_g_id, v_account_g_id,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    'confirmed', '00000000-0000-0000-0000-000000998705', null, 'tester'
  );

  -- Adversarial fixture, mirror shape: a raw INSERT into app.job_order_handoffs, bypassing
  -- app.prepare_job_order_handoff entirely, reusing chain A's own quotation_id but with
  -- tenant_id/account_id from gizmoo1c3. Same actor-visibility argument as above.
  -- owner_user_id is deliberately left NULL (unlike chain G's own real rows) -- 998705
  -- is otherwise used above as the plain "cross-tenant, no relationship" actor for
  -- acmeo1c3's own QA quotation, and this row must not accidentally hand it an owner
  -- match on that same quotation_id via the adversarial fixture.
  insert into app.job_order_handoffs (
    id, tenant_id, quotation_id, account_id, payload, payload_hash,
    prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_other_tenant_id, v_quotation_a_id, v_account_g_id,
    jsonb_build_object('note', 'ambiguous handoff'), 'hash-o1c3-ambig',
    '00000000-0000-0000-0000-000000998705', null, null, 'tester'
  );
end $$;

\echo '>> ambiguous_context (SAFETY-CRITICAL): app.get_job_order_for_handoff RAISES once a second app.job_orders row (raw INSERT, bypassing app.prepare_job_order) shares JOB-O1C3-A''s own source_handoff_id from a different tenant, for an actor (Supreme Admin) who can see BOTH matching rows -- an ordinary single-tenant actor still resolves to exactly 1 match, unaffected'
do $$
declare
  v_handoff_id uuid := (select source_handoff_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_row record;
  v_raised boolean := false;
begin
  -- Ordinary actor (owner, acmeo1c3-only): still exactly 1 match (the adversarial second
  -- row belongs to gizmoo1c3, which the owner has no standing in at all) -- no raise.
  select * into v_row from app.get_job_order_for_handoff(v_handoff_id, '00000000-0000-0000-0000-000000998701');
  if v_row.id is null or v_row.job_number <> 'JOB-O1C3-A' then
    raise exception 'assertion failed (test setup bug): the owner must still resolve get_job_order_for_handoff to exactly JOB-O1C3-A, unaffected by the adversarial cross-tenant row';
  end if;

  begin
    -- Supreme Admin bypasses has_active_tenant_membership AND ownership for BOTH
    -- tenants -- sees both JOB-O1C3-A and the adversarial JOB-O1C3-AMBIG row.
    perform app.get_job_order_for_handoff(v_handoff_id, '00000000-0000-0000-0000-000000998704');
  exception
    when check_violation then
      if position('ambiguous_context' in sqlerrm) = 0 then
        raise exception 'assertion failed: expected the raised message to contain "ambiguous_context", got: %', sqlerrm;
      end if;
      v_raised := true;
  end;

  if not v_raised then
    raise exception 'CRITICAL: app.get_job_order_for_handoff did not RAISE for an actor who can see 2 job_orders rows sharing one source_handoff_id -- the ambiguous_context guard is not working';
  end if;

  raise notice 'ambiguous_context proof (get_job_order_for_handoff): a genuine 2-tenant multi-row match RAISES an exception containing "ambiguous_context" for the one actor who can see both rows; an ordinary single-tenant actor is unaffected';
end $$;

\echo '>> ambiguous_context (SAFETY-CRITICAL): app.get_job_order_handoff_for_quotation RAISES once a second app.job_order_handoffs row (raw INSERT, bypassing app.prepare_job_order_handoff) shares JOB-O1C3-A''s own quotation_id from a different tenant, for an actor (Supreme Admin) who can see BOTH matching rows -- an ordinary single-tenant actor still resolves to exactly 1 match, unaffected'
do $$
declare
  v_quotation_id uuid := (select quotation_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  v_row record;
  v_raised boolean := false;
begin
  select * into v_row from app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998701');
  if v_row.id is null then
    raise exception 'assertion failed (test setup bug): the owner must still resolve get_job_order_handoff_for_quotation to exactly 1 row, unaffected by the adversarial cross-tenant row';
  end if;

  begin
    perform app.get_job_order_handoff_for_quotation(v_quotation_id, '00000000-0000-0000-0000-000000998704');
  exception
    when check_violation then
      if position('ambiguous_context' in sqlerrm) = 0 then
        raise exception 'assertion failed: expected the raised message to contain "ambiguous_context", got: %', sqlerrm;
      end if;
      v_raised := true;
  end;

  if not v_raised then
    raise exception 'CRITICAL: app.get_job_order_handoff_for_quotation did not RAISE for an actor who can see 2 job_order_handoffs rows sharing one quotation_id -- the ambiguous_context guard is not working';
  end if;

  raise notice 'ambiguous_context proof (get_job_order_handoff_for_quotation): a genuine 2-tenant multi-row match RAISES an exception containing "ambiguous_context" for the one actor who can see both rows; an ordinary single-tenant actor is unaffected';
end $$;

\echo '>> RULE A: app.get_job_order and app.list_job_orders both genuinely reject a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998705", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3');
    v_job_order_id uuid := (select id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeo1c3') and job_number = 'JOB-O1C3-A');
  begin
    begin
      -- Real session is 998705 (gizmoo1c3's own admin); claims to be 998701 (acmeo1c3's
      -- own owner, who WOULD otherwise see this job order) -- must still be rejected.
      perform app.get_job_order(v_job_order_id, '00000000-0000-0000-0000-000000998701');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (get_job_order)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: get_job_order impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.list_job_orders(v_tenant_id, '00000000-0000-0000-0000-000000998701');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_job_orders)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_job_orders impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 9 new cluster-3-batch-1 functions in either schema (app or public); authenticated/service_role (spot-checked on 3 of the 9) hold EXECUTE on both the app.* function and its public.* wrapper, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'count_dispatch_ready_shipment_orders',
      'list_dispatch_ready_queue',
      'count_dispatch_board_shipment_orders',
      'list_dispatch_board',
      'get_job_order',
      'get_job_order_for_handoff',
      'list_job_orders',
      'get_job_order_handoff_for_quotation',
      'list_job_order_handoffs'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 9 cluster-3-batch-1 functions (either schema), found % grants', v_count;
  end if;

  -- Spot-check 3 of the 9: authenticated AND service_role both hold EXECUTE on the
  -- app.* function AND its public.* wrapper (grant parity, ISS-2026-309).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in ('list_dispatch_board', 'get_job_order', 'list_job_order_handoffs')
    and grantee in ('authenticated', 'service_role');
  if v_count <> 3 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 12 grants (3 functions x 2 schemas x 2 grantees) for the spot-checked functions, found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 9 new cluster-3-batch-1 functions; authenticated/service_role hold the declared grant on both the app.* and public.* spot-checked functions';
end $$;

drop function app._o1c3b1_test_make_job_order_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster3-batch1.sql test suite passed -- cluster 3 batch 1 (dispatch + job order/job order lineage, 7/7 call sites) is now fully DONE'
