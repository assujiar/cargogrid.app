-- Real, executable test evidence for CPL-322 (CG-S13-CPL-024, Prompt 322,
-- "Expiry and Fraud Prevention") -- run via `pnpm run db:test` against a
-- real, disposable Postgres database. The THIRD prompt of Batch 5
-- (CPL-320..323), and the SEVENTH Loyalty-domain db-test in this
-- repository.
--
-- UUID range 00000000-0000-0000-0000-0000003450xx (tenant efp1) /
-- 00000000-0000-0000-0000-0000003451xx (tenant efp2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Fixture shortcuts, disclosed (mirror CPL-318/319's own established
-- "directly fixture-backdate, never through the RPC" precedent exactly):
-- (a) a points lot is created via the real app.finance_ar_open_items (paid)
-- -> app.evaluate_customer_loyalty_earning_for_paid_invoice -> app.post_
-- loyalty_points_earned chain, then its own expires_at is directly
-- backdated (never through any RPC, none of which lets a caller set that
-- field directly) to make it genuinely due for expiry; (b) a voucher
-- entitlement is issued with a real future expires_at (issuance itself
-- rejects a past one), then directly backdated the same way.
--
-- Covers, live: (a) expiry sweep idempotency/replay (running twice for the
-- same period does not double-expire); (b) storm-control -- a REAL
-- two-process concurrent race for the SAME tenant+run_label serializes,
-- never double-processing (reusing scripts/db-tests/wms-picking-
-- concurrency-helper.sh); (c) fraud case open -> hold-applied ->
-- claim(under_review) -> confirm (hold stays) / open -> clear (hold
-- released) full lifecycle, both decision branches; (d) suppression
-- blocking a new case while active and auto-revoking once expired; (e)
-- redaction -- risk_signal_type/risk_signal_detail/review_reason/
-- reviewed_by never appear in any customer-facing read, grep-provable via a
-- dynamic to_jsonb(...) ? 'field' probe; (f) a held account correctly
-- blocked from CPL-321's own app.submit_loyalty_redemption (live
-- cross-prompt regression proof); (g) optimistic-concurrency NULL-bypass
-- regression proof across claim/decide/revoke; (h) cross-tenant/cross-
-- account isolation; (i) anti-enumeration; (j) authority boundaries; (k)
-- raw-table RLS / raw-function-grant defense-in-depth; (l) actor-identity
-- session cross-check; (m) keyset pagination.

\set ON_ERROR_STOP on

-- ISS-2026-319 fixture helpers (docs/runtime/KNOWN_ISSUES.md). The new
-- app.validate_finance_open_item_source guard (20260901060000) now rejects a
-- fabricated source_document_id on a direct app.finance_ar_open_items insert,
-- so this file's own direct inserts below (source_document_type = 'invoice')
-- can no longer name a synthetic id that resolves to no real app.finance_invoices
-- row. These pg_temp functions mint a genuinely real, minimal app.finance_invoices
-- row via direct INSERT rather than the full Commercial->Operations RPC pipeline
-- -- this file's own established "directly fixture-backdate, never through the
-- RPC" precedent (this file's own header), extended one layer deeper because the
-- new guard now checks one layer deeper. pg_temp is session-scoped, matching
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

\echo '>> setup: tenant efp1 (Loyalty Manager [full LYL], Plain User [no LYL grant]; customer accounts Alpha/Beta/Gamma, customer_user identities for each), tenant efp2 (its own Loyalty Manager, customer account Zeta); a published loyalty program per tenant; Alpha/Beta/Gamma/Zeta all enrolled'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_account_zeta uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- ISS-2026-133 item 1 fix regression: a SECOND LYL:Configure staff
  -- identity in tenant1, used wherever a case opened by v_manager1 must be
  -- DECIDED by a different actor -- self-approval is now structurally
  -- blocked (app.decide_loyalty_fraud_review_case rejects the SAME actor
  -- who opened the case).
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000345004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000345010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000345020';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000345030';
  v_manager2 uuid := '00000000-0000-0000-0000-000000345101';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000345110';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
  v_program_id uuid;
  v_program2_id uuid;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@efp1.test'),
    (v_manager1b, 'manager1b@efp1.test'),
    (v_plain1, 'plain1@efp1.test'),
    (v_customer_alpha, 'customer-alpha@efp1.test'),
    (v_customer_beta, 'customer-beta@efp1.test'),
    (v_customer_gamma, 'customer-gamma@efp1.test'),
    (v_manager2, 'manager2@efp2.test'),
    (v_customer_zeta, 'customer-zeta@efp2.test');

  perform app.provision_tenant('efp1', 'Expiry Fraud Test Tenant One', 'idem-efp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'efp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'EFP1-CO', 'Efp1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'EFP1-CO');

  perform app.provision_tenant('efp2', 'Expiry Fraud Test Tenant Two', 'idem-efp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'efp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'EFP2-CO', 'Efp2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'EFP2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@efp1.test', 'Efp1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@efp1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_manager1b, 'manager1b@efp1.test', 'Efp1 Manager B', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1b@efp1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1b, v_manager1b, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@efp1.test', 'Efp1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@efp1.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Efp Account Alpha', 'efp-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Efp Account Beta', 'efp-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Efp Account Gamma', 'efp-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Efp Account Zeta', 'efp-zeta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_zeta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@efp1.test', 'Efp Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@efp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@efp1.test', 'Efp Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@efp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_gamma, 'customer-gamma@efp1.test', 'Efp Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@efp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant1, v_account_gamma::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@efp2.test', 'Efp2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@efp2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_zeta, 'customer-zeta@efp2.test', 'Efp Customer Zeta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-zeta@efp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_zeta, 'customer_user', v_tenant2, v_account_zeta::text, 'tester');

  perform app.create_loyalty_program(v_tenant1, 'Efp Program', 'Program used to test expiry and fraud prevention.', v_manager1, 'manager1');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Efp Program');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1, 'manager1');
  perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager1, 'manager1');
  perform app.publish_loyalty_program_rule_version(v_tenant1, (select id from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'draft'), 1, null, v_manager1, 'manager1');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1, 'manager1');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1, 'manager1');

  perform app.create_loyalty_program(v_tenant2, 'Efp Program 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Efp Program 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_zeta, v_program2_id, v_manager2, 'manager2');
end $$;

\echo '>> fixture: a discount_voucher reward (real internal_cost) published for the cross-prompt redemption-block test'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'efp1') and name = 'Efp Program');
  v_row app.loyalty_rewards;
begin
  v_row := app.create_loyalty_reward_draft(v_tenant1, v_program_id, 'Efp Voucher Reward', 'discount_voucher', 'A discount voucher.', 'Terms.', null, 0, null, 25, 'vendor-1', null, v_manager1, 'manager1');
  perform app.publish_loyalty_reward(v_tenant1, v_row.id, v_row.record_version, null, v_manager1, 'manager1');
end $$;

\echo '>> fixture: Alpha earns 100 points (paid invoice -> earning event -> lot), lot directly backdated to be due for expiry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Alpha');
  v_event_id uuid;
  v_lot app.loyalty_point_lots;
begin
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000345201', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-efp-alpha'), 'USD', 100, 100, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000345201', v_manager1, 'manager1');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000345201');
  perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1, 'manager1', 365);
  select * into v_lot from app.loyalty_point_lots where source_earning_event_id = v_event_id;
  -- Directly fixture-backdate expires_at into the past -- never through the
  -- RPC (mirrors CPL-318's own established "next_review_at backdate"
  -- precedent for exactly this class of timing test).
  update app.loyalty_point_lots set expires_at = clock_timestamp() - interval '1 day' where id = v_lot.id;
end $$;

\echo '>> fixture: Beta is issued a real voucher entitlement, directly backdated to be due for expiry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Beta'));
  v_row record;
begin
  select * into v_row from app.issue_loyalty_benefit_entitlement(v_tenant1, v_loyalty_account_beta, 'voucher', 10, null, 'USD', 'manual', null, clock_timestamp() + interval '1 day', 'beta-voucher-expiry', v_manager1, 'manager1');
  update app.loyalty_benefit_entitlements set expires_at = clock_timestamp() - interval '1 day' where id = v_row.id;
end $$;

\echo '>> app.run_loyalty_expiry_sweep: composes app.expire_loyalty_point_lots + app.expire_loyalty_benefit_entitlements, real counts recorded on the completed job row (mandatory test)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000345004';
  v_run record;
begin
  -- Plain User lacks LYL:Edit.
  begin
    perform app.run_loyalty_expiry_sweep(v_tenant1, now(), v_plain1, 'plain1', null);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User expiry sweep attempt';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_run from app.run_loyalty_expiry_sweep(v_tenant1, now(), v_manager1, 'manager1', null);
  if v_run.status <> 'completed' then
    raise exception 'assertion failed: expected a completed run, got %', v_run.status;
  end if;
  if v_run.lots_expired_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 lot expired (Alpha), got %', v_run.lots_expired_count;
  end if;
  if v_run.entitlements_expired_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 entitlement expired (Beta), got %', v_run.entitlements_expired_count;
  end if;

  if not exists (select 1 from app.loyalty_point_lots where tenant_id = v_tenant1 and status = 'expired') then
    raise exception 'assertion failed: expected Alpha''s lot to now be status=expired';
  end if;
  if not exists (select 1 from app.loyalty_benefit_entitlements where tenant_id = v_tenant1 and status = 'expired') then
    raise exception 'assertion failed: expected Beta''s entitlement to now be status=expired';
  end if;
end $$;

\echo '>> idempotency/replay (mandatory test): running the sweep AGAIN for the same day does NOT double-expire -- identical counts recorded, no new expiry ledger entries'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_run record;
  v_lot_expiry_events_before integer;
  v_lot_expiry_events_after integer;
  v_entitlement_expiry_events_before integer;
  v_entitlement_expiry_events_after integer;
begin
  select count(*) into v_lot_expiry_events_before from app.loyalty_point_ledger_entries where tenant_id = v_tenant1 and event_type = 'expiry';
  select count(*) into v_entitlement_expiry_events_before from app.loyalty_benefit_entitlement_events where tenant_id = v_tenant1 and event_type = 'expired';

  select * into v_run from app.run_loyalty_expiry_sweep(v_tenant1, now(), v_manager1, 'manager1', null);
  if v_run.status <> 'completed' then
    raise exception 'assertion failed: expected the replay to still report completed, got %', v_run.status;
  end if;
  if v_run.lots_expired_count <> 1 or v_run.entitlements_expired_count <> 1 then
    raise exception 'assertion failed: expected the replay to return the SAME original counts (1, 1), got (%, %)', v_run.lots_expired_count, v_run.entitlements_expired_count;
  end if;

  select count(*) into v_lot_expiry_events_after from app.loyalty_point_ledger_entries where tenant_id = v_tenant1 and event_type = 'expiry';
  select count(*) into v_entitlement_expiry_events_after from app.loyalty_benefit_entitlement_events where tenant_id = v_tenant1 and event_type = 'expired';
  if v_lot_expiry_events_after <> v_lot_expiry_events_before then
    raise exception 'assertion failed: expected NO new point-lot expiry ledger entries on replay, % vs %', v_lot_expiry_events_before, v_lot_expiry_events_after;
  end if;
  if v_entitlement_expiry_events_after <> v_entitlement_expiry_events_before then
    raise exception 'assertion failed: expected NO new entitlement expiry events on replay, % vs %', v_entitlement_expiry_events_before, v_entitlement_expiry_events_after;
  end if;
end $$;

\echo '>> app.list_loyalty_expiry_runs (staff, LYL:View): the completed run appears with its own real counts; Plain User denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000345004';
  v_count integer;
begin
  select count(*) into v_count from app.list_loyalty_expiry_runs(v_tenant1, v_manager1, null, null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 expiry run row (the two calls above share the SAME run_label/idempotency_key), got %', v_count;
  end if;

  begin
    perform app.list_loyalty_expiry_runs(v_tenant1, v_plain1, null, null, 50);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User expiry-run history read';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> HDN-374 (Financial Integrity Audit) finding 4 regression: app.run_loyalty_expiry_sweep''s own p_as_of must actually govern which lots are due -- not silently ignored in favor of the real clock'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Alpha');
  v_event_id uuid;
  v_lot app.loyalty_point_lots;
  v_run record;
  v_future_as_of timestamptz;
begin
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000345203', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-efp-alpha-idem'), 'USD', 20, 20, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000345203', v_manager1, 'manager1');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000345203');
  perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1, 'manager1', 365);
  select * into v_lot from app.loyalty_point_lots where source_earning_event_id = v_event_id;

  -- Due 2 days from the real clock -- NOT yet due by clock_timestamp().
  update app.loyalty_point_lots set expires_at = clock_timestamp() + interval '2 days' where id = v_lot.id;

  -- A sweep evaluated as of the REAL current time must not touch it.
  select * into v_run from app.run_loyalty_expiry_sweep(v_tenant1, now(), v_manager1, 'manager1', 'as-of-regression-real-now');
  if v_run.lots_expired_count <> 0 then
    raise exception 'assertion failed: expected 0 lots expired when evaluated as of the real current time (lot is due 2 days from now), got %', v_run.lots_expired_count;
  end if;
  if exists (select 1 from app.loyalty_point_lots where id = v_lot.id and status = 'expired') then
    raise exception 'assertion failed: expected the not-yet-due lot to remain untouched by a real-time sweep';
  end if;

  -- HDN-374 finding 4 regression: a sweep evaluated as of 3 days from now (AFTER the
  -- lot's own due date) must expire it, even though the real clock has not reached that
  -- date -- proving p_as_of is now actually honored, not silently discarded in favor of
  -- clock_timestamp().
  v_future_as_of := clock_timestamp() + interval '3 days';
  select * into v_run from app.run_loyalty_expiry_sweep(v_tenant1, v_future_as_of, v_manager1, 'manager1', 'as-of-regression-future');
  if v_run.lots_expired_count <> 1 then
    raise exception 'assertion failed: HDN-374 finding 4 regressed -- expected the p_as_of-future sweep to expire the lot due 2 days from now, got lots_expired_count=%', v_run.lots_expired_count;
  end if;
  if not exists (select 1 from app.loyalty_point_lots where id = v_lot.id and status = 'expired') then
    raise exception 'assertion failed: HDN-374 finding 4 regressed -- expected the lot to now be status=expired after a p_as_of-future sweep';
  end if;
end $$;

\echo '>> storm-control (mandatory test): a REAL two-process concurrent race calling app.run_loyalty_expiry_sweep for the SAME tenant+run_label serializes -- exactly ONE real expiry, never double-processed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Gamma');
  v_event_id uuid;
  v_lot app.loyalty_point_lots;
begin
  -- A fresh, dedicated due lot for THIS race (Gamma's own, never touched by
  -- the sequential idempotency test above).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000345202', v_tenant1, v_account_gamma, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_gamma, v_manager1, 'manager1', 'iss319-efp-gamma'), 'USD', 50, 50, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000345202', v_manager1, 'manager1');
  v_event_id := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000345202');
  perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1, 'manager1', 365);
  select * into v_lot from app.loyalty_point_lots where source_earning_event_id = v_event_id;
  update app.loyalty_point_lots set expires_at = clock_timestamp() - interval '1 day' where id = v_lot.id;
end $$;

select (select id from app.tenants where slug = 'efp1') as race_tenant1_id \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

-- Literal-interpolated (never current_setting()/set_config -- the race
-- helper opens brand-new psql CONNECTIONS, which do not share this
-- session's own GUCs). Both processes share the IDENTICAL run_label, so
-- app.enqueue_job's own real unique-constraint blocking behavior is what
-- actually serializes them (design decision 1).
\set race_sql_a 'select app.run_loyalty_expiry_sweep(''' :race_tenant1_id ''', now(), ''00000000-0000-0000-0000-000000345001'', ''manager1'', ''race-day'');'
\set race_sql_b 'select app.run_loyalty_expiry_sweep(''' :race_tenant1_id ''', now(), ''00000000-0000-0000-0000-000000345001'', ''manager1'', ''race-day'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-efp-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-efp-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_job_count integer;
  v_expiry_event_count integer;
  v_gamma_lot_id uuid := (select l.id from app.loyalty_point_lots l join app.loyalty_earning_events e on e.id = l.source_earning_event_id where e.idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000345202');
begin
  -- Exactly ONE job row for this run_label -- app.enqueue_job's own real
  -- unique(tenant_id, idempotency_key) constraint is the storm-control
  -- mechanism.
  select count(*) into v_job_count from app.jobs where tenant_id = v_tenant1 and job_type = 'loyalty_expiry_sweep' and payload->>'run_label' = 'race-day';
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected EXACTLY ONE app.jobs row for run_label=race-day (storm-control), got %', v_job_count;
  end if;
  if (select status from app.jobs where tenant_id = v_tenant1 and job_type = 'loyalty_expiry_sweep' and payload->>'run_label' = 'race-day') <> 'completed' then
    raise exception 'assertion failed: expected the race-day job to have completed';
  end if;

  -- Exactly ONE expiry ledger entry for Gamma's own lot -- never double-
  -- processed regardless of which of the two racing processes actually did
  -- the real work.
  select count(*) into v_expiry_event_count from app.loyalty_point_ledger_entries where tenant_id = v_tenant1 and event_type = 'expiry' and lot_id = v_gamma_lot_id;
  if v_expiry_event_count <> 1 then
    raise exception 'assertion failed: expected EXACTLY ONE expiry ledger entry for the raced lot, got %', v_expiry_event_count;
  end if;
end $$;

\echo '>> fraud case lifecycle A (mandatory test): open -> hold applied -> claim (under_review) -> confirm -> hold STAYS in place (no autonomous action beyond the decision)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- ISS-2026-133 item 1 fix: decide is performed by a DIFFERENT LYL:Configure
  -- actor than the one who opened the case (self-approval is now blocked).
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000345004';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Alpha'));
  v_case app.loyalty_fraud_review_cases;
  v_hold app.loyalty_account_tier_holds;
begin
  -- Plain User lacks LYL:Configure.
  begin
    perform app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_alpha, 'velocity_anomaly', 'burst of redemptions', 'case-a-open', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for a Plain User open-case attempt';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_case := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_alpha, 'velocity_anomaly', 'CONFIDENTIAL: 12 redemption attempts in 4 minutes from 3 distinct IPs', 'case-a-open', v_manager1, 'manager1');
  if v_case.status <> 'open' then
    raise exception 'assertion failed: expected status=open, got %', v_case.status;
  end if;

  -- Idempotent replay (mandatory test): the SAME idempotency_key returns
  -- the IDENTICAL case, never opens a duplicate.
  declare
    v_replay app.loyalty_fraud_review_cases;
  begin
    v_replay := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_alpha, 'velocity_anomaly', 'a different detail text', 'case-a-open', v_manager1, 'manager1');
    if v_replay.id <> v_case.id then
      raise exception 'assertion failed: expected the idempotent replay to return the SAME case id';
    end if;
  end;

  select * into v_hold from app.loyalty_account_tier_holds where loyalty_account_id = v_loyalty_account_alpha;
  if not v_hold.is_held then
    raise exception 'assertion failed: expected app.hold_loyalty_account_tier_benefits to have been composed (is_held=true)';
  end if;

  -- At most one OPEN/UNDER_REVIEW case per account (mandatory test).
  begin
    perform app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_alpha, 'manual_flag', 'a second, distinct flag', 'case-a-open-2', v_manager1, 'manager1');
    raise exception 'assertion failed: expected fraud_review_case_already_active for a second open case on the SAME account';
  exception when others then if sqlerrm not like 'fraud_review_case_already_active%' then raise; end if;
  end;

  -- claim: open -> under_review.
  v_case := app.claim_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, v_manager1, 'manager1');
  if v_case.status <> 'under_review' then
    raise exception 'assertion failed: expected status=under_review after claim, got %', v_case.status;
  end if;

  -- decide: confirm, mandatory non-empty reason.
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'confirm', '', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected reason_required for an empty review_reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- ISS-2026-133 item 1 fix (mandatory test): v_manager1 opened this case
  -- and may NOT also decide it -- self-approval is structurally blocked.
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'confirm', 'attempting to decide my own case', v_manager1, 'manager1');
    raise exception 'assertion failed: expected self_approval_not_allowed when the opening actor also tries to decide';
  exception when others then if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  v_case := app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'confirm', 'confirmed genuine velocity anomaly after manual review', v_manager1b, 'manager1b');
  if v_case.status <> 'confirmed' then
    raise exception 'assertion failed: expected status=confirmed, got %', v_case.status;
  end if;
  if v_case.reviewed_by <> 'manager1b' or v_case.review_reason is null or v_case.decided_at is null then
    raise exception 'assertion failed: expected a real reviewed_by/review_reason/decided_at on confirm';
  end if;

  -- No autonomous action beyond the decision (mandatory test): the hold,
  -- already applied at open time, simply stays -- confirm never touches it.
  select * into v_hold from app.loyalty_account_tier_holds where loyalty_account_id = v_loyalty_account_alpha;
  if not v_hold.is_held then
    raise exception 'assertion failed: expected the hold to STAY in place after confirm (no autonomous action, no release)';
  end if;

  -- Deciding an already-decided case is rejected.
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'clear', 'trying again', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition for deciding an already-confirmed case';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> fraud case lifecycle B (mandatory test): open -> hold applied -> decide directly from OPEN (no claim needed) -> clear -> hold RELEASED'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- ISS-2026-133 item 1 fix: decide is performed by a DIFFERENT LYL:Configure
  -- actor than the one who opened the case (self-approval is now blocked).
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Beta'));
  v_case app.loyalty_fraud_review_cases;
  v_hold app.loyalty_account_tier_holds;
begin
  v_case := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_beta, 'duplicate_device', 'CONFIDENTIAL: same device fingerprint as account Alpha', 'case-b-open', v_manager1, 'manager1');
  select * into v_hold from app.loyalty_account_tier_holds where loyalty_account_id = v_loyalty_account_beta;
  if not v_hold.is_held then
    raise exception 'assertion failed: expected the hold to be applied on open';
  end if;

  -- decide directly from 'open' (never claimed) -- proves BOTH open and
  -- under_review are valid pre-decision states. A DIFFERENT actor than the
  -- opener (ISS-2026-133 item 1 fix).
  v_case := app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'clear', 'verified false positive -- same household, shared device', v_manager1b, 'manager1b');
  if v_case.status <> 'cleared' then
    raise exception 'assertion failed: expected status=cleared, got %', v_case.status;
  end if;

  select * into v_hold from app.loyalty_account_tier_holds where loyalty_account_id = v_loyalty_account_beta;
  if v_hold.is_held then
    raise exception 'assertion failed: expected the hold to be RELEASED after clear';
  end if;
end $$;

\echo '>> suppression (mandatory test): blocks a NEW case while active; auto-revokes once expired, the next case then succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- ISS-2026-133 item 1 fix: the cleanup decide below must use a DIFFERENT
  -- actor than the one who opened the case (self-approval is now blocked).
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Beta'));
  v_suppression app.loyalty_fraud_review_suppressions;
  v_case app.loyalty_fraud_review_cases;
begin
  -- Mandatory non-empty reason, mandatory future expiry.
  begin
    perform app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_beta, '', now() + interval '7 days', v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for an empty suppression reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  begin
    perform app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_beta, 'test', now() - interval '1 day', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_expiry for a past expires_at';
  exception when others then if sqlerrm not like 'invalid_expiry%' then raise; end if;
  end;

  v_suppression := app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_beta, 'verified false positive, cooldown 7 days', now() + interval '7 days', v_manager1, 'manager1');

  -- A NEW case for the SAME account is blocked while the suppression is active.
  begin
    perform app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_beta, 'manual_flag', 'a new flag while suppressed', 'case-suppressed', v_manager1, 'manager1');
    raise exception 'assertion failed: expected fraud_review_suppressed for a new case while an active suppression covers this account';
  exception when others then if sqlerrm not like 'fraud_review_suppressed%' then raise; end if;
  end;

  -- A second suppression on the SAME account while one is already active is rejected.
  begin
    perform app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_beta, 'a second suppression attempt', now() + interval '1 day', v_manager1, 'manager1');
    raise exception 'assertion failed: expected fraud_review_already_suppressed for a second active suppression on the SAME account';
  exception when others then if sqlerrm not like 'fraud_review_already_suppressed%' then raise; end if;
  end;

  -- Directly fixture-backdate the suppression's own expiry into the past --
  -- never through the RPC (mirrors the lot/entitlement backdating pattern
  -- above) -- to prove the auto-revoke-on-next-check behavior (design
  -- decision 7).
  update app.loyalty_fraud_review_suppressions set expires_at = clock_timestamp() - interval '1 hour' where id = v_suppression.id;

  -- The next open-case attempt auto-revokes the stale suppression (never
  -- silently left stale) and then succeeds.
  v_case := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_beta, 'manual_flag', 'a new flag after the suppression expired', 'case-after-suppression', v_manager1, 'manager1');
  if v_case.status <> 'open' then
    raise exception 'assertion failed: expected the new case to open successfully once the suppression auto-revoked';
  end if;
  if (select revoked_reason from app.loyalty_fraud_review_suppressions where id = v_suppression.id) <> 'expired' then
    raise exception 'assertion failed: expected the stale suppression to be auto-revoked with revoked_reason=expired';
  end if;

  -- Suppression never hides the underlying history -- both the case AND
  -- the (now-revoked) suppression remain fully queryable by staff.
  if not exists (select 1 from app.loyalty_fraud_review_suppressions where id = v_suppression.id) then
    raise exception 'assertion failed: expected the revoked suppression row to remain queryable (never deleted)';
  end if;

  -- Clean up: decide this case so it does not interfere with later cross-
  -- tenant/pagination assertions expecting a known state. A DIFFERENT actor
  -- than the opener (ISS-2026-133 item 1 fix).
  perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'clear', 'resolved for test cleanup', v_manager1b, 'manager1b');
end $$;

\echo '>> revoke_loyalty_fraud_review_suppression (mandatory test): staff-only, idempotent on an already-revoked row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Gamma'));
  v_suppression app.loyalty_fraud_review_suppressions;
  v_revoked app.loyalty_fraud_review_suppressions;
  v_replay app.loyalty_fraud_review_suppressions;
begin
  v_suppression := app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_gamma, 'manual cooldown', now() + interval '30 days', v_manager1, 'manager1');
  v_revoked := app.revoke_loyalty_fraud_review_suppression(v_tenant1, v_suppression.id, v_suppression.record_version, 'no longer needed', v_manager1, 'manager1');
  if v_revoked.revoked_at is null or v_revoked.revoked_by <> 'manager1' then
    raise exception 'assertion failed: expected a real revoked_at/revoked_by';
  end if;

  -- Idempotent: revoking an already-revoked suppression is a safe no-op.
  v_replay := app.revoke_loyalty_fraud_review_suppression(v_tenant1, v_suppression.id, v_revoked.record_version, 'again', v_manager1, 'manager1');
  if v_replay.revoked_at <> v_revoked.revoked_at then
    raise exception 'assertion failed: expected the idempotent replay to leave revoked_at unchanged';
  end if;
end $$;

\echo '>> optimistic-concurrency NULL-bypass regression proof (mandatory test) on app.claim_loyalty_fraud_review_case / app.decide_loyalty_fraud_review_case / app.revoke_loyalty_fraud_review_suppression'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- ISS-2026-133 item 1 fix: the real-version decide call below must use a
  -- DIFFERENT actor than the one who opened the case (self-approval is now
  -- blocked) -- claim has no such restriction, so it stays on v_manager1.
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Gamma'));
  v_case app.loyalty_fraud_review_cases;
  v_before app.loyalty_fraud_review_cases;
  v_suppression app.loyalty_fraud_review_suppressions;
  v_sup_before app.loyalty_fraud_review_suppressions;
begin
  v_case := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_gamma, 'manual_flag', 'null-bypass regression fixture', 'case-nullbypass', v_manager1, 'manager1');
  v_before := v_case;

  begin
    perform app.claim_loyalty_fraud_review_case(v_tenant1, v_case.id, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on claim';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select record_version from app.loyalty_fraud_review_cases where id = v_case.id) <> v_before.record_version then
    raise exception 'assertion failed: expected the case row to be byte-for-byte unchanged after the rejected NULL-version claim attempt';
  end if;
  v_case := app.claim_loyalty_fraud_review_case(v_tenant1, v_case.id, v_before.record_version, v_manager1, 'manager1');
  if v_case.status <> 'under_review' then
    raise exception 'assertion failed: expected the real-version claim call to succeed';
  end if;

  v_before := v_case;
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, null, 'clear', 'null-bypass check', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on decide';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select record_version from app.loyalty_fraud_review_cases where id = v_case.id) <> v_before.record_version then
    raise exception 'assertion failed: expected the case row to be byte-for-byte unchanged after the rejected NULL-version decide attempt';
  end if;
  v_case := app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_before.record_version, 'clear', 'resolved for test', v_manager1b, 'manager1b');
  if v_case.status <> 'cleared' then
    raise exception 'assertion failed: expected the real-version decide call to succeed';
  end if;

  v_suppression := app.suppress_loyalty_fraud_review(v_tenant1, v_loyalty_account_gamma, 'null-bypass regression fixture', now() + interval '5 days', v_manager1, 'manager1');
  v_sup_before := v_suppression;
  begin
    perform app.revoke_loyalty_fraud_review_suppression(v_tenant1, v_suppression.id, null, 'attempt', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on revoke';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select revoked_at from app.loyalty_fraud_review_suppressions where id = v_suppression.id) is not null then
    raise exception 'assertion failed: expected the suppression row to remain non-revoked after the rejected NULL-version revoke attempt';
  end if;
  perform app.revoke_loyalty_fraud_review_suppression(v_tenant1, v_suppression.id, v_sup_before.record_version, 'resolved', v_manager1, 'manager1');
end $$;

\echo '>> redaction (mandatory test, grep-provable): risk_signal_type/risk_signal_detail/review_reason/reviewed_by never appear in app.list_customer_portal_loyalty_account_hold_status'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000345010';
  v_row jsonb;
  v_row_text text;
begin
  select to_jsonb(t) into v_row
  from app.list_customer_portal_loyalty_account_hold_status(v_tenant1, v_customer_alpha, null, 50) t
  limit 1;

  if v_row ? 'risk_signal_type' or v_row ? 'riskSignalType' then
    raise exception 'assertion failed: risk_signal_type leaked into the customer-facing hold status projection';
  end if;
  if v_row ? 'risk_signal_detail' or v_row ? 'riskSignalDetail' then
    raise exception 'assertion failed: risk_signal_detail leaked into the customer-facing hold status projection';
  end if;
  if v_row ? 'review_reason' or v_row ? 'reviewReason' then
    raise exception 'assertion failed: review_reason leaked into the customer-facing hold status projection';
  end if;
  if v_row ? 'reviewed_by' or v_row ? 'reviewedBy' then
    raise exception 'assertion failed: reviewed_by leaked into the customer-facing hold status projection';
  end if;

  -- Alpha's own hold (still active, confirmed above) is genuinely visible
  -- as a GENERIC notice, but the real internal detail planted at open time
  -- ("CONFIDENTIAL: 12 redemption attempts...") never appears anywhere in
  -- the returned row's own text.
  select v_row::text into v_row_text;
  if v_row_text like '%CONFIDENTIAL%' or v_row_text like '%12 redemption attempts%' then
    raise exception 'assertion failed: the real internal risk_signal_detail text leaked into the customer-facing projection';
  end if;
  if (v_row->>'is_on_hold')::boolean is distinct from true then
    raise exception 'assertion failed: expected Alpha''s account to show is_on_hold=true (still confirmed-and-held from lifecycle A above)';
  end if;
end $$;

\echo '>> cross-prompt regression (mandatory test): a held account is correctly blocked from CPL-321''s own app.submit_loyalty_redemption'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000345010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Alpha'));
  v_reward_id uuid := (select id from app.loyalty_rewards where tenant_id = (select id from app.tenants where slug = 'efp1') and reward_name = 'Efp Voucher Reward');
  v_err text;
begin
  begin
    perform app.submit_loyalty_redemption(v_tenant1, v_loyalty_account_alpha, v_reward_id, 'redeem-while-held', v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected account_on_hold for a redemption attempt against Alpha''s own STILL-confirmed-and-held account';
  exception when others then
    v_err := sqlerrm;
    if v_err not like 'account_on_hold%' then raise; end if;
  end;
  -- The generic block message never leaks the real internal risk signal.
  if v_err like '%CONFIDENTIAL%' or v_err like '%12 redemption attempts%' then
    raise exception 'assertion failed: the real internal risk_signal_detail leaked into CPL-321''s own account_on_hold error message';
  end if;
end $$;

\echo '>> anti-enumeration (mandatory test): app.get_loyalty_fraud_review_case raises the identical error for a genuinely nonexistent case AND a cross-tenant case'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'efp2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000345101';
  v_real_case_id uuid := (select id from app.loyalty_fraud_review_cases where tenant_id = v_tenant1 limit 1);
  v_err_nonexistent text;
  v_err_cross_tenant text;
begin
  begin
    perform app.get_loyalty_fraud_review_case(v_tenant2, gen_random_uuid(), v_manager2);
  exception when others then v_err_nonexistent := sqlerrm;
  end;
  begin
    perform app.get_loyalty_fraud_review_case(v_tenant2, v_real_case_id, v_manager2);
  exception when others then v_err_cross_tenant := sqlerrm;
  end;
  if v_err_nonexistent is null or v_err_cross_tenant is null then
    raise exception 'assertion failed: expected both probes to raise';
  end if;
  if v_err_nonexistent not like 'loyalty_fraud_review_case_not_found%' or v_err_cross_tenant not like 'loyalty_fraud_review_case_not_found%' then
    raise exception 'assertion failed: expected both errors to carry the loyalty_fraud_review_case_not_found errcode prefix, got % vs %', v_err_nonexistent, v_err_cross_tenant;
  end if;
  if split_part(v_err_nonexistent, ':', 1) <> split_part(v_err_cross_tenant, ':', 1) then
    raise exception 'assertion failed: expected byte-identical error-code prefixes (before the first colon), got % vs %', v_err_nonexistent, v_err_cross_tenant;
  end if;
end $$;

\echo '>> cross-tenant/cross-account isolation (mandatory test): efp2''s own manager cannot act on efp1''s cases/suppressions; efp2''s own customer sees zero efp1 hold-status rows even passing efp1''s own tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'efp2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000345101';
  v_customer_zeta uuid := '00000000-0000-0000-0000-000000345110';
  v_efp1_case_id uuid := (select id from app.loyalty_fraud_review_cases where tenant_id = v_tenant1 limit 1);
  v_row_count integer;
begin
  -- Wrong tenant_id entirely -- efp2's manager has no role assignment there.
  begin
    perform app.open_loyalty_fraud_review_case(v_tenant1, (select id from app.loyalty_accounts where tenant_id = v_tenant1 limit 1), 'manual_flag', 'cross-tenant probe', 'cross-tenant-open', v_manager2, 'manager2');
    raise exception 'assertion failed: expected insufficient_authority for efp2''s manager acting under efp1''s own tenant_id';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Guessing an efp1 case id inside efp2's own scope.
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant2, v_efp1_case_id, 1, 'clear', 'cross-tenant probe', v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_fraud_review_case_not_found for an efp1 case id guessed inside efp2''s own tenant scope';
  exception when others then if sqlerrm not like 'loyalty_fraud_review_case_not_found%' then raise; end if;
  end;

  -- Zeta (efp2) sees zero efp1 hold-status rows even explicitly passing efp1's own tenant_id.
  select count(*) into v_row_count from app.list_customer_portal_loyalty_account_hold_status(v_tenant1, v_customer_zeta, null, 50);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected ZERO rows for a cross-tenant customer hold-status probe, got %', v_row_count;
  end if;

  -- Zeta's own tenant2 read works normally (no rows held there).
  select count(*) into v_row_count from app.list_customer_portal_loyalty_account_hold_status(v_tenant2, v_customer_zeta, null, 50);
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row (Zeta''s own account) on her own tenant2 read, got %', v_row_count;
  end if;
end $$;

\echo '>> actor-identity session cross-check (ATW-031): a forged p_actor_auth_user_id is rejected with actor_identity_mismatch when a genuine session identity is set'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000345010';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Gamma'));
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  begin
    perform app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_gamma, 'manual_flag', 'forged actor probe', 'forged-actor-open', v_customer_alpha, 'alpha');
    raise exception 'assertion failed: expected actor_identity_mismatch for a forged actor id under a real session';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> raw-table RLS / raw-function-grant defense-in-depth: authenticated holds zero direct table grant on either new table; anon holds zero EXECUTE on any of the 11 new functions; a real authenticated-role positive path matches a direct superuser call'
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000345001","role":"authenticated"}', true);
  set local role authenticated;
  begin
    perform 1 from app.loyalty_fraud_review_cases limit 1;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_fraud_review_cases to be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from app.loyalty_fraud_review_suppressions limit 1;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_fraud_review_suppressions to be denied';
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
      'run_loyalty_expiry_sweep', 'list_loyalty_expiry_runs', 'open_loyalty_fraud_review_case', 'claim_loyalty_fraud_review_case',
      'decide_loyalty_fraud_review_case', 'suppress_loyalty_fraud_review', 'revoke_loyalty_fraud_review_suppression',
      'get_loyalty_fraud_review_case', 'list_loyalty_fraud_review_cases', 'list_loyalty_fraud_review_suppressions',
      'list_customer_portal_loyalty_account_hold_status'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected ZERO anon EXECUTE grants on any CPL-322 function, got %', v_count;
  end if;
end $$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- Resolved BEFORE switching role below -- authenticated holds no raw
  -- SELECT on app.loyalty_fraud_review_cases (that is the very thing this
  -- test proves), so this lookup must happen under the original session role.
  v_case_id uuid := (select id from app.loyalty_fraud_review_cases where tenant_id = v_tenant1 limit 1);
  v_row app.loyalty_fraud_review_cases;
begin
  perform set_config('request.jwt.claims', '{"sub":"' || v_manager1 || '","role":"authenticated"}', true);
  set local role authenticated;
  v_row := app.get_loyalty_fraud_review_case(v_tenant1, v_case_id, v_manager1);
  if v_row.id is null then
    raise exception 'assertion failed: expected a real authenticated-role positive read path to succeed';
  end if;
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

\echo '>> keyset pagination on app.list_loyalty_fraud_review_cases, visiting every row exactly once at p_limit=1; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  v_total_count integer;
  v_visited_count integer := 0;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_fraud_review_cases;
  v_row_count integer;
begin
  select count(*) into v_total_count from app.loyalty_fraud_review_cases where tenant_id = v_tenant1;

  loop
    select * into v_page from app.list_loyalty_fraud_review_cases(v_tenant1, v_manager1, null, null, v_cursor_updated_at, v_cursor_id, 1) limit 1;
    get diagnostics v_row_count = row_count;
    exit when v_row_count = 0;
    v_visited_count := v_visited_count + 1;
    v_cursor_updated_at := v_page.updated_at;
    v_cursor_id := v_page.id;
    exit when v_visited_count > v_total_count + 5;
  end loop;

  if v_visited_count <> v_total_count then
    raise exception 'assertion failed: expected keyset pagination to visit every row exactly once, expected % got %', v_total_count, v_visited_count;
  end if;

  begin
    perform app.list_loyalty_fraud_review_cases(v_tenant1, v_manager1, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for a half-supplied cursor';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-133 item 1 regression (mandatory test): self-approval is now blocked between app.open_loyalty_fraud_review_case and app.decide_loyalty_fraud_review_case for the SAME staff identity; a DIFFERENT LYL:Configure staff identity in the same tenant may still decide it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000345001';
  -- v_manager1b (a second LYL:Configure staff identity) already exists --
  -- created in this file's own top-level setup block, above.
  v_manager1b uuid := '00000000-0000-0000-0000-000000345002';
  -- Alpha's own case from lifecycle A (above) already reached a terminal
  -- 'confirmed' status, so its account is free to open a new case on.
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'efp1') and legal_name = 'Efp Account Alpha'));
  v_case app.loyalty_fraud_review_cases;
begin
  v_case := app.open_loyalty_fraud_review_case(v_tenant1, v_loyalty_account_alpha, 'manual_flag', 'ISS-2026-133 self-approval regression fixture', 'case-self-approval', v_manager1, 'manager1');

  -- Column-level proof: the real opening actor identity is now captured.
  if v_case.opened_by_auth_user_id <> v_manager1 then
    raise exception 'assertion failed: expected opened_by_auth_user_id=%, got %', v_manager1, v_case.opened_by_auth_user_id;
  end if;

  -- The SAME actor who opened it may not also decide it.
  begin
    perform app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'confirm', 'attempting to decide my own case', v_manager1, 'manager1');
    raise exception 'assertion failed: expected self_approval_not_allowed when the opening actor also tries to decide';
  exception when others then if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- The case is untouched by the rejected attempt -- still open, still
  -- undecided (mirrors every other self_approval_not_allowed precedent:
  -- a rejected self-decision is a true no-op, never a partial state change).
  select * into v_case from app.loyalty_fraud_review_cases where id = v_case.id;
  if v_case.status <> 'open' or v_case.reviewed_by is not null then
    raise exception 'assertion failed: expected the case to remain open/undecided after the rejected self-approval attempt, got status=%', v_case.status;
  end if;

  -- A DIFFERENT LYL:Configure staff identity in the same tenant is NOT
  -- blocked -- the check is narrowly self-approval, not a broader ban.
  v_case := app.decide_loyalty_fraud_review_case(v_tenant1, v_case.id, v_case.record_version, 'confirm', 'decided by a different reviewer than the opener', v_manager1b, 'manager1b');
  if v_case.status <> 'confirmed' or v_case.reviewed_by <> 'manager1b' then
    raise exception 'assertion failed: expected a different actor to successfully decide the case, got status=% reviewed_by=%', v_case.status, v_case.reviewed_by;
  end if;
end $$;

\echo '>> LYL:View authority boundary on staff reads (Viewer succeeds, Plain User denied)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'efp1');
  v_plain1 uuid := '00000000-0000-0000-0000-000000345004';
begin
  begin
    perform app.list_loyalty_fraud_review_suppressions(v_tenant1, v_plain1, null, false, null, null, 50);
    raise exception 'assertion failed: expected insufficient_authority for a Plain User suppression list read';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-133 item 2, ruled an accepted variant: the account-level hold is sufficient BECAUSE the entitlement-level primitives are already independently staff-callable. That is a claim about the schema, so it is pinned here rather than left as prose that can quietly stop being true'
do $$
declare
  v_fn text;
  v_oid oid;
  v_auth boolean;
  v_anon boolean;
begin
  -- The entry declined to build a second, entitlement-scoped case-and-decide review workflow,
  -- and gave three reasons. Two of them are assertions about this schema rather than opinions:
  --   (b) CPL-319's entitlement-hold primitives already exist and are already independently
  --       staff-callable, so holding ONE suspicious voucher needs no new code;
  --   (a) an account-level hold already blocks every redemption for that account.
  -- (a) is already proven live elsewhere in this file, against a real redemption attempt.
  -- (b) was only ever prose. If somebody later revoked those grants, the ruling would silently
  -- become false and nobody would find out until a fraud investigation needed the lever.
  foreach v_fn in array array['hold_loyalty_benefit_entitlement', 'release_loyalty_benefit_entitlement_hold'] loop
    -- Resolved by oid rather than by a written-out argument list: the two primitives do not
    -- share a signature (the hold takes a reason, the release does not), and a hardcoded one
    -- would make this assertion fail for the wrong reason the first time either changes shape.
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_fn limit 1;
    if v_oid is null then
      raise exception 'assertion failed: app.% no longer exists -- ISS-2026-133 item 2 was ruled acceptable ON THE BASIS that this primitive gives staff a direct entitlement-level lever. Without it the ruling is void and the entry must be reopened, not quietly left closed', v_fn;
    end if;

    select has_function_privilege('authenticated', v_oid, 'EXECUTE') into v_auth;
    select has_function_privilege('anon', v_oid, 'EXECUTE') into v_anon;
    if not v_auth then
      raise exception 'assertion failed: app.% is no longer callable by staff -- the entitlement-level lever ISS-2026-133 item 2 rests on is gone', v_fn;
    end if;
    if v_anon then
      raise exception 'assertion failed: anon must never hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: both entitlement-hold primitives exist and remain staff-callable, so ISS-2026-133 item 2''s ruling still stands on something real';
end $$;

\echo '>> ALL PASSED: CPL-322 Expiry and Fraud Prevention'
