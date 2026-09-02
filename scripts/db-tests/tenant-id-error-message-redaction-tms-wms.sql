-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Regression evidence for the Advanced TMS / WMS remediation lane (3 migrations,
-- 20260903110000-20260903112000, 121 functions / 122 raise sites across Advanced TMS
-- tracking, WMS inbound/inventory, and WMS outbound operations).
--
-- A sibling of scripts/db-tests/tenant-id-error-message-redaction.sql, which carries the
-- identical proof for the earlier Finance/HRIS/Procurement/Ticketing/Platform Core parts.
-- Kept as its own file rather than appended to that one so the two lanes' fixtures stay
-- independent (this file provisions its own tenant, its own actors and its own records
-- and shares nothing with it).
--
-- Proves, for a representative sample of THIS lane's functions, both directions of the fix:
--
--   1. A caller with ZERO relationship to the record's real tenant (registered in
--      auth.users only -- never invited, no app.principal_memberships or
--      app.tenant_user_identities row for that tenant anywhere) gets the GENERIC
--      not-found error, with errcode no_data_found, whose text does NOT contain the
--      record's real tenant_id anywhere. That is the disclosure this issue closes.
--   2. A GENUINE member of that same tenant who merely lacks the specific role authority
--      still gets the ORIGINAL, specific insufficient_authority message, WITH the
--      tenant_id in it and with the unchanged insufficient_privilege errcode -- because
--      that tenant_id is not a new disclosure to somebody who already belongs to the
--      tenant. Preserving that distinction is the whole point of the fix, so it is
--      asserted just as hard as the redaction itself.
--
-- Sample selection. The lane's 122 raise sites take three shapes (see the migration
-- headers). This file exercises the dominant one directly and names where the other two
-- are already proved, rather than duplicating a ~200-line CRM->quotation->job-order->
-- shipment-order fixture that those suites already build:
--
--   (A) 103 sites -- the membership check folded into an existing not-found branch.
--       Covered here end to end by four functions chosen to span a read, a write, a list
--       and a SECOND row variable (v_location, not v_warehouse), so the proof is not
--       one function's accident: app.get_warehouse_deactivation_impact,
--       app.create_warehouse_zone, app.list_warehouse_zones and
--       app.get_warehouse_location_deactivation_impact.
--   (B) 18 sites -- a NEW guard added after a parent-by-FK lookup. Proved by the
--       cross-tenant blocks in scripts/db-tests/advanced-tms-mile-orchestration.sql
--       (app.upsert_shipment_leg_tracking_policy -> leg_not_found),
--       advanced-tms-milestone-exception-telemetry.sql
--       (app.get_shipment_leg_eta_projection -> leg_not_found) and
--       advanced-tms-geofence-route-deviation-signals.sql
--       (app.confirm_milestone_candidate -> milestone_candidate_not_found), each updated
--       in this same commit against a real zero-membership foreign actor.
--   (C) 1 site -- app.end_leg_tracking_session, whose driver-mobile token branch must NOT
--       be gated on tenant membership. Its RBAC branch is proved by
--       advanced-tms-mile-orchestration.sql, and the driver-token branch is proved still
--       working, unchanged, by advanced-tms-driver-mobile-tracking.sql, which drives a
--       real token through app.ingest_driver_mobile_report(..., 'stop', ...) into
--       app.end_leg_tracking_session and asserts the resulting session ended and its
--       'driver-mobile' audit event was written.

\set ON_ERROR_STOP on

\echo '>> ISS-2026-146 (TMS/WMS) setup: tenant iss146tms with an admin holding full OPS authority (used only to create the fixture records), a zero-role member (a REAL, active tenant membership with no role assignment at all -- the "genuine member without authority" case), and an outsider identity with no relationship to the tenant whatsoever (never invited, no membership row anywhere) -- the caller class this fix closes'
do $$
declare
  v_tenant uuid;
  v_supreme uuid := '00000000-0000-0000-0000-0000001460b0';
  v_admin uuid := '00000000-0000-0000-0000-0000001460b1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000001460b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_role_id uuid;
  v_role_draft app.role_versions;
  v_org_unit app.org_units;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iss146tms.test'),
    (v_admin, 'admin@iss146tms.test'),
    (v_member_no_auth, 'memberzero@iss146tms.test'),
    (v_outsider, 'outsider@iss146tms.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iss146tms', 'ISS-2026-146 TMS/WMS Tenant', 'idem-iss146-tms', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iss146tms');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  -- Both real identities are homed in the SAME company org unit as the warehouse created
  -- below, so neither of them is ever refused on record-scope grounds -- the only thing
  -- separating the admin from the zero-role member is the role assignment itself, which
  -- is precisely the distinction this file has to keep visible.
  v_org_unit := app.create_org_unit(v_tenant, 'company', null, 'ISS146TMS-CO', 'ISS146 TMS Co', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iss146tms.test', 'ISS146 TMS Admin', v_org_unit.id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iss146tms.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, v_member_no_auth, 'memberzero@iss146tms.test', 'ISS146 TMS Zero Role Member', v_org_unit.id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberzero@iss146tms.test'), 'active', 'onboarded', 'tester');
  -- A real, active tenant membership, deliberately with NO role assignment: this actor
  -- genuinely belongs to the tenant but holds not one OPS permission.
  perform app.grant_principal_membership(v_member_no_auth, 'org_user', v_tenant, null, 'tester');

  -- v_outsider is registered in auth.users and NOTHING else -- never invited to this
  -- tenant, never granted a principal membership anywhere on the platform.

  v_role_id := (app.create_role(v_tenant, 'ISS146 TMS Full OPS', 'full OPS authority for fixture setup', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = 'OPS'), 'tester');
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_role_id and status = 'published'), v_admin, v_supreme, 'supreme');
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS) setup: one real warehouse and one real warehouse location in that tenant, created by the admin -- these are the records the outsider probes below'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_admin uuid := '00000000-0000-0000-0000-0000001460b1';
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant and code = 'ISS146TMS-CO');
  v_warehouse app.warehouses;
  v_location app.warehouse_locations;
begin
  v_warehouse := app.create_warehouse(
    v_tenant, v_org_unit_id, 'WH-ISS146', 'ISS146 Regression DC', 'Jl. Regression 146',
    'Asia/Jakarta', null, array['land']::text[], v_admin, 'admin');

  v_location := app.create_warehouse_location(
    v_warehouse.id, null, null, 'RACK-146', 'Rack 146', 'rack', 1,
    null, null, null, null, null, false, false, v_admin, 'admin');

  if v_warehouse.id is null or v_location.id is null then
    raise exception 'assertion failed: test precondition failed -- the warehouse/location fixture was not created';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS, shape A, read): app.get_warehouse_deactivation_impact -- the outsider gets a generic warehouse_not_found (no_data_found) carrying NO tenant_id, while the real zero-role member still gets the original insufficient_authority (insufficient_privilege) WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000001460b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant and code = 'WH-ISS146');
  v_msg text;
begin
  begin
    perform app.get_warehouse_deactivation_impact(v_warehouse_id, v_outsider);
    raise exception 'assertion failed: expected warehouse_not_found for an outsider with zero relationship to iss146tms';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'warehouse_not_found' then
        raise exception 'assertion failed: expected warehouse_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.get_warehouse_deactivation_impact(v_warehouse_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146tms member holding no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:View' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS, shape A, write): app.create_warehouse_zone -- an outsider''s WRITE attempt is refused with the same generic warehouse_not_found and creates nothing; the real zero-role member still gets insufficient_authority OPS:Create WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000001460b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant and code = 'WH-ISS146');
  v_msg text;
  v_count integer;
begin
  begin
    perform app.create_warehouse_zone(v_warehouse_id, 'HIJACK-146', 'Hijack Zone', 'ambient', null, null, null, null, null, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected warehouse_not_found for an outsider creating a zone in a foreign tenant''s warehouse';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'warehouse_not_found' then
        raise exception 'assertion failed: expected warehouse_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  select count(*) into v_count from app.warehouse_zones where warehouse_id = v_warehouse_id;
  if v_count <> 0 then
    raise exception 'assertion failed: the outsider''s refused write must not have created a zone, found % zone(s)', v_count;
  end if;

  begin
    perform app.create_warehouse_zone(v_warehouse_id, 'HIJACK-146', 'Hijack Zone', 'ambient', null, null, null, null, null, null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146tms member holding no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:Create' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:Create message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS, shape A, list): app.list_warehouse_zones -- a bounded READ path refuses the outsider identically, never returning an empty set that would still confirm the warehouse exists'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000001460b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant and code = 'WH-ISS146');
  v_msg text;
begin
  begin
    perform app.list_warehouse_zones(v_warehouse_id, v_outsider, null);
    raise exception 'assertion failed: expected warehouse_not_found for an outsider listing a foreign tenant''s warehouse zones';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'warehouse_not_found' then
        raise exception 'assertion failed: expected warehouse_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.list_warehouse_zones(v_warehouse_id, v_member_no_auth, null);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146tms member holding no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:View' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS, shape A, second row variable): app.get_warehouse_location_deactivation_impact gates on v_location.tenant_id (not v_warehouse.tenant_id) and raises its own distinct location_not_found -- proving the fix follows the actually-disclosed row variable rather than one hard-coded table'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000001460b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_location_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant and code = 'RACK-146');
  v_msg text;
begin
  begin
    perform app.get_warehouse_location_deactivation_impact(v_location_id, v_outsider);
    raise exception 'assertion failed: expected location_not_found for an outsider probing a foreign tenant''s warehouse location';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'location_not_found' then
        raise exception 'assertion failed: expected location_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.get_warehouse_location_deactivation_impact(v_location_id, v_member_no_auth);
    raise exception 'assertion failed: expected insufficient_authority for a real iss146tms member holding no OPS role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'OPS:View' then
        raise exception 'assertion failed: expected the original insufficient_authority OPS:View message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS): an outsider probing a genuinely NONEXISTENT id must get the byte-identical error a real-but-foreign id now produces -- the two cases must be indistinguishable, which is exactly what removes the ownership/existence oracle'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146tms');
  v_outsider uuid := '00000000-0000-0000-0000-0000001460b3';
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant and code = 'WH-ISS146');
  v_absent_id uuid := '00000000-0000-0000-0000-0000001460ff';
  v_real_msg text;
  v_real_code text;
  v_absent_msg text;
  v_absent_code text;
begin
  begin
    perform app.get_warehouse_deactivation_impact(v_warehouse_id, v_outsider);
    raise exception 'assertion failed: expected the real-but-foreign warehouse probe to be refused';
  exception
    when no_data_found then
      get stacked diagnostics v_real_msg = message_text, v_real_code = returned_sqlstate;
  end;

  begin
    perform app.get_warehouse_deactivation_impact(v_absent_id, v_outsider);
    raise exception 'assertion failed: expected the nonexistent-id probe to be refused';
  exception
    when no_data_found then
      get stacked diagnostics v_absent_msg = message_text, v_absent_code = returned_sqlstate;
  end;

  if v_real_code <> v_absent_code then
    raise exception 'assertion failed: existence oracle survives -- a real foreign id returned sqlstate % but a nonexistent id returned %', v_real_code, v_absent_code;
  end if;
  -- The two messages differ only by the id the CALLER itself supplied; strip it and they
  -- must be identical, with no tenant_id or other record-derived detail left in either.
  if replace(v_real_msg, v_warehouse_id::text, '<id>') <> replace(v_absent_msg, v_absent_id::text, '<id>') then
    raise exception 'assertion failed: ownership oracle survives -- real-foreign message % differs from nonexistent-id message % by more than the caller-supplied id', v_real_msg, v_absent_msg;
  end if;
end;
$$;

\echo '>> ISS-2026-146 (TMS/WMS): all shape-A probes PASSED -- an outsider never sees the real tenant_id and cannot tell a real foreign record from a nonexistent one, while a genuine same-tenant member''s refusal is byte-identical to before this fix'
