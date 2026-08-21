-- Real, executable test evidence for CPL-300 (CG-S13-CPL-002, Prompt 300,
-- "Customer User Scope") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/
-- advanced-tms-customer-inventory-access.sql (two-tenant fixture, direct RPC
-- calls as the connecting superuser for parameter-driven authority checks,
-- `set local role authenticated` + `set local request.jwt.claims` only where the
-- assertion genuinely needs a real session -- raw-table RLS/grant proofs and the
-- actor-identity session cross-check).
--
-- UUID range 00000000-0000-0000-0000-0000003000xx (grep-verified unclaimed
-- before this file was written). Tenant slugs cps1/cps2.
--
-- Covers, live: (1) a customer_user with an active membership on account A
-- resolves scope including A; (2) the SAME identity has zero scope for an
-- unrelated account B in the same tenant with no membership row; (3) a revoked
-- membership immediately stops resolving (no caching); (4) cross-tenant
-- isolation; (5) only an active account_admin on account A can invite/suspend/
-- revoke members of A -- a member-role or wrong-account actor is rejected; (6)
-- idempotent invite; (7) optimistic-concurrency stale_version rejection on
-- accept/status-change; (8) forged/copied auth_user_id on accept is rejected.
-- Also: app.resolve_customer_account_scope's own UNION of the legacy
-- customer_account_ref marker and the new grant table (design decision 4);
-- app.get_customer_portal_scope_context's deny-by-default/empty-set behavior
-- and column projection; app.grant_initial_customer_portal_account_admin's own
-- staff/CPT:Create gate and idempotency; app.list_customer_portal_account_
-- memberships' keyset pagination and account_admin-only gate; raw-table
-- RLS/grant defense-in-depth (authenticated holds nothing on either new table
-- directly); the actor-identity session cross-check (assert_actor_is_session_
-- identity) rejects a genuinely different session claiming another actor's id
-- -- on the write RPCs AND (Tier C security-rls/correctness-spec review fix,
-- Finding 1, CRITICAL) on every read RPC (app.resolve_customer_account_scope/
-- app.get_customer_portal_scope_context/app.list_customer_portal_account_
-- memberships/app.actor_is_active_customer_portal_account_admin), which
-- previously trusted their identity parameter with no cross-check at all --
-- a live-verified IDOR both independent review lenses reproduced. Also (Tier
-- C review fix, Finding 2, CRITICAL): legacy-consumer propagation -- an
-- invited-but-not-accepted identity holds no legacy app.resolve_customer_
-- owner_account_scope/app.actor_holds_customer_user_layer access, and
-- suspend/revoke/reactivate through app.set_customer_portal_account_
-- membership_status now drives that same legacy app.principal_memberships
-- row so already-shipped ATW-023/portal-entry consumers lose/regain access
-- in step, not only this migration's own new resolver. Also (Finding 3):
-- app.grant_initial_customer_portal_account_admin's CPT:Create authority
-- check now runs before the account-existence check, closing a cross-tenant
-- account-id existence oracle previously reachable by any authenticated
-- identity, not only tenant staff.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cps1 (accounts Alpha/Beta/Gamma/Fresh) and cps2 (account T2); staff admins with a Portal Admin role (CPT:Create); customer identities for account_admin/member/pending-invite/legacy-only/cross-tenant scenarios'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_portal_role1 uuid; v_portal_draft1 app.role_versions;
  v_portal_role2 uuid; v_portal_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_account_fresh uuid;
  v_account_t2 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000300001', 'supreme@cps.test'),
    ('00000000-0000-0000-0000-000000300002', 'admin@cps1.test'),
    ('00000000-0000-0000-0000-000000300003', 'admin@cps2.test'),
    ('00000000-0000-0000-0000-000000300004', 'noauthority-staff@cps1.test'),
    ('00000000-0000-0000-0000-000000300010', 'alpha-admin@cps1.test'),
    ('00000000-0000-0000-0000-000000300011', 'alpha-member@cps1.test'),
    ('00000000-0000-0000-0000-000000300012', 'alpha-pending@cps1.test'),
    ('00000000-0000-0000-0000-000000300020', 'beta-admin@cps1.test'),
    ('00000000-0000-0000-0000-000000300030', 'gamma-legacy@cps1.test'),
    ('00000000-0000-0000-0000-000000300040', 't2-admin@cps2.test'),
    ('00000000-0000-0000-0000-000000300050', 'impersonator@cps1.test'),
    ('00000000-0000-0000-0000-000000300060', 'fresh-admin@cps1.test'),
    ('00000000-0000-0000-0000-000000300061', 'fresh-member@cps1.test');

  perform app.provision_tenant('cps1', 'Customer Portal Scope Tenant One', 'idem-cps1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cps1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CPS1-CO', 'Cps1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CPS1-CO');

  perform app.provision_tenant('cps2', 'Customer Portal Scope Tenant Two', 'idem-cps2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cps2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CPS2-CO', 'Cps2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CPS2-CO');

  -- Staff: tenant admins get a "Portal Admin" role granting CPT:Create (the
  -- bootstrap gate, design decision 6) -- one staff member per tenant has no
  -- role at all (300004), used to prove the bootstrap RPC's own RBAC gate is
  -- real, not a rubber stamp.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000300002', 'admin@cps1.test', 'Cps1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@cps1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000300004', 'noauthority-staff@cps1.test', 'No Authority Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauthority-staff@cps1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000300003', 'admin@cps2.test', 'Cps2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@cps2.test'), 'active', 'onboarded', 'tester');

  v_portal_role1 := (app.create_role(v_tenant1, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_portal_draft1 := app.create_role_version(v_portal_role1, 'tester');
  perform app.set_role_version_permissions(v_portal_draft1.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_portal_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_portal_role1 and status = 'published'), '00000000-0000-0000-0000-000000300002', '00000000-0000-0000-0000-000000300002', 'tester');

  v_portal_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_portal_draft2 := app.create_role_version(v_portal_role2, 'tester');
  perform app.set_role_version_permissions(v_portal_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_portal_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_portal_role2 and status = 'published'), '00000000-0000-0000-0000-000000300003', '00000000-0000-0000-0000-000000300003', 'tester');

  -- app.accounts: Alpha/Beta/Gamma/Fresh in cps1, T2 in cps2 (direct fixture
  -- insert, bypassing the full lead->prospect->quotation->convert Commercial
  -- pipeline, mirrors advanced-tms-customer-inventory-access.sql's own
  -- established convention).
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cps1 Account Alpha', 'cps1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cps1 Account Beta', 'cps1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cps1 Account Gamma', 'cps1-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cps1 Account Fresh', 'cps1-fresh-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_fresh;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cps2 Account T2', 'cps2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  -- Gamma is a LEGACY-ONLY grant (pre-dates this migration's own table --
  -- mirrors how ATW-016/ATW-023 era callers granted a customer_user layer
  -- directly): link_auth_identity + grant_principal_membership called
  -- directly, never through this migration's own invite RPC, and NO row is
  -- ever created in app.customer_portal_account_memberships for it.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000300030', v_tenant1, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000300030', 'customer_user', v_tenant1, v_account_gamma::text, 'tester');

  -- T2-admin's own legacy marker in tenant2 (cross-tenant isolation fixture).
  perform app.link_auth_identity('00000000-0000-0000-0000-000000300040', v_tenant2, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000300040', 'customer_user', v_tenant2, v_account_t2::text, 'tester');

  -- 300050 (impersonator) needs a real tenant1 identity linkage to run a
  -- genuine `set local role authenticated` session later, but is granted NO
  -- customer_user membership of any kind -- it exists purely to prove a
  -- forged actor id is rejected by the session cross-check.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000300050', v_tenant1, 'tester', 'active');
end $$;

\echo '>> app.grant_initial_customer_portal_account_admin: staff/CPT:Create bootstrap -- success seeds the first account_admin; idempotent re-call returns the same row; a staff actor without CPT:Create is rejected; a cross-tenant account id is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cps2');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_account_t2 uuid := (select id from app.accounts where tenant_id = v_tenant2 and legal_name = 'Cps2 Account T2');
  v_row app.customer_portal_account_memberships;
  v_row2 app.customer_portal_account_memberships;
  v_count integer;
begin
  select * into v_row from app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', '00000000-0000-0000-0000-000000300002', 'cps1-admin');
  if v_row.role <> 'account_admin' or v_row.status <> 'active' or v_row.account_id <> v_account_alpha then
    raise exception 'assertion failed: expected the first Alpha account_admin seeded active, got role=% status=% account_id=%', v_row.role, v_row.status, v_row.account_id;
  end if;

  -- Idempotent: same identity/account, called again -- returns the SAME row,
  -- no duplicate.
  select * into v_row2 from app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', '00000000-0000-0000-0000-000000300002', 'cps1-admin');
  if v_row2.id <> v_row.id then
    raise exception 'assertion failed: expected the idempotent re-seed to return the SAME row id, got % vs %', v_row2.id, v_row.id;
  end if;
  select count(*) into v_count from app.customer_portal_account_memberships where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000300010';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row after two bootstrap calls for the same identity+account, got %', v_count;
  end if;

  -- Staff without CPT:Create is rejected.
  begin
    perform app.grant_initial_customer_portal_account_admin(v_tenant1, (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Fresh'), '00000000-0000-0000-0000-000000300020', '00000000-0000-0000-0000-000000300004', 'no-authority-staff');
    raise exception 'assertion failed: expected insufficient_authority -- staff actor 300004 holds no CPT:Create role';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A cross-tenant account id (real account, wrong tenant) is rejected as
  -- account_not_found, never silently accepted.
  begin
    perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_t2, '00000000-0000-0000-0000-000000300010', '00000000-0000-0000-0000-000000300002', 'cps1-admin');
    raise exception 'assertion failed: expected account_not_found -- v_account_t2 belongs to tenant2, not tenant1';
  exception
    when others then
      if sqlerrm not like 'account_not_found%' then raise; end if;
  end;

  -- Tier C security-rls review fix (Finding 3): a staff actor with NO
  -- CPT:Create authority gets insufficient_authority for a totally
  -- NONEXISTENT account id too -- not account_not_found. Before this fix, the
  -- account-existence check ran BEFORE the authority check, so the two
  -- distinct errors let ANY authenticated identity -- not just staff of this
  -- tenant -- use this RPC as a cross-tenant account-id existence oracle.
  -- Authority is now checked first, so an unauthorized caller learns nothing
  -- about whether the id is real.
  begin
    perform app.grant_initial_customer_portal_account_admin(v_tenant1, gen_random_uuid(), '00000000-0000-0000-0000-000000300021', '00000000-0000-0000-0000-000000300004', 'no-authority-staff');
    raise exception 'assertion failed: expected insufficient_authority for a no-authority actor even against a nonexistent account id -- got no error';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Seed T2's own account_admin too, for the cross-tenant isolation section below.
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, '00000000-0000-0000-0000-000000300040', '00000000-0000-0000-0000-000000300003', 'cps2-admin');
end $$;

\echo '>> app.invite_customer_portal_user: self-service invite by an active account_admin; a member-role actor is rejected; an account_admin of a DIFFERENT account is rejected; idempotent re-invite returns the same row; invalid role is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Beta');
  v_account_fresh uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Fresh');
  v_row app.customer_portal_account_memberships;
  v_row2 app.customer_portal_account_memberships;
  v_pending app.customer_portal_account_memberships;
  v_count integer;
begin
  -- alpha-admin (300010) invites alpha-member (300011) as 'member'.
  select * into v_row from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300011', 'member', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_row.role <> 'member' or v_row.status <> 'invited' then
    raise exception 'assertion failed: expected alpha-member invited with role=member status=invited, got role=% status=%', v_row.role, v_row.status;
  end if;

  -- Idempotent: the identical invite call again returns the SAME row, no duplicate.
  select * into v_row2 from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300011', 'member', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_row2.id <> v_row.id then
    raise exception 'assertion failed: expected the idempotent re-invite to return the SAME row id, got % vs %', v_row2.id, v_row.id;
  end if;
  select count(*) into v_count from app.customer_portal_account_memberships where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000300011';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row after two identical invite calls, got %', v_count;
  end if;

  -- A separate pending (never-accepted) invite, used by the forged-accept
  -- section below.
  select * into v_pending from app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300012', 'member', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_pending.status <> 'invited' then
    raise exception 'assertion failed: expected alpha-pending to remain invited';
  end if;

  -- Invalid role is rejected.
  begin
    perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300050', 'owner', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected invalid_role -- ''owner'' is not a recognized customer portal role';
  exception
    when others then
      if sqlerrm not like 'invalid_role%' then raise; end if;
  end;

  -- alpha-member (role=member, active) may not invite -- only account_admin may.
  perform app.accept_customer_portal_invite(v_row.id, v_row.record_version, '00000000-0000-0000-0000-000000300011');
  begin
    perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300050', 'member', '00000000-0000-0000-0000-000000300011', 'alpha-member');
    raise exception 'assertion failed: expected insufficient_authority -- alpha-member holds role=member, not account_admin';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Seed Beta's own account_admin (for the wrong-account rejection case), then
  -- prove beta-admin cannot invite/manage Alpha's members even though they
  -- ARE a genuine account_admin -- just on a different account.
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, '00000000-0000-0000-0000-000000300020', '00000000-0000-0000-0000-000000300002', 'cps1-admin');
  begin
    perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300050', 'member', '00000000-0000-0000-0000-000000300020', 'beta-admin');
    raise exception 'assertion failed: expected insufficient_authority -- beta-admin is account_admin on Beta, not Alpha';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Sanity: v_account_fresh exists and currently has zero memberships (used
  -- later); referenced here only to keep the fixture var used.
  perform v_account_fresh;
end $$;

\echo '>> app.accept_customer_portal_invite: forged/copied auth_user_id is rejected (only the invited identity may accept); stale_version is rejected; a second accept on an already-active membership is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_pending app.customer_portal_account_memberships;
  v_row app.customer_portal_account_memberships;
begin
  select * into v_pending from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000300012';

  -- Forged/copied auth_user_id: alpha-member (a real, different, already-active
  -- identity) tries to accept alpha-pending's own invite by id.
  begin
    perform app.accept_customer_portal_invite(v_pending.id, v_pending.record_version, '00000000-0000-0000-0000-000000300011');
    raise exception 'assertion failed: expected insufficient_authority -- only the invited identity (300012) may accept this invite, not 300011';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Stale version: a wrong expected_version is rejected even for the genuinely
  -- invited identity.
  begin
    perform app.accept_customer_portal_invite(v_pending.id, v_pending.record_version + 99, '00000000-0000-0000-0000-000000300012');
    raise exception 'assertion failed: expected stale_version for a wrong p_expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- The real accept, with the correct version, by the genuinely invited identity.
  select * into v_row from app.accept_customer_portal_invite(v_pending.id, v_pending.record_version, '00000000-0000-0000-0000-000000300012');
  if v_row.status <> 'active' or v_row.accepted_at is null then
    raise exception 'assertion failed: expected alpha-pending to be active with accepted_at set after a genuine accept, got status=% accepted_at=%', v_row.status, v_row.accepted_at;
  end if;

  -- A second accept attempt (now already active, version has moved on) is
  -- rejected -- both because it is stale (using the OLD version) and because
  -- invited->active is the only transition this RPC ever performs.
  begin
    perform app.accept_customer_portal_invite(v_pending.id, v_pending.record_version, '00000000-0000-0000-0000-000000300012');
    raise exception 'assertion failed: expected stale_version -- the row''s version already advanced when it was first accepted';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> app.resolve_customer_account_scope: (1) active membership on A resolves scope including A; (2) the SAME identity has zero scope for an unrelated account with no membership row; (4) cross-tenant isolation; the legacy-marker/new-table UNION (design decision 4) -- legacy-only, new-table-only, and both, with no duplicate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cps2');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_account_fresh uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Fresh');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Gamma');
  v_scope uuid[];
begin
  -- (1) alpha-admin's scope includes Alpha.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300010', v_tenant1);
  if not (v_account_alpha = any (v_scope)) then
    raise exception 'assertion failed: expected alpha-admin''s scope to include Account Alpha, got %', v_scope;
  end if;

  -- (2) the SAME identity has zero scope for Account Fresh -- no membership
  -- row exists there for alpha-admin.
  if v_account_fresh = any (v_scope) then
    raise exception 'assertion failed: expected alpha-admin''s scope to EXCLUDE Account Fresh (no membership row), got %', v_scope;
  end if;

  -- (4) cross-tenant isolation: alpha-admin is active only in tenant1 -- queried
  -- against tenant2, scope must be a real, empty array, never NULL.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300010', v_tenant2);
  if v_scope is null or array_length(v_scope, 1) is not null then
    raise exception 'assertion failed: expected alpha-admin to resolve a REAL EMPTY array in tenant2 (cross-tenant isolation), got %', v_scope;
  end if;

  -- Legacy-only: gamma-legacy (300030) holds ONLY a pre-existing app.
  -- principal_memberships.customer_account_ref marker, no
  -- app.customer_portal_account_memberships row at all -- still resolves via
  -- the UNION's legacy half (design decision 4, app.resolve_customer_owner_
  -- account_scope reused by direct call, never re-derived).
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300030', v_tenant1);
  if v_scope <> array[v_account_gamma] then
    raise exception 'assertion failed: expected gamma-legacy''s scope to be exactly [Gamma] via the legacy marker alone, got %', v_scope;
  end if;
  if exists (select 1 from app.customer_portal_account_memberships where auth_user_id = '00000000-0000-0000-0000-000000300030') then
    raise exception 'assertion failed: gamma-legacy must hold NO row in the new grant table -- this is the legacy-only fixture';
  end if;

  -- New-table-only: alpha-member (300011) holds no legacy customer_account_ref
  -- pointing anywhere other than Alpha (its own app.principal_memberships
  -- row, granted by app.accept_customer_portal_invite on its earlier accept
  -- above, carries account_id::text -- Alpha's own id, not a second,
  -- unrelated legacy value) -- and resolves via the new table's own active row.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300011', v_tenant1);
  if v_scope <> array[v_account_alpha] then
    raise exception 'assertion failed: expected alpha-member''s scope to be exactly [Alpha], got %', v_scope;
  end if;

  -- Both: alpha-admin (300010) now holds a legacy-shaped principal_memberships
  -- row (created by app.grant_initial_customer_portal_account_admin's own
  -- composition of app.grant_principal_membership, pointing at Alpha) AND an
  -- active new-table row for the SAME Alpha account -- the UNION must not
  -- double-count or duplicate.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300010', v_tenant1);
  if array_length(v_scope, 1) <> 1 or v_scope <> array[v_account_alpha] then
    raise exception 'assertion failed: expected alpha-admin''s scope to be exactly [Alpha] with no duplicate even though both the legacy marker and the new table point at the same account, got %', v_scope;
  end if;
end $$;

\echo '>> revocation takes immediate effect (3): a revoked membership stops resolving scope on its very next check, no caching'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_membership app.customer_portal_account_memberships;
  v_scope uuid[];
begin
  select * into v_membership from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000300011';

  -- Before revoke: alpha-member's scope includes Alpha.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300011', v_tenant1);
  if not (v_account_alpha = any (v_scope)) then
    raise exception 'assertion failed: expected alpha-member''s scope to include Alpha BEFORE revocation';
  end if;

  perform app.set_customer_portal_account_membership_status(v_membership.id, v_membership.record_version, 'revoked', 'membership revocation test', '00000000-0000-0000-0000-000000300010', 'alpha-admin');

  -- Immediately after, same session, no caching: scope no longer includes Alpha.
  v_scope := app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300011', v_tenant1);
  if v_account_alpha = any (v_scope) then
    raise exception 'assertion failed: expected alpha-member''s scope to EXCLUDE Alpha immediately after revocation, got %', v_scope;
  end if;

  -- Revoked is terminal: no further transition is permitted, not even back to active.
  begin
    perform app.set_customer_portal_account_membership_status(v_membership.id, v_membership.record_version + 1, 'active', 'attempted un-revoke', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected revoked -> active to be rejected (revoked is terminal)';
  exception
    when others then
      if sqlerrm not like 'invalid_cpam_transition%' then raise; end if;
  end;
end $$;

\echo '>> Tier C security-rls review fix (Finding 2): legacy consumer propagation. An invited-but-not-yet-accepted identity holds NO legacy app.resolve_customer_owner_account_scope/app.actor_holds_customer_user_layer access (the live-verified ATW-023/portal-entry bypass); accepting grants it; suspend strips it immediately and reactivate restores it; revoke strips it permanently -- all on the SAME legacy primitives ATW-023 (WMS/inventory) and this migration''s own portal-entry guard actually call, not merely on this migration''s own new resolver'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_fresh uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Fresh');
  v_pending app.customer_portal_account_memberships;
  v_row app.customer_portal_account_memberships;
begin
  -- fresh-admin (300060) bootstrapped as Fresh's own first account_admin, so
  -- it can self-service-invite fresh-member (300061) below.
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_fresh, '00000000-0000-0000-0000-000000300060', '00000000-0000-0000-0000-000000300002', 'cps1-admin');

  select * into v_pending from app.invite_customer_portal_user(v_tenant1, v_account_fresh, '00000000-0000-0000-0000-000000300061', 'member', '00000000-0000-0000-0000-000000300060', 'fresh-admin');

  -- Invited, not yet accepted: NO legacy access at all -- this is the exact
  -- bypass both review lenses live-reproduced (invite used to grant the
  -- legacy app.principal_memberships row immediately, before acceptance).
  if app.resolve_customer_owner_account_scope('00000000-0000-0000-0000-000000300061', v_tenant1) <> array[]::uuid[] then
    raise exception 'assertion failed: expected fresh-member to hold ZERO legacy scope while still invited (not yet accepted)';
  end if;
  if app.actor_holds_customer_user_layer(v_tenant1, '00000000-0000-0000-0000-000000300061') then
    raise exception 'assertion failed: expected fresh-member to NOT hold the customer_user layer while still invited (not yet accepted) -- portal-entry guard would wrongly admit them';
  end if;

  -- Accept: legacy access now appears.
  select * into v_row from app.accept_customer_portal_invite(v_pending.id, v_pending.record_version, '00000000-0000-0000-0000-000000300061');
  if not (v_account_fresh = any (app.resolve_customer_owner_account_scope('00000000-0000-0000-0000-000000300061', v_tenant1))) then
    raise exception 'assertion failed: expected fresh-member''s legacy scope to include Fresh immediately after accepting';
  end if;
  if not app.actor_holds_customer_user_layer(v_tenant1, '00000000-0000-0000-0000-000000300061') then
    raise exception 'assertion failed: expected fresh-member to hold the customer_user layer immediately after accepting';
  end if;

  -- Suspend: legacy access is stripped immediately, not merely on this
  -- migration's own new resolver.
  select * into v_row from app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'suspended', 'legacy propagation test', '00000000-0000-0000-0000-000000300060', 'fresh-admin');
  if app.resolve_customer_owner_account_scope('00000000-0000-0000-0000-000000300061', v_tenant1) <> array[]::uuid[] then
    raise exception 'assertion failed: expected fresh-member''s legacy scope to be EMPTY immediately after suspension';
  end if;
  if app.actor_holds_customer_user_layer(v_tenant1, '00000000-0000-0000-0000-000000300061') then
    raise exception 'assertion failed: expected fresh-member to NOT hold the customer_user layer immediately after suspension';
  end if;

  -- Reactivate: legacy access is restored.
  select * into v_row from app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'active', 'legacy propagation test reactivate', '00000000-0000-0000-0000-000000300060', 'fresh-admin');
  if not (v_account_fresh = any (app.resolve_customer_owner_account_scope('00000000-0000-0000-0000-000000300061', v_tenant1))) then
    raise exception 'assertion failed: expected fresh-member''s legacy scope to include Fresh again immediately after reactivation';
  end if;
  if not app.actor_holds_customer_user_layer(v_tenant1, '00000000-0000-0000-0000-000000300061') then
    raise exception 'assertion failed: expected fresh-member to hold the customer_user layer again immediately after reactivation';
  end if;

  -- Revoke: legacy access is stripped, permanently.
  perform app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'revoked', 'legacy propagation test revoke', '00000000-0000-0000-0000-000000300060', 'fresh-admin');
  if app.resolve_customer_owner_account_scope('00000000-0000-0000-0000-000000300061', v_tenant1) <> array[]::uuid[] then
    raise exception 'assertion failed: expected fresh-member''s legacy scope to be EMPTY immediately after revocation';
  end if;
  if app.actor_holds_customer_user_layer(v_tenant1, '00000000-0000-0000-0000-000000300061') then
    raise exception 'assertion failed: expected fresh-member to NOT hold the customer_user layer after revocation';
  end if;
end $$;

\echo '>> app.set_customer_portal_account_membership_status: mandatory non-empty reason for suspend/revoke; suspend/reactivate round-trip; wrong-account actor rejected; stale_version rejected; an admin may not force invited->active through this RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Beta');
  v_pending app.customer_portal_account_memberships;
  v_pending_member app.customer_portal_account_memberships;
  v_row app.customer_portal_account_memberships;
begin
  select * into v_pending from app.customer_portal_account_memberships
  where tenant_id = v_tenant1 and account_id = v_account_alpha and auth_user_id = '00000000-0000-0000-0000-000000300012';

  -- Mandatory non-empty reason for suspend.
  begin
    perform app.set_customer_portal_account_membership_status(v_pending.id, v_pending.record_version, 'suspended', '', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected reason_required for an empty-string reason on suspend';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  begin
    perform app.set_customer_portal_account_membership_status(v_pending.id, v_pending.record_version, 'suspended', null, '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected reason_required for a null reason on suspend';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Suspend/reactivate round-trip (300012 was accepted -- now status=active --
  -- in the app.accept_customer_portal_invite block above; active -> suspended
  -- is a valid transition per the matrix).
  select * into v_row from app.set_customer_portal_account_membership_status(v_pending.id, v_pending.record_version, 'suspended', 'temporary hold pending verification', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_row.status <> 'suspended' or v_row.suspended_reason <> 'temporary hold pending verification' or v_row.suspended_by <> 'alpha-admin' then
    raise exception 'assertion failed: expected suspended with reason/actor recorded, got status=% reason=% by=%', v_row.status, v_row.suspended_reason, v_row.suspended_by;
  end if;

  select * into v_row from app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'active', 'verification complete', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_row.status <> 'active' then
    raise exception 'assertion failed: expected suspended -> active (reactivate) to succeed, got status=%', v_row.status;
  end if;

  -- Wrong-account actor: beta-admin (a genuine account_admin, just on a
  -- different account) may not suspend an Alpha member.
  begin
    perform app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version, 'suspended', 'unauthorized attempt', '00000000-0000-0000-0000-000000300020', 'beta-admin');
    raise exception 'assertion failed: expected insufficient_authority -- beta-admin is not an account_admin on Alpha';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Stale version.
  begin
    perform app.set_customer_portal_account_membership_status(v_row.id, v_row.record_version + 99, 'suspended', 'stale attempt', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a wrong p_expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- An admin may not force invited -> active through this RPC -- only
  -- app.accept_customer_portal_invite, by the invited identity themselves, may.
  select * into v_pending_member from app.invite_customer_portal_user(v_tenant1, v_account_beta, '00000000-0000-0000-0000-000000300030', 'member', '00000000-0000-0000-0000-000000300020', 'beta-admin');
  begin
    perform app.set_customer_portal_account_membership_status(v_pending_member.id, v_pending_member.record_version, 'active', 'admin forced activation', '00000000-0000-0000-0000-000000300020', 'beta-admin');
    raise exception 'assertion failed: expected accept_required -- an account_admin may not force invited -> active through this RPC';
  exception
    when others then
      if sqlerrm not like 'accept_required%' then raise; end if;
  end;
end $$;

\echo '>> app.get_customer_portal_scope_context: correct rows/role/is_primary/account_name; empty set (never an error) for an actor with no customer_user layer at all; never exposes internal-only app.accounts columns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_count integer;
  v_row record;
begin
  select count(*) into v_count from app.get_customer_portal_scope_context('00000000-0000-0000-0000-000000300010', v_tenant1);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 scope-context row for alpha-admin (Alpha only), got %', v_count;
  end if;

  select * into v_row from app.get_customer_portal_scope_context('00000000-0000-0000-0000-000000300010', v_tenant1);
  if v_row.account_id <> v_account_alpha or v_row.account_name <> 'Cps1 Account Alpha' or v_row.role <> 'account_admin' or v_row.is_primary <> true then
    raise exception 'assertion failed: expected account_id=%% account_name=Cps1 Account Alpha role=account_admin is_primary=true, got account_id=% account_name=% role=% is_primary=%', v_row.account_id, v_row.account_name, v_row.role, v_row.is_primary;
  end if;

  -- Deny-by-default/anti-enumeration: a staff identity (300002, tenant_admin
  -- layer, no customer_user layer at all) gets an EMPTY set, never an error.
  select count(*) into v_count from app.get_customer_portal_scope_context('00000000-0000-0000-0000-000000300002', v_tenant1);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero scope-context rows for a non-customer_user staff actor, got %', v_count;
  end if;

  -- Column shape: exactly 4 output columns (account_id, account_name, role,
  -- is_primary) -- no internal-only app.accounts column (normalized_legal_
  -- name/duplicate_fingerprint/owner_user_id/org_unit_id) leaks through.
  if (
    select count(*) from information_schema.parameters
    where specific_schema = 'app' and specific_name = (
      select specific_name from information_schema.routines
      where routine_schema = 'app' and routine_name = 'get_customer_portal_scope_context' limit 1
    ) and parameter_mode = 'OUT'
  ) <> 4 then
    raise exception 'assertion failed: expected app.get_customer_portal_scope_context to return exactly 4 OUT columns';
  end if;
end $$;

\echo '>> app.list_customer_portal_account_memberships: account_admin sees the full membership list for their own account, keyset-paginated; a non-admin caller gets an empty result, never an error; cross-account isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_total integer;
  v_page1 app.customer_portal_account_memberships[];
  v_row app.customer_portal_account_memberships;
  v_page2_count integer;
  v_seen_ids uuid[] := array[]::uuid[];
begin
  select count(*) into v_total from app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', null, null, 200);
  if v_total < 3 then
    raise exception 'assertion failed: expected at least 3 Alpha membership rows (admin + member + pending), got %', v_total;
  end if;

  -- Keyset pagination: page through with p_limit=1, confirm it terminates and
  -- visits every row exactly once (no OFFSET, no duplicate, no skip).
  for v_row in select * from app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', null, null, 1) loop
    v_seen_ids := v_seen_ids || v_row.id;
  end loop;
  while array_length(v_seen_ids, 1) < v_total loop
    v_page2_count := 0;
    for v_row in
      select * from app.list_customer_portal_account_memberships(
        v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010',
        (select updated_at from app.customer_portal_account_memberships where id = v_seen_ids[array_length(v_seen_ids, 1)]),
        v_seen_ids[array_length(v_seen_ids, 1)], 1)
    loop
      v_seen_ids := v_seen_ids || v_row.id;
      v_page2_count := v_page2_count + 1;
    end loop;
    exit when v_page2_count = 0;
  end loop;
  if array_length(v_seen_ids, 1) <> v_total or array_length(v_seen_ids, 1) <> (select count(distinct x) from unnest(v_seen_ids) x) then
    raise exception 'assertion failed: expected keyset pagination to visit exactly % distinct rows with no duplicate/skip, got % (% distinct)', v_total, array_length(v_seen_ids, 1), (select count(distinct x) from unnest(v_seen_ids) x);
  end if;

  -- A non-admin caller (alpha-pending, role=member, currently suspended from
  -- an earlier section) gets an EMPTY result, never an error.
  select count(*) into v_total from app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300012', null, null, 50);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows for a non-account_admin caller, got %', v_total;
  end if;

  -- Cross-account isolation: beta-admin may not list Alpha's members.
  select count(*) into v_total from app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300020', null, null, 50);
  if v_total <> 0 then
    raise exception 'assertion failed: expected zero rows -- beta-admin is not an account_admin on Alpha';
  end if;

  -- A half-supplied cursor fails loud rather than silently returning an empty page.
  begin
    perform app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege on either new table (service_role only, design decision 3); anon holds no EXECUTE on any new function; authenticated holds EXECUTE on all 8'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.resolve_customer_account_scope(uuid, uuid)',
    'app.actor_is_active_customer_portal_account_admin(uuid, uuid, uuid)',
    'app.get_customer_portal_scope_context(uuid, uuid)',
    'app.invite_customer_portal_user(uuid, uuid, uuid, text, uuid, text)',
    'app.accept_customer_portal_invite(uuid, integer, uuid)',
    'app.set_customer_portal_account_membership_status(uuid, integer, text, text, uuid, text)',
    'app.list_customer_portal_account_memberships(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.grant_initial_customer_portal_account_admin(uuid, uuid, uuid, uuid, text)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_account_memberships', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_account_memberships directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_account_memberships', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_account_memberships directly';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_account_membership_history', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_account_membership_history directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_account_memberships', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_account_memberships';
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

  -- A raw, real authenticated session (not merely the grant-privilege check
  -- above) genuinely cannot read the table at all.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000300010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_account_memberships;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_account_memberships';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity (impersonation prevention, ATW-031/032)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_fresh uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Fresh');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000300050", "role": "authenticated"}';
  begin
    -- The real session is 300050 (impersonator); this call claims to act as
    -- 300010 (alpha-admin) -- must be rejected before any authority/business
    -- logic even runs.
    perform app.invite_customer_portal_user(v_tenant1, v_account_fresh, '00000000-0000-0000-0000-000000300050', 'member', '00000000-0000-0000-0000-000000300010', 'forged-actor-label');
    raise exception 'assertion failed: expected actor_identity_mismatch -- session 300050 may not act as 300010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end $$;

\echo '>> Tier C security-rls/correctness-spec review fix (Finding 1, CRITICAL): the actor-identity session cross-check also covers the READ RPCs, not only the write RPCs above. Live-verified IDOR both lenses independently reproduced: before this fix, a genuinely different authenticated session (300050, zero relationship to Alpha) could pass alpha-admin''s own uuid (300010) as the identity/actor parameter to app.resolve_customer_account_scope/app.get_customer_portal_scope_context/app.list_customer_portal_account_memberships and receive alpha-admin''s full cross-account scope, role, and Alpha''s entire membership roster -- no membership, session, or token of alpha-admin''s own required, only their raw uuid'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000300050", "role": "authenticated"}';

  -- The real session is 300050 (impersonator, zero customer_user grants of
  -- any kind anywhere); each call below claims to BE 300010 (alpha-admin) --
  -- must be rejected before any scope/authority logic even runs, never
  -- silently returning alpha-admin's own data to the real caller.
  begin
    perform app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300010', v_tenant1);
    raise exception 'assertion failed: expected actor_identity_mismatch from app.resolve_customer_account_scope -- session 300050 may not resolve 300010''s scope';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_scope_context('00000000-0000-0000-0000-000000300010', v_tenant1);
    raise exception 'assertion failed: expected actor_identity_mismatch from app.get_customer_portal_scope_context -- session 300050 may not resolve 300010''s scope context';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_account_memberships(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010', null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch from app.list_customer_portal_account_memberships -- session 300050 may not claim to be 300010, Alpha''s own account_admin';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.actor_is_active_customer_portal_account_admin(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000000300010');
    raise exception 'assertion failed: expected actor_identity_mismatch from app.actor_is_active_customer_portal_account_admin -- session 300050 may not claim to be 300010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A session correctly naming ITSELF still gets a real (empty) answer, never
  -- an error -- the check rejects impersonation, not ordinary self-service use.
  if app.resolve_customer_account_scope('00000000-0000-0000-0000-000000300050', v_tenant1) <> array[]::uuid[] then
    raise exception 'assertion failed: expected impersonator''s own scope to be a real empty array, not an error, when naming itself';
  end if;

  reset role;
end $$;

\echo '>> ATW-032 authority-surface sweep readiness (informational cross-check mirrored from scripts/db-tests/rbac-enforcement.sql -- the authoritative gate is that file itself): every new SECURITY DEFINER function granted to authenticated either matches the sweep''s own base regex directly or is covered by this migration''s own companion edit to that file'
do $$
begin
  raise notice 'customer-portal-scope.sql: structural coverage complete -- scripts/db-tests/rbac-enforcement.sql is the authoritative ATW-032 gate for this migration''s own new functions.';
end $$;

\echo '>> CPL-324 Tier C fix regression: optimistic-concurrency NULL-bypass on app.accept_customer_portal_invite and app.set_customer_portal_account_membership_status -- a NULL p_expected_version is rejected with stale_version, the row proven byte-for-byte unchanged, then the real version succeeds (20260801260000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cps1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cps1 Account Alpha');
  v_invitee uuid := '00000000-0000-0000-0000-000000300090';
  v_before app.customer_portal_account_memberships;
  v_after app.customer_portal_account_memberships;
begin
  insert into auth.users (id, email) values (v_invitee, 'null-bypass-invitee@cps1.test');

  -- accept_customer_portal_invite: fresh invited row, own identity.
  select * into v_before from app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_invitee, 'member', '00000000-0000-0000-0000-000000300010', 'alpha-admin');

  begin
    perform app.accept_customer_portal_invite(v_before.id, null, v_invitee);
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on accept_customer_portal_invite';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_after from app.customer_portal_account_memberships where id = v_before.id;
  if v_after.status <> v_before.status or v_after.record_version <> v_before.record_version then
    raise exception 'assertion failed: expected the invite row to be byte-for-byte unchanged after a rejected NULL-bypass accept attempt, got %', v_after;
  end if;

  v_after := app.accept_customer_portal_invite(v_before.id, v_before.record_version, v_invitee);
  if v_after.status <> 'active' then
    raise exception 'assertion failed: expected the real-version accept call to succeed, got %', v_after;
  end if;

  -- set_customer_portal_account_membership_status: suspend the just-accepted row.
  begin
    perform app.set_customer_portal_account_membership_status(v_after.id, null, 'suspended', 'null-bypass probe', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on set_customer_portal_account_membership_status';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  if not exists (select 1 from app.customer_portal_account_memberships where id = v_after.id and status = 'active' and record_version = v_after.record_version) then
    raise exception 'assertion failed: expected the membership row to be byte-for-byte unchanged after a rejected NULL-bypass status-change attempt';
  end if;

  v_after := app.set_customer_portal_account_membership_status(v_after.id, v_after.record_version, 'suspended', 'real-version probe', '00000000-0000-0000-0000-000000300010', 'alpha-admin');
  if v_after.status <> 'suspended' then
    raise exception 'assertion failed: expected the real-version status-change call to succeed, got %', v_after;
  end if;
end $$;

\echo 'customer-portal-scope.sql: ALL PASSED'
