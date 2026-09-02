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

-- ISS-2026-319 fixture helpers (docs/runtime/KNOWN_ISSUES.md). The new
-- app.validate_finance_open_item_source guard (20260901060000) now rejects a
-- fabricated source_document_id on a direct app.finance_ar_open_items insert,
-- so this file's own direct inserts below (source_document_type = 'invoice')
-- can no longer name a synthetic id that resolves to no real app.finance_invoices
-- row. These pg_temp functions mint a genuinely real, minimal app.finance_invoices
-- row via direct INSERT rather than the full Commercial->Operations RPC pipeline,
-- extended one layer deeper than this file's own established "directly
-- fixture-backdate, never through the RPC" precedent because the new guard now
-- checks one layer deeper. pg_temp is session-scoped, matching
-- scripts/db-tests/run.sh's one-psql-connection-per-file execution model.

create function pg_temp.iss319_build_job_order(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
returns uuid
language plpgsql
as $fn$
declare
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_opp_version integer;
  v_quotation_id uuid := gen_random_uuid();
  v_joh_id uuid;
  v_job_order_id uuid;
begin
  insert into app.leads (tenant_id, source, contact_name, email, created_by)
  values (p_tenant_id, 'manual', p_seed, p_seed || '@iss319-fixture.test', p_actor_label)
  returning id into v_lead_id;

  insert into app.prospects (tenant_id, lead_id, legal_name, contact_name, created_by)
  values (p_tenant_id, v_lead_id, p_seed || ' Co', p_seed, p_actor_label)
  returning id into v_prospect_id;

  insert into app.opportunities (tenant_id, prospect_id, name, created_by)
  values (p_tenant_id, v_prospect_id, p_seed || ' opportunity', p_actor_label)
  returning id, record_version into v_opportunity_id, v_opp_version;

  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, root_quotation_id, created_by)
  values (v_quotation_id, p_tenant_id, p_seed || '-QUOTE', v_opportunity_id, v_opp_version, v_prospect_id, 'USD', now() + interval '30 days', v_quotation_id, p_actor_label);

  insert into app.job_order_handoffs (tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, created_by)
  values (p_tenant_id, v_quotation_id, p_account_id, '{}'::jsonb, 'iss319-fixture-hash', p_actor_auth_user_id, p_actor_label)
  returning id into v_joh_id;

  insert into app.job_orders (tenant_id, job_number, source_handoff_id, quotation_id, account_id, customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot, created_by)
  values (p_tenant_id, p_seed || '-JOB', v_joh_id, v_quotation_id, p_account_id, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, p_actor_label)
  returning id into v_job_order_id;

  return v_job_order_id;
end;
$fn$;

-- Mints one real, minimal (draft, never issued -- so it never posts its own AR
-- open item) app.finance_invoices row and returns its id, so a direct
-- app.finance_ar_open_items insert below resolves against a genuinely
-- existing invoice instead of a fabricated one.
create function pg_temp.iss319_mint_invoice(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
returns uuid
language plpgsql
as $fn$
declare
  v_job_order_id uuid;
  v_eval_id uuid;
  v_handoff_id uuid;
  v_invoice_id uuid;
begin
  v_job_order_id := pg_temp.iss319_build_job_order(p_tenant_id, p_account_id, p_actor_auth_user_id, p_actor_label, p_seed);

  insert into app.billing_readiness_evaluations (tenant_id, job_order_id, evaluated_status, is_overridden, override_reason, overridden_by_auth_user_id, overridden_by, evaluated_by_auth_user_id, evaluated_by, created_by)
  values (p_tenant_id, v_job_order_id, 'not_ready', true, 'ISS-2026-319 fixture: minted so the new source-lineage guard has a real invoice to resolve', p_actor_auth_user_id, p_actor_label, p_actor_auth_user_id, p_actor_label, p_actor_label)
  returning id into v_eval_id;

  insert into app.billing_readiness_handoffs (tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (p_tenant_id, v_job_order_id, v_eval_id, p_seed || '-handoff', p_actor_auth_user_id, p_actor_label)
  returning id into v_handoff_id;

  insert into app.finance_invoices (tenant_id, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, created_by)
  values (p_tenant_id, p_account_id, v_job_order_id, v_handoff_id, 'USD', p_actor_label)
  returning id into v_invoice_id;

  return v_invoice_id;
end;
$fn$;

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
  values ('00000000-0000-0000-0000-000000346201', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-lra-alpha-1'), 'USD', 150, 150, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346201', v_manager1, 'manager1');
  v_event1_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346201');
  perform app.post_loyalty_points_earned(v_tenant1, v_event1_id, v_manager1, 'manager1', 365);

  -- Invoice 2: 50 points, fully reversed (real reversal chain, CPL-316 then CPL-318).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346202', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-lra-alpha-2'), 'USD', 50, 50, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000346202', v_manager1, 'manager1');
  v_event2_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346202');
  perform app.post_loyalty_points_earned(v_tenant1, v_event2_id, v_manager1, 'manager1', 365);
  v_reversal_event := app.reverse_loyalty_earning_event(v_tenant1, v_event2_id, 'invoice 2 disputed by customer', 'lra-alpha-invoice2-reversal', v_manager1, 'manager1');
  perform app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_manager1, 'manager1');

  -- Invoice 3: 100 points, expired via a REAL app.run_loyalty_expiry_sweep call (CPL-322).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346203', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-lra-alpha-3'), 'USD', 100, 100, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
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
  values ('00000000-0000-0000-0000-000000346204', v_tenant1, v_account_delta, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_delta, v_manager1, 'manager1', 'iss319-lra-delta'), 'USD', 300, 300, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
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
  values ('00000000-0000-0000-0000-000000346600', v_tenant3, v_account_theta, 'invoice', pg_temp.iss319_mint_invoice(v_tenant3, v_account_theta, v_manager3, 'manager3', 'iss319-lra-theta'), 'USD', 40, 40, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
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
  values ('00000000-0000-0000-0000-000000346205', v_tenant1, v_account_beta, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_beta, v_manager1, 'manager1', 'iss319-lra-beta'), 'USD', 200, 200, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
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

\echo '>> ISS-2026-136 item 2 regression (mandatory): mismatch DETECTION is now scoped identically to each domain''s own liability computation -- Gamma''s (USD) entitlement corruption and Delta''s (tenant-default-currency) redemption corruption from the block above are still sitting there, untouched. A FRESH off-currency (IDR) run must raise NEITHER, while Beta''s tenant-wide point corruption must STILL be caught (the load-bearing anti-regression proof that points were NOT accidentally currency-scoped); a fresh SAME-instant in-scope (USD) run must still raise all three, exactly as before this fix'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_run_idr app.loyalty_liability_reconciliation_runs;
  v_run_usd app.loyalty_liability_reconciliation_runs;
  v_entitlement_count integer;
  v_redemption_count integer;
  v_point_count integer;
  v_total_count integer;
  v_point_exception app.loyalty_liability_reconciliation_exceptions;
begin
  -- ---------------------------------------------------------------------
  -- Off-currency (IDR) run: Gamma's own entitlement currency is USD and
  -- Delta's redemption is only ever in scope for lra1's own resolved
  -- default currency (USD) -- neither is IDR, so neither mismatch may fire.
  -- ---------------------------------------------------------------------
  v_run_idr := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'IDR', v_manager1, 'manager1', 'lra-currency-scope-detection-idr', 1);

  select count(*) into v_entitlement_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_idr.id and exception_type = 'entitlement_state_derivation_mismatch';
  if v_entitlement_count <> 0 then
    raise exception 'ISS-2026-136 item 2 regression: expected ZERO entitlement_state_derivation_mismatch exceptions on an IDR-scoped run (Gamma''s corrupted entitlement is USD, out of scope for this run), got %', v_entitlement_count;
  end if;

  select count(*) into v_redemption_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_idr.id and exception_type = 'redemption_liability_status_mismatch';
  if v_redemption_count <> 0 then
    raise exception 'ISS-2026-136 item 2 regression: expected ZERO redemption_liability_status_mismatch exceptions on an IDR-scoped run (redemptions only ever land on the tenant-default-currency run, USD here), got %', v_redemption_count;
  end if;

  -- The load-bearing anti-regression assertion: a tenant-wide points defect
  -- must still be caught on EVERY currency-scoped run, proving points were
  -- NOT accidentally currency-scoped by this fix.
  select count(*) into v_point_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_idr.id and exception_type = 'point_balance_derivation_mismatch';
  if v_point_count <> 1 then
    raise exception 'ISS-2026-136 item 2 regression: expected EXACTLY ONE point_balance_derivation_mismatch exception on the IDR-scoped run (Beta''s corruption is tenant-wide and must be caught on every run regardless of currency -- this is the proof points were NOT accidentally currency-scoped), got %', v_point_count;
  end if;

  select * into v_point_exception from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_idr.id and exception_type = 'point_balance_derivation_mismatch';
  if v_point_exception.detail->>'loyaltyAccountId' is null then
    raise exception 'assertion failed: expected the IDR run''s own point exception to carry a real loyaltyAccountId in its detail';
  end if;

  if v_run_idr.status <> 'exceptions_pending' then
    raise exception 'ISS-2026-136 item 2 regression: expected the IDR-scoped run to still land exceptions_pending (Beta''s tenant-wide point defect alone must still block it), got %', v_run_idr.status;
  end if;

  -- Certify must still be BLOCKED by the one exception that is genuinely in
  -- scope for this run (the points mismatch) -- detection SCOPE changed,
  -- the certify gate itself (zero open exceptions) did not.
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant1, v_run_idr.id, v_run_idr.record_version, v_manager1, 'manager1');
    raise exception 'ISS-2026-136 item 2 regression: expected certify to remain BLOCKED on the IDR-scoped run by the still-open, genuinely-in-scope point mismatch';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_unresolved_exceptions%' then raise; end if;
  end;

  -- ---------------------------------------------------------------------
  -- Same-instant in-scope (USD) run: proves the fix did not also suppress
  -- detection for the currency it SHOULD fire on -- all three mismatches
  -- (point, entitlement, redemption) still raise, exactly as the original
  -- "all THREE forced mismatches" assertion above already proved before
  -- this fix existed.
  -- ---------------------------------------------------------------------
  v_run_usd := app.execute_loyalty_liability_reconciliation_run(v_tenant1, clock_timestamp(), 'USD', v_manager1, 'manager1', 'lra-currency-scope-detection-usd', 1);

  select count(*) into v_total_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id;
  if v_total_count <> 3 then
    raise exception 'ISS-2026-136 item 2 regression: expected exactly 3 exceptions on the fresh in-scope USD run (1 point, 1 entitlement, 1 redemption -- unchanged from before this fix), got %', v_total_count;
  end if;

  select count(*) into v_entitlement_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id and exception_type = 'entitlement_state_derivation_mismatch';
  if v_entitlement_count <> 1 then
    raise exception 'ISS-2026-136 item 2 regression: expected the USD run to still raise Gamma''s entitlement_state_derivation_mismatch (in scope -- her entitlement IS USD), got %', v_entitlement_count;
  end if;
  if (select detail->>'currency' from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id and exception_type = 'entitlement_state_derivation_mismatch') <> 'USD' then
    raise exception 'assertion failed: expected the entitlement mismatch exception''s own detail to name its scoping currency (USD, the entitlement''s own currency)';
  end if;

  select count(*) into v_redemption_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id and exception_type = 'redemption_liability_status_mismatch';
  if v_redemption_count <> 1 then
    raise exception 'ISS-2026-136 item 2 regression: expected the USD run to still raise Delta''s redemption_liability_status_mismatch (in scope -- USD is lra1''s own resolved default currency), got %', v_redemption_count;
  end if;
  if (select detail->>'currency' from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id and exception_type = 'redemption_liability_status_mismatch') <> 'USD' then
    raise exception 'assertion failed: expected the redemption mismatch exception''s own detail to name its scoping currency (USD, the run''s own currency / the tenant''s resolved default currency)';
  end if;

  select count(*) into v_point_count from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_usd.id and exception_type = 'point_balance_derivation_mismatch';
  if v_point_count <> 1 then
    raise exception 'ISS-2026-136 item 2 regression: expected the USD run to still raise exactly one point_balance_derivation_mismatch (unaffected by this fix), got %', v_point_count;
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

\echo '>> ISS-2026-134 item 3 regression (mandatory): a physical_item reward published with internal_cost=NULL, redeemed and approved into fulfilling -- the run must still report reward_fulfillment_liability_total=0 for it (unchanged) but now ALSO raise a real, typed reward_internal_cost_missing exception naming the redemption/reward, block certify until resolved, and certify cleanly once resolved. Own, fully isolated tenant (lra4), mirroring lra3''s own established isolation rationale -- this fixture''s own account/redemption activity must never ripple into lra1''s own tenant-wide absolute-count assertions elsewhere in this file'
do $$
declare
  v_tenant4 uuid;
  v_company4 uuid;
  v_manager4 uuid := '00000000-0000-0000-0000-000000346701';
  v_customer_iota uuid := '00000000-0000-0000-0000-000000346710';
  v_manager_role4 uuid;
  v_manager_draft4 app.role_versions;
  v_locale_draft4 app.tenant_locale_versions;
  v_program4_id uuid;
  v_account_iota uuid;
  v_reward app.loyalty_rewards;
  v_event_id uuid;
  v_redemption app.loyalty_redemptions;
  v_run app.loyalty_liability_reconciliation_runs;
  v_exception app.loyalty_liability_reconciliation_exceptions;
begin
  insert into auth.users (id, email) values
    (v_manager4, 'manager4@lra4.test'),
    (v_customer_iota, 'customer-iota@lra4.test');

  perform app.provision_tenant('lra4', 'Liability Recon Test Tenant Four (null internal_cost, isolated)', 'idem-lra4', 'tester');
  v_tenant4 := (select id from app.tenants where slug = 'lra4');
  perform app.transition_tenant_status(v_tenant4, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant4, 'company', null, 'LRA4-CO', 'Lra4 Co', 'tester');
  v_company4 := (select id from app.org_units where tenant_id = v_tenant4 and code = 'LRA4-CO');

  perform app.invite_user(v_tenant4, v_manager4, 'manager4@lra4.test', 'Lra4 Manager', v_company4, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager4@lra4.test'), 'active', 'onboarded', 'tester');
  v_manager_role4 := (app.create_role(v_tenant4, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft4 := app.create_role_version(v_manager_role4, 'tester');
  perform app.set_role_version_permissions(v_manager_draft4.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft4.id, now(), 'tester');
  perform app.assign_role(v_tenant4, (select id from app.role_versions where role_id = v_manager_role4 and status = 'published'), v_manager4, v_manager4, 'tester');

  -- A real published USD locale (mirrors lra3''s own fixture exactly) --
  -- the currency-scope gate this new exception's own detection is
  -- deliberately co-scoped with (this migration's own header) resolves
  -- against this.
  perform app.grant_principal_membership(v_manager4, 'tenant_admin', v_tenant4, null, 'tester');
  v_locale_draft4 := app.create_tenant_locale_draft(v_tenant4, v_manager4, 'tester');
  perform app.set_tenant_locale_config(v_locale_draft4.id, v_manager4, 'id', 'Asia/Jakarta', 'USD', '{}'::jsonb, 'tester');
  perform app.publish_tenant_locale_version(v_locale_draft4.id, v_manager4, clock_timestamp(), 'tester');

  perform app.invite_user(v_tenant4, v_customer_iota, 'customer-iota@lra4.test', 'Lra4 Customer Iota', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-iota@lra4.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant4, 'Lra4 Account Iota', 'lra4-iota-fp', '{}'::jsonb, v_company4, 'tester') returning id into v_account_iota;
  perform app.grant_principal_membership(v_customer_iota, 'customer_user', v_tenant4, v_account_iota::text, 'tester');

  perform app.create_loyalty_program(v_tenant4, 'Lra4 Program', 'Program used ONLY by the ISS-2026-134 item 3 regression.', v_manager4, 'manager4');
  v_program4_id := (select id from app.loyalty_programs where tenant_id = v_tenant4 and name = 'Lra4 Program');
  perform app.update_loyalty_program_status(v_tenant4, v_program4_id, 1, 'active', v_manager4, 'manager4');
  perform app.create_loyalty_program_rule_version(v_tenant4, v_program4_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager4, 'manager4');
  perform app.publish_loyalty_program_rule_version(v_tenant4, (select id from app.loyalty_program_rule_versions where program_id = v_program4_id and status = 'draft'), 1, null, v_manager4, 'manager4');

  perform app.enroll_customer_loyalty_account(v_tenant4, v_account_iota, v_program4_id, v_manager4, 'manager4');

  -- The reward under test: p_internal_cost is explicitly NULL -- a real,
  -- valid, published physical_item reward with no internal_cost configured.
  v_reward := app.create_loyalty_reward_draft(v_tenant4, v_program4_id, 'Lra4 Physical Reward (null cost)', 'physical_item', 'Null internal_cost fixture.', 'Terms.', null, 20, 5, null::numeric, null, null, v_manager4, 'manager4');
  perform app.publish_loyalty_reward(v_tenant4, v_reward.id, v_reward.record_version, null, v_manager4, 'manager4');

  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000346800', v_tenant4, v_account_iota, 'invoice', pg_temp.iss319_mint_invoice(v_tenant4, v_account_iota, v_manager4, 'manager4', 'iss319-lra-iota'), 'USD', 20, 20, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant4, '00000000-0000-0000-0000-000000346800', v_manager4, 'manager4');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000346800');
  perform app.post_loyalty_points_earned(v_tenant4, v_event_id, v_manager4, 'manager4', 365);

  v_redemption := app.submit_loyalty_redemption(v_tenant4, (select id from app.loyalty_accounts where tenant_id = v_tenant4 and customer_account_id = v_account_iota), v_reward.id, 'lra4-iota-redeem-1', v_manager4, 'manager4');
  v_redemption := app.decide_loyalty_redemption(v_tenant4, v_redemption.id, v_redemption.record_version, 'approve', 'approved for null-internal_cost fixture', v_manager4, 'manager4');
  if v_redemption.status <> 'fulfilling' then
    raise exception 'assertion failed: expected Iota''s redemption to be fulfilling, got %', v_redemption.status;
  end if;

  v_run := app.execute_loyalty_liability_reconciliation_run(v_tenant4, null, 'USD', v_manager4, 'manager4', 'lra4-run-1', 1);
  if v_run.status <> 'exceptions_pending' then
    raise exception 'assertion failed: expected status=exceptions_pending for the null-internal_cost run, got %', v_run.status;
  end if;
  if v_run.reward_fulfillment_liability_total <> 0 then
    raise exception 'assertion failed: expected reward_fulfillment_liability_total = 0 for a null-internal_cost open redemption (unchanged behavior), got %', v_run.reward_fulfillment_liability_total;
  end if;

  select * into v_exception from app.loyalty_liability_reconciliation_exceptions where run_id = v_run.id and exception_type = 'reward_internal_cost_missing';
  if v_exception.id is null then
    raise exception 'assertion failed: expected a real reward_internal_cost_missing exception row, found none';
  end if;
  if (v_exception.detail->>'redemptionId')::uuid <> v_redemption.id or (v_exception.detail->>'rewardId')::uuid <> v_reward.id then
    raise exception 'assertion failed: expected the exception detail to name the exact redemption/reward, got %', v_exception.detail;
  end if;

  -- A currency-mismatched run (co-scoped with the ISS-2026-136 item 1
  -- accumulation gate, this migration's own header) must NOT re-raise the
  -- identical exception -- avoiding the ISS-2026-136 item 2 detection-noise
  -- shape for this new type.
  declare
    v_run_wrong_currency app.loyalty_liability_reconciliation_runs := app.execute_loyalty_liability_reconciliation_run(v_tenant4, null, 'IDR', v_manager4, 'manager4', 'lra4-run-idr', 1);
  begin
    if exists (select 1 from app.loyalty_liability_reconciliation_exceptions where run_id = v_run_wrong_currency.id and exception_type = 'reward_internal_cost_missing') then
      raise exception 'assertion failed: expected NO reward_internal_cost_missing exception on a currency-mismatched (IDR) run of a USD-denominated tenant';
    end if;
  end;

  -- Certify is BLOCKED while this exception remains open.
  begin
    perform app.certify_loyalty_liability_reconciliation_run(v_tenant4, v_run.id, v_run.record_version, v_manager4, 'manager4');
    raise exception 'assertion failed: expected certify to be BLOCKED while the reward_internal_cost_missing exception remains open';
  exception when others then if sqlerrm not like 'loyalty_liability_reconciliation_unresolved_exceptions%' then raise; end if;
  end;

  -- Resolve it (mandatory non-empty reason, the same convention as every
  -- other exception type), then certify succeeds.
  v_exception := app.resolve_loyalty_liability_reconciliation_exception(v_tenant4, v_exception.id, v_exception.record_version, 'accepted -- reward internal_cost intentionally left unset for this test fixture', v_manager4, 'manager4');
  if v_exception.status <> 'resolved' then
    raise exception 'assertion failed: expected the reward_internal_cost_missing exception to resolve, got status=%', v_exception.status;
  end if;

  -- The run's own status just auto-cleared from exceptions_pending back to
  -- open (the same mechanism the file's own established "resolve all three
  -- exceptions" block above already exercises), bumping record_version --
  -- re-select the current version rather than reuse the pre-resolve one.
  v_run := app.certify_loyalty_liability_reconciliation_run(v_tenant4, v_run.id, (select record_version from app.loyalty_liability_reconciliation_runs where id = v_run.id), v_manager4, 'manager4');
  if v_run.status <> 'certified' then
    raise exception 'assertion failed: expected certify to succeed once the exception is resolved, got status=%', v_run.status;
  end if;
end $$;

\echo '>> fixture: tenant lra5 (own, fully isolated tenant), Loyalty Manager [full LYL] + Finance Viewer/Editor [FIN View/Edit], a published USD locale, a published loyalty program, customer account Epsilon enrolled -- used ONLY by the ISS-2026-134 item 2 (point-in-time) and item 5 (Finance handoff) regressions below'
do $$
declare
  v_tenant5 uuid;
  v_company5 uuid;
  v_manager5 uuid := '00000000-0000-0000-0000-000000346901';
  v_finance5 uuid := '00000000-0000-0000-0000-000000346902';
  v_customer_epsilon uuid := '00000000-0000-0000-0000-000000346910';
  v_account_epsilon uuid;
  v_manager_role5 uuid; v_manager_draft5 app.role_versions;
  v_finance_role5 uuid; v_finance_draft5 app.role_versions;
  v_locale_draft5 app.tenant_locale_versions;
  v_program5_id uuid;
begin
  insert into auth.users (id, email) values
    (v_manager5, 'manager5@lra5.test'),
    (v_finance5, 'finance5@lra5.test'),
    (v_customer_epsilon, 'customer-epsilon@lra5.test');

  perform app.provision_tenant('lra5', 'Liability Recon Test Tenant Five (point-in-time, Finance handoff)', 'idem-lra5', 'tester');
  v_tenant5 := (select id from app.tenants where slug = 'lra5');
  perform app.transition_tenant_status(v_tenant5, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant5, 'company', null, 'LRA5-CO', 'Lra5 Co', 'tester');
  v_company5 := (select id from app.org_units where tenant_id = v_tenant5 and code = 'LRA5-CO');

  perform app.invite_user(v_tenant5, v_manager5, 'manager5@lra5.test', 'Lra5 Manager', v_company5, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager5@lra5.test'), 'active', 'onboarded', 'tester');
  v_manager_role5 := (app.create_role(v_tenant5, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft5 := app.create_role_version(v_manager_role5, 'tester');
  perform app.set_role_version_permissions(v_manager_draft5.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft5.id, now(), 'tester');
  perform app.assign_role(v_tenant5, (select id from app.role_versions where role_id = v_manager_role5 and status = 'published'), v_manager5, v_manager5, 'tester');

  perform app.invite_user(v_tenant5, v_finance5, 'finance5@lra5.test', 'Lra5 Finance', v_company5, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'finance5@lra5.test'), 'active', 'onboarded', 'tester');
  -- v_finance5 deliberately holds FIN:View/Edit and ZERO LYL grant of any
  -- kind -- proves the handoff's own two-sided authority boundary for real.
  v_finance_role5 := (app.create_role(v_tenant5, 'Finance Viewer/Editor', 'FIN View/Edit', 'tester')).id;
  v_finance_draft5 := app.create_role_version(v_finance_role5, 'tester');
  perform app.set_role_version_permissions(v_finance_draft5.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('View', 'Edit')), 'tester');
  perform app.publish_role_version(v_finance_draft5.id, now(), 'tester');
  perform app.assign_role(v_tenant5, (select id from app.role_versions where role_id = v_finance_role5 and status = 'published'), v_finance5, v_manager5, 'tester');

  perform app.grant_principal_membership(v_manager5, 'tenant_admin', v_tenant5, null, 'tester');
  v_locale_draft5 := app.create_tenant_locale_draft(v_tenant5, v_manager5, 'tester');
  perform app.set_tenant_locale_config(v_locale_draft5.id, v_manager5, 'id', 'Asia/Jakarta', 'USD', '{}'::jsonb, 'tester');
  perform app.publish_tenant_locale_version(v_locale_draft5.id, v_manager5, clock_timestamp(), 'tester');

  perform app.invite_user(v_tenant5, v_customer_epsilon, 'customer-epsilon@lra5.test', 'Lra5 Customer Epsilon', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-epsilon@lra5.test'), 'active', 'onboarded', 'tester');
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant5, 'Lra5 Account Epsilon', 'lra5-epsilon-fp', '{}'::jsonb, v_company5, 'tester') returning id into v_account_epsilon;
  perform app.grant_principal_membership(v_customer_epsilon, 'customer_user', v_tenant5, v_account_epsilon::text, 'tester');

  perform app.create_loyalty_program(v_tenant5, 'Lra5 Program', 'Program used ONLY by the ISS-2026-134 items 2/5 regressions.', v_manager5, 'manager5');
  v_program5_id := (select id from app.loyalty_programs where tenant_id = v_tenant5 and name = 'Lra5 Program');
  perform app.update_loyalty_program_status(v_tenant5, v_program5_id, 1, 'active', v_manager5, 'manager5');
  perform app.enroll_customer_loyalty_account(v_tenant5, v_account_epsilon, v_program5_id, v_manager5, 'manager5');
end $$;

\echo '>> ISS-2026-134 item 2 (2026-09-02, point-in-time reconciliation): a run with an explicit past p_as_of reflects ONLY ledger activity dated at or before that moment; the CURRENT (p_as_of omitted) run reflects everything -- the identical raw ledger, two genuinely different, correct totals'
do $$
declare
  v_tenant5 uuid := (select id from app.tenants where slug = 'lra5');
  v_manager5 uuid := '00000000-0000-0000-0000-000000346901';
  v_loyalty_account_epsilon uuid := (select id from app.loyalty_accounts where tenant_id = v_tenant5 and customer_account_id = (select id from app.accounts where tenant_id = v_tenant5 and legal_name = 'Lra5 Account Epsilon'));
  v_t_before timestamptz := clock_timestamp() - interval '2 days';
  v_t_asof timestamptz := clock_timestamp() - interval '1 day';
  v_run_historical app.loyalty_liability_reconciliation_runs;
  v_run_current app.loyalty_liability_reconciliation_runs;
begin
  -- Direct ledger insert (this checkpoint's own established "direct
  -- insert, business logic not under test" precedent, HRT-291/292 and this
  -- same file's own CPL-325 fixtures) -- explicit created_at values are the
  -- entire point of this regression, which real-time RPC calls cannot
  -- deterministically control within one test run.
  insert into app.loyalty_point_ledger_entries (tenant_id, loyalty_account_id, event_type, amount, source_type, idempotency_key, created_by, created_at)
  values (v_tenant5, v_loyalty_account_epsilon, 'earn', 100, 'manual_adjustment', 'lra5-pit-entry-before', 'tester', v_t_before);
  insert into app.loyalty_point_ledger_entries (tenant_id, loyalty_account_id, event_type, amount, source_type, idempotency_key, created_by, created_at)
  values (v_tenant5, v_loyalty_account_epsilon, 'earn', 50, 'manual_adjustment', 'lra5-pit-entry-after', 'tester', clock_timestamp());
  -- Cached balance matches the CURRENT (both-entries) total, so the
  -- "current" run below is genuinely clean (0 point mismatches) -- the
  -- exactness cross-check is not this regression's own concern.
  insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
  values (v_tenant5, v_loyalty_account_epsilon, 150, 0);

  v_run_historical := app.execute_loyalty_liability_reconciliation_run(v_tenant5, v_t_asof, 'USD', v_manager5, 'manager5', 'lra5-pit-historical', 1);
  if v_run_historical.points_liability_total <> 100 then
    raise exception 'assertion failed: expected a p_as_of run strictly between the two ledger entries to reflect ONLY the earlier one (100), got %', v_run_historical.points_liability_total;
  end if;

  v_run_current := app.execute_loyalty_liability_reconciliation_run(v_tenant5, null, 'USD', v_manager5, 'manager5', 'lra5-pit-current', 1);
  if v_run_current.points_liability_total <> 150 then
    raise exception 'assertion failed: expected the current (p_as_of omitted) run to reflect BOTH ledger entries (150), got %', v_run_current.points_liability_total;
  end if;
  if v_run_current.status <> 'open' then
    raise exception 'assertion failed: expected the current run to be exception-free (status=open) given the matching cached balance, got status=%', v_run_current.status;
  end if;
end $$;

\echo '>> ISS-2026-134 item 5 (2026-09-02, Finance liability handoff): a non-certified run is rejected; a certified run''s handoff copies its own totals verbatim and is idempotent on reconciliation_run_id; Finance (FIN:View/Edit) discovers and acknowledges it; Loyalty-only (LYL, no FIN) is rejected by both Finance-side gates; a NULL p_expected_version is rejected outright; a repeat acknowledgement is a safe no-op; both LYL:View and FIN:View can read it back'
do $$
declare
  v_tenant5 uuid := (select id from app.tenants where slug = 'lra5');
  v_manager5 uuid := '00000000-0000-0000-0000-000000346901';
  v_finance5 uuid := '00000000-0000-0000-0000-000000346902';
  v_run app.loyalty_liability_reconciliation_runs;
  v_uncertified_run app.loyalty_liability_reconciliation_runs;
  v_batch app.loyalty_finance_liability_handoff_batches;
  v_replay app.loyalty_finance_liability_handoff_batches;
  v_n integer;
  v_read_lyl app.loyalty_finance_liability_handoff_batches;
  v_read_fin app.loyalty_finance_liability_handoff_batches;
begin
  v_uncertified_run := app.execute_loyalty_liability_reconciliation_run(v_tenant5, null, 'USD', v_manager5, 'manager5', 'lra5-fh-uncertified', 1);
  if v_uncertified_run.status = 'certified' then
    raise exception 'assertion failed: fixture bug -- expected a freshly-executed run to NOT already be certified';
  end if;

  -- A non-certified run is rejected outright -- mirrors HRT-282's own
  -- finalized-only gate.
  begin
    perform app.prepare_finance_liability_handoff_from_loyalty_liability(v_tenant5, v_uncertified_run.id, v_manager5, 'manager5');
    raise exception 'assertion failed: expected loyalty_liability_reconciliation_run_not_certified for a non-certified run';
  exception when others then
    if sqlerrm not like 'loyalty_liability_reconciliation_run_not_certified%' then raise; end if;
  end;

  -- Certify the SAME run this file's own point-in-time section above
  -- already produced clean (status=open, zero exceptions) -- re-select the
  -- current row rather than reuse the pre-existing variable, since this is
  -- a genuinely separate `do` block.
  select * into v_run from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant5 and idempotency_key = 'lra5-pit-current';
  v_run := app.certify_loyalty_liability_reconciliation_run(v_tenant5, v_run.id, v_run.record_version, v_manager5, 'manager5');
  if v_run.status <> 'certified' then
    raise exception 'assertion failed: expected the clean lra5-pit-current run to certify, got status=%', v_run.status;
  end if;

  v_batch := app.prepare_finance_liability_handoff_from_loyalty_liability(v_tenant5, v_run.id, v_manager5, 'manager5');
  if v_batch.points_liability_total <> v_run.points_liability_total
    or v_batch.cashback_liability_total <> v_run.cashback_liability_total
    or v_batch.discount_liability_total <> v_run.discount_liability_total
    or v_batch.voucher_liability_total <> v_run.voucher_liability_total
    or v_batch.reward_fulfillment_liability_total <> v_run.reward_fulfillment_liability_total
    or v_batch.currency <> v_run.currency
    or v_batch.as_of <> v_run.as_of
    or v_batch.status <> 'pending_acknowledgement' then
    raise exception 'assertion failed: expected the handoff batch to copy the certified run''s own totals verbatim, got %', to_jsonb(v_batch);
  end if;

  -- Idempotent on reconciliation_run_id -- a replay returns the SAME batch,
  -- never a second one.
  v_replay := app.prepare_finance_liability_handoff_from_loyalty_liability(v_tenant5, v_run.id, v_manager5, 'manager5');
  if v_replay.id <> v_batch.id then
    raise exception 'assertion failed: expected a replayed prepare call to return the SAME batch id, got % vs %', v_replay.id, v_batch.id;
  end if;
  select count(*) into v_n from app.loyalty_finance_liability_handoff_batches where reconciliation_run_id = v_run.id;
  if v_n <> 1 then raise exception 'assertion failed: expected exactly ONE handoff batch for this run, got %', v_n; end if;

  -- Loyalty-only (LYL:Configure, zero FIN grant) cannot discover or
  -- acknowledge -- the ONE place a Finance-side authority check applies.
  begin
    perform app.search_loyalty_finance_handoffs_pending_acknowledgement(v_tenant5, v_manager5);
    raise exception 'assertion failed: expected insufficient_authority for a LYL-only actor searching pending Finance handoffs';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  begin
    perform app.acknowledge_loyalty_finance_liability_handoff(v_batch.id, v_batch.record_version, v_manager5, 'manager5');
    raise exception 'assertion failed: expected insufficient_authority for a LYL-only actor acknowledging a Finance handoff';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Finance (FIN:View) discovers it.
  select count(*) into v_n from app.search_loyalty_finance_handoffs_pending_acknowledgement(v_tenant5, v_finance5) where id = v_batch.id;
  if v_n <> 1 then raise exception 'assertion failed: expected Finance (FIN:View) to discover the pending handoff batch, got % matching rows', v_n; end if;

  -- NULL p_expected_version rejected outright (ISS-2026-318 discipline),
  -- even for a genuinely FIN:Edit-authorized actor.
  begin
    perform app.acknowledge_loyalty_finance_liability_handoff(v_batch.id, null, v_finance5, 'finance5');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version';
  exception when others then
    if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_batch := app.acknowledge_loyalty_finance_liability_handoff(v_batch.id, v_batch.record_version, v_finance5, 'finance5');
  if v_batch.status <> 'acknowledged' or v_batch.acknowledged_by <> 'finance5' or v_batch.acknowledged_at is null then
    raise exception 'assertion failed: expected FIN:Edit acknowledgement to succeed and record acknowledged_by/acknowledged_at, got %', to_jsonb(v_batch);
  end if;

  -- A repeat acknowledgement (any expected_version) is a safe no-op --
  -- never a re-stamped acknowledged_by/acknowledged_at.
  v_replay := app.acknowledge_loyalty_finance_liability_handoff(v_batch.id, 999999, v_finance5, 'finance5');
  if v_replay.acknowledged_by <> v_batch.acknowledged_by or v_replay.acknowledged_at <> v_batch.acknowledged_at then
    raise exception 'assertion failed: expected a repeat acknowledgement to be a no-op, got a changed acknowledged_by/acknowledged_at';
  end if;

  -- Readable by EITHER side of the boundary.
  v_read_lyl := app.get_loyalty_finance_liability_handoff(v_batch.id, v_manager5);
  v_read_fin := app.get_loyalty_finance_liability_handoff(v_batch.id, v_finance5);
  if v_read_lyl.id <> v_batch.id or v_read_fin.id <> v_batch.id then
    raise exception 'assertion failed: expected both LYL:View and FIN:View to read the SAME handoff batch back';
  end if;
end $$;

\echo '>> ISS-2026-134 item 1 (2026-09-02, cross-currency reconciliation) fixture: tenant lra6 (own, fully isolated tenant), one actor holding full LYL + full FIN (View/Edit/Approve), a published USD-base locale, a program, one customer account enrolled; a real approved EUR->USD spot rate (1.10)'
do $$
declare
  v_tenant6 uuid;
  v_company6 uuid;
  v_manager6 uuid := '00000000-0000-0000-0000-000000346801';
  v_account6 uuid;
  v_role6 uuid; v_draft6 app.role_versions;
  v_locale_draft6 app.tenant_locale_versions;
  v_program6_id uuid;
  v_rate app.finance_exchange_rates;
begin
  insert into auth.users (id, email) values (v_manager6, 'manager6@lra6.test');

  perform app.provision_tenant('lra6', 'Liability Recon Test Tenant Six (cross-currency)', 'idem-lra6', 'tester');
  v_tenant6 := (select id from app.tenants where slug = 'lra6');
  perform app.transition_tenant_status(v_tenant6, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant6, 'company', null, 'LRA6-CO', 'Lra6 Co', 'tester');
  v_company6 := (select id from app.org_units where tenant_id = v_tenant6 and code = 'LRA6-CO');

  perform app.invite_user(v_tenant6, v_manager6, 'manager6@lra6.test', 'Lra6 Manager', v_company6, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager6@lra6.test'), 'active', 'onboarded', 'tester');
  v_role6 := (app.create_role(v_tenant6, 'Full LYL+FIN', 'full LYL and FIN authority, one actor for test simplicity', 'tester')).id;
  v_draft6 := app.create_role_version(v_role6, 'tester');
  perform app.set_role_version_permissions(v_draft6.id, array(select id from app.permissions where (resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')) or (resource_module_code = 'FIN' and action in ('View', 'Edit', 'Approve'))), 'tester');
  perform app.publish_role_version(v_draft6.id, now(), 'tester');
  perform app.assign_role(v_tenant6, (select id from app.role_versions where role_id = v_role6 and status = 'published'), v_manager6, v_manager6, 'tester');
  perform app.grant_principal_membership(v_manager6, 'tenant_admin', v_tenant6, null, 'tester');

  v_locale_draft6 := app.create_tenant_locale_draft(v_tenant6, v_manager6, 'tester');
  perform app.set_tenant_locale_config(v_locale_draft6.id, v_manager6, 'en', 'Asia/Jakarta', 'USD', '{}'::jsonb, 'tester');
  perform app.publish_tenant_locale_version(v_locale_draft6.id, v_manager6, clock_timestamp(), 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant6, 'Lra6 Account', 'lra6-account-fp', '{}'::jsonb, v_company6, 'tester') returning id into v_account6;

  perform app.create_loyalty_program(v_tenant6, 'Lra6 Program', 'Program used ONLY by the ISS-2026-134 item 1 cross-currency regression.', v_manager6, 'manager6');
  v_program6_id := (select id from app.loyalty_programs where tenant_id = v_tenant6 and name = 'Lra6 Program');
  perform app.update_loyalty_program_status(v_tenant6, v_program6_id, 1, 'active', v_manager6, 'manager6');
  perform app.enroll_customer_loyalty_account(v_tenant6, v_account6, v_program6_id, v_manager6, 'manager6');

  v_rate := app.create_finance_exchange_rate_draft(v_tenant6, 'spot', 'EUR', 'USD', 1.10, 'manual', clock_timestamp() - interval '30 days', null, v_manager6, 'manager6');
  perform app.approve_finance_exchange_rate(v_rate.id, v_rate.record_version, v_manager6, 'manager6');
end $$;

\echo '>> ISS-2026-134 item 1: a run across ALL of a tenant''s currencies, in one call, converts each currency-scoped entitlement total into the tenant''s own base_currency (via app.resolve_operations_fx_conversion, ISS-2026-197) and sums them into one true consolidated total -- something no staff member manually summing raw per-currency figures could ever do correctly'
do $$
declare
  v_tenant6 uuid := (select id from app.tenants where slug = 'lra6');
  v_manager6 uuid := '00000000-0000-0000-0000-000000346801';
  v_account6 uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra6') and legal_name = 'Lra6 Account');
  v_loyalty_account6 uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra6') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra6') and legal_name = 'Lra6 Account'));
  v_consolidated app.loyalty_liability_reconciliation_consolidated_runs;
  v_as_of timestamptz;
begin
  perform app.issue_loyalty_benefit_entitlement(v_tenant6, v_loyalty_account6, 'cashback', 100, null, 'USD', 'manual', null, null, 'lra6-usd-cashback', v_manager6, 'manager6');
  perform app.issue_loyalty_benefit_entitlement(v_tenant6, v_loyalty_account6, 'cashback', 50, null, 'EUR', 'manual', null, null, 'lra6-eur-cashback', v_manager6, 'manager6');

  -- Captured AFTER both entitlements are issued (a DECLARE-time default
  -- evaluates at block entry, BEFORE any statement in the body runs, which
  -- would exclude both entitlements from the currency-scope query below).
  v_as_of := clock_timestamp();

  -- Plain (no-LYL) authority is denied outright -- same gate as the
  -- underlying per-currency RPC, re-checked here too.
  begin
    perform app.execute_loyalty_liability_reconciliation_run_all_currencies(v_tenant6, v_as_of, '00000000-0000-0000-0000-000000000099', 'nobody', 'lra6-denied');
    raise exception 'assertion failed: expected insufficient_authority for an unrecognized/unauthorized actor';
  exception when others then if sqlerrm not like 'insufficient_authority%' and sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  v_consolidated := app.execute_loyalty_liability_reconciliation_run_all_currencies(v_tenant6, v_as_of, v_manager6, 'manager6', 'lra6-consolidated-1');
  if v_consolidated.base_currency <> 'USD' then
    raise exception 'assertion failed: expected base_currency=USD (the tenant''s own resolved default), got %', v_consolidated.base_currency;
  end if;
  if not (v_consolidated.member_currencies @> array['USD', 'EUR'] and array_length(v_consolidated.member_currencies, 1) = 2) then
    raise exception 'assertion failed: expected exactly the two currencies this tenant has entitlements in (USD, EUR), got %', v_consolidated.member_currencies;
  end if;
  if array_length(v_consolidated.member_run_ids, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 member runs (one per currency), got %', array_length(v_consolidated.member_run_ids, 1);
  end if;
  -- 100 (USD, identity) + 50*1.10 (EUR->USD, the real approved rate) = 155.00 --
  -- a number no plain sum of the two raw per-currency figures (100 + 50 = 150)
  -- would ever produce, and no staff member manually summing raw per-currency
  -- runs could compute without first knowing to convert.
  if v_consolidated.cashback_liability_base_amount <> 155.00 then
    raise exception 'assertion failed: expected cashback_liability_base_amount = 100 + (50 * 1.10) = 155.00, got %', v_consolidated.cashback_liability_base_amount;
  end if;
  if v_consolidated.status <> 'complete' or jsonb_array_length(v_consolidated.unconverted_lines) <> 0 then
    raise exception 'assertion failed: expected status=complete with zero unconverted lines (a real rate covers both currencies), got status=% unconverted=%', v_consolidated.status, v_consolidated.unconverted_lines;
  end if;

  -- Idempotent: the SAME explicit key returns the IDENTICAL row, never
  -- recomputes, never duplicates the two per-currency member runs it drove.
  declare
    v_replay app.loyalty_liability_reconciliation_consolidated_runs;
  begin
    v_replay := app.execute_loyalty_liability_reconciliation_run_all_currencies(v_tenant6, v_as_of, v_manager6, 'manager6', 'lra6-consolidated-1');
    if v_replay.id <> v_consolidated.id or v_replay.cashback_liability_base_amount <> v_consolidated.cashback_liability_base_amount then
      raise exception 'assertion failed: expected an explicit-key replay to return the IDENTICAL consolidated row, got id % vs %', v_replay.id, v_consolidated.id;
    end if;
  end;
  if (select count(*) from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant6) <> 2 then
    raise exception 'assertion failed: expected the replay to still leave exactly 2 member runs (USD, EUR), never a duplicate';
  end if;

  -- A staff member who ALREADY ran the USD leg manually today gets that
  -- SAME run reused here, never duplicated -- the consolidated call composes
  -- the existing per-currency RPC, it does not fork a parallel path.
  if (select count(*) from app.loyalty_liability_reconciliation_runs where tenant_id = v_tenant6 and currency = 'USD') <> 1 then
    raise exception 'assertion failed: expected exactly 1 USD member run to exist, reused rather than duplicated';
  end if;
end $$;

\echo '>> ISS-2026-134 item 1: a currency with NO approved exchange rate is EXCLUDED from the consolidated total (never treated as zero, which would silently understate a real liability) and disclosed in unconverted_lines, status=partial_rate_unavailable -- never fabricate, disclose the gap'
do $$
declare
  v_tenant6 uuid := (select id from app.tenants where slug = 'lra6');
  v_manager6 uuid := '00000000-0000-0000-0000-000000346801';
  v_loyalty_account6 uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'lra6') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'lra6') and legal_name = 'Lra6 Account'));
  v_consolidated app.loyalty_liability_reconciliation_consolidated_runs;
  v_as_of timestamptz;
  v_unconverted jsonb;
begin
  -- JPY: a real, structurally valid ISO currency with NO app.finance_
  -- exchange_rates row of any kind configured for this tenant.
  perform app.issue_loyalty_benefit_entitlement(v_tenant6, v_loyalty_account6, 'cashback', 1000, null, 'JPY', 'manual', null, null, 'lra6-jpy-cashback', v_manager6, 'manager6');

  -- Captured AFTER issuing (see the prior block's own identical note).
  v_as_of := clock_timestamp();

  v_consolidated := app.execute_loyalty_liability_reconciliation_run_all_currencies(v_tenant6, v_as_of, v_manager6, 'manager6', 'lra6-consolidated-2-partial');
  if v_consolidated.status <> 'partial_rate_unavailable' then
    raise exception 'assertion failed: expected status=partial_rate_unavailable once a currency has no approved rate, got %', v_consolidated.status;
  end if;
  if not (v_consolidated.member_currencies @> array['USD', 'EUR', 'JPY'] and array_length(v_consolidated.member_currencies, 1) = 3) then
    raise exception 'assertion failed: expected exactly 3 member currencies (USD, EUR, JPY), got %', v_consolidated.member_currencies;
  end if;
  -- The JPY cashback line is EXCLUDED, not zeroed -- the USD+EUR total is
  -- UNCHANGED from the prior (complete) run.
  if v_consolidated.cashback_liability_base_amount <> 155.00 then
    raise exception 'assertion failed: expected the USD+EUR total to stay exactly 155.00 (JPY excluded, never silently zeroed or fabricated), got %', v_consolidated.cashback_liability_base_amount;
  end if;

  select jsonb_agg(elem) into v_unconverted from jsonb_array_elements(v_consolidated.unconverted_lines) elem where elem ->> 'currency' = 'JPY';
  if v_unconverted is null or jsonb_array_length(v_unconverted) <> 1 or (v_unconverted -> 0 ->> 'line') <> 'cashback' or ((v_unconverted -> 0 ->> 'raw_amount')::numeric) <> 1000 then
    raise exception 'assertion failed: expected exactly one unconverted_lines entry naming (line=cashback, currency=JPY, raw_amount=1000), got %', v_consolidated.unconverted_lines;
  end if;
end $$;

\echo '>> ISS-2026-134 item 1: LYL:View read RPCs (get/list) work and are authority-gated the same way as every other reconciliation read surface; raw-function-grant defense-in-depth (anon holds zero EXECUTE on any of the 3 new functions)'
do $$
declare
  v_tenant6 uuid := (select id from app.tenants where slug = 'lra6');
  v_manager6 uuid := '00000000-0000-0000-0000-000000346801';
  v_consolidated_id uuid := (select id from app.loyalty_liability_reconciliation_consolidated_runs where tenant_id = (select id from app.tenants where slug = 'lra6') and idempotency_key = 'lra6-consolidated-2-partial');
  v_row app.loyalty_liability_reconciliation_consolidated_runs;
  v_list_count integer;
  v_anon_count integer;
begin
  v_row := app.get_loyalty_liability_reconciliation_consolidated_run(v_tenant6, v_consolidated_id, v_manager6);
  if v_row.id <> v_consolidated_id then
    raise exception 'assertion failed: expected get to return the same consolidated run by id';
  end if;

  select count(*) into v_list_count from app.list_loyalty_liability_reconciliation_consolidated_runs(v_tenant6, v_manager6, null, null, 200);
  if v_list_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 consolidated runs listed for lra6 (the complete run and the partial_rate_unavailable run), got %', v_list_count;
  end if;

  begin
    perform app.get_loyalty_liability_reconciliation_consolidated_run(v_tenant6, v_consolidated_id, '00000000-0000-0000-0000-000000344004');
    raise exception 'assertion failed: expected insufficient_authority for a no-LYL-grant actor';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_anon_count from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in (
      'execute_loyalty_liability_reconciliation_run_all_currencies',
      'get_loyalty_liability_reconciliation_consolidated_run',
      'list_loyalty_liability_reconciliation_consolidated_runs'
    ) and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE on any of the 3 new functions, got %', v_anon_count;
  end if;
end $$;

\echo '>> ISS-2026-134 item 4: app.run_loyalty_engagement_metrics_snapshot persists exactly what app.get_loyalty_engagement_metrics reports for the same window (never a second, drifting computation), is idempotent per (tenant, idempotency_key) so a replayed scheduler fire returns the SAME row rather than a second measurement, a genuinely different window is a genuinely different snapshot, the LYL:View gate is inherited from the metrics RPC itself (a Plain User and a customer_user are both refused), and app.list_loyalty_engagement_metric_snapshots is staff-only and newest-first'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lra1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000346001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000346004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000346010';
  v_now timestamptz := clock_timestamp() + interval '1 day';
  v_live record;
  v_snap app.loyalty_engagement_metric_snapshots;
  v_replay app.loyalty_engagement_metric_snapshots;
  v_wide app.loyalty_engagement_metric_snapshots;
  v_rows integer;
begin
  -- The point of the item: a schedule over app.get_loyalty_engagement_metrics alone would
  -- compute these numbers and discard them. Capture the same window through the sweep and
  -- prove the stored row IS the read, not a re-derivation that could drift from it.
  select * into v_live
  from app.get_loyalty_engagement_metrics(v_tenant1, v_now - interval '400 days', v_now, v_manager1);

  select * into v_snap from app.run_loyalty_engagement_metrics_snapshot(
    v_tenant1, v_now, 400, v_manager1, 'tester', 'iss134-item4-w400-p1');

  if v_snap.id is null then
    raise exception 'assertion failed: expected a real persisted snapshot row';
  end if;
  if v_snap.window_days <> 400 then
    raise exception 'assertion failed: expected window_days = 400 stored on the row, got %', v_snap.window_days;
  end if;
  if v_snap.active_loyalty_accounts_count <> v_live.active_loyalty_accounts_count
     or v_snap.points_earned_total <> v_live.points_earned_total
     or v_snap.points_redeemed_total <> v_live.points_redeemed_total
     or v_snap.redemption_count <> v_live.redemption_count
     or v_snap.redemption_rate <> v_live.redemption_rate
     or v_snap.published_reward_count <> v_live.published_reward_count
     or v_snap.rewards_with_redemption_count <> v_live.rewards_with_redemption_count then
    raise exception 'assertion failed: the snapshot disagrees with app.get_loyalty_engagement_metrics for the same window -- snapshot=% live=%',
      to_jsonb(v_snap), to_jsonb(v_live);
  end if;
  -- Anchored to this file's own already-asserted fixture numbers, so a future change to the
  -- metric arithmetic cannot make both sides agree on the wrong answer.
  if v_snap.active_loyalty_accounts_count <> 4 or v_snap.points_earned_total <> 800
     or v_snap.redemption_count <> 1 or v_snap.redemption_rate <> 0.2500 then
    raise exception 'assertion failed: snapshot did not capture this fixture''s own known engagement numbers, got %', to_jsonb(v_snap);
  end if;

  -- A replayed scheduler fire for a window already captured returns the SAME row -- not a
  -- second measurement taken at a different instant, and not a unique-violation.
  select * into v_replay from app.run_loyalty_engagement_metrics_snapshot(
    v_tenant1, clock_timestamp() + interval '2 days', 400, v_manager1, 'tester', 'iss134-item4-w400-p1');
  if v_replay.id <> v_snap.id or v_replay.computed_at <> v_snap.computed_at then
    raise exception 'assertion failed: expected an idempotent replay to return the identical stored measurement, got a different row';
  end if;
  select count(*) into v_rows from app.loyalty_engagement_metric_snapshots
  where tenant_id = v_tenant1 and idempotency_key = 'iss134-item4-w400-p1';
  if v_rows <> 1 then
    raise exception 'assertion failed: expected exactly one row for the replayed key, found %', v_rows;
  end if;

  -- A different window is a genuinely different measurement, which is why window_days is part
  -- of the scheduler's own idempotency key rather than the day alone.
  select * into v_wide from app.run_loyalty_engagement_metrics_snapshot(
    v_tenant1, v_now, 1, v_manager1, 'tester', 'iss134-item4-w1-p1');
  if v_wide.id = v_snap.id then
    raise exception 'assertion failed: a different window must produce its own snapshot row';
  end if;
  if v_wide.window_days <> 1 then
    raise exception 'assertion failed: expected window_days = 1 on the narrow snapshot, got %', v_wide.window_days;
  end if;

  -- A window shorter than a day is refused rather than silently widened.
  begin
    perform app.run_loyalty_engagement_metrics_snapshot(v_tenant1, v_now, 0, v_manager1, 'tester', 'iss134-item4-w0');
    raise exception 'assertion failed: expected invalid_window for a zero-day window';
  exception when check_violation then
    if sqlerrm not like 'invalid_window%' then raise; end if;
  end;

  -- An empty idempotency key is refused: without one, every fire would be a new measurement.
  begin
    perform app.run_loyalty_engagement_metrics_snapshot(v_tenant1, v_now, 30, v_manager1, 'tester', '   ');
    raise exception 'assertion failed: expected idempotency_key_required for a blank key';
  exception when check_violation then
    if sqlerrm not like 'idempotency_key_required%' then raise; end if;
  end;

  -- Authority is app.get_loyalty_engagement_metrics' own LYL:View gate, inherited rather than
  -- re-implemented -- so both callers that RPC already refuses are refused here too, and no
  -- partial row is written for either.
  begin
    perform app.run_loyalty_engagement_metrics_snapshot(v_tenant1, v_now, 30, v_plain1, 'tester', 'iss134-item4-plain');
    raise exception 'assertion failed: expected a Plain User to be denied the snapshot sweep';
  exception when insufficient_privilege then null;
  end;
  begin
    perform app.run_loyalty_engagement_metrics_snapshot(v_tenant1, v_now, 30, v_customer_alpha, 'tester', 'iss134-item4-customer');
    raise exception 'assertion failed: expected a customer_user to be denied the snapshot sweep';
  exception when insufficient_privilege then null;
  end;
  select count(*) into v_rows from app.loyalty_engagement_metric_snapshots
  where tenant_id = v_tenant1 and idempotency_key in ('iss134-item4-plain', 'iss134-item4-customer');
  if v_rows <> 0 then
    raise exception 'assertion failed: a denied sweep must persist nothing, found % row(s)', v_rows;
  end if;

  -- The read side: staff-only, newest-first, and filterable by window so one series can be
  -- read without the other interleaved into it.
  select count(*) into v_rows from app.list_loyalty_engagement_metric_snapshots(v_tenant1, v_manager1, null, null, null, 50);
  if v_rows < 2 then
    raise exception 'assertion failed: expected at least the two snapshots taken above, got %', v_rows;
  end if;
  select count(*) into v_rows from app.list_loyalty_engagement_metric_snapshots(v_tenant1, v_manager1, 400, null, null, 50);
  if v_rows <> 1 then
    raise exception 'assertion failed: expected exactly the one 400-day snapshot when filtering by window, got %', v_rows;
  end if;
  begin
    perform app.list_loyalty_engagement_metric_snapshots(v_tenant1, v_customer_alpha, null, null, null, 50);
    raise exception 'assertion failed: expected a customer_user to be denied the snapshot series -- tenant-internal analytics must not leak through the stored rows either';
  exception when insufficient_privilege then null;
  end;
end $$;

\echo '>> ISS-2026-134 item 4: the scheduler catalogue carries the new task, and app._run_scheduled_task_once genuinely dispatches it -- a catalogue row with no dispatch branch would raise scheduled_task_not_dispatchable at fire time rather than at migration time'
do $$
declare
  v_def app.scheduled_task_definitions;
begin
  select * into v_def from app.scheduled_task_definitions where task_code = 'loyalty_engagement_metrics_snapshot';
  if not found then
    raise exception 'assertion failed: expected a loyalty_engagement_metrics_snapshot catalogue row';
  end if;
  if not v_def.tenant_admin_configurable then
    raise exception 'assertion failed: expected the engagement-metrics snapshot to be delegable to tenant admins -- measuring its own commercial rhythm is a tenant decision, unlike the liability-reconciliation sibling';
  end if;
  if v_def.min_interval_minutes <> 1440 then
    raise exception 'assertion failed: expected a daily interval floor, got %', v_def.min_interval_minutes;
  end if;
  if not (v_def.required_params @> array['window_days']) then
    raise exception 'assertion failed: window_days must be a REQUIRED param -- a defaulted window produces a series whose rows cannot be told apart, got %', v_def.required_params;
  end if;

  -- Every catalogue task must have a dispatch branch; this proves the new one does, using the
  -- same pg_proc read the file's own defense-in-depth checks already use rather than firing a
  -- real schedule (which would need a live authorized identity and a due timestamp).
  if (select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = '_run_scheduled_task_once')
     not like '%loyalty_engagement_metrics_snapshot%' then
    raise exception 'assertion failed: app._run_scheduled_task_once has no dispatch branch for loyalty_engagement_metrics_snapshot';
  end if;
end $$;

\echo '>> ALL PASSED: CPL-323 Liability Reconciliation Analytics'
