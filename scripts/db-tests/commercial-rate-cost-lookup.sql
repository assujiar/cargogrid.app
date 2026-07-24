-- Real, executable test evidence for COM-149 (Rate and Cost Lookup, CG-S7-COM-008) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- Sorts alphabetically *before* scripts/db-tests/master-data.sql -- this file's own
-- setup creates real, approved app.vendor_rate_versions rows under its own tenant
-- ('acmerate'), which is why master-data.sql's own app.v_active_vendor_rates assertion
-- was updated (proactively, applying the COM-145/COM-148 cross-file-fragility lesson)
-- to scope its count by its own tenant rather than a bare global count.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a tenant_admin (rate authority), a rep (COM:Edit/View/View cost), a manager (COM:Edit/View, no View cost), a sibling-team outsider, and a full opportunity/costing-request chain'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_mgr_role uuid;
  v_mgr_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009001', 'tenantadmin@acmerate.test'),
    ('00000000-0000-0000-0000-000000009002', 'rep@acmerate.test'),
    ('00000000-0000-0000-0000-000000009003', 'manager@acmerate.test'),
    ('00000000-0000-0000-0000-000000009004', 'outsider@acmerate.test'),
    ('00000000-0000-0000-0000-000000009005', 'other-tenant-admin@betarate.test');

  perform app.provision_tenant('acmerate', 'Acme Rate Co', 'idem-acmerate', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betarate', 'Beta Rate Co', 'idem-betarate', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betarate');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMERATE-CO', 'Acme Rate Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERATE-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMERATE-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERATE-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMERATE-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERATE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMERATE-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERATE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009001', 'tenantadmin@acmerate.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmerate.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009002', 'rep@acmerate.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmerate.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009003', 'manager@acmerate.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmerate.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009004', 'outsider@acmerate.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmerate.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009005', 'other-tenant-admin@betarate.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-admin@betarate.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009005', 'tenant_admin', v_tenant2, null, 'tester');

  -- Manager first (no protected permission in this set, self-assignment is fine), then
  -- the manager assigns the two View-cost-carrying roles (COM-147/148's own established
  -- fixture pattern -- app.assign_role's self-escalation guard only fires when
  -- actor = grantee AND the role version carries a protected permission).
  v_mgr_role := (app.create_role(v_tenant1, 'Rate Manager', 'rate governance', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000009003', '00000000-0000-0000-0000-000000009003', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Rate Rep', 'rate capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009002', '00000000-0000-0000-0000-000000009003', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Rate Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009004', '00000000-0000-0000-0000-000000009003', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Rate Ltd', 'Jane Doe', 'jane@contosorate.test', '0811',
    '00000000-0000-0000-0000-000000009002', v_team_a, '00000000-0000-0000-0000-000000009002', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosorate.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009002', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosorate.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Rate Ltd', null, '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009002', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Rate Ltd';

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso Jakarta-Surabaya ocean lane',
    jsonb_build_object(
      'service_type', 'ocean_freight', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000009002', v_team_a, '00000000-0000-0000-0000-000000009002', 'tester'
  );
  perform app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009002', 'tester');
end;
$$;

\echo '>> create_rate_version: authority-gated (is_support_grant_authority, not ordinary COM RBAC), idempotent master-record identity, structural CHECK constraints'
do $$
declare
  v_tenant1 uuid;
  v_rate1 app.vendor_rate_versions;
  v_rate2 app.vendor_rate_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  begin
    perform app.create_rate_version(
      v_tenant1, 'VENDOR-OCEAN-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
      1000, 5000, 10, 50, 'IDR', 15000000, 500000, '[]'::jsonb, now(), null, null,
      '00000000-0000-0000-0000-000000009002', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- a rep (no is_support_grant_authority) cannot create a rate version';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_rate1 from app.create_rate_version(
    v_tenant1, 'VENDOR-OCEAN-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    1000, 5000, 10, 50, 'IDR', 15000000, 500000, jsonb_build_array(jsonb_build_object('code', 'bunker_surcharge', 'amount', 250000)),
    now(), null, null,
    '00000000-0000-0000-0000-000000009001', 'tester'
  );
  if v_rate1.approval_status <> 'pending_approval' or v_rate1.base_amount <> 15000000 then
    raise exception 'assertion failed: expected status=pending_approval base_amount=15000000, got status=% base_amount=%', v_rate1.approval_status, v_rate1.base_amount;
  end if;

  -- A second rate version under the *same* vendor_code reuses the same master_record_id
  -- (idempotent get-or-create, PLT-120) rather than creating a duplicate vendor identity.
  select * into v_rate2 from app.create_rate_version(
    v_tenant1, 'VENDOR-OCEAN-1', 'Contoso Ocean Line', 'ocean_freight', 'LCL', 'Jakarta', 'Surabaya', null,
    null, null, null, null, 'IDR', 2500000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009001', 'tester'
  );
  if v_rate2.master_record_id <> v_rate1.master_record_id then
    raise exception 'assertion failed: expected the same master_record_id for the same vendor_code, got % and %', v_rate1.master_record_id, v_rate2.master_record_id;
  end if;

  begin
    perform app.create_rate_version(
      v_tenant1, 'VENDOR-BAD-CURRENCY', 'Bad Currency Co', 'ocean_freight', null, 'Jakarta', 'Surabaya', null,
      null, null, null, null, 'idr', 1000, null, '[]'::jsonb, now(), null, null,
      '00000000-0000-0000-0000-000000009001', 'tester'
    );
    raise exception 'assertion failed: expected check_violation -- currency must be 3 uppercase letters';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.create_rate_version(
      v_tenant1, 'VENDOR-BAD-RANGE', 'Bad Range Co', 'ocean_freight', null, 'Jakarta', 'Surabaya', null,
      5000, 1000, null, null, 'IDR', 1000, null, '[]'::jsonb, now(), null, null,
      '00000000-0000-0000-0000-000000009001', 'tester'
    );
    raise exception 'assertion failed: expected check_violation -- cargo_weight_min must not exceed cargo_weight_max';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> approve_rate_version / reject_rate_version: authority-gated, optimistic concurrency, pending_approval-only, mandatory reject reason'
do $$
declare
  v_tenant1 uuid;
  v_rate app.vendor_rate_versions;
  v_reject_target app.vendor_rate_versions;
begin
  -- Scoped to this file's own tenant, not a bare lane/mode match -- "Jakarta"/"Surabaya"/
  -- "FCL" is a natural, reusable test lane name a later capability's own fixture may also
  -- use (e.g. COM-150's own margin-calculation fixture does), which would otherwise make
  -- this lookup ambiguous across the shared disposable database (the same class of
  -- cross-file fragility COM-145/148 first found for audit-log counts, applied here to
  -- an entity lookup instead).
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select * into v_rate from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'FCL';

  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009002', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- a rep cannot approve a rate version';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version + 1, '00000000-0000-0000-0000-000000009001', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  select * into v_rate from app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009001', 'tester');
  if v_rate.approval_status <> 'approved' or v_rate.approved_by <> 'tester' then
    raise exception 'assertion failed: expected status=approved approved_by=tester, got status=% approved_by=%', v_rate.approval_status, v_rate.approved_by;
  end if;

  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009001', 'tester');
    raise exception 'assertion failed: expected check_violation -- an already-approved rate version cannot be approved again';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_reject_target from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'LCL';

  begin
    perform app.reject_rate_version(v_reject_target.id, v_reject_target.record_version, '', '00000000-0000-0000-0000-000000009001', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- rejecting requires a non-empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_reject_target from app.reject_rate_version(v_reject_target.id, v_reject_target.record_version, 'Pricing not competitive', '00000000-0000-0000-0000-000000009001', 'tester');
  if v_reject_target.approval_status <> 'rejected' or v_reject_target.rejected_reason <> 'Pricing not competitive' then
    raise exception 'assertion failed: expected status=rejected with reason set, got status=% reason=%', v_reject_target.approval_status, v_reject_target.rejected_reason;
  end if;
end;
$$;

\echo '>> withdraw_rate_version: only an approved rate can be withdrawn, mandatory reason'
do $$
declare
  v_tenant1 uuid;
  v_rate app.vendor_rate_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select * into v_rate from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'LCL';

  begin
    perform app.withdraw_rate_version(v_rate.id, v_rate.record_version, 'no longer offered', '00000000-0000-0000-0000-000000009001', 'tester');
    raise exception 'assertion failed: expected check_violation -- a rejected rate version cannot be withdrawn (only approved can)';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_rate from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'FCL';

  begin
    perform app.withdraw_rate_version(v_rate.id, v_rate.record_version, '', '00000000-0000-0000-0000-000000009001', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- withdrawing requires a non-empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> create_rate_version supersede: inherits the source''s master_record_id, immediately marks the source superseded, cannot supersede an already-terminal version'
do $$
declare
  v_tenant1 uuid;
  v_source app.vendor_rate_versions;
  v_revision app.vendor_rate_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select * into v_source from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'FCL';

  select * into v_revision from app.create_rate_version(
    v_source.tenant_id, 'VENDOR-OCEAN-1-REVISED', 'Contoso Ocean Line (should be ignored on supersede)', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    1000, 5000, 10, 50, 'IDR', 16000000, 500000, '[]'::jsonb, now(), null, v_source.id,
    '00000000-0000-0000-0000-000000009001', 'tester'
  );
  if v_revision.master_record_id <> v_source.master_record_id then
    raise exception 'assertion failed: expected the revision to inherit master_record_id % (vendor_code/name ignored on supersede), got %', v_source.master_record_id, v_revision.master_record_id;
  end if;
  if v_revision.approval_status <> 'pending_approval' or v_revision.supersedes_version_id <> v_source.id then
    raise exception 'assertion failed: expected the new revision status=pending_approval supersedes_version_id=%, got status=% supersedes=%', v_source.id, v_revision.approval_status, v_revision.supersedes_version_id;
  end if;

  select * into v_source from app.vendor_rate_versions where id = v_source.id;
  if v_source.approval_status <> 'superseded' then
    raise exception 'assertion failed: expected the source rate version to be marked superseded immediately, got %', v_source.approval_status;
  end if;

  begin
    perform app.create_rate_version(
      v_source.tenant_id, 'irrelevant', 'irrelevant', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
      null, null, null, null, 'IDR', 1, null, '[]'::jsonb, now(), null, v_source.id,
      '00000000-0000-0000-0000-000000009001', 'tester'
    );
    raise exception 'assertion failed: expected check_violation -- an already-superseded rate version cannot itself be superseded again';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  perform app.approve_rate_version(v_revision.id, v_revision.record_version, '00000000-0000-0000-0000-000000009001', 'tester');
end;
$$;

\echo '>> app.vendor_rate_versions_directory / app.v_active_vendor_rates: cost masked without COM:View cost, visible with it; tenant-wide visibility (not owner-scoped); base-table columns withheld from direct select; cross-tenant isolation'
do $$
declare
  v_active_rate_id uuid;
  v_masked boolean;
  v_amount numeric;
  v_active_count integer;
begin
  -- Looked up from the base table, not the masked view: app.vendor_rate_versions_directory
  -- embeds its own auth.uid()-driven filter directly in the view's WHERE clause (not a
  -- table RLS policy), so a superuser session with no request.jwt.claims set (this
  -- statement runs before any role switch below) would see it evaluate has_active_tenant_
  -- membership()/is_supreme_admin() against a null uid and legitimately return 0 rows --
  -- an artifact of the lookup context, not a real defect. The base table's own RLS *is*
  -- a real policy, which a superuser session bypasses unconditionally.
  select id into v_active_rate_id from app.vendor_rate_versions
  where tenant_id = (select id from app.tenants where slug = 'acmerate')
    and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'FCL' and approval_status = 'approved';

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009003", "role": "authenticated"}';
  select cost_masked, base_amount into v_masked, v_amount from app.vendor_rate_versions_directory where rate_version_id = v_active_rate_id;
  if not v_masked or v_amount is not null then
    raise exception 'assertion failed: expected cost_masked=true and null base_amount for the manager (no View cost), got masked=% amount=%', v_masked, v_amount;
  end if;

  begin
    perform base_amount from app.vendor_rate_versions where id = v_active_rate_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting base_amount directly from app.vendor_rate_versions';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  -- Tenant-wide visibility (unlike leads/opportunities/costing requests): the manager,
  -- who has no ownership tie to this rate at all, still sees the row (masked) -- vendor
  -- rates are tenant reference data, not per-owner/org-unit-scoped.
  select count(*) into v_active_count from app.vendor_rate_versions_directory where rate_version_id = v_active_rate_id;
  if v_active_count <> 1 then
    raise exception 'assertion failed: expected the manager to see the rate row (masked), found % rows', v_active_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009002", "role": "authenticated"}';
  select cost_masked, base_amount into v_masked, v_amount from app.vendor_rate_versions_directory where rate_version_id = v_active_rate_id;
  if v_masked or v_amount <> 16000000 then
    raise exception 'assertion failed: expected cost_masked=false and base_amount=16000000 for the rep (holds View cost), got masked=% amount=%', v_masked, v_amount;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009005", "role": "authenticated"}';
  select count(*) into v_active_count from app.vendor_rate_versions_directory where rate_version_id = v_active_rate_id;
  if v_active_count <> 0 then
    raise exception 'assertion failed: expected a different tenant''s admin to see 0 rows for this rate version, found %', v_active_count;
  end if;
  reset role;
end;
$$;

\echo '>> search_vendor_rates: requires COM:View, filters by lane/service/mode, masked caller still receives rows (nulled cost)'
do $$
declare
  v_tenant1 uuid;
  v_result_count integer;
  v_masked boolean;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  -- app.search_vendor_rates gates via its own explicit p_actor_auth_user_id parameter,
  -- not auth.uid() -- but the view it queries (app.v_active_vendor_rates ->
  -- app.vendor_rate_versions_directory) masks cost columns via app.has_view_cost's
  -- *default* auth.uid() argument. A prior DO block in this same file left
  -- request.jwt.claims set to '' (a Postgres custom-placeholder-GUC quirk: SET LOCAL's
  -- value does not cleanly revert to unset/null across statements the way a real
  -- Supabase/PostgREST request boundary would), and auth.uid()'s own
  -- current_setting(...)::json cast then raises on that empty string rather than
  -- returning null. Resetting to a valid empty JSON object here is the correct,
  -- self-contained fix -- not a change to the shared, verbatim-from-Supabase auth stub.
  set local request.jwt.claims to '{}';

  begin
    perform app.search_vendor_rates(v_tenant1, 'ocean_freight', 'Jakarta', 'Surabaya', null, '00000000-0000-0000-0000-000000009004'::uuid, 20);
    -- The sibling-team outsider still holds COM:View at the tenant level (record-scope
    -- does not gate this tenant-wide search), so this should succeed, not raise.
  exception
    when insufficient_privilege then
      raise exception 'assertion failed: unexpected insufficient_privilege -- the outsider holds COM:View for this tenant';
  end;

  select count(*) into v_result_count from app.search_vendor_rates(v_tenant1, 'ocean_freight', 'Jakarta', 'Surabaya', null, '00000000-0000-0000-0000-000000009002'::uuid, 20);
  if v_result_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 approved+current rate for the Jakarta->Surabaya ocean lane, found %', v_result_count;
  end if;

  select count(*) into v_result_count from app.search_vendor_rates(v_tenant1, 'trucking', 'Jakarta', 'Surabaya', null, '00000000-0000-0000-0000-000000009002'::uuid, 20);
  if v_result_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for an unmatched service_type, found %', v_result_count;
  end if;

  select cost_masked into v_masked from app.search_vendor_rates(v_tenant1, 'ocean_freight', 'Jakarta', 'Surabaya', null, '00000000-0000-0000-0000-000000009003'::uuid, 20);
  if not v_masked then
    raise exception 'assertion failed: expected the manager''s own search results to also be cost-masked';
  end if;
end;
$$;

\echo '>> select_vendor_rate: requires COM:Edit + COM:View cost, ad-hoc requires override_reason + valid currency/amount, selecting a non-approved rate requires override_reason, snapshots correctly, tenant mismatch rejected'
do $$
declare
  v_tenant1 uuid;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_active_rate app.vendor_rate_versions;
  v_rejected_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_other_tenant_rate app.vendor_rate_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select * into v_opportunity from app.opportunities where name = 'Contoso Jakarta-Surabaya ocean lane';
  select * into v_request from app.costing_requests where opportunity_id = v_opportunity.id;
  select * into v_active_rate from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'FCL' and approval_status = 'approved';
  select * into v_rejected_rate from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Surabaya' and mode = 'LCL' and approval_status = 'rejected';

  begin
    perform app.select_vendor_rate(v_request.id, v_active_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the manager lacks COM:View cost required to select a rate';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.select_vendor_rate(v_request.id, null, true, 'IDR', 5000000, null, '00000000-0000-0000-0000-000000009002', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- an ad-hoc selection requires a non-empty override_reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.select_vendor_rate(v_request.id, null, true, 'idr', 5000000, 'no canonical rate on file', '00000000-0000-0000-0000-000000009002', 'tester');
    raise exception 'assertion failed: expected check_violation -- an ad-hoc selection requires a valid 3-letter-uppercase currency';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.select_vendor_rate(v_request.id, v_rejected_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009002', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- selecting a rejected (non-approved) rate version requires an override_reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_selection from app.select_vendor_rate(v_request.id, v_active_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009002', 'tester');
  if v_selection.is_adhoc or v_selection.amount <> v_active_rate.base_amount or v_selection.currency <> v_active_rate.currency then
    raise exception 'assertion failed: expected a non-adhoc selection snapshotting amount=% currency=%, got is_adhoc=% amount=% currency=%', v_active_rate.base_amount, v_active_rate.currency, v_selection.is_adhoc, v_selection.amount, v_selection.currency;
  end if;
  if (v_selection.snapshot ->> 'id')::uuid <> v_active_rate.id then
    raise exception 'assertion failed: expected the snapshot to capture the source rate version''s own id';
  end if;

  select * into v_selection from app.select_vendor_rate(v_request.id, null, true, 'USD', 999.50, 'Spot quote, no canonical rate for this cargo profile', '00000000-0000-0000-0000-000000009002', 'tester');
  if not v_selection.is_adhoc or v_selection.rate_version_id is not null or v_selection.override_reason is null then
    raise exception 'assertion failed: expected an ad-hoc selection with rate_version_id=null and override_reason set';
  end if;

  -- A rate version from a different tenant can never be selected, even by an actor who
  -- otherwise passes every gate for their own tenant''s costing request.
  select * into v_other_tenant_rate from app.create_rate_version(
    (select id from app.tenants where slug = 'betarate'), 'OTHER-TENANT-VENDOR', 'Other Tenant Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', null,
    null, null, null, null, 'IDR', 1, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009005', 'tester'
  );
  perform app.approve_rate_version(v_other_tenant_rate.id, v_other_tenant_rate.record_version, '00000000-0000-0000-0000-000000009005', 'tester');

  begin
    perform app.select_vendor_rate(v_request.id, v_other_tenant_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009002', 'tester');
    raise exception 'assertion failed: expected check_violation -- a rate version from a different tenant cannot be selected for this costing request';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> app.rate_selections_directory: cost masked without COM:View cost, visible with it; record-scoped like app.costing_responses_directory (owner/ancestor see, sibling-team outsider does not)'
do $$
declare
  v_tenant1 uuid;
  v_selection_id uuid;
  v_masked boolean;
  v_amount numeric;
  v_count integer;
begin
  -- Scoped to this file's own tenant -- a bare, unscoped "is_adhoc = false limit 1" (no
  -- ORDER BY, no tenant filter) is ambiguous the moment any other capability's own
  -- fixture (e.g. COM-150's margin-calculation.sql) also creates a non-adhoc rate
  -- selection in the same shared disposable database, the same cross-file-fragility
  -- class already found and fixed for the vendor_rate_versions lookups above.
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select id into v_selection_id from app.rate_selections where tenant_id = v_tenant1 and is_adhoc = false limit 1;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009003", "role": "authenticated"}';
  select cost_masked, amount into v_masked, v_amount from app.rate_selections_directory where id = v_selection_id;
  if not v_masked or v_amount is not null then
    raise exception 'assertion failed: expected cost_masked=true and null amount for the manager (no View cost), got masked=% amount=%', v_masked, v_amount;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009004", "role": "authenticated"}';
  select count(*) into v_count from app.rate_selections_directory where id = v_selection_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope, found % row(s)', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009002", "role": "authenticated"}';
  select cost_masked, amount into v_masked, v_amount from app.rate_selections_directory where id = v_selection_id;
  if v_masked or v_amount is null then
    raise exception 'assertion failed: expected cost_masked=false and a non-null amount for the owning rep (holds View cost), got masked=% amount=%', v_masked, v_amount;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: create/approve/reject/withdraw/select all recorded real app.audit_logs events (tenant-scoped counts, applying the COM-145/COM-148 cross-file-fragility lesson from the start)'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmerate');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.vendor_rate_versions' and action = 'create_rate_version' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 create_rate_version audit events for acmerate (the 2 initial rate versions plus 1 successful supersede revision; the 2 CHECK-violating attempts and the 1 already-superseded-source attempt inserted nothing), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.vendor_rate_versions' and action = 'approve_rate_version' and tenant_id = v_tenant1;
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 approve_rate_version audit events for acmerate, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.vendor_rate_versions' and action = 'reject_rate_version' and tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 reject_rate_version audit event for acmerate, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.vendor_rate_versions' and action = 'withdraw_rate_version' and tenant_id = v_tenant1;
  if v_count <> 0 then raise exception 'assertion failed: expected exactly 0 withdraw_rate_version audit events for acmerate (both attempts failed validation), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.rate_selections' and action = 'select_vendor_rate' and tenant_id = v_tenant1;
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 select_vendor_rate audit events for acmerate, found %', v_count; end if;
end;
$$;
