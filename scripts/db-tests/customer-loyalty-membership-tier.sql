-- Real, executable test evidence for CPL-317 (CG-S13-CPL-019, Prompt 317,
-- "Membership Tier") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- UUID range 00000000-0000-0000-0000-0000003380xx (tenant tier1) /
-- 00000000-0000-0000-0000-0000003390xx (tenant tier2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Covers, live: (a) THRESHOLD-EDGE CORRECTNESS -- one unit below a
-- threshold does not qualify, exactly at a threshold does; (b) a TIER-
-- DEFINITION VERSION CHANGE does not retroactively rewrite a historical
-- tier movement -- the movement keeps the version it was evaluated under,
-- even after that version is superseded; (c) IDEMPOTENT RECALCULATION --
-- calling app.recalculate_customer_loyalty_tier repeatedly with no
-- underlying eligibility change never inserts a spurious movement row;
-- (d) a FRAUD-HELD account's benefits are correctly suppressed (empty
-- object plus a generic customer-safe message, never the real internal
-- hold_reason) in the customer-facing tier card, while tier tracking
-- itself remains unaffected by the hold (orthogonality); (e) CROSS-TENANT/
-- CROSS-ACCOUNT isolation; plus the downgrade grace-period policy (blocked
-- during the window, applied once elapsed), upgrade-is-immediate, tier
-- definition draft/publish/supersede lifecycle correctness, LYL:*
-- authority boundaries, raw-table RLS / raw-function-grant defense in
-- depth, the actor-identity session cross-check on every one of the 11 new
-- RPCs, and keyset pagination.

\set ON_ERROR_STOP on

\echo '>> setup: tenant tier1 (org unit, roles: Loyalty Manager [LYL Create/Edit/View/Configure], Loyalty Viewer [LYL View only], Plain User [no LYL grant]; customer accounts Alpha/Beta/Edge/Gap/BadDim; customer_user identities for Alpha/Beta; an impersonator identity), tenant tier2 (its own Loyalty Manager, customer account Gamma)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_edge uuid;
  v_account_gap uuid;
  v_account_baddim uuid;
  v_account_gamma uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000338002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000338003';
  v_impersonator uuid := '00000000-0000-0000-0000-000000338050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000338010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000338020';
  v_manager2 uuid := '00000000-0000-0000-0000-000000339001';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000339010';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_viewer_role1 uuid;
  v_viewer_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@tier1.test'),
    (v_viewer1, 'viewer1@tier1.test'),
    (v_plain1, 'plain1@tier1.test'),
    (v_impersonator, 'impersonator@tier1.test'),
    (v_customer_alpha, 'customer-alpha@tier1.test'),
    (v_customer_beta, 'customer-beta@tier1.test'),
    (v_manager2, 'manager2@tier2.test'),
    (v_customer_gamma, 'customer-gamma@tier2.test');

  perform app.provision_tenant('tier1', 'Tier Test Tenant One', 'idem-tier1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'tier1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'TIER1-CO', 'Tier1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'TIER1-CO');

  perform app.provision_tenant('tier2', 'Tier Test Tenant Two', 'idem-tier2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'tier2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'TIER2-CO', 'Tier2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'TIER2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@tier1.test', 'Tier1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@tier1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer1@tier1.test', 'Tier1 Viewer', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer1@tier1.test'), 'active', 'onboarded', 'tester');
  v_viewer_role1 := (app.create_role(v_tenant1, 'Loyalty Viewer', 'LYL:View only, never Configure/Create/Edit', 'tester')).id;
  v_viewer_draft1 := app.create_role_version(v_viewer_role1, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role1 and status = 'published'), v_viewer1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@tier1.test', 'Tier1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@tier1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@tier1.test', 'Tier1 Impersonator', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@tier1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_impersonator, v_manager1, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Tier Account Alpha', 'tier-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Tier Account Beta', 'tier-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Tier Account Edge', 'tier-edge-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_edge;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Tier Account Gap', 'tier-gap-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gap;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Tier Account BadDim', 'tier-baddim-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_baddim;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Tier Account Gamma', 'tier-gamma-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_gamma;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@tier1.test', 'Tier Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@tier1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@tier1.test', 'Tier Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@tier1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@tier2.test', 'Tier2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@tier2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_gamma, 'customer-gamma@tier2.test', 'Tier Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@tier2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant2, v_account_gamma::text, 'tester');

  -- AR open items (direct fixture insert, mirrors CPL-311/CPL-316's own
  -- established precedent -- app.finance_ar_open_items itself is not under
  -- test here). Alpha: 338101 (500, paid), 338102 (500, paid). Edge: 338103
  -- (999, paid), 338104 (1, paid). Beta: 338105 (700, paid -- deliberately
  -- above Silver v2's own 600 threshold, since by the time Beta's own
  -- fraud-hold test section runs, the earlier version-change test section
  -- has already published Silver v2 in this SAME shared program).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000338101', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000338501', 'USD', 500, 500, 'paid', false, '2026-08-01', '2026-08-31', 'tester'),
    ('00000000-0000-0000-0000-000000338102', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000338502', 'USD', 500, 500, 'paid', false, '2026-08-02', '2026-09-01', 'tester'),
    ('00000000-0000-0000-0000-000000338103', v_tenant1, v_account_edge, 'invoice', '00000000-0000-0000-0000-000000338503', 'USD', 999, 999, 'paid', false, '2026-08-03', '2026-09-02', 'tester'),
    ('00000000-0000-0000-0000-000000338104', v_tenant1, v_account_edge, 'invoice', '00000000-0000-0000-0000-000000338504', 'USD', 1, 1, 'paid', false, '2026-08-04', '2026-09-03', 'tester'),
    ('00000000-0000-0000-0000-000000338105', v_tenant1, v_account_beta, 'invoice', '00000000-0000-0000-0000-000000338505', 'USD', 700, 700, 'paid', false, '2026-08-05', '2026-09-04', 'tester');
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000339101', v_tenant2, v_account_gamma, 'invoice', '00000000-0000-0000-0000-000000339501', 'USD', 500, 500, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
end $$;

\echo '>> fixture: program "Tier Rewards" (tenant1) with a published earning rule (rate=1, 1 point per $1) and three published tiers -- Bronze(rank1, threshold=0), Silver(rank2, threshold=500), Gold(rank3, threshold=1000, review_period_days=30); Alpha/Beta/Edge enrolled'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Beta');
  v_account_edge uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Edge');
  v_program app.loyalty_programs;
  v_rule_draft app.loyalty_program_rule_versions;
  v_bronze_draft app.loyalty_tier_definitions;
  v_silver_draft app.loyalty_tier_definitions;
  v_gold_draft app.loyalty_tier_definitions;
begin
  v_program := app.create_loyalty_program(v_tenant1, 'Tier Rewards', 'Earn on every paid invoice.', v_manager1, 'manager1');
  perform app.update_loyalty_program_status(v_tenant1, v_program.id, 1, 'active', v_manager1, 'manager1');

  v_rule_draft := app.create_loyalty_program_rule_version(v_tenant1, v_program.id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager1, 'manager1');
  perform app.publish_loyalty_program_rule_version(v_tenant1, v_rule_draft.id, v_rule_draft.record_version, null, v_manager1, 'manager1');

  v_bronze_draft := app.create_loyalty_tier_definition(v_tenant1, v_program.id, 'Bronze', 1, 'earning_amount_ytd', 0, jsonb_build_object('newsletter', true), 0, v_manager1, 'manager1');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_bronze_draft.id, v_bronze_draft.record_version, null, v_manager1, 'manager1');

  v_silver_draft := app.create_loyalty_tier_definition(v_tenant1, v_program.id, 'Silver', 2, 'earning_amount_ytd', 500, jsonb_build_object('free_shipping', true), 0, v_manager1, 'manager1');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_silver_draft.id, v_silver_draft.record_version, null, v_manager1, 'manager1');

  v_gold_draft := app.create_loyalty_tier_definition(v_tenant1, v_program.id, 'Gold', 3, 'earning_amount_ytd', 1000, jsonb_build_object('priority_support', true), 30, v_manager1, 'manager1');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_gold_draft.id, v_gold_draft.record_version, null, v_manager1, 'manager1');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program.id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program.id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_edge, v_program.id, v_manager1, 'manager1');
end $$;

\echo '>> app.create_loyalty_tier_definition / app.update_loyalty_tier_definition_draft: LYL:Create/Edit required (Plain User denied); invalid inputs rejected; at most one draft per (program, tier_name); at most one published tier per rank (tier_rank_conflict)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000338003';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_draft app.loyalty_tier_definitions;
  v_conflict_draft app.loyalty_tier_definitions;
begin
  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Denied', 1, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, '', 1, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_tier_name for a blank name';
  exception when others then if sqlerrm not like 'invalid_tier_name%' then raise; end if;
  end;

  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'BadRank', 0, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_tier_rank for a non-positive rank';
  exception when others then if sqlerrm not like 'invalid_tier_rank%' then raise; end if;
  end;

  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'BadThreshold', 5, 'earning_amount_ytd', -1, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_threshold_value for a negative threshold';
  exception when others then if sqlerrm not like 'invalid_threshold_value%' then raise; end if;
  end;

  -- draft_already_exists: two open drafts for the same tier_name.
  v_draft := app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'ScratchDraft', 90, 'earning_amount_ytd', 99999, '{}'::jsonb, 0, v_manager1, 'manager1');
  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'ScratchDraft', 91, 'earning_amount_ytd', 99998, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected draft_already_exists for a second open draft on the same tier_name';
  exception when others then if sqlerrm not like 'draft_already_exists%' then raise; end if;
  end;

  begin
    perform app.update_loyalty_tier_definition_draft(v_tenant1, v_draft.id, 99, 'ScratchDraft', 90, 'earning_amount_ytd', 99999, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency.
  begin
    perform app.update_loyalty_tier_definition_draft(v_tenant1, v_draft.id, null, 'ScratchDraft', 90, 'earning_amount_ytd', 12345, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select threshold_value from app.loyalty_tier_definitions where id = v_draft.id) <> 99999
     or (select record_version from app.loyalty_tier_definitions where id = v_draft.id) <> v_draft.record_version then
    raise exception 'assertion failed: a NULL expected_version must never actually change the row -- threshold_value=%, record_version=%',
      (select threshold_value from app.loyalty_tier_definitions where id = v_draft.id), (select record_version from app.loyalty_tier_definitions where id = v_draft.id);
  end if;

  -- tier_rank_conflict: a DIFFERENT tier_name attempting to publish at an
  -- already-published rank (Bronze already holds rank 1).
  v_conflict_draft := app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'BronzeClone', 1, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency.
  begin
    perform app.publish_loyalty_tier_definition(v_tenant1, v_conflict_draft.id, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_tier_definitions where id = v_conflict_draft.id) <> 'draft' then
    raise exception 'assertion failed: a NULL expected_version must never actually publish the draft -- status=%', (select status from app.loyalty_tier_definitions where id = v_conflict_draft.id);
  end if;

  begin
    perform app.publish_loyalty_tier_definition(v_tenant1, v_conflict_draft.id, v_conflict_draft.record_version, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected tier_rank_conflict -- rank 1 is already held by the published Bronze tier';
  exception when others then if sqlerrm not like 'tier_rank_conflict%' then raise; end if;
  end;

  -- publish requires LYL:Configure, not merely LYL:Edit/Create.
  begin
    perform app.update_loyalty_tier_definition_draft(v_tenant1, v_draft.id, v_draft.record_version, 'ScratchDraft', 90, 'earning_amount_ytd', 99999, '{}'::jsonb, 0, '00000000-0000-0000-0000-000000338002', 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not satisfy LYL:Edit';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> (c) IDEMPOTENT RECALCULATION + INITIAL ASSIGNMENT: Alpha''s first recalculation (sum=0) resolves Bronze via a real initial movement; a second call with nothing changed is a safe no-op (no new row)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000338003';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_bronze_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_movement app.loyalty_account_tier_movements;
  v_repeat app.loyalty_account_tier_movements;
  v_count integer;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;

  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'initial' or v_movement.to_tier_id <> v_bronze_id or v_movement.from_tier_id is not null then
    raise exception 'assertion failed: expected an initial movement to Bronze with from_tier_id null, got %', v_movement;
  end if;

  select count(*) into v_count from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE movement row after the first recalculation, got %', v_count;
  end if;

  -- Idempotent: nothing changed (sum still 0) -- a safe no-op, no new row.
  v_repeat := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_repeat.id <> v_movement.id then
    raise exception 'assertion failed: expected the IDENTICAL movement row on an unchanged recalculation, got a different id %', v_repeat.id;
  end if;
  select count(*) into v_count from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the row count to remain 1 after an idempotent no-op recalculation, got %', v_count;
  end if;
end $$;

\echo '>> Alpha upgrades to Silver (exactly at the 500 threshold) then Gold (exactly at the 1000 threshold, review_period_days=30) -- both exact-boundary upgrades apply immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_silver_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Silver' and status = 'published');
  v_gold_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Gold' and status = 'published');
  v_bronze_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_movement app.loyalty_account_tier_movements;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;

  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000338101', v_manager1, 'manager1');
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'upgrade' or v_movement.to_tier_id <> v_silver_id or v_movement.from_tier_id <> v_bronze_id then
    raise exception 'assertion failed: expected an upgrade Bronze->Silver at exactly the 500 threshold, got %', v_movement;
  end if;
  if (v_movement.evaluation_snapshot ->> 'computed_amount')::numeric <> 500 then
    raise exception 'assertion failed: expected evaluation_snapshot.computed_amount=500, got %', v_movement.evaluation_snapshot;
  end if;

  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000338102', v_manager1, 'manager1');
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'upgrade' or v_movement.to_tier_id <> v_gold_id or v_movement.from_tier_id <> v_silver_id then
    raise exception 'assertion failed: expected an upgrade Silver->Gold at exactly the 1000 threshold, got %', v_movement;
  end if;
  if v_movement.next_review_at < now() + interval '29 days' then
    raise exception 'assertion failed: expected Gold''s own 30-day review_period_days to stamp next_review_at ~30 days out, got %', v_movement.next_review_at;
  end if;
end $$;

\echo '>> DOWNGRADE GRACE-PERIOD POLICY: a downgrade candidate is a safe no-op while inside Gold''s own 30-day review window; once the window has elapsed (simulated by advancing next_review_at into the past), the SAME recalculation call performs the downgrade to whatever is CURRENTLY eligible'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_gold_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Gold' and status = 'published');
  v_silver_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Silver' and status = 'published');
  v_gold_movement app.loyalty_account_tier_movements;
  v_movement app.loyalty_account_tier_movements;
  v_count_before integer;
  v_count_after integer;
  -- ISS-2026-137 fix (supabase/migrations/20260828060000): app.loyalty_
  -- account_tier_movements is now append-only-protected (the identical
  -- ISS-2026-130 Supreme-Admin-override gate the other 5 Loyalty ledger
  -- tables already carry) -- the direct fixture UPDATE below now requires a
  -- genuine Supreme Admin actor context, mirroring scripts/db-tests/
  -- customer-portal-loyalty-ledger-supreme-admin-override.sql's own
  -- established convention exactly, rather than a bare superuser session.
  v_supreme uuid := '00000000-0000-0000-0000-000000338099';
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;
  select * into v_gold_movement from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id order by created_at desc, id desc limit 1;
  if v_gold_movement.to_tier_id <> v_gold_id then
    raise exception 'assertion failed: fixture setup error, expected Alpha currently at Gold, got to_tier_id=%', v_gold_movement.to_tier_id;
  end if;

  -- Reverse the second invoice -- earning drops back to 500, a downgrade candidate.
  perform app.reverse_loyalty_earning_event(
    v_tenant1,
    (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000338102'),
    'test: simulate a payment reversal', 'reversal:338102', v_manager1, 'manager1'
  );

  select count(*) into v_count_before from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  select count(*) into v_count_after from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_movement.id <> v_gold_movement.id or v_count_after <> v_count_before then
    raise exception 'assertion failed: expected a safe no-op (still the Gold movement, no new row) while inside the 30-day review window, got % (count % -> %)', v_movement, v_count_before, v_count_after;
  end if;

  -- Simulate the review window having elapsed (direct fixture manipulation
  -- -- never through the RPC, which never lets a caller set next_review_at
  -- directly). ISS-2026-137 fix: this table is now append-only-protected,
  -- so the direct UPDATE requires a genuine Supreme Admin actor context
  -- (app.protect_loyalty_ledger_append_only) -- a real, disposable Supreme
  -- Admin identity, used for this ONE statement only, then reset.
  insert into auth.users (id, email) values (v_supreme, 'supreme@tier1.test');
  perform app.link_auth_identity(v_supreme, v_tenant1, 'tester', 'active');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');
  perform set_config('request.jwt.claims', json_build_object('sub', v_supreme::text, 'role', 'authenticated')::text, true);
  update app.loyalty_account_tier_movements set next_review_at = now() - interval '1 day' where id = v_gold_movement.id;
  perform set_config('request.jwt.claims', 'null', true);

  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'downgrade' or v_movement.to_tier_id <> v_silver_id or v_movement.from_tier_id <> v_gold_id then
    raise exception 'assertion failed: expected a downgrade Gold->Silver once the review window elapsed, got %', v_movement;
  end if;
  select count(*) into v_count_after from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_count_after <> v_count_before + 1 then
    raise exception 'assertion failed: expected exactly ONE new movement row for the downgrade, got % (was %)', v_count_after, v_count_before;
  end if;

  -- The Gold movement row itself is untouched by the downgrade (append-only -- a correction is a NEW row).
  if (select movement_type from app.loyalty_account_tier_movements where id = v_gold_movement.id) <> 'upgrade' then
    raise exception 'assertion failed: expected the original Gold movement row''s own movement_type unchanged (upgrade), the downgrade must be a NEW row';
  end if;

  -- Idempotent again: nothing changed now.
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  select count(*) into v_count_after from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_count_after <> v_count_before + 1 then
    raise exception 'assertion failed: expected the row count to stay at % after a further idempotent no-op call, got %', v_count_before + 1, v_count_after;
  end if;
end $$;

\echo '>> (b) TIER-DEFINITION VERSION CHANGE DOES NOT RETROACTIVELY REWRITE A HISTORICAL MOVEMENT: publishing Silver v2 (threshold raised to 600) leaves Alpha''s already-recorded downgrade-to-Silver movement''s own to_tier_id/tier_definition_version_id/evaluation_snapshot COMPLETELY unchanged, and Silver v1''s own recorded facts (tier_rank/threshold_value) are never mutated -- only status/effective_to change'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_silver_v1_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Silver' and status = 'published');
  v_bronze_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_downgrade_movement_before app.loyalty_account_tier_movements;
  v_downgrade_movement_after app.loyalty_account_tier_movements;
  v_silver_v1_reloaded app.loyalty_tier_definitions;
  v_silver_v2_draft app.loyalty_tier_definitions;
  v_silver_v2 app.loyalty_tier_definitions;
  v_movement app.loyalty_account_tier_movements;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;
  select * into v_downgrade_movement_before from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id order by created_at desc, id desc limit 1;
  if v_downgrade_movement_before.movement_type <> 'downgrade' then
    raise exception 'assertion failed: fixture setup error, expected Alpha''s latest movement to be the Gold->Silver downgrade, got %', v_downgrade_movement_before;
  end if;

  v_silver_v2_draft := app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Silver', 2, 'earning_amount_ytd', 600, jsonb_build_object('free_shipping', true, 'lounge_access', true), 0, v_manager1, 'manager1');
  v_silver_v2 := app.publish_loyalty_tier_definition(v_tenant1, v_silver_v2_draft.id, v_silver_v2_draft.record_version, null, v_manager1, 'manager1');
  if v_silver_v2.status <> 'published' or v_silver_v2.version_number <> 2 or v_silver_v2.threshold_value <> 600 then
    raise exception 'assertion failed: expected Silver v2 published (threshold=600), got %', v_silver_v2;
  end if;

  select * into v_silver_v1_reloaded from app.loyalty_tier_definitions where id = v_silver_v1_id;
  if v_silver_v1_reloaded.status <> 'superseded' or v_silver_v1_reloaded.effective_to is null or v_silver_v1_reloaded.threshold_value <> 500 or v_silver_v1_reloaded.tier_rank <> 2 then
    raise exception 'assertion failed: expected Silver v1 superseded (threshold_value STILL 500, tier_rank STILL 2, effective_to set), got %', v_silver_v1_reloaded;
  end if;

  -- The core business-rule proof: the historical downgrade movement, re-read
  -- fresh, is byte-for-byte identical to before Silver v2 was ever published.
  select * into v_downgrade_movement_after from app.loyalty_account_tier_movements where id = v_downgrade_movement_before.id;
  if v_downgrade_movement_after.to_tier_id <> v_downgrade_movement_before.to_tier_id
    or v_downgrade_movement_after.to_tier_id <> v_silver_v1_id
    or v_downgrade_movement_after.tier_definition_version_id <> v_silver_v1_id
    or v_downgrade_movement_after.evaluation_snapshot <> v_downgrade_movement_before.evaluation_snapshot
  then
    raise exception 'assertion failed: expected the historical movement COMPLETELY unchanged (still pointing at Silver v1), got % (was %)', v_downgrade_movement_after, v_downgrade_movement_before;
  end if;

  -- A NEW recalculation, now that Silver v2 (threshold=600) is the published
  -- version, correctly re-evaluates against the CURRENT set: Alpha's own sum
  -- is still 500 (< Silver v2's 600), so the newly eligible tier is Bronze.
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'downgrade' or v_movement.to_tier_id <> v_bronze_id then
    raise exception 'assertion failed: expected a downgrade to Bronze now that Silver v2 requires 600 (Alpha has 500), got %', v_movement;
  end if;
end $$;

\echo '>> (a) THRESHOLD-EDGE CORRECTNESS (dedicated, isolated Edge account): one unit below the Gold threshold (999) does NOT qualify for Gold; exactly at the threshold (1000) DOES'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_edge uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Edge');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_gold_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Gold' and status = 'published');
  v_silver_v1_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Silver' and version_number = 1);
  v_movement app.loyalty_account_tier_movements;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_edge;
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'initial' then
    raise exception 'assertion failed: expected Edge''s initial movement, got %', v_movement;
  end if;

  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000338103', v_manager1, 'manager1');
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.to_tier_id = v_gold_id then
    raise exception 'assertion failed: 999 is ONE UNIT BELOW the 1000 Gold threshold -- must NOT qualify for Gold, got %', v_movement;
  end if;
  if (v_movement.evaluation_snapshot ->> 'computed_amount')::numeric <> 999 then
    raise exception 'assertion failed: expected computed_amount=999, got %', v_movement.evaluation_snapshot;
  end if;

  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000338104', v_manager1, 'manager1');
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.to_tier_id <> v_gold_id or v_movement.movement_type <> 'upgrade' then
    raise exception 'assertion failed: 1000 is EXACTLY AT the Gold threshold -- must qualify, got %', v_movement;
  end if;
  if (v_movement.evaluation_snapshot ->> 'computed_amount')::numeric <> 1000 then
    raise exception 'assertion failed: expected computed_amount=1000, got %', v_movement.evaluation_snapshot;
  end if;
end $$;

\echo '>> app.loyalty_account_closed: recalculation is rejected once the underlying loyalty account is closed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_edge uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Edge');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account app.loyalty_accounts;
begin
  select * into v_loyalty_account from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_edge;
  perform app.set_loyalty_account_status(v_tenant1, v_loyalty_account.id, v_loyalty_account.record_version, 'closed', 'test: close Edge', v_manager1, 'manager1');

  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account.id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected loyalty_account_closed for a closed loyalty account';
  exception when others then if sqlerrm not like 'loyalty_account_closed%' then raise; end if;
  end;
end $$;

\echo '>> fixture: "Gapped Program" (single Elite tier, threshold=10000, no base rung) and "Bad Dimension Program" (single tier using an unsupported threshold_dimension) -- each with its own dedicated account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_company1 uuid := (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'tier1') and code = 'TIER1-CO');
  v_account_gap uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Gap');
  v_account_baddim uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account BadDim');
  v_gapped_program app.loyalty_programs;
  v_baddim_program app.loyalty_programs;
  v_elite_draft app.loyalty_tier_definitions;
  v_weird_draft app.loyalty_tier_definitions;
begin
  v_gapped_program := app.create_loyalty_program(v_tenant1, 'Gapped Program', null, v_manager1, 'manager1');
  perform app.update_loyalty_program_status(v_tenant1, v_gapped_program.id, 1, 'active', v_manager1, 'manager1');
  v_elite_draft := app.create_loyalty_tier_definition(v_tenant1, v_gapped_program.id, 'Elite', 1, 'earning_amount_ytd', 10000, '{}'::jsonb, 0, v_manager1, 'manager1');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_elite_draft.id, v_elite_draft.record_version, null, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gap, v_gapped_program.id, v_manager1, 'manager1');

  v_baddim_program := app.create_loyalty_program(v_tenant1, 'Bad Dimension Program', null, v_manager1, 'manager1');
  perform app.update_loyalty_program_status(v_tenant1, v_baddim_program.id, 1, 'active', v_manager1, 'manager1');
  v_weird_draft := app.create_loyalty_tier_definition(v_tenant1, v_baddim_program.id, 'Weird', 1, 'transaction_count_lifetime', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_weird_draft.id, v_weird_draft.record_version, null, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_baddim, v_baddim_program.id, v_manager1, 'manager1');
end $$;

\echo '>> no_eligible_tier_definition: a program with no base (threshold=0) tier raises a real error rather than silently applying nothing'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_gap uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Gap');
  v_gapped_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Gapped Program');
  v_loyalty_account_id uuid;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_gapped_program_id and customer_account_id = v_account_gap;
  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected no_eligible_tier_definition -- sum=0 does not meet Elite''s own 10000 threshold and no lower tier exists';
  exception when others then if sqlerrm not like 'no_eligible_tier_definition%' then raise; end if;
  end;
end $$;

\echo '>> unsupported_threshold_dimension: a published tier definition using a dimension this checkpoint does not implement is rejected loudly, before any eligible-tier resolution'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_account_baddim uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account BadDim');
  v_baddim_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Bad Dimension Program');
  v_loyalty_account_id uuid;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_baddim_program_id and customer_account_id = v_account_baddim;
  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected unsupported_threshold_dimension for the Weird tier''s own transaction_count_lifetime dimension';
  exception when others then if sqlerrm not like 'unsupported_threshold_dimension%' then raise; end if;
  end;
end $$;

\echo '>> (d) FRAUD HOLD: Beta''s tier benefits are suppressed (empty object + generic customer-safe message, NEVER the real internal hold_reason) while held; tier tracking itself is unaffected by the hold (orthogonality -- a recalculation while held still applies normally); benefits reappear correctly on release; hold is idempotent (a repeat hold call preserves the ORIGINAL reason); release of a never-held account is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000338003';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000338020';
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Beta');
  v_account_edge uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Edge');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_loyalty_account_id uuid;
  v_edge_loyalty_account_id uuid;
  v_hold app.loyalty_account_tier_holds;
  v_hold_repeat app.loyalty_account_tier_holds;
  v_movement app.loyalty_account_tier_movements;
  v_card record;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_beta;
  select id into v_edge_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_edge;

  perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');

  select * into v_card from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_beta, v_account_beta);
  if v_card.current_tier_name <> 'Bronze' or v_card.is_benefits_suspended <> false or v_card.benefits <> jsonb_build_object('newsletter', true) then
    raise exception 'assertion failed: expected Beta at Bronze, not suspended, real benefits shown, got %', v_card;
  end if;

  begin
    perform app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, 'Suspected fraud on recent transactions', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User on hold';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, '', v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for an empty hold reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_hold := app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, 'Suspected fraud on recent transactions', v_manager1, 'manager1');
  if v_hold.is_held <> true or v_hold.hold_reason <> 'Suspected fraud on recent transactions' then
    raise exception 'assertion failed: expected a real hold row, got %', v_hold;
  end if;

  -- Idempotent hold: a second hold call with a DIFFERENT reason preserves the ORIGINAL.
  v_hold_repeat := app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, 'a different, later reason', v_manager1, 'manager1');
  if v_hold_repeat.id <> v_hold.id or v_hold_repeat.hold_reason <> 'Suspected fraud on recent transactions' then
    raise exception 'assertion failed: expected the repeat hold to be a no-op preserving the ORIGINAL reason, got %', v_hold_repeat;
  end if;

  select * into v_card from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_beta, v_account_beta);
  if v_card.is_benefits_suspended <> true or v_card.benefits <> '{}'::jsonb then
    raise exception 'assertion failed: expected benefits suppressed to {} while held, got %', v_card;
  end if;
  if v_card.benefits_suspended_reason like '%Suspected fraud%' or v_card.benefits_suspended_reason is null then
    raise exception 'assertion failed: expected a GENERIC customer-safe message, NEVER the real internal hold_reason, got %', v_card.benefits_suspended_reason;
  end if;

  -- Orthogonality: recalculation still applies normally while held. Beta's
  -- own invoice (700) is deliberately above Silver v2's own 600 threshold
  -- (the earlier version-change test section already published Silver v2
  -- in this SAME shared program, superseding v1's own 500 threshold).
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000338105', v_manager1, 'manager1');
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  if v_movement.movement_type <> 'upgrade' then
    raise exception 'assertion failed: expected tier recalculation to apply normally despite the hold (design decision 5, orthogonality), got %', v_movement;
  end if;

  select * into v_card from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_beta, v_account_beta);
  if v_card.current_tier_name <> 'Silver' or v_card.is_benefits_suspended <> true or v_card.benefits <> '{}'::jsonb then
    raise exception 'assertion failed: expected Beta now at Silver (tier tracking unaffected) but STILL benefit-suspended, got %', v_card;
  end if;

  -- release_loyalty_account_tier_benefits on a NEVER-held account is rejected.
  begin
    perform app.release_loyalty_account_tier_benefits(v_tenant1, v_edge_loyalty_account_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected loyalty_account_tier_hold_not_found for an account that was never held';
  exception when others then if sqlerrm not like 'loyalty_account_tier_hold_not_found%' then raise; end if;
  end;

  perform app.release_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
  select * into v_card from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_beta, v_account_beta);
  if v_card.is_benefits_suspended <> false or v_card.benefits <> jsonb_build_object('free_shipping', true, 'lounge_access', true) then
    raise exception 'assertion failed: expected Beta''s real Silver v2 benefits restored after release, got %', v_card;
  end if;

  -- Idempotent release: releasing an already-released account is a safe no-op.
  perform app.release_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
end $$;

\echo '>> (e) CROSS-TENANT/CROSS-ACCOUNT ISOLATION: tenant tier2''s own Loyalty Manager cannot read/act on tenant tier1''s tier definitions/movements/holds (own tenant_id -> insufficient_authority, borrowed tier1 id inside tier2''s own scope -> not_found); Gamma (tier2) never sees Alpha/Beta''s own tier cards'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'tier2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000339001';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000339010';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier2') and legal_name = 'Tier Account Gamma');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_tier_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_loyalty_account_alpha uuid;
  v_card_count integer;
begin
  select id into v_loyalty_account_alpha from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;

  begin
    perform app.get_loyalty_tier_definition(v_tenant1, v_tier_id, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority -- manager2 holds no role assignment in tenant1 at all';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_tier_definition(v_tenant2, v_tier_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_tier_definition_not_found -- a tier1 id does not exist inside tenant2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_tier_definition_not_found%' then raise; end if;
  end;

  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant2, v_loyalty_account_alpha, v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_account_not_found -- a tier1 loyalty account does not exist inside tenant2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;

  begin
    perform app.hold_loyalty_account_tier_benefits(v_tenant2, v_loyalty_account_alpha, 'cross tenant attempt', v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_account_not_found for a cross-tenant hold attempt';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;

  -- Gamma's own card, in her own tenant -- program not yet created for tier2
  -- in this fixture, so this is a real deny-by-default empty result, not an
  -- error. Confirms zero rows leak from tier1's own Alpha/Beta cards.
  select count(*) into v_card_count from app.list_customer_portal_loyalty_tier_cards(v_tenant2, v_customer_gamma, v_account_gamma);
  if v_card_count <> 0 then
    raise exception 'assertion failed: expected Gamma to see zero tier cards (never enrolled in tier2), got %', v_card_count;
  end if;

  -- Gamma may not read tier1's own cards even by passing tier1's own tenant_id -- resolve_customer_account_scope returns empty for her there.
  select count(*) into v_card_count from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_gamma);
  if v_card_count <> 0 then
    raise exception 'assertion failed: expected Gamma to see zero tier1 tier cards (no membership there at all), got %', v_card_count;
  end if;
end $$;

\echo '>> Gamma (tenant2) enrolls in her own tenant''s own program with a Gold-only tier and earns her own way to it, entirely independent of tenant1'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'tier2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000339001';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000339010';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier2') and legal_name = 'Tier Account Gamma');
  v_program app.loyalty_programs;
  v_rule_draft app.loyalty_program_rule_versions;
  v_tier_draft app.loyalty_tier_definitions;
  v_loyalty_account_id uuid;
  v_movement app.loyalty_account_tier_movements;
  v_card record;
begin
  v_program := app.create_loyalty_program(v_tenant2, 'Gamma Rewards', null, v_manager2, 'manager2');
  perform app.update_loyalty_program_status(v_tenant2, v_program.id, 1, 'active', v_manager2, 'manager2');
  v_rule_draft := app.create_loyalty_program_rule_version(v_tenant2, v_program.id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager2, 'manager2');
  perform app.publish_loyalty_program_rule_version(v_tenant2, v_rule_draft.id, v_rule_draft.record_version, null, v_manager2, 'manager2');
  v_tier_draft := app.create_loyalty_tier_definition(v_tenant2, v_program.id, 'Base', 1, 'earning_amount_ytd', 0, jsonb_build_object('welcome_gift', true), 0, v_manager2, 'manager2');
  perform app.publish_loyalty_tier_definition(v_tenant2, v_tier_draft.id, v_tier_draft.record_version, null, v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_gamma, v_program.id, v_manager2, 'manager2');

  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant2 and program_id = v_program.id and customer_account_id = v_account_gamma;
  v_movement := app.recalculate_customer_loyalty_tier(v_tenant2, v_loyalty_account_id, v_manager2, 'manager2');
  if v_movement.movement_type <> 'initial' then
    raise exception 'assertion failed: expected Gamma''s own initial movement, got %', v_movement;
  end if;

  select * into v_card from app.list_customer_portal_loyalty_tier_cards(v_tenant2, v_customer_gamma, v_account_gamma);
  if v_card.current_tier_name <> 'Base' or v_card.program_name <> 'Gamma Rewards' then
    raise exception 'assertion failed: expected Gamma at Base in her own Gamma Rewards program, got %', v_card;
  end if;
end $$;

\echo '>> staff reads: app.get_loyalty_tier_definition/app.get_loyalty_account_tier_state LYL:View-gated (Viewer succeeds, Plain User denied); app.list_loyalty_account_tier_movements keyset pagination visits every row exactly once at p_limit=1; half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_viewer1 uuid := '00000000-0000-0000-0000-000000338002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000338003';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_tier_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_loyalty_account_id uuid;
  v_tier app.loyalty_tier_definitions;
  v_state record;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_created_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
  v_expected_total integer;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;

  v_tier := app.get_loyalty_tier_definition(v_tenant1, v_tier_id, v_viewer1);
  if v_tier.id <> v_tier_id then
    raise exception 'assertion failed: Viewer (LYL:View) should be able to read the tier definition';
  end if;

  begin
    perform app.get_loyalty_tier_definition(v_tenant1, v_tier_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User on get_loyalty_tier_definition';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_tier_definition(v_tenant1, gen_random_uuid(), v_viewer1);
    raise exception 'assertion failed: expected loyalty_tier_definition_not_found for a genuinely nonexistent id';
  exception when others then if sqlerrm not like 'loyalty_tier_definition_not_found%' then raise; end if;
  end;

  select * into v_state from app.get_loyalty_account_tier_state(v_tenant1, v_loyalty_account_id, v_viewer1);
  if v_state.current_tier_name is null then
    raise exception 'assertion failed: expected Alpha''s own current tier name to be populated, got %', v_state;
  end if;

  begin
    perform app.get_loyalty_account_tier_state(v_tenant1, v_loyalty_account_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User on get_loyalty_account_tier_state';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_expected_total from app.loyalty_account_tier_movements where loyalty_account_id = v_loyalty_account_id;
  if v_expected_total < 3 then
    raise exception 'assertion failed: fixture setup error, expected at least 3 movements for Alpha, got %', v_expected_total;
  end if;

  loop
    v_page_count := 0;
    for v_row in select * from app.list_loyalty_account_tier_movements(v_tenant1, v_viewer1, p_loyalty_account_id => v_loyalty_account_id, p_cursor_created_at => v_cursor_created_at, p_cursor_id => v_cursor_id, p_limit => 1) loop
      v_page_count := v_page_count + 1;
      if v_row.id = any (v_seen_ids) then
        raise exception 'assertion failed: cursor pagination returned a duplicate row %, seen so far %', v_row.id, v_seen_ids;
      end if;
      v_seen_ids := v_seen_ids || v_row.id;
      v_cursor_created_at := v_row.created_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_page_count = 0;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 20 then
      raise exception 'assertion failed: cursor pagination did not terminate within 20 pages -- possible infinite loop';
    end if;
  end loop;
  if v_total_pages <> v_expected_total or array_length(v_seen_ids, 1) <> v_expected_total then
    raise exception 'assertion failed: expected exactly % pages of 1 row each covering % distinct rows, got % pages / % rows', v_expected_total, v_expected_total, v_total_pages, array_length(v_seen_ids, 1);
  end if;

  begin
    perform app.list_loyalty_account_tier_movements(v_tenant1, v_viewer1, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_created_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS/grant defense-in-depth: app.loyalty_tier_definitions/app.loyalty_account_tier_movements/app.loyalty_account_tier_holds all deny a raw authenticated SELECT outright with a real permission-denied error -- authenticated holds ZERO direct grant on any of the 3 new tables'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000338010", "role": "authenticated"}';

  begin
    select count(*) into v_count from app.loyalty_tier_definitions;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_tier_definitions to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_account_tier_movements;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_account_tier_movements to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_account_tier_holds;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_account_tier_holds to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;

  reset role;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on any of the 11 new public functions; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.create_loyalty_tier_definition(uuid, uuid, text, integer, text, numeric, jsonb, integer, uuid, text)',
    'app.update_loyalty_tier_definition_draft(uuid, uuid, integer, text, integer, text, numeric, jsonb, integer, uuid, text)',
    'app.publish_loyalty_tier_definition(uuid, uuid, integer, timestamptz, uuid, text)',
    'app.get_loyalty_tier_definition(uuid, uuid, uuid)',
    'app.list_loyalty_tier_definitions(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.recalculate_customer_loyalty_tier(uuid, uuid, uuid, text)',
    'app.hold_loyalty_account_tier_benefits(uuid, uuid, text, uuid, text)',
    'app.release_loyalty_account_tier_benefits(uuid, uuid, uuid, text)',
    'app.get_loyalty_account_tier_state(uuid, uuid, uuid)',
    'app.list_loyalty_account_tier_movements(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_tier_cards(uuid, uuid, uuid, integer)'
  ] loop
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
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every one of the 11 actor-taking new RPCs (ATW-031/032 discipline, applied from the first draft)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000338010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000338050';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_tier_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'Bronze' and status = 'published');
  v_scratch_tier_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards') and tier_name = 'ScratchDraft' and status = 'draft');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'tier1') and legal_name = 'Tier Account Alpha');
  v_loyalty_account_id uuid;
begin
  select id into v_loyalty_account_id from app.loyalty_accounts where tenant_id = v_tenant1 and program_id = v_program_id and customer_account_id = v_account_alpha;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000338050", "role": "authenticated"}';

  begin
    perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Impersonated', 50, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.create_loyalty_tier_definition';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.update_loyalty_tier_definition_draft(v_tenant1, v_scratch_tier_id, 1, 'ScratchDraft', 90, 'earning_amount_ytd', 99999, '{}'::jsonb, 0, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.update_loyalty_tier_definition_draft';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.publish_loyalty_tier_definition(v_tenant1, v_scratch_tier_id, 1, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.publish_loyalty_tier_definition';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_tier_definition(v_tenant1, v_tier_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_tier_definition';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_tier_definitions(v_tenant1, v_program_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_tier_definitions';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.recalculate_customer_loyalty_tier(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.recalculate_customer_loyalty_tier';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.hold_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, 'x', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.hold_loyalty_account_tier_benefits';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.release_loyalty_account_tier_benefits(v_tenant1, v_loyalty_account_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.release_loyalty_account_tier_benefits';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_account_tier_state(v_tenant1, v_loyalty_account_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_account_tier_state';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_account_tier_movements(v_tenant1, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_account_tier_movements';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_tier_cards';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (impersonator holds the
  -- Loyalty Manager role too) is NOT rejected by the identity check -- it
  -- succeeds on its own authority, proving the identity check and the
  -- authority check are two independent gates.
  perform app.get_loyalty_tier_definition(v_tenant1, v_tier_id, v_impersonator);

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: Alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000338010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_alpha, p_limit => 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000338010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_loyalty_tier_cards(v_tenant1, v_customer_alpha, p_limit => 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

\echo '>> ISS-2026-127 item 1: the tier-recalculation SWEEP -- recalculates every ACTIVE enrolment, counts an account whose programme has no base tier as a skip rather than aborting, and is idempotent per run label'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'tier2');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000338002';
  v_manager2 uuid := '00000000-0000-0000-0000-000000339001';
  v_active_accounts integer;
  v_t2_movements_before integer;
  v_t2_movements_after integer;
  v_row record;
  v_repeat record;
begin
  select count(*) into v_active_accounts from app.loyalty_accounts where tenant_id = v_tenant1 and status = 'active';
  if v_active_accounts = 0 then
    raise exception 'assertion failed: this fixture must carry at least one active loyalty account for the sweep to walk';
  end if;
  select count(*) into v_t2_movements_before from app.loyalty_account_tier_movements where tenant_id = v_tenant2;

  select * into v_row from app.run_loyalty_tier_recalculation_sweep(v_tenant1, now(), v_manager1, 'manager1', 'iss127-run-a');

  -- The sweep walks EVERY active enrolment, not only those with recent activity: a
  -- time-based demotion has no new earning event to key off, so an activity filter would
  -- skip exactly what a periodic recalculation exists to catch.
  if v_row.processed_count + v_row.skipped_count <> v_active_accounts then
    raise exception 'assertion failed: expected every one of % active accounts accounted for, got % processed + % skipped', v_active_accounts, v_row.processed_count, v_row.skipped_count;
  end if;
  if v_row.status <> 'completed' then
    raise exception 'assertion failed: expected a completed sweep job, got %', v_row.status;
  end if;

  -- This fixture deliberately carries accounts whose programme configuration makes
  -- recalculation raise (ISS-2026-127 item 2). The run must survive them.
  if v_row.processed_count = 0 then
    raise exception 'assertion failed: at least one account must have recalculated successfully -- a sweep that skips everything proves nothing about isolation';
  end if;

  select count(*) into v_t2_movements_after from app.loyalty_account_tier_movements where tenant_id = v_tenant2;
  if v_t2_movements_after <> v_t2_movements_before then
    raise exception 'assertion failed: a tenant1 sweep wrote % tenant2 tier movements', v_t2_movements_after - v_t2_movements_before;
  end if;

  select * into v_repeat from app.run_loyalty_tier_recalculation_sweep(v_tenant1, now(), v_manager1, 'manager1', 'iss127-run-a');
  if v_repeat.job_id <> v_row.job_id then
    raise exception 'assertion failed: the same run label must be the same job, got % vs %', v_repeat.job_id, v_row.job_id;
  end if;

  -- A DIFFERENT label is a genuinely new run, and recalculating unchanged accounts must be a
  -- no-op rather than a spurious second tier movement -- the property that makes walking every
  -- account on every run safe.
  select * into v_repeat from app.run_loyalty_tier_recalculation_sweep(v_tenant1, now(), v_manager1, 'manager1', 'iss127-run-b');
  if v_repeat.job_id = v_row.job_id then
    raise exception 'assertion failed: a different run label must be a different job';
  end if;
  if v_repeat.processed_count <> v_row.processed_count then
    raise exception 'assertion failed: an immediate re-sweep must process the same accounts, got % vs %', v_repeat.processed_count, v_row.processed_count;
  end if;

  begin
    perform app.run_loyalty_tier_recalculation_sweep(v_tenant1, now(), v_viewer1, 'viewer1', 'iss127-denied');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not start a tier sweep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.run_loyalty_tier_recalculation_sweep(v_tenant1, now(), v_manager2, 'manager2', 'iss127-crosstenant');
    raise exception 'assertion failed: expected insufficient_authority -- a tenant2 manager must not sweep tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'PASS: tier sweep walked all % active accounts (% recalculated, % skipped), stayed inside its tenant, and re-running is a no-op', v_active_accounts, v_row.processed_count, v_row.skipped_count;
end $$;

\echo '>> ISS-2026-127 item 2: app.get_loyalty_program_tier_readiness -- advisory, read-only readiness snapshot. A healthy programme (Tier Rewards) reports ready; "Gapped Program" reports not-ready with no base tier and an untiered active account; "Bad Dimension Program" reports not-ready with an unsupported-dimension count; LYL:View alone (no Edit) may call it; a cross-tenant actor is refused; a tenant-A program id passed under tenant B is loyalty_program_not_found, indistinguishable from a genuinely nonexistent id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tier1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'tier2');
  v_manager1 uuid := '00000000-0000-0000-0000-000000338001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000338002';
  v_manager2 uuid := '00000000-0000-0000-0000-000000339001';
  v_rewards_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Tier Rewards');
  v_gapped_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Gapped Program');
  v_baddim_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'tier1') and name = 'Bad Dimension Program');
  v_readiness app.loyalty_program_tier_readiness;
  v_nonexistent_msg text;
  v_borrowed_msg text;
begin
  -- A healthy, fully-configured programme (base tier Bronze=0, no
  -- unsupported dimensions, its own two remaining active accounts -- Edge
  -- was closed earlier in this file -- both already recalculated) reports
  -- ready. Called by v_viewer1, who holds LYL:View only, never Create/Edit/
  -- Configure -- proving this read needs no elevated authority.
  v_readiness := app.get_loyalty_program_tier_readiness(v_tenant1, v_rewards_program_id, v_viewer1);
  if v_readiness.ready is not true or v_readiness.has_base_tier is not true or v_readiness.unsupported_dimension_tier_count <> 0 or v_readiness.untiered_active_account_count <> 0 then
    raise exception 'assertion failed: expected Tier Rewards ready with a base tier, zero unsupported dimensions, zero untiered accounts, got %', v_readiness;
  end if;
  if v_readiness.active_account_count <> 2 then
    raise exception 'assertion failed: expected Tier Rewards to carry exactly 2 active accounts (Edge was closed earlier), got %', v_readiness.active_account_count;
  end if;

  -- "Gapped Program": single Elite tier at threshold=10000, no base
  -- (threshold=0) rung -- not ready, and its own dedicated Gap account
  -- (never successfully recalculated, per the no_eligible_tier_definition
  -- block above) is counted untiered.
  v_readiness := app.get_loyalty_program_tier_readiness(v_tenant1, v_gapped_program_id, v_manager1);
  if v_readiness.ready is not false or v_readiness.has_base_tier is not false then
    raise exception 'assertion failed: expected Gapped Program not-ready with no base tier, got %', v_readiness;
  end if;
  if v_readiness.untiered_active_account_count < 1 then
    raise exception 'assertion failed: expected at least 1 untiered active account for Gapped Program, got %', v_readiness;
  end if;

  -- "Bad Dimension Program": single "Weird" tier at threshold=0 (so
  -- has_base_tier is TRUE -- design decision 1, base-tier presence is
  -- independent of dimension support) but threshold_dimension =
  -- 'transaction_count_lifetime', unsupported -- not ready via the
  -- unsupported-dimension count instead.
  v_readiness := app.get_loyalty_program_tier_readiness(v_tenant1, v_baddim_program_id, v_manager1);
  if v_readiness.ready is not false or v_readiness.unsupported_dimension_tier_count <> 1 then
    raise exception 'assertion failed: expected Bad Dimension Program not-ready with unsupported_dimension_tier_count=1, got %', v_readiness;
  end if;
  if v_readiness.has_base_tier is not true then
    raise exception 'assertion failed: expected Bad Dimension Program to still report has_base_tier=true (its own Weird tier IS a threshold=0 rung, just an unsupported dimension), got %', v_readiness;
  end if;

  -- A tenant2 manager holds no role assignment in tenant1 at all --
  -- insufficient_authority, never a program lookup.
  begin
    perform app.get_loyalty_program_tier_readiness(v_tenant1, v_rewards_program_id, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority -- manager2 holds no role assignment in tenant1';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A tenant1 program id, borrowed under tenant2's own tenant_id (with
  -- tenant2's own valid LYL:View authority) -- must be indistinguishable
  -- from a genuinely nonexistent program id, proving authority is checked
  -- BEFORE existence and existence never leaks across the tenant boundary.
  begin
    perform app.get_loyalty_program_tier_readiness(v_tenant2, v_rewards_program_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_program_not_found -- a tier1 program id does not exist inside tenant2''s own scope';
  exception when others then
    if sqlerrm not like 'loyalty_program_not_found%' then raise; end if;
    v_borrowed_msg := regexp_replace(sqlerrm, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<id>', 'g');
  end;

  begin
    perform app.get_loyalty_program_tier_readiness(v_tenant2, gen_random_uuid(), v_manager2);
    raise exception 'assertion failed: expected loyalty_program_not_found for a genuinely nonexistent program id';
  exception when others then
    if sqlerrm not like 'loyalty_program_not_found%' then raise; end if;
    v_nonexistent_msg := regexp_replace(sqlerrm, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<id>', 'g');
  end;
  if v_borrowed_msg <> v_nonexistent_msg then
    raise exception 'assertion failed: a borrowed-id not_found and a genuinely-nonexistent-id not_found must be the identically-shaped error (ids normalized), got % vs %', v_borrowed_msg, v_nonexistent_msg;
  end if;
end $$;

\echo '>> ISS-2026-127 item 3: the live CHECK constraint tying tier_definition_version_id to to_tier_id on app.loyalty_account_tier_movements still exists -- not merely that one row''s own values happen to match'
do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid = 'app.loyalty_account_tier_movements'::regclass and conname = 'latm_version_id_matches_to_tier_check';
  if v_def is null then
    raise exception 'assertion failed: expected a live CHECK constraint named latm_version_id_matches_to_tier_check on app.loyalty_account_tier_movements (ISS-2026-127 item 3) -- a future migration silently dropped it';
  end if;
  if v_def <> 'CHECK ((tier_definition_version_id = to_tier_id))' then
    raise exception 'assertion failed: expected latm_version_id_matches_to_tier_check to read CHECK ((tier_definition_version_id = to_tier_id)), got %', v_def;
  end if;
end $$;

\echo '>> ALL PASSED: CPL-317 Membership Tier'
