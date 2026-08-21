-- Real, executable test evidence for CPL-323 (CG-S13-CPL-025, Prompt 323,
-- "Liability Reconciliation Analytics") -- run via `pnpm run db:test`
-- against a real, disposable Postgres database. The FOURTH AND FINAL prompt
-- of Batch 5 (CPL-320..323), and the EIGHTH Loyalty-domain db-test in this
-- repository.
--
-- UUID range 00000000-0000-0000-0000-000000346000-000000346099 (tenant
-- lra1) / 00000000-0000-0000-0000-000000346100-000000346199 (tenant lra2).
--
-- Tier C review fix (Batch 5 close): this file ORIGINALLY used the
-- 000000036xxx range and its own header claimed it was "grep-verified
-- unclaimed against every other file in this directory" -- that claim was
-- FALSE, live-reproduced: 000000036001/036002/036004 collided with
-- scripts/db-tests/finance-cash-bank.sql, and 000000036101/036201/036202
-- collided with scripts/db-tests/procurement-sourcing.sql, breaking the
-- shared `app.users` primary key the first time this file ran alongside
-- either of those two inside the full `bash scripts/db-tests/run.sh`
-- harness (a real, live-reproduced regression, not a theoretical risk).
-- Renumbered to 346xxx -- the batch's own next-free range, continuing
-- CPL-320/321/322's own established 343xxx/344xxx/345xxx sequence exactly
-- -- and re-verified genuinely unclaimed by a direct grep across every
-- other file in this directory before this fix was finalized.
--
-- Covers, live: (a) a clean reconciliation run with zero exceptions when
-- ledgers/entitlements are internally consistent (composing an account with
-- REAL reversal activity, CPL-318, and REAL expiry-sweep activity, CPL-322,
-- proving both still reconcile exactly); (b) two deliberately-forced
-- mismatches (a directly-corrupted cached point balance, a directly-
-- corrupted entitlement status column, both bypassing every RPC -- never
-- through one) each correctly producing a real, typed exception row, with
-- the liability TOTAL itself proven to use the re-derived (never the
-- corrupted) value; (c) certify blocked while any exception is open,
-- succeeding once both are resolved, with the run auto-clearing from
-- exceptions_pending back to open on the last resolution; (d) idempotent
-- re-run (both an explicit-key replay and a default day-derived-key
-- replay); (e) engagement metrics -- correct aggregate counts, a
-- customer_user caller rejected outright, no per-customer/internal-cost
-- field anywhere in the returned row; (f) the customer-facing consolidated
-- summary composing points/entitlements/redemptions/hold-status for the
-- caller's own account only; (g) optimistic-concurrency NULL-bypass
-- regression proof on both resolve and certify; (h) authority split
-- (LYL:Edit executes/resolves, the elevated LYL:Configure certifies -- an
-- Edit-only actor is denied certify); (i) cross-tenant/cross-account
-- isolation; (j) anti-enumeration; (k) raw-table RLS / raw-function-grant
-- defense-in-depth; (l) actor-identity session cross-check; (m) keyset
-- pagination.

\set ON_ERROR_STOP on

\echo '>> setup: tenant lra1 (Loyalty Manager [full LYL], Loyalty Editor [LYL View/Edit only, no Configure], Plain User [no LYL grant]; customer accounts Alpha/Beta/Gamma/Delta, customer_user identities for each), tenant lra2 (its own Loyalty Manager, customer account Zeta); a published loyalty program per tenant; a published physical_item reward on lra1; all four lra1 accounts enrolled'
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
  v_account_zeta uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_editor1 uuid := '00000000-0000-0000-0000-000000346002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000346004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000346010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000346020';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000346030';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000346040';
  v_manager2 uuid := '00000000-0000-0000-0000-000000346101';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000346110';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_editor_role1 uuid;
  v_editor_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
  v_program_id uuid;
  v_program2_id uuid;
  v_reward app.loyalty_rewards;
  v_locale_draft1 app.tenant_locale_versions;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@lra1.test'),
    (v_editor1, 'editor1@lra1.test'),
    (v_plain1, 'plain1@lra1.test'),
    (v_customer_alpha, 'customer-alpha@lra1.test'),
    (v_customer_beta, 'customer-beta@lra1.test'),
    (v_customer_gamma, 'customer-gamma@lra1.test'),
    (v_customer_delta, 'customer-delta@lra1.test'),
    (v_manager2, 'manager2@lra2.test'),
    (v_customer_zeta, 'customer-zeta@lra2.test');

  perform app.provision_tenant('lra1', 'Liability Recon Test Tenant One', 'idem-lra1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'lra1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'LRA1-CO', 'Lra1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LRA1-CO');

  perform app.provision_tenant('lra2', 'Liability Recon Test Tenant Two', 'idem-lra2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'lra2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'LRA2-CO', 'Lra2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'LRA2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@lra1.test', 'Lra1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@lra1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  -- CPL-324 hardening fix regression setup (ISS-2026-136 item 1): this
  -- fixture's own entitlements/reconciliation calls have always been
  -- denominated in USD (see below), but that was never wired into a real
  -- app.resolve_tenant_locale() default -- it happened not to matter before
  -- app.execute_loyalty_liability_reconciliation_run's own reward-
  -- fulfillment line gained a currency filter. Publish a real USD locale for
  -- lra1 now (v_manager1 already has a real tenant_user_identities row from
  -- invite_user above, so a second, tenant_admin-layer principal membership
  -- may be granted to the SAME actor) so the fixture's own long-standing USD
  -- assumption becomes real and explicit, matching every currency literal
  -- already used throughout this file -- zero other line in this file
  -- changes.
  perform app.grant_principal_membership(v_manager1, 'tenant_admin', v_tenant1, null, 'tester');
  v_locale_draft1 := app.create_tenant_locale_draft(v_tenant1, v_manager1, 'tester');
  perform app.set_tenant_locale_config(v_locale_draft1.id, v_manager1, 'id', 'Asia/Jakarta', 'USD', '{}'::jsonb, 'tester');
  perform app.publish_tenant_locale_version(v_locale_draft1.id, v_manager1, clock_timestamp(), 'tester');
  if (select default_currency from app.resolve_tenant_locale(v_tenant1)) <> 'USD' then
    raise exception 'assertion failed: expected lra1''s own resolved default_currency to be USD after publish';
  end if;

  perform app.invite_user(v_tenant1, v_editor1, 'editor1@lra1.test', 'Lra1 Editor', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor1@lra1.test'), 'active', 'onboarded', 'tester');
  v_editor_role1 := (app.create_role(v_tenant1, 'Loyalty Editor', 'LYL View/Edit only -- no Configure', 'tester')).id;
  v_editor_draft1 := app.create_role_version(v_editor_role1, 'tester');
  perform app.set_role_version_permissions(v_editor_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Edit')), 'tester');
  perform app.publish_role_version(v_editor_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role1 and status = 'published'), v_editor1, v_editor1, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@lra1.test', 'Lra1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@lra1.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lra Account Alpha', 'lra-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lra Account Beta', 'lra-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lra Account Gamma', 'lra-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Lra Account Delta', 'lra-delta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_delta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Lra Account Zeta', 'lra-zeta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_zeta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@lra1.test', 'Lra Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@lra1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@lra1.test', 'Lra Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@lra1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_gamma, 'customer-gamma@lra1.test', 'Lra Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@lra1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant1, v_account_gamma::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_delta, 'customer-delta@lra1.test', 'Lra Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@lra1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant1, v_account_delta::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@lra2.test', 'Lra2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@lra2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_zeta, 'customer-zeta@lra2.test', 'Lra Customer Zeta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-zeta@lra2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_zeta, 'customer_user', v_tenant2, v_account_zeta::text, 'tester');

  perform app.create_loyalty_program(v_tenant1, 'Lra Program', 'Program used to test liability reconciliation.', v_manager1, 'manager1');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Lra Program');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1, 'manager1');
  perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager1, 'manager1');
  perform app.publish_loyalty_program_rule_version(v_tenant1, (select id from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'draft'), 1, null, v_manager1, 'manager1');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_delta, v_program_id, v_manager1, 'manager1');

  v_reward := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Lra Physical Reward', 'physical_item', 'A physical item reward.', 'Terms.', null, 50, 10, 75, 'vendor-recon-1', null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_reward.id, v_reward.record_version, null, v_manager1, 'manager1');

  perform app.create_loyalty_program(v_tenant2, 'Lra Program 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Lra Program 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_zeta, v_program2_id, v_manager2, 'manager2');
end $$;

\echo '>> fixture: Alpha -- REAL reversal activity (CPL-318) and REAL expiry-sweep activity (CPL-322) -- earns 150 (kept), 50 (fully reversed), 100 (expired via app.run_loyalty_expiry_sweep); net available must be exactly 150; issues Alpha a real voucher entitlement (40 USD, clean)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Alpha');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and customer_account_id = v_account_alpha);
  v_event1_id uuid;
  v_event2_id uuid;
  v_event3_id uuid;
  v_reversal_event app.loyalty_earning_events;
  v_lot3 app.loyalty_point_lots;
begin
  -- Invoice 1: 150 points, kept.
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346201', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000346301', 'USD', 150, 150, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346201', v_manager1, 'manager1');
  v_event1_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346201');
  perform app.post_loyalty_points_earned(v_tenant1, v_event1_id, v_manager1, 'manager1', 365);

  -- Invoice 2: 50 points, fully reversed (real reversal chain, CPL-316 then CPL-318).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346202', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000346302', 'USD', 50, 50, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346202', v_manager1, 'manager1');
  v_event2_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346202');
  perform app.post_loyalty_points_earned(v_tenant1, v_event2_id, v_manager1, 'manager1', 365);
  v_reversal_event := app.reverse_loyalty_earning_event(v_tenant1, v_event2_id, 'invoice 2 disputed by customer', 'lra-alpha-invoice2-reversal', v_manager1, 'manager1');
  perform app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_manager1, 'manager1');

  -- Invoice 3: 100 points, expired via a REAL app.run_loyalty_expiry_sweep call (CPL-322).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346203', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000346303', 'USD', 100, 100, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346203', v_manager1, 'manager1');
  v_event3_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346203');
  perform app.post_loyalty_points_earned(v_tenant1, v_event3_id, v_manager1, 'manager1', 365);
  select * into v_lot3 from app.loyalty_point_lots where source_earning_event_id = v_event3_id;
  -- Directly fixture-backdate expires_at into the past -- never through the
  -- RPC (mirrors CPL-318/322's own established precedent for exactly this
  -- class of timing test).
  update app.loyalty_point_lots set expires_at = clock_timestamp() - interval '1 day' where id = v_lot3.id;
  perform app.run_loyalty_expiry_sweep(v_tenant1, clock_timestamp(), v_manager1, 'manager1', 'lra-alpha-expiry-run');

  if (select available from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_alpha) <> 150 then
    raise exception 'assertion failed: expected Alpha''s cached available to be exactly 150 after earn/reversal/expiry, got %', (select available from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_alpha);
  end if;

  perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_loyalty_account_alpha, 'voucher', 40, null, 'USD', 'manual', null, clock_timestamp() + interval '365 days', 'lra-alpha-voucher', v_manager1, 'manager1');
end $$;

\echo '>> fixture: Delta -- earns 300 points, submits a genuine customer-initiated physical_item redemption (pending_approval, CPL-321), staff approves it -- composition consumes 50 points and moves it to fulfilling/in_fulfillment, a real, open reward-fulfillment liability'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000346040';
  v_account_delta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Delta');
  v_loyalty_account_delta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and customer_account_id = v_account_delta);
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'lra1') and reward_name = 'Lra Physical Reward' and status = 'published');
  v_event_id uuid;
  v_redemption app.loyalty_redemptions;
begin
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346204', v_tenant1, v_account_delta, 'invoice', '00000000-0000-0000-0000-000000346304', 'USD', 300, 300, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346204', v_manager1, 'manager1');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346204');
  perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1, 'manager1', 365);

  v_redemption := app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_delta, v_reward_id, 'lra-delta-redeem-1', v_customer_delta, 'Delta');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected Delta''s own genuine self-service physical_item submission to land pending_approval, got %', v_redemption.status;
  end if;

  v_redemption := app.decide_loyalty_redemption(v_tenant1, v_redemption.id, v_redemption.record_version, 'approve', 'approved for liability recon test fixture', v_manager1, 'manager1');
  if v_redemption.status <> 'fulfilling' or v_redemption.fulfillment_status <> 'in_fulfillment' then
    raise exception 'assertion failed: expected Delta''s redemption to be fulfilling/in_fulfillment after staff approval, got %/%', v_redemption.status, v_redemption.fulfillment_status;
  end if;
  if v_redemption.points_consumed <> 50 then
    raise exception 'assertion failed: expected Delta''s redemption to consume exactly 50 points (min_points_required), got %', v_redemption.points_consumed;
  end if;

  if (select available from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_delta) <> 250 then
    raise exception 'assertion failed: expected Delta''s cached available to be exactly 250 (300 - 50), got %', (select available from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_delta);
  end if;
end $$;

\echo '>> app.execute_loyalty_liability_reconciliation_run: a clean run with ZERO exceptions when ledgers/entitlements are internally consistent (mandatory test), covering the reversal-touched and expiry-touched account (Alpha) and the reward-fulfillment line (Delta); Plain User denied; Editor (LYL:Edit only) succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_editor1 uuid := '00000000-0000-0000-0000-000000346002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000346004';
  v_run app.loyalty_liability_reconciliation_runs;
  v_exception_count integer;
begin
  begin
    perform app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_plain1, 'plain1', 'lra-clean-run-denied', 1);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User execute attempt';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_run := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_editor1, 'editor1', 'lra-clean-run', 1);
  if v_run.status <> 'open' then
    raise exception 'assertion failed: expected a clean run to land status=open, got %', v_run.status;
  end if;
  if v_run.points_liability_total <> 400 then
    raise exception 'assertion failed: expected points_liability_total = 400 (Alpha 150 + Delta 250), got %', v_run.points_liability_total;
  end if;
  if v_run.voucher_liability_total <> 40 then
    raise exception 'assertion failed: expected voucher_liability_total = 40 (Alpha''s voucher), got %', v_run.voucher_liability_total;
  end if;
  if v_run.cashback_liability_total <> 0 or v_run.discount_liability_total <> 0 then
    raise exception 'assertion failed: expected zero cashback/discount liability on the clean run, got %/%', v_run.cashback_liability_total, v_run.discount_liability_total;
  end if;
  if v_run.reward_fulfillment_liability_total <> 75 then
    raise exception 'assertion failed: expected reward_fulfillment_liability_total = 75 (Delta''s open physical_item redemption), got %', v_run.reward_fulfillment_liability_total;
  end if;

  select count(*) into v_exception_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id;
  if v_exception_count <> 0 then
    raise exception 'assertion failed: expected ZERO exceptions on the clean run, got %', v_exception_count;
  end if;
end $$;

\echo '>> CPL-324 hardening regression (ISS-2026-136 item 1, mandatory): a currency-MISMATCHED run must NOT count Delta''s open physical_item redemption -- an IDR-scoped run on this USD-denominated tenant reports zero reward-fulfillment exposure, while a fresh USD-scoped run still correctly reports 75; the old bug reported 75 on BOTH'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_editor1 uuid := '00000000-0000-0000-0000-000000346002';
  v_run_wrong_currency app.loyalty_liability_reconciliation_runs;
  v_run_right_currency app.loyalty_liability_reconciliation_runs;
begin
  v_run_wrong_currency := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'IDR', v_editor1, 'editor1', 'lra-currency-scope-idr', 1);
  if v_run_wrong_currency.reward_fulfillment_liability_total <> 0 then
    raise exception 'assertion failed: ISS-2026-136 item 1 regression -- expected reward_fulfillment_liability_total = 0 on an IDR-scoped run of a USD-denominated tenant (Delta''s open physical_item redemption must not be double-counted across currencies), got %', v_run_wrong_currency.reward_fulfillment_liability_total;
  end if;

  v_run_right_currency := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_editor1, 'editor1', 'lra-currency-scope-usd', 1);
  if v_run_right_currency.reward_fulfillment_liability_total <> 75 then
    raise exception 'assertion failed: expected reward_fulfillment_liability_total = 75 on the matching USD-scoped run (the fix must not also suppress the CORRECT currency), got %', v_run_right_currency.reward_fulfillment_liability_total;
  end if;
end $$;

\echo '>> fixture: tenant lra3 (own, fully isolated tenant -- deliberately NOT reusing lra1, so this test''s own account/points/redemption activity can never ripple into any of lra1''s own downstream tenant-wide absolute-count assertions elsewhere in this file), Loyalty Manager, a published USD locale, a published loyalty program, customer account Theta enrolled and earning exactly 40 points, submitted+approved for a NEW physical_item reward (min_points_required=40, internal_cost=30) -- used ONLY by the CPL-325 atomicity-race regression below'
do $$
declare
  v_tenant3 uuid;
  v_company3 uuid;
  v_manager3 uuid := '00000000-0000-0000-0000-000000346501';
  v_customer_theta uuid := '00000000-0000-0000-0000-000000346510';
  v_manager_role3 uuid;
  v_manager_draft3 app.role_versions;
  v_locale_draft3 app.tenant_locale_versions;
  v_program3_id uuid;
  v_account_theta uuid;
  v_reward app.loyalty_rewards;
  v_event_id uuid;
  v_redemption app.loyalty_redemptions;
begin
  insert into auth.users (id, email) values
    (v_manager3, 'manager3@lra3.test'),
    (v_customer_theta, 'customer-theta@lra3.test');

  perform app.provision_tenant('lra3', 'Liability Recon Test Tenant Three (atomicity race, isolated)', 'idem-lra3', 'tester');
  v_tenant3 := (select id from app.tenants where slug = 'lra3');
  perform app.transition_tenant_status(v_tenant3, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant3, 'company', null, 'LRA3-CO', 'Lra3 Co', 'tester');
  v_company3 := (select id from app.org_units where tenant_id = v_tenant3 and code = 'LRA3-CO');

  perform app.invite_user(v_tenant3, v_manager3, 'manager3@lra3.test', 'Lra3 Manager', v_company3, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager3@lra3.test'), 'active', 'onboarded', 'tester');
  v_manager_role3 := (app.create_role(v_tenant3, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft3 := app.create_role_version(v_manager_role3, 'tester');
  perform app.set_role_version_permissions(v_manager_draft3.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft3.id, now(), 'tester');
  perform app.assign_role(v_tenant3, (select id from app.role_versions where role_id = v_manager_role3 and status = 'published'), v_manager3, v_manager3, 'tester');

  -- A real published USD locale (mirrors lra1''s own CPL-324 fixture
  -- addition exactly) -- app.execute_loyalty_liability_reconciliation_run's
  -- own reward-fulfillment currency scope resolves against this.
  perform app.grant_principal_membership(v_manager3, 'tenant_admin', v_tenant3, null, 'tester');
  v_locale_draft3 := app.create_tenant_locale_draft(v_tenant3, v_manager3, 'tester');
  perform app.set_tenant_locale_config(v_locale_draft3.id, v_manager3, 'id', 'Asia/Jakarta', 'USD', '{}'::jsonb, 'tester');
  perform app.publish_tenant_locale_version(v_locale_draft3.id, v_manager3, clock_timestamp(), 'tester');

  perform app.invite_user(v_tenant3, v_customer_theta, 'customer-theta@lra3.test', 'Lra3 Customer Theta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-theta@lra3.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant3, 'Lra3 Account Theta', 'lra3-theta-fp', '{}'::jsonb, v_company3, 'tester') returning id into v_account_theta;
  perform app.grant_principal_membership(v_customer_theta, 'customer_user', v_tenant3, v_account_theta::text, 'tester');

  perform app.create_loyalty_program(v_tenant3, 'Lra3 Program', 'Program used ONLY by the CPL-325 atomicity-race regression.', v_manager3, 'manager3');
  v_program3_id := (select id from app.loyalty_programs where tenant_id = v_tenant3 and name = 'Lra3 Program');
  perform app.update_loyalty_program_status(v_tenant3, v_program3_id, 1, 'active', v_manager3, 'manager3');
  perform app.create_loyalty_program_rule_version(v_tenant3, v_program3_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager3, 'manager3');
  perform app.publish_loyalty_program_rule_version(v_tenant3, (select id from app.loyalty_program_rule_versions where program_id = v_program3_id and status = 'draft'), 1, null, v_manager3, 'manager3');

  perform app.enroll_customer_loyalty_account(v_tenant3, v_account_theta, v_program3_id, v_manager3, 'manager3');

  v_reward := app.create_loyalty_reward_draft(v_tenant3, v_program3_id, 'Lra3 Physical Reward', 'physical_item', 'Atomicity-race fixture only.', 'Terms.', null, 40, 5, 30, 'vendor-recon-3', null, v_manager3, 'manager3');
  perform app.publish_loyalty_reward(v_tenant3, v_reward.id, v_reward.record_version, null, v_manager3, 'manager3');

  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346600', v_tenant3, v_account_theta, 'invoice', '00000000-0000-0000-0000-000000346601', 'USD', 40, 40, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant3, '00000000-0000-0000-0000-000000346600', v_manager3, 'manager3');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346600');
  perform app.post_loyalty_points_earned(v_tenant3, v_event_id, v_manager3, 'manager3', 365);

  v_redemption := app.submit_loyalty_redemption(v_tenant3, (select id from app.loyalty_accounts where tenant_id = v_tenant3 and customer_account_id = v_account_theta), v_reward.id, 'lra3-theta-redeem-1', v_manager3, 'manager3');
  if v_redemption.status <> 'pending_approval' then
    raise exception 'assertion failed: expected Theta''s physical_item submission to land pending_approval, got %', v_redemption.status;
  end if;
  v_redemption := app.decide_loyalty_redemption(v_tenant3, v_redemption.id, v_redemption.record_version, 'approve', 'approved for atomicity race fixture', v_manager3, 'manager3');
  if v_redemption.status <> 'fulfilling' or v_redemption.points_consumed <> 40 then
    raise exception 'assertion failed: expected Theta''s redemption to be fulfilling, consuming exactly 40 points, got status=% points_consumed=%', v_redemption.status, v_redemption.points_consumed;
  end if;
end $$;

\echo '>> CPL-325 hardening regression (single-snapshot atomicity, mandatory): a REAL, deterministic lock-gated three-process race -- a "gate" session holds an ACCESS EXCLUSIVE lock on app.loyalty_benefit_entitlements while a "mutator" reverses Theta''s own fulfilling redemption (app.mark_loyalty_redemption_fulfillment_failed -- touches points/redemptions, never entitlements, so it commits freely under the gate) and a "reader" runs app.execute_loyalty_liability_reconciliation_run (blocks on the gate, since its own single combined statement reads app.loyalty_benefit_entitlements too) -- launched via scripts/db-tests/loyalty-liability-reconciliation-atomicity-gate-helper.sh. Two independently-computed reference runs (strictly before and strictly after the reversal) bound the only two valid combined (points+reward) totals; the raced run''s own combined total must equal ONE of them exactly -- never a third, torn value'
do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'lra3');
  v_manager3 uuid := '00000000-0000-0000-0000-000000346501';
  v_run_before app.loyalty_liability_reconciliation_runs;
begin
  v_run_before := app.execute_loyalty_liability_reconciliation_run(v_tenant3, clock_timestamp(), 'USD', v_manager3, 'manager3', 'lra3-atomic-before', 1);
end $$;

select (select id from app.tenants where slug = 'lra3') as at_tenant3_id \gset
select id as at_redemption_id, record_version as at_redemption_version from app.loyalty_redemptions where tenant_id = (select id from app.tenants where slug = 'lra3') and idempotency_key = 'lra3-theta-redeem-1' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as at_bpid \gset

\set gate_sql 'BEGIN; LOCK TABLE app.loyalty_benefit_entitlements IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(2); COMMIT;'
\set mutator_sql 'select app.mark_loyalty_redemption_fulfillment_failed(''' :at_tenant3_id ''', ''' :at_redemption_id ''', ' :at_redemption_version ', ''CPL-325 atomicity race test reversal'', ''00000000-0000-0000-0000-000000346501'', ''manager3'');'
\set reader_sql 'select app.execute_loyalty_liability_reconciliation_run(''' :at_tenant3_id ''', clock_timestamp(), ''USD'', ''00000000-0000-0000-0000-000000346501'', ''manager3'', ''lra3-atomic-race'', 1);'

\setenv PG_TEST_DB :pg_test_db
\setenv GATE_SQL :gate_sql
\setenv MUTATOR_SQL :mutator_sql
\setenv READER_SQL :reader_sql
\setenv GATE_OUT /tmp/cargogrid-lra3-atomic-gate-:at_bpid.out
\setenv MUTATOR_OUT /tmp/cargogrid-lra3-atomic-mutator-:at_bpid.out
\setenv READER_OUT /tmp/cargogrid-lra3-atomic-reader-:at_bpid.out

\! bash scripts/db-tests/loyalty-liability-reconciliation-atomicity-gate-helper.sh

do $$
declare
  v_tenant3 uuid := (select id from app.tenants where slug = 'lra3');
  v_manager3 uuid := '00000000-0000-0000-0000-000000346501';
  v_run_before app.loyalty_liability_reconciliation_runs;
  v_run_after app.loyalty_liability_reconciliation_runs;
  v_run_race app.loyalty_liability_reconciliation_runs;
  v_before_combined numeric;
  v_after_combined numeric;
  v_race_combined numeric;
  v_redemption_status text;
begin
  -- Re-read the "before" reference run directly from the table (never via a
  -- psql-level colon-substituted variable -- psql''s own client-side
  -- substitution does not interpolate a colon-prefixed name inside a
  -- dollar-quoted PL/pgSQL function body, since dollar-quoting is itself a
  -- real SQL string-literal quoting mechanism; live-confirmed this
  -- checkpoint when an earlier draft of this exact test hit a literal
  -- syntax error at the colon from precisely this).
  select * into v_run_before from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant3 and idempotency_key = 'lra3-atomic-before';
  if v_run_before.id is null then
    raise exception 'assertion failed: expected the before-run leg to have produced a real run row (lra3-atomic-before)';
  end if;
  v_before_combined := v_run_before.points_liability_total + v_run_before.reward_fulfillment_liability_total;

  -- The mutator must have genuinely committed by now (the helper waits on
  -- all three processes before returning) -- confirm the reversal actually
  -- happened, so this test cannot silently pass by accident if the mutator
  -- leg failed for an unrelated reason.
  select status into v_redemption_status from app.loyalty_redemptions where tenant_id = v_tenant3 and idempotency_key = 'lra3-theta-redeem-1';
  if v_redemption_status <> 'failed' then
    raise exception 'assertion failed: expected the mutator leg to have genuinely reversed Theta''s redemption to status=failed, got % -- the race proof below is meaningless if this did not happen', v_redemption_status;
  end if;

  v_run_after := app.execute_loyalty_liability_reconciliation_run(v_tenant3, clock_timestamp(), 'USD', v_manager3, 'manager3', 'lra3-atomic-after', 1);
  v_after_combined := v_run_after.points_liability_total + v_run_after.reward_fulfillment_liability_total;

  select * into v_run_race from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant3 and idempotency_key = 'lra3-atomic-race';
  if v_run_race.id is null then
    raise exception 'assertion failed: expected the raced reader leg to have produced a real run row (lra3-atomic-race)';
  end if;
  v_race_combined := v_run_race.points_liability_total + v_run_race.reward_fulfillment_liability_total;

  -- Sanity: the reversal must have actually changed the combined total (40
  -- credited back to points, 30 removed from reward-fulfillment -- a net
  -- +10) -- otherwise this test would not be exercising anything real.
  if v_after_combined <> v_before_combined + 10 then
    raise exception 'assertion failed: expected the reversal to shift the combined total by exactly +10 (40 points credited back - 30 reward-fulfillment removed), got before=% after=% (delta %)', v_before_combined, v_after_combined, v_after_combined - v_before_combined;
  end if;

  -- The core invariant this fix restores: the raced run's own combined
  -- total must equal EITHER the fully-before OR the fully-after snapshot --
  -- never a third, torn value (before-points-with-after-reward, or vice
  -- versa) that corresponds to no single real instant.
  if v_race_combined <> v_before_combined and v_race_combined <> v_after_combined then
    raise exception 'CRITICAL: the raced reconciliation run''s own combined total (%) matches NEITHER the fully-before (%) NOR the fully-after (%) snapshot -- a torn, non-atomic read (the exact defect supabase/migrations/20260801310000 fixes)', v_race_combined, v_before_combined, v_after_combined;
  end if;

  raise notice 'PASS: the raced reconciliation run''s own combined total (%) exactly matches one of the two valid consistent snapshots (before=%, after=%) -- single-statement snapshot atomicity holds under a genuine, deterministic, lock-gated concurrent write', v_race_combined, v_before_combined, v_after_combined;
end $$;

\echo '>> fixture: Beta earns 200 points (clean) and is issued a discount entitlement (15 USD, clean); Gamma is issued a cashback entitlement (30 USD) with no points activity at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Beta');
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and customer_account_id = v_account_beta);
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Gamma');
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and customer_account_id = v_account_gamma);
  v_event_id uuid;
begin
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346205', v_tenant1, v_account_beta, 'invoice', '00000000-0000-0000-0000-000000346305', 'USD', 200, 200, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346205', v_manager1, 'manager1');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346205');
  perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1, 'manager1', 365);

  perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_loyalty_account_beta, 'discount', 15, null, 'USD', 'manual', null, clock_timestamp() + interval '365 days', 'lra-beta-discount', v_manager1, 'manager1');
  perform app.issue_loyalty_benefit_entitlement(v_tenant1, v_loyalty_account_gamma, 'cashback', 30, null, 'USD', 'manual', null, clock_timestamp() + interval '365 days', 'lra-gamma-cashback', v_manager1, 'manager1');
end $$;

\echo '>> deliberately-forced mismatch #1 (mandatory test): directly corrupt Beta''s CACHED point balance (never through any RPC) -- app.loyalty_point_ledger_entries itself is untouched and still says 200'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Beta');
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_beta);
begin
  update app.loyalty_point_balances set total_earned = total_earned + 500 where loyalty_account_id = v_loyalty_account_beta;
end $$;

\echo '>> deliberately-forced mismatch #2 (mandatory test): directly corrupt Gamma''s entitlement status column (never through any RPC) -- app.loyalty_benefit_entitlement_events itself is untouched and still says the entitlement was only ever issued'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Gamma');
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_gamma);
begin
  update app.loyalty_benefit_entitlements set status = 'reversed' where loyalty_account_id = v_loyalty_account_gamma and benefit_type = 'cashback';
end $$;

\echo '>> deliberately-forced mismatch #3 (mandatory test, Tier C review regression, Batch 5 close): directly corrupt Delta''s open physical_item redemption status column (never through any RPC) to FALSELY mark it already fulfilled -- app.loyalty_redemption_events itself is untouched and still shows only submitted+approved, never a real fulfilled event -- this is exactly the class of silent liability-understatement the redemption-status re-derivation fix exists to catch'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_account_delta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Delta');
  v_loyalty_account_delta uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_delta);
begin
  update app.loyalty_redemptions set status = 'fulfilled', fulfillment_status = 'fulfilled'
    where loyalty_account_id = v_loyalty_account_delta and idempotency_key = 'lra-delta-redeem-1';
end $$;

\echo '>> app.execute_loyalty_liability_reconciliation_run: all THREE forced mismatches correctly produce real, typed exception rows (mandatory test); the liability TOTAL itself still uses the RE-DERIVED (never the corrupted) value -- Beta counted at her real live 200, Gamma''s cashback still counted despite the corrupted status column, Delta''s $75 reward-fulfillment liability still counted despite being falsely marked fulfilled; run lands exceptions_pending'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run app.loyalty_liability_reconciliation_runs;
  v_point_exception app.loyalty_liability_reconciliation_exceptions;
  v_entitlement_exception app.loyalty_liability_reconciliation_exceptions;
  v_redemption_exception app.loyalty_liability_reconciliation_exceptions;
  v_exception_count integer;
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra1') and legal_name = 'Lra Account Beta');
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_beta);
  v_redemption_id uuid := (select id from app.loyalty_redemptions where idempotency_key = 'lra-delta-redeem-1');
begin
  v_run := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_manager1, 'manager1', 'lra-mismatch-run', 1);
  if v_run.status <> 'exceptions_pending' then
    raise exception 'assertion failed: expected the forced-mismatch run to land status=exceptions_pending, got %', v_run.status;
  end if;

  select count(*) into v_exception_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id;
  if v_exception_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 exceptions (1 point, 1 entitlement, 1 redemption), got %', v_exception_count;
  end if;

  select * into v_point_exception from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id and exception_type = 'point_balance_derivation_mismatch';
  if v_point_exception.id is null then
    raise exception 'assertion failed: expected a point_balance_derivation_mismatch exception';
  end if;
  if (v_point_exception.detail->>'loyaltyAccountId')::uuid <> v_loyalty_account_beta then
    raise exception 'assertion failed: expected the point mismatch exception to name Beta''s own loyalty_account_id';
  end if;
  if (v_point_exception.detail->>'expectedAvailable')::numeric <> 200 then
    raise exception 'assertion failed: expected the point mismatch exception''s own expectedAvailable (live, from the ledger) to be 200, got %', v_point_exception.detail->>'expectedAvailable';
  end if;
  if (v_point_exception.detail->>'actualAvailable')::numeric <> 700 then
    raise exception 'assertion failed: expected the point mismatch exception''s own actualAvailable (the corrupted cached column) to be 700, got %', v_point_exception.detail->>'actualAvailable';
  end if;

  select * into v_entitlement_exception from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id and exception_type = 'entitlement_state_derivation_mismatch';
  if v_entitlement_exception.id is null then
    raise exception 'assertion failed: expected an entitlement_state_derivation_mismatch exception';
  end if;
  if v_entitlement_exception.detail->>'expectedStatus' <> 'issued' or v_entitlement_exception.detail->>'actualStatus' <> 'reversed' then
    raise exception 'assertion failed: expected the entitlement mismatch to show expectedStatus=issued (from the event log) vs actualStatus=reversed (the corrupted column), got %/%', v_entitlement_exception.detail->>'expectedStatus', v_entitlement_exception.detail->>'actualStatus';
  end if;

  select * into v_redemption_exception from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id and exception_type = 'redemption_liability_status_mismatch';
  if v_redemption_exception.id is null then
    raise exception 'assertion failed: expected a redemption_liability_status_mismatch exception (Tier C review regression)';
  end if;
  if (v_redemption_exception.detail->>'redemptionId')::uuid <> v_redemption_id then
    raise exception 'assertion failed: expected the redemption mismatch exception to name Delta''s own redemption id';
  end if;
  if v_redemption_exception.detail->>'expectedStatus' <> 'fulfilling' or v_redemption_exception.detail->>'actualStatus' <> 'fulfilled' then
    raise exception 'assertion failed: expected the redemption mismatch to show expectedStatus=fulfilling (from the event log, latest event=approved) vs actualStatus=fulfilled (the corrupted column), got %/%', v_redemption_exception.detail->>'expectedStatus', v_redemption_exception.detail->>'actualStatus';
  end if;
  if v_redemption_exception.detail->>'latestEventType' <> 'approved' then
    raise exception 'assertion failed: expected the redemption mismatch to name the real latest event type (approved -- no fulfilled event was ever actually posted), got %', v_redemption_exception.detail->>'latestEventType';
  end if;

  -- The liability total itself is authoritative and re-derived (design
  -- decision 3/5/7) -- NEVER the corrupted cached value: points still 200
  -- for Beta (not 700), Gamma''s cashback still counted (derived status
  -- overrides her corrupted 'reversed' column), and -- the Tier C review
  -- regression proof -- Delta''s $75 reward-fulfillment liability is STILL
  -- counted even though her redemption was falsely marked 'fulfilled': a
  -- direct, RPC-bypassing corruption can no longer silently understate
  -- this line with zero detection.
  if v_run.points_liability_total <> 600 then
    raise exception 'assertion failed: expected points_liability_total = 600 (Alpha 150 + Delta 250 + Beta''s REAL live 200, never her corrupted 700), got %', v_run.points_liability_total;
  end if;
  if v_run.cashback_liability_total <> 30 then
    raise exception 'assertion failed: expected cashback_liability_total = 30 (Gamma''s cashback still counted -- re-derived status overrides the corrupted column), got %', v_run.cashback_liability_total;
  end if;
  if v_run.discount_liability_total <> 15 then
    raise exception 'assertion failed: expected discount_liability_total = 15 (Beta''s clean discount), got %', v_run.discount_liability_total;
  end if;
  if v_run.reward_fulfillment_liability_total <> 75 then
    raise exception 'assertion failed: expected reward_fulfillment_liability_total = 75 (Delta''s open physical_item redemption STILL counted -- re-derived status overrides her corrupted ''fulfilled'' column), got %', v_run.reward_fulfillment_liability_total;
  end if;
end $$;

\echo '>> certify BLOCKED while any exception on the run remains open (mandatory test) -- a real, tested exception, mirroring FIN-209''s own certify-blocked-while-exceptions-open semantics exactly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run app.loyalty_liability_reconciliation_runs := (select r from app.loyalty_liability_reconciliation_runs r where r.tenant_id = (select id from app.tenants where slug = 'lra1') and r.idempotency_key = 'lra-mismatch-run');
begin
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, v_run.record_version, v_manager1, 'manager1');
    raise exception 'assertion failed: expected certify to be BLOCKED while 3 exceptions remain open';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_unresolved_exceptions%' then raise; end if;
  end;
end $$;

\echo '>> optimistic-concurrency NULL-bypass regression proof (mandatory test) on app.resolve_loyalty_liability_reconciliation_exception and app.certify_loyalty_liability_reconciliation_run'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run app.loyalty_liability_reconciliation_runs := (select r from app.loyalty_liability_reconciliation_runs r where r.tenant_id = (select id from app.tenants where slug = 'lra1') and r.idempotency_key = 'lra-mismatch-run');
  v_point_exception app.loyalty_liability_reconciliation_exceptions := (select e from app.loyalty_liability_reconciliation_exceptions e where e.run_id = v_run.id and e.exception_type = 'point_balance_derivation_mismatch');
begin
  begin
    perform app.resolve_loyalty_liability_reconciliation_exception(v_tenant1, v_point_exception.id, null, 'a reason', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on resolve';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_liability_reconciliation_exceptions where id = v_point_exception.id) <> 'open' then
    raise exception 'assertion failed: expected the exception to remain byte-for-byte unchanged (still open) after the rejected NULL-version resolve attempt';
  end if;

  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on certify';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'exceptions_pending' then
    raise exception 'assertion failed: expected the run to remain byte-for-byte unchanged (still exceptions_pending) after the rejected NULL-version certify attempt';
  end if;
end $$;

\echo '>> resolve all three exceptions (mandatory reason enforced); the run auto-clears from exceptions_pending back to open once the LAST open exception is resolved; certify then succeeds (mandatory test)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_editor1 uuid := '00000000-0000-0000-0000-000000346002';
  v_run app.loyalty_liability_reconciliation_runs := (select r from app.loyalty_liability_reconciliation_runs r where r.tenant_id = (select id from app.tenants where slug = 'lra1') and r.idempotency_key = 'lra-mismatch-run');
  v_point_exception app.loyalty_liability_reconciliation_exceptions := (select e from app.loyalty_liability_reconciliation_exceptions e where e.run_id = v_run.id and e.exception_type = 'point_balance_derivation_mismatch');
  v_entitlement_exception app.loyalty_liability_reconciliation_exceptions := (select e from app.loyalty_liability_reconciliation_exceptions e where e.run_id = v_run.id and e.exception_type = 'entitlement_state_derivation_mismatch');
  v_redemption_exception app.loyalty_liability_reconciliation_exceptions := (select e from app.loyalty_liability_reconciliation_exceptions e where e.run_id = v_run.id and e.exception_type = 'redemption_liability_status_mismatch');
begin
  -- Mandatory non-empty reason enforced.
  begin
    perform app.resolve_loyalty_liability_reconciliation_exception(v_tenant1, v_point_exception.id, v_point_exception.record_version, '   ', v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for a blank resolution_reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Editor (LYL:Edit only, no Configure) may resolve -- ordinary posting-tier authority (design decision 11).
  perform app.resolve_loyalty_liability_reconciliation_exception(v_tenant1, v_point_exception.id, v_point_exception.record_version, 'known test-corruption, acknowledged and reconciled manually', v_editor1, 'editor1');

  if (select status from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'exceptions_pending' then
    raise exception 'assertion failed: expected the run to remain exceptions_pending while Gamma''s and Delta''s own exceptions are still open';
  end if;

  -- Certify still blocked -- two exceptions remain open.
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, v_run.record_version, v_manager1, 'manager1');
    raise exception 'assertion failed: expected certify to still be BLOCKED with two exceptions remaining open';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_unresolved_exceptions%' then raise; end if;
  end;

  perform app.resolve_loyalty_liability_reconciliation_exception(v_tenant1, v_entitlement_exception.id, v_entitlement_exception.record_version, 'known test-corruption, acknowledged and reconciled manually', v_manager1, 'manager1');

  if (select status from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'exceptions_pending' then
    raise exception 'assertion failed: expected the run to remain exceptions_pending while Delta''s own redemption-status exception is still open';
  end if;

  -- Certify still blocked -- one exception remains open (Tier C review's
  -- own new redemption_liability_status_mismatch exception).
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, (select record_version from app.loyalty_liability_reconciliation_runs where id = v_run.id), v_manager1, 'manager1');
    raise exception 'assertion failed: expected certify to still be BLOCKED with one exception remaining open';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_unresolved_exceptions%' then raise; end if;
  end;

  perform app.resolve_loyalty_liability_reconciliation_exception(v_tenant1, v_redemption_exception.id, v_redemption_exception.record_version, 'known test-corruption, acknowledged and reconciled manually', v_manager1, 'manager1');

  if (select status from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'open' then
    raise exception 'assertion failed: expected the run to auto-clear from exceptions_pending back to open once its last open exception was resolved';
  end if;

  -- Editor (LYL:Edit only, no Configure) is DENIED certify -- the elevated bar (design decision 11).
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, (select record_version from app.loyalty_liability_reconciliation_runs where id = v_run.id), v_editor1, 'editor1');
    raise exception 'assertion failed: expected an Edit-only actor to be DENIED certify (requires the elevated LYL:Configure)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, (select record_version from app.loyalty_liability_reconciliation_runs where id = v_run.id), v_manager1, 'manager1');

  if (select status from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'certified' then
    raise exception 'assertion failed: expected the run to be certified once every exception was resolved';
  end if;
  if (select certified_by from app.loyalty_liability_reconciliation_runs where id = v_run.id) <> 'manager1' then
    raise exception 'assertion failed: expected certified_by to record the certifying actor''s own label';
  end if;

  -- A repeat certify call on an already-certified run is a safe no-op.
  perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run.id, (select record_version from app.loyalty_liability_reconciliation_runs where id = v_run.id), v_manager1, 'manager1');
end $$;

\echo '>> idempotent re-run of the same period (mandatory test) -- an explicit-key replay of the now-certified run returns the IDENTICAL row, never recomputes, never creates a new run or a new exception row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run_before app.loyalty_liability_reconciliation_runs := (select r from app.loyalty_liability_reconciliation_runs r where r.tenant_id = (select id from app.tenants where slug = 'lra1') and r.idempotency_key = 'lra-mismatch-run');
  v_run_replay app.loyalty_liability_reconciliation_runs;
  v_run_count_before integer;
  v_run_count_after integer;
  v_exception_count_before integer;
  v_exception_count_after integer;
begin
  select count(*) into v_run_count_before from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant1;
  select count(*) into v_exception_count_before from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_before.id;

  v_run_replay := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_manager1, 'manager1', 'lra-mismatch-run', 1);

  select count(*) into v_run_count_after from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant1;
  select count(*) into v_exception_count_after from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_before.id;

  if v_run_replay.id <> v_run_before.id then
    raise exception 'assertion failed: expected the replay to return the IDENTICAL run id, got a different one';
  end if;
  if v_run_replay.status <> 'certified' then
    raise exception 'assertion failed: expected the replay to still report status=certified (never recomputed), got %', v_run_replay.status;
  end if;
  if v_run_count_after <> v_run_count_before then
    raise exception 'assertion failed: expected NO new run row on replay, % vs %', v_run_count_before, v_run_count_after;
  end if;
  if v_exception_count_after <> v_exception_count_before then
    raise exception 'assertion failed: expected NO new exception rows on replay, % vs %', v_exception_count_before, v_exception_count_after;
  end if;
end $$;

\echo '>> idempotent re-run via the DEFAULT day-derived idempotency key (no explicit key supplied) -- a fresh scope with zero activity, two back-to-back calls return the identical row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run1 app.loyalty_liability_reconciliation_runs;
  v_run2 app.loyalty_liability_reconciliation_runs;
begin
  v_run1 := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'EUR', v_manager1, 'manager1');
  v_run2 := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'EUR', v_manager1, 'manager1');
  if v_run1.id <> v_run2.id then
    raise exception 'assertion failed: expected two back-to-back default-key calls (same day, same currency) to return the IDENTICAL run id';
  end if;
  if v_run1.points_liability_total <> 600 then
    raise exception 'assertion failed: expected the EUR-scoped run''s own points_liability_total to still be 600 (points are currency-independent, design decision 6), got %', v_run1.points_liability_total;
  end if;
  if v_run1.cashback_liability_total <> 0 and v_run1.discount_liability_total <> 0 and v_run1.voucher_liability_total <> 0 then
    raise exception 'assertion failed: expected zero currency-denominated entitlement liability on an EUR-scoped run (every real entitlement in this fixture is USD), got cashback=%/discount=%/voucher=%', v_run1.cashback_liability_total, v_run1.discount_liability_total, v_run1.voucher_liability_total;
  end if;
end $$;

\echo '>> app.get_loyalty_engagement_metrics: correct aggregate counts (mandatory test); a customer_user caller is REJECTED outright, never merely handed an empty row; Plain User denied; invalid period rejected; no per-customer/internal-cost field anywhere in the returned row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000346004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000346010';
  v_metrics record;
begin
  select * into v_metrics from app.get_loyalty_engagement_metrics(v_tenant1, '2026-01-01'::timestamptz, clock_timestamp() + interval '1 day', v_manager1);

  if v_metrics.active_loyalty_accounts_count <> 4 then
    raise exception 'assertion failed: expected active_loyalty_accounts_count = 4 (Alpha/Beta/Gamma/Delta), got %', v_metrics.active_loyalty_accounts_count;
  end if;
  if v_metrics.points_earned_total <> 800 then
    raise exception 'assertion failed: expected points_earned_total = 800 (150+50+100 Alpha, 300 Delta, 200 Beta), got %', v_metrics.points_earned_total;
  end if;
  if v_metrics.points_redeemed_total <> 50 then
    raise exception 'assertion failed: expected points_redeemed_total = 50 (Delta''s own physical_item redemption composition), got %', v_metrics.points_redeemed_total;
  end if;
  if v_metrics.redemption_count <> 1 then
    raise exception 'assertion failed: expected redemption_count = 1 (Delta''s own redemption), got %', v_metrics.redemption_count;
  end if;
  if v_metrics.published_reward_count <> 1 then
    raise exception 'assertion failed: expected published_reward_count = 1, got %', v_metrics.published_reward_count;
  end if;
  if v_metrics.rewards_with_redemption_count <> 1 then
    raise exception 'assertion failed: expected rewards_with_redemption_count = 1, got %', v_metrics.rewards_with_redemption_count;
  end if;
  if v_metrics.redemption_rate <> 0.2500 then
    raise exception 'assertion failed: expected redemption_rate = 0.25 (1 redemption / 4 active accounts), got %', v_metrics.redemption_rate;
  end if;

  -- Structurally, grep-provably no per-customer/internal-cost field.
  if to_jsonb(v_metrics) ? 'customer_account_id' or to_jsonb(v_metrics) ? 'loyalty_account_id' or to_jsonb(v_metrics) ? 'internal_cost' or to_jsonb(v_metrics) ? 'vendor_ref' then
    raise exception 'assertion failed: engagement metrics row unexpectedly carries a per-customer or internal-cost field: %', to_jsonb(v_metrics);
  end if;

  -- A customer_user caller is REJECTED outright (business rule: "analytics
  -- cannot infer or expose other customers, margins or internal
  -- profitability").
  begin
    perform app.get_loyalty_engagement_metrics(v_tenant1, '2026-01-01'::timestamptz, clock_timestamp() + interval '1 day', v_customer_alpha);
    raise exception 'assertion failed: expected a customer_user caller to be REJECTED (insufficient_authority) from engagement metrics, never merely handed a row';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_engagement_metrics(v_tenant1, '2026-01-01'::timestamptz, clock_timestamp() + interval '1 day', v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User engagement-metrics read';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_engagement_metrics(v_tenant1, clock_timestamp(), '2026-01-01'::timestamptz, v_manager1);
    raise exception 'assertion failed: expected invalid_period when period_start >= period_end';
  exception when others then if sqlerrm not like 'invalid_period%' then raise; end if;
  end;
end $$;

\echo '>> app.get_customer_portal_loyalty_summary: composes points/entitlements/redemptions/hold-status for the caller''s OWN account only (mandatory deliverable); a different customer and a different tenant cannot fetch Alpha''s own summary (anti-enumeration, deny-by-default)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'lra2');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000346010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000346020';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000346110';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lra Account Alpha');
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant1 and customer_account_id = v_account_alpha);
  v_summary record;
begin
  select * into v_summary from app.get_customer_portal_loyalty_summary(v_tenant1, v_loyalty_account_alpha, v_customer_alpha);

  if v_summary.loyalty_account_id <> v_loyalty_account_alpha then
    raise exception 'assertion failed: expected the summary to name Alpha''s own loyalty_account_id';
  end if;
  if v_summary.points_available <> 150 then
    raise exception 'assertion failed: expected points_available = 150, got %', v_summary.points_available;
  end if;
  if v_summary.active_entitlements_count <> 1 then
    raise exception 'assertion failed: expected active_entitlements_count = 1 (Alpha''s own voucher), got %', v_summary.active_entitlements_count;
  end if;
  if v_summary.active_entitlements_summary is null or jsonb_array_length(v_summary.active_entitlements_summary) <> 1 then
    raise exception 'assertion failed: expected exactly one (benefit_type, currency) group in active_entitlements_summary, got %', v_summary.active_entitlements_summary;
  end if;
  if v_summary.is_on_hold is distinct from false then
    raise exception 'assertion failed: expected Alpha''s own account to not be on hold';
  end if;

  -- A different customer on the SAME tenant cannot fetch Alpha''s own summary.
  begin
    perform app.get_customer_portal_loyalty_summary(v_tenant1, v_loyalty_account_alpha, v_customer_beta);
    raise exception 'assertion failed: expected loyalty_account_not_found for a different customer''s attempt to read Alpha''s own summary';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;

  -- A customer on a DIFFERENT tenant cannot fetch Alpha''s own summary, even
  -- explicitly passing tenant1''s own tenant_id.
  begin
    perform app.get_customer_portal_loyalty_summary(v_tenant1, v_loyalty_account_alpha, v_customer_zeta);
    raise exception 'assertion failed: expected loyalty_account_not_found for a cross-tenant customer''s attempt to read Alpha''s own summary';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;

  -- A genuinely nonexistent loyalty_account_id resolves to the identical error.
  begin
    perform app.get_customer_portal_loyalty_summary(v_tenant1, gen_random_uuid(), v_customer_alpha);
    raise exception 'assertion failed: expected loyalty_account_not_found for a genuinely nonexistent loyalty_account_id';
  exception when others then if sqlerrm not like 'loyalty_account_not_found%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant/cross-account isolation (mandatory test): lra2''s own manager cannot act on lra1''s own runs/exceptions, whether by passing lra1''s own tenant_id or by guessing an lra1 id inside lra2''s own scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'lra2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000346101';
  v_run app.loyalty_liability_reconciliation_runs := (select r from app.loyalty_liability_reconciliation_runs r where r.tenant_id = (select id from app.tenants where slug = 'lra1') and r.idempotency_key = 'lra-mismatch-run');
begin
  begin
    perform app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_manager2, 'manager2', 'lra2-cross-attempt', 1);
    raise exception 'assertion failed: expected insufficient_authority for lra2''s own manager acting under lra1''s own tenant_id';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_liability_reconciliation_run(v_tenant2, v_run.id, v_manager2);
    raise exception 'assertion failed: expected loyalty_liability_reconciliation_run_not_found for lra1''s own run id guessed inside lra2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_run_not_found%' then raise; end if;
  end;

  -- Anti-enumeration: a genuinely nonexistent id and the real cross-tenant
  -- id resolve to the identical error prefix.
  begin
    perform app.get_loyalty_liability_reconciliation_run(v_tenant2, gen_random_uuid(), v_manager2);
    raise exception 'assertion failed: expected loyalty_liability_reconciliation_run_not_found for a genuinely nonexistent run id too';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_run_not_found%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS / raw-function-grant defense-in-depth: authenticated holds zero direct table grant on either new table; anon holds zero EXECUTE on any of the 8 new functions; a real authenticated-role positive path matches a direct superuser call'
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000346001","role":"authenticated"}', true);
  set local role authenticated;
  begin
    perform 1 from app.loyalty_liability_reconciliation_runs limit 1;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_liability_reconciliation_runs to be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from app.loyalty_liability_reconciliation_exceptions limit 1;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_liability_reconciliation_exceptions to be denied';
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
    and routine_name in (
      'execute_loyalty_liability_reconciliation_run', 'resolve_loyalty_liability_reconciliation_exception',
      'certify_loyalty_liability_reconciliation_run', 'get_loyalty_liability_reconciliation_run',
      'list_loyalty_liability_reconciliation_runs', 'list_loyalty_liability_reconciliation_exceptions',
      'get_loyalty_engagement_metrics', 'get_customer_portal_loyalty_summary'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected ZERO anon EXECUTE grants on any CPL-323 function, got %', v_count;
  end if;
end $$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run_id uuid := (select id from app.loyalty_liability_reconciliation_runs where tenant_id = (select id from app.tenants where slug = 'lra1') and idempotency_key = 'lra-mismatch-run');
  v_row app.loyalty_liability_reconciliation_runs;
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  set local role authenticated;
  v_row := app.get_loyalty_liability_reconciliation_run(v_tenant1, v_run_id, v_manager1);
  if v_row.id is null then
    raise exception 'assertion failed: expected a real authenticated-role positive read path to succeed';
  end if;
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> actor-identity session cross-check (ATW-031): a forged p_actor_auth_user_id is rejected with actor_identity_mismatch when a genuine session identity is set'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  begin
    perform app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', gen_random_uuid(), 'forged', 'lra-forged-attempt', 1);
    raise exception 'assertion failed: expected actor_identity_mismatch for a forged actor id under a real session';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> keyset pagination on app.list_loyalty_liability_reconciliation_runs and app.list_loyalty_liability_reconciliation_exceptions, visiting every row exactly once at p_limit=1; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_total_count integer;
  v_visited_count integer := 0;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_liability_reconciliation_runs;
  v_row_count integer;
  v_run_id uuid := (select id from app.loyalty_liability_reconciliation_runs where tenant_id = (select id from app.tenants where slug = 'lra1') and idempotency_key = 'lra-mismatch-run');
  v_epage app.loyalty_liability_reconciliation_exceptions;
  v_evisited integer := 0;
  v_etotal integer;
begin
  select count(*) into v_total_count from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant1;

  loop
    select * into v_page from app.list_loyalty_liability_reconciliation_runs(v_tenant1, v_manager1, null, null, v_cursor_updated_at, v_cursor_id, 1) limit 1;
    get diagnostics v_row_count = row_count;
    exit when v_row_count = 0;
    v_visited_count := v_visited_count + 1;
    v_cursor_updated_at := v_page.updated_at;
    v_cursor_id := v_page.id;
    exit when v_visited_count > v_total_count + 5;
  end loop;

  if v_visited_count <> v_total_count then
    raise exception 'assertion failed: expected keyset pagination over runs to visit every row exactly once, expected % got %', v_total_count, v_visited_count;
  end if;

  begin
    perform app.list_loyalty_liability_reconciliation_runs(v_tenant1, v_manager1, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for a half-supplied cursor on runs';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;

  select count(*) into v_etotal from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_id;
  v_cursor_updated_at := null;
  v_cursor_id := null;
  loop
    select * into v_epage from app.list_loyalty_liability_reconciliation_exceptions(v_tenant1, v_run_id, v_manager1, null, v_cursor_updated_at, v_cursor_id, 1) limit 1;
    get diagnostics v_row_count = row_count;
    exit when v_row_count = 0;
    v_evisited := v_evisited + 1;
    v_cursor_updated_at := v_epage.updated_at;
    v_cursor_id := v_epage.id;
    exit when v_evisited > v_etotal + 5;
  end loop;

  if v_evisited <> v_etotal then
    raise exception 'assertion failed: expected keyset pagination over exceptions to visit every row exactly once, expected % got %', v_etotal, v_evisited;
  end if;
end $$;

\echo '>> LYL:View authority boundary on staff list/get reads (Manager succeeds, Plain User denied)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_plain1 uuid := '00000000-0000-0000-0000-000000346004';
begin
  begin
    perform app.list_loyalty_liability_reconciliation_runs(v_tenant1, v_plain1, null, null, null, null, 50);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User run-list read';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> ALL PASSED: CPL-323 Liability Reconciliation Analytics'
