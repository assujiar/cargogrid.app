-- Real, executable test evidence for CPL-319 (CG-S13-CPL-021, Prompt 319,
-- "Cashback Discount Voucher") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. The FOURTH Loyalty-domain db-test in this
-- repository, and the fifth/final capability of Batch 4.
--
-- UUID range 00000000-0000-0000-0000-0000003420xx (tenant cbv1) /
-- 00000000-0000-0000-0000-0000003421xx (tenant cbv2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Covers, live: (a) value_cap enforcement (both a rejected over-cap issuance
-- and a genuine at-cap success); (b) duplicate issuance is idempotent (same
-- idempotency_key returns the SAME entitlement, never a duplicate row, and a
-- voucher replay never re-mints/re-returns the raw code); (c) voucher code
-- lookup uses the hash, never plaintext -- grep-provable no stored column
-- anywhere ever equals the raw code; (d) redeeming an already-redeemed/
-- expired/held/forged/foreign-owner code all collapse into the IDENTICAL
-- anti-enumerating error, proven by direct string comparison across every
-- failure cause; (e) reversal/expiry preserve history (never delete/
-- rewrite); (f) fraud hold blocks redemption and is idempotent; (g) cross-
-- tenant/cross-account isolation; plus actor-identity session cross-check,
-- raw-table RLS/raw-function-grant defense-in-depth, and keyset pagination.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cbv1 (org unit, roles: Loyalty Manager A/B [both full LYL], Loyalty Viewer [LYL View only], Plain User [no LYL grant]; customer accounts Alpha/Beta/Gamma, customer_user identities for Alpha/Beta; an impersonator identity), tenant cbv2 (its own Loyalty Manager, customer account Delta); a shared cashback-reward loyalty program, published rule version, Alpha/Beta/Gamma/Delta all enrolled'
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
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_manager1b uuid := '00000000-0000-0000-0000-000000342002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000342003';
  v_plain1 uuid := '00000000-0000-0000-0000-000000342004';
  v_impersonator uuid := '00000000-0000-0000-0000-000000342050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000342020';
  v_manager2 uuid := '00000000-0000-0000-0000-000000342101';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000342110';
  v_manager_role1a uuid;
  v_manager_draft1a app.role_versions;
  v_manager_role1b uuid;
  v_manager_draft1b app.role_versions;
  v_viewer_role1 uuid;
  v_viewer_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
  v_program_id uuid;
  v_program2_id uuid;
  v_rule_version_id uuid;
begin
  insert into auth.users (id, email) values
    (v_manager1a, 'manager1a@cbv1.test'),
    (v_manager1b, 'manager1b@cbv1.test'),
    (v_viewer1, 'viewer1@cbv1.test'),
    (v_plain1, 'plain1@cbv1.test'),
    (v_impersonator, 'impersonator@cbv1.test'),
    (v_customer_alpha, 'customer-alpha@cbv1.test'),
    (v_customer_beta, 'customer-beta@cbv1.test'),
    (v_manager2, 'manager2@cbv2.test'),
    (v_customer_delta, 'customer-delta@cbv2.test');

  perform app.provision_tenant('cbv1', 'Cashback Voucher Test Tenant One', 'idem-cbv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cbv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CBV1-CO', 'Cbv1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CBV1-CO');

  perform app.provision_tenant('cbv2', 'Cashback Voucher Test Tenant Two', 'idem-cbv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cbv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CBV2-CO', 'Cbv2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CBV2-CO');

  perform app.invite_user(v_tenant1, v_manager1a, 'manager1a@cbv1.test', 'Cbv1 Manager A', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1a@cbv1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1a := (app.create_role(v_tenant1, 'Loyalty Manager A', 'full LYL authority', 'tester')).id;
  v_manager_draft1a := app.create_role_version(v_manager_role1a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1a.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1a.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1a and status = 'published'), v_manager1a, v_manager1a, 'tester');

  -- A SECOND, independent full-LYL manager -- required for tests where two
  -- distinct real staff actors are needed.
  perform app.invite_user(v_tenant1, v_manager1b, 'manager1b@cbv1.test', 'Cbv1 Manager B', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1b@cbv1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1b := (app.create_role(v_tenant1, 'Loyalty Manager B', 'full LYL authority', 'tester')).id;
  v_manager_draft1b := app.create_role_version(v_manager_role1b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1b.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1b.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1b and status = 'published'), v_manager1b, v_manager1a, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer1@cbv1.test', 'Cbv1 Viewer', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer1@cbv1.test'), 'active', 'onboarded', 'tester');
  v_viewer_role1 := (app.create_role(v_tenant1, 'Loyalty Viewer', 'LYL:View only, never Configure/Create/Edit', 'tester')).id;
  v_viewer_draft1 := app.create_role_version(v_viewer_role1, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role1 and status = 'published'), v_viewer1, v_manager1a, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@cbv1.test', 'Cbv1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@cbv1.test'), 'active', 'onboarded', 'tester');

  -- impersonator: a real, active tenant1 identity holding Loyalty Manager A's
  -- role too, used ONLY for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@cbv1.test', 'Cbv1 Impersonator', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cbv1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1a and status = 'published'), v_impersonator, v_manager1a, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cbv Account Alpha', 'cbv-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cbv Account Beta', 'cbv-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cbv Account Gamma', 'cbv-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cbv Account Delta', 'cbv-delta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_delta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@cbv1.test', 'Cbv Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@cbv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@cbv1.test', 'Cbv Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cbv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@cbv2.test', 'Cbv2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@cbv2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_delta, 'customer-delta@cbv2.test', 'Cbv Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@cbv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant2, v_account_delta::text, 'tester');

  -- CPL-316 program/rule-version/account scaffolding (this checkpoint's own
  -- direct upstream dependency -- reads app.loyalty_accounts, never writes
  -- it).
  perform app.create_loyalty_program(v_tenant1, 'Cashback Rewards', 'Cashback/discount/voucher benefits.', v_manager1a, 'manager1a');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Cashback Rewards');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1a, 'manager1a');
  perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'cashback', 0.01, '{}'::jsonb, v_manager1a, 'manager1a');
  v_rule_version_id := (select id from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'draft');
  perform app.publish_loyalty_program_rule_version(v_tenant1, v_rule_version_id, 1, null, v_manager1a, 'manager1a');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1a, 'manager1a');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1a, 'manager1a');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1a, 'manager1a');

  perform app.create_loyalty_program(v_tenant2, 'Cashback Rewards 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Cashback Rewards 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.create_loyalty_program_rule_version(v_tenant2, v_program2_id, 'per_paid_invoice_amount', 'cashback', 0.01, '{}'::jsonb, v_manager2, 'manager2');
  perform app.publish_loyalty_program_rule_version(v_tenant2, (select id from app.loyalty_program_rule_versions where program_id = v_program2_id and status = 'draft'), 1, null, v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_delta, v_program2_id, v_manager2, 'manager2');
end $$;

\echo '>> app.issue_loyalty_benefit_entitlement: cashback/discount/voucher issuance, value_cap enforcement, currency validation, LYL:Edit required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000342004';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_cashback_id uuid;
begin
  -- Plain cashback, no cap.
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 50, null, 'USD', 'manual', null, null, 'issue-cashback-alpha-1', v_manager1a, 'manager1a');
  if v_row.status <> 'issued' or v_row.value_amount <> 50 or v_row.code_hash is not null or v_row.raw_code is not null then
    raise exception 'assertion failed: expected an issued cashback entitlement, no code, no raw_code, got %', v_row;
  end if;
  v_cashback_id := v_row.id;

  -- value_cap at exactly the boundary (value_amount = value_cap) must succeed.
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'discount', 25, 25, 'USD', 'manual', null, null, 'issue-discount-alpha-1', v_manager1a, 'manager1a');
  if v_row.value_amount <> 25 or v_row.value_cap <> 25 then
    raise exception 'assertion failed: expected value_amount == value_cap to be accepted at the boundary, got %', v_row;
  end if;

  -- value_cap exceeded must be rejected (mandatory test: value_cap enforcement).
  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'discount', 30, 25, 'USD', 'manual', null, null, 'issue-discount-over-cap', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected value_exceeds_cap for value_amount 30 > value_cap 25';
  exception when others then if sqlerrm not like 'value_exceeds_cap%' then raise; end if;
  end;

  -- Invalid currency.
  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 10, null, 'us-dollars', 'manual', null, null, 'issue-bad-currency', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_currency';
  exception when others then if sqlerrm not like 'invalid_currency%' then raise; end if;
  end;

  -- Invalid benefit_type.
  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'store_credit', 10, null, 'USD', 'manual', null, null, 'issue-bad-type', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_benefit_type';
  exception when others then if sqlerrm not like 'invalid_benefit_type%' then raise; end if;
  end;

  -- Nonexistent loyalty account.
  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, gen_random_uuid(), 'cashback', 10, null, 'USD', 'manual', null, null, 'issue-bad-account', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected loyalty_account_not_found';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;

  -- Plain User denied.
  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 10, null, 'USD', 'manual', null, null, 'issue-denied', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> duplicate issuance is idempotent (mandatory test): same idempotency_key returns the SAME entitlement, not a duplicate row -- proven for cashback AND voucher (voucher replay never re-mints/re-returns the raw code)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row1 record;
  v_row2 record;
  v_count integer;
begin
  select * into v_row1 from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 40, null, 'USD', 'manual', null, null, 'issue-idem-cashback', v_manager1a, 'manager1a');
  select * into v_row2 from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 999, null, 'USD', 'manual', null, null, 'issue-idem-cashback', v_manager1a, 'manager1a');
  if v_row2.id <> v_row1.id or v_row2.value_amount <> v_row1.value_amount then
    raise exception 'assertion failed: expected the identical entitlement on idempotent replay (ignoring the different value_amount 999 passed the second time), got % vs %', v_row2, v_row1;
  end if;
  select count(*) into v_count from app.loyalty_benefit_entitlements where idempotency_key = 'issue-idem-cashback';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row for the idempotency key, got %', v_count;
  end if;

  select * into v_row1 from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 15, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-idem-voucher', v_manager1a, 'manager1a');
  if v_row1.raw_code is null then
    raise exception 'assertion failed: expected a real raw_code on the first (real) voucher issuance';
  end if;
  select * into v_row2 from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 15, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-idem-voucher', v_manager1a, 'manager1a');
  if v_row2.id <> v_row1.id then
    raise exception 'assertion failed: expected the identical voucher entitlement on replay';
  end if;
  if v_row2.raw_code is not null then
    raise exception 'assertion failed: expected raw_code to be NULL on an idempotent voucher replay (design decision 2) -- the raw code is never recoverable after the first call, got %', v_row2.raw_code;
  end if;
  select count(*) into v_count from app.loyalty_benefit_entitlements where idempotency_key = 'issue-idem-voucher';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 voucher row for the idempotency key, got %', v_count;
  end if;
end $$;

\echo '>> voucher code lookup uses the hash, never plaintext (mandatory test): grep-provable -- no stored text column anywhere in either new table ever equals the raw code'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_expected_hash text;
  v_col record;
  v_match_count integer;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 12, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-hash-proof', v_manager1a, 'manager1a');
  if v_row.raw_code is null or v_row.raw_code !~ '^CGV-[A-Z2-7]{4}-[A-Z2-7]{4}$' then
    raise exception 'assertion failed: expected a real CGV-XXXX-XXXX formatted raw_code, got %', v_row.raw_code;
  end if;

  v_expected_hash := encode(digest(v_row.raw_code, 'sha256'), 'hex');
  if v_row.code_hash <> v_expected_hash then
    raise exception 'assertion failed: expected code_hash to equal sha256(raw_code), got % vs expected %', v_row.code_hash, v_expected_hash;
  end if;
  if v_row.code_hash = v_row.raw_code then
    raise exception 'assertion failed: code_hash must never equal the raw code itself';
  end if;

  -- Dynamically scan EVERY text-typed column of BOTH new tables for the raw
  -- code value -- proves, at the database level (not by inspection), that
  -- the raw code is stored nowhere at all except this function's own one-
  -- time return row.
  for v_col in
    select table_name, column_name from information_schema.columns
    where table_schema = 'app' and table_name in ('loyalty_benefit_entitlements', 'loyalty_benefit_entitlement_events')
      and data_type in ('text', 'character varying')
  loop
    execute format('select count(*) from app.%I where %I = %L', v_col.table_name, v_col.column_name, v_row.raw_code) into v_match_count;
    if v_match_count <> 0 then
      raise exception 'assertion failed: raw voucher code found stored in app.%.% -- hash-only storage violated', v_col.table_name, v_col.column_name;
    end if;
  end loop;
end $$;

\echo '>> app.redeem_loyalty_benefit_entitlement: ID path (staff and owning customer), status/expiry/version checks, invalid_transition on a second redemption'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000342020';
  v_row record;
  v_entitlement_id uuid;
  v_redeemed app.loyalty_benefit_entitlements;
begin
  select id into v_entitlement_id from app.loyalty_benefit_entitlements where idempotency_key = 'issue-idem-cashback';

  -- Beta (a DIFFERENT customer than the entitlement's own owner Alpha)
  -- cannot redeem Alpha's own entitlement by id -- anti-enumerating
  -- not_found, identical to a genuinely nonexistent id.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, null, v_customer_beta, 'customer-beta');
    raise exception 'assertion failed: expected loyalty_benefit_entitlement_not_found for a non-owning customer redeeming by id';
  exception when others then if sqlerrm not like 'loyalty_benefit_entitlement_not_found%' then raise; end if;
  end;

  -- Alpha (the OWNING customer) may redeem her own cashback entitlement by
  -- id directly -- the first genuinely customer-initiated write in this
  -- domain (design decision 5).
  v_redeemed := app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, null, v_customer_alpha, 'customer-alpha');
  if v_redeemed.status <> 'redeemed' then
    raise exception 'assertion failed: expected status redeemed after Alpha''s own self-redemption, got %', v_redeemed;
  end if;

  -- A second redemption attempt (already redeemed) is rejected.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, null, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_transition for an already-redeemed entitlement';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Stale version (staff ID path, real optimistic concurrency).
  select id into v_entitlement_id from app.loyalty_benefit_entitlements where idempotency_key = 'issue-discount-alpha-1';
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, 999, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  -- The SAME entitlement, correct version, succeeds.
  v_redeemed := app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, 1, v_manager1a, 'manager1a');
  if v_redeemed.status <> 'redeemed' then
    raise exception 'assertion failed: expected status redeemed with the correct expected_version, got %', v_redeemed;
  end if;

  -- Nonexistent id.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, gen_random_uuid()::text, null, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected loyalty_benefit_entitlement_not_found for a nonexistent id';
  exception when others then if sqlerrm not like 'loyalty_benefit_entitlement_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.redeem_loyalty_benefit_entitlement: CODE path -- Alpha redeems her OWN voucher by the real raw code; anti-enumeration proven adversarially (mandatory test) -- forged/foreign-owner/already-redeemed/expired/held/cross-tenant codes ALL collapse into the IDENTICAL error text'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cbv2');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_manager2 uuid := '00000000-0000-0000-0000-000000342101';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000342020';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000342110';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_alpha_code text;
  v_beta_owned_code text;
  v_expired_code text;
  v_held_code text;
  v_redeemed app.loyalty_benefit_entitlements;
  v_messages text[] := array[]::text[];
  v_msg text;
begin
  -- Alpha's own real, un-redeemed voucher (redeemed later in this section).
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 20, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-code-redeem-alpha', v_manager1a, 'manager1a');
  v_alpha_code := v_row.raw_code;

  -- Alpha redeems it herself, by CODE, from her own portal session shape.
  v_redeemed := app.redeem_loyalty_benefit_entitlement(v_tenant1, v_alpha_code, v_row.record_version, v_customer_alpha, 'customer-alpha');
  if v_redeemed.status <> 'redeemed' then
    raise exception 'assertion failed: expected Alpha''s own code redemption to succeed, got %', v_redeemed;
  end if;

  -- Now build the adversarial fixture set: a SECOND real voucher for Beta's
  -- own account (never redeemed by Beta -- Alpha will try to guess/use it),
  -- an ALREADY-REDEEMED code (Alpha's own, above), an EXPIRED code, and a
  -- HELD code.
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbv Account Beta')), 'voucher', 20, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-code-foreign-owner', v_manager1a, 'manager1a');
  v_beta_owned_code := v_row.raw_code;

  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 20, null, 'USD', 'manual', null, now() + interval '1 second', 'issue-code-will-expire', v_manager1a, 'manager1a');
  v_expired_code := v_row.raw_code;
  perform pg_sleep(1.2);

  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 20, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-code-will-be-held', v_manager1a, 'manager1a');
  v_held_code := v_row.raw_code;
  perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, 'suspected fraud -- test fixture', v_manager1a, 'manager1a');

  -- 1. A wholly forged/garbage code.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, 'CGV-ZZZZ-ZZZZ', null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed for a forged code';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- 2. A REAL code belonging to a DIFFERENT customer (Beta's own) -- Alpha
  -- attempting it must get the identical generic error, not a distinguishable
  -- one that would confirm the code is real but not hers.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_beta_owned_code, null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed for a real but foreign-owner code';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- 3. An already-redeemed code (Alpha's own, redeemed above).
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_alpha_code, null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed for an already-redeemed code';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- 4. An expired code.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_expired_code, null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed for an expired code';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- 5. A held code.
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_held_code, null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed for a held code';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- 6. A REAL code, but presented against the WRONG tenant (tenant2, where
  -- it structurally cannot be found).
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant2, v_beta_owned_code, null, v_customer_delta, 'customer-delta');
    raise exception 'assertion failed: expected voucher_redemption_failed for a real code presented against the wrong tenant';
  exception when others then v_messages := array_append(v_messages, sqlerrm);
  end;

  -- Adversarial proof: every one of the 6 distinct failure causes above
  -- produced the BYTE-IDENTICAL error message -- no oracle for guessing a
  -- valid code, whether the code is forged, real-but-foreign, already used,
  -- expired, held, or presented against the wrong tenant.
  foreach v_msg in array v_messages loop
    if v_msg <> v_messages[1] or v_msg <> 'voucher_redemption_failed: this voucher code cannot be redeemed' then
      raise exception 'assertion failed: expected every adversarial redemption attempt to raise the IDENTICAL message, got %', v_messages;
    end if;
  end loop;

  -- A genuinely different customer (Beta) using her OWN real code succeeds
  -- normally -- proving the anti-enumeration collapse above is about
  -- OWNERSHIP/validity, not a blanket code-path failure.
  v_redeemed := app.redeem_loyalty_benefit_entitlement(v_tenant1, v_beta_owned_code, null, v_customer_beta, 'customer-beta');
  if v_redeemed.status <> 'redeemed' then
    raise exception 'assertion failed: expected Beta''s own real code redemption to succeed, got %', v_redeemed;
  end if;

  -- Staff (LYL:Edit) may ALSO redeem by code -- the held code, once
  -- released, redeems normally for staff (proven in the fraud-hold section
  -- below); here just confirm staff redeeming a genuinely nonexistent code
  -- gets the SAME generic message too (staff is not exempted from the
  -- anti-enumeration collapse on the code path, design decision 5b).
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, 'CGV-9999-9999', null, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected voucher_redemption_failed for staff too, on a forged code';
  exception when others then if sqlerrm <> 'voucher_redemption_failed: this voucher code cannot be redeemed' then raise; end if;
  end;
end $$;

\echo '>> fraud hold: mandatory reason, idempotent, blocks redemption (both id and code paths), release restores redemption -- mirrors CPL-317''s own governing principles (design decision 3)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000342004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_held app.loyalty_benefit_entitlements;
  v_held2 app.loyalty_benefit_entitlements;
  v_released app.loyalty_benefit_entitlements;
  v_redeemed app.loyalty_benefit_entitlements;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 30, null, 'USD', 'manual', null, now() + interval '30 days', 'issue-hold-cycle', v_manager1a, 'manager1a');

  -- Blank reason rejected.
  begin
    perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, '', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected reason_required for a blank hold reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Plain User denied.
  begin
    perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, 'x', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User (LYL:Configure required)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_held := app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, 'Suspected fraud -- chargeback dispute in progress', v_manager1a, 'manager1a');
  if v_held.status <> 'held' or v_held.is_fraud_hold <> true or v_held.hold_reason <> 'Suspected fraud -- chargeback dispute in progress' then
    raise exception 'assertion failed: expected a real held entitlement, got %', v_held;
  end if;

  -- Idempotent: a repeat hold with a DIFFERENT reason is a no-op preserving
  -- the ORIGINAL reason.
  v_held2 := app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, 'a different reason', v_manager1a, 'manager1a');
  if v_held2.hold_reason <> v_held.hold_reason or v_held2.held_at <> v_held.held_at then
    raise exception 'assertion failed: expected a repeat hold to preserve the ORIGINAL reason/held_at, got % vs original %', v_held2, v_held;
  end if;

  -- Blocked while held -- both by id (staff) and by code (owning customer).
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_row.id::text, v_held.record_version, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_transition -- a held entitlement may not be redeemed by id';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_row.raw_code, null, v_customer_alpha, 'customer-alpha');
    raise exception 'assertion failed: expected voucher_redemption_failed -- a held voucher may not be redeemed by code';
  exception when others then if sqlerrm not like 'voucher_redemption_failed%' then raise; end if;
  end;

  -- Release restores redemption.
  v_released := app.release_loyalty_benefit_entitlement_hold(v_tenant1, v_row.id, v_manager1a, 'manager1a');
  if v_released.status <> 'issued' or v_released.is_fraud_hold <> false then
    raise exception 'assertion failed: expected release to restore status=issued, is_fraud_hold=false, got %', v_released;
  end if;

  v_redeemed := app.redeem_loyalty_benefit_entitlement(v_tenant1, v_row.raw_code, null, v_customer_alpha, 'customer-alpha');
  if v_redeemed.status <> 'redeemed' then
    raise exception 'assertion failed: expected redemption to succeed after release, got %', v_redeemed;
  end if;

  -- Releasing a never-held / already-released entitlement is rejected.
  begin
    perform app.release_loyalty_benefit_entitlement_hold(v_tenant1, v_row.id, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected entitlement_not_held for an already-released (now redeemed) entitlement';
  exception when others then if sqlerrm not like 'entitlement_not_held%' then raise; end if;
  end;
end $$;

\echo '>> app.reverse_loyalty_benefit_entitlement: history preserved (never delete/rewrite), reversible from issued/held/redeemed, rejected from already-reversed, mandatory reason'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_original app.loyalty_benefit_entitlements;
  v_reversed app.loyalty_benefit_entitlements;
  v_event_count integer;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 60, null, 'USD', 'finance_invoice_cancelled', gen_random_uuid(), null, 'issue-reverse-from-issued', v_manager1a, 'manager1a');
  select * into v_original from app.loyalty_benefit_entitlements where id = v_row.id;

  -- Blank reason rejected.
  begin
    perform app.reverse_loyalty_benefit_entitlement(v_tenant1, v_row.id, v_row.record_version, '', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected reason_required for a blank reversal reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_reversed := app.reverse_loyalty_benefit_entitlement(v_tenant1, v_row.id, v_row.record_version, 'source invoice was cancelled', v_manager1a, 'manager1a');
  if v_reversed.status <> 'reversed' then
    raise exception 'assertion failed: expected status reversed, got %', v_reversed;
  end if;
  -- History preserved: id, value_amount, currency, created_at all
  -- byte-for-byte unchanged -- never a delete, never a rewrite of the
  -- original issuance facts.
  if v_reversed.id <> v_original.id or v_reversed.value_amount <> v_original.value_amount
     or v_reversed.currency <> v_original.currency or v_reversed.created_at <> v_original.created_at then
    raise exception 'assertion failed: reversal must preserve the original row''s own issuance facts, got % vs original %', v_reversed, v_original;
  end if;
  select count(*) into v_event_count from app.loyalty_benefit_entitlement_events where entitlement_id = v_row.id;
  if v_event_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 events (issued, reversed) for this entitlement, got %', v_event_count;
  end if;

  -- Already-reversed cannot be reversed again.
  begin
    perform app.reverse_loyalty_benefit_entitlement(v_tenant1, v_row.id, v_reversed.record_version, 'again', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_transition for an already-reversed entitlement';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Reversal is also allowed from an already-REDEEMED entitlement (business
  -- rule: "reversed after source transaction cancellation... policy").
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'discount', 10, null, 'USD', 'manual', null, null, 'issue-reverse-from-redeemed', v_manager1a, 'manager1a');
  perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_row.id::text, v_row.record_version, v_manager1a, 'manager1a');
  v_reversed := app.reverse_loyalty_benefit_entitlement(v_tenant1, v_row.id, 2, 'invoice disputed after redemption', v_manager1a, 'manager1a');
  if v_reversed.status <> 'reversed' then
    raise exception 'assertion failed: expected a redeemed entitlement to be reversible, got %', v_reversed;
  end if;
end $$;

\echo '>> app.expire_loyalty_benefit_entitlements: expires a due entitlement (directly fixture-backdated, never through the RPC), idempotent re-run, a HELD entitlement past its own expiry is NOT swept (disclosed boundary)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000342004';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_held_row record;
  v_entries app.loyalty_benefit_entitlements[];
  v_entries2 app.loyalty_benefit_entitlements[];
  v_after app.loyalty_benefit_entitlements;
  v_held_after app.loyalty_benefit_entitlements;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 5, null, 'USD', 'manual', null, now() + interval '90 days', 'issue-expire-scan', v_manager1a, 'manager1a');
  update app.loyalty_benefit_entitlements set expires_at = clock_timestamp() - interval '1 day' where id = v_row.id;

  select * into v_held_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'voucher', 5, null, 'USD', 'manual', null, now() + interval '90 days', 'issue-expire-scan-held', v_manager1a, 'manager1a');
  update app.loyalty_benefit_entitlements set expires_at = clock_timestamp() - interval '1 day' where id = v_held_row.id;
  perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_held_row.id, 'held before expiry scan runs', v_manager1a, 'manager1a');

  begin
    perform app.expire_loyalty_benefit_entitlements(v_tenant1, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_entries := array(select app.expire_loyalty_benefit_entitlements(v_tenant1, v_manager1a, 'manager1a'));
  if array_length(v_entries, 1) is null or not (v_row.id = any (select id from unnest(v_entries) e)) then
    raise exception 'assertion failed: expected the due entitlement to appear in this run''s expired set, got %', v_entries;
  end if;
  if v_row.id = any (select id from unnest(v_entries) e where e.id = v_held_row.id) then
    raise exception 'assertion failed: the HELD entitlement must NOT be swept by expiry (disclosed boundary)';
  end if;

  select * into v_after from app.loyalty_benefit_entitlements where id = v_row.id;
  if v_after.status <> 'expired' then
    raise exception 'assertion failed: expected the due entitlement to be expired, got %', v_after;
  end if;
  select * into v_held_after from app.loyalty_benefit_entitlements where id = v_held_row.id;
  if v_held_after.status <> 'held' then
    raise exception 'assertion failed: expected the held entitlement to remain held (not swept), got %', v_held_after;
  end if;

  -- Idempotent re-run: the already-expired row no longer matches the scan.
  v_entries2 := array(select app.expire_loyalty_benefit_entitlements(v_tenant1, v_manager1a, 'manager1a'));
  if v_row.id = any (select id from unnest(v_entries2) e) then
    raise exception 'assertion failed: expected the second expire run to be a no-op for the already-expired entitlement';
  end if;
end $$;

\echo '>> cross-tenant/cross-account isolation: tenant cbv2''s own manager cannot act on cbv1 data; customer wallet listings never leak another account''s entitlements'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cbv2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000342101';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000342020';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000342110';
  v_cbv1_entitlement_id uuid := (select id from app.loyalty_benefit_entitlements where tenant_id = v_tenant1 limit 1);
  v_beta_rows record;
  v_delta_rows integer;
begin
  -- cbv2's manager, passing cbv1's own tenant_id, has no role assignment
  -- there -- rejected.
  begin
    perform app.get_loyalty_benefit_entitlement(v_tenant1, v_cbv1_entitlement_id, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant staff actor';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Delta (tenant cbv2) sees zero cbv1 rows, even if cbv1''s own tenant_id
  -- were passed -- deny-by-default via resolve_customer_account_scope,
  -- never an error.
  select count(*) into v_delta_rows from app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_customer_delta, p_limit => 200);
  if v_delta_rows <> 0 then
    raise exception 'assertion failed: expected zero cbv1 rows for a cbv2 customer, got %', v_delta_rows;
  end if;

  -- Beta''s own wallet listing never includes another customer''s (Alpha''s
  -- or Gamma''s) entitlements -- every returned row''s own loyalty_account_id
  -- must resolve back to Beta''s own account.
  for v_beta_rows in select * from app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_customer_beta, p_limit => 200) loop
    if v_beta_rows.loyalty_account_id <> (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbv Account Beta')) then
      raise exception 'assertion failed: Beta''s own wallet listing leaked a row belonging to a different account: %', v_beta_rows;
    end if;
  end loop;
end $$;

\echo '>> customer-facing wallet: never exposes code_hash/idempotency_key/source_type/source_id/config_version/the real hold_reason; a held entitlement shows is_on_hold + a generic notice'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cbv1') and legal_name = 'Cbv Account Alpha'));
  v_row record;
  v_wallet record;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_account_alpha, 'cashback', 22, null, 'USD', 'manual', null, null, 'issue-wallet-hold-view', v_manager1a, 'manager1a');
  perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_row.id, 'Internal fraud investigation ref #9001 -- must never leak to the customer', v_manager1a, 'manager1a');

  select * into v_wallet from app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_customer_alpha, p_customer_account_id => (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbv Account Alpha')) w where w.id = v_row.id;
  if v_wallet.is_on_hold <> true then
    raise exception 'assertion failed: expected is_on_hold=true, got %', v_wallet;
  end if;
  if v_wallet.hold_notice is null or v_wallet.hold_notice like '%Internal fraud investigation%' then
    raise exception 'assertion failed: hold_notice must be a generic customer-safe message, never the real hold_reason, got %', v_wallet.hold_notice;
  end if;
  if (to_jsonb(v_wallet) ? 'code_hash') or (to_jsonb(v_wallet) ? 'idempotency_key') or (to_jsonb(v_wallet) ? 'source_type') or (to_jsonb(v_wallet) ? 'source_id') or (to_jsonb(v_wallet) ? 'config_version') or (to_jsonb(v_wallet) ? 'hold_reason') then
    raise exception 'assertion failed: the customer-facing projection must never carry an internal-only column, got %', to_jsonb(v_wallet);
  end if;
end $$;

\echo '>> raw-table RLS / raw-function-grant defense-in-depth: authenticated has zero direct SELECT on either new table; anon has zero EXECUTE on any of the 10 new functions'
do $$
begin
  set local role authenticated;
  begin
    perform 1 from app.loyalty_benefit_entitlements limit 1;
    raise exception 'assertion failed: expected a real permission-denied error for a raw authenticated SELECT on app.loyalty_benefit_entitlements';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from app.loyalty_benefit_entitlement_events limit 1;
    raise exception 'assertion failed: expected a real permission-denied error for a raw authenticated SELECT on app.loyalty_benefit_entitlement_events';
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
    'issue_loyalty_benefit_entitlement', 'redeem_loyalty_benefit_entitlement', 'reverse_loyalty_benefit_entitlement',
    'expire_loyalty_benefit_entitlements', 'hold_loyalty_benefit_entitlement', 'release_loyalty_benefit_entitlement_hold',
    'get_loyalty_benefit_entitlement', 'list_loyalty_benefit_entitlements', 'list_loyalty_benefit_entitlement_events',
    'list_customer_portal_loyalty_benefit_entitlements'
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

\echo '>> actor-identity session cross-check: a genuinely different authenticated session (impersonator) claiming to act as Manager A is rejected on every new RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_entitlement_id uuid := (select id from app.loyalty_benefit_entitlements where tenant_id = v_tenant1 limit 1);
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000342050", "role": "authenticated"}';

  begin
    perform app.issue_loyalty_benefit_entitlement(v_tenant1, gen_random_uuid(), 'cashback', 1, null, 'USD', 'manual', null, null, 'imp-1', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.issue_loyalty_benefit_entitlement';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.redeem_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id::text, null, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.redeem_loyalty_benefit_entitlement';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.reverse_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id, 1, 'x', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.reverse_loyalty_benefit_entitlement';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.expire_loyalty_benefit_entitlements(v_tenant1, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.expire_loyalty_benefit_entitlements';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.hold_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id, 'x', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.hold_loyalty_benefit_entitlement';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.release_loyalty_benefit_entitlement_hold(v_tenant1, v_entitlement_id, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.release_loyalty_benefit_entitlement_hold';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_benefit_entitlement';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_benefit_entitlements(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_benefit_entitlements';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_benefit_entitlement_events(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_benefit_entitlement_events';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_benefit_entitlements';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (impersonator holds Manager
  -- A's own role too) is NOT rejected -- succeeds on its own authority.
  perform app.get_loyalty_benefit_entitlement(v_tenant1, v_entitlement_id, '00000000-0000-0000-0000-000000342050');

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: Alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000342010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_customer_alpha, p_limit => 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000342010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_loyalty_benefit_entitlements(v_tenant1, v_customer_alpha, p_limit => 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

\echo '>> keyset pagination on app.list_loyalty_benefit_entitlements and app.list_loyalty_benefit_entitlement_events: visits every row exactly once at limit=1, never OFFSET; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_benefit_entitlements[];
  v_seen_count integer := 0;
  v_total_pages integer := 0;
  v_row app.loyalty_benefit_entitlements;
  v_expected_count integer;
  v_cursor_created_at timestamptz := null;
  v_event_cursor_id uuid := null;
  v_event_page app.loyalty_benefit_entitlement_events[];
  v_event_seen_count integer := 0;
  v_event_row app.loyalty_benefit_entitlement_events;
  v_expected_event_count integer;
begin
  select count(*) into v_expected_count from app.loyalty_benefit_entitlements where tenant_id = v_tenant1;
  loop
    v_page := array(select app.list_loyalty_benefit_entitlements(v_tenant1, v_manager1a, p_cursor_updated_at => v_cursor_updated_at, p_cursor_id => v_cursor_id, p_limit => 1));
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
    raise exception 'assertion failed: expected keyset pagination to visit every one of % entitlement rows exactly once, saw %', v_expected_count, v_seen_count;
  end if;

  begin
    perform app.list_loyalty_benefit_entitlements(v_tenant1, v_manager1a, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;

  select count(*) into v_expected_event_count from app.loyalty_benefit_entitlement_events where tenant_id = v_tenant1;
  loop
    v_event_page := array(select app.list_loyalty_benefit_entitlement_events(v_tenant1, v_manager1a, p_cursor_created_at => v_cursor_created_at, p_cursor_id => v_event_cursor_id, p_limit => 1));
    exit when array_length(v_event_page, 1) is null;
    foreach v_event_row in array v_event_page loop
      v_event_seen_count := v_event_seen_count + 1;
      v_cursor_created_at := v_event_row.created_at;
      v_event_cursor_id := v_event_row.id;
    end loop;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 400 then
      raise exception 'assertion failed: keyset pagination (events) did not terminate within budget';
    end if;
  end loop;
  if v_event_seen_count <> v_expected_event_count then
    raise exception 'assertion failed: expected keyset pagination to visit every one of % event rows exactly once, saw %', v_expected_event_count, v_event_seen_count;
  end if;
end $$;

\echo '>> ISS-2026-129 item 2: app.loyalty_benefit_issuance_rules + app.run_loyalty_benefit_issuance_rule_sweep -- a tenant-configured recurring rule issues to every active enrolled account exactly once per its own recurrence window, never re-issues early, and respects inactive/authority boundaries'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbv1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000342001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000342004';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'cbv1') and name = 'Cashback Rewards');
  v_rule app.loyalty_benefit_issuance_rules;
  v_updated app.loyalty_benefit_issuance_rules;
  v_sweep record;
  v_issued_count integer;
begin
  -- Plain User denied.
  begin
    perform app.create_loyalty_benefit_issuance_rule(v_tenant1, v_program_id, 'cashback', 15, null, 'USD', null, null, 30, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User creating an issuance rule';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_rule := app.create_loyalty_benefit_issuance_rule(v_tenant1, v_program_id, 'cashback', 15, null, 'USD', null, null, 30, v_manager1a, 'manager1a');
  if v_rule.status <> 'active' or v_rule.value_amount <> 15 or v_rule.recurrence_interval_days <> 30 then
    raise exception 'assertion failed: expected a real, active issuance rule, got %', v_rule;
  end if;

  -- First sweep: Alpha/Beta/Gamma are all active enrolled accounts on this program
  -- with no prior issuance from this rule -- all three are due.
  select * into v_sweep from app.run_loyalty_benefit_issuance_rule_sweep(v_tenant1, clock_timestamp(), v_manager1a, 'manager1a', 'iss2026129-rule-run-1');
  if v_sweep.processed_count <> 3 or v_sweep.skipped_count <> 0 then
    raise exception 'assertion failed: expected the first sweep to issue to exactly 3 accounts with 0 skips, got processed=% skipped=%', v_sweep.processed_count, v_sweep.skipped_count;
  end if;

  select count(*) into v_issued_count from app.loyalty_benefit_entitlements
  where tenant_id = v_tenant1 and source_type = 'loyalty_benefit_issuance_rule' and source_id = v_rule.id;
  if v_issued_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 entitlements attributed to this rule, got %', v_issued_count;
  end if;

  -- Second sweep, same instant, a genuinely distinct run (own run_label, so
  -- app.enqueue_job''s own idempotency does not merely replay run 1''s cached
  -- counts): every account was just issued to, so every one is inside its own
  -- 30-day recurrence window -- none are due yet. This is the load-bearing proof
  -- that the sweep does not re-issue on every run.
  select * into v_sweep from app.run_loyalty_benefit_issuance_rule_sweep(v_tenant1, clock_timestamp(), v_manager1a, 'manager1a', 'iss2026129-rule-run-2');
  if v_sweep.processed_count <> 0 then
    raise exception 'assertion failed: expected the second (same-window) sweep to issue to 0 accounts, got processed=%', v_sweep.processed_count;
  end if;

  select count(*) into v_issued_count from app.loyalty_benefit_entitlements
  where tenant_id = v_tenant1 and source_type = 'loyalty_benefit_issuance_rule' and source_id = v_rule.id;
  if v_issued_count <> 3 then
    raise exception 'assertion failed: expected still exactly 3 entitlements after the second (not-yet-due) sweep, got %', v_issued_count;
  end if;

  -- NULL-bypass hardening on update: a null p_expected_version is rejected outright.
  begin
    perform app.update_loyalty_benefit_issuance_rule(v_tenant1, v_rule.id, null, 15, null, 'USD', null, null, 30, 'active', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected expected_version_required for a null p_expected_version';
  exception when others then if sqlerrm not like 'expected_version_required%' then raise; end if;
  end;

  -- A stale version is rejected.
  begin
    perform app.update_loyalty_benefit_issuance_rule(v_tenant1, v_rule.id, v_rule.record_version + 1, 15, null, 'USD', null, null, 30, 'active', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected stale_version for a wrong p_expected_version';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Deactivating the rule via the real, versioned update RPC stops the sweep from
  -- issuing to it, even once accounts are otherwise due again.
  v_updated := app.update_loyalty_benefit_issuance_rule(v_tenant1, v_rule.id, v_rule.record_version, 15, null, 'USD', null, null, 30, 'inactive', v_manager1a, 'manager1a');
  if v_updated.status <> 'inactive' or v_updated.record_version <> v_rule.record_version + 1 then
    raise exception 'assertion failed: expected the rule to be inactive at record_version %, got %', v_rule.record_version + 1, v_updated;
  end if;

  select * into v_sweep from app.run_loyalty_benefit_issuance_rule_sweep(v_tenant1, clock_timestamp() + interval '31 days', v_manager1a, 'manager1a', 'iss2026129-rule-run-3-inactive');
  if v_sweep.processed_count <> 0 then
    raise exception 'assertion failed: expected an inactive rule to issue to 0 accounts even after its own recurrence window elapsed, got processed=%', v_sweep.processed_count;
  end if;

  -- Genuinely reactivating and advancing past the recurrence window DOES issue
  -- again -- proves the skip above was the inactive-rule gate, not a stuck
  -- idempotency key or a permanently-exhausted candidate set.
  perform app.update_loyalty_benefit_issuance_rule(v_tenant1, v_rule.id, v_updated.record_version, 15, null, 'USD', null, null, 30, 'active', v_manager1a, 'manager1a');
  select * into v_sweep from app.run_loyalty_benefit_issuance_rule_sweep(v_tenant1, clock_timestamp() + interval '31 days', v_manager1a, 'manager1a', 'iss2026129-rule-run-4-reactivated');
  if v_sweep.processed_count <> 3 then
    raise exception 'assertion failed: expected a reactivated rule, 31 days later, to issue to all 3 due accounts again, got processed=%', v_sweep.processed_count;
  end if;

  select count(*) into v_issued_count from app.loyalty_benefit_entitlements
  where tenant_id = v_tenant1 and source_type = 'loyalty_benefit_issuance_rule' and source_id = v_rule.id;
  if v_issued_count <> 6 then
    raise exception 'assertion failed: expected 3 (first window) + 3 (second window) = 6 entitlements attributed to this rule, got %', v_issued_count;
  end if;

  -- The scheduler catalogue actually carries this task, and the dispatcher has a
  -- real branch for it -- not merely a function that exists in isolation.
  if not exists (select 1 from app.scheduled_task_definitions where task_code = 'loyalty_benefit_issuance_sweep') then
    raise exception 'assertion failed: expected loyalty_benefit_issuance_sweep to be a real scheduler catalogue task';
  end if;
end $$;

\echo 'ALL PASSED: CPL-319 Cashback Discount Voucher'
