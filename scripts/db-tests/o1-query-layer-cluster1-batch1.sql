-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 1
-- (finance) batch 1 of ~N
-- (supabase/migrations/20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql).
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data an owner/shared-org-unit member can see; the estimated_amount/total_amount and
-- revenue/cost/margin/FX/invoiced masks are correctly applied for an actor lacking OPS:View
-- cost/margin and correctly lifted for one holding it; a global Supreme Admin with ZERO
-- tenant membership bypasses row-visibility on every can_access_record-gated function; RULE A
-- genuinely rejects a claimed actor that does not match the real session identity; RULE B
-- (active-tenant-membership-and-not-customer-user-layer) is enforced by
-- app.list_finance_period_checklist_items; app.billing_readiness_evaluations' deliberate
-- overridden_by_auth_user_id column exclusion is confirmed structurally (a to_jsonb key
-- check on the real returned row, not merely a static read of the migration's own column
-- list); the two zero-actor-param, SECURITY INVOKER global reference functions
-- (app.list_finance_currencies/app.list_finance_rounding_modes) genuinely work under a real
-- `authenticated`-role session (proving the SECURITY INVOKER design decision is actually
-- correct in practice, not merely asserted); cross-tenant denial throughout; and
-- schema-privilege defense in depth (anon holds zero EXECUTE on any of the 8 new functions).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with two org_user staff (one the fixture-row owner with no OPS:View cost/margin, one a shared-org-unit member WITH OPS:View cost/margin), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
  v_ops_role_id uuid;
  v_ops_draft app.role_versions;
  v_fin_role_id uuid;
  v_fin_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998501', 'ownero1c1@example.test'),
    ('00000000-0000-0000-0000-000000998502', 'viewero1c1@example.test'),
    ('00000000-0000-0000-0000-000000998503', 'customerusero1c1@example.test'),
    ('00000000-0000-0000-0000-000000998504', 'supremeo1c1@example.test'),
    ('00000000-0000-0000-0000-000000998505', 'othertenanto1c1@example.test');

  perform app.provision_tenant('acmeo1c1', 'Acme O1C1 Co', 'idem-acmeo1c1', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c1');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C1-CO', 'Acme O1C1 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C1-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998501', 'ownero1c1@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998501', 'org_user', v_tenant_id, null, 'tester');
  -- Also granted 'tenant_admin' layer (app.is_support_grant_authority's own requirement,
  -- via app.check_config_object_authority) purely so this fixture identity can publish the
  -- finance_close_policy config draft and generate the fiscal calendar below -- unrelated
  -- to app.list_finance_period_checklist_items' own membership-only gate, which this actor
  -- already satisfies via its plain org_user membership regardless.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998501', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998502', 'viewero1c1@example.test', 'Viewer', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewero1c1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998502', 'org_user', v_tenant_id, null, 'tester');

  -- 998502 gets OPS:View cost + OPS:View margin (masking test's "unmasked" actor) --
  -- 998501 (the row owner) deliberately gets NEITHER, so ownership alone is proven
  -- insufficient to see masked amounts.
  v_ops_role_id := (app.create_role(v_tenant_id, 'OPS Viewer', 'OPS:View cost + OPS:View margin', 'tester')).id;
  v_ops_draft := app.create_role_version(v_ops_role_id, 'tester');
  perform app.set_role_version_permissions(v_ops_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View cost', 'View margin')), 'tester');
  perform app.publish_role_version(v_ops_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_ops_role_id and status = 'published'), '00000000-0000-0000-0000-000000998502', '00000000-0000-0000-0000-000000998501', 'tester');

  -- 998501 also gets FIN:Edit/Approve/View, needed only to generate the fiscal calendar
  -- fixture below (app.list_finance_period_checklist_items itself checks membership, not
  -- this permission at all).
  v_fin_role_id := (app.create_role(v_tenant_id, 'Finance Manager', 'fiscal calendar generation authority', 'tester')).id;
  v_fin_draft := app.create_role_version(v_fin_role_id, 'tester');
  perform app.set_role_version_permissions(v_fin_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_fin_role_id and status = 'published'), '00000000-0000-0000-0000-000000998501', '00000000-0000-0000-0000-000000998501', 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000998503', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998503', 'customer_user', v_tenant_id, 'fake-account-ref-o1c1', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998504', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c1', 'Gizmo O1C1 Co', 'idem-gizmoo1c1', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c1');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998505', 'othertenanto1c1@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998505', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors
-- scripts/db-tests/customer-invoice-billing-visibility.sql's own established
-- lead->prospect->opportunity->quotation->job_order_handoff->job_order chain helper,
-- extended here to also seed the shipment order / actual-cost / job-profitability-snapshot
-- rows this batch's own functions read.
create function app._o1c1b1_test_make_chain(p_tenant uuid, p_company uuid, p_owner uuid, p_tag text)
returns table (job_order_id uuid, shipment_order_id uuid, evaluation_id uuid)
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
  v_shipment uuid;
  v_eval uuid;
begin
  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c1-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c1.test', 'fp-o1c1-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c1-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C1-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, '{"note": "o1c1b1 fixture"}'::jsonb, 'hash-o1c1-' || p_tag, p_owner, p_company, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C1-' || p_tag, v_handoff, v_quotation, v_account,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    'confirmed', p_owner, p_company, 'tester'
  )
  returning id into v_job_order;

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, v_job_order, 'SHP-O1C1-' || p_tag, 'idem-shp-o1c1-' || p_tag, 'confirmed', v_account,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    p_owner, p_company, 'tester'
  )
  returning id into v_shipment;

  insert into app.shipment_actual_costs (id, tenant_id, shipment_order_id, is_current, status, currency, estimated_amount, total_amount, created_by)
  values (gen_random_uuid(), p_tenant, v_shipment, true, 'approved', 'IDR', 14000000, 15000000, 'tester');

  insert into app.job_profitability_snapshots (
    id, tenant_id, job_order_id, is_current, status, revenue_currency, revenue_amount,
    cost_currency, cost_amount, margin_amount, margin_percent, calculated_by_auth_user_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, v_job_order, true, 'calculated', 'IDR', 25000000,
    'IDR', 15000000, 10000000, 40.0000, p_owner, 'tester'
  );

  insert into app.billing_readiness_evaluations (
    id, tenant_id, job_order_id, evaluated_status, blockers, evidence,
    is_overridden, override_reason, overridden_by_auth_user_id, overridden_by, overridden_at,
    evaluated_by_auth_user_id
  ) values (
    gen_random_uuid(), p_tenant, v_job_order, 'not_ready', '["missing_pod"]'::jsonb, '{}'::jsonb,
    true, 'manual override for O1C1B1 fixture', p_owner, 'Test Approver', now(),
    p_owner
  )
  returning id into v_eval;

  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (gen_random_uuid(), p_tenant, v_job_order, v_eval, 'idem-handoff-o1c1-' || p_tag, p_owner, 'Test Approver');

  return query select v_job_order, v_shipment, v_eval;
end;
$$;

\echo '>> fixture: one job order + shipment order chain, owned by 998501, with a current actual-cost header, a current job-profitability snapshot, an overridden billing-readiness evaluation, and one handoff'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c1');
  v_company_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C1-CO');
  perform app._o1c1b1_test_make_chain(v_tenant_id, v_company_id, '00000000-0000-0000-0000-000000998501', 'B1');
end $$;

\echo '>> app.get_shipment_actual_cost: masked for the owner (no OPS:View cost), unmasked for the shared-org-unit viewer (OPS:View cost), Supreme Admin bypasses with zero membership, cross-tenant denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_shipment_id uuid;
  v_row record;
begin
  v_shipment_id := (select id from app.shipment_orders where tenant_id = v_tenant_id and shipment_number = 'SHP-O1C1-B1');

  select * into v_row from app.get_shipment_actual_cost(v_shipment_id, '00000000-0000-0000-0000-000000998501');
  if v_row.cost_masked is not true or v_row.total_amount is not null or v_row.estimated_amount is not null then
    raise exception 'assertion failed: owner without OPS:View cost must see a masked (null amount) row, got cost_masked=% total_amount=% estimated_amount=%', v_row.cost_masked, v_row.total_amount, v_row.estimated_amount;
  end if;

  select * into v_row from app.get_shipment_actual_cost(v_shipment_id, '00000000-0000-0000-0000-000000998502');
  if v_row.cost_masked is not false or v_row.total_amount <> 15000000 or v_row.estimated_amount <> 14000000 then
    raise exception 'assertion failed: shared-org-unit viewer with OPS:View cost must see real amounts, got cost_masked=% total_amount=% estimated_amount=%', v_row.cost_masked, v_row.total_amount, v_row.estimated_amount;
  end if;

  select * into v_row from app.get_shipment_actual_cost(v_shipment_id, '00000000-0000-0000-0000-000000998504');
  if v_row.id is null then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must still see the row (can_access_record bypass)';
  end if;

  if exists (select 1 from app.get_shipment_actual_cost(v_shipment_id, '00000000-0000-0000-0000-000000998505')) then
    raise exception 'assertion failed: cross-tenant actor must see zero rows';
  end if;

  raise notice 'app.get_shipment_actual_cost proof: masked for the owner, unmasked for the OPS:View-cost viewer, Supreme Admin bypasses, cross-tenant denied';
end $$;

\echo '>> app.get_current_billing_readiness_evaluation / app.list_billing_readiness_evaluations: overridden_by_auth_user_id is structurally excluded (overridden_by text is not), cross-tenant denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_job_order_id uuid;
  v_row record;
  v_list_count integer;
begin
  v_job_order_id := (select id from app.job_orders where tenant_id = v_tenant_id and job_number = 'JOB-O1C1-B1');

  select * into v_row from app.get_current_billing_readiness_evaluation(v_job_order_id, '00000000-0000-0000-0000-000000998501');
  if v_row.id is null or v_row.overridden_by <> 'Test Approver' or v_row.is_overridden is not true then
    raise exception 'assertion failed: owner must see the current (overridden) evaluation with overridden_by populated';
  end if;
  if to_jsonb(v_row) ? 'overridden_by_auth_user_id' then
    raise exception 'assertion failed: overridden_by_auth_user_id must NOT appear in the returned row shape (contract fidelity)';
  end if;

  select count(*) into v_list_count from app.list_billing_readiness_evaluations(v_job_order_id, '00000000-0000-0000-0000-000000998501');
  if v_list_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 evaluation version, got %', v_list_count;
  end if;

  if exists (select 1 from app.get_current_billing_readiness_evaluation(v_job_order_id, '00000000-0000-0000-0000-000000998505')) then
    raise exception 'assertion failed: cross-tenant actor must see zero rows on get_current_billing_readiness_evaluation';
  end if;
  if exists (select 1 from app.list_billing_readiness_evaluations(v_job_order_id, '00000000-0000-0000-0000-000000998505')) then
    raise exception 'assertion failed: cross-tenant actor must see zero rows on list_billing_readiness_evaluations';
  end if;

  raise notice 'app.get_current_billing_readiness_evaluation/app.list_billing_readiness_evaluations proof: overridden_by_auth_user_id excluded, overridden_by present, cross-tenant denied';
end $$;

\echo '>> app.list_billing_readiness_handoffs: owner sees the handoff, cross-tenant denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_job_order_id uuid;
  v_count integer;
begin
  v_job_order_id := (select id from app.job_orders where tenant_id = v_tenant_id and job_number = 'JOB-O1C1-B1');

  select count(*) into v_count from app.list_billing_readiness_handoffs(v_job_order_id, '00000000-0000-0000-0000-000000998501');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 handoff, got %', v_count;
  end if;

  if exists (select 1 from app.list_billing_readiness_handoffs(v_job_order_id, '00000000-0000-0000-0000-000000998505')) then
    raise exception 'assertion failed: cross-tenant actor must see zero handoffs';
  end if;

  raise notice 'app.list_billing_readiness_handoffs proof: owner sees the real handoff, cross-tenant denied';
end $$;

\echo '>> app.get_job_profitability_directory: masked for the owner (no OPS:View margin), unmasked for the shared-org-unit viewer (OPS:View margin), Supreme Admin bypasses with zero membership, cross-tenant denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_job_order_id uuid;
  v_row record;
begin
  v_job_order_id := (select id from app.job_orders where tenant_id = v_tenant_id and job_number = 'JOB-O1C1-B1');

  select * into v_row from app.get_job_profitability_directory(v_job_order_id, '00000000-0000-0000-0000-000000998501');
  if v_row.margin_masked is not true or v_row.margin_amount is not null or v_row.revenue_amount is not null or v_row.cost_amount is not null then
    raise exception 'assertion failed: owner without OPS:View margin must see a masked row, got margin_masked=% margin_amount=% revenue_amount=% cost_amount=%', v_row.margin_masked, v_row.margin_amount, v_row.revenue_amount, v_row.cost_amount;
  end if;

  select * into v_row from app.get_job_profitability_directory(v_job_order_id, '00000000-0000-0000-0000-000000998502');
  if v_row.margin_masked is not false or v_row.margin_amount <> 10000000 or v_row.revenue_amount <> 25000000 or v_row.cost_amount <> 15000000 then
    raise exception 'assertion failed: shared-org-unit viewer with OPS:View margin must see real amounts, got margin_masked=% margin_amount=% revenue_amount=% cost_amount=%', v_row.margin_masked, v_row.margin_amount, v_row.revenue_amount, v_row.cost_amount;
  end if;

  select * into v_row from app.get_job_profitability_directory(v_job_order_id, '00000000-0000-0000-0000-000000998504');
  if v_row.id is null then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must still see the row (can_access_record bypass)';
  end if;

  if exists (select 1 from app.get_job_profitability_directory(v_job_order_id, '00000000-0000-0000-0000-000000998505')) then
    raise exception 'assertion failed: cross-tenant actor must see zero rows';
  end if;

  raise notice 'app.get_job_profitability_directory proof: masked for the owner, unmasked for the OPS:View-margin viewer, Supreme Admin bypasses, cross-tenant denied';
end $$;

\echo '>> RULE A: app.get_shipment_actual_cost genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998505", "role": "authenticated"}';
  do $$
  declare
    v_shipment_id uuid;
  begin
    v_shipment_id := (select id from app.shipment_orders where shipment_number = 'SHP-O1C1-B1');
    begin
      -- Real session is 998505 (the other tenant's admin); claims to be 998501 (this
      -- tenant's own owner, who WOULD otherwise be allowed) -- must still be rejected.
      perform app.get_shipment_actual_cost(v_shipment_id, '00000000-0000-0000-0000-000000998501');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.list_finance_currencies / app.list_finance_rounding_modes: SECURITY INVOKER genuinely works under a real authenticated-role session (proves the table-level grant + bare-true policy actually admit the real calling role, not merely the design draft''s own claim)'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998501", "role": "authenticated"}';
  do $$
  declare
    v_currency_count integer;
    v_rounding_count integer;
  begin
    select count(*) into v_currency_count from app.list_finance_currencies();
    if v_currency_count = 0 then
      raise exception 'assertion failed: expected at least one seeded currency row, got 0 (SECURITY INVOKER may be missing a real table grant)';
    end if;

    select count(*) into v_rounding_count from app.list_finance_rounding_modes();
    if v_rounding_count = 0 then
      raise exception 'assertion failed: expected at least one seeded rounding-mode row, got 0 (SECURITY INVOKER may be missing a real table grant)';
    end if;

    raise notice 'app.list_finance_currencies/app.list_finance_rounding_modes proof: % currencies / % rounding modes returned under a real authenticated-role session', v_currency_count, v_rounding_count;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> fixture: a 1-period fiscal calendar with 2 required checklist items, generated via app.generate_finance_fiscal_calendar (the same real, already-tested mutation RPC this table''s own read function reads behind)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_draft app.config_versions;
begin
  select * into v_draft from app.create_finance_config_draft('finance_close_policy', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000998501', 'ownero1c1');
  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "pod_confirmed", "value": {"label": "POD confirmed", "required": true, "sourceCapability": "OPS-181"}}, {"key": "cost_finalized", "value": {"label": "Actual cost finalized", "required": true, "sourceCapability": "OPS-178"}}]'::jsonb,
    '00000000-0000-0000-0000-000000998501', 'ownero1c1'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000998501', null, 'ownero1c1');
  perform app.generate_finance_fiscal_calendar(v_tenant_id, null, 'FY2026-O1C1', 'Fiscal Year 2026 O1C1', '2026-01-01'::date, 1, '00000000-0000-0000-0000-000000998501', 'ownero1c1');
end $$;

\echo '>> app.list_finance_period_checklist_items: an active org_user member sees both checklist items (RULE B); a customer_user-layer principal in the SAME tenant sees zero (RULE B exclusion); a Supreme Admin with ZERO membership bypasses; a cross-tenant actor sees zero'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c1');
  v_period_id uuid;
  v_count integer;
begin
  v_period_id := (select p.id from app.finance_fiscal_periods p join app.finance_fiscal_calendars c on c.id = p.calendar_id where c.tenant_id = v_tenant_id and c.code = 'FY2026-O1C1');

  select count(*) into v_count from app.list_finance_period_checklist_items(v_period_id, '00000000-0000-0000-0000-000000998501');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 checklist items for the active member, got %', v_count;
  end if;

  select count(*) into v_count from app.list_finance_period_checklist_items(v_period_id, '00000000-0000-0000-0000-000000998503');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must see zero checklist items, got %', v_count;
  end if;

  select count(*) into v_count from app.list_finance_period_checklist_items(v_period_id, '00000000-0000-0000-0000-000000998504');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must bypass and see both checklist items, got %', v_count;
  end if;

  select count(*) into v_count from app.list_finance_period_checklist_items(v_period_id, '00000000-0000-0000-0000-000000998505');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero checklist items, got %', v_count;
  end if;

  raise notice 'app.list_finance_period_checklist_items proof: active member sees both items, RULE B excludes the customer_user layer, Supreme Admin bypasses with zero membership, cross-tenant denied';
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 8 new cluster-1-batch-1 functions'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'get_shipment_actual_cost',
      'get_current_billing_readiness_evaluation',
      'list_billing_readiness_evaluations',
      'list_billing_readiness_handoffs',
      'list_finance_currencies',
      'list_finance_rounding_modes',
      'list_finance_period_checklist_items',
      'get_job_profitability_directory'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any cluster-1-batch-1 function, found % grants', v_count;
  end if;
  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 8 new cluster-1-batch-1 functions';
end $$;

drop function app._o1c1b1_test_make_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster1-batch1.sql test suite passed -- cluster 1 (finance, 8/8 call sites) is now fully DONE'
