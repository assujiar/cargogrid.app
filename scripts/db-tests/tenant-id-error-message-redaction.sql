-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Regression evidence for the representative repository-wide fix pass (5 migrations,
-- 20260902100000-20260902104000, 120 functions across Finance/HRIS/Procurement/
-- Ticketing/Platform Core). Proves, for one function per module (including the exact
-- Platform Core function the original disclosure live-reproduced,
-- app.approve_dedicated_deployment_qualification):
--
--   1. A caller with ZERO relationship to the record's real tenant (never invited,
--      no app.principal_memberships row anywhere for that tenant) gets a GENERIC
--      not-found error whose text does NOT contain the record's real tenant_id --
--      the fix.
--   2. A genuine member of that SAME tenant who simply lacks the specific role
--      authority still gets the ORIGINAL, specific insufficient_authority message,
--      WITH the tenant_id in it -- unchanged, since that tenant_id is not a new
--      disclosure to an actor who already belongs to the tenant. Same errcode class
--      (insufficient_privilege) as before this fix, proving the underlying refusal
--      is untouched -- only the ordering/gating relative to a cross-tenant caller
--      moved.
--
-- Not exhaustive by design (120 functions is out of scope for one test file) -- a
-- representative cross-section, one per module, per this item's own regression-proof
-- instructions in docs/runtime/KNOWN_ISSUES.md's ISS-2026-146 entry.
--
-- The SECOND half of this file (below the first five module blocks) extends the same
-- two-sided proof to the cross-cutting harden_* tranche that followed: migrations
-- 20260903120000-20260903123000, a further 115 functions across Operations,
-- WMS/warehouse, HRIS/payroll/imports, and Procurement/integrations/platform. It probes
-- five representative functions, one of which (app.update_wms_inbound_order_line) carries
-- the tranche's second remedy shape, and additionally proves the outsider's error is
-- byte-identical to the one a genuinely nonexistent id produces.

\set ON_ERROR_STOP on

\echo '>> ISS-2026-146 setup: tenant1 (real records live here) with an admin (full FIN/HRS/PRC/TKT/DEPLOY authority, used only to create fixture records) and a zero-role member (real tenant1 membership, no role assignment -- the "genuine same-tenant member without authority" case). A separate identity has NO relationship to tenant1 at all (never invited, no membership row) -- the "outsider" case this fix closes.'
do $$
declare
  v_tenant1 uuid;
  v_admin uuid := '00000000-0000-0000-0000-0000000146a1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_supreme uuid := '00000000-0000-0000-0000-0000000146a0';
  v_role_id uuid;
  v_role_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iss146.test'),
    (v_admin, 'admin@iss146.test'),
    (v_member_no_auth, 'memberzero@iss146.test'),
    (v_outsider, 'outsider@iss146.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iss146t1', 'ISS-2026-146 Tenant 1', 'idem-iss146-t1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iss146t1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin, 'admin@iss146.test', 'ISS146 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iss146.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_member_no_auth, 'memberzero@iss146.test', 'ISS146 Zero Role Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberzero@iss146.test'), 'active', 'onboarded', 'tester');
  -- Real membership, deliberately NO role assignment -- proves "genuinely belongs to
  -- the tenant but lacks specific authority" without granting a single permission.
  perform app.grant_principal_membership(v_member_no_auth, 'org_user', v_tenant1, null, 'tester');

  -- v_outsider is registered in auth.users only -- never invited to tenant1, never
  -- granted any principal membership anywhere. This is the caller class the original
  -- disclosure let learn a foreign tenant's real UUID.

  -- ISS-2026-146 (cross-cutting harden_* tranche, 20260903120000-20260903123000):
  -- 'OPS' added to this fixture role's module list so the same admin can also create
  -- the Operations/WMS fixture records the second half of this file probes. Purely
  -- additive -- every assertion already in this file concerns FIN/HRS/PRC/TKT/DEPLOY
  -- denials for the zero-role member, which no OPS grant on a DIFFERENT identity touches.
  v_role_id := (app.create_role(v_tenant1, 'ISS146 Full Admin', 'full FIN/HRS/PRC/TKT/DEPLOY/OPS authority for fixture setup', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = any(array['FIN', 'HRS', 'PRC', 'TKT', 'DEPLOY', 'OPS'])), 'tester');
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  -- Assigned by a genuine Supreme Admin, never self-assigned: this role carries
  -- DEPLOY authority, a protected permission class app.assign_role's own
  -- self-escalation guard refuses to let an actor grant themselves.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role_id and status = 'published'), v_admin, v_supreme, 'supreme');
end;
$$;

\echo '>> ISS-2026-146 setup: one real record per module, created by the admin in tenant1 -- these are the records an outsider will probe below'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_admin uuid := '00000000-0000-0000-0000-0000000146a1';
  v_org_unit app.org_units;
  v_account app.finance_accounts;
  v_competency app.training_competencies;
  v_policy app.vendor_bill_match_tolerance_policies;
  v_calendar app.sla_calendars;
  v_calendar_version app.sla_calendar_versions;
  v_deployment app.tenant_deployment_records;
begin
  v_org_unit := app.create_org_unit(v_tenant1, 'company', null, 'ISS146-CO', 'ISS146 Co', 'tester');

  -- Finance: app.amend_finance_account_draft is the fixed function under test.
  v_account := app.create_finance_account_draft(v_tenant1, v_org_unit.id, 'ISS146-1000', 'ISS146 Test Asset', 'asset', 'debit', null, false, null, v_admin, 'tester');

  -- HRIS: app.archive_training_competency is the fixed function under test.
  v_competency := app.create_training_competency(v_tenant1, 'iss146_comp', 'ISS146 Test Competency', 'regression fixture', 'technical', v_admin, 'tester');

  -- Procurement: app.update_vendor_bill_match_tolerance_policy_draft is the fixed
  -- function under test.
  v_policy := app.create_vendor_bill_match_tolerance_policy_draft(v_tenant1, 'ISS146 Test Policy', 2, 2, 1, 5, false, 30, null, 'idem-iss146-policy', v_admin, 'tester');

  -- Ticketing: app.add_sla_calendar_business_hours is the fixed function under test.
  v_calendar := app.create_sla_calendar(v_tenant1, 'ISS146-CAL', 'ISS146 Test Calendar', v_admin, 'tester');
  v_calendar_version := app.create_sla_calendar_version(v_calendar.id, 'UTC', false, v_admin, 'tester');

  -- Platform Core: app.approve_dedicated_deployment_qualification is the fixed
  -- function under test -- the EXACT function this entry's own live reproduction
  -- (IAE-032) named.
  v_deployment := app.request_dedicated_deployment_qualification(v_tenant1, 'ISS-2026-146 regression fixture', 'contract-ref-iss146', v_admin, 'tester');

  if v_account.id is null or v_competency.id is null or v_policy.id is null or v_calendar_version.id is null or v_deployment.id is null then
    raise exception 'assertion failed: test precondition failed -- one or more fixture records were not created';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (Finance): app.amend_finance_account_draft -- outsider gets a generic finance_account_not_found with NO tenant_id, real member without FIN:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant1 and code = 'ISS146-1000');
  v_msg text;
begin
  begin
    perform app.amend_finance_account_draft(v_account_id, 1, 'renamed', null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected finance_account_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'finance_account_not_found' then
        raise exception 'assertion failed: expected finance_account_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.amend_finance_account_draft(v_account_id, 1, 'renamed', null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no FIN role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'FIN:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority FIN:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (HRIS): app.archive_training_competency -- outsider gets a generic training_competency_not_found with NO tenant_id, real member without HRS:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_competency_id uuid := (select id from app.training_competencies where tenant_id = v_tenant1 and code = 'iss146_comp');
  v_msg text;
begin
  begin
    perform app.archive_training_competency(v_competency_id, 1, v_outsider, 'outsider');
    raise exception 'assertion failed: expected training_competency_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'training_competency_not_found' then
        raise exception 'assertion failed: expected training_competency_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.archive_training_competency(v_competency_id, 1, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no HRS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'HRS:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority HRS:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement): app.update_vendor_bill_match_tolerance_policy_draft -- outsider gets a generic vendor_bill_match_tolerance_policy_not_found with NO tenant_id, real member without PRC:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_policy_id uuid := (select id from app.vendor_bill_match_tolerance_policies where tenant_id = v_tenant1 and name = 'ISS146 Test Policy');
  v_msg text;
begin
  begin
    perform app.update_vendor_bill_match_tolerance_policy_draft(v_policy_id, 1, 'ISS146 renamed', 2, 2, 1, 5, false, 30, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected vendor_bill_match_tolerance_policy_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_bill_match_tolerance_policy_not_found' then
        raise exception 'assertion failed: expected vendor_bill_match_tolerance_policy_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.update_vendor_bill_match_tolerance_policy_draft(v_policy_id, 1, 'ISS146 renamed', 2, 2, 1, 5, false, 30, null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Ticketing): app.add_sla_calendar_business_hours -- outsider gets a generic sla_calendar_version_not_found with NO tenant_id, real member without TKT:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_calendar_version_id uuid := (
    select cv.id from app.sla_calendar_versions cv
    join app.sla_calendars c on c.id = cv.calendar_id
    where c.tenant_id = v_tenant1 and c.code = 'ISS146-CAL'
  );
  v_msg text;
begin
  begin
    perform app.add_sla_calendar_business_hours(v_calendar_version_id, 1::smallint, '09:00'::time, '17:00'::time, v_outsider, 'outsider');
    raise exception 'assertion failed: expected sla_calendar_version_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'sla_calendar_version_not_found' then
        raise exception 'assertion failed: expected sla_calendar_version_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.add_sla_calendar_business_hours(v_calendar_version_id, 1::smallint, '09:00'::time, '17:00'::time, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no TKT role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'TKT:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority TKT:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Platform Core): app.approve_dedicated_deployment_qualification -- the EXACT function this entry live-reproduced (IAE-032). Outsider gets a generic deployment_record_not_pending_qualification with NO tenant_id, real member without DEPLOY:Approve still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_deployment_id uuid := (select id from app.tenant_deployment_records where tenant_id = v_tenant1);
  v_msg text;
begin
  begin
    perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_outsider, 'outsider');
    raise exception 'assertion failed: expected deployment_record_not_pending_qualification for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'deployment_record_not_pending_qualification' then
        raise exception 'assertion failed: expected deployment_record_not_pending_qualification, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no DEPLOY role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'DEPLOY:Approve' then
        raise exception 'assertion failed: expected the original insufficient_authority DEPLOY:Approve message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146: all 5 modules PASSED -- outsider probes never see the real tenant_id, genuine same-tenant refusals are byte-identical to before this fix'

-- ===========================================================================
-- ISS-2026-146, cross-cutting harden_* tranche (migrations 20260903120000,
-- 20260903121000, 20260903122000, 20260903123000 -- 115 further functions across
-- Operations, WMS/warehouse, HRIS/payroll/imports, and Procurement/integrations/
-- platform). Same two-sided proof as above, for a representative function from each
-- of the four new parts, PLUS one function fixed with the second (shape B) remedy:
-- app.update_wms_inbound_order_line, whose disclosing row (the parent inbound order)
-- is reached by FK from an already-guarded line, so its own lookup had no not-found
-- branch to fold into and a NEW guard reusing the sibling's identical generic
-- 'line_not_found' message/errcode was added instead. That case additionally proves
-- the outsider's error is INDISTINGUISHABLE from the one a nonexistent id produces.
-- ===========================================================================

\echo '>> ISS-2026-146 part 2 setup: one real Operations/WMS/payroll/master-data record per new migration part, created by the same tenant1 admin -- the records an outsider probes below'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_supreme uuid := '00000000-0000-0000-0000-0000000146a0';
  -- A SECOND full-authority fixture identity, distinct from the file's own v_admin only
  -- in that it is seated in the ISS146-CO company org unit. The Operations/WMS creators
  -- below additionally gate on app.can_access_record against the record's own org-unit
  -- subtree, which an org-unit-less identity (v_admin, invited with a null org unit)
  -- cannot satisfy. Nothing this identity does is probed -- it only builds fixtures.
  v_ops_admin uuid := '00000000-0000-0000-0000-0000000146a4';
  v_org_unit uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ISS146-CO');
  v_wh app.warehouses;
  v_device app.gps_devices;
  v_period app.payroll_periods;
  v_master app.master_records;
  v_account app.accounts;
  v_item app.item_masters;
  v_inbound app.wms_inbound_orders;
  v_line app.wms_inbound_order_lines;
begin
  insert into auth.users (id, email) values (v_ops_admin, 'opsadmin@iss146.test');
  perform app.invite_user(v_tenant1, v_ops_admin, 'opsadmin@iss146.test', 'ISS146 Ops Admin', v_org_unit, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'opsadmin@iss146.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_ops_admin, 'tenant_admin', v_tenant1, null, 'tester');
  perform app.assign_role(
    v_tenant1,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id
     where r.tenant_id = v_tenant1 and r.name = 'ISS146 Full Admin' and rv.status = 'published'),
    v_ops_admin, v_supreme, 'supreme'
  );

  -- Part 1 (Operations): app.deregister_gps_device is the fixed function under test.
  v_device := app.register_gps_device(v_tenant1, '860000000000146', 'ISS146 Tracker', 'cargogrid', v_ops_admin, 'tester');

  -- Part 2 (WMS/warehouse): app.update_warehouse (shape A) and
  -- app.update_wms_inbound_order_line (shape B) are the fixed functions under test.
  v_wh := app.create_warehouse(v_tenant1, v_org_unit, 'ISS146-WH-1', 'ISS146 Warehouse 1', 'Jl. ISS146 No. 1', 'Asia/Jakarta', null, array['land']::text[], v_ops_admin, 'tester');

  -- Direct account fixture insert -- bypasses the full lead->prospect->quotation->
  -- convert Commercial pipeline, out of scope for this test; the established
  -- convention of scripts/db-tests/advanced-tms-customer-inventory-access.sql.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'ISS146 Customer', 'iss146-account-fp', '{}'::jsonb, v_org_unit, 'tester')
  returning * into v_account;

  v_item := app.create_item_master(v_tenant1, v_account.id, 'ISS146-SKU-1', 'ISS146 Widget', null, 'PCS', false, false, false, v_ops_admin, 'tester');
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh.id, v_account.id, 'ISS-2026-146 regression fixture', 'idem-iss146-inbound', v_ops_admin, 'tester');
  v_line := app.add_wms_inbound_order_line(v_inbound.id, v_item.id, 'PCS', 10, null, v_ops_admin, 'tester');

  -- Part 3 (HRIS/payroll): app.freeze_payroll_period_inputs is the fixed function under test.
  v_period := app.create_payroll_period(v_tenant1, null, 'iss146-2026-09', 'monthly', '2026-09-01', '2026-09-30', '2026-10-05', v_ops_admin, 'tester');

  -- Part 4 (platform master data): app.update_master_record is the fixed function under test.
  v_master := app.create_master_record('fleet', v_tenant1, 'ISS146-FLEET-1', 'ISS146 Fleet Truck 1', null, null, v_ops_admin, 'tester');

  if v_device.id is null or v_wh.id is null or v_line.id is null or v_period.id is null or v_master.id is null then
    raise exception 'assertion failed: test precondition failed -- one or more ISS-2026-146 part 2 fixture records were not created';
  end if;
  if v_inbound.status <> 'draft' then
    raise exception 'assertion failed: test precondition failed -- the inbound order must be draft for the line-edit probe to reach its authority check, got %', v_inbound.status;
  end if;
end;
$$;

\echo '>> ISS-2026-146 (Operations, migration 20260903120000): app.deregister_gps_device -- outsider gets a generic device_not_found with NO tenant_id, real member without OPS:Override still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_device_id uuid := (select id from app.gps_devices where tenant_id = v_tenant1 and imei = '860000000000146');
  v_version integer := (select record_version from app.gps_devices where tenant_id = v_tenant1 and imei = '860000000000146');
  v_msg text;
begin
  begin
    perform app.deregister_gps_device(v_device_id, 'iss146 outsider probe', v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected device_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'device_not_found' then
        raise exception 'assertion failed: expected device_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.deregister_gps_device(v_device_id, 'iss146 member probe', v_version, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:Override' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:Override message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (WMS/warehouse, migration 20260903121000): app.update_warehouse -- outsider gets a generic warehouse_not_found with NO tenant_id (identical to the error a nonexistent warehouse id produces), real member without OPS:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_wh_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'ISS146-WH-1');
  v_version integer := (select record_version from app.warehouses where tenant_id = v_tenant1 and code = 'ISS146-WH-1');
  v_absent_id uuid := '00000000-0000-0000-0000-0000000146ff';
  v_msg text;
  v_absent_msg text;
begin
  begin
    perform app.update_warehouse(v_wh_id, 'ISS146 Warehouse 1', null, 'Asia/Jakarta', null, array['land']::text[], v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected warehouse_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'warehouse_not_found' then
        raise exception 'assertion failed: expected warehouse_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  -- The oracle this fix closes: a REAL foreign warehouse id and a genuinely
  -- nonexistent one must be indistinguishable to a zero-membership caller.
  begin
    perform app.update_warehouse(v_absent_id, 'ISS146 Warehouse 1', null, 'Asia/Jakarta', null, array['land']::text[], v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected warehouse_not_found for a genuinely nonexistent warehouse id';
  exception
    when no_data_found then
      get stacked diagnostics v_absent_msg = message_text;
  end;
  if replace(v_msg, v_wh_id::text, '<id>') <> replace(v_absent_msg, v_absent_id::text, '<id>') then
    raise exception 'assertion failed: the outsider can still tell a REAL foreign warehouse from a nonexistent one -- real=% absent=%', v_msg, v_absent_msg;
  end if;

  begin
    perform app.update_warehouse(v_wh_id, 'ISS146 Warehouse 1', null, 'Asia/Jakarta', null, array['land']::text[], v_version, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (WMS, shape B, migration 20260903121000): app.update_wms_inbound_order_line -- the disclosing parent order is reached by FK from an already-guarded line, so a NEW guard reusing the sibling line_not_found message was added. Outsider gets exactly the line_not_found a nonexistent line id produces; real member without OPS:Edit still gets insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_line_id uuid := (
    select l.id from app.wms_inbound_order_lines l
    join app.wms_inbound_orders o on o.id = l.inbound_order_id
    where o.tenant_id = v_tenant1 and o.idempotency_key = 'idem-iss146-inbound'
  );
  v_version integer := (
    select l.record_version from app.wms_inbound_order_lines l
    join app.wms_inbound_orders o on o.id = l.inbound_order_id
    where o.tenant_id = v_tenant1 and o.idempotency_key = 'idem-iss146-inbound'
  );
  v_absent_id uuid := '00000000-0000-0000-0000-0000000146fe';
  v_msg text;
  v_absent_msg text;
begin
  begin
    perform app.update_wms_inbound_order_line(v_line_id, 12, 'outsider probe', v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected line_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'line_not_found' then
        raise exception 'assertion failed: expected line_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.update_wms_inbound_order_line(v_absent_id, 12, 'outsider probe', v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected line_not_found for a genuinely nonexistent line id';
  exception
    when no_data_found then
      get stacked diagnostics v_absent_msg = message_text;
  end;
  if replace(v_msg, v_line_id::text, '<id>') <> replace(v_absent_msg, v_absent_id::text, '<id>') then
    raise exception 'assertion failed: the outsider can still tell a REAL foreign inbound line from a nonexistent one -- real=% absent=%', v_msg, v_absent_msg;
  end if;

  begin
    perform app.update_wms_inbound_order_line(v_line_id, 12, 'member probe', v_version, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (HRIS/payroll, migration 20260903122000): app.freeze_payroll_period_inputs -- outsider gets a generic payroll_period_not_found with NO tenant_id, real member without HRS:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_period_id uuid := (select id from app.payroll_periods where tenant_id = v_tenant1 and code = 'iss146-2026-09');
  v_version integer := (select record_version from app.payroll_periods where tenant_id = v_tenant1 and code = 'iss146-2026-09');
  v_msg text;
begin
  begin
    perform app.freeze_payroll_period_inputs(v_period_id, v_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected payroll_period_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'payroll_period_not_found' then
        raise exception 'assertion failed: expected payroll_period_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.freeze_payroll_period_inputs(v_period_id, v_version, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no HRS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'HRS:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority HRS:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (platform master data, migration 20260903123000): app.update_master_record -- outsider gets a generic master_record_not_found with NO tenant_id, real member who is not a tenant_admin still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t1');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146a2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146a3';
  v_record_id uuid := (select id from app.master_records where tenant_id = v_tenant1 and code = 'ISS146-FLEET-1');
  v_version integer := (select record_version from app.master_records where tenant_id = v_tenant1 and code = 'ISS146-FLEET-1');
  v_msg text;
begin
  begin
    perform app.update_master_record(v_record_id, v_version, 'ISS146 Fleet Truck 1 (renamed)', null, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected master_record_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'master_record_not_found' then
        raise exception 'assertion failed: expected master_record_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.update_master_record(v_record_id, v_version, 'ISS146 Fleet Truck 1 (renamed)', null, null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member who is not a tenant_admin';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'tenant_admin' then
        raise exception 'assertion failed: expected the original insufficient_authority tenant_admin message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 cross-cutting tranche: all 4 new migration parts PASSED (5 probed functions, one of them the shape-B remedy) -- outsider probes never see the real tenant_id and are byte-identical to a nonexistent id, genuine same-tenant refusals are unchanged'
