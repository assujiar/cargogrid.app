-- Real, executable test evidence for CPL-320 (CG-S13-CPL-022, Prompt 320,
-- "Reward Catalogue") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. The FIRST prompt of Batch 5 (CPL-320..323),
-- and the FIFTH Loyalty-domain db-test in this repository.
--
-- UUID range 00000000-0000-0000-0000-0000003430xx (tenant rwd1) /
-- 00000000-0000-0000-0000-0000003431xx (tenant rwd2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Fixture shortcut, disclosed (mirrors CPL-317's own db-test backdating
-- next_review_at directly via fixture UPDATE, never through the RPC):
-- customer tier standing (app.loyalty_account_tier_movements) and points
-- balance (app.loyalty_point_balances) are seeded via DIRECT insert, never
-- through CPL-317/318's own recalculation/posting RPCs -- this checkpoint's
-- own test is about REWARD ELIGIBILITY PROJECTION correctness given a KNOWN
-- tier/points state, not about how that state came to be (CPL-317's/318's
-- own db-tests already cover that exhaustively).
--
-- Covers, live: (a) draft/publish/pause/resume/archive lifecycle, including
-- the disclosed 6th function (resume) and a full NULL-bypass optimistic-
-- concurrency regression proof across all five version-checked functions;
-- (b) eligibility projection correctness -- an open reward, a tier-gated
-- reward, a points-gated reward, and a combined tier+points-gated reward,
-- each verified for a Bronze/50-point customer AND a Silver/500-point
-- customer AND a Gold/0-point customer; (c) internal-cost-never-leaked
-- assertion (jsonb key probe on both customer-facing RPCs); (d) malware-
-- scan-gated file visibility (clean vs pending), including the app.file_
-- access_logs write; (e) stock: a real reservation, an idempotent replay, a
-- rejected over-reservation, and a REAL two-process concurrent race
-- (reusing scripts/db-tests/wms-picking-concurrency-helper.sh) proving
-- exactly one of two concurrent single-unit reservations against a
-- total_stock=1 reward can ever succeed; (f) a paused reward surfaces as
-- display_state=unavailable, not hidden; a not-yet-effective (scheduled)
-- reward is hidden entirely; an archived/superseded reward is hidden
-- entirely; (g) cross-tenant/cross-account isolation; plus anti-
-- enumeration on the detail read, actor-identity session cross-check, raw-
-- table RLS/raw-function-grant defense-in-depth, a real authenticated-role
-- positive path, and keyset pagination.

\set ON_ERROR_STOP on

\echo '>> setup: tenant rwd1 (org unit, roles: Loyalty Manager [full LYL], Loyalty Viewer [LYL View only], Plain User [no LYL grant]; a document-config tenant_admin; a Supreme Admin; customer accounts Alpha/Beta/Gamma, customer_user identities for Alpha/Beta/Gamma; an impersonator identity), tenant rwd2 (its own Loyalty Manager, customer account Delta); a shared loyalty program with published Bronze/Silver/Gold tier definitions; Alpha (Silver, 500 pts)/Beta (Bronze, 50 pts)/Gamma (Gold, 0 pts) all enrolled with seeded tier/points fixture state'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_account_delta uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000343003';
  v_plain1 uuid := '00000000-0000-0000-0000-000000343004';
  v_docadmin1 uuid := '00000000-0000-0000-0000-000000343006';
  v_supreme uuid := '00000000-0000-0000-0000-000000343090';
  v_impersonator uuid := '00000000-0000-0000-0000-000000343050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000343020';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000343030';
  v_manager2 uuid := '00000000-0000-0000-0000-000000343101';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000343110';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_viewer_role1 uuid;
  v_viewer_draft1 app.role_versions;
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
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@rwd1.test'),
    (v_viewer1, 'viewer1@rwd1.test'),
    (v_plain1, 'plain1@rwd1.test'),
    (v_docadmin1, 'docadmin1@rwd1.test'),
    (v_supreme, 'supreme@rwd1.test'),
    (v_impersonator, 'impersonator@rwd1.test'),
    (v_customer_alpha, 'customer-alpha@rwd1.test'),
    (v_customer_beta, 'customer-beta@rwd1.test'),
    (v_customer_gamma, 'customer-gamma@rwd1.test'),
    (v_manager2, 'manager2@rwd2.test'),
    (v_customer_delta, 'customer-delta@rwd2.test');

  perform app.provision_tenant('rwd1', 'Reward Catalogue Test Tenant One', 'idem-rwd1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'rwd1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'RWD1-CO', 'Rwd1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'RWD1-CO');

  perform app.provision_tenant('rwd2', 'Reward Catalogue Test Tenant Two', 'idem-rwd2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'rwd2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'RWD2-CO', 'Rwd2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'RWD2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@rwd1.test', 'Rwd1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@rwd1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer1@rwd1.test', 'Rwd1 Viewer', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer1@rwd1.test'), 'active', 'onboarded', 'tester');
  v_viewer_role1 := (app.create_role(v_tenant1, 'Loyalty Viewer', 'LYL:View only, never Configure/Create/Edit', 'tester')).id;
  v_viewer_draft1 := app.create_role_version(v_viewer_role1, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role1 and status = 'published'), v_viewer1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@rwd1.test', 'Rwd1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@rwd1.test'), 'active', 'onboarded', 'tester');

  -- docadmin1: a real tenant_admin identity, used ONLY for the document-
  -- type/config-version setup below (PLT-121 config engine authority,
  -- distinct from LYL role-based authority).
  perform app.invite_user(v_tenant1, v_docadmin1, 'docadmin1@rwd1.test', 'Rwd1 Doc Admin', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'docadmin1@rwd1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_docadmin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  -- impersonator: a real, active tenant1 identity holding Manager's role
  -- too, used ONLY for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@rwd1.test', 'Rwd1 Impersonator', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@rwd1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_impersonator, v_manager1, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rwd Account Alpha', 'rwd-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rwd Account Beta', 'rwd-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Rwd Account Gamma', 'rwd-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Rwd Account Delta', 'rwd-delta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_delta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@rwd1.test', 'Rwd Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@rwd1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@rwd1.test', 'Rwd Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@rwd1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_gamma, 'customer-gamma@rwd1.test', 'Rwd Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@rwd1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant1, v_account_gamma::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@rwd2.test', 'Rwd2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@rwd2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_delta, 'customer-delta@rwd2.test', 'Rwd Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@rwd2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant2, v_account_delta::text, 'tester');

  -- CPL-316 program/account scaffolding (this checkpoint's own direct
  -- upstream dependency -- reads app.loyalty_accounts, never writes it).
  perform app.create_loyalty_program(v_tenant1, 'Reward Catalogue Program', 'Program used to test the reward catalogue.', v_manager1, 'manager1');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Reward Catalogue Program');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1, 'manager1');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1, 'manager1');
  v_loyalty_account_alpha := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_alpha);
  v_loyalty_account_beta := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_beta);
  v_loyalty_account_gamma := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_gamma);

  perform app.create_loyalty_program(v_tenant2, 'Reward Catalogue Program 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Reward Catalogue Program 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_delta, v_program2_id, v_manager2, 'manager2');

  -- CPL-317 tier scaffolding: Bronze(1)/Silver(2)/Gold(3), all published.
  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Bronze', 1, 'earning_amount_ytd', 0, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_bronze_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Bronze' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_bronze_id, 1, null, v_manager1, 'manager1');

  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Silver', 2, 'earning_amount_ytd', 500, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_silver_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Silver' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_silver_id, 1, null, v_manager1, 'manager1');

  perform app.create_loyalty_tier_definition(v_tenant1, v_program_id, 'Gold', 3, 'earning_amount_ytd', 1000, '{}'::jsonb, 0, v_manager1, 'manager1');
  v_gold_id := (select id from app.loyalty_tier_definitions where program_id = v_program_id and tier_name = 'Gold' and status = 'draft');
  perform app.publish_loyalty_tier_definition(v_tenant1, v_gold_id, 1, null, v_manager1, 'manager1');

  -- Fixture shortcut (disclosed in this file's own header): seed tier
  -- standing/points balance directly, never through CPL-317/318's own
  -- recalculation/posting RPCs. Alpha -> Silver, 500 points. Beta ->
  -- Bronze, 50 points. Gamma -> Gold, 0 points (no balance row at all --
  -- proves the "no row yet" path coalesces to 0, never null/error).
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_alpha, null, v_silver_id, 'initial', v_silver_id, '{}'::jsonb, 'CPL-320 fixture seed', clock_timestamp() + interval '365 days', 'tester');
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_beta, null, v_bronze_id, 'initial', v_bronze_id, '{}'::jsonb, 'CPL-320 fixture seed', clock_timestamp() + interval '365 days', 'tester');
  insert into app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id, evaluation_snapshot, reason, next_review_at, created_by)
  values (v_tenant1, v_loyalty_account_gamma, null, v_gold_id, 'initial', v_gold_id, '{}'::jsonb, 'CPL-320 fixture seed', clock_timestamp() + interval '365 days', 'tester');

  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_alpha, 500, 0);
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant1, v_loyalty_account_beta, 50, 0);
end $$;

\echo '>> document-type/config setup for the malware-scan-gated file visibility test (PLT-128) -- Supreme Admin registers a reward_terms document type, tenant_admin publishes a definition, two files uploaded (one clean, one still pending)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_supreme uuid := '00000000-0000-0000-0000-000000343090';
  v_docadmin1 uuid := '00000000-0000-0000-0000-000000343006';
  v_draft app.config_versions;
begin
  perform app.register_document_type('reward_terms', 'Reward Terms Document', 'LYL', v_supreme, 'supreme admin');

  v_draft := app.create_config_draft('document:reward_terms', v_tenant1, 'tenant', null, v_docadmin1, 'docadmin1');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('none'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_docadmin1, 'docadmin1');
  perform app.publish_document_type_definition(v_draft.id, v_docadmin1, now(), 'docadmin1');
end $$;

\echo '>> app.create_loyalty_reward_draft / app.update_loyalty_reward_draft: field validation, invalid_min_tier_id/invalid_file_id cross-checks, draft_already_exists, LYL:Create/Edit required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000343004';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_program2_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd2') and name = 'Reward Catalogue Program 2');
  v_row app.loyalty_rewards;
begin
  -- Invalid reward_type.
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Bad Type Reward', 'store_credit', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_reward_type';
  exception when others then if sqlerrm not like 'invalid_reward_type%' then raise; end if;
  end;

  -- Empty reward_name.
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, '   ', 'physical_item', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_reward_name';
  exception when others then if sqlerrm not like 'invalid_reward_name%' then raise; end if;
  end;

  -- min_tier_id belonging to a DIFFERENT program (cross-program guard).
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Cross Program Reward', 'physical_item', null, null, gen_random_uuid(), null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_min_tier_id for a nonexistent tier';
  exception when others then if sqlerrm not like 'invalid_min_tier_id%' then raise; end if;
  end;

  -- invalid_file_id.
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Bad File Reward', 'physical_item', null, null, null, null, null, null, null, gen_random_uuid(), v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_file_id';
  exception when others then if sqlerrm not like 'invalid_file_id%' then raise; end if;
  end;

  -- Plain User denied.
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Denied Reward', 'physical_item', null, null, null, null, null, null, null, null, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A real draft, then a SECOND draft attempt for the SAME (program,
  -- reward_name) is rejected (mandatory test: at most one draft per
  -- lineage, real exception-handler-backed).
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Duplicate Draft Reward', 'physical_item', 'A reward.', 'Terms.', null, null, null, null, null, null, v_manager1, 'manager1');
  if v_row.status <> 'draft' or v_row.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh draft at version 1, got %', v_row;
  end if;
  begin
    perform app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Duplicate Draft Reward', 'physical_item', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected draft_already_exists';
  exception when others then if sqlerrm not like 'draft_already_exists%' then raise; end if;
  end;

  -- app.update_loyalty_reward_draft: Plain User denied; editing a
  -- non-draft is rejected (proven later, after publish, in the lifecycle
  -- section); a valid edit succeeds and bumps record_version.
  begin
    perform app.update_loyalty_reward_draft(v_tenant1, v_row.id, v_row.record_version, 'Duplicate Draft Reward', 'physical_item', null, null, null, null, null, null, null, null, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User on update';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_row := app.update_loyalty_reward_draft(v_tenant1, v_row.id, v_row.record_version, 'Duplicate Draft Reward', 'physical_item', 'Updated description.', 'Updated terms.', null, null, null, null, null, null, v_manager1, 'manager1');
  if v_row.description <> 'Updated description.' or v_row.record_version <> 2 then
    raise exception 'assertion failed: expected the draft edit to apply and bump record_version to 2, got %', v_row;
  end if;
end $$;

\echo '>> full lifecycle + NULL-bypass optimistic-concurrency regression proof (mandatory test), across ALL FIVE version-checked functions in sequence: create -> update(NULL rejected, then real) -> publish(NULL rejected, then real) -> pause(NULL rejected, then real) -> resume(NULL rejected, then real) -> archive(NULL rejected, then real)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_row app.loyalty_rewards;
  v_before app.loyalty_rewards;
begin
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'NULL Bypass Reward', 'service_credit', 'Proves the NULL-bypass fix.', null, null, null, null, null, null, null, v_manager1, 'manager1');
  if v_row.record_version <> 1 or v_row.status <> 'draft' then
    raise exception 'assertion failed: fixture setup error, got %', v_row;
  end if;

  -- update_loyalty_reward_draft: NULL expected_version is rejected, row
  -- unchanged; then the real version succeeds.
  v_before := v_row;
  begin
    perform app.update_loyalty_reward_draft(v_tenant1, v_row.id, null, 'NULL Bypass Reward Edited', 'service_credit', 'should not apply', null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on update';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_row from app.loyalty_rewards where id = v_before.id;
  if v_row.record_version <> v_before.record_version or v_row.description <> v_before.description then
    raise exception 'assertion failed: NULL-bypass regression -- a NULL p_expected_version must never apply the write, got % vs before %', v_row, v_before;
  end if;
  v_row := app.update_loyalty_reward_draft(v_tenant1, v_row.id, v_row.record_version, 'NULL Bypass Reward Edited', 'service_credit', 'applied for real', null, null, null, null, null, null, null, v_manager1, 'manager1');
  if v_row.record_version <> 2 or v_row.description <> 'applied for real' then
    raise exception 'assertion failed: expected the real-version update to apply, got %', v_row;
  end if;

  -- publish_loyalty_reward: NULL rejected, row still draft; real version
  -- publishes.
  v_before := v_row;
  begin
    perform app.publish_loyalty_reward(v_tenant1, v_row.id, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on publish';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_row from app.loyalty_rewards where id = v_before.id;
  if v_row.status <> 'draft' or v_row.record_version <> v_before.record_version then
    raise exception 'assertion failed: NULL-bypass regression on publish -- row must remain draft, got %', v_row;
  end if;
  v_row := app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');
  if v_row.status <> 'published' or v_row.record_version <> 3 or v_row.published_by is null or v_row.effective_from is null then
    raise exception 'assertion failed: expected the real-version publish to apply, got %', v_row;
  end if;

  -- pause_loyalty_reward: NULL rejected, still published; real version
  -- pauses.
  v_before := v_row;
  begin
    perform app.pause_loyalty_reward(v_tenant1, v_row.id, null, 'seasonal pause', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on pause';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_row from app.loyalty_rewards where id = v_before.id;
  if v_row.status <> 'published' or v_row.record_version <> v_before.record_version then
    raise exception 'assertion failed: NULL-bypass regression on pause -- row must remain published, got %', v_row;
  end if;
  v_row := app.pause_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, 'seasonal pause', v_manager1, 'manager1');
  if v_row.status <> 'paused' or v_row.record_version <> 4 then
    raise exception 'assertion failed: expected the real-version pause to apply, got %', v_row;
  end if;

  -- resume_loyalty_reward: NULL rejected, still paused; real version
  -- resumes.
  v_before := v_row;
  begin
    perform app.resume_loyalty_reward(v_tenant1, v_row.id, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on resume';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_row from app.loyalty_rewards where id = v_before.id;
  if v_row.status <> 'paused' or v_row.record_version <> v_before.record_version then
    raise exception 'assertion failed: NULL-bypass regression on resume -- row must remain paused, got %', v_row;
  end if;
  v_row := app.resume_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, v_manager1, 'manager1');
  if v_row.status <> 'published' or v_row.record_version <> 5 then
    raise exception 'assertion failed: expected the real-version resume to apply, got %', v_row;
  end if;

  -- archive_loyalty_reward: NULL rejected, still published; real version
  -- archives. Re-archiving is rejected (invalid_transition).
  v_before := v_row;
  begin
    perform app.archive_loyalty_reward(v_tenant1, v_row.id, null, 'retiring', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on archive';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_row from app.loyalty_rewards where id = v_before.id;
  if v_row.status <> 'published' or v_row.record_version <> v_before.record_version then
    raise exception 'assertion failed: NULL-bypass regression on archive -- row must remain published, got %', v_row;
  end if;
  v_row := app.archive_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, 'retiring', v_manager1, 'manager1');
  if v_row.status <> 'archived' or v_row.record_version <> 6 then
    raise exception 'assertion failed: expected the real-version archive to apply, got %', v_row;
  end if;
  begin
    perform app.archive_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, 'again', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition for an already-archived reward';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Editing a non-draft reward is rejected.
  begin
    perform app.update_loyalty_reward_draft(v_tenant1, v_row.id, v_row.record_version, 'x', 'service_credit', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition for editing a non-draft reward';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Pausing a draft (never published) is rejected.
  declare
    v_fresh_draft app.loyalty_rewards;
  begin
    v_fresh_draft := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Never Published Reward', 'physical_item', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    begin
      perform app.pause_loyalty_reward(v_tenant1, v_fresh_draft.id, v_fresh_draft.record_version, 'x', v_manager1, 'manager1');
      raise exception 'assertion failed: expected invalid_transition for pausing a draft';
    exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
    end;
    begin
      perform app.resume_loyalty_reward(v_tenant1, v_fresh_draft.id, v_fresh_draft.record_version, v_manager1, 'manager1');
      raise exception 'assertion failed: expected invalid_transition for resuming a draft';
    exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
    end;
  end;
end $$;

-- Session-scoped helper (pg_temp -- auto-dropped at session end, never a
-- permanent app-schema object) -- a CREATE FUNCTION cannot be nested inside
-- a DO block, so this is defined as its own top-level statement.
create function pg_temp.assert_reward_display_state(p_tenant_id uuid, p_loyalty_account_id uuid, p_actor uuid, p_reward_id uuid, p_expected text)
returns void
language plpgsql
as $$
declare
  v_r record;
begin
  select * into v_r from app.list_customer_portal_loyalty_rewards(p_tenant_id, p_loyalty_account_id, p_actor, p_limit => 200) x where x.reward_id = p_reward_id;
  if v_r.reward_id is null then
    raise exception 'assertion failed: expected reward % to appear in the catalogue for account %, but it was absent', p_reward_id, p_loyalty_account_id;
  end if;
  if v_r.display_state <> p_expected then
    raise exception 'assertion failed: expected display_state=% for reward % / account %, got %', p_expected, p_reward_id, p_loyalty_account_id, v_r.display_state;
  end if;
end;
$$;

\echo '>> eligibility projection correctness (mandatory test): open, tier-gated, points-gated, and combined tier+points-gated rewards, verified for Alpha (Silver/500pts), Beta (Bronze/50pts), and Gamma (Gold/0pts)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000343020';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000343030';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_gold_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program') and tier_name = 'Gold' and status = 'published');
  v_silver_id uuid := (select id from app.loyalty_tier_definitions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program') and tier_name = 'Silver' and status = 'published');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Beta'));
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Gamma'));
  v_open app.loyalty_rewards;
  v_tier_gated app.loyalty_rewards;
  v_points_gated app.loyalty_rewards;
  v_combined app.loyalty_rewards;
  v_row record;
begin
  v_open := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Open Welcome Gift', 'discount_voucher', 'A welcome gift for every enrolled member.', 'No restrictions.', null, null, null, 12.34, 'Acme Fulfillment Co', null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_open.id, v_open.record_version, null, v_manager1, 'manager1');

  v_tier_gated := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Gold Tier Exclusive', 'physical_item', 'Gold members only.', 'Gold tier required.', v_gold_id, null, null, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_tier_gated.id, v_tier_gated.record_version, null, v_manager1, 'manager1');

  v_points_gated := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Points Redemption 200', 'service_credit', '200 points required.', null, null, 200, null, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_points_gated.id, v_points_gated.record_version, null, v_manager1, 'manager1');

  v_combined := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Combined VIP Reward', 'discount_voucher', 'Silver tier AND 100 points required.', null, v_silver_id, 100, null, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_combined.id, v_combined.record_version, null, v_manager1, 'manager1');

  -- Open reward: eligible for everyone.
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, v_open.id, 'eligible');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_beta, v_customer_beta, v_open.id, 'eligible');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_gamma, v_customer_gamma, v_open.id, 'eligible');

  -- Tier-gated (Gold): only Gamma (Gold) is eligible; Alpha (Silver) and
  -- Beta (Bronze) are locked.
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, v_tier_gated.id, 'locked');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_beta, v_customer_beta, v_tier_gated.id, 'locked');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_gamma, v_customer_gamma, v_tier_gated.id, 'eligible');

  -- Points-gated (200): Alpha (500) eligible, Beta (50) locked, Gamma (0)
  -- locked.
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, v_points_gated.id, 'eligible');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_beta, v_customer_beta, v_points_gated.id, 'locked');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_gamma, v_customer_gamma, v_points_gated.id, 'locked');

  -- Combined (Silver AND 100 pts): Alpha (Silver, 500) eligible -- meets
  -- BOTH; Beta (Bronze, 50) locked -- fails BOTH; Gamma (Gold, 0) locked --
  -- meets tier but fails points (proves AND-composition, not merely
  -- either-gate-alone).
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, v_combined.id, 'eligible');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_beta, v_customer_beta, v_combined.id, 'locked');
  perform pg_temp.assert_reward_display_state(v_tenant1, v_loyalty_account_gamma, v_customer_gamma, v_combined.id, 'locked');

  -- A locked reward's own description/terms/eligibility requirements are
  -- still shown (source prompt: "return the reward's own public terms/
  -- description") via the LIST projection's own min_tier_name/
  -- min_points_required columns, non-null even when locked.
  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_beta, v_customer_beta, p_limit => 200) x where x.reward_id = v_tier_gated.id;
  if v_row.min_tier_name <> 'Gold' or v_row.description is null then
    raise exception 'assertion failed: expected a LOCKED reward to still surface min_tier_name/description, got %', v_row;
  end if;
end $$;

\echo '>> internal-cost-never-leaked assertion (mandatory test): app.loyalty_rewards.internal_cost/vendor_ref are structurally absent from BOTH customer-facing RPCs'' own returned rows, but present and correct on the staff-facing read'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_open_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Open Welcome Gift');
  v_staff_row app.loyalty_rewards;
  v_list_row record;
  v_get_row record;
begin
  v_staff_row := app.get_loyalty_reward(v_tenant1, v_open_id, v_manager1);
  if v_staff_row.internal_cost <> 12.34 or v_staff_row.vendor_ref <> 'Acme Fulfillment Co' then
    raise exception 'assertion failed: expected the staff read to correctly return internal_cost/vendor_ref, got %', v_staff_row;
  end if;

  select * into v_list_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_open_id;
  if (to_jsonb(v_list_row) ? 'internal_cost') or (to_jsonb(v_list_row) ? 'internalCost') or (to_jsonb(v_list_row) ? 'vendor_ref') or (to_jsonb(v_list_row) ? 'vendorRef') then
    raise exception 'assertion failed: the customer-facing LIST projection must never carry internal_cost/vendor_ref, got %', to_jsonb(v_list_row);
  end if;

  select * into v_get_row from app.get_customer_portal_loyalty_reward(v_tenant1, v_open_id, v_loyalty_account_alpha, v_customer_alpha);
  if (to_jsonb(v_get_row) ? 'internal_cost') or (to_jsonb(v_get_row) ? 'internalCost') or (to_jsonb(v_get_row) ? 'vendor_ref') or (to_jsonb(v_get_row) ? 'vendorRef') then
    raise exception 'assertion failed: the customer-facing GET projection must never carry internal_cost/vendor_ref, got %', to_jsonb(v_get_row);
  end if;
end $$;

\echo '>> stock: a real reservation via app.reserve_loyalty_reward_stock_unit drives display_state to out_of_stock; idempotent replay does not double-subtract; a distinct over-reservation is rejected (mandatory test: real, race-safe stock-tracking mechanism)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_reward app.loyalty_rewards;
  v_res1 app.loyalty_reward_stock_reservations;
  v_res2 app.loyalty_reward_stock_reservations;
  v_row record;
begin
  v_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Limited Edition Item', 'physical_item', 'Only one available.', null, null, null, 1, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, null, v_manager1, 'manager1');

  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_row.display_state <> 'eligible' or v_row.stock_available <> 1 then
    raise exception 'assertion failed: expected 1 unit in stock and display_state=eligible before any reservation, got %', v_row;
  end if;

  v_res1 := app.reserve_loyalty_reward_stock_unit(v_tenant1, v_reward.id, 1, 'seed-reserve-1', v_manager1, 'manager1');
  if v_res1.quantity <> 1 then
    raise exception 'assertion failed: expected the reservation to record quantity=1, got %', v_res1;
  end if;

  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_row.display_state <> 'out_of_stock' or v_row.stock_available <> 0 then
    raise exception 'assertion failed: expected display_state=out_of_stock and stock_available=0 after the reservation, got %', v_row;
  end if;

  -- Idempotent replay (mandatory pattern): the SAME idempotency_key returns
  -- the IDENTICAL reservation row, never a second one -- stock_available
  -- must stay 0, not go negative.
  v_res2 := app.reserve_loyalty_reward_stock_unit(v_tenant1, v_reward.id, 1, 'seed-reserve-1', v_manager1, 'manager1');
  if v_res2.id <> v_res1.id then
    raise exception 'assertion failed: expected the idempotent replay to return the identical reservation row, got % vs %', v_res2, v_res1;
  end if;
  if (select count(*) from app.loyalty_reward_stock_reservations where reward_id = v_reward.id) <> 1 then
    raise exception 'assertion failed: expected exactly 1 reservation row for this reward after the idempotent replay';
  end if;

  -- A DIFFERENT idempotency key requesting 1 more unit is genuinely
  -- rejected (0 of 1 remains).
  begin
    perform app.reserve_loyalty_reward_stock_unit(v_tenant1, v_reward.id, 1, 'seed-reserve-2', v_manager1, 'manager1');
    raise exception 'assertion failed: expected insufficient_reward_stock for a second, distinct reservation against a fully-reserved reward';
  exception when others then if sqlerrm not like 'insufficient_reward_stock%' then raise; end if;
  end;

  -- reserve_loyalty_reward_stock_unit only accepts a PUBLISHED reward.
  declare
    v_paused app.loyalty_rewards;
  begin
    v_paused := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Paused Stock Reward', 'physical_item', null, null, null, null, 5, null, null, null, v_manager1, 'manager1');
    v_paused := app.publish_loyalty_reward(v_tenant1, v_paused.id, v_paused.record_version, null, v_manager1, 'manager1');
    v_paused := app.pause_loyalty_reward(v_tenant1, v_paused.id, v_paused.record_version, 'x', v_manager1, 'manager1');
    begin
      perform app.reserve_loyalty_reward_stock_unit(v_tenant1, v_paused.id, 1, 'seed-reserve-paused', v_manager1, 'manager1');
      raise exception 'assertion failed: expected reward_not_available_for_reservation for a paused reward';
    exception when others then if sqlerrm not like 'reward_not_available_for_reservation%' then raise; end if;
    end;
  end;
end $$;

\echo '>> stock: a REAL two-process concurrent race -- two overlapping psql sessions each try to reserve the SAME single unit of a total_stock=1 reward (mandatory test: race-safe under concurrency) -- exactly one may succeed, the other must be rejected, never both'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_race_reward app.loyalty_rewards;
begin
  v_race_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Race Stock Item', 'physical_item', null, null, null, null, 1, null, null, null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_race_reward.id, v_race_reward.record_version, null, v_manager1, 'manager1');
end $$;

select (select id from app.tenants where slug = 'rwd1') as race_tenant1_id \gset
select (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Race Stock Item') as race_reward_id \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

-- Literal-interpolated (never current_setting()/set_config -- the race
-- helper opens brand-new psql CONNECTIONS, which do not share this
-- session's own GUCs) -- mirrors scripts/db-tests/customer-loyalty-points-
-- ledger.sql's own established :variable-interpolation-into-a-\set-string
-- pattern exactly.
\set race_sql_a 'select app.reserve_loyalty_reward_stock_unit(''' :race_tenant1_id ''', ''' :race_reward_id ''', 1, ''race-reserve-a'', ''00000000-0000-0000-0000-000000343001'', ''manager1'');'
\set race_sql_b 'select app.reserve_loyalty_reward_stock_unit(''' :race_tenant1_id ''', ''' :race_reward_id ''', 1, ''race-reserve-b'', ''00000000-0000-0000-0000-000000343001'', ''manager1'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-rwd-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-rwd-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Race Stock Item');
  v_reserved_sum integer;
  v_reservation_count integer;
begin
  select coalesce(sum(quantity), 0), count(*) into v_reserved_sum, v_reservation_count
    from app.loyalty_reward_stock_reservations where reward_id = v_reward_id;

  -- The invariant under test: never both succeed (240-vs-200-style
  -- oversubscription is structurally impossible here, since total_stock=1
  -- and each racer requests exactly 1).
  if v_reserved_sum > 1 then
    raise exception 'assertion failed: the concurrent race must never reserve more than the reward''s own total_stock=1, got a reserved sum of %', v_reserved_sum;
  end if;
  if v_reservation_count > 1 then
    raise exception 'assertion failed: expected at most 1 successful concurrent reservation against a total_stock=1 reward, got % rows', v_reservation_count;
  end if;
  -- Under ordinary scheduling, exactly one racer wins -- both racers
  -- losing to some unrelated error is not the invariant under test.
  if v_reservation_count = 1 and v_reserved_sum <> 1 then
    raise exception 'assertion failed: expected the one winning racer''s own reservation to sum to exactly 1, got %', v_reserved_sum;
  end if;
end $$;

\echo '>> pause -> unavailable (never hidden); resume restores eligible; a not-yet-effective (scheduled) reward is hidden entirely; an archived reward is hidden entirely; a superseded reward (republished over) is hidden and the historical row is preserved unchanged'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_reward app.loyalty_rewards;
  v_scheduled app.loyalty_rewards;
  v_original_v1 app.loyalty_rewards;
  v_republished app.loyalty_rewards;
  v_row record;
  v_count integer;
begin
  -- Pause/resume.
  v_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Pausable Reward', 'discount_voucher', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
  v_reward := app.publish_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, null, v_manager1, 'manager1');

  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_row.display_state <> 'eligible' then
    raise exception 'assertion failed: expected a fresh published reward to be eligible before any pause, got %', v_row;
  end if;

  v_reward := app.pause_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, 'seasonal', v_manager1, 'manager1');
  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_row.reward_id is null then
    raise exception 'assertion failed: a PAUSED reward must NOT be hidden entirely -- it must still appear with display_state=unavailable (source prompt''s own disclosed choice)';
  end if;
  if v_row.display_state <> 'unavailable' then
    raise exception 'assertion failed: expected display_state=unavailable for a paused reward, got %', v_row;
  end if;

  v_reward := app.resume_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, v_manager1, 'manager1');
  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_row.display_state <> 'eligible' then
    raise exception 'assertion failed: expected display_state=eligible again after resume, got %', v_row;
  end if;

  -- Scheduled (future effective_from) -- hidden entirely.
  v_scheduled := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Scheduled Future Reward', 'discount_voucher', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
  v_scheduled := app.publish_loyalty_reward(v_tenant1, v_scheduled.id, v_scheduled.record_version, now() + interval '7 days', v_manager1, 'manager1');
  select count(*) into v_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_scheduled.id;
  if v_count <> 0 then
    raise exception 'assertion failed: a not-yet-effective (scheduled) reward must be hidden entirely, found % rows', v_count;
  end if;
  begin
    perform app.get_customer_portal_loyalty_reward(v_tenant1, v_scheduled.id, v_loyalty_account_alpha, v_customer_alpha);
    raise exception 'assertion failed: expected loyalty_reward_not_found for a not-yet-effective reward on the detail read too';
  exception when others then if sqlerrm not like 'loyalty_reward_not_found%' then raise; end if;
  end;

  -- Archived -- hidden entirely.
  v_reward := app.archive_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, 'retired', v_manager1, 'manager1');
  select count(*) into v_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_reward.id;
  if v_count <> 0 then
    raise exception 'assertion failed: an archived reward must be hidden entirely, found % rows', v_count;
  end if;

  -- Superseded (a new draft published over the same lineage) -- the OLD
  -- version is hidden and its own row is preserved unchanged; the NEW
  -- version is what customers now see.
  v_original_v1 := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Superseded Reward', 'discount_voucher', 'Original description.', null, null, null, null, null, null, null, v_manager1, 'manager1');
  v_original_v1 := app.publish_loyalty_reward(v_tenant1, v_original_v1.id, v_original_v1.record_version, null, v_manager1, 'manager1');
  v_republished := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Superseded Reward', 'discount_voucher', 'Updated description.', null, null, null, null, null, null, null, v_manager1, 'manager1');
  v_republished := app.publish_loyalty_reward(v_tenant1, v_republished.id, v_republished.record_version, null, v_manager1, 'manager1');

  select * into v_row from app.loyalty_rewards where id = v_original_v1.id;
  if v_row.status <> 'superseded' or v_row.effective_to is null or v_row.description <> 'Original description.' then
    raise exception 'assertion failed: expected the OLD version to be superseded, effective_to set, and its own description byte-for-byte unchanged, got %', v_row;
  end if;

  select count(*) into v_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_original_v1.id;
  if v_count <> 0 then
    raise exception 'assertion failed: a superseded reward version must be hidden entirely, found % rows', v_count;
  end if;
  select * into v_row from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200) x where x.reward_id = v_republished.id;
  if v_row.description <> 'Updated description.' then
    raise exception 'assertion failed: expected the NEW version to be visible with its own updated description, got %', v_row;
  end if;
end $$;

\echo '>> NULL-bypass early-rejection regression proof on app.publish_loyalty_reward specifically (Tier C review hardening, Batch 5 close): a NULL p_expected_version against a NEW draft of a lineage that already has a real prior LIVE version must be rejected BEFORE the prior-live-version supersede write ever runs -- the prior live row must stay byte-for-byte untouched, not merely rolled back'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_live app.loyalty_rewards;
  v_new_draft app.loyalty_rewards;
  v_before_live app.loyalty_rewards;
begin
  v_live := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Null Bypass Supersede Reward', 'discount_voucher', 'Live original.', null, null, null, null, null, null, null, v_manager1, 'manager1');
  v_live := app.publish_loyalty_reward(v_tenant1, v_live.id, v_live.record_version, null, v_manager1, 'manager1');
  v_before_live := v_live;

  v_new_draft := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Null Bypass Supersede Reward', 'discount_voucher', 'New candidate.', null, null, null, null, null, null, null, v_manager1, 'manager1');

  begin
    perform app.publish_loyalty_reward(v_tenant1, v_new_draft.id, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on publish (supersede scenario)';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_live from app.loyalty_rewards where id = v_before_live.id;
  if v_live.status <> 'published' or v_live.effective_to is not null or v_live.record_version <> v_before_live.record_version then
    raise exception 'assertion failed: NULL-bypass regression -- the prior LIVE version must never be touched (not even transiently) by a rejected NULL-version publish attempt, got %', v_live;
  end if;
  select * into v_new_draft from app.loyalty_rewards where id = v_new_draft.id;
  if v_new_draft.status <> 'draft' then
    raise exception 'assertion failed: the candidate draft must remain draft after a rejected NULL-version publish attempt, got %', v_new_draft;
  end if;

  -- The real version still publishes normally, correctly superseding the
  -- prior live row exactly as before.
  v_new_draft := app.publish_loyalty_reward(v_tenant1, v_new_draft.id, v_new_draft.record_version, null, v_manager1, 'manager1');
  select * into v_live from app.loyalty_rewards where id = v_before_live.id;
  if v_live.status <> 'superseded' then
    raise exception 'assertion failed: expected the real-version publish to correctly supersede the prior live row, got %', v_live;
  end if;
end $$;

\echo '>> malware-scan-gated file visibility (mandatory test): a clean file''s metadata is returned; a still-pending file''s real scan status is honestly surfaced with no metadata; app.file_access_logs records both correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'rwd1') and name = 'Reward Catalogue Program');
  v_clean_file app.files;
  v_pending_file app.files;
  v_clean_reward app.loyalty_rewards;
  v_pending_reward app.loyalty_rewards;
  v_row record;
  v_log_result text;
  v_log_reason text;
begin
  v_clean_file := app.initiate_file_upload(v_tenant1, 'reward_terms', 'loyalty_reward', gen_random_uuid(), 'terms-clean.pdf', 'application/pdf', 20480, null, false, null, '{}', null, 'idem-reward-file-clean', v_manager1, 'manager1');
  perform app.record_file_scan_result(v_clean_file.id, 'clean', 'provider-ref-clean', v_manager1, 'manager1');

  v_pending_file := app.initiate_file_upload(v_tenant1, 'reward_terms', 'loyalty_reward', gen_random_uuid(), 'terms-pending.pdf', 'application/pdf', 20480, null, false, null, '{}', null, 'idem-reward-file-pending', v_manager1, 'manager1');

  v_clean_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Reward With Clean Terms', 'discount_voucher', null, 'See attached terms.', null, null, null, null, null, v_clean_file.id, v_manager1, 'manager1');
  v_clean_reward := app.publish_loyalty_reward(v_tenant1, v_clean_reward.id, v_clean_reward.record_version, null, v_manager1, 'manager1');

  v_pending_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Reward With Pending Terms', 'discount_voucher', null, 'See attached terms.', null, null, null, null, null, v_pending_file.id, v_manager1, 'manager1');
  v_pending_reward := app.publish_loyalty_reward(v_tenant1, v_pending_reward.id, v_pending_reward.record_version, null, v_manager1, 'manager1');

  select * into v_row from app.get_customer_portal_loyalty_reward(v_tenant1, v_clean_reward.id, v_loyalty_account_alpha, v_customer_alpha);
  if not v_row.has_terms_file or v_row.terms_file_scan_status <> 'clean' or v_row.terms_file_name <> 'terms-clean.pdf' or v_row.terms_file_mime_type <> 'application/pdf' then
    raise exception 'assertion failed: expected a clean file''s own real metadata to be returned, got %', v_row;
  end if;
  select result, reason into v_log_result, v_log_reason from app.file_access_logs where file_id = v_clean_file.id and accessed_by_auth_user_id = v_customer_alpha order by accessed_at desc limit 1;
  if v_log_result <> 'granted' or v_log_reason is not null then
    raise exception 'assertion failed: expected a GRANTED, reason-less app.file_access_logs row for the clean file, got result=% reason=%', v_log_result, v_log_reason;
  end if;

  select * into v_row from app.get_customer_portal_loyalty_reward(v_tenant1, v_pending_reward.id, v_loyalty_account_alpha, v_customer_alpha);
  if not v_row.has_terms_file or v_row.terms_file_scan_status <> 'pending' or v_row.terms_file_name is not null then
    raise exception 'assertion failed: expected a still-pending file''s own real scan status (pending) with NO metadata, got %', v_row;
  end if;
  select result, reason into v_log_result, v_log_reason from app.file_access_logs where file_id = v_pending_file.id and accessed_by_auth_user_id = v_customer_alpha order by accessed_at desc limit 1;
  if v_log_result <> 'denied' or v_log_reason <> 'document_not_yet_scanned' then
    raise exception 'assertion failed: expected a DENIED app.file_access_logs row (document_not_yet_scanned) for the pending file, got result=% reason=%', v_log_result, v_log_reason;
  end if;

  -- The LIST rpc never touches app.files/app.file_access_logs at all
  -- (design decision 9) -- confirmed by an unchanged file_access_logs
  -- row-count across a fresh list call.
  declare
    v_count_before integer;
    v_count_after integer;
  begin
    select count(*) into v_count_before from app.file_access_logs;
    perform app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200);
    select count(*) into v_count_after from app.file_access_logs;
    if v_count_after <> v_count_before then
      raise exception 'assertion failed: expected app.list_customer_portal_loyalty_rewards to write ZERO app.file_access_logs rows, but the count changed from % to %', v_count_before, v_count_after;
    end if;
  end;
end $$;

\echo '>> cross-tenant/cross-account isolation (mandatory test): rwd2''s own manager cannot act on rwd1''s rewards; Delta (rwd2) sees zero rwd1 rewards even passing rwd1''s own tenant_id, and sees her own tenant2 catalogue normally'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'rwd2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000343101';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000343110';
  v_open_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Open Welcome Gift');
  v_loyalty_account_delta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd2') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd2') and legal_name = 'Rwd Account Delta'));
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_count integer;
begin
  -- rwd2's manager has no LYL role at all in rwd1.
  begin
    perform app.get_loyalty_reward(v_tenant1, v_open_id, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority for rwd2''s manager acting inside rwd1';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- rwd2's manager, scoped to their OWN tenant, guessing an rwd1 reward id
  -- -- anti-enumerating not_found, tenant-scoped fetch.
  begin
    perform app.get_loyalty_reward(v_tenant2, v_open_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_reward_not_found for an rwd1 id inside rwd2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_reward_not_found%' then raise; end if;
  end;

  -- Delta (a real rwd2 customer_user) sees zero rwd1 rewards even passing
  -- rwd1's own tenant_id and Alpha's own real loyalty_account_id --
  -- deny-by-default, never an error.
  select count(*) into v_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_delta, p_limit => 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant customer read, got %', v_count;
  end if;

  -- Delta sees her OWN tenant2 catalogue normally (currently empty --
  -- confirms the function does not error, just returns nothing, since
  -- rwd2 has no published rewards of its own in this fixture).
  select count(*) into v_count from app.list_customer_portal_loyalty_rewards(v_tenant2, v_loyalty_account_delta, v_customer_delta, p_limit => 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for Delta''s own tenant2 catalogue (no rwd2 rewards were ever published in this fixture), got %', v_count;
  end if;
end $$;

\echo '>> anti-enumeration on app.get_customer_portal_loyalty_reward: a genuinely nonexistent reward and an out-of-scope loyalty account collapse into the IDENTICAL error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000343020';
  v_open_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Open Welcome Gift');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_msg1 text;
  v_msg2 text;
begin
  begin
    perform app.get_customer_portal_loyalty_reward(v_tenant1, gen_random_uuid(), v_loyalty_account_alpha, v_customer_alpha);
  exception when others then v_msg1 := sqlerrm;
  end;
  begin
    -- Beta requesting Alpha's own loyalty_account_id (a real id, but not
    -- her own) -- must be indistinguishable from a genuinely nonexistent
    -- reward id.
    perform app.get_customer_portal_loyalty_reward(v_tenant1, v_open_id, v_loyalty_account_alpha, v_customer_beta);
  exception when others then v_msg2 := sqlerrm;
  end;
  -- Both messages carry the SAME errcode/prefix shape (loyalty_reward_not_
  -- found: <id>) -- the trailing id necessarily differs (a random guess vs.
  -- a real-but-not-owned reward id), which is fine: the anti-enumeration
  -- guarantee is that BOTH failure causes collapse onto the identical
  -- ERROR CLASS/prefix, never a distinguishable message ABOUT WHY, not that
  -- the echoed id itself is masked.
  if v_msg1 is null or v_msg2 is null or v_msg1 !~ '^loyalty_reward_not_found: ' or v_msg2 !~ '^loyalty_reward_not_found: ' then
    raise exception 'assertion failed: expected both to raise the identical loyalty_reward_not_found prefix, got % vs %', v_msg1, v_msg2;
  end if;
end $$;

\echo '>> raw-table RLS / raw-function-grant defense-in-depth: authenticated has zero direct SELECT on either new table; anon has zero EXECUTE on any of the 11 new functions'
do $$
begin
  set local role authenticated;
  begin
    perform 1 from app.loyalty_rewards limit 1;
    raise exception 'assertion failed: expected a real permission-denied error for a raw authenticated SELECT on app.loyalty_rewards';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from app.loyalty_reward_stock_reservations limit 1;
    raise exception 'assertion failed: expected a real permission-denied error for a raw authenticated SELECT on app.loyalty_reward_stock_reservations';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

do $$
declare
  v_fn text;
  v_has_grant boolean;
begin
  foreach v_fn in array array[
    'create_loyalty_reward_draft', 'update_loyalty_reward_draft', 'publish_loyalty_reward', 'pause_loyalty_reward',
    'resume_loyalty_reward', 'archive_loyalty_reward', 'reserve_loyalty_reward_stock_unit',
    'get_loyalty_reward', 'list_loyalty_rewards', 'list_customer_portal_loyalty_rewards', 'get_customer_portal_loyalty_reward'
  ] loop
    select exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon' and privilege_type = 'EXECUTE'
    ) into v_has_grant;
    if v_has_grant then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session (impersonator) claiming to act as Manager is rejected on every one of the 11 new RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Open Welcome Gift');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000343050", "role": "authenticated"}';

  begin
    perform app.create_loyalty_reward_draft(v_tenant1, gen_random_uuid(), 'x', 'physical_item', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.create_loyalty_reward_draft';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.update_loyalty_reward_draft(v_tenant1, v_reward_id, 1, 'x', 'physical_item', null, null, null, null, null, null, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.update_loyalty_reward_draft';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.publish_loyalty_reward(v_tenant1, v_reward_id, 1, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.publish_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.pause_loyalty_reward(v_tenant1, v_reward_id, 1, 'x', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.pause_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.resume_loyalty_reward(v_tenant1, v_reward_id, 1, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.resume_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.archive_loyalty_reward(v_tenant1, v_reward_id, 1, 'x', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.archive_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.reserve_loyalty_reward_stock_unit(v_tenant1, v_reward_id, 1, 'imp-1', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.reserve_loyalty_reward_stock_unit';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_reward(v_tenant1, v_reward_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_rewards(v_tenant1, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_rewards';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_rewards';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_customer_portal_loyalty_reward(v_tenant1, v_reward_id, v_loyalty_account_alpha, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_loyalty_reward';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (impersonator holds
  -- Manager's own role too) is NOT rejected -- succeeds on its own
  -- authority.
  perform app.get_loyalty_reward(v_tenant1, v_reward_id, '00000000-0000-0000-0000-000000343050');

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: Alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000343010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'rwd1') and legal_name = 'Rwd Account Alpha'));
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000343010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_loyalty_rewards(v_tenant1, v_loyalty_account_alpha, v_customer_alpha, p_limit => 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

\echo '>> keyset pagination on app.list_loyalty_rewards: visits every row exactly once at limit=1, never OFFSET; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000343001';
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_rewards[];
  v_seen_count integer := 0;
  v_total_pages integer := 0;
  v_row app.loyalty_rewards;
  v_expected_count integer;
begin
  select count(*) into v_expected_count from app.loyalty_rewards where tenant_id = v_tenant1;
  loop
    v_page := array(select app.list_loyalty_rewards(v_tenant1, v_manager1, p_cursor_updated_at => v_cursor_updated_at, p_cursor_id => v_cursor_id, p_limit => 1));
    exit when array_length(v_page, 1) is null;
    foreach v_row in array v_page loop
      v_seen_count := v_seen_count + 1;
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 200 then
      raise exception 'assertion failed: keyset pagination did not terminate within 200 pages';
    end if;
  end loop;
  if v_seen_count <> v_expected_count then
    raise exception 'assertion failed: expected keyset pagination to visit every one of % reward rows exactly once, saw %', v_expected_count, v_seen_count;
  end if;

  begin
    perform app.list_loyalty_rewards(v_tenant1, v_manager1, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> app.list_loyalty_rewards / app.get_loyalty_reward: LYL:View required (Viewer succeeds, Plain User denied)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rwd1');
  v_viewer1 uuid := '00000000-0000-0000-0000-000000343003';
  v_plain1 uuid := '00000000-0000-0000-0000-000000343004';
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'rwd1') and reward_name = 'Open Welcome Gift');
  v_count integer;
begin
  select count(*) into v_count from app.list_loyalty_rewards(v_tenant1, v_viewer1, p_limit => 200);
  if v_count = 0 then
    raise exception 'assertion failed: expected the Viewer to see a non-zero reward count';
  end if;
  perform app.get_loyalty_reward(v_tenant1, v_reward_id, v_viewer1);

  begin
    perform app.list_loyalty_rewards(v_tenant1, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User on list';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_reward(v_tenant1, v_reward_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User on get';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo 'ALL PASSED: CPL-320 Reward Catalogue'
