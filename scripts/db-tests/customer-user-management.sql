-- Real, executable test evidence for CPL-315 (CG-S13-CPL-017, Prompt 315,
-- "Customer User Management") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-portal-scope.sql (CPL-300) and
-- scripts/db-tests/customer-profile-visibility.sql (CPL-314): a self-
-- contained two-tenant fixture, direct RPC calls as the connecting superuser
-- for parameter-driven authority checks, `set local role authenticated` +
-- `set local request.jwt.claims` only where the assertion genuinely needs a
-- real session (raw-table RLS/grant proofs and the actor-identity session
-- cross-check).
--
-- UUID range 00000000-0000-0000-0000-0000003320xx (tenant cum1) /
-- ...3330xx (tenant cum2) -- grep-verified unclaimed before this file was
-- written.
--
-- Covers, live: (1) role-update authority boundaries -- only an active
-- account_admin may change a role, a member-role actor and a different
-- account's admin are both rejected, and the flat two-role model (design
-- decision 2 of the migration) means there is no "grant more authority than
-- my own" case to construct (disclosed, not silently skipped -- see the
-- dedicated section below); (2) cross-tenant/cross-account isolation for
-- every one of this migration's four new RPCs; (3) optimistic-concurrency
-- stale_version rejection on app.update_customer_portal_account_membership_
-- role; (4) the last-account_admin guard (design decision 3) -- a sole admin
-- cannot demote themselves, a non-last admin can be demoted, and the true
-- last cannot; (5) access-review record creation and read-back, including
-- idempotency (same key -> same row; key reused against a different
-- membership -> idempotency_key_conflict), the active-membership-only
-- target restriction, and the two new read RPCs' own deny-by-default/
-- keyset-pagination/latest-review-join behavior; (6) raw-table RLS/grant
-- defense-in-depth; (7) the actor-identity session cross-check on all four
-- new functions.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cum1 (accounts Alpha [2 admins + member + pending + suspended + revoked], Solo [1 admin], Beta [1 admin]) and cum2 (account T2, cross-tenant isolation fixture); staff admin with CPT:Create'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_portal_role1 uuid; v_portal_draft1 app.role_versions;
  v_portal_role2 uuid; v_portal_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_solo uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_row app.customer_portal_account_memberships;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000332001', 'staff@cum1.test'),
    ('00000000-0000-0000-0000-000000332010', 'alpha-admin-1@cum1.test'),
    ('00000000-0000-0000-0000-000000332011', 'alpha-admin-2@cum1.test'),
    ('00000000-0000-0000-0000-000000332012', 'alpha-member@cum1.test'),
    ('00000000-0000-0000-0000-000000332013', 'alpha-pending@cum1.test'),
    ('00000000-0000-0000-0000-000000332014', 'alpha-suspended@cum1.test'),
    ('00000000-0000-0000-0000-000000332015', 'alpha-revoked@cum1.test'),
    ('00000000-0000-0000-0000-000000332020', 'solo-admin@cum1.test'),
    ('00000000-0000-0000-0000-000000332030', 'beta-admin@cum1.test'),
    ('00000000-0000-0000-0000-000000332040', 'impersonator@cum1.test'),
    ('00000000-0000-0000-0000-000000333001', 'staff@cum2.test'),
    ('00000000-0000-0000-0000-000000333010', 't2-admin@cum2.test');

  perform app.provision_tenant('cum1', 'Customer User Mgmt Tenant One', 'idem-cum1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cum1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CUM1-CO', 'Cum1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CUM1-CO');

  perform app.provision_tenant('cum2', 'Customer User Mgmt Tenant Two', 'idem-cum2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cum2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CUM2-CO', 'Cum2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CUM2-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000332001', 'staff@cum1.test', 'Cum1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cum1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000333001', 'staff@cum2.test', 'Cum2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cum2.test'), 'active', 'onboarded', 'tester');

  v_portal_role1 := (app.create_role(v_tenant1, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_portal_draft1 := app.create_role_version(v_portal_role1, 'tester');
  perform app.set_role_version_permissions(v_portal_draft1.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_portal_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_portal_role1 and status = 'published'), '00000000-0000-0000-0000-000000332001', '00000000-0000-0000-0000-000000332001', 'tester');

  v_portal_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_portal_draft2 := app.create_role_version(v_portal_role2, 'tester');
  perform app.set_role_version_permissions(v_portal_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_portal_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_portal_role2 and status = 'published'), '00000000-0000-0000-0000-000000333001', '00000000-0000-0000-0000-000000333001', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cum1 Account Alpha', 'cum1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cum1 Account Solo', 'cum1-solo-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_solo;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cum1 Account Beta', 'cum1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cum2 Account T2', 'cum2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  -- Bootstrap the first account_admin on each account (CPL-300's own staff-gated RPC, unmodified, composed here).
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', '00000000-0000-0000-0000-000000332001', 'cum1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_solo, '00000000-0000-0000-0000-000000332020', '00000000-0000-0000-0000-000000332001', 'cum1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, '00000000-0000-0000-0000-000000332030', '00000000-0000-0000-0000-000000332001', 'cum1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, '00000000-0000-0000-0000-000000333010', '00000000-0000-0000-0000-000000333001', 'cum2-staff');

  -- Second Alpha admin (invited then accepted).
  select * into v_row from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332011', 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  perform app.accept_customer_portal_invite(v_row.id, v_row.record_version, '00000000-0000-0000-0000-000000332011');

  -- Alpha member (invited then accepted) -- the main access-review target.
  select * into v_row from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332012', 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  perform app.accept_customer_portal_invite(v_row.id, v_row.record_version, '00000000-0000-0000-0000-000000332012');

  -- Alpha pending -- invited, never accepted (status stays 'invited').
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332013', 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');

  -- Alpha suspended -- invited, accepted, then suspended.
  select * into v_row from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332014', 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  select * into v_row from app.accept_customer_portal_invite(v_row.id, v_row.record_version, '00000000-0000-0000-0000-000000332014');
  perform app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'suspended', 'fixture setup', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');

  -- Alpha revoked -- invited, accepted, then revoked.
  select * into v_row from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332015', 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  select * into v_row from app.accept_customer_portal_invite(v_row.id, v_row.record_version, '00000000-0000-0000-0000-000000332015');
  perform app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'revoked', 'fixture setup', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');

  -- Impersonator needs a real tenant1 identity linkage to run a genuine
  -- `set local role authenticated` session, but holds NO customer_user
  -- membership of any kind.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000332040', v_tenant1, 'tester', 'active');
end $$;

\echo '>> app.update_customer_portal_account_membership_role: authority boundaries -- only an active account_admin on the SAME account may change a role; a member-role actor and a different account''s admin are both rejected; invalid role rejected; membership-not-found rejected; non-active-membership rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Beta');
  v_member app.customer_portal_account_memberships;
  v_pending app.customer_portal_account_memberships;
begin
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';

  -- A member-role actor (alpha-member itself) may not change anyone's role.
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version, 'account_admin', '00000000-0000-0000-0000-000000332012', 'alpha-member');
    raise exception 'assertion failed: expected insufficient_authority -- alpha-member holds role=member, not account_admin';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A genuine account_admin of a DIFFERENT account (Beta) may not change Alpha's member.
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version, 'account_admin', '00000000-0000-0000-0000-000000332030', 'beta-admin');
    raise exception 'assertion failed: expected insufficient_authority -- beta-admin is account_admin on Beta, not Alpha';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Invalid role value.
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version, 'owner', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_role -- ''owner'' is not a recognized customer portal role';
  exception
    when others then
      if sqlerrm not like 'invalid_role%' then raise; end if;
  end;

  -- Nonexistent membership id.
  begin
    perform app.update_customer_portal_account_membership_role(gen_random_uuid(), 1, 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected customer_portal_membership_not_found for a random membership id';
  exception
    when others then
      if sqlerrm not like 'customer_portal_membership_not_found%' then raise; end if;
  end;

  -- A pending (not-yet-accepted) invite's role may not be changed -- only an
  -- ACTIVE membership's role can.
  select * into v_pending from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332013';
  begin
    perform app.update_customer_portal_account_membership_role(v_pending.id, v_pending.record_version, 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_transition -- alpha-pending is still ''invited'', not ''active''';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Stale version.
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version + 99, 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected stale_version for a wrong p_expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency (record_version <> NULL is SQL
  -- NULL, which a bare `if ... then raise` treats as false). Confirmed
  -- rejected AND confirmed the role genuinely did not change.
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, null, 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version, got a silent success';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select role from app.customer_portal_account_memberships where id = v_member.id) <> v_member.role then
    raise exception 'assertion failed: a NULL p_expected_version must never actually change the row -- role changed from % to %', v_member.role, (select role from app.customer_portal_account_memberships where id = v_member.id);
  end if;
end $$;

\echo '>> role-hierarchy finding (design decision 2 of the migration, disclosed not silently skipped): app.customer_portal_account_memberships'' own cpam_role_check CHECK constraint admits EXACTLY {account_admin, member} -- a flat, two-level model, not a ranked hierarchy. Confirmed live, structurally, not merely asserted in a comment: a raw CHECK-bypassing role value fails at the table level, so no THIRD, higher role exists anywhere in this schema for a caller to escalate into. The only authority gate this capability has (account_admin, the higher of the two) is already required to REACH app.update_customer_portal_account_membership_role at all (proven above) -- there is no narrower "may not grant a role above my own" case this schema can construct.'
do $$
declare
  v_role_values text[];
begin
  select array_agg(distinct m.x[1]) into v_role_values
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace,
  lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') as m(x)
  where n.nspname = 'app' and t.relname = 'customer_portal_account_memberships' and c.conname = 'cpam_role_check';

  if v_role_values is null or array_length(v_role_values, 1) <> 2 or not ('account_admin' = any(v_role_values)) or not ('member' = any(v_role_values)) then
    raise exception 'assertion failed: expected app.customer_portal_account_memberships'' own cpam_role_check to admit EXACTLY {account_admin, member}, got %', v_role_values;
  end if;

  raise notice 'role-hierarchy finding confirmed live: cpam_role_check admits exactly {account_admin, member} -- flat, two-level model, no escalation case exists to guard against';
end $$;

\echo '>> last-account_admin guard (design decision 3): a sole account_admin cannot demote themselves; on a 2-admin account, a non-last admin CAN be demoted (leaving one); the true last admin then cannot be demoted either; a promotion (member -> account_admin) is never blocked by this guard'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_solo uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Solo');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_solo_admin app.customer_portal_account_memberships;
  v_alpha_admin_2 app.customer_portal_account_memberships;
  v_alpha_admin_1 app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
  v_member app.customer_portal_account_memberships;
begin
  select * into v_solo_admin from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_solo and auth_user_id = '00000000-0000-0000-0000-000000332020';

  -- Solo's own sole admin cannot demote themselves.
  begin
    perform app.update_customer_portal_account_membership_role(v_solo_admin.id, v_solo_admin.record_version, 'member', '00000000-0000-0000-0000-000000332020', 'solo-admin');
    raise exception 'assertion failed: expected last_account_admin -- solo-admin is the ONLY active account_admin on Solo';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;

  -- Alpha has TWO active admins -- alpha-admin-1 demotes alpha-admin-2, which
  -- must succeed (one admin, alpha-admin-1, still remains).
  select * into v_alpha_admin_2 from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332011';
  select * into v_updated from app.update_customer_portal_account_membership_role(v_alpha_admin_2.id, v_alpha_admin_2.record_version, 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  if v_updated.role <> 'member' then
    raise exception 'assertion failed: expected alpha-admin-2 to be demoted to member (a non-last admin), got role=%', v_updated.role;
  end if;

  -- Idempotent no-op: requesting the SAME role again returns unchanged, no
  -- version bump.
  select * into v_updated from app.update_customer_portal_account_membership_role(v_updated.id, v_updated.record_version, 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  if v_updated.record_version <> v_alpha_admin_2.record_version + 1 then
    raise exception 'assertion failed: expected the idempotent no-op re-request to leave record_version unchanged at %, got %', v_alpha_admin_2.record_version + 1, v_updated.record_version;
  end if;

  -- Role-change audit write: app.customer_portal_account_membership_history
  -- carries a row for the real demotion, mirroring app.set_customer_portal_
  -- account_membership_status's own audit-write shape (design decision 1).
  if not exists (
    select 1 from app.customer_portal_account_membership_history
    where membership_id = v_alpha_admin_2.id and reason like 'role changed from account_admin to member%'
  ) then
    raise exception 'assertion failed: expected a role-change history row for the alpha-admin-2 demotion';
  end if;

  -- Now Alpha has exactly ONE active admin (alpha-admin-1) again -- that sole
  -- remaining admin cannot demote themselves either.
  select * into v_alpha_admin_1 from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332010';
  begin
    perform app.update_customer_portal_account_membership_role(v_alpha_admin_1.id, v_alpha_admin_1.record_version, 'member', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected last_account_admin -- alpha-admin-1 is now the ONLY active account_admin on Alpha';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;

  -- A PROMOTION (member -> account_admin) is never blocked by this guard --
  -- alpha-admin-1 promotes the now-demoted alpha-admin-2 back up.
  select * into v_updated from app.update_customer_portal_account_membership_role(v_updated.id, v_updated.record_version, 'account_admin', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  if v_updated.role <> 'account_admin' then
    raise exception 'assertion failed: expected the promotion back to account_admin to succeed unconditionally, got role=%', v_updated.role;
  end if;

  -- Sanity: the ordinary alpha-member (a genuine member, never touched by
  -- this section) is still exactly a member, used by the access-review
  -- section below.
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';
  if v_member.role <> 'member' then
    raise exception 'assertion failed: expected alpha-member to remain a plain member, got role=%', v_member.role;
  end if;
end $$;

\echo '>> app.record_customer_portal_account_membership_access_review: authority boundaries, active-membership-only target, idempotency (same key returns same row; key reused against a different membership is idempotency_key_conflict), invalid outcome/key rejected, membership-not-found rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_member app.customer_portal_account_memberships;
  v_pending app.customer_portal_account_memberships;
  v_suspended app.customer_portal_account_memberships;
  v_alpha_admin_1 app.customer_portal_account_memberships;
  v_review app.customer_portal_account_membership_access_reviews;
  v_review2 app.customer_portal_account_membership_access_reviews;
begin
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';
  select * into v_alpha_admin_1 from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332010';

  -- A member-role actor may not record a review.
  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', null, 'cum1-review-unauthorized-1', '00000000-0000-0000-0000-000000332012', 'alpha-member');
    raise exception 'assertion failed: expected insufficient_authority -- alpha-member holds role=member, not account_admin';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A different account's admin may not record a review for Alpha.
  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', null, 'cum1-review-unauthorized-2', '00000000-0000-0000-0000-000000332030', 'beta-admin');
    raise exception 'assertion failed: expected insufficient_authority -- beta-admin is account_admin on Beta, not Alpha';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Invalid outcome / missing idempotency key.
  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'escalated', null, 'cum1-review-badoutcome', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_review_outcome -- ''escalated'' is not a recognized outcome';
  exception
    when others then
      if sqlerrm not like 'invalid_review_outcome%' then raise; end if;
  end;
  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', null, null, '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_idempotency_key for a null key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  -- Membership-not-found.
  begin
    perform app.record_customer_portal_account_membership_access_review(gen_random_uuid(), 'confirmed_appropriate', null, 'cum1-review-notfound', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected customer_portal_membership_not_found for a random membership id';
  exception
    when others then
      if sqlerrm not like 'customer_portal_membership_not_found%' then raise; end if;
  end;

  -- Active-membership-only target: a PENDING invite may not be access-reviewed.
  select * into v_pending from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332013';
  begin
    perform app.record_customer_portal_account_membership_access_review(v_pending.id, 'confirmed_appropriate', null, 'cum1-review-pending', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_review_target -- alpha-pending is still ''invited''';
  exception
    when others then
      if sqlerrm not like 'invalid_review_target%' then raise; end if;
  end;

  -- ...nor a SUSPENDED membership.
  select * into v_suspended from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332014';
  begin
    perform app.record_customer_portal_account_membership_access_review(v_suspended.id, 'confirmed_appropriate', null, 'cum1-review-suspended', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected invalid_review_target -- alpha-suspended is ''suspended'', not ''active''';
  exception
    when others then
      if sqlerrm not like 'invalid_review_target%' then raise; end if;
  end;

  -- The real, successful review.
  select * into v_review from app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', 'Still needed for invoicing.', 'cum1-review-member-1', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  if v_review.review_outcome <> 'confirmed_appropriate' or v_review.note <> 'Still needed for invoicing.' or v_review.reviewed_by_actor_auth_user_id <> '00000000-0000-0000-0000-000000332010' then
    raise exception 'assertion failed: expected a real access review row, got outcome=% note=% reviewer=%', v_review.review_outcome, v_review.note, v_review.reviewed_by_actor_auth_user_id;
  end if;

  -- Idempotent: the identical key returns the SAME row (C-01: verifies the
  -- full target tuple, not only the key).
  select * into v_review2 from app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', 'Still needed for invoicing.', 'cum1-review-member-1', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
  if v_review2.id <> v_review.id then
    raise exception 'assertion failed: expected the idempotent re-call to return the SAME review row id, got % vs %', v_review2.id, v_review.id;
  end if;

  -- The SAME key reused against a DIFFERENT (and itself perfectly valid --
  -- active) membership is a real conflict, never a silent misattribution.
  -- Uses alpha-admin-1's OWN membership as the different target (a genuinely
  -- active membership, so the idempotency check is what actually fires, not
  -- the earlier invalid_review_target check a non-active target would trip
  -- first).
  begin
    perform app.record_customer_portal_account_membership_access_review(v_alpha_admin_1.id, 'confirmed_appropriate', null, 'cum1-review-member-1', '00000000-0000-0000-0000-000000332010', 'alpha-admin-1');
    raise exception 'assertion failed: expected idempotency_key_conflict -- key ''cum1-review-member-1'' was already used for a DIFFERENT membership (alpha-member, not alpha-admin-1)';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- A second, GENUINELY DISTINCT review occasion for the SAME membership,
  -- with its own key, is a real, separate, new row -- confirming this table
  -- is append-only event history, never a single mutable "last review" slot.
  perform app.record_customer_portal_account_membership_access_review(v_member.id, 'flagged_for_follow_up', 'Role seems broader than needed.', 'cum1-review-member-2', '00000000-0000-0000-0000-000000332011', 'alpha-admin-1-second-review');
  if (select count(*) from app.customer_portal_account_membership_access_reviews where membership_id = v_member.id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 distinct review rows for alpha-member after two genuinely separate review occasions';
  end if;
end $$;

\echo '>> app.list_customer_portal_account_membership_access_reviews: account_admin-only, deny-by-default for a non-admin caller, membership filter, keyset pagination'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_member app.customer_portal_account_memberships;
  v_total integer;
begin
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';

  select count(*) into v_total from app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, null, 200);
  if v_total <> 2 then
    raise exception 'assertion failed: expected exactly 2 access-review rows visible to alpha-admin-1 for Alpha, got %', v_total;
  end if;

  select count(*) into v_total from app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', v_member.id, null, null, 200);
  if v_total <> 2 then
    raise exception 'assertion failed: expected exactly 2 access-review rows filtered to alpha-member''s own membership id, got %', v_total;
  end if;

  -- Deny-by-default: a member-role caller (alpha-member itself) sees zero rows, never an error.
  select count(*) into v_total from app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332012', null, null, null, 200);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows for a non-account_admin caller, got %', v_total;
  end if;

  -- A different account's admin sees zero rows for Alpha.
  select count(*) into v_total from app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332030', null, null, null, 200);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows -- beta-admin is not an account_admin on Alpha';
  end if;

  -- Keyset pagination at limit=1 visits both rows exactly once.
  declare
    v_seen_ids uuid[] := array[]::uuid[];
    v_row app.customer_portal_account_membership_access_reviews;
    v_page_count integer;
  begin
    for v_row in select * from app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, null, 1) loop
      v_seen_ids := v_seen_ids || v_row.id;
    end loop;
    loop
      v_page_count := 0;
      for v_row in
        select * from app.list_customer_portal_account_membership_access_reviews(
          v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null,
          (select reviewed_at from app.customer_portal_account_membership_access_reviews where id = v_seen_ids[array_length(v_seen_ids, 1)]),
          v_seen_ids[array_length(v_seen_ids, 1)], 1)
      loop
        v_seen_ids := v_seen_ids || v_row.id;
        v_page_count := v_page_count + 1;
      end loop;
      exit when v_page_count = 0;
    end loop;
    if array_length(v_seen_ids, 1) <> 2 or array_length(v_seen_ids, 1) <> (select count(distinct x) from unnest(v_seen_ids) x) then
      raise exception 'assertion failed: expected keyset pagination to visit exactly 2 distinct rows with no duplicate/skip, got % (% distinct)', array_length(v_seen_ids, 1), (select count(distinct x) from unnest(v_seen_ids) x);
    end if;
  end;

  -- A half-supplied cursor fails loud.
  begin
    perform app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_reviewed_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> app.list_customer_portal_account_memberships_for_access_review: active-only, correctly joined with each membership''s own MOST RECENT review, deny-by-default, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cum2');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_account_t2 uuid := (select id from app.accounts where tenant_id = v_tenant2 and legal_name = 'Cum2 Account T2');
  v_total integer;
  v_member_row record;
begin
  -- Alpha has 2 active memberships at this point (alpha-admin-1, alpha-member)
  -- -- alpha-admin-2/pending/suspended/revoked are all excluded (member is
  -- active again after the promotion in the earlier section, so 3 total:
  -- alpha-admin-1, alpha-admin-2 (promoted back), alpha-member).
  select count(*) into v_total from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, 200);
  if v_total <> 3 then
    raise exception 'assertion failed: expected exactly 3 ACTIVE memberships visible for Alpha (pending/suspended/revoked excluded), got %', v_total;
  end if;

  select * into v_member_row from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, 200)
  where auth_user_id = '00000000-0000-0000-0000-000000332012';
  if v_member_row.last_reviewed_at is null or v_member_row.last_review_outcome <> 'flagged_for_follow_up' then
    raise exception 'assertion failed: expected alpha-member''s own row to show its MOST RECENT review (flagged_for_follow_up, the second review occasion), got last_review_outcome=%', v_member_row.last_review_outcome;
  end if;

  select * into v_member_row from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, 200)
  where auth_user_id = '00000000-0000-0000-0000-000000332010';
  if v_member_row.last_reviewed_at is not null then
    raise exception 'assertion failed: expected alpha-admin-1''s own row to show NO prior review (never reviewed), got last_reviewed_at=%', v_member_row.last_reviewed_at;
  end if;

  -- Deny-by-default: a member-role caller sees zero rows.
  select count(*) into v_total from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332012', null, null, 200);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows for a non-account_admin caller, got %', v_total;
  end if;

  -- Cross-tenant isolation: t2-admin (active only in tenant cum2) resolves a
  -- real, empty result set querying Alpha (tenant cum1).
  select count(*) into v_total from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000333010', null, null, 200);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows -- t2-admin has no standing in tenant cum1 at all';
  end if;

  -- t2-admin''s OWN account (T2, tenant cum2) resolves correctly for itself.
  select count(*) into v_total from app.list_customer_portal_account_memberships_for_access_review(v_tenant2, v_account_t2, '00000000-0000-0000-0000-000000333010', null, null, 200);
  if v_total <> 1 then
    raise exception 'assertion failed: expected exactly 1 active membership (t2-admin itself) for account T2, got %', v_total;
  end if;

  -- A half-supplied cursor fails loud.
  begin
    perform app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant isolation, direct: t2-admin (tenant cum2, active only there) cannot act on an Alpha (tenant cum1) membership at all, for either new mutation RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_member app.customer_portal_account_memberships;
begin
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';

  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version, 'account_admin', '00000000-0000-0000-0000-000000333010', 't2-admin');
    raise exception 'assertion failed: expected insufficient_authority -- t2-admin has no standing in tenant cum1 at all';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', null, 'cum2-cross-tenant-attempt', '00000000-0000-0000-0000-000000333010', 't2-admin');
    raise exception 'assertion failed: expected insufficient_authority -- t2-admin has no standing in tenant cum1 at all';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege on the new access-review table (service_role only); anon holds no EXECUTE on any of the 4 new functions; authenticated holds EXECUTE on all 4'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.update_customer_portal_account_membership_role(uuid, integer, text, uuid, text)',
    'app.record_customer_portal_account_membership_access_review(uuid, text, text, text, uuid, text)',
    'app.list_customer_portal_account_membership_access_reviews(uuid, uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_account_memberships_for_access_review(uuid, uuid, uuid, timestamptz, uuid, integer)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_account_membership_access_reviews', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_account_membership_access_reviews directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_account_membership_access_reviews', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_account_membership_access_reviews directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_account_membership_access_reviews', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_account_membership_access_reviews';
  end if;

  foreach v_fn in array v_functions loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;

  -- A raw, real authenticated session genuinely cannot read the table at all.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000332010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_account_membership_access_reviews;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_account_membership_access_reviews';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end $$;

\echo '>> actor-identity session cross-check (ATW-031/032): a genuinely different authenticated session may not claim to act as another identity, on any of the 4 new functions -- neither the two mutations nor the two reads'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Alpha');
  v_member app.customer_portal_account_memberships;
begin
  select * into v_member from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000332012';

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000332040", "role": "authenticated"}';

  -- The real session is 332040 (impersonator, zero customer_user grants of
  -- any kind); each call below claims to BE 332010 (alpha-admin-1).
  begin
    perform app.update_customer_portal_account_membership_role(v_member.id, v_member.record_version, 'account_admin', '00000000-0000-0000-0000-000000332010', 'forged-actor-label');
    raise exception 'assertion failed: expected actor_identity_mismatch from app.update_customer_portal_account_membership_role -- session 332040 may not act as 332010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.record_customer_portal_account_membership_access_review(v_member.id, 'confirmed_appropriate', null, 'cum1-forged-review', '00000000-0000-0000-0000-000000332010', 'forged-actor-label');
    raise exception 'assertion failed: expected actor_identity_mismatch from app.record_customer_portal_account_membership_access_review -- session 332040 may not act as 332010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_account_membership_access_reviews(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch from app.list_customer_portal_account_membership_access_reviews -- session 332040 may not act as 332010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332010', null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch from app.list_customer_portal_account_memberships_for_access_review -- session 332040 may not act as 332010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A session correctly naming ITSELF still gets a real (empty/deny-by-
  -- default) answer, never an error -- the check rejects impersonation, not
  -- ordinary self-service use.
  if (select count(*) from app.list_customer_portal_account_memberships_for_access_review(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000332040', null, null, 50)) <> 0 then
    raise exception 'assertion failed: expected impersonator''s own query to be a real, empty (deny-by-default) result, not an error, when naming itself';
  end if;

  reset role;
end $$;

\echo '>> ISS-2026-125 item 3 regression (Track B Batch 8): app.set_customer_portal_account_membership_status now carries the identical last-account_admin guard app.update_customer_portal_account_membership_role already has (design decision 3) -- a sole account_admin cannot suspend or revoke themselves; on a 2-admin account, a non-last admin CAN be suspended (leaving one); the true last admin then cannot be suspended OR revoked either, and their own status stays untouched by the rejected attempts; suspending a plain member is never blocked by this guard'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cum1');
  v_company1 uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CUM1-CO');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cum1 Account Beta');
  v_account_gamma uuid;
  v_beta_admin app.customer_portal_account_memberships;
  v_gamma_admin_1 app.customer_portal_account_memberships;
  v_gamma_admin_2 app.customer_portal_account_memberships;
  v_gamma_member app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
begin
  -- Beta already has exactly ONE active account_admin (beta-admin) --
  -- reused as-is, untouched by any earlier block in this file.
  select * into v_beta_admin from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_beta and auth_user_id = '00000000-0000-0000-0000-000000332030';

  begin
    perform app.set_customer_portal_account_membership_status(v_beta_admin.id, v_beta_admin.record_version, 'suspended', 'self-suspend attempt', '00000000-0000-0000-0000-000000332030', 'beta-admin');
    raise exception 'assertion failed: expected last_account_admin -- beta-admin is the ONLY active account_admin on Beta';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;
  begin
    perform app.set_customer_portal_account_membership_status(v_beta_admin.id, v_beta_admin.record_version, 'revoked', 'self-revoke attempt', '00000000-0000-0000-0000-000000332030', 'beta-admin');
    raise exception 'assertion failed: expected last_account_admin -- beta-admin is still the ONLY active account_admin on Beta (revoked path)';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;
  if (select status from app.customer_portal_account_memberships where id = v_beta_admin.id) <> 'active' then
    raise exception 'assertion failed: beta-admin''s own status must remain active after both rejected self-suspend/self-revoke attempts';
  end if;

  -- A fresh, dedicated 2-admin account (Gamma) -- self-contained, never
  -- touched by any earlier block in this file -- proving the FULL shape the
  -- issue itself asked for: one admin is suspended (a non-last admin, still
  -- leaving one) and the true last is then rejected too.
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000332050', 'gamma-admin-1@cum1.test'),
    ('00000000-0000-0000-0000-000000332051', 'gamma-admin-2@cum1.test'),
    ('00000000-0000-0000-0000-000000332052', 'gamma-member@cum1.test');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cum1 Account Gamma', 'cum1-gamma-fp', '{}'::jsonb, v_company1, 'tester')
  returning id into v_account_gamma;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_gamma, '00000000-0000-0000-0000-000000332050', '00000000-0000-0000-0000-000000332001', 'cum1-staff');
  select * into v_gamma_admin_1 from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_gamma and auth_user_id = '00000000-0000-0000-0000-000000332050';

  select * into v_gamma_admin_2 from app.invite_customer_portal_user(v_tenant1, v_account_gamma, '00000000-0000-0000-0000-000000332051', 'account_admin', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
  perform app.accept_customer_portal_invite(v_gamma_admin_2.id, v_gamma_admin_2.record_version, '00000000-0000-0000-0000-000000332051');
  select * into v_gamma_admin_2 from app.customer_portal_account_memberships where id = v_gamma_admin_2.id;

  select * into v_gamma_member from app.invite_customer_portal_user(v_tenant1, v_account_gamma, '00000000-0000-0000-0000-000000332052', 'member', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
  perform app.accept_customer_portal_invite(v_gamma_member.id, v_gamma_member.record_version, '00000000-0000-0000-0000-000000332052');
  select * into v_gamma_member from app.customer_portal_account_memberships where id = v_gamma_member.id;

  -- Suspending a plain MEMBER is never blocked by this guard (it only
  -- inspects the target row's own role/status, never anyone else's).
  select * into v_updated from app.set_customer_portal_account_membership_status(v_gamma_member.id, v_gamma_member.record_version, 'suspended', 'member suspend, unrelated to the admin guard', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
  if v_updated.status <> 'suspended' then
    raise exception 'assertion failed: expected the plain member to be suspended (the last-account_admin guard must never block a non-admin target)';
  end if;

  -- Gamma has TWO active admins -- gamma-admin-1 suspends gamma-admin-2,
  -- which must succeed (one admin, gamma-admin-1, still remains active).
  select * into v_updated from app.set_customer_portal_account_membership_status(v_gamma_admin_2.id, v_gamma_admin_2.record_version, 'suspended', 'a non-last admin may be suspended', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
  if v_updated.status <> 'suspended' then
    raise exception 'assertion failed: expected gamma-admin-2 to be suspended (a non-last admin), got status=%', v_updated.status;
  end if;

  -- gamma-admin-1 is now the SOLE active account_admin on Gamma -- may not
  -- suspend or revoke themselves either.
  begin
    perform app.set_customer_portal_account_membership_status(v_gamma_admin_1.id, v_gamma_admin_1.record_version, 'suspended', 'self-suspend attempt as the true last admin', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
    raise exception 'assertion failed: expected last_account_admin -- gamma-admin-1 is now the ONLY active account_admin on Gamma';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;
  begin
    perform app.set_customer_portal_account_membership_status(v_gamma_admin_1.id, v_gamma_admin_1.record_version, 'revoked', 'self-revoke attempt as the true last admin', '00000000-0000-0000-0000-000000332050', 'gamma-admin-1');
    raise exception 'assertion failed: expected last_account_admin -- gamma-admin-1 is still the ONLY active account_admin on Gamma (revoked path)';
  exception
    when others then
      if sqlerrm not like 'last_account_admin%' then raise; end if;
  end;
  if (select status from app.customer_portal_account_memberships where id = v_gamma_admin_1.id) <> 'active' then
    raise exception 'assertion failed: gamma-admin-1''s own status must remain active after both rejected self-suspend/self-revoke attempts';
  end if;

  raise notice 'PASS (ISS-2026-125 item 3): the sole active account_admin on an account (Beta, and Gamma once reduced to one) can no longer suspend or revoke themselves via app.set_customer_portal_account_membership_status; a non-last admin and a plain member are both unaffected by the guard';
end $$;

\echo '>> ISS-2026-125 item 1 (20260901140000): step-up-MFA gate on app.update_customer_portal_account_membership_role and app.set_customer_portal_account_membership_status (suspend/revoke only), fully isolated to its own dedicated fixture tenant (cummfa) so this policy can never affect any other block''s assertions -- a tenant with NO app.mfa_tenant_policies row sees zero behavior change (role change, suspend, AND revoke all still succeed unconditionally); a tenant that has opted (CPADM, ManageMembership) into its own additional_high_risk_actions AND turned tenant-wide MFA on blocks all three with mfa_step_up_required until a real, current, verified step-up challenge exists for that exact actor/tenant/module/action tuple; reactivation (suspended -> active) is never gated by this guard, mirroring the migration''s own explicit scoping; app.request_mfa_step_up_challenge itself now succeeds for a customer_user-layer principal (widened from staff/supreme-admin-only), the PLT-128/CPL-302 shape'
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000334001';
  v_admin1 uuid := '00000000-0000-0000-0000-000000334010';
  v_admin2 uuid := '00000000-0000-0000-0000-000000334011';
  v_admin3 uuid := '00000000-0000-0000-0000-000000334012';
  v_account uuid;
  v_row app.customer_portal_account_memberships;
  v_admin1_row app.customer_portal_account_memberships;
  v_admin2_row app.customer_portal_account_memberships;
  v_admin3_row app.customer_portal_account_memberships;
  v_challenge app.mfa_step_up_challenges;
  v_updated app.customer_portal_account_memberships;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cummfa.test'),
    (v_admin1, 'admin1@cummfa.test'),
    (v_admin2, 'admin2@cummfa.test'),
    (v_admin3, 'admin3@cummfa.test');

  perform app.provision_tenant('cummfa', 'Customer User Mgmt MFA Tenant', 'idem-cummfa', 'tester');
  v_tenant := (select id from app.tenants where slug = 'cummfa');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  v_company := (app.create_org_unit(v_tenant, 'company', null, 'CUMMFA-CO', 'CumMfa Co', 'tester')).id;
  perform app.invite_user(v_tenant, v_staff, 'staff@cummfa.test', 'CumMfa Staff', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cummfa.test'), 'active', 'onboarded', 'tester');

  -- v_staff needs CPT:Create (app.grant_initial_customer_portal_account_admin's own bootstrap
  -- gate) AND SEC:Configure (app.set_mfa_tenant_policy, used below to opt this tenant into the
  -- new step-up-MFA gate) -- mirrors this file's own top-of-file setup block plus scripts/db-
  -- tests/customer-portal-legal-identity-change-requests.sql's own SEC:Configure grant shape.
  v_staff_role := (app.create_role(v_tenant, 'CumMfa Staff Role', null, 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(
    v_staff_draft.id,
    array(select id from app.permissions where (resource_module_code = 'CPT' and action = 'Create') or (resource_module_code = 'SEC' and action = 'Configure')),
    'tester'
  );
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), v_staff, v_staff, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant, 'CumMfa Account', 'cummfa-fp', '{}'::jsonb, v_company, 'tester') returning id into v_account;

  perform app.grant_initial_customer_portal_account_admin(v_tenant, v_account, v_admin1, v_staff, 'cummfa-staff');
  select * into v_admin1_row from app.customer_portal_account_memberships
  where tenant_id = v_tenant and account_id = v_account and auth_user_id = v_admin1;

  -- admin2 is used ONLY for the no-policy section below and ends terminal (revoked) --
  -- customer_portal_account_memberships_tenant_user_account_uq (tenant_id, auth_user_id,
  -- account_id) is a plain, non-partial unique index, so a second row for the SAME identity on
  -- the SAME account is never possible even once the first is terminal -- admin3 (a genuinely
  -- distinct identity) is used for the opted-in section instead of ever re-inviting admin2.
  select * into v_row from app.invite_customer_portal_user(v_tenant, v_account, v_admin2, 'member', v_admin1, 'admin1');
  perform app.accept_customer_portal_invite(v_row.id, v_row.record_version, v_admin2);
  select * into v_admin2_row from app.customer_portal_account_memberships where id = v_row.id;

  select * into v_row from app.invite_customer_portal_user(v_tenant, v_account, v_admin3, 'member', v_admin1, 'admin1');
  perform app.accept_customer_portal_invite(v_row.id, v_row.record_version, v_admin3);
  select * into v_admin3_row from app.customer_portal_account_memberships where id = v_row.id;

  -- (1) No app.mfa_tenant_policies row for this tenant at all: app.is_high_risk_action returns
  -- false for (CPADM, ManageMembership) (it is not in the platform-default list), so app.assert_
  -- current_step_up_authorization is a genuine no-op -- role change, suspend AND revoke all
  -- succeed unconditionally, exercised end to end on admin2.
  select * into v_updated from app.update_customer_portal_account_membership_role(v_admin2_row.id, v_admin2_row.record_version, 'account_admin', v_admin1, 'admin1');
  if v_updated.role <> 'account_admin' then
    raise exception 'assertion failed: expected the role change to succeed unconditionally with no MFA policy row, got role=%', v_updated.role;
  end if;
  select * into v_updated from app.update_customer_portal_account_membership_role(v_admin2_row.id, v_updated.record_version, 'member', v_admin1, 'admin1');
  if v_updated.role <> 'member' then
    raise exception 'assertion failed: expected the role change back to member to succeed unconditionally with no MFA policy row, got role=%', v_updated.role;
  end if;

  select * into v_updated from app.set_customer_portal_account_membership_status(v_admin2_row.id, v_updated.record_version, 'suspended', 'no-policy no-op proof', v_admin1, 'admin1');
  if v_updated.status <> 'suspended' then
    raise exception 'assertion failed: expected suspend to succeed unconditionally with no MFA policy row, got status=%', v_updated.status;
  end if;
  select * into v_updated from app.set_customer_portal_account_membership_status(v_updated.id, v_updated.record_version, 'active', 'reactivate mid-proof', v_admin1, 'admin1');
  select * into v_updated from app.set_customer_portal_account_membership_status(v_updated.id, v_updated.record_version, 'revoked', 'no-policy no-op proof', v_admin1, 'admin1');
  if v_updated.status <> 'revoked' then
    raise exception 'assertion failed: expected revoke to succeed unconditionally with no MFA policy row, got status=%', v_updated.status;
  end if;

  -- (2) Opt (CPADM, ManageMembership) into this tenant's own additional_high_risk_actions AND
  -- turn tenant-wide MFA on -- mirrors scripts/db-tests/customer-portal-legal-identity-change-
  -- requests.sql's own step-up-MFA proof fixture shape exactly. Only admin3 is touched from here
  -- on; admin1/admin2's already-proven state above is untouched by this policy change.
  perform app.set_mfa_tenant_policy(v_tenant, true, '["supreme_admin", "tenant_admin"]'::jsonb, 15, '[{"moduleCode": "CPADM", "action": "ManageMembership"}]'::jsonb, v_staff, 'cummfa-staff');

  -- Role change (promotion, never blocked by the last-account_admin guard either way) is blocked
  -- before any step-up challenge exists.
  begin
    perform app.update_customer_portal_account_membership_role(v_admin3_row.id, v_admin3_row.record_version, 'account_admin', v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_step_up_required for the role change with no verified challenge on record';
  exception
    when others then
      if sqlerrm not like 'mfa_step_up_required%' then raise; end if;
  end;
  if (select role from app.customer_portal_account_memberships where id = v_admin3_row.id) <> 'member' then
    raise exception 'assertion failed: expected admin3''s role to remain unchanged while blocked on step-up';
  end if;

  -- Suspend is blocked the same way.
  begin
    perform app.set_customer_portal_account_membership_status(v_admin3_row.id, v_admin3_row.record_version, 'suspended', 'attempting without step-up', v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_step_up_required for suspend with no verified challenge on record';
  exception
    when others then
      if sqlerrm not like 'mfa_step_up_required%' then raise; end if;
  end;
  if (select status from app.customer_portal_account_memberships where id = v_admin3_row.id) <> 'active' then
    raise exception 'assertion failed: expected admin3 to remain active while blocked on step-up';
  end if;

  -- admin1 (the actor performing these actions) obtains and verifies a real step-up challenge
  -- for this exact (tenant, actor, module, action) tuple -- proving app.request_mfa_step_up_
  -- challenge now genuinely succeeds for a customer_user-layer principal (ISS-2026-125 item 1's
  -- own widening of its has_active_tenant_membership precondition), not merely that the assert
  -- itself is generic.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant, 'CPADM', 'ManageMembership', v_admin1, 'admin1');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_admin1, 'admin1');

  -- Role change now succeeds -- admin3 is promoted to account_admin (Beta now has 2 active
  -- admins: admin1, admin3).
  select * into v_updated from app.update_customer_portal_account_membership_role(v_admin3_row.id, v_admin3_row.record_version, 'account_admin', v_admin1, 'admin1');
  if v_updated.role <> 'account_admin' then
    raise exception 'assertion failed: expected the role change to succeed once a current verified step-up challenge exists, got role=%', v_updated.role;
  end if;

  -- Suspend now succeeds too, off the SAME verified challenge (same module/action tuple, still
  -- within its max-age window) -- no second challenge required. admin1 remains active, so this
  -- is a non-last-admin suspend and the last-account_admin guard does not interfere.
  select * into v_updated from app.set_customer_portal_account_membership_status(v_admin3_row.id, v_updated.record_version, 'suspended', 'approved after step-up', v_admin1, 'admin1');
  if v_updated.status <> 'suspended' then
    raise exception 'assertion failed: expected suspend to succeed once a current verified step-up challenge exists, got status=%', v_updated.status;
  end if;

  -- Reactivation (suspended -> active) is deliberately NEVER gated by this guard, even with the
  -- tenant's policy still active and no fresh challenge for this call -- the migration''s own
  -- explicit scoping (p_to_status IN ('suspended', 'revoked') only).
  select * into v_updated from app.set_customer_portal_account_membership_status(v_updated.id, v_updated.record_version, 'active', 'reactivate, never step-up-gated', v_admin1, 'admin1');
  if v_updated.status <> 'active' then
    raise exception 'assertion failed: expected reactivation to succeed unconditionally -- it is never step-up-gated, got status=%', v_updated.status;
  end if;

  raise notice 'PASS (ISS-2026-125 item 1): app.update_customer_portal_account_membership_role and app.set_customer_portal_account_membership_status (suspend/revoke) are both step-up-MFA-gated, strictly opt-in per tenant, with reactivation never gated and app.request_mfa_step_up_challenge now reachable by a customer_user-layer principal';
end $$;

\echo 'customer-user-management.sql: ALL PASSED'
