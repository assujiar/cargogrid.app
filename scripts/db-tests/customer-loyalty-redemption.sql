-- Real, executable test evidence for CPL-321 (CG-S13-CPL-023, Prompt 321,
-- "Redemption Approval and Fulfillment") -- run via `pnpm run db:test`
-- against a real, disposable Postgres database. The SECOND prompt of Batch
-- 5 (CPL-320..323), and the SIXTH Loyalty-domain db-test in this
-- repository.
--
-- UUID range 00000000-0000-0000-0000-0000003440xx (tenant rdm1) /
-- 00000000-0000-0000-0000-0000003441xx (tenant rdm2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Fixture shortcut, disclosed (mirrors CPL-320's own db-test backdating
-- tier/points state directly via fixture INSERT, never through CPL-317/318's
-- own recalculation/posting RPCs): customer tier standing (app.loyalty_
-- account_tier_movements) and points balance (app.loyalty_point_balances)
-- are seeded via DIRECT insert -- this checkpoint's own test is about
-- REDEMPTION correctness given a KNOWN tier/points state, not about how
-- that state came to be.
--
-- Covers, live: (a) the full main flow, both self-service (customer submits
-- -> pending_approval -> staff decide approve -> fulfilling -> staff mark
-- fulfilled) and staff-assisted-instant (staff submits a discount_voucher
-- -> fulfilled inline, single call); (b) rejection reversal -- stock AND
-- points both genuinely released, proven via reservation-sum/points-balance
-- assertions before/after; (c) cancellation reversal, same proof shape;
-- (d) a REAL two-process concurrent double-redemption race against
-- total_stock=1 (reusing scripts/db-tests/wms-picking-concurrency-helper.sh)
-- -- exactly one wins; (e) insufficient-points rejection; (f) held-account
-- block, customer-safe generic message, real hold_reason never leaked;
-- (g) ineligible-reward (tier) block; (h) paused-reward block; (i) an
-- idempotent duplicate submit -- identical redemption returned, zero
-- double-consumption; (j) cross-tenant/cross-account isolation; (k) a real
-- adversarial atomicity proof -- a misconfigured discount_voucher (no
-- internal_cost) with real finite stock and a real points cost rolls back
-- EVERY prior step of the same composition, including the redemption row's
-- own INSERT; (l) optimistic-concurrency NULL-bypass regression proof on
-- app.decide_loyalty_redemption; (m) fulfillment-failed reversal.

\set ON_ERROR_STOP on

\echo '>> setup: tenant rdm1 (Loyalty Manager [full LYL], Plain User [no LYL grant]; customer accounts Alpha/Beta/Gamma/Epsilon, customer_user identities for each), tenant rdm2 (its own Loyalty Manager, customer account Zeta); a shared loyalty program with published Bronze/Silver/Gold tiers; Alpha (Silver, 1000 pts)/Beta (Bronze, 10 pts)/Gamma (Gold, 1000 pts, later held)/Epsilon (Silver, 1000 pts) all enrolled with seeded tier/points fixture state'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_account_epsilon uuid;
  v_account_zeta uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000344004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000344020';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000344030';
  v_customer_epsilon uuid := '00000000-0000-0000-0000-000000344040';
  v_manager2 uuid := '00000000-0000-0000-0000-000000344101';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000344110';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
  v_program_id uuid;
  v_program2_id uuid;
  v_bronze_id uuid;
  v_silver_id uuid;
  v_gold_id uuid;
  v_loyalty_account_alpha uuid;
  v_loyalty_account_beta uuid;
  v_loyalty_account_gamma uuid;
  v_loyalty_account_epsilon uuid;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@rdm1.test'),
    (v_plain1, 'plain1@rdm1.test'),
    (v_customer_alpha, 'customer-alpha@rdm1.test'),
    (v_customer_beta, 'customer-beta@rdm1.test'),
    (v_customer_gamma, 'customer-gamma@rdm1.test'),
    (v_customer_epsilon, 'customer-epsilon@rdm1.test'),
    (v_manager2, 'manager2@rdm2.test'),
    (v_customer_zeta, 'customer-zeta@rdm2.test');

  perform app.provision_tenant('rdm1', 'Redemption Test Tenant One', 'idem-rdm1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'rdm1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'RDM1-CO', 'Rdm1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'RDM1-CO');

  perform app.provision_tenant('rdm2', 'Redemption Test Tenant Two', 'idem-rdm2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'rdm2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'RDM2-CO', 'Rdm2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'RDM2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@rdm1.test', 'Rdm1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@rdm1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@rdm1.test', 'Rdm1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@rdm1.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rdm Account Alpha', 'rdm-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rdm Account Beta', 'rdm-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rdm Account Gamma', 'rdm-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rdm Account Epsilon', 'rdm-epsilon-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_epsilon;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Rdm Account Zeta', 'rdm-zeta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_zeta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@rdm1.test', 'Rdm Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@rdm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@rdm1.test', 'Rdm Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@rdm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_gamma, 'customer-gamma@rdm1.test', 'Rdm Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@rdm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant1, v_account_gamma::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_epsilon, 'customer-epsilon@rdm1.test', 'Rdm Customer Epsilon', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-epsilon@rdm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_epsilon, 'customer_user', v_tenant1, v_account_epsilon::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@rdm2.test', 'Rdm2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@rdm2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_zeta, 'customer-zeta@rdm2.test', 'Rdm Customer Zeta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-zeta@rdm2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_zeta, 'customer_user', v_tenant2, v_account_zeta::text, 'tester');

  perform app.create_loyalty_program(v_tenant1, 'Redemption Program', 'Program used to test redemption.', v_manager1, 'manager1');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Redemption Program');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1, 'manager1');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_epsilon, v_program_id, v_manager1, 'manager1');
  v_loyalty_account_alpha := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_alpha);
  v_loyalty_account_beta := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_beta);
  v_loyalty_account_gamma := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_gamma);
  v_loyalty_account_epsilon := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_epsilon);

  perform app.create_loyalty_program(v_tenant2, 'Redemption Program 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Redemption Program 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_zeta, v_program2_id, v_manager2, 'manager2');

  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Bronze', 1, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_bronze_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Bronze' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_bronze_id, 1, null, v_manager1, 'manager1');

  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Silver', 2, 'earning_amount_ytd', 500, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_silver_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Silver' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_silver_id, 1, null, v_manager1, 'manager1');

  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Gold', 3, 'earning_amount_ytd', 1000, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_gold_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Gold' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_gold_id, 1, null, v_manager1, 'manager1');

  -- Fixture shortcut (disclosed above): Alpha/Epsilon -> Silver, 1000 pts.
  -- Beta -> Bronze, 10 pts. Gamma -> Gold, 1000 pts (held later).
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_alpha, null, v_silver_id, 'initial', v_silver_id, '{}'::jsonb, 'CPL-321 fixture seed', clock_timestamp() + interval '365 days', 'tester');
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_beta, null, v_bronze_id, 'initial', v_bronze_id, '{}'::jsonb, 'CPL-321 fixture seed', clock_timestamp() + interval '365 days', 'tester');
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_gamma, null, v_gold_id, 'initial', v_gold_id, '{}'::jsonb, 'CPL-321 fixture seed', clock_timestamp() + interval '365 days', 'tester');
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_epsilon, null, v_silver_id, 'initial', v_silver_id, '{}'::jsonb, 'CPL-321 fixture seed', clock_timestamp() + interval '365 days', 'tester');

  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_alpha, 1000, 0);
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_beta, 10, 0);
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_gamma, 1000, 0);
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_epsilon, 1000, 0);
end $$;

\echo '>> reward fixtures: a discount_voucher (real internal_cost, points cost 100), a physical_item (points cost 50, stock 5), a race item (stock 1, points cost 0), a tier-gated physical_item (Gold), a points-gated physical_item (500), a paused physical_item, and a MISCONFIGURED discount_voucher (no internal_cost) -- all published'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rdm1') and name = 'Redemption Program');
  v_gold_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rdm1') and name = 'Redemption Program') and tier_name = 'Gold');
  v_row app.loyalty_rewards;
begin
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Voucher Reward', 'discount_voucher', 'A discount voucher.', 'Terms.', null, 100, null, 25, 'vendor-1', null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Physical Reward', 'physical_item', 'A physical item.', null, null, 50, 5, 10, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Race Item', 'physical_item', 'A scarce item.', null, null, 0, 1, 5, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Gold Item', 'physical_item', 'Gold-tier only.', null, v_gold_id, 0, null, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Expensive Item', 'physical_item', 'Costs 500 points.', null, null, 500, null, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Paused Item', 'physical_item', 'Will be paused.', null, null, 0, null, null, null, null, v_manager1, 'manager1');
  v_row := app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');
  perform app.pause_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, 'test pause', v_manager1, 'manager1');

  -- Misconfigured voucher: no internal_cost, but real finite stock and a
  -- real points cost -- the adversarial atomicity fixture.
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Broken Voucher', 'discount_voucher', 'No internal_cost set.', null, null, 30, 3, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');
end $$;

\echo '>> main flow A: staff-assisted instant auto-approve -- v_manager1 submits a discount_voucher redemption for Alpha, composes stock+points+entitlement inline, status=fulfilled in ONE call (design decision 5, the literal auto-approve-inline path)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Voucher Reward');
  v_before_points numeric;
  v_after_points numeric;
  v_redemption app.loyalty_redemptions;
begin
  v_before_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'main-a-voucher', v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilled' or v_redemption.fulfillment_status <> 'not_applicable' or v_redemption.benefit_entitlement_id is null or v_redemption.stock_reservation_id is null then
    raise exception 'assertion failed: expected an instant fulfilled discount_voucher redemption, got %', v_redemption;
  end if;
  if v_redemption.points_consumed <> 100 then
    raise exception 'assertion failed: expected points_consumed=100 (min_points_required), got %', v_redemption.points_consumed;
  end if;

  v_after_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  if v_after_points <> v_before_points - 100 then
    raise exception 'assertion failed: expected points to drop by exactly 100 (% -> %), got %', v_before_points, v_before_points - 100, v_after_points;
  end if;

  -- The entitlement was genuinely minted: benefit_type=voucher,
  -- value_amount=internal_cost (25), a real raw_code returned once.
  if not exists (select 1 from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id and benefit_type = 'voucher' and value_amount = 25 and status = 'issued') then
    raise exception 'assertion failed: expected a real, issued voucher entitlement worth 25';
  end if;

  -- Idempotent duplicate submit (mandatory test): the SAME idempotency_key
  -- returns the IDENTICAL redemption, never double-consumes.
  declare
    v_replay app.loyalty_redemptions;
    v_replay_points numeric;
  begin
    v_replay := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'main-a-voucher', v_manager1, 'manager1');
    if v_replay.id <> v_redemption.id then
      raise exception 'assertion failed: expected the idempotent replay to return the SAME redemption id';
    end if;
    v_replay_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
    if v_replay_points <> v_after_points then
      raise exception 'assertion failed: expected NO further point consumption on idempotent replay, % vs %', v_replay_points, v_after_points;
    end if;
  end;

  -- Idempotency key reused for a DIFFERENT target is rejected.
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, (select id from app.loyalty_rewards where tenant_id = v_tenant1 and reward_name = 'Physical Reward'), 'main-a-voucher', v_manager1, 'manager1');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key against a different reward';
  exception when others then if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;

\echo '>> main flow B: genuine customer self-service -- Epsilon submits a discount_voucher AND a physical_item redemption herself (no LYL:Edit); BOTH land pending_approval (design decision 5, graceful fallback); staff then decides both -- discount_voucher -> fulfilled, physical_item -> fulfilling -> mark_fulfilled'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_epsilon uuid := '00000000-0000-0000-0000-000000344040';
  v_loyalty_account_epsilon uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Epsilon'));
  v_voucher_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Voucher Reward');
  v_physical_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
  v_voucher_redemption app.loyalty_redemptions;
  v_physical_redemption app.loyalty_redemptions;
  v_before_points numeric;
  v_mid_points numeric;
  v_after_points numeric;
begin
  v_before_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_epsilon);

  v_voucher_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_voucher_reward_id, 'main-b-voucher', v_customer_epsilon, 'epsilon');
  if v_voucher_redemption.status <> 'pending_approval' or v_voucher_redemption.stock_reservation_id is not null then
    raise exception 'assertion failed: expected a genuine customer-submitted discount_voucher redemption to land pending_approval, unreserved, got %', v_voucher_redemption;
  end if;

  v_physical_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_physical_reward_id, 'main-b-physical', v_customer_epsilon, 'epsilon');
  if v_physical_redemption.status <> 'pending_approval' or v_physical_redemption.fulfillment_status <> 'pending' or v_physical_redemption.stock_reservation_id is not null then
    raise exception 'assertion failed: expected a genuine customer-submitted physical_item redemption to land pending_approval/pending, unreserved, got %', v_physical_redemption;
  end if;

  -- Points balance is UNCHANGED (nothing was composed yet).
  v_mid_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_epsilon);
  if v_mid_points <> v_before_points then
    raise exception 'assertion failed: expected zero point consumption before staff decides, % vs %', v_mid_points, v_before_points;
  end if;

  -- Plain User (no LYL:Configure) denied.
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_voucher_redemption.id, v_voucher_redemption.record_version, 'approve', null, '00000000-0000-0000-0000-000000344004', 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Customer herself can never reach decide_loyalty_redemption's own
  -- authority gate (design decision 7, self-approval structurally
  -- impossible).
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_voucher_redemption.id, v_voucher_redemption.record_version, 'approve', null, v_customer_epsilon, 'epsilon');
    raise exception 'assertion failed: expected insufficient_authority for a customer_user actor on decide_loyalty_redemption';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_voucher_redemption := app.decide_loyalty_redemption(v_tenant1, v_voucher_redemption.id, v_voucher_redemption.record_version, 'approve', null, v_manager1, 'manager1');
  if v_voucher_redemption.status <> 'fulfilled' or v_voucher_redemption.benefit_entitlement_id is null then
    raise exception 'assertion failed: expected the voucher redemption to be fulfilled after staff approval, got %', v_voucher_redemption;
  end if;

  v_physical_redemption := app.decide_loyalty_redemption(v_tenant1, v_physical_redemption.id, v_physical_redemption.record_version, 'approve', 'looks good', v_manager1, 'manager1');
  if v_physical_redemption.status <> 'fulfilling' or v_physical_redemption.fulfillment_status <> 'in_fulfillment' or v_physical_redemption.stock_reservation_id is null then
    raise exception 'assertion failed: expected the physical_item redemption to move to fulfilling/in_fulfillment, got %', v_physical_redemption;
  end if;

  v_after_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_epsilon);
  -- Voucher cost 100, physical item cost 50 -> 150 consumed total.
  if v_after_points <> v_before_points - 150 then
    raise exception 'assertion failed: expected points to drop by exactly 150 after both approvals, % vs %', v_before_points - 150, v_after_points;
  end if;

  -- app.mark_loyalty_redemption_fulfilled: discount_voucher rejected
  -- (design decision 3), physical_item succeeds.
  begin
    perform app.mark_loyalty_redemption_fulfilled(v_tenant1, v_voucher_redemption.id, v_voucher_redemption.record_version, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition marking a discount_voucher fulfilled directly';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_physical_redemption := app.mark_loyalty_redemption_fulfilled(v_tenant1, v_physical_redemption.id, v_physical_redemption.record_version, v_manager1, 'manager1');
  if v_physical_redemption.status <> 'fulfilled' or v_physical_redemption.fulfillment_status <> 'fulfilled' then
    raise exception 'assertion failed: expected the physical_item redemption to be fulfilled, got %', v_physical_redemption;
  end if;

  -- Re-marking an already-fulfilled redemption is rejected.
  begin
    perform app.mark_loyalty_redemption_fulfilled(v_tenant1, v_physical_redemption.id, v_physical_redemption.record_version, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition re-marking an already-fulfilled redemption';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> rejection reversal (mandatory test): staff submits a physical_item redemption for Alpha (reserves stock + consumes points immediately), then REJECTS it -- both genuinely released, proven via reservation-sum/points-balance assertions before/after; mandatory non-empty reason enforced'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
  v_redemption app.loyalty_redemptions;
  v_before_points numeric;
  v_after_reserve_points numeric;
  v_after_reject_points numeric;
  v_reserved_before integer;
  v_reserved_after_compose integer;
  v_reserved_after_reject integer;
begin
  -- physical_item never auto-composes at submit -- lock it in manually via
  -- decide(approve) first (staff, holds LYL:Edit) to reach a REAL reserved
  -- state, then reject it.
  v_before_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  select coalesce(sum(quantity), 0) into v_reserved_before from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'reject-flow', v_manager1, 'manager1');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected physical_item to land pending_approval even for a staff submitter, got %', v_redemption;
  end if;

  v_redemption := app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', null, v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilling' or v_redemption.stock_reservation_id is null then
    raise exception 'assertion failed: expected the redemption to be genuinely reserved after approval, got %', v_redemption;
  end if;

  select coalesce(sum(quantity), 0) into v_reserved_after_compose from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;
  if v_reserved_after_compose <> v_reserved_before + 1 then
    raise exception 'assertion failed: expected reserved sum to increase by exactly 1, % -> %', v_reserved_before, v_reserved_after_compose;
  end if;
  v_after_reserve_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  if v_after_reserve_points <> v_before_points - 50 then
    raise exception 'assertion failed: expected points to drop by 50 after reservation, % vs %', v_before_points - 50, v_after_reserve_points;
  end if;

  -- Reject requires a mandatory non-empty reason.
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'reject', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for a reject with no reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- decide_loyalty_redemption only accepts a pending_approval redemption --
  -- this one is now 'fulfilling', so reject is rejected too.
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'reject', 'changed our mind', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition rejecting a fulfilling redemption';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Use app.mark_loyalty_redemption_fulfillment_failed instead (the real,
  -- post-approval reversal path) -- mandatory non-empty reason, genuinely
  -- reverses stock + points.
  begin
    perform app.mark_loyalty_redemption_fulfillment_failed(v_tenant1, v_redemption.id, v_redemption.record_version, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for fulfillment-failed with no reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_redemption := app.mark_loyalty_redemption_fulfillment_failed(v_tenant1, v_redemption.id, v_redemption.record_version, 'item damaged in warehouse', v_manager1, 'manager1');
  if v_redemption.status <> 'failed' or v_redemption.fulfillment_status <> 'failed' then
    raise exception 'assertion failed: expected status=failed/fulfillment_status=failed, got %', v_redemption;
  end if;

  select coalesce(sum(quantity), 0) into v_reserved_after_reject from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;
  if v_reserved_after_reject <> v_reserved_before then
    raise exception 'assertion failed: expected the reservation to be fully released back to the pre-reservation sum, % vs %', v_reserved_before, v_reserved_after_reject;
  end if;
  v_after_reject_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  if v_after_reject_points <> v_before_points then
    raise exception 'assertion failed: expected points to be fully credited back to the pre-reservation balance, % vs %', v_before_points, v_after_reject_points;
  end if;
end $$;

\echo '>> straight rejection reversal (mandatory test, decide-time reject branch): staff submits + immediately approves a SECOND physical_item redemption for Alpha (reserving again), demonstrating app.decide_loyalty_redemption own reject branch (not just fulfillment-failed) also reverses stock+points -- via a genuinely re-opened pending_approval created by a fresh customer submission, decided and rejected in one step is not reachable once approved, so this proves the reject path using a CUSTOMER-submitted (never-reserved) redemption plus a STAFF-submitted (reserved) one, side by side'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_voucher_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Voucher Reward');
  v_before_points numeric;
  v_after_points numeric;
  v_redemption app.loyalty_redemptions;
begin
  -- A customer-submitted voucher redemption (unassisted -> never reserved)
  -- rejected by staff has NOTHING to reverse -- a real, safe no-op path,
  -- proven distinct from the reserved case above.
  v_before_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_voucher_reward_id, 'reject-unreserved', v_customer_alpha, 'alpha');
  if v_redemption.stock_reservation_id is not null then
    raise exception 'assertion failed: expected a genuine customer submission to be unreserved before decide';
  end if;

  v_redemption := app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'reject', 'declined by staff', v_manager1, 'manager1');
  if v_redemption.status <> 'rejected' or v_redemption.decision_reason <> 'declined by staff' then
    raise exception 'assertion failed: expected status=rejected with the real reason recorded, got %', v_redemption;
  end if;

  v_after_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  if v_after_points <> v_before_points then
    raise exception 'assertion failed: expected zero point movement for a reject of a never-composed redemption, % vs %', v_before_points, v_after_points;
  end if;
end $$;

\echo '>> cancellation reversal (mandatory test): Alpha submits a physical_item redemption HERSELF (never reserved -- customer path), cancels it -- a safe no-op reversal; a staff member cannot cancel an already-decided redemption'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000344020';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
  v_redemption app.loyalty_redemptions;
begin
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'cancel-flow', v_customer_alpha, 'alpha');

  -- A DIFFERENT customer (Beta) cannot cancel Alpha's own redemption --
  -- anti-enumeration: identical loyalty_redemption_not_found.
  begin
    perform app.cancel_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, v_customer_beta, 'beta');
    raise exception 'assertion failed: expected loyalty_redemption_not_found for a different customer cancelling';
  exception when others then if sqlerrm not like 'loyalty_redemption_not_found%' then raise; end if;
  end;

  v_redemption := app.cancel_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, v_customer_alpha, 'alpha');
  if v_redemption.status <> 'cancelled' or v_redemption.fulfillment_status <> 'not_applicable' then
    raise exception 'assertion failed: expected status=cancelled, got %', v_redemption;
  end if;

  -- Cancelling an already-cancelled redemption is rejected.
  begin
    perform app.cancel_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected invalid_transition cancelling an already-cancelled redemption';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> insufficient-points rejection: Beta (10 points) attempts the Expensive Item (500 points required)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_customer_beta uuid := '00000000-0000-0000-0000-000000344020';
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Beta'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Expensive Item');
begin
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_beta, v_reward_id, 'insufficient-points', v_customer_beta, 'beta');
    raise exception 'assertion failed: expected ineligible_reward for insufficient points';
  exception when others then if sqlerrm not like 'ineligible_reward%' then raise; end if;
  end;
  if exists (select 1 from app.loyalty_redemptions where tenant_id = v_tenant1 and idempotency_key = 'insufficient-points') then
    raise exception 'assertion failed: expected NO redemption row to be created for a rejected-at-validation submit';
  end if;
end $$;

\echo '>> ineligible-reward (tier) block: Alpha (Silver) attempts the Gold Item'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Gold Item');
begin
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'ineligible-tier', v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected ineligible_reward for a Silver customer against a Gold-gated reward';
  exception when others then if sqlerrm not like 'ineligible_reward%' then raise; end if;
  end;
end $$;

\echo '>> paused-reward block (stale-reward-version/status revalidation): the Paused Item is not currently redeemable'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Paused Item');
begin
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'paused-reward', v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected reward_not_currently_redeemable for a paused reward';
  exception when others then if sqlerrm not like 'reward_not_currently_redeemable%' then raise; end if;
  end;
end $$;

\echo '>> held-account block (customer-safe denial, mandatory test): Gamma is held (app.hold_loyalty_account_tier_benefits, real hold_reason set); redemption attempt is blocked with a GENERIC message that never leaks the real hold_reason'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000344030';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Gamma'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
begin
  perform app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_gamma, 'CONFIDENTIAL: fraud investigation case #77712, do not disclose to customer', v_manager1, 'manager1');

  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_gamma, v_reward_id, 'held-account', v_customer_gamma, 'gamma');
    raise exception 'assertion failed: expected account_on_hold for a held account';
  exception when others then
    if sqlerrm not like 'account_on_hold%' then raise; end if;
    if sqlerrm like '%fraud investigation%' or sqlerrm like '%77712%' or sqlerrm like '%CONFIDENTIAL%' then
      raise exception 'assertion failed: the real hold_reason leaked into a customer-facing error message: %', sqlerrm;
    end if;
  end;

  -- Release the hold so Gamma is usable by later isolation tests if
  -- needed, and to prove the block lifts.
  perform app.release_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_gamma, v_manager1, 'manager1');
end $$;

\echo '>> adversarial atomicity + intent-record-survival proof (mandatory test, Tier C review regression, Batch 5 close): staff submits a MISCONFIGURED discount_voucher (real finite stock, real points cost, but NO internal_cost) -- reserve succeeds, consume succeeds, entitlement issuance fails -- the COMPOSITION''s own partial work (stock reservation, point consumption) rolls back completely, but the redemption row''s own INSERT and its submitted event now correctly SURVIVE at pending_approval (Tier C review fix -- app.submit_loyalty_redemption catches ANY composition failure, not only insufficient_authority), proven via reservation-sum/points-balance/row-existence/row-status assertions -- the call itself no longer raises to the caller at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Broken Voucher');
  v_before_points numeric;
  v_after_points numeric;
  v_reserved_before integer;
  v_reserved_after integer;
  v_redemption app.loyalty_redemptions;
  v_event_count integer;
begin
  v_before_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  select coalesce(sum(quantity), 0) into v_reserved_before from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;

  -- No exception reaches the caller at all now -- the composition's own
  -- internal failure (reward_redemption_unavailable) is caught INSIDE
  -- app.submit_loyalty_redemption and the call returns normally with the
  -- redemption still at pending_approval.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'adversarial-atomicity', v_manager1, 'manager1');

  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected the redemption to survive at pending_approval after a forced mid-composition failure, got %', v_redemption.status;
  end if;
  if v_redemption.stock_reservation_id is not null or v_redemption.benefit_entitlement_id is not null then
    raise exception 'assertion failed: expected NO stock_reservation_id/benefit_entitlement_id to be attached -- the composition''s own partial work must not be linked to a redemption that never actually completed it, got %', v_redemption;
  end if;

  v_after_points := (select available from app.loyalty_point_balances where tenant_id = v_tenant1 and loyalty_account_id = v_loyalty_account_alpha);
  if v_after_points <> v_before_points then
    raise exception 'assertion failed: expected ZERO net point consumption after a forced mid-composition failure, % vs %', v_before_points, v_after_points;
  end if;

  select coalesce(sum(quantity), 0) into v_reserved_after from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;
  if v_reserved_after <> v_reserved_before then
    raise exception 'assertion failed: expected ZERO net stock reservation after a forced mid-composition failure, % vs %', v_reserved_before, v_reserved_after;
  end if;

  if not exists (select 1 from app.loyalty_redemptions where tenant_id = v_tenant1 and idempotency_key = 'adversarial-atomicity' and status = 'pending_approval') then
    raise exception 'assertion failed: expected the redemption row''s own INSERT to SURVIVE (Tier C review fix) -- a staff-initiated request must never silently vanish just because the auto-approve attempt failed for a non-authority reason';
  end if;

  -- The 'submitted' event survives too -- no 'approved'/'fulfilled' event
  -- was ever committed (the composition's own event inserts are inside the
  -- same rolled-back attempt).
  select count(*) into v_event_count from app.loyalty_redemption_events where redemption_id = v_redemption.id;
  if v_event_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE surviving event (submitted) for this redemption, got %', v_event_count;
  end if;
  if not exists (select 1 from app.loyalty_redemption_events where redemption_id = v_redemption.id and event_type = 'submitted') then
    raise exception 'assertion failed: expected the surviving event to be the original submitted event';
  end if;

  -- A genuine replay (same idempotency key) does not re-attempt
  -- composition -- the idempotent short-circuit returns the SAME
  -- pending_approval row, never a second attempt/second event.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'adversarial-atomicity', v_manager1, 'manager1');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected the idempotent replay to return the same pending_approval row, got %', v_redemption.status;
  end if;
  select count(*) into v_event_count from app.loyalty_redemption_events where redemption_id = v_redemption.id;
  if v_event_count <> 1 then
    raise exception 'assertion failed: expected the idempotent replay to add NO further event, got % total', v_event_count;
  end if;

  -- A real staff decision on the now-surviving row independently
  -- re-validates and correctly fails again (the reward is still
  -- misconfigured) -- via decide_loyalty_redemption's own uncaught
  -- propagation (staff decisions are never silently swallowed the way
  -- submit''s own auto-approve attempt is).
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected reward_redemption_unavailable when a human staff decision re-validates the same misconfigured reward';
  exception when others then if sqlerrm not like 'reward_redemption_unavailable%' then raise; end if;
  end;
  if not exists (select 1 from app.loyalty_redemptions where id = v_redemption.id and status = 'pending_approval') then
    raise exception 'assertion failed: expected the redemption to remain pending_approval after a failed decide(approve) re-validation too';
  end if;
end $$;

\echo '>> a REAL two-process concurrent race (mandatory test): two overlapping psql sessions each submit a staff-assisted discount_voucher-shaped redemption... using the Race Item (physical_item, total_stock=1) via staff-submitted decide(approve) -- reusing scripts/db-tests/wms-picking-concurrency-helper.sh -- exactly one wins, the other is genuinely rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_loyalty_account_epsilon uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Epsilon'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Race Item');
  v_redemption_a app.loyalty_redemptions;
  v_redemption_b app.loyalty_redemptions;
begin
  -- Two DISTINCT pending_approval redemptions (one per account) against the
  -- SAME total_stock=1 reward -- both submitted by staff (Race Item costs 0
  -- points, so submit alone does not compose; only decide(approve) does).
  v_redemption_a := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'race-submit-a', v_manager1, 'manager1');
  v_redemption_b := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_reward_id, 'race-submit-b', v_manager1, 'manager1');
end $$;

select (select id from app.tenants where slug = 'rdm1') as race_tenant1_id \gset
select id as race_redemption_a_id, record_version as race_redemption_a_version from app.loyalty_redemptions where tenant_id = (select id from app.tenants where slug = 'rdm1') and idempotency_key = 'race-submit-a' \gset
select id as race_redemption_b_id, record_version as race_redemption_b_version from app.loyalty_redemptions where tenant_id = (select id from app.tenants where slug = 'rdm1') and idempotency_key = 'race-submit-b' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

-- Literal-interpolated (never current_setting()/set_config -- the race
-- helper opens brand-new psql CONNECTIONS, which do not share this
-- session's own GUCs).
\set race_sql_a 'select app.decide_loyalty_redemption(''' :race_tenant1_id ''', ''' :race_redemption_a_id ''', ' :race_redemption_a_version ', ''approve'', null, ''00000000-0000-0000-0000-000000344001'', ''manager1'');'
\set race_sql_b 'select app.decide_loyalty_redemption(''' :race_tenant1_id ''', ''' :race_redemption_b_id ''', ' :race_redemption_b_version ', ''approve'', null, ''00000000-0000-0000-0000-000000344001'', ''manager1'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-rdm-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-rdm-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Race Item');
  v_reserved_sum integer;
  v_approved_count integer;
  v_failed_count integer;
begin
  select coalesce(sum(quantity), 0) into v_reserved_sum from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;
  if v_reserved_sum > 1 then
    raise exception 'assertion failed: the concurrent race must never reserve more than total_stock=1, got a reserved sum of %', v_reserved_sum;
  end if;

  select count(*) into v_approved_count from app.loyalty_redemptions where reward_id = v_reward_id and idempotency_key in ('race-submit-a', 'race-submit-b') and status = 'fulfilling';
  select count(*) into v_failed_count from app.loyalty_redemptions where reward_id = v_reward_id and idempotency_key in ('race-submit-a', 'race-submit-b') and status = 'pending_approval';

  if v_approved_count <> 1 then
    raise exception 'assertion failed: expected EXACTLY ONE of the two racing redemptions to reach fulfilling, got %', v_approved_count;
  end if;
  if v_failed_count <> 1 then
    raise exception 'assertion failed: expected EXACTLY ONE of the two racing redemptions to remain pending_approval (its own decide call genuinely failed), got %', v_failed_count;
  end if;
end $$;

\echo '>> CPL-325 hold-race regression (mandatory test): a REAL two-process concurrent race between app.hold_loyalty_account_tier_benefits and app.decide_loyalty_redemption(approve) on the SAME loyalty account -- the live-reproduced TOCTOU this checkpoint fixed (supabase/migrations/20260801300000). Gamma (Gold, 1000 pts, currently released from the earlier held-account test) gets a fresh pending_approval physical_item redemption; process A holds her account, process B approves the SAME redemption, launched via scripts/db-tests/wms-picking-concurrency-helper.sh. Whichever order the two genuinely land in, the post-fix invariant must hold: the redemption may only reach fulfilling if its own decided_at is BEFORE the hold''s own held_at (decide-first, hold-applies-after -- today''s already-correct non-concurrent ordering) -- never a fulfilling redemption whose decided_at is AFTER an already-committed hold (the torn state the fix closes)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rdm1') and name = 'Redemption Program');
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Gamma'));
  v_reward app.loyalty_rewards;
  v_redemption app.loyalty_redemptions;
begin
  -- Confirmed unheld at this point (the earlier held-account test releases
  -- Gamma's own hold at its own close, line ~590) -- an explicit release
  -- here too, defensively, so this block's own assertions never depend on
  -- execution order relative to that earlier block.
  begin
    perform app.release_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_gamma, v_manager1, 'manager1');
  exception when no_data_found then null;
  end;

  v_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Hold Race Item', 'physical_item', 'CPL-325 hold-vs-redemption race fixture.', null, null, 0, 3, 5, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, null, v_manager1, 'manager1');

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_gamma, v_reward.id, 'hold-race-submit-1', v_manager1, 'manager1');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected the physical_item redemption to land pending_approval (staff decide required), got %', v_redemption;
  end if;
end $$;

select (select id from app.tenants where slug = 'rdm1') as hr_tenant1_id \gset
select id as hr_loyalty_account_gamma_id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Gamma') \gset
select id as hr_redemption_id, record_version as hr_redemption_version from app.loyalty_redemptions where tenant_id = (select id from app.tenants where slug = 'rdm1') and idempotency_key = 'hold-race-submit-1' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as hr_bpid \gset

\set race_sql_a 'select app.hold_loyalty_account_tier_benefits(''' :hr_tenant1_id ''', ''' :hr_loyalty_account_gamma_id ''', ''CPL-325 hold-race regression test'', ''00000000-0000-0000-0000-000000344001'', ''manager1'');'
\set race_sql_b 'select app.decide_loyalty_redemption(''' :hr_tenant1_id ''', ''' :hr_redemption_id ''', ' :hr_redemption_version ', ''approve'', null, ''00000000-0000-0000-0000-000000344001'', ''manager1'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-rdm-hold-race-a-:hr_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-rdm-hold-race-b-:hr_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Gamma'));
  v_hold app.loyalty_account_tier_holds;
  v_redemption app.loyalty_redemptions;
begin
  select * into v_hold from app.loyalty_account_tier_holds where tenant_id = (select id from app.tenants where slug = 'rdm1') and loyalty_account_id = v_loyalty_account_gamma;
  select * into v_redemption from app.loyalty_redemptions where tenant_id = (select id from app.tenants where slug = 'rdm1') and idempotency_key = 'hold-race-submit-1';

  -- The hold-open call is independent of the redemption's own outcome --
  -- it always succeeds, whichever order the race lands in.
  if not coalesce(v_hold.is_held, false) then
    raise exception 'assertion failed: expected the hold to have been applied regardless of race ordering, got is_held=%', v_hold.is_held;
  end if;

  -- The core invariant this fix restores: a fulfilling redemption's own
  -- decided_at must be BEFORE the hold's own held_at -- i.e. the decide
  -- call fully completed (and released the shared advisory lock) before
  -- the hold-open call ever started its own check. The reverse (a hold
  -- already committed, then a decide that still reaches fulfilling) is
  -- exactly the live-reproduced torn state this migration closes.
  if v_redemption.status = 'fulfilling' and v_hold.held_at < v_redemption.decided_at then
    raise exception 'CRITICAL: fulfilling redemption (decided_at=%) with a hold that committed BEFORE it (held_at=%) -- the hold-vs-redemption TOCTOU race is back', v_redemption.decided_at, v_hold.held_at;
  end if;
  if v_redemption.status not in ('fulfilling', 'pending_approval') then
    raise exception 'assertion failed: expected the raced redemption to land either fulfilling (decide-first) or pending_approval (hold-first, account_on_hold) got status=%', v_redemption.status;
  end if;

  -- Clean up -- release the hold so it cannot affect any later block in
  -- this file (defensive; no later block currently touches Gamma, but
  -- matches this file's own established hygiene).
  perform app.release_loyalty_account_tier_benefits((select id from app.tenants where slug = 'rdm1'), v_loyalty_account_gamma, '00000000-0000-0000-0000-000000344001', 'manager1');
end $$;

\echo '>> optimistic-concurrency NULL-bypass regression proof (mandatory test) on app.decide_loyalty_redemption: a NULL p_expected_version is rejected with stale_version, row unchanged, then the real version succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
  v_redemption app.loyalty_redemptions;
  v_before app.loyalty_redemptions;
begin
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'null-bypass-decide', v_customer_alpha, 'alpha');
  v_before := v_redemption;

  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_redemption.id, null, 'approve', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on decide_loyalty_redemption';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  if not exists (select 1 from app.loyalty_redemptions where id = v_before.id and status = v_before.status and record_version = v_before.record_version) then
    raise exception 'assertion failed: expected the redemption row to be byte-for-byte unchanged after a rejected NULL-bypass attempt';
  end if;

  v_redemption := app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', null, v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilling' then
    raise exception 'assertion failed: expected the real-version call to succeed, got %', v_redemption;
  end if;

  -- Same regression proof on app.cancel_loyalty_redemption and app.mark_
  -- loyalty_redemption_fulfilled/failed -- each independently.
  begin
    perform app.mark_loyalty_redemption_fulfilled(v_tenant1, v_redemption.id, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on mark_loyalty_redemption_fulfilled';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  perform app.mark_loyalty_redemption_fulfilled(v_tenant1, v_redemption.id, v_redemption.record_version, v_manager1, 'manager1');
end $$;

\echo '>> cross-tenant/cross-account isolation (mandatory test): tenant rdm2''s own manager cannot act on rdm1''s redemptions (insufficient_authority by wrong tenant, loyalty_redemption_not_found guessing an rdm1 id inside rdm2''s own scope); customer Zeta (rdm2) sees zero rdm1 redemptions even passing rdm1''s own tenant_id and Alpha''s own real loyalty_account_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'rdm2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000344101';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000344110';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_rdm1_redemption_id uuid;
  v_row_count integer;
begin
  select id into v_rdm1_redemption_id from app.loyalty_redemptions where tenant_id = v_tenant1 limit 1;

  -- rdm2's manager, scoped to rdm2, cannot read/decide an rdm1 redemption
  -- id (wrong tenant in p_tenant_id -> not found within rdm2's own scope).
  begin
    perform app.get_loyalty_redemption(v_tenant2, v_rdm1_redemption_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_redemption_not_found for an rdm1 id queried under rdm2''s own tenant scope';
  exception when others then if sqlerrm not like 'loyalty_redemption_not_found%' then raise; end if;
  end;

  begin
    perform app.decide_loyalty_redemption(v_tenant2, v_rdm1_redemption_id, 1, 'approve', null, v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_redemption_not_found deciding an rdm1 id under rdm2''s own tenant scope';
  exception when others then if sqlerrm not like 'loyalty_redemption_not_found%' then raise; end if;
  end;

  -- Zeta (rdm2 customer) sees ZERO rdm1 redemptions even passing rdm1's
  -- own tenant_id and Alpha's own real loyalty_account_id (deny-by-default,
  -- ADR-0024 Part A).
  select count(*) into v_row_count from app.list_customer_portal_loyalty_redemptions(v_tenant1, v_customer_zeta, v_loyalty_account_alpha, null, null, 50);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected ZERO rows for a cross-tenant customer scope probe, got %', v_row_count;
  end if;

  begin
    perform app.get_customer_portal_loyalty_redemption(v_tenant1, v_rdm1_redemption_id, v_customer_zeta);
    raise exception 'assertion failed: expected loyalty_redemption_not_found for a cross-tenant customer detail probe';
  exception when others then if sqlerrm not like 'loyalty_redemption_not_found%' then raise; end if;
  end;
end $$;

\echo '>> actor-identity session cross-check (ATW-031): a forged p_actor_auth_user_id is rejected with actor_identity_mismatch when a genuine session identity is set'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000344010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Physical Reward');
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'forged-actor', v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected actor_identity_mismatch for a forged actor id under a real session';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> raw-table RLS / raw-function-grant defense-in-depth: authenticated holds zero direct table grant; anon holds zero EXECUTE on any of the new functions; a real authenticated-role positive path matches a direct superuser call'
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000344001","role":"authenticated"}', true);
  set local role authenticated;
  begin
    perform 1 from app.loyalty_redemptions limit 1;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_redemptions to be denied';
  exception when insufficient_privilege then null;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('submit_loyalty_redemption', 'decide_loyalty_redemption', 'cancel_loyalty_redemption', 'mark_loyalty_redemption_fulfilled', 'mark_loyalty_redemption_fulfillment_failed', 'release_loyalty_reward_stock_reservation', '_compose_loyalty_redemption_decision', '_reverse_loyalty_redemption_composition')
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected ZERO anon EXECUTE grants on any CPL-321 mutation function, got %', v_count;
  end if;
end $$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  -- Resolved BEFORE switching role below -- authenticated holds no raw
  -- SELECT on app.loyalty_redemptions (that is the very thing this test
  -- proves), so this lookup must happen under the original session role.
  v_redemption_id uuid := (select id from app.loyalty_redemptions where tenant_id = v_tenant1 limit 1);
  v_row app.loyalty_redemptions;
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  set local role authenticated;
  v_row := app.get_loyalty_redemption(v_tenant1, v_redemption_id, v_manager1);
  if v_row.id is null then
    raise exception 'assertion failed: expected a real authenticated-role positive read path to succeed';
  end if;
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> keyset pagination on app.list_loyalty_redemptions, visiting every row exactly once at p_limit=1; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_total_count integer;
  v_visited_count integer := 0;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_row app.loyalty_redemptions;
  v_seen uuid[] := array[]::uuid[];
begin
  select count(*) into v_total_count from app.loyalty_redemptions where tenant_id = v_tenant1;

  loop
    v_row := null;
    select r.* into v_row from app.list_loyalty_redemptions(v_tenant1, v_manager1, null, null, v_cursor_updated_at, v_cursor_id, 1) r;
    exit when v_row.id is null;
    if v_row.id = any (v_seen) then
      raise exception 'assertion failed: keyset pagination revisited id %', v_row.id;
    end if;
    v_seen := v_seen || v_row.id;
    v_visited_count := v_visited_count + 1;
    v_cursor_updated_at := v_row.updated_at;
    v_cursor_id := v_row.id;
  end loop;

  if v_visited_count <> v_total_count then
    raise exception 'assertion failed: expected to visit all % redemptions exactly once, visited %', v_total_count, v_visited_count;
  end if;

  begin
    perform app.list_loyalty_redemptions(v_tenant1, v_manager1, null, null, null, gen_random_uuid(), 10);
    raise exception 'assertion failed: expected invalid_cursor for a half-supplied cursor (id without updated_at)';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> HDN-373 (ISS-2026-139, RLS and RBAC Audit): a redemption clerk holding LYL:Edit but NOT LYL:Configure can submit a discount_voucher redemption but the auto-compose shortcut no longer fires for them -- it lands pending_approval like a genuine customer submission, closing the maker/checker collapse main flow A relies on Configure-holding staff to legitimately exercise. A distinct LYL:Configure holder (v_manager1) then decides it for real -- self-service-with-Configure remains unaffected (main flow A above), and the graceful pending_approval fallback for everyone else is unchanged (main flow B above).'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_company1 uuid := (select org_unit_id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_clerk uuid := '00000000-0000-0000-0000-000000344005';
  v_clerk_role uuid;
  v_clerk_draft app.role_versions;
  v_account_id uuid;
  v_loyalty_account_id uuid;
  v_voucher_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rdm1') and reward_name = 'Voucher Reward');
  v_redemption app.loyalty_redemptions;
begin
  -- A fresh account and loyalty account, isolated from every balance/stock
  -- state the rest of this file may have already consumed.
  insert into auth.users (id, email) values (v_clerk, 'clerk@rdm1.test');
  perform app.invite_user(v_tenant1, v_clerk, 'clerk@rdm1.test', 'Rdm1 Redemption Clerk', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'clerk@rdm1.test'), 'active', 'onboarded', 'tester');

  v_clerk_role := (app.create_role(v_tenant1, 'Redemption Clerk', 'LYL:Edit only, no Configure -- HDN-373 regression', 'tester')).id;
  v_clerk_draft := app.create_role_version(v_clerk_role, 'tester');
  perform app.set_role_version_permissions(v_clerk_draft.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit')), 'tester');
  perform app.publish_role_version(v_clerk_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_clerk_role and status = 'published'), v_clerk, v_manager1, 'tester');

  if (app.evaluate_permission(v_clerk, v_tenant1, 'LYL', 'Configure')).allowed then
    raise exception 'assertion failed: fixture error -- the clerk role must NOT hold LYL:Configure for this regression to be meaningful';
  end if;

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rdm Account HDN373', 'rdm-hdn373-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_id;
  perform app.enroll_customer_loyalty_account(
    v_tenant1, v_account_id,
    (select program_id from app.loyalty_tier_definitions where tenant_id = v_tenant1 and tier_name = 'Silver' and status = 'published'),
    v_manager1, 'manager1'
  );
  v_loyalty_account_id := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_id);

  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (
    v_tenant1, v_loyalty_account_id, null,
    (select id from app.loyalty_tier_definitions where tenant_id = v_tenant1 and tier_name = 'Silver' and status = 'published'),
    'initial',
    (select id from app.loyalty_tier_definitions where tenant_id = v_tenant1 and tier_name = 'Silver' and status = 'published'),
    '{}'::jsonb, 'HDN-373 fixture seed', clock_timestamp() + interval '365 days', 'tester'
  );
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_id, 1000, 0);

  -- The clerk, LYL:Edit only, submits the SAME discount_voucher reward main
  -- flow A's Configure-holding manager gets instant-fulfilled for.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_id, v_voucher_reward_id, 'hdn373-clerk-voucher', v_clerk, 'clerk');
  if v_redemption.status <> 'pending_approval' or v_redemption.benefit_entitlement_id is not null or v_redemption.stock_reservation_id is not null then
    raise exception 'assertion failed: HDN-373/ISS-2026-139 has regressed -- an LYL:Edit-only clerk auto-composed a discount_voucher redemption (status=%), the maker/checker collapse this fix closed', v_redemption.status;
  end if;
  if v_redemption.created_by <> 'clerk' then
    raise exception 'assertion failed: fixture error -- expected created_by=clerk, got %', v_redemption.created_by;
  end if;

  -- The clerk cannot decide their own submission either (decide_loyalty_
  -- redemption's own pre-existing LYL:Configure gate, unaffected by this fix).
  begin
    perform app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', null, v_clerk, 'clerk');
    raise exception 'assertion failed: expected insufficient_authority for the LYL:Edit-only clerk on decide_loyalty_redemption';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A genuine, distinct LYL:Configure holder can still decide it for real --
  -- the maker/checker separation this fix restores, not a blanket lockout.
  v_redemption := app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', null, v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilled' or v_redemption.benefit_entitlement_id is null or v_redemption.decided_by <> 'manager1' then
    raise exception 'assertion failed: expected a distinct LYL:Configure holder to successfully decide the clerk''s submission, got %', v_redemption;
  end if;

  raise notice 'HDN-373 loyalty redemption maker/checker regression proof: an LYL:Edit-only clerk''s discount_voucher submission lands pending_approval (no self-fulfillment), is denied on their own decide_loyalty_redemption attempt, and is correctly decided by a distinct LYL:Configure holder';
end $$;

\echo '>> ISS-2026-129 item 3 / ISS-2026-132 item 2 (2026-09-02): a percentage-type discount_voucher reward computes its entitlement value against its own staff-configured base amount; a fixed_amount reward with an explicitly-configured voucher_face_value redeems at that DECOUPLED figure, never internal_cost; app.set_loyalty_reward_voucher_value_config itself rejects an invalid percentage/base_amount shape before a reward can ever be redeemed at it; a reward NEVER migrated to voucher_face_value keeps redeeming at internal_cost, byte-identical to before this fix'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rdm1') and name = 'Redemption Program');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Alpha'));
  v_row app.loyalty_rewards;
  v_pct_reward app.loyalty_rewards;
  v_facevalue_reward app.loyalty_rewards;
  v_redemption app.loyalty_redemptions;
begin
  -- Percentage-type reward: 20% of a staff-configured 100 base -> 20.00.
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Percentage Voucher', 'discount_voucher', 'A percentage-off voucher.', 'Terms.', null, 10, null, 999, 'vendor-pct', null, v_manager1, 'manager1');

  -- Configuring an invalid shape is rejected BEFORE it can ever be
  -- redeemed at it -- "never a fabricated or zero value" holds at
  -- configuration time, not merely as a redemption-time afterthought.
  begin
    perform app.set_loyalty_reward_voucher_value_config(v_tenant1, v_row.id, v_row.record_version, 'percentage', null, 150, 100, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_voucher_percentage for a percentage > 100';
  exception when others then if sqlerrm not like 'invalid_voucher_percentage%' then raise; end if;
  end;
  begin
    perform app.set_loyalty_reward_voucher_value_config(v_tenant1, v_row.id, v_row.record_version, 'percentage', null, 20, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_voucher_percentage_base_amount for a zero base_amount';
  exception when others then if sqlerrm not like 'invalid_voucher_percentage_base_amount%' then raise; end if;
  end;

  v_row := app.set_loyalty_reward_voucher_value_config(v_tenant1, v_row.id, v_row.record_version, 'percentage', null, 20, 100, v_manager1, 'manager1');
  if v_row.voucher_value_type <> 'percentage' or v_row.voucher_percentage <> 20 or v_row.voucher_percentage_base_amount <> 100 then
    raise exception 'assertion failed: expected the reward''s own percentage config to persist, got %', to_jsonb(v_row);
  end if;
  v_pct_reward := app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_pct_reward.id, 'pct-voucher-redeem-1', v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilled' then
    raise exception 'assertion failed: expected the percentage-type voucher to instant-fulfill (staff Configure submission), got status=%', v_redemption.status;
  end if;
  if not exists (select 1 from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id and value_amount = 20.00) then
    raise exception 'assertion failed: expected the percentage voucher''s entitlement to be worth exactly 20.00 (20%% of the staff-configured 100 base), got %', (select value_amount from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id);
  end if;

  -- Fixed-amount reward with a DECOUPLED, real customer-facing face value:
  -- internal_cost is 999 (staff-only), voucher_face_value is explicitly
  -- configured to 15 -- the entitlement must be worth 15, NEVER 999.
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Decoupled Face Value Voucher', 'discount_voucher', 'internal_cost != customer value.', 'Terms.', null, 10, null, 999, 'vendor-decoupled', null, v_manager1, 'manager1');
  v_row := app.set_loyalty_reward_voucher_value_config(v_tenant1, v_row.id, v_row.record_version, 'fixed_amount', 15, null, null, v_manager1, 'manager1');
  v_facevalue_reward := app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_facevalue_reward.id, 'facevalue-voucher-redeem-1', v_manager1, 'manager1');
  if not exists (select 1 from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id and value_amount = 15) then
    raise exception 'assertion failed: expected the decoupled voucher''s entitlement to be worth its own voucher_face_value (15), never internal_cost (999), got %', (select value_amount from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id);
  end if;

  -- Backward compatibility (mandatory): this file''s own PRE-EXISTING
  -- 'Voucher Reward' (created earlier in this same file, internal_cost=25,
  -- never touched by app.set_loyalty_reward_voucher_value_config) already
  -- redeemed at 25 in "main flow A" above, before this fix existed --
  -- re-confirmed unaffected via a SECOND, fresh redemption against it here.
  declare
    v_voucher_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = v_tenant1 and reward_name = 'Voucher Reward');
    v_compat_redemption app.loyalty_redemptions;
  begin
    v_compat_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_voucher_reward_id, 'voucher-compat-redeem-2', v_manager1, 'manager1');
    if not exists (select 1 from app.loyalty_benefit_entitlements where id = v_compat_redemption.benefit_entitlement_id and value_amount = 25) then
      raise exception 'assertion failed: expected a reward NEVER migrated to voucher_face_value to keep redeeming at internal_cost (25), byte-identical to before this fix, got %', (select value_amount from app.loyalty_benefit_entitlements where id = v_compat_redemption.benefit_entitlement_id);
    end if;
  end;
end $$;

\echo '>> ISS-2026-132 item 1 (2026-09-02): a genuine, unassisted customer_user (Epsilon) redemption never auto-approves for a reward without auto_approve_customer_redemption; toggling it on requires LYL:Configure; it STILL falls back to pending_approval with no auto-approval principal configured; app.set_loyalty_redemption_auto_approval_principal rejects a target that does not hold LYL:Edit; once BOTH the toggle and a real, LYL:Edit-holding principal are configured, Epsilon''s own genuinely unassisted submission composes synchronously -- decided_by names the system principal, never Epsilon herself'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rdm1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000344001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000344004';
  v_customer_epsilon uuid := '00000000-0000-0000-0000-000000344040';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rdm1') and name = 'Redemption Program');
  v_loyalty_account_epsilon uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rdm1') and legal_name = 'Rdm Account Epsilon'));
  v_row app.loyalty_rewards;
  v_reward app.loyalty_rewards;
  v_redemption app.loyalty_redemptions;
  v_principal app.loyalty_redemption_auto_approval_principals;
begin
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Auto Approve Voucher', 'discount_voucher', 'Opt-in auto-approve fixture.', 'Terms.', null, 5, null, null, null, null, v_manager1, 'manager1');
  v_row := app.set_loyalty_reward_voucher_value_config(v_tenant1, v_row.id, v_row.record_version, 'fixed_amount', 12, null, null, v_manager1, 'manager1');
  v_reward := app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');

  -- auto_approve_customer_redemption defaults false -- never the default
  -- for a newly-created reward. Epsilon''s own genuine self-service
  -- submission lands pending_approval, exactly the pre-existing "main flow
  -- B" shape.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_reward.id, 'auto-approve-attempt-1-off', v_customer_epsilon, 'epsilon');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected pending_approval for a reward with auto_approve_customer_redemption=false (the default), got %', v_redemption.status;
  end if;

  -- Toggling requires LYL:Configure -- v_plain1 (zero LYL grant) is denied.
  begin
    perform app.set_loyalty_reward_auto_approve_customer_redemption(v_tenant1, v_reward.id, v_reward.record_version, true, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for a no-LYL-grant actor toggling auto-approve';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_reward := app.set_loyalty_reward_auto_approve_customer_redemption(v_tenant1, v_reward.id, v_reward.record_version, true, v_manager1, 'manager1');
  if v_reward.auto_approve_customer_redemption is not true then
    raise exception 'assertion failed: expected auto_approve_customer_redemption=true after the toggle, got %', v_reward.auto_approve_customer_redemption;
  end if;

  -- Toggle is ON, but NO auto-approval principal is configured yet for
  -- this tenant -- Epsilon''s submission STILL gracefully falls back to
  -- pending_approval, never a hard failure and never a bypass.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_reward.id, 'auto-approve-attempt-2-no-principal', v_customer_epsilon, 'epsilon');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected pending_approval with no auto-approval principal configured (opt-in toggle alone is not enough), got %', v_redemption.status;
  end if;

  -- A target that does not hold LYL:Edit cannot be designated the
  -- principal -- the ONE guardrail this fix adds.
  begin
    perform app.set_loyalty_redemption_auto_approval_principal(v_tenant1, v_plain1, 'bogus principal', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_principal for a target that does not hold LYL:Edit';
  exception when others then if sqlerrm not like 'invalid_principal%' then raise; end if;
  end;

  -- Reading the principal before one is configured requires LYL:View but
  -- returns no row; v_plain1 (zero LYL grant) is denied outright.
  begin
    perform app.get_loyalty_redemption_auto_approval_principal(v_tenant1, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for a no-LYL-grant actor reading the auto-approval principal';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_principal := app.set_loyalty_redemption_auto_approval_principal(v_tenant1, v_manager1, 'manager1-auto-approver', v_manager1, 'manager1');
  if v_principal.auth_user_id <> v_manager1 or v_principal.principal_label <> 'manager1-auto-approver' then
    raise exception 'assertion failed: expected the configured principal to persist, got %', to_jsonb(v_principal);
  end if;

  -- BOTH the reward toggle AND a real, LYL:Edit-holding principal are now
  -- configured -- Epsilon''s own genuinely unassisted, zero-staff-touch
  -- submission composes SYNCHRONOUSLY: status=fulfilled in the SAME call,
  -- and decided_by names the SYSTEM principal, never Epsilon herself --
  -- the shared LYL:Edit-gated primitives were never called with Epsilon''s
  -- own identity, exactly as ADR-0024 Part B requires.
  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_epsilon, v_reward.id, 'auto-approve-attempt-3-live', v_customer_epsilon, 'epsilon');
  if v_redemption.status <> 'fulfilled' or v_redemption.benefit_entitlement_id is null then
    raise exception 'assertion failed: expected Epsilon''s own submission to auto-compose to fulfilled once toggle+principal are both configured, got %', v_redemption;
  end if;
  if v_redemption.decided_by <> 'system:manager1-auto-approver' then
    raise exception 'assertion failed: expected decided_by to name the system principal (system:manager1-auto-approver), never Epsilon herself, got %', v_redemption.decided_by;
  end if;
  if v_redemption.created_by <> 'epsilon' then
    raise exception 'assertion failed: fixture error -- expected created_by=epsilon (the real submitting actor), got %', v_redemption.created_by;
  end if;
  if not exists (select 1 from app.loyalty_benefit_entitlements where id = v_redemption.benefit_entitlement_id and value_amount = 12) then
    raise exception 'assertion failed: expected the auto-approved entitlement to be worth its own configured voucher_face_value (12)';
  end if;
end $$;

\echo 'ALL PASSED: CPL-321 Redemption Approval and Fulfillment'
