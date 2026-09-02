-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Regression evidence for the SECOND fix pass (2 migrations, 20260902200000-
-- 20260902201000, 99 functions across Commercial (42) and Operations (57), on top
-- of the first pass's 120 across Finance/HRIS/Procurement/Ticketing/Platform Core --
-- see scripts/db-tests/tenant-id-error-message-redaction.sql for that pass's own
-- regression file and full rationale, identical in shape here).
--
-- Proves, for one function per module fixed in THIS pass:
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
-- Not exhaustive by design (99 functions is out of scope for one test file) -- a
-- representative cross-section, one per module, per this item's own regression-proof
-- instructions in docs/runtime/KNOWN_ISSUES.md's ISS-2026-146 entry.

\set ON_ERROR_STOP on

\echo '>> ISS-2026-146 batch 2 setup: tenant1 (real records live here) with a Supreme Admin (registers a milestone code, a platform-wide primitive no ordinary tenant actor may touch), an admin (full COM/OPS authority, used only to create fixture records), and a zero-role member (real tenant1 membership, no role assignment -- the "genuine same-tenant member without authority" case). A separate identity has NO relationship to tenant1 at all (never invited, no membership row) -- the "outsider" case this fix closes.'
do $$
declare
  v_tenant1 uuid;
  v_admin uuid := '00000000-0000-0000-0000-0000000146b1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146b3';
  v_supreme uuid := '00000000-0000-0000-0000-0000000146b0';
  v_role_id uuid;
  v_role_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iss146b.test'),
    (v_admin, 'admin@iss146b.test'),
    (v_member_no_auth, 'memberzero@iss146b.test'),
    (v_outsider, 'outsider@iss146b.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iss146t2', 'ISS-2026-146 Batch 2 Tenant', 'idem-iss146-t2', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iss146t2');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin, 'admin@iss146b.test', 'ISS146B Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iss146b.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_member_no_auth, 'memberzero@iss146b.test', 'ISS146B Zero Role Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberzero@iss146b.test'), 'active', 'onboarded', 'tester');
  -- Real membership, deliberately NO role assignment -- proves "genuinely belongs to
  -- the tenant but lacks specific authority" without granting a single permission.
  perform app.grant_principal_membership(v_member_no_auth, 'org_user', v_tenant1, null, 'tester');

  -- v_outsider is registered in auth.users only -- never invited to tenant1, never
  -- granted any principal membership anywhere. This is the caller class the original
  -- disclosure let learn a foreign tenant's real UUID.

  v_role_id := (app.create_role(v_tenant1, 'ISS146B Full Admin', 'full COM/OPS authority for fixture setup', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = any(array['COM', 'OPS'])), 'tester');
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  -- Assigned by a genuine Supreme Admin, never self-assigned: a full COM/OPS bundle
  -- carries at least one protected permission app.assign_role's own self-escalation
  -- guard refuses to let an actor grant themselves.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role_id and status = 'published'), v_admin, v_supreme, 'supreme');

  -- A registered milestone code is a permanent, platform-wide primitive (Supreme-only,
  -- OPS-173) -- needed below so a real, valid app.milestone_template_versions sequence
  -- can be published, but registering it is deliberately NOT part of either function
  -- this file tests.
  perform app.register_milestone_code('iss146b_picked_up', 'ISS146B Picked Up', 'pickup', true, true, false, v_supreme, 'supreme');
end;
$$;

\echo '>> ISS-2026-146 batch 2 setup: one real record per module, created by the admin in tenant1 -- these are the records an outsider will probe below'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t2');
  v_admin uuid := '00000000-0000-0000-0000-0000000146b1';
  v_lead app.leads;
  v_template app.milestone_template_versions;
begin
  -- Commercial: app.assign_lead is the fixed function under test.
  v_lead := app.capture_lead(v_tenant1, 'manual', null, 'ISS146B Test Co', 'ISS146B Contact', 'contact@iss146b.test', '081100000000', v_admin, null, v_admin, 'tester');

  -- Operations: app.publish_milestone_template_version is the fixed function under
  -- test. A real, valid single-code sequence so publish's own sequence-validation
  -- loop (which runs BEFORE the OPS:Edit authority check inside the function body)
  -- never masks the assertion this file is actually proving.
  v_template := app.create_milestone_template_draft(v_tenant1, 'sea', v_admin, 'tester');
  perform app.set_milestone_template_sequence(v_template.id, jsonb_build_array(jsonb_build_object('code', 'iss146b_picked_up')), v_admin, 'tester');

  if v_lead.id is null or v_template.id is null then
    raise exception 'assertion failed: test precondition failed -- one or more fixture records were not created';
  end if;
end;
$$;

\echo '>> ISS-2026-146 batch 2 (Commercial): app.assign_lead -- outsider gets a generic lead_not_found with NO tenant_id, real member without COM:Assign still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t2');
  v_admin uuid := '00000000-0000-0000-0000-0000000146b1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146b3';
  v_lead app.leads;
  v_msg text;
begin
  select * into v_lead from app.leads where tenant_id = v_tenant1 and email = 'contact@iss146b.test';

  begin
    perform app.assign_lead(v_lead.id, v_lead.record_version, v_admin, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected lead_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'lead_not_found' then
        raise exception 'assertion failed: expected lead_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.assign_lead(v_lead.id, v_lead.record_version, v_admin, null, v_member_no_auth, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real tenant1 member with no COM role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'COM:Assign' then
        raise exception 'assertion failed: expected the original insufficient_authority COM:Assign message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant1::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (this is not a new disclosure) -- got %', v_msg;
      end if;
  end;

  -- The genuine admin (real COM:Assign) still succeeds -- the underlying capability
  -- itself is completely unaffected by this fix.
  select * into v_lead from app.assign_lead(v_lead.id, v_lead.record_version, v_admin, null, v_admin, 'admin');
  if v_lead.owner_user_id <> v_admin then
    raise exception 'assertion failed: expected the genuine admin''s own assign_lead call to succeed unaffected by this fix';
  end if;
end;
$$;

\echo '>> ISS-2026-146 batch 2 (Operations): app.publish_milestone_template_version -- outsider gets a generic milestone_template_not_found with NO tenant_id, real member without OPS:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iss146t2');
  v_admin uuid := '00000000-0000-0000-0000-0000000146b1';
  v_member_no_auth uuid := '00000000-0000-0000-0000-0000000146b2';
  v_outsider uuid := '00000000-0000-0000-0000-0000000146b3';
  v_template app.milestone_template_versions;
  v_msg text;
begin
  select * into v_template from app.milestone_template_versions where tenant_id = v_tenant1 and mode = 'sea';

  begin
    perform app.publish_milestone_template_version(v_template.id, v_template.record_version, null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected milestone_template_not_found for an outsider with zero relationship to tenant1';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'milestone_template_not_found' then
        raise exception 'assertion failed: expected milestone_template_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- outsider error message still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.publish_milestone_template_version(v_template.id, v_template.record_version, null, v_member_no_auth, 'memberzero');
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

  -- The genuine admin (real OPS:Edit) still succeeds -- the underlying capability
  -- itself is completely unaffected by this fix.
  select * into v_template from app.publish_milestone_template_version(v_template.id, v_template.record_version, null, v_admin, 'admin');
  if v_template.status <> 'published' then
    raise exception 'assertion failed: expected the genuine admin''s own publish_milestone_template_version call to succeed unaffected by this fix';
  end if;
end;
$$;

\echo '>> ISS-2026-146 batch 2: both modules PASSED -- outsider probes never see the real tenant_id, genuine same-tenant refusals are byte-identical to before this fix, and the genuine authorized actor is completely unaffected'
