-- Real, executable regression evidence for ISS-2026-060 (vendor rate engine has no
-- zone/distance pricing dimension) -- run via `pnpm run db:test` /
-- `bash scripts/db-tests/run.sh` against a real, disposable Postgres database.
-- Scoped to supabase/migrations/20260902030000_add_vendor_rate_zone_distance_pricing_
-- iss2026060.sql. Self-contained -- builds its own tenant/role/vendor-rate fixtures
-- from scratch, mirroring scripts/db-tests/procurement-vendor-rate-tiers.sql's own
-- disclosed convention. Left untouched by this file: commercial-rate-cost-lookup.sql
-- and procurement-vendor-rate-tiers.sql both re-run unchanged in the same shared
-- disposable database (this file adds no column/constraint either of those fixture
-- sets would ever trip).
--
-- Covers exactly the three acceptance criteria named in the issue:
-- 1. a rate card WITH a zone/distance dimension configured resolves the correct tier
--    (both a zone-scoped match and a distance-bracket match, independently);
-- 2. a rate card WITHOUT one behaves unchanged (byte-identical to
--    app.calculate_vendor_rate's own flat/weight-tiered output);
-- 3. a partial/ambiguous match is handled sanely: an unmatched zone/distance input on
--    a zone/distance-priced rate raises a clear, named error (never a silent
--    fallback), and a genuinely overlapping/gapped tier set is rejected at publish
--    time (never silently mis-priced), mirroring PRC-255's own weight/volume
--    contiguity discipline.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a tenant_admin (create/approve_rate_version authority), a PRC staff actor (Edit + View cost), a PRC view-only actor (no cost), a global Supreme Admin'
do $$
declare
  v_tenant1 uuid;
  v_admin_role uuid;
  v_staff_role uuid;
  v_viewer_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000606101', 'admin@zdtier1.test'),
    ('00000000-0000-0000-0000-000000606102', 'staff@zdtier1.test'),
    ('00000000-0000-0000-0000-000000606103', 'viewer@zdtier1.test'),
    ('00000000-0000-0000-0000-000000606999', 'supreme@zdtier.test');

  perform app.provision_tenant('zdtier1', 'Zone Distance Tier Co 1', 'idem-zdtier1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'zdtier1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000606101', 'admin@zdtier1.test', 'Zdtier1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@zdtier1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000606101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000606102', 'staff@zdtier1.test', 'Zdtier1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@zdtier1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000606103', 'viewer@zdtier1.test', 'Zdtier1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@zdtier1.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000606999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'ZD Rate Admin', 'full PRC action set for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  -- PRC:View cost is protected (self-escalation guard) -- Supreme Admin grants it.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000606101', '00000000-0000-0000-0000-000000606999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'ZD Rate Staff', 'PRC:Edit + View cost', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Edit', 'View', 'View cost')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000606102', '00000000-0000-0000-0000-000000606101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'ZD Rate Viewer', 'PRC:View only, no cost', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000606103', '00000000-0000-0000-0000-000000606101', 'admin');
end $$;

\echo '>> acceptance criterion 2: a rate card WITHOUT a zone/distance dimension configured behaves EXACTLY as before -- app.calculate_vendor_rate_zoned delegates to the unmodified app._compute_vendor_rate_amount and returns a byte-identical result to app.calculate_vendor_rate itself'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'zdtier1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000606101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000606102';
  v_flat_rate app.vendor_rate_versions;
  v_old record;
  v_new record;
begin
  select * into v_flat_rate from app.create_rate_version(
    p_tenant_id => v_tenant1, p_vendor_code => 'ZD-VENDOR-1', p_vendor_name => 'Zone Distance Vendor 1', p_service_type => 'trucking',
    p_mode => null, p_origin_lane => 'Jakarta', p_destination_lane => 'Bandung', p_equipment_type => null,
    p_cargo_weight_min => null, p_cargo_weight_max => null, p_cargo_volume_min => null, p_cargo_volume_max => null,
    p_currency => 'IDR', p_base_amount => 250000, p_minimum_amount => null, p_surcharge_components => '[]'::jsonb,
    p_effective_from => now(), p_effective_to => null, p_supersedes_version_id => null,
    p_actor_auth_user_id => v_admin1, p_actor_label => 'admin'
  );
  select * into v_flat_rate from app.approve_rate_version(v_flat_rate.id, v_flat_rate.record_version, v_admin1, 'admin');

  select * into v_old from app.calculate_vendor_rate(v_flat_rate.id, null, null, null, v_staff1);
  select * into v_new from app.calculate_vendor_rate_zoned(v_flat_rate.id, null, null, null, null, null, v_staff1);

  if v_new.zone_distance_priced is distinct from false then
    raise exception 'assertion failed: expected zone_distance_priced=false for a rate with zero zone/distance tiers, got %', v_new.zone_distance_priced;
  end if;
  if v_new.computed_amount is distinct from v_old.computed_amount
     or v_new.matched_tier_id is distinct from v_old.matched_tier_id
     or v_new.subtotal_amount is distinct from v_old.subtotal_amount
     or v_new.rounding_mode is distinct from v_old.rounding_mode then
    raise exception 'assertion failed: expected app.calculate_vendor_rate_zoned to reproduce app.calculate_vendor_rate byte-for-byte on an unconfigured rate -- old=% new=%', row_to_json(v_old), row_to_json(v_new);
  end if;
  if v_new.computed_amount <> 250000 then
    raise exception 'assertion failed: expected computed_amount=250000, got %', v_new.computed_amount;
  end if;
end $$;

\echo '>> acceptance criterion 1: a rate card WITH zone and distance tiers configured resolves the correct tier -- independent zone matches and an independent distance-bracket ladder within one zone'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'zdtier1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000606101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000606102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000606103';
  v_rate app.vendor_rate_versions;
  v_tier_east app.vendor_rate_zone_distance_tiers;
  v_tier_west app.vendor_rate_zone_distance_tiers;
  v_result record;
  v_masked boolean;
  v_amount numeric;
begin
  select * into v_rate from app.create_rate_version(
    p_tenant_id => v_tenant1, p_vendor_code => 'ZD-VENDOR-1', p_vendor_name => 'Zone Distance Vendor 1', p_service_type => 'trucking',
    p_mode => null, p_origin_lane => 'Jakarta', p_destination_lane => 'Regional', p_equipment_type => null,
    p_cargo_weight_min => null, p_cargo_weight_max => null, p_cargo_volume_min => null, p_cargo_volume_max => null,
    p_currency => 'IDR', p_base_amount => 999999999, p_minimum_amount => null, p_surcharge_components => '[]'::jsonb,
    p_effective_from => now(), p_effective_to => null, p_supersedes_version_id => null,
    p_actor_auth_user_id => v_admin1, p_actor_label => 'admin'
  );

  -- Viewer (no PRC:Edit) cannot add a zone/distance tier -- reuses the unchanged
  -- app.assert_vendor_rate_version_tier_editable gate.
  begin
    perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 1, 'EAST', 0, 100, 100000, null, null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks PRC:Edit';
  exception
    when insufficient_privilege then null;
  end;

  -- EAST zone: one flat wildcard-distance tier.
  v_tier_east := app.add_vendor_rate_zone_distance_tier(v_rate.id, 1, 'EAST', null, null, 100000, null, 'idem-zd-east', v_staff1, 'staff');
  -- WEST zone: a two-step distance ladder [0,50) and [50,null).
  v_tier_west := app.add_vendor_rate_zone_distance_tier(v_rate.id, 2, 'WEST', 0, 50, 150000, null, 'idem-zd-west-1', v_staff1, 'staff');
  perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 3, 'WEST', 50, null, 200000, null, 'idem-zd-west-2', v_staff1, 'staff');

  select * into v_rate from app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  if v_rate.approval_status <> 'approved' then
    raise exception 'assertion failed: expected the disjoint EAST/WEST tier set to approve cleanly, got %', v_rate.approval_status;
  end if;

  -- EAST match: zone alone selects the tier regardless of distance (wildcard distance).
  select * into v_result from app.calculate_vendor_rate_zoned(v_rate.id, 'EAST', 12345, null, null, null, v_staff1);
  if v_result.zone_distance_priced is distinct from true or v_result.computed_amount <> 100000 or v_result.matched_tier_id <> v_tier_east.id then
    raise exception 'assertion failed: expected EAST zone to match tier % with amount 100000, got tier=% amount=% priced=%', v_tier_east.id, v_result.matched_tier_id, v_result.computed_amount, v_result.zone_distance_priced;
  end if;

  -- WEST, distance 30 -> the [0,50) step.
  select * into v_result from app.calculate_vendor_rate_zoned(v_rate.id, 'WEST', 30, null, null, null, v_staff1);
  if v_result.computed_amount <> 150000 or v_result.matched_tier_id <> v_tier_west.id then
    raise exception 'assertion failed: expected WEST distance=30 to match the [0,50) tier (150000), got tier=% amount=%', v_result.matched_tier_id, v_result.computed_amount;
  end if;

  -- WEST, distance 500 -> the [50,null) unbounded step, a DIFFERENT tier/amount.
  select * into v_result from app.calculate_vendor_rate_zoned(v_rate.id, 'WEST', 500, null, null, null, v_staff1);
  if v_result.computed_amount <> 200000 or v_result.matched_tier_id = v_tier_west.id then
    raise exception 'assertion failed: expected WEST distance=500 to match the [50,null) tier (200000), a DIFFERENT tier than distance=30''s match, got amount=%', v_result.computed_amount;
  end if;

  -- Cost masking: PRC:View cost required for calculate_vendor_rate_zoned, mirroring
  -- app.calculate_vendor_rate exactly.
  begin
    perform app.calculate_vendor_rate_zoned(v_rate.id, 'EAST', 1, null, null, null, v_viewer1);
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks PRC:View cost';
  exception
    when insufficient_privilege then null;
  end;

  -- The masked directory view: the viewer sees cost_masked=true, the staff actor
  -- (PRC:View cost) sees real amounts.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000606103", "role": "authenticated"}';
  select cost_masked, amount into v_masked, v_amount from app.vendor_rate_zone_distance_tiers_directory where id = v_tier_east.id;
  if not v_masked or v_amount is not null then
    raise exception 'assertion failed: expected cost_masked=true and amount=null for the PRC:View-only viewer, got masked=% amount=%', v_masked, v_amount;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000606102", "role": "authenticated"}';
  select cost_masked, amount into v_masked, v_amount from app.vendor_rate_zone_distance_tiers_directory where id = v_tier_east.id;
  if v_masked or v_amount <> 100000 then
    raise exception 'assertion failed: expected cost_masked=false and amount=100000 for the staff actor (PRC:View cost), got masked=% amount=%', v_masked, v_amount;
  end if;
  reset role;
end $$;

\echo '>> acceptance criterion 3: partial/ambiguous match handled sanely -- an unmatched zone/distance input on a zone/distance-priced rate raises a clear, named error (never a silent base_amount fallback); a genuinely overlapping tier set is rejected at approve time; a genuine gap is rejected at approve time; a zone_code-less caller against a zone-scoped-only rate is rejected too'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'zdtier1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000606101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000606102';
  v_rate app.vendor_rate_versions;
  v_tier1 app.vendor_rate_zone_distance_tiers;
  v_tier_bad app.vendor_rate_zone_distance_tiers;
  v_failed boolean;
begin
  select * into v_rate from app.create_rate_version(
    p_tenant_id => v_tenant1, p_vendor_code => 'ZD-VENDOR-1', p_vendor_name => 'Zone Distance Vendor 1', p_service_type => 'trucking',
    p_mode => null, p_origin_lane => 'Jakarta', p_destination_lane => 'Ambiguity Lane', p_equipment_type => null,
    p_cargo_weight_min => null, p_cargo_weight_max => null, p_cargo_volume_min => null, p_cargo_volume_max => null,
    p_currency => 'IDR', p_base_amount => 1, p_minimum_amount => null, p_surcharge_components => '[]'::jsonb,
    p_effective_from => now(), p_effective_to => null, p_supersedes_version_id => null,
    p_actor_auth_user_id => v_admin1, p_actor_label => 'admin'
  );

  v_tier1 := app.add_vendor_rate_zone_distance_tier(v_rate.id, 1, 'NORTH', 0, 100, 100000, null, null, v_staff1, 'staff');
  select * into v_rate from app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');

  -- No silent fallback: a zone_code with no configured tier (and no wildcard tier
  -- exists on this rate) raises the named error, never the flat base_amount (1).
  begin
    perform app.calculate_vendor_rate_zoned(v_rate.id, 'SOUTH', 50, null, null, null, v_staff1);
    v_failed := false;
  exception
    when no_data_found then
      v_failed := true;
      if sqlerrm not like 'zone_distance_tier_not_matched%' then
        raise exception 'assertion failed: expected zone_distance_tier_not_matched, got %', sqlerrm;
      end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an unmatched zone to be refused, not silently priced'; end if;

  -- Same again with no zone_code supplied at all (null) -- still refused, never
  -- defaults to the NORTH tier or the flat base_amount.
  begin
    perform app.calculate_vendor_rate_zoned(v_rate.id, null, 50, null, null, null, v_staff1);
    v_failed := false;
  exception
    when no_data_found then
      v_failed := true;
  end;
  if not v_failed then raise exception 'assertion failed: expected a null zone_code against a zone-scoped-only rate to be refused, not silently priced'; end if;

  -- Distance out of range within the correct zone is refused too.
  begin
    perform app.calculate_vendor_rate_zoned(v_rate.id, 'NORTH', 500, null, null, null, v_staff1);
    v_failed := false;
  exception
    when no_data_found then
      v_failed := true;
  end;
  if not v_failed then raise exception 'assertion failed: expected an out-of-range distance to be refused, not silently priced'; end if;

  -- This rate is already approved -- tiers may only be added while pending_approval
  -- (the unchanged app.assert_vendor_rate_version_tier_editable gate, reused).
  -- A fresh, still-editable sibling rate is what the NEXT block uses to actually
  -- prove the overlap/gap validator itself.
  begin
    perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 2, 'NORTH', 50, 150, 150000, null, null, v_staff1, 'staff');
    raise exception 'assertion failed: expected vendor_rate_version_not_editable -- the rate is approved, not pending_approval';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'vendor_rate_version_not_editable%' then raise; end if;
  end;
end $$;

\echo '>> acceptance criterion 3 (continued): contiguity validation on a FRESH pending_approval rate -- overlap rejected, gap rejected, the corrected contiguous set approves cleanly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'zdtier1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000606101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000606102';
  v_rate app.vendor_rate_versions;
  v_tier_bad app.vendor_rate_zone_distance_tiers;
begin
  select * into v_rate from app.create_rate_version(
    p_tenant_id => v_tenant1, p_vendor_code => 'ZD-VENDOR-1', p_vendor_name => 'Zone Distance Vendor 1', p_service_type => 'trucking',
    p_mode => null, p_origin_lane => 'Jakarta', p_destination_lane => 'Contiguity Lane', p_equipment_type => null,
    p_cargo_weight_min => null, p_cargo_weight_max => null, p_cargo_volume_min => null, p_cargo_volume_max => null,
    p_currency => 'IDR', p_base_amount => 1, p_minimum_amount => null, p_surcharge_components => '[]'::jsonb,
    p_effective_from => now(), p_effective_to => null, p_supersedes_version_id => null,
    p_actor_auth_user_id => v_admin1, p_actor_label => 'admin'
  );

  perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 1, null, 0, 100, 100000, null, null, v_staff1, 'staff');
  v_tier_bad := app.add_vendor_rate_zone_distance_tier(v_rate.id, 2, null, 50, 150, 150000, null, null, v_staff1, 'staff');

  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
    raise exception 'assertion failed: expected zone_distance_tier_overlap -- [0,100) and [50,150) overlap';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'zone_distance_tier_overlap%' then raise; end if;
  end;

  perform app.remove_vendor_rate_zone_distance_tier(v_tier_bad.id, v_tier_bad.record_version, v_staff1, 'staff');

  -- A genuine gap: [0,100) then [150,200) leaves [100,150) uncovered.
  v_tier_bad := app.add_vendor_rate_zone_distance_tier(v_rate.id, 2, null, 150, 200, 200000, null, null, v_staff1, 'staff');
  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
    raise exception 'assertion failed: expected zone_distance_tier_gap -- [100,150) is uncovered';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'zone_distance_tier_gap%' then raise; end if;
  end;

  perform app.remove_vendor_rate_zone_distance_tier(v_tier_bad.id, v_tier_bad.record_version, v_staff1, 'staff');

  -- Corrected: [0,100) then [100,null) -- contiguous, approves cleanly.
  perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 2, null, 100, null, 200000, null, null, v_staff1, 'staff');
  select * into v_rate from app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  if v_rate.approval_status <> 'approved' then
    raise exception 'assertion failed: expected the corrected contiguous zone/distance tier set to approve cleanly, got %', v_rate.approval_status;
  end if;
end $$;

\echo '>> at least one dimension required: a tier with zone_code, distance_min and distance_max all null is refused (guards the "zero rows = old behavior" invariant)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'zdtier1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000606101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000606102';
  v_rate app.vendor_rate_versions;
begin
  select * into v_rate from app.create_rate_version(
    p_tenant_id => v_tenant1, p_vendor_code => 'ZD-VENDOR-1', p_vendor_name => 'Zone Distance Vendor 1', p_service_type => 'trucking',
    p_mode => null, p_origin_lane => 'Jakarta', p_destination_lane => 'Nodim Lane', p_equipment_type => null,
    p_cargo_weight_min => null, p_cargo_weight_max => null, p_cargo_volume_min => null, p_cargo_volume_max => null,
    p_currency => 'IDR', p_base_amount => 1, p_minimum_amount => null, p_surcharge_components => '[]'::jsonb,
    p_effective_from => now(), p_effective_to => null, p_supersedes_version_id => null,
    p_actor_auth_user_id => v_admin1, p_actor_label => 'admin'
  );

  begin
    perform app.add_vendor_rate_zone_distance_tier(v_rate.id, 1, null, null, null, 100000, null, null, v_staff1, 'staff');
    raise exception 'assertion failed: expected invalid_zone_distance_dimension -- a tier with no configured dimension must be refused';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_zone_distance_dimension%' then raise; end if;
  end;
end $$;
