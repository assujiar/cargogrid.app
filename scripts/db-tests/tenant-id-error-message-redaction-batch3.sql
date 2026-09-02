-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Regression evidence for the THIRD fix pass (Procurement lane: 4 migrations,
-- 20260903100000-20260903103000, 96 functions across vendor registration, vendor
-- assessment, vendor compliance, vendor financial security, sourcing, vendor comparison,
-- procurement approval, vendor performance and procurement dashboard saved views).
--
-- Same two-actor proof shape as this file's two predecessors
-- (tenant-id-error-message-redaction.sql, -batch2.sql), applied to a representative
-- function per source module of THIS pass:
--
--   1. A caller with ZERO relationship to the record's real tenant (never invited, no
--      app.principal_memberships / app.tenant_user_identities row for that tenant) gets a
--      GENERIC not-found error whose text does NOT contain the record's real tenant_id --
--      exactly what a nonexistent id already produced. This is the fix.
--   2. A genuine member of that SAME tenant who merely lacks the specific role authority
--      still gets the ORIGINAL, specific insufficient_authority message, WITH the
--      tenant_id in it and with the same insufficient_privilege errcode -- unchanged,
--      since that tenant_id is not a new disclosure to an actor who already belongs to
--      the tenant. Preserving this distinction is the whole point of the fix: no
--      permission check was weakened, only its ordering relative to a tenant-membership
--      pre-check moved.
--
-- Representative, not exhaustive by design (96 functions is out of scope for one test
-- file): one function per module for 8 of the pass's 9 source modules. Vendor comparison
-- (app.revise_vendor_comparison and its 5 siblings) is deliberately not exercised here --
-- its cheapest fixture is the full sourcing-request -> candidate-eligibility ->
-- shortlist -> RFQ -> comparison chain, and those 6 functions carry the byte-identical
-- gate this file proves 8 times over on the other modules.

\set ON_ERROR_STOP on

\echo '>> ISS-2026-146 batch 3 setup: tenant iss146t3 (every real record below lives here) with an admin holding full PRC/FIN authority (used only to create fixtures) and a zero-role member (a REAL iss146t3 membership with no role assignment at all -- the "genuine same-tenant member without authority" case). A separate identity has NO relationship to iss146t3 whatsoever -- the "outsider" case this fix closes.'
do $$
declare
  v_tenant3 uuid;
  v_admin uuid := '00000000-0000-0000-0000-0000000146c1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_supreme uuid := '00000000-0000-0000-0000-0000000146c0';
  v_role_id uuid;
  v_role_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iss146b3.test'),
    (v_admin, 'admin@iss146b3.test'),
    (v_member_no_auth, 'memberzero@iss146b3.test'),
    (v_outsider, 'outsider@iss146b3.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iss146t3', 'ISS-2026-146 Batch 3 Tenant', 'idem-iss146-t3', 'tester');
  v_tenant3 := (select id from app.tenants where slug = 'iss146t3');
  perform app.transition_tenant_status(v_tenant3, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant3, v_admin, 'admin@iss146b3.test', 'ISS146B3 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iss146b3.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant3, null, 'tester');

  perform app.invite_user(v_tenant3, v_member_no_auth, 'memberzero@iss146b3.test', 'ISS146B3 Zero Role Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberzero@iss146b3.test'), 'active', 'onboarded', 'tester');
  -- Real membership, deliberately NO role assignment -- "genuinely belongs to the tenant
  -- but holds no procurement authority", without granting a single permission.
  perform app.grant_principal_membership(v_member_no_auth, 'org_user', v_tenant3, null, 'tester');

  -- v_outsider exists in auth.users only -- never invited to iss146t3, never granted any
  -- principal membership anywhere. This is the caller class the original disclosure let
  -- learn a foreign tenant's real UUID from a denial message alone.

  v_role_id := (app.create_role(v_tenant3, 'ISS146B3 Procurement Admin', 'full PRC/FIN authority for fixture setup', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = any(array['PRC', 'FIN'])), 'tester');
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant3, (select id from app.role_versions where role_id = v_role_id and status = 'published'), v_admin, v_supreme, 'supreme');
end;
$$;

\echo '>> ISS-2026-146 batch 3 setup: one real record per module, all created by the admin inside iss146t3 -- these are the records the outsider probes below'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_admin uuid := '00000000-0000-0000-0000-0000000146c1';
  v_profile app.vendor_profiles;
  v_request app.sourcing_requests;
  v_policy app.procurement_approval_policies;
  v_definition app.vendor_kpi_definitions;
  v_view app.procurement_dashboard_saved_views;
begin
  -- Vendor registration / assessment / compliance / financial security all resolve their
  -- row from this one vendor profile's bare master_record_id.
  v_profile := app.create_vendor_profile_draft(v_tenant3, 'PT ISS146B3 Vendor', 'I146B3', 'PT', 'REG-ISS146B3', 'trucking', 30, 'staff_created', 'idem-iss146b3-vendor', v_admin, 'admin');

  -- Sourcing: app.submit_sourcing_request is the fixed function under test.
  v_request := app.create_proactive_sourcing_request(
    v_tenant3, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', null, null, null, null, null, null, 'IDR', 50000000,
    v_admin, now() + interval '7 days', 'idem-iss146b3-sourcing', v_admin, 'admin'
  );

  -- Procurement approval: app.publish_procurement_approval_policy_version is under test.
  v_policy := app.create_procurement_approval_policy_version(v_tenant3, 'vendor_activation', null, true, v_admin, 'admin');

  -- Vendor performance: app.publish_vendor_kpi_definition is under test.
  v_definition := app.create_vendor_kpi_definition_draft(
    v_tenant3, 'on_time_delivery', 'ISS146B3 On-Time Delivery', 'regression fixture', 30, 1, 90, 'gte', 15, 'percent',
    null, null, 2, true, null, 'idem-iss146b3-kpi', v_admin, 'admin'
  );

  -- Procurement dashboard: app.get_procurement_dashboard_saved_view is under test.
  v_view := app.create_procurement_dashboard_saved_view(
    v_tenant3, 'vendor_risk_compliance', 'ISS146B3 Saved View', 'regression fixture',
    '{}'::jsonb, '{}'::jsonb, 'idem-iss146b3-view', v_admin, 'admin'
  );

  if v_profile.master_record_id is null or v_request.id is null or v_policy.id is null or v_definition.id is null or v_view.id is null then
    raise exception 'assertion failed: test precondition failed -- one or more ISS-2026-146 batch 3 fixture records were not created';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / vendor registration): app.get_vendor_profile -- the outsider gets a generic vendor_profile_not_found with NO tenant_id; a real iss146t3 member without PRC:View still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-vendor');
  v_msg text;
begin
  begin
    perform 1 from app.get_vendor_profile(v_vendor_id, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_profile_not_found' then
        raise exception 'assertion failed: expected vendor_profile_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform 1 from app.get_vendor_profile(v_vendor_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:View' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / vendor assessment): app.get_vendor_current_assessment_status -- the outsider gets a generic vendor_profile_not_found with NO tenant_id, the zero-role member still gets insufficient_authority WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-vendor');
  v_msg text;
begin
  begin
    perform 1 from app.get_vendor_current_assessment_status(v_vendor_id, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_profile_not_found' then
        raise exception 'assertion failed: expected vendor_profile_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform 1 from app.get_vendor_current_assessment_status(v_vendor_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:View' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / vendor compliance): app.list_vendor_compliance_documents -- the outsider gets a generic vendor_profile_not_found with NO tenant_id, the zero-role member still gets insufficient_authority WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-vendor');
  v_msg text;
begin
  begin
    perform 1 from app.list_vendor_compliance_documents(v_vendor_id, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_profile_not_found' then
        raise exception 'assertion failed: expected vendor_profile_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform 1 from app.list_vendor_compliance_documents(v_vendor_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:View' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / vendor financial security): app.list_vendor_bank_accounts_masked -- the outsider gets a generic vendor_profile_not_found with NO tenant_id, the zero-role member still gets insufficient_authority WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-vendor');
  v_msg text;
begin
  begin
    perform 1 from app.list_vendor_bank_accounts_masked(v_vendor_id, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_profile_not_found' then
        raise exception 'assertion failed: expected vendor_profile_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform 1 from app.list_vendor_bank_accounts_masked(v_vendor_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:View' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / sourcing): app.submit_sourcing_request -- the outsider gets a generic sourcing_request_not_found with NO tenant_id, the zero-role member still gets insufficient_authority (PRC:Edit) WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_request app.sourcing_requests;
  v_msg text;
begin
  select * into v_request from app.sourcing_requests where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-sourcing';

  begin
    perform app.submit_sourcing_request(v_request.id, v_outsider, 'outsider', v_request.record_version);
    raise exception 'assertion failed: expected sourcing_request_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'sourcing_request_not_found' then
        raise exception 'assertion failed: expected sourcing_request_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.submit_sourcing_request(v_request.id, v_member_no_auth, 'memberzero', v_request.record_version);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;

  -- The request itself is untouched by either denial -- both callers were refused
  -- before any state change, exactly as before the fix.
  if (select status from app.sourcing_requests where id = v_request.id) <> 'draft' then
    raise exception 'assertion failed: neither denied caller may advance the sourcing request, got status %', (select status from app.sourcing_requests where id = v_request.id);
  end if;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / approval): app.publish_procurement_approval_policy_version -- the outsider gets a generic procurement_approval_policy_not_found with NO tenant_id, the zero-role member still gets insufficient_authority (PRC:Approve) WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_policy app.procurement_approval_policies;
  v_msg text;
begin
  select * into v_policy from app.procurement_approval_policies where tenant_id = v_tenant3 and entity_type = 'vendor_activation';

  begin
    perform app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected procurement_approval_policy_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'procurement_approval_policy_not_found' then
        raise exception 'assertion failed: expected procurement_approval_policy_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:Approve' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:Approve message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;

  if (select status from app.procurement_approval_policies where id = v_policy.id) <> 'draft' then
    raise exception 'assertion failed: neither denied caller may publish the policy version, got status %', (select status from app.procurement_approval_policies where id = v_policy.id);
  end if;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / vendor performance): app.publish_vendor_kpi_definition -- the outsider gets a generic vendor_kpi_definition_not_found with NO tenant_id, the zero-role member still gets insufficient_authority (PRC:Approve) WITH it'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146c2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_definition app.vendor_kpi_definitions;
  v_msg text;
begin
  select * into v_definition from app.vendor_kpi_definitions where tenant_id = v_tenant3 and kpi_code = 'on_time_delivery';

  begin
    perform app.publish_vendor_kpi_definition(v_definition.id, v_definition.record_version, v_outsider, 'outsider');
    raise exception 'assertion failed: expected vendor_kpi_definition_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'vendor_kpi_definition_not_found' then
        raise exception 'assertion failed: expected vendor_kpi_definition_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.publish_vendor_kpi_definition(v_definition.id, v_definition.record_version, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146t3 member with no PRC role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'PRC:Approve' then
        raise exception 'assertion failed: expected the original insufficient_authority PRC:Approve message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant3::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (Procurement / dashboard saved views): app.get_procurement_dashboard_saved_view -- the outsider gets the generic procurement_dashboard_saved_view_not_found with NO tenant_id; the real owner (the admin, who holds PRC:View) still reads the view back unchanged'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_admin uuid := '00000000-0000-0000-0000-0000000146c1';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_view_id uuid := (select id from app.procurement_dashboard_saved_views where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-view');
  v_readback app.procurement_dashboard_saved_views;
  v_msg text;
begin
  begin
    perform app.get_procurement_dashboard_saved_view(v_view_id, v_outsider);
    raise exception 'assertion failed: expected procurement_dashboard_saved_view_not_found for an outsider with zero relationship to iss146t3';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'procurement_dashboard_saved_view_not_found' then
        raise exception 'assertion failed: expected procurement_dashboard_saved_view_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant3::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  -- The "unaffected legitimate caller" arm for this function is its OWNER, not a
  -- zero-role member: these three saved-view functions already fold "row does not exist"
  -- and "not this actor's own saved view" into one generic not-found (PRC-264's own
  -- pre-existing owner scoping), so a non-owner member never reaches the
  -- insufficient_authority line at all -- with or without this fix. What must be proven
  -- unchanged here is that the owner still reads their own view back.
  v_readback := app.get_procurement_dashboard_saved_view(v_view_id, v_admin);
  if v_readback.id <> v_view_id or v_readback.name <> 'ISS146B3 Saved View' then
    raise exception 'assertion failed: the saved view''s own owner must still read it back unchanged, got %', to_jsonb(v_readback);
  end if;
end;
$$;

\echo '>> ISS-2026-146 batch 3: a genuinely nonexistent id produces the SAME generic not-found the outsider sees -- the two failure paths are indistinguishable, which is exactly what closes the existence/ownership oracle'
do $$
declare
  v_outsider uuid := '00000000-0000-0000-0000-0000000146c3';
  v_missing uuid := '00000000-0000-0000-0000-0000014600ff';
  v_msg_missing text;
  v_msg_outsider text;
  v_tenant3 uuid := (select id from app.tenants where slug = 'iss146t3');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant3 and idempotency_key = 'idem-iss146b3-vendor');
begin
  begin
    perform 1 from app.get_vendor_profile(v_missing, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for a genuinely nonexistent master_record_id';
  exception
    when no_data_found then
      get stacked diagnostics v_msg_missing = message_text;
  end;

  begin
    perform 1 from app.get_vendor_profile(v_vendor_id, v_outsider);
    raise exception 'assertion failed: expected vendor_profile_not_found for the outsider probing a REAL iss146t3 vendor';
  exception
    when no_data_found then
      get stacked diagnostics v_msg_outsider = message_text;
  end;

  -- Identical up to the echoed id the caller itself supplied: same error name, same
  -- errcode, and neither carries the real tenant_id.
  if replace(v_msg_missing, v_missing::text, '<id>') <> replace(v_msg_outsider, v_vendor_id::text, '<id>') then
    raise exception 'assertion failed: the nonexistent-id and foreign-tenant failure paths are still distinguishable: % vs %', v_msg_missing, v_msg_outsider;
  end if;
end;
$$;
