-- Real, executable test evidence for CPL-325 (CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.
--
-- Regression coverage for supabase/migrations/20260801280000_harden_
-- customer_portal_loyalty_ledger_supreme_admin_override.sql -- this
-- checkpoint's own explicit ruling on ISS-2026-130 (docs/runtime/
-- KNOWN_ISSUES.md) and the 06_RLS_RBAC_WORKSTREAM.md sec.8/sec.13
-- tension: option (a), build the FIN-204-mirrored Supreme-Admin-override
-- mechanism now, scoped to Phase 8's own 5 append_only_ledger-family
-- tables (app.loyalty_earning_events, app.loyalty_point_ledger_entries,
-- app.loyalty_benefit_entitlement_events, app.loyalty_reward_stock_
-- reservations, app.loyalty_redemption_events).
--
-- Extended (ISS-2026-137, Track B Batch 4, loyalty-approval-authority) by
-- supabase/migrations/20260828010000_harden_customer_portal_loyalty_tier_
-- movements_supreme_admin_override.sql to a 6th table, app.loyalty_
-- account_tier_movements -- named in ISS-2026-130's own ORIGINAL four-table
-- list but omitted from CPL-325's own 5-table remediation scope. Block (c3)
-- and the (d)/(e) grant-check array below now also cover this 6th table.
--
-- UUID range 00000000-0000-0000-0000-000003992xxx, grep-verified unclaimed
-- against every other file in this directory before writing this fixture.
--
-- Covers, live, for representative tables (app.loyalty_point_ledger_entries
-- and app.loyalty_reward_stock_reservations -- the shared trigger function
-- is identical across all 5, verified once per distinct code path): (a) a
-- raw UPDATE/DELETE with no actor context (auth.uid() = NULL) is blocked;
-- (b) an ordinary tenant staff actor (LYL:Configure, holding NO
-- supreme_admin membership) is ALSO blocked -- RPD-022 is Supreme-Admin-
-- only, never any elevated tenant role; (c) a genuine Supreme Admin (a
-- live global supreme_admin principal membership) CAN mutate, and the
-- mutation is captured to app.audit_logs with correct before/after values
-- and actor identity; (d) `authenticated` still holds ZERO UPDATE/DELETE
-- grant on any of the 5 tables (unchanged baseline); (e) `service_role` now
-- DOES hold the additive UPDATE/DELETE grant this migration adds (without
-- it, a real deployment's Supreme Admin has no path to exercise the
-- override at all).

\set ON_ERROR_STOP on

\echo '>> setup: tenant sao1, a Loyalty Manager staff actor (LYL:Configure, no supreme_admin), a genuine global Supreme Admin identity, a customer loyalty account with a seeded point-ledger adjustment and a reward stock reservation'
do $$
declare
  v_tenant1 uuid;
  v_company1 uuid;
  v_account1 uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000003992001';
  v_supreme uuid := '00000000-0000-0000-0000-000003992099';
  v_role1 uuid; v_draft1 app.role_versions;
  v_program1 uuid;
  v_lacct1 uuid;
  v_reward app.loyalty_rewards;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'mgr1@sao1.test'),
    (v_supreme, 'supreme@sao1.test');

  perform app.provision_tenant('sao1', 'Supreme Admin Override Test Tenant', 'idem-sao1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'sao1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'SAO1-CO', 'Sao1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'SAO1-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'mgr1@sao1.test', 'Sao1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@sao1.test'), 'active', 'onboarded', 'tester');
  v_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_draft1 := app.create_role_version(v_role1, 'tester');
  perform app.set_role_version_permissions(v_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View','Create','Edit','Configure')), 'tester');
  perform app.publish_role_version(v_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role1 and status='published'), v_manager1, v_manager1, 'tester');

  -- Genuine global supreme_admin principal membership (tenant_id/customer_account_ref
  -- both null -- the layer-scope-shape constraint, PLT-108).
  perform app.link_auth_identity(v_supreme, v_tenant1, 'tester', 'active');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Sao1 Account', 'sao1-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account1;

  perform app.create_loyalty_program(v_tenant1, 'Sao1 Program', null, v_manager1, 'manager1');
  v_program1 := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Sao1 Program');
  perform app.update_loyalty_program_status(v_tenant1, v_program1, 1, 'active', v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account1, v_program1, v_manager1, 'manager1');
  v_lacct1 := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account1);

  perform app.post_loyalty_point_ledger_entry(v_tenant1, v_lacct1, 'adjustment', 50, null, 'manual_adjustment', null, 'sao1-entry-1', 'seed for supreme admin override test', null, v_manager1, 'manager1', 1);

  v_reward := app.create_loyalty_reward_draft(v_tenant1, v_program1, 'Sao1 Reward', 'physical_item', 'seed reward', null, null, 0, 5, 5, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, null, v_manager1, 'manager1');
  insert into app.loyalty_reward_stock_reservations (tenant_id, reward_id, quantity, reason, created_by, idempotency_key)
  values (v_tenant1, v_reward.id, 1, 'seed', 'tester', 'sao1-resv-1');

  -- ISS-2026-137 fixture: a real published tier definition, then a direct
  -- fixture INSERT into app.loyalty_account_tier_movements (mirrors this
  -- same file's own already-established "direct table INSERT, no RPC
  -- exists to create one standalone" fixture shape used above for
  -- app.loyalty_reward_stock_reservations -- no dedicated single-movement
  -- RPC exists; production movements are a side effect of the tier
  -- evaluation engine, out of scope to stand up for this narrow trigger
  -- regression).
  declare
    v_tier app.loyalty_tier_definitions;
  begin
    v_tier := app.create_loyalty_tier_definition(v_tenant1, v_program1, 'Silver', 1, 'lifetime_points', 0, '{}'::jsonb, 365, v_manager1, 'manager1');
    v_tier := app.publish_loyalty_tier_definition(v_tenant1, v_tier.id, v_tier.record_version, null, v_manager1, 'manager1');

    insert into app.loyalty_account_tier_movements (
      tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type,
      tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by
    ) values (
      v_tenant1, v_lacct1, null, v_tier.id, 'initial',
      v_tier.id, '{"seed": true}'::jsonb, 'seed for supreme admin override test', clock_timestamp() + interval '365 days', 'tester'
    );
  end;
end $$;

\echo '>> (a) raw UPDATE/DELETE with no actor context (auth.uid() = NULL) is BLOCKED on app.loyalty_point_ledger_entries'
do $$
begin
  -- Explicit, not inherited: never assume the previous block's own cleanup
  -- left request.jwt.claims unset -- a PL/pgSQL nested begin/exception
  -- block (as every "blocked" check below uses) establishes an implicit
  -- SAVEPOINT, and a local set_config() value set AFTER that savepoint can
  -- otherwise survive as a literal empty string past this block's own
  -- commit (a real, confirmed psql/PL-pgSQL local-GUC quirk under a caught
  -- exception -- unrelated to the product code under test). Every block in
  -- this file therefore sets its OWN required identity context (a real
  -- actor, or explicitly 'null') as its first statement, never relying on
  -- a previous block's trailing reset.
  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.loyalty_point_ledger_entries set amount = 999 where idempotency_key = 'sao1-entry-1';
    raise exception 'assertion failed: expected UPDATE with no actor context to be blocked';
  exception when others then
    if sqlerrm not like 'loyalty_ledger_append_only_immutable%' then raise; end if;
  end;
  begin
    delete from app.loyalty_point_ledger_entries where idempotency_key = 'sao1-entry-1';
    raise exception 'assertion failed: expected DELETE with no actor context to be blocked';
  exception when others then
    if sqlerrm not like 'loyalty_ledger_append_only_immutable%' then raise; end if;
  end;
end $$;

\echo '>> (b) an ORDINARY tenant staff actor (Loyalty Manager, LYL:Configure -- NOT supreme_admin) is ALSO blocked'
do $$
declare
  v_manager1 uuid := '00000000-0000-0000-0000-000003992001';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager1::text, 'role', 'authenticated')::text, true);
  begin
    update app.loyalty_point_ledger_entries set amount = 999 where idempotency_key = 'sao1-entry-1';
    raise exception 'assertion failed: expected tenant staff (non-supreme) UPDATE to be blocked';
  exception when others then
    if sqlerrm not like 'loyalty_ledger_append_only_immutable%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', 'null', true);
end $$;

\echo '>> (c) a genuine Supreme Admin CAN mutate app.loyalty_point_ledger_entries, and the mutation is captured to app.audit_logs with correct before/after values and actor identity'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000003992099';
  v_row app.loyalty_point_ledger_entries;
  v_audit app.audit_logs;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_supreme::text, 'role', 'authenticated')::text, true);

  update app.loyalty_point_ledger_entries set amount = 999, reason = 'corrected by supreme admin' where idempotency_key = 'sao1-entry-1' returning * into v_row;
  if v_row.amount <> 999 then
    raise exception 'assertion failed: expected Supreme Admin UPDATE to succeed with amount=999, got %', v_row.amount;
  end if;

  select * into v_audit from app.audit_logs where resource_type = 'app.loyalty_point_ledger_entries' and resource_id = v_row.id and action = 'update_append_only_loyalty_ledger_row';
  if v_audit.id is null then
    raise exception 'assertion failed: expected exactly 1 audit_logs row for the Supreme Admin UPDATE';
  end if;
  if (v_audit.before_value->>'amount')::numeric <> 50 or (v_audit.after_value->>'amount')::numeric <> 999 then
    raise exception 'assertion failed: expected audit before=50/after=999, got before=% after=%', v_audit.before_value->>'amount', v_audit.after_value->>'amount';
  end if;
  if v_audit.actor_auth_user_id <> v_supreme then
    raise exception 'assertion failed: expected audit actor_auth_user_id=%, got %', v_supreme, v_audit.actor_auth_user_id;
  end if;

  delete from app.loyalty_point_ledger_entries where idempotency_key = 'sao1-entry-1';
  if exists (select 1 from app.loyalty_point_ledger_entries where idempotency_key = 'sao1-entry-1') then
    raise exception 'assertion failed: expected Supreme Admin DELETE to succeed';
  end if;
  if not exists (select 1 from app.audit_logs where resource_type = 'app.loyalty_point_ledger_entries' and action = 'delete_append_only_loyalty_ledger_row') then
    raise exception 'assertion failed: expected exactly 1 audit_logs row for the Supreme Admin DELETE';
  end if;

  perform set_config('request.jwt.claims', 'null', true);
end $$;

\echo '>> (c2) same three-part proof (blocked / blocked / Supreme-Admin-allowed-and-audited) on a SECOND table -- app.loyalty_reward_stock_reservations -- confirms the shared trigger function generalizes correctly across tables, not a loyalty_point_ledger_entries-only special case'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000003992099';
begin
  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.loyalty_reward_stock_reservations set quantity = 2 where idempotency_key = 'sao1-resv-1';
    raise exception 'assertion failed: expected normal-context UPDATE to be blocked';
  exception when others then
    if sqlerrm not like 'loyalty_ledger_append_only_immutable%' then raise; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_supreme::text, 'role', 'authenticated')::text, true);
  update app.loyalty_reward_stock_reservations set quantity = 2 where idempotency_key = 'sao1-resv-1';
  if not exists (select 1 from app.loyalty_reward_stock_reservations where idempotency_key = 'sao1-resv-1' and quantity = 2) then
    raise exception 'assertion failed: expected Supreme Admin UPDATE on app.loyalty_reward_stock_reservations to succeed';
  end if;
  if not exists (select 1 from app.audit_logs where resource_type = 'app.loyalty_reward_stock_reservations' and action = 'update_append_only_loyalty_ledger_row') then
    raise exception 'assertion failed: expected an audit_logs row for the Supreme Admin UPDATE on app.loyalty_reward_stock_reservations';
  end if;
  perform set_config('request.jwt.claims', 'null', true);
end $$;

\echo '>> (c3) ISS-2026-137 regression: same three-part proof (blocked / blocked / Supreme-Admin-allowed-and-audited) on the 6th table, app.loyalty_account_tier_movements -- confirms the ISS-2026-130 fix extends correctly to the table it originally omitted'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000003992099';
  v_movement_id uuid := (select id from app.loyalty_account_tier_movements where reason = 'seed for supreme admin override test');
begin
  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.loyalty_account_tier_movements set reason = 'tampered' where id = v_movement_id;
    raise exception 'assertion failed: expected normal-context UPDATE to be blocked';
  exception when others then
    if sqlerrm not like 'loyalty_ledger_append_only_immutable%' then raise; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_supreme::text, 'role', 'authenticated')::text, true);
  update app.loyalty_account_tier_movements set reason = 'corrected by supreme admin' where id = v_movement_id;
  if not exists (select 1 from app.loyalty_account_tier_movements where id = v_movement_id and reason = 'corrected by supreme admin') then
    raise exception 'assertion failed: expected Supreme Admin UPDATE on app.loyalty_account_tier_movements to succeed';
  end if;
  if not exists (select 1 from app.audit_logs where resource_type = 'app.loyalty_account_tier_movements' and resource_id = v_movement_id and action = 'update_append_only_loyalty_ledger_row') then
    raise exception 'assertion failed: expected an audit_logs row for the Supreme Admin UPDATE on app.loyalty_account_tier_movements';
  end if;
  perform set_config('request.jwt.claims', 'null', true);
end $$;

\echo '>> (d) authenticated holds ZERO UPDATE/DELETE grant on any of the 6 tables (unchanged baseline); (e) service_role now DOES hold the additive UPDATE/DELETE grant on all 6, including app.loyalty_account_tier_movements (ISS-2026-137)'
do $$
declare
  v_has_grant boolean;
  t text;
begin
  foreach t in array array['loyalty_earning_events','loyalty_point_ledger_entries','loyalty_benefit_entitlement_events','loyalty_reward_stock_reservations','loyalty_redemption_events','loyalty_account_tier_movements'] loop
    select exists (
      select 1 from information_schema.role_table_grants
      where table_schema = 'app' and table_name = t and grantee = 'authenticated' and privilege_type in ('UPDATE','DELETE')
    ) into v_has_grant;
    if v_has_grant then
      raise exception 'assertion failed: authenticated holds UPDATE/DELETE grant on app.%, expected none', t;
    end if;

    select bool_and(g) into v_has_grant from (
      select exists (
        select 1 from information_schema.role_table_grants
        where table_schema = 'app' and table_name = t and grantee = 'service_role' and privilege_type = p
      ) as g
      from unnest(array['UPDATE','DELETE']) as p
    ) x;
    if not v_has_grant then
      raise exception 'assertion failed: service_role is missing UPDATE/DELETE grant on app.%', t;
    end if;
  end loop;
end $$;

\echo '>> customer-portal-loyalty-ledger-supreme-admin-override.sql: ALL PASSED'
