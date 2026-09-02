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

  v_role_id := (app.create_role(v_tenant1, 'ISS146 Full Admin', 'full FIN/HRS/PRC/TKT/DEPLOY authority for fixture setup', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = any(array['FIN', 'HRS', 'PRC', 'TKT', 'DEPLOY'])), 'tester');
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
