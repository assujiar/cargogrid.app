-- Real, executable test evidence for PRC-262 (Vendor Capacity and Availability,
-- CG-S11-PRC-013) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Scoped to this checkpoint's own additive migration (supabase/migrations/
-- 20260730710000_create_procurement_vendor_capacity.sql). Self-contained -- builds its
-- own tenants/vendors from scratch, mirroring procurement-vendor-contract.sql's own
-- disclosed convention.
--
-- Covers: offer create/update/publish/archive, blackout, the concurrency-critical
-- reserve/accept/decline/release/consume lifecycle including a REAL two-process
-- concurrent over-reservation race (reusing scripts/db-tests/wms-picking-concurrency-
-- helper.sh, the same helper PRC-258's own revise-race test uses), idempotency target
-- verification, window/blackout validation, and cross-tenant/authority denial.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (vcap1): tenant_admin (admin1), full-PRC staff (staff1, Create/Edit/View/Override), View-only viewer (viewer1), no-PRC outsider (outsider1). Tenant2 (vcap2): tenant_admin (admin2) + staff2. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_staff_role uuid;
  v_viewer_role uuid;
  v_outsider_role uuid;
  v_t2_staff_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000262101', 'admin@vcap1.test'),
    ('00000000-0000-0000-0000-000000262102', 'staff@vcap1.test'),
    ('00000000-0000-0000-0000-000000262103', 'viewer@vcap1.test'),
    ('00000000-0000-0000-0000-000000262104', 'outsider@vcap1.test'),
    ('00000000-0000-0000-0000-000000262201', 'admin@vcap2.test'),
    ('00000000-0000-0000-0000-000000262202', 'staff@vcap2.test'),
    ('00000000-0000-0000-0000-000000262999', 'supreme@vcap.test');

  perform app.provision_tenant('vcap1', 'Vendor Capacity Co 1', 'idem-vcap1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vcap1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('vcap2', 'Vendor Capacity Co 2', 'idem-vcap2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vcap2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000262101', 'admin@vcap1.test', 'Vcap1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vcap1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000262101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000262102', 'staff@vcap1.test', 'Vcap1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vcap1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000262103', 'viewer@vcap1.test', 'Vcap1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vcap1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000262104', 'outsider@vcap1.test', 'Vcap1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@vcap1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000262201', 'admin@vcap2.test', 'Vcap2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vcap2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000262201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000262202', 'staff@vcap2.test', 'Vcap2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vcap2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000262999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Vcap1 Admin', 'full PRC for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Override', 'Approve')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000262101', '00000000-0000-0000-0000-000000262999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Vcap1 Staff', 'Create/Edit/View', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000262102', '00000000-0000-0000-0000-000000262101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Vcap1 Viewer', 'View only', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000262103', '00000000-0000-0000-0000-000000262101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Vcap1 Outsider', 'no PRC at all', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_outsider_role, 'tester')).id, array[]::uuid[], 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_outsider_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000262104', '00000000-0000-0000-0000-000000262101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Vcap2 Staff', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_staff_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000262202', '00000000-0000-0000-0000-000000262201', 'admin');
end $$;

\echo '>> setup: one ACTIVE vendor in tenant1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000262101';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Capacity A', 'VCAPA', 'PT', 'REG-VCAP-A', 'logistics', 30, 'staff_created', 'idem-vcap-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani A', 'Ops', 'ani@vcapa.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
end $$;

\echo '>> create/update/publish offer: validation, idempotency target-mismatch (C-01), authority'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000262102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000262104';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Capacity A');
  v_offer app.vendor_capacity_offers;
  v_offer2 app.vendor_capacity_offers;
  v_failed boolean;
begin
  v_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_vendor_master, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
    100, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-offer-1', v_staff1, 'staff'
  );
  if v_offer.status <> 'draft' or v_offer.quantity <> 100 then
    raise exception 'assertion failed: expected a fresh draft offer with quantity=100, got status=% quantity=%', v_offer.status, v_offer.quantity;
  end if;

  -- idempotency replay: identical key returns the SAME row
  v_offer2 := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_vendor_master, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
    100, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-offer-1', v_staff1, 'staff'
  );
  if v_offer2.id <> v_offer.id then
    raise exception 'assertion failed: expected the identical idempotency-key replay to return the SAME row';
  end if;

  -- C-01 coverage: reusing the SAME key for a genuinely different quantity is a conflict
  begin
    perform app.create_vendor_capacity_offer_draft(
      v_tenant1, v_vendor_master, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
      9999, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-offer-1', v_staff1, 'staff'
    );
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a target-mismatched replay, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected reusing idem-vcap-offer-1 for a different quantity to be rejected as a conflict'; end if;

  -- Tier C batch-3 fix regression: the ORIGINAL in-prompt comparison only covered
  -- vendor/service_type/quantity/window_start -- live-reproduced by an independent
  -- Tier C lens as silently discarding a caller's real window_end on replay. Same
  -- vendor/service/quantity/window_start as idem-vcap-offer-1's own original call,
  -- but a genuinely different window_end -- must now ALSO be a conflict.
  begin
    perform app.create_vendor_capacity_offer_draft(
      v_tenant1, v_vendor_master, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'vehicle', null,
      100, 'teu', '2026-01-01'::timestamptz, '2027-06-30'::timestamptz, 'idem-vcap-offer-1', v_staff1, 'staff'
    );
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a window_end-mismatched replay, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected reusing idem-vcap-offer-1 with a mismatched window_end (2027-06-30 vs the original 2026-12-31) to be rejected as a conflict, not silently returned with the ORIGINAL window_end'; end if;

  -- invalid window rejected
  begin
    perform app.create_vendor_capacity_offer_draft(v_tenant1, v_vendor_master, null, 'ocean_freight', null, null, null, 'general', null, 10, 'teu', '2026-06-01'::timestamptz, '2026-01-01'::timestamptz, 'idem-vcap-bad-1', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_window%' then
      raise exception 'assertion failed: expected invalid_window, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an inverted window to be rejected'; end if;

  -- an outsider with no PRC:Create is denied
  begin
    perform app.create_vendor_capacity_offer_draft(v_tenant1, v_vendor_master, null, 'ocean_freight', null, null, null, 'general', null, 10, 'teu', now(), now() + interval '1 day', 'idem-vcap-outsider-1', v_outsider1, 'outsider');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Create-less outsider to be denied'; end if;

  -- update preserves untouched optional fields (coalesce-by-null)
  v_offer := app.update_vendor_capacity_offer_draft(v_offer.id, v_offer.record_version, null, null, null, null, null, 120, 'teu', v_offer.window_start, v_offer.window_end, v_staff1, 'staff');
  if v_offer.quantity <> 120 or v_offer.origin_lane <> 'Jakarta' then
    raise exception 'assertion failed: expected quantity updated to 120 and origin_lane preserved as Jakarta, got quantity=% origin_lane=%', v_offer.quantity, v_offer.origin_lane;
  end if;

  v_offer := app.publish_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_staff1, 'staff');
  if v_offer.status <> 'published' then
    raise exception 'assertion failed: expected status=published, got %', v_offer.status;
  end if;

  -- a published offer can no longer be edited
  begin
    perform app.update_vendor_capacity_offer_draft(v_offer.id, v_offer.record_version, null, null, null, null, null, 50, 'teu', v_offer.window_start, v_offer.window_end, v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected editing a published offer to be rejected'; end if;
end $$;

\echo '>> reserve/accept/decline/release/consume lifecycle, blackout enforcement, over-reservation rejection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000262102';
  v_offer app.vendor_capacity_offers;
  v_res1 app.vendor_capacity_reservations;
  v_res2 app.vendor_capacity_reservations;
  v_available numeric;
  v_failed boolean;
begin
  select * into v_offer from app.vendor_capacity_offers where tenant_id = v_tenant1 and idempotency_key = 'idem-vcap-offer-1';

  v_available := app.compute_vendor_capacity_available(v_offer.id, '2026-03-01'::timestamptz, '2026-03-31'::timestamptz, v_staff1);
  if v_available <> 120 then
    raise exception 'assertion failed: expected 120 available before any reservation, got %', v_available;
  end if;

  v_res1 := app.reserve_vendor_capacity(v_offer.id, 80, '2026-03-01'::timestamptz, '2026-03-31'::timestamptz, 'manual', null, 'idem-vcap-res-1', v_staff1, 'staff');
  if v_res1.status <> 'held' or v_res1.requested_quantity <> 80 then
    raise exception 'assertion failed: expected status=held requested_quantity=80, got %/%', v_res1.status, v_res1.requested_quantity;
  end if;

  -- a second, overlapping reservation that would exceed the remaining 40 is rejected
  begin
    perform app.reserve_vendor_capacity(v_offer.id, 50, '2026-03-15'::timestamptz, '2026-04-15'::timestamptz, 'manual', null, 'idem-vcap-res-2', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'over_reservation%' then
      raise exception 'assertion failed: expected over_reservation, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an over-committing overlapping reservation to be rejected'; end if;

  -- a NON-overlapping reservation (later window) succeeds independently
  v_res2 := app.reserve_vendor_capacity(v_offer.id, 100, '2026-07-01'::timestamptz, '2026-07-31'::timestamptz, 'manual', null, 'idem-vcap-res-3', v_staff1, 'staff');
  if v_res2.status <> 'held' then
    raise exception 'assertion failed: expected the non-overlapping reservation to succeed, got %', v_res2.status;
  end if;

  -- a reservation outside the offer's own declared window is rejected
  begin
    perform app.reserve_vendor_capacity(v_offer.id, 10, '2027-01-01'::timestamptz, '2027-02-01'::timestamptz, 'manual', null, 'idem-vcap-res-4', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reservation_outside_offer_window%' then
      raise exception 'assertion failed: expected reservation_outside_offer_window, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a reservation outside the offer window to be rejected'; end if;

  -- blackout blocks a NEW overlapping reservation but does not retroactively cancel v_res1
  perform app.add_vendor_capacity_blackout(v_offer.id, '2026-03-10'::timestamptz, '2026-03-20'::timestamptz, 'scheduled maintenance', v_staff1, 'staff');
  begin
    perform app.reserve_vendor_capacity(v_offer.id, 5, '2026-03-12'::timestamptz, '2026-03-14'::timestamptz, 'manual', null, 'idem-vcap-res-5', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reservation_in_blackout%' then
      raise exception 'assertion failed: expected reservation_in_blackout, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a reservation overlapping a blackout to be rejected'; end if;
  if (select status from app.vendor_capacity_reservations where id = v_res1.id) <> 'held' then
    raise exception 'assertion failed: expected v_res1 to remain held -- a blackout added afterward must not retroactively cancel it (design note 6)';
  end if;

  -- C-09 fix coverage: idempotency scope is PER-OFFER, not tenant-wide (this
  -- prompt's own Tier B self-check found the unique index was originally scoped to
  -- (tenant_id, idempotency_key) while app.reserve_vendor_capacity's own lookup/
  -- race-recovery queries were always offer_id-scoped -- a real mismatch that would
  -- have surfaced a raw unique_violation, not a clean idempotency_key_conflict, the
  -- moment a key was ever reused across two different offers. Fixed by rescoping the
  -- index to (offer_id, idempotency_key) -- reusing the SAME key string against a
  -- DIFFERENT offer is therefore legitimate (two genuinely different resources) and
  -- must succeed independently, proven live here, not merely inferred from the DDL.
  declare
    v_second_offer app.vendor_capacity_offers;
    v_second_reservation app.vendor_capacity_reservations;
  begin
    v_second_offer := app.create_vendor_capacity_offer_draft(
      v_tenant1, (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Capacity A'), null,
      'warehousing', null, null, null, 'warehouse', null, 500, 'sqm', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-offer-2', v_staff1, 'staff'
    );
    v_second_offer := app.publish_vendor_capacity_offer(v_second_offer.id, v_second_offer.record_version, v_staff1, 'staff');
    -- 'idem-vcap-res-1' was already consumed by v_res1 above, against the FIRST offer.
    v_second_reservation := app.reserve_vendor_capacity(v_second_offer.id, 10, '2026-02-01'::timestamptz, '2026-02-05'::timestamptz, 'manual', null, 'idem-vcap-res-1', v_staff1, 'staff');
    if v_second_reservation.offer_id <> v_second_offer.id or v_second_reservation.status <> 'held' then
      raise exception 'assertion failed: expected the SAME idempotency key to succeed independently against a genuinely different offer, got offer_id=% status=%', v_second_reservation.offer_id, v_second_reservation.status;
    end if;
  end;

  -- decline requires a reason and frees the held quantity
  v_res1 := app.decline_vendor_capacity_reservation(v_res1.id, v_res1.record_version, 'vendor unavailable after all', v_staff1, 'staff');
  if v_res1.status <> 'declined' or v_res1.decline_reason is null then
    raise exception 'assertion failed: expected status=declined with a reason, got %/%', v_res1.status, v_res1.decline_reason;
  end if;
  v_available := app.compute_vendor_capacity_available(v_offer.id, '2026-03-01'::timestamptz, '2026-03-31'::timestamptz, v_staff1);
  if v_available <> 120 then
    raise exception 'assertion failed: expected the declined reservation''s 80 to be freed back (120 available again for that window), got %', v_available;
  end if;

  -- accept -> release -> archive-blocked-while-active -> consume lifecycle on v_res2
  v_res2 := app.accept_vendor_capacity_reservation(v_res2.id, v_res2.record_version, v_staff1, 'staff');
  if v_res2.status <> 'accepted' then
    raise exception 'assertion failed: expected status=accepted, got %', v_res2.status;
  end if;

  begin
    perform app.archive_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'active_reservations_exist%' then
      raise exception 'assertion failed: expected active_reservations_exist, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected archiving an offer with an active (accepted) reservation to be rejected'; end if;

  v_res2 := app.consume_vendor_capacity_reservation(v_res2.id, v_res2.record_version, v_staff1, 'staff');
  if v_res2.status <> 'consumed' then
    raise exception 'assertion failed: expected status=consumed, got %', v_res2.status;
  end if;
end $$;

\echo '>> REAL two-process concurrent race (design note 2''s own headline claim, "no silent overbooking"): two reservations, 70 tons each, racing the SAME 100-ton offer over the SAME window -- together they exceed capacity, so exactly one must win, never both, never neither. Launched via scripts/db-tests/wms-picking-concurrency-helper.sh, the same helper PRC-258''s own revise-race and Prompt 236''s own pick-task-generation race use.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000262101';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Capacity A');
  v_offer app.vendor_capacity_offers;
begin
  v_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_vendor_master, null, 'trucking', 'FTL', 'Jakarta', 'Bandung', 'vehicle', null,
    100, 'ton', '2026-05-01'::timestamptz, '2026-05-31'::timestamptz, 'idem-vcap-race-offer', v_admin1, 'admin'
  );
  v_offer := app.publish_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_admin1, 'admin');
end $$;

select id as race_offer_id from app.vendor_capacity_offers where tenant_id = (select id from app.tenants where slug = 'vcap1') and idempotency_key = 'idem-vcap-race-offer' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.reserve_vendor_capacity(''' :race_offer_id ''', 70, ''2026-05-05'', ''2026-05-10'', ''manual'', null, ''idem-vcap-race-a'', ''00000000-0000-0000-0000-000000262101'', ''admin'');'
\set race_sql_b 'select app.reserve_vendor_capacity(''' :race_offer_id ''', 70, ''2026-05-06'', ''2026-05-11'', ''manual'', null, ''idem-vcap-race-b'', ''00000000-0000-0000-0000-000000262102'', ''staff'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-vcap-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-vcap-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- psql does not interpolate :variables inside a do $$ ... $$ body (confirmed
-- empirically, matches advanced-tms-wms-picking.sql's own identical disclosure) --
-- re-resolve the offer by its own stable idempotency_key instead.
do $$
declare
  v_offer_id uuid;
  v_won_count integer;
  v_total_committed numeric;
begin
  select id into v_offer_id from app.vendor_capacity_offers where tenant_id = (select id from app.tenants where slug = 'vcap1') and idempotency_key = 'idem-vcap-race-offer';
  select count(*) into v_won_count from app.vendor_capacity_reservations where offer_id = v_offer_id and idempotency_key in ('idem-vcap-race-a', 'idem-vcap-race-b') and status = 'held';
  if v_won_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE of the two racing 70-ton reservations to have won (held), got % -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_won_count;
  end if;

  select coalesce(sum(requested_quantity), 0) into v_total_committed from app.vendor_capacity_reservations where offer_id = v_offer_id and status in ('held', 'accepted', 'consumed');
  if v_total_committed > 100 then
    raise exception 'assertion failed: expected total committed quantity to never exceed the offer''s own 100-ton capacity, got % -- a real overbooking occurred', v_total_committed;
  end if;

  raise notice 'concurrent reservation race proof: exactly one of two racing 70-ton reservations won, total committed=% (<=100) -- see RACE_OUT_A/RACE_OUT_B captured above', v_total_committed;
end $$;

\echo '>> cross-tenant authority denial (C-05 fold: not-found, never insufficient_authority, so a zero-membership caller cannot confirm existence) and viewer-authority read'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_staff2 uuid := '00000000-0000-0000-0000-000000262202';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000262103';
  v_offer_id uuid;
  v_offer app.vendor_capacity_offers;
  v_failed boolean;
begin
  select id into v_offer_id from app.vendor_capacity_offers where tenant_id = v_tenant1 and idempotency_key = 'idem-vcap-offer-1';

  begin
    perform app.get_vendor_capacity_offer(v_offer_id, v_staff2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_capacity_offer_not_found%' then
      raise exception 'assertion failed: expected vendor_capacity_offer_not_found (never insufficient_authority) for a cross-tenant read, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant get_vendor_capacity_offer to be denied'; end if;

  -- a View-only actor in the SAME tenant reads it successfully (View is sufficient, no Edit/Create/Override needed for a read)
  v_offer := app.get_vendor_capacity_offer(v_offer_id, v_viewer1);
  if v_offer.id <> v_offer_id then
    raise exception 'assertion failed: expected the View-only viewer to successfully read the offer';
  end if;
end $$;

\echo '>> Tier C batch-3 fix regression (C-05, live-reproduced by an independent Tier C lens): the SAME not-found fold now also applies to every WRITE RPC, not just reads'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_staff2 uuid := '00000000-0000-0000-0000-000000262202';
  v_offer_id uuid;
  v_offer app.vendor_capacity_offers;
  v_failed boolean;
begin
  select id into v_offer_id from app.vendor_capacity_offers where tenant_id = v_tenant1 and idempotency_key = 'idem-vcap-offer-1';
  select * into v_offer from app.vendor_capacity_offers where id = v_offer_id;

  begin
    perform app.update_vendor_capacity_offer_draft(v_offer_id, v_offer.record_version, v_offer.contract_id, v_offer.mode, v_offer.origin_lane, v_offer.destination_lane, v_offer.resource_master_id, v_offer.quantity, v_offer.uom, v_offer.window_start, v_offer.window_end, v_staff2, 'staff2');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_capacity_offer_not_found%' then
      raise exception 'assertion failed: expected vendor_capacity_offer_not_found (never insufficient_authority, which would disclose a real row exists in another tenant) for a cross-tenant WRITE, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant update_vendor_capacity_offer_draft to be denied'; end if;

  begin
    perform app.reserve_vendor_capacity(v_offer_id, 1, v_offer.window_start, v_offer.window_end, 'manual', null, 'idem-vcap-crosstenant-probe', v_staff2, 'staff2');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_capacity_offer_not_found%' then
      raise exception 'assertion failed: expected vendor_capacity_offer_not_found for a cross-tenant reserve_vendor_capacity, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant reserve_vendor_capacity to be denied'; end if;
end $$;

\echo '>> Tier C batch-3 fix regression (C-15, live-reproduced by an independent Tier C lens): a compliance-holded vendor, or an inactive/lapsed/not-yet-effective governing contract, must now be blocked at publish and at reserve'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000262101';
  v_supreme uuid := '00000000-0000-0000-0000-000000262999';
  v_vendor app.vendor_profiles;
  v_req app.vendor_compliance_requirements;
  v_contract app.vendor_contracts;
  v_offer app.vendor_capacity_offers;
  v_offer2 app.vendor_capacity_offers;
  v_failed boolean;
begin
  -- a fresh, otherwise-active vendor, placed on a REAL compliance hold via the actual
  -- requirement/document pipeline (never a raw INSERT into app.vendor_compliance_
  -- status, which is written only by app._recalculate_vendor_compliance_status_family
  -- -- mirrors scripts/db-tests/procurement-sourcing.sql's own established "vendor D"
  -- pattern exactly): a published BLOCKING requirement scoped to this vendor's own
  -- category, with no document ever submitted.
  v_vendor := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Capacity Compliance Hold', 'VCAPHOLD', 'PT', 'REG-VCAP-HOLD', 'vcap_restricted_category', 30, 'staff_created', 'idem-vcap-hold-vendor', v_admin1, 'admin');
  perform app.add_vendor_contact(v_vendor.master_record_id, 'Hana H', 'Ops', 'hana@vcaphold.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_vendor.master_record_id, 'legal', 'Jl. Hold 1', 'Jakarta', 'DKI Jakarta', '10110', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_vendor.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_vendor.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_vendor from app.vendor_profiles where master_record_id = v_vendor.master_record_id;
  v_vendor := app.submit_vendor_profile_for_review(v_vendor.master_record_id, v_vendor.record_version, v_admin1, 'admin');
  v_vendor := app.decide_vendor_profile_review(v_vendor.master_record_id, v_vendor.record_version, 'approve', null, v_admin1, 'admin');
  v_vendor := app.activate_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, v_admin1, 'admin');

  perform app.register_document_type('vcap_hold_compliance_doc', 'Vendor Capacity Hold Compliance Doc', 'PRC', v_supreme, 'supreme');
  v_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'vcap_restricted_category', null, 'vcap_hold_compliance_doc', 'Vendor Capacity Hold Requirement', null, 'blocking', false, null, null, 'idem-vcap-hold-req', v_admin1, 'admin');
  v_req := app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_admin1, 'admin');
  perform app.recalculate_vendor_compliance_status(v_vendor.master_record_id, v_admin1, 'admin');

  if not exists (select 1 from app.vendor_compliance_status where vendor_master_record_id = v_vendor.master_record_id and eligibility_hold = true) then
    raise exception 'assertion failed: expected the fresh vendor to carry a real eligibility_hold=true compliance status after recalculation (test setup precondition, not the fix under test)';
  end if;

  v_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_vendor.master_record_id, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'general', null,
    50, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-hold-offer', v_admin1, 'admin'
  );
  begin
    perform app.publish_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_compliance_hold%' then
      raise exception 'assertion failed: expected vendor_compliance_hold, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected publishing an offer for a compliance-holded vendor to be rejected'; end if;

  -- a SEPARATE, already-active, non-held vendor (PT Vendor Capacity A) linked to a
  -- NOT-YET-EFFECTIVE contract -- isolates the contract-effective-window check from
  -- the compliance-hold check above (the compliance check runs first inside the RPC,
  -- so reusing the held vendor here would hit vendor_compliance_hold again, never
  -- reaching this second, independent check).
  v_contract := app.create_vendor_contract_draft(
    v_tenant1, (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Capacity A'), 'framework', (current_date + interval '30 days')::date, null, null, 30,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vcap-hold-contract', v_admin1, 'admin'
  );
  v_contract := app.submit_vendor_contract_for_approval(v_contract.id, v_contract.record_version, 'idem-vcap-hold-contract-submit', v_admin1, 'admin');
  v_contract := app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');

  v_offer2 := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_contract.vendor_master_id, v_contract.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'general', null,
    50, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-notyeteffective-offer', v_admin1, 'admin'
  );
  begin
    perform app.publish_vendor_capacity_offer(v_offer2.id, v_offer2.record_version, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'governing_contract_not_yet_effective%' then
      raise exception 'assertion failed: expected governing_contract_not_yet_effective, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected publishing an offer governed by a not-yet-effective contract to be rejected'; end if;

  -- reserve's OWN independent re-check (not merely trusted from publish time): a
  -- THIRD vendor, active and eligible when its offer was published, then placed on
  -- the SAME real compliance hold afterward -- reserve must reject it even though
  -- publish already succeeded earlier.
  declare
    v_vendor3 app.vendor_profiles;
    v_offer3 app.vendor_capacity_offers;
  begin
    v_vendor3 := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Capacity Hold At Reserve', 'VCAPHOLD2', 'PT', 'REG-VCAP-HOLD2', 'vcap_restricted_category', 30, 'staff_created', 'idem-vcap-hold2-vendor', v_admin1, 'admin');
    perform app.add_vendor_contact(v_vendor3.master_record_id, 'Rian R', 'Ops', 'rian@vcaphold2.test', '0812', true, v_admin1, 'admin');
    perform app.add_vendor_address(v_vendor3.master_record_id, 'legal', 'Jl. Hold 2', 'Jakarta', 'DKI Jakarta', '10111', 'Indonesia', v_admin1, 'admin');
    perform app.add_vendor_service(v_vendor3.master_record_id, 'ocean_freight', v_admin1, 'admin');
    perform app.add_vendor_coverage(v_vendor3.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
    select * into v_vendor3 from app.vendor_profiles where master_record_id = v_vendor3.master_record_id;
    v_vendor3 := app.submit_vendor_profile_for_review(v_vendor3.master_record_id, v_vendor3.record_version, v_admin1, 'admin');
    v_vendor3 := app.decide_vendor_profile_review(v_vendor3.master_record_id, v_vendor3.record_version, 'approve', null, v_admin1, 'admin');
    v_vendor3 := app.activate_vendor_profile(v_vendor3.master_record_id, v_vendor3.record_version, v_admin1, 'admin');
    -- eligible now (no requirement recalculation has run for this vendor yet)

    v_offer3 := app.create_vendor_capacity_offer_draft(
      v_tenant1, v_vendor3.master_record_id, null, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 'general', null,
      50, 'teu', '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-hold2-offer', v_admin1, 'admin'
    );
    v_offer3 := app.publish_vendor_capacity_offer(v_offer3.id, v_offer3.record_version, v_admin1, 'admin');

    -- the same published requirement (vcap_restricted_category) now applies retroactively
    perform app.recalculate_vendor_compliance_status(v_vendor3.master_record_id, v_admin1, 'admin');
    if not exists (select 1 from app.vendor_compliance_status where vendor_master_record_id = v_vendor3.master_record_id and eligibility_hold = true) then
      raise exception 'assertion failed: expected the third vendor to carry a real eligibility_hold=true compliance status after recalculation (test setup precondition, not the fix under test)';
    end if;

    begin
      perform app.reserve_vendor_capacity(v_offer3.id, 10, '2026-02-01'::timestamptz, '2026-02-10'::timestamptz, 'manual', null, 'idem-vcap-hold2-reserve', v_admin1, 'admin');
      v_failed := false;
    exception when others then
      v_failed := true;
      if sqlerrm not like 'vendor_compliance_hold%' then
        raise exception 'assertion failed: expected vendor_compliance_hold at reserve time, got %', sqlerrm;
      end if;
    end;
    if not v_failed then raise exception 'assertion failed: expected reserving against an already-published offer to be rejected once its vendor is compliance-held, never trusted from publish time alone'; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new vendor-capacity function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon'
    and routine_name like '%vendor_capacity%';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any vendor-capacity function, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every vendor-capacity mutation recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action in (
    'create_vendor_capacity_offer_draft', 'update_vendor_capacity_offer_draft', 'publish_vendor_capacity_offer',
    'archive_vendor_capacity_offer', 'add_vendor_capacity_blackout', 'remove_vendor_capacity_blackout',
    'reserve_vendor_capacity', 'accept_vendor_capacity_reservation', 'decline_vendor_capacity_reservation',
    'release_vendor_capacity_reservation', 'consume_vendor_capacity_reservation'
  );
  if v_count < 10 then
    raise exception 'assertion failed: expected at least 10 captured vendor-capacity audit events, found %', v_count;
  end if;
end $$;

-- ===========================================================================
-- ISS-2026-058: Prompt 262 §22 "manual confirmation with evidence".
--
-- The gap this closes was not a bug but an omission: §22 names a second route to
-- `accepted` -- somebody attests the vendor agreed OUT OF BAND and attaches the document
-- that says so -- and 20260730710000 implemented only the in-system route. The capability's
-- own Tier B self-check marked taxonomy class C-10 (file/evidence linking) "N/A" for this
-- domain, which is how a named requirement went missing without anyone noticing.
--
-- What these assertions are actually for: proving the manual route records a WEAKER claim
-- honestly rather than laundering it into looking like the system watched the vendor accept.
-- Every one of them is a way the record could lie if the constraint or the RPC were absent.
-- ===========================================================================

\echo '>> ISS-2026-058 setup: a document type for manual confirmation evidence, published for tenant1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_doc_draft app.config_versions;
begin
  perform app.register_document_type('vendor_capacity_confirmation', 'Vendor Capacity Manual Confirmation Evidence', 'DOC', '00000000-0000-0000-0000-000000262999', 'supreme');
  v_doc_draft := app.create_config_draft('document:vendor_capacity_confirmation', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000262101', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000262101', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000262101', now(), 'admin');
end $$;

\echo '>> ISS-2026-058: app.confirm_vendor_capacity_reservation_manually refuses a confirmation with no evidence, no note, evidence scoped to another record, an unscanned file, an infected file, and an actor without PRC:Edit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vcap1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000262102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000262103';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Capacity A');
  v_offer app.vendor_capacity_offers;
  v_res app.vendor_capacity_reservations;
  v_other_res app.vendor_capacity_reservations;
  v_clean_file app.files;
  v_pending_file app.files;
  v_infected_file app.files;
  v_wrong_record_file app.files;
  v_failed boolean;
begin
  v_offer := app.create_vendor_capacity_offer_draft(
    v_tenant1, v_vendor_master, null, 'warehousing', null, null, null, 'warehouse', null, 400, 'sqm',
    '2026-01-01'::timestamptz, '2026-12-31'::timestamptz, 'idem-vcap-offer-058', v_staff1, 'staff'
  );
  v_offer := app.publish_vendor_capacity_offer(v_offer.id, v_offer.record_version, v_staff1, 'staff');

  v_res := app.reserve_vendor_capacity(v_offer.id, 50, '2026-05-01'::timestamptz, '2026-05-31'::timestamptz, 'manual', null, 'idem-vcap-res-058a', v_staff1, 'staff');
  v_other_res := app.reserve_vendor_capacity(v_offer.id, 50, '2026-06-01'::timestamptz, '2026-06-30'::timestamptz, 'manual', null, 'idem-vcap-res-058b', v_staff1, 'staff');

  -- no evidence at all: the whole point of §22 is the document, so a confirmation without
  -- one is a bare status change wearing the word "confirmed".
  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, null, 'vendor agreed by phone', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'confirmation_evidence_required%' then
      raise exception 'assertion failed: expected confirmation_evidence_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a manual confirmation with no evidence file to be refused'; end if;

  -- a blank note is refused BEFORE the file is even looked up: a document with no account of
  -- what was agreed and with whom leaves the next reader guessing at the very thing in dispute.
  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, gen_random_uuid(), '   ', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'confirmation_note_required%' then
      raise exception 'assertion failed: expected confirmation_note_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a manual confirmation with a blank note to be refused'; end if;

  select * into v_clean_file from app.initiate_file_upload(
    v_tenant1, 'vendor_capacity_confirmation', 'vendor_capacity_reservation', v_res.id,
    'vendor-confirmation.pdf', 'application/pdf', 20480, null, false, null, '{}'::uuid[], null,
    'idem-vcap-file-058-clean', v_staff1, 'staff'
  );
  select * into v_pending_file from app.initiate_file_upload(
    v_tenant1, 'vendor_capacity_confirmation', 'vendor_capacity_reservation', v_res.id,
    'vendor-confirmation-unscanned.pdf', 'application/pdf', 20480, null, false, null, '{}'::uuid[], null,
    'idem-vcap-file-058-pending', v_staff1, 'staff'
  );
  select * into v_infected_file from app.initiate_file_upload(
    v_tenant1, 'vendor_capacity_confirmation', 'vendor_capacity_reservation', v_res.id,
    'vendor-confirmation-bad.pdf', 'application/pdf', 20480, null, false, null, '{}'::uuid[], null,
    'idem-vcap-file-058-infected', v_staff1, 'staff'
  );
  -- Uploaded against the OTHER reservation. Everything else about it is legitimate -- same
  -- tenant, same document type, clean scan -- which is exactly why record scope has to be
  -- re-checked here rather than assumed from a successful upload.
  select * into v_wrong_record_file from app.initiate_file_upload(
    v_tenant1, 'vendor_capacity_confirmation', 'vendor_capacity_reservation', v_other_res.id,
    'other-reservation.pdf', 'application/pdf', 20480, null, false, null, '{}'::uuid[], null,
    'idem-vcap-file-058-other', v_staff1, 'staff'
  );
  perform app.record_file_scan_result(v_clean_file.id, 'clean', 'test-scanner-058', v_staff1, 'staff');
  perform app.record_file_scan_result(v_infected_file.id, 'infected', 'test-scanner-058', v_staff1, 'staff');
  perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', 'test-scanner-058', v_staff1, 'staff');

  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, v_wrong_record_file.id, 'vendor agreed by phone', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'evidence_file_not_found%' then
      raise exception 'assertion failed: expected evidence_file_not_found for a file scoped to a different reservation, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected evidence uploaded against a DIFFERENT reservation to be refused'; end if;

  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, v_pending_file.id, 'vendor agreed by phone', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'evidence_file_not_scanned%' then
      raise exception 'assertion failed: expected evidence_file_not_scanned, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an unscanned evidence file to be refused'; end if;

  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, v_infected_file.id, 'vendor agreed by phone', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'evidence_file_infected%' then
      raise exception 'assertion failed: expected evidence_file_infected, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an infected evidence file to be refused'; end if;

  -- the manual route is a real acceptance, so it carries the same PRC:Edit authority as the
  -- in-system one -- attesting on the vendor's behalf is not a lesser act than watching them.
  begin
    perform app.confirm_vendor_capacity_reservation_manually(v_res.id, v_res.record_version, v_clean_file.id, 'vendor agreed by phone', v_viewer1, 'viewer');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only actor, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a PRC:View-only actor to be refused the manual confirmation'; end if;

  -- the legitimate path
  v_res := app.confirm_vendor_capacity_reservation_manually(
    v_res.id, v_res.record_version, v_clean_file.id, '  Confirmed by phone with Pak Andi, vendor ops, 2026-04-28  ', v_staff1, 'staff'
  );
  if v_res.status <> 'accepted' then
    raise exception 'assertion failed: expected the manual confirmation to reach accepted, got %', v_res.status;
  end if;
  if v_res.confirmation_method <> 'manual_with_evidence' then
    raise exception 'assertion failed: expected confirmation_method=manual_with_evidence, got %', v_res.confirmation_method;
  end if;
  if v_res.confirmation_evidence_file_id <> v_clean_file.id then
    raise exception 'assertion failed: expected the evidence file to be recorded on the reservation, got %', v_res.confirmation_evidence_file_id;
  end if;
  if v_res.confirmation_note <> 'Confirmed by phone with Pak Andi, vendor ops, 2026-04-28' then
    raise exception 'assertion failed: expected the note to be stored trimmed, got [%]', v_res.confirmation_note;
  end if;
  if v_res.confirmed_by_auth_user_id <> v_staff1 or v_res.confirmed_at is null then
    raise exception 'assertion failed: expected the confirming identity and timestamp to be recorded, got %/%', v_res.confirmed_by_auth_user_id, v_res.confirmed_at;
  end if;

  -- and the in-system route says what it always meant, rather than leaving it inferable from
  -- a null evidence column. Without this, "no evidence file" would be ambiguous between
  -- "the system watched it" and "somebody forgot to attach the document".
  v_other_res := app.accept_vendor_capacity_reservation(v_other_res.id, v_other_res.record_version, v_staff1, 'staff');
  if v_other_res.confirmation_method <> 'system_accept' or v_other_res.confirmation_evidence_file_id is not null then
    raise exception 'assertion failed: expected the in-system accept to stamp system_accept with no evidence file, got %/%', v_other_res.confirmation_method, v_other_res.confirmation_evidence_file_id;
  end if;

  -- The constraint, not just the RPC. A raw UPDATE is the case the RPC cannot police, and it
  -- is precisely the one worth policing: relabelling an in-system accept as an evidenced
  -- manual confirmation, with no evidence, is how the record would come to overstate itself.
  begin
    update app.vendor_capacity_reservations
    set confirmation_method = 'manual_with_evidence', confirmation_evidence_file_id = null
    where id = v_other_res.id;
    v_failed := false;
  exception when check_violation then
    v_failed := true;
    if sqlerrm not like '%vendor_capacity_reservations_manual_evidence_check%' then
      raise exception 'assertion failed: expected the manual-evidence CHECK to reject it, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a raw UPDATE claiming manual_with_evidence without evidence to be rejected by the CHECK constraint'; end if;

  -- and an unknown method is rejected outright rather than silently stored
  begin
    update app.vendor_capacity_reservations set confirmation_method = 'trust_me' where id = v_other_res.id;
    v_failed := false;
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then raise exception 'assertion failed: expected an unrecognised confirmation_method to be rejected'; end if;

  if not exists (
    select 1 from app.audit_logs
    where action = 'confirm_vendor_capacity_reservation_manually' and resource_id = v_res.id and result = 'success'
  ) then
    raise exception 'assertion failed: expected the manual confirmation to leave a real audit event';
  end if;
end $$;

\echo 'ALL PRC-262 db-test assertions passed.'
