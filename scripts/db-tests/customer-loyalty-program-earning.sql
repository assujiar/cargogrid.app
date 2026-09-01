-- Real, executable test evidence for CPL-316 (CG-S13-CPL-018, Prompt 316,
-- "Loyalty Program and Earning") -- run via `pnpm run db:test` against a
-- real, disposable Postgres database. The FIRST-EVER Loyalty domain db-test
-- in this repository.
--
-- UUID range 00000000-0000-0000-0000-0000003360xx (tenant loy1) /
-- 00000000-0000-0000-0000-0000003370xx (tenant loy2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Covers, live: (a) idempotent earning -- calling app.evaluate_customer_
-- loyalty_earning_for_paid_invoice twice for the same paid invoice produces
-- exactly one event; (b) an ineligible (unpaid/held/below-minimum) invoice
-- is rejected; (c) a rule-version change does not retroactively alter an
-- already-recorded earning event's amount; (d) cross-tenant/cross-account
-- isolation; (e) reversal creates a new linked event rather than deleting
-- the original; (f) program/rule-version draft->published->superseded
-- lifecycle correctness (at most one draft/published per program, never
-- mutated in place); (g) loyalty account enrollment/status lifecycle,
-- including the single-active-enrollment-per-customer-account constraint
-- (migration design decision 1) and its reactivation-collision guard; (h)
-- LYL:Create/Edit/Configure/View authority boundaries on every RPC; (i)
-- customer-facing reads (deny-by-default, customer-safe projection, never
-- internal linkage); (j) raw-table RLS and raw-function grant defense in
-- depth; (k) the actor-identity session cross-check on every one of the 19
-- new RPCs; (l) keyset pagination.

\set ON_ERROR_STOP on

-- ISS-2026-319 fixture helpers (docs/runtime/KNOWN_ISSUES.md). The new
-- app.validate_finance_open_item_source guard (20260901060000) now rejects a
-- fabricated source_document_id on a direct app.finance_ar_open_items insert,
-- so this file's own direct inserts below (source_document_type = 'invoice')
-- can no longer name a synthetic id that resolves to no real app.finance_invoices
-- row. These pg_temp functions mint a genuinely real, minimal app.finance_invoices
-- row via direct INSERT rather than the full Commercial->Operations RPC
-- pipeline, extended one layer deeper than this file's own established "direct
-- fixture insert" precedent because the new guard now checks one layer deeper.
-- pg_temp is session-scoped, matching scripts/db-tests/run.sh's
-- one-psql-connection-per-file execution model.

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

\echo '>> setup: tenant loy1 (org unit, roles: Loyalty Manager [LYL Create/Edit/View/Configure], Loyalty Viewer [LYL View only], Plain User [no LYL grant]; customer accounts Alpha/Beta/Delta/Echo, customer_user identities for Alpha/Beta; an impersonator identity), tenant loy2 (its own Loyalty Manager, customer account Gamma)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_delta uuid;
  v_account_echo uuid;
  v_account_gamma uuid;
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000336002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_impersonator uuid := '00000000-0000-0000-0000-000000336050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000336010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000336020';
  v_manager2 uuid := '00000000-0000-0000-0000-000000337001';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000337010';
  v_manager_role1 uuid;
  v_manager_draft1 app.role_versions;
  v_viewer_role1 uuid;
  v_viewer_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_manager1, 'manager1@loy1.test'),
    (v_viewer1, 'viewer1@loy1.test'),
    (v_plain1, 'plain1@loy1.test'),
    (v_impersonator, 'impersonator@loy1.test'),
    (v_customer_alpha, 'customer-alpha@loy1.test'),
    (v_customer_beta, 'customer-beta@loy1.test'),
    (v_manager2, 'manager2@loy2.test'),
    (v_customer_gamma, 'customer-gamma@loy2.test');

  perform app.provision_tenant('loy1', 'Loyalty Test Tenant One', 'idem-loy1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'loy1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'LOY1-CO', 'Loy1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LOY1-CO');

  perform app.provision_tenant('loy2', 'Loyalty Test Tenant Two', 'idem-loy2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'loy2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'LOY2-CO', 'Loy2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'LOY2-CO');

  perform app.invite_user(v_tenant1, v_manager1, 'manager1@loy1.test', 'Loy1 Manager', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1@loy1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1 := (app.create_role(v_tenant1, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft1 := app.create_role_version(v_manager_role1, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_manager1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer1@loy1.test', 'Loy1 Viewer', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer1@loy1.test'), 'active', 'onboarded', 'tester');
  v_viewer_role1 := (app.create_role(v_tenant1, 'Loyalty Viewer', 'LYL:View only, never Configure/Create/Edit', 'tester')).id;
  v_viewer_draft1 := app.create_role_version(v_viewer_role1, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role1 and status = 'published'), v_viewer1, v_manager1, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@loy1.test', 'Loy1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@loy1.test'), 'active', 'onboarded', 'tester');

  -- impersonator: a real, active tenant1 identity holding the Loyalty
  -- Manager role, used ONLY for the actor-identity session cross-check
  -- (never for a legitimate call).
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@loy1.test', 'Loy1 Impersonator', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@loy1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1 and status = 'published'), v_impersonator, v_manager1, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Loy Account Alpha', 'loy-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Loy Account Beta', 'loy-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Loy Account Delta', 'loy-delta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_delta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Loy Account Echo', 'loy-echo-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_echo;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Loy Account Gamma', 'loy-gamma-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_gamma;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@loy1.test', 'Loy Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@loy1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@loy1.test', 'Loy Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@loy1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@loy2.test', 'Loy2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@loy2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_gamma, 'customer-gamma@loy2.test', 'Loy Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@loy2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant2, v_account_gamma::text, 'tester');

  -- AR open items -- direct fixture insert (bypasses app.post_finance_ar_
  -- open_item/app.apply_finance_ar_allocation, neither under test here,
  -- mirroring CPL-311's own established "direct fixture insert" precedent).
  -- Alpha: 336101 paid/eligible (-> event1 under v1), 336102 open/unpaid,
  -- 336103 paid+HELD, 336104 paid but below the v1 minimum, 336105
  -- paid/eligible (-> event2 under v2, after v1 is superseded).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000336101', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-loy-alpha-1'), 'USD', 1000, 1000, 'paid', false, '2026-08-01', '2026-08-31', 'tester'),
    ('00000000-0000-0000-0000-000000336102', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-loy-alpha-2'), 'USD', 500, 0, 'open', false, '2026-08-05', '2026-09-04', 'tester'),
    ('00000000-0000-0000-0000-000000336103', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-loy-alpha-3'), 'USD', 400, 400, 'paid', true, '2026-08-06', '2026-09-05', 'tester'),
    ('00000000-0000-0000-0000-000000336104', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-loy-alpha-4'), 'USD', 20, 20, 'paid', false, '2026-08-07', '2026-09-06', 'tester'),
    ('00000000-0000-0000-0000-000000336105', v_tenant1, v_account_alpha, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_alpha, v_manager1, 'manager1', 'iss319-loy-alpha-5'), 'USD', 2000, 2000, 'paid', false, '2026-08-08', '2026-09-07', 'tester');
  update app.finance_ar_open_items set hold_reason = 'loy fixture dispute hold', held_by = 'tester', held_at = now() where id = '00000000-0000-0000-0000-000000336103';
  -- Beta: 336106 paid, used for the no_published_rule_version negative test
  -- (Second Program never gets a rule version in this fixture). Echo: 336107
  -- paid, used for loyalty_account_not_active (Echo is never enrolled).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000336106', v_tenant1, v_account_beta, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_beta, v_manager1, 'manager1', 'iss319-loy-beta'), 'USD', 300, 300, 'paid', false, '2026-08-09', '2026-09-08', 'tester'),
    ('00000000-0000-0000-0000-000000336107', v_tenant1, v_account_echo, 'invoice', pg_temp.iss319_mint_invoice(v_tenant1, v_account_echo, v_manager1, 'manager1', 'iss319-loy-echo'), 'USD', 100, 100, 'paid', false, '2026-08-09', '2026-09-08', 'tester');
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000337101', v_tenant2, v_account_gamma, 'invoice', pg_temp.iss319_mint_invoice(v_tenant2, v_account_gamma, v_manager2, 'manager2', 'iss319-loy-gamma'), 'USD', 800, 800, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
end $$;

\echo '>> app.create_loyalty_program: LYL:Create required (Plain User denied); duplicate name rejected; non-empty name required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_program app.loyalty_programs;
begin
  v_program := app.create_loyalty_program(v_tenant1, 'Freight Rewards', 'Earn on every paid invoice.', v_manager1, 'manager1');
  if v_program.status <> 'draft' or v_program.name <> 'Freight Rewards' then
    raise exception 'assertion failed: expected a new draft program named Freight Rewards, got %', v_program;
  end if;

  begin
    perform app.create_loyalty_program(v_tenant1, 'Freight Rewards', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected loyalty_program_name_conflict for a duplicate name';
  exception when others then if sqlerrm not like 'loyalty_program_name_conflict%' then raise; end if;
  end;

  begin
    perform app.create_loyalty_program(v_tenant1, '   ', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_name for a blank name';
  exception when others then if sqlerrm not like 'invalid_name%' then raise; end if;
  end;

  begin
    perform app.create_loyalty_program(v_tenant1, 'Denied Program', null, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User (no LYL grant)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Two more active programs used by later sections: Second Program (never
  -- gets a rule version -- the no_published_rule_version negative test) and
  -- Third Program (Delta's own enrollment-lifecycle sandbox).
  perform app.create_loyalty_program(v_tenant1, 'Second Program', null, v_manager1, 'manager1');
  perform app.update_loyalty_program_status(v_tenant1, (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Second Program'), 1, 'active', v_manager1, 'manager1');
  perform app.create_loyalty_program(v_tenant1, 'Third Program', null, v_manager1, 'manager1');
  perform app.update_loyalty_program_status(v_tenant1, (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Third Program'), 1, 'active', v_manager1, 'manager1');
end $$;

\echo '>> app.update_loyalty_program_status: draft->active->inactive->active canonical; draft->inactive rejected; stale_version rejected; identical-status no-op (record_version unchanged); LYL:Edit required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_program app.loyalty_programs;
begin
  begin
    perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'inactive', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition for draft -> inactive';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  begin
    perform app.update_loyalty_program_status(v_tenant1, v_program_id, 99, 'active', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency (record_version <> NULL is SQL
  -- NULL, which a bare `if ... then raise` treats as false).
  begin
    perform app.update_loyalty_program_status(v_tenant1, v_program_id, null, 'active', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_programs where id = v_program_id) <> 'draft'
     or (select record_version from app.loyalty_programs where id = v_program_id) <> 1 then
    raise exception 'assertion failed: a NULL expected_version must never actually change the row -- status=%, record_version=%',
      (select status from app.loyalty_programs where id = v_program_id), (select record_version from app.loyalty_programs where id = v_program_id);
  end if;

  begin
    perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_program := app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1, 'manager1');
  if v_program.status <> 'active' then
    raise exception 'assertion failed: expected status=active, got %', v_program.status;
  end if;

  -- Identical-status is a safe no-op -- does NOT bump record_version.
  v_program := app.update_loyalty_program_status(v_tenant1, v_program_id, v_program.record_version, 'active', v_manager1, 'manager1');
  if v_program.record_version <> 2 then
    raise exception 'assertion failed: expected an identical-status call to be a no-op (record_version still 2), got %', v_program.record_version;
  end if;

  v_program := app.update_loyalty_program_status(v_tenant1, v_program_id, 2, 'inactive', v_manager1, 'manager1');
  if v_program.status <> 'inactive' then
    raise exception 'assertion failed: expected status=inactive, got %', v_program.status;
  end if;

  v_program := app.update_loyalty_program_status(v_tenant1, v_program_id, 3, 'active', v_manager1, 'manager1');
  if v_program.status <> 'active' then
    raise exception 'assertion failed: expected status=active again, got %', v_program.status;
  end if;
end $$;

\echo '>> app.create_loyalty_program_rule_version / app.update_loyalty_program_rule_version_draft: LYL:Create/Edit required; only one draft per program at a time; final draft rate=0.1, reward=points, min_invoice_amount=50'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_version app.loyalty_program_rule_versions;
begin
  v_version := app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 0.2, '{}'::jsonb, v_manager1, 'manager1');
  if v_version.status <> 'draft' or v_version.version_number <> 1 then
    raise exception 'assertion failed: expected draft v1, got %', v_version;
  end if;

  begin
    perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 0.3, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected draft_already_exists for a second draft on the same program';
  exception when others then if sqlerrm not like 'draft_already_exists%' then raise; end if;
  end;

  begin
    perform app.update_loyalty_program_rule_version_draft(v_tenant1, v_version.id, v_version.record_version, 'per_paid_invoice_amount', 'points', 0.15, '{}'::jsonb, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.update_loyalty_program_rule_version_draft(v_tenant1, v_version.id, v_version.record_version, 'per_paid_invoice_amount', 'points', -1, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_rate for a non-positive rate';
  exception when others then if sqlerrm not like 'invalid_rate%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency.
  begin
    perform app.update_loyalty_program_rule_version_draft(v_tenant1, v_version.id, null, 'per_paid_invoice_amount', 'points', 0.5, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select rate from app.loyalty_program_rule_versions where id = v_version.id) <> 0.2
     or (select record_version from app.loyalty_program_rule_versions where id = v_version.id) <> v_version.record_version then
    raise exception 'assertion failed: a NULL expected_version must never actually change the row -- rate=%, record_version=%',
      (select rate from app.loyalty_program_rule_versions where id = v_version.id), (select record_version from app.loyalty_program_rule_versions where id = v_version.id);
  end if;

  -- Edit it down to the values the earning sections below actually exercise:
  -- rate=0.1, min_invoice_amount=50.
  v_version := app.update_loyalty_program_rule_version_draft(v_tenant1, v_version.id, v_version.record_version, 'per_paid_invoice_amount', 'points', 0.1, jsonb_build_object('min_invoice_amount', 50), v_manager1, 'manager1');
  if v_version.rate <> 0.1 or v_version.record_version <> 2 or (v_version.eligibility_config ->> 'min_invoice_amount')::numeric <> 50 then
    raise exception 'assertion failed: expected the draft edited in place (record_version bumped to 2, rate=0.1, min=50), got %', v_version;
  end if;
end $$;

\echo '>> app.publish_loyalty_program_rule_version: LYL:Configure required (Viewer with only LYL:View denied); only a draft may be published; a published version can never be published/edited again'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000336002';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_draft app.loyalty_program_rule_versions;
  v_published_v1 app.loyalty_program_rule_versions;
begin
  select * into v_draft from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'draft';

  begin
    perform app.publish_loyalty_program_rule_version(v_tenant1, v_draft.id, v_draft.record_version, null, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not satisfy LYL:Configure';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency.
  begin
    perform app.publish_loyalty_program_rule_version(v_tenant1, v_draft.id, null, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_program_rule_versions where id = v_draft.id) <> 'draft' then
    raise exception 'assertion failed: a NULL expected_version must never actually publish the draft -- status=%', (select status from app.loyalty_program_rule_versions where id = v_draft.id);
  end if;

  v_published_v1 := app.publish_loyalty_program_rule_version(v_tenant1, v_draft.id, v_draft.record_version, '2026-08-10T00:00:00Z', v_manager1, 'manager1');
  if v_published_v1.status <> 'published' or v_published_v1.published_by <> 'manager1' or v_published_v1.effective_from is null or v_published_v1.rate <> 0.1 then
    raise exception 'assertion failed: expected v1 published (rate=0.1) with published_by/effective_from set, got %', v_published_v1;
  end if;

  begin
    perform app.publish_loyalty_program_rule_version(v_tenant1, v_published_v1.id, v_published_v1.record_version, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition -- an already-published version may not be published again';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  begin
    perform app.update_loyalty_program_rule_version_draft(v_tenant1, v_published_v1.id, v_published_v1.record_version, 'per_paid_invoice_amount', 'points', 0.99, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition -- a published version may NEVER be edited in place';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.enroll_customer_loyalty_account: LYL:Create required; only an active program accepts enrollment; idempotent re-enroll into the SAME program; at most one ACTIVE enrollment per customer account at a time (design decision 1) -- rejects a second active enrollment in a DIFFERENT program'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Beta');
  v_freight_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_second_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Second Program');
  v_loyalty_account app.loyalty_accounts;
  v_repeat app.loyalty_accounts;
begin
  begin
    perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_freight_id, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_loyalty_account := app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_freight_id, v_manager1, 'manager1');
  if v_loyalty_account.status <> 'active' or v_loyalty_account.customer_account_id <> v_account_alpha then
    raise exception 'assertion failed: expected Alpha enrolled active in Freight Rewards, got %', v_loyalty_account;
  end if;

  -- Idempotent: a repeat enroll into the SAME program returns the SAME row.
  v_repeat := app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_freight_id, v_manager1, 'manager1');
  if v_repeat.id <> v_loyalty_account.id then
    raise exception 'assertion failed: expected the identical row on re-enroll, got a different id %', v_repeat.id;
  end if;

  -- A DRAFT program cannot accept enrollment at all.
  perform app.update_loyalty_program_status(v_tenant1, v_second_id, (select record_version from app.loyalty_programs where id = v_second_id), 'inactive', v_manager1, 'manager1');
  begin
    perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_second_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected loyalty_program_not_active for an inactive program';
  exception when others then if sqlerrm not like 'loyalty_program_not_active%' then raise; end if;
  end;
  perform app.update_loyalty_program_status(v_tenant1, v_second_id, (select record_version from app.loyalty_programs where id = v_second_id), 'active', v_manager1, 'manager1');

  -- Alpha already holds an ACTIVE enrollment (Freight Rewards) -- enrolling
  -- Alpha into a DIFFERENT active program must be rejected (design decision
  -- 1's own single-active-enrollment constraint).
  begin
    perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_second_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected customer_already_has_active_enrollment for Alpha''s second active enrollment attempt';
  exception when others then if sqlerrm not like 'customer_already_has_active_enrollment%' then raise; end if;
  end;

  -- Beta, who holds NO enrollment yet, CAN enroll into Second Program.
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_second_id, v_manager1, 'manager1');
end $$;

\echo '>> app.set_loyalty_account_status (Delta''s own sandbox in Third Program, never touching Alpha/Beta''s own rows): LYL:Edit required; reason required for suspend/close; active<->suspended, both ->closed(terminal); reactivation blocked if it would collide with the single-active constraint (the exception-handler-backed guard, not merely the enroll-side pre-check)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_account_delta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Delta');
  v_third_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Third Program');
  v_freight_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_third_account app.loyalty_accounts;
  v_updated app.loyalty_accounts;
begin
  v_third_account := app.enroll_customer_loyalty_account(v_tenant1, v_account_delta, v_third_id, v_manager1, 'manager1');

  begin
    perform app.set_loyalty_account_status(v_tenant1, v_third_account.id, v_third_account.record_version, 'suspended', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for a suspend with no reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Tier C review fix regression: a NULL p_expected_version must NOT
  -- silently bypass optimistic concurrency.
  begin
    perform app.set_loyalty_account_status(v_tenant1, v_third_account.id, null, 'suspended', 'should never apply', v_manager1, 'manager1');
    raise exception 'assertion failed: expected stale_version for a NULL expected_version, got a silent success';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select status from app.loyalty_accounts where id = v_third_account.id) <> 'active' then
    raise exception 'assertion failed: a NULL expected_version must never actually change the row -- status=%', (select status from app.loyalty_accounts where id = v_third_account.id);
  end if;

  v_updated := app.set_loyalty_account_status(v_tenant1, v_third_account.id, v_third_account.record_version, 'suspended', 'fraud review', v_manager1, 'manager1');
  if v_updated.status <> 'suspended' then
    raise exception 'assertion failed: expected status=suspended, got %', v_updated;
  end if;

  -- Delta now holds ZERO active rows (Third Program is suspended) -- Delta
  -- may freely enroll into Freight Rewards.
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_delta, v_freight_id, v_manager1, 'manager1');

  -- Reactivating Third Program now WOULD give Delta two simultaneously
  -- active rows -- the reactivation-collision guard (a real exception-
  -- handler-backed check inside app.set_loyalty_account_status itself, not
  -- merely enroll's own pre-check) must reject it.
  begin
    perform app.set_loyalty_account_status(v_tenant1, v_updated.id, v_updated.record_version, 'active', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected customer_already_has_active_enrollment -- reactivating Third Program would collide with Delta''s own active Freight Rewards row';
  exception when others then if sqlerrm not like 'customer_already_has_active_enrollment%' then raise; end if;
  end;

  v_updated := app.set_loyalty_account_status(v_tenant1, v_updated.id, v_updated.record_version, 'closed', 'customer consolidated into Freight Rewards', v_manager1, 'manager1');
  if v_updated.status <> 'closed' or v_updated.closed_by <> 'manager1' or v_updated.closed_at is null then
    raise exception 'assertion failed: expected status=closed with closed_by/closed_at set, got %', v_updated;
  end if;

  begin
    perform app.set_loyalty_account_status(v_tenant1, v_updated.id, v_updated.record_version, 'active', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_transition -- closed is terminal';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> (a) IDEMPOTENT EARNING: app.evaluate_customer_loyalty_earning_for_paid_invoice called twice for the SAME paid invoice produces exactly ONE event, second call is a safe no-op'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_event1 app.loyalty_earning_events;
  v_event1_repeat app.loyalty_earning_events;
  v_count integer;
begin
  v_event1 := app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336101', v_manager1, 'manager1');
  if v_event1.amount <> 100 or v_event1.reward_type <> 'points' or v_event1.source_type <> 'finance_invoice_paid' then
    raise exception 'assertion failed: expected 1000 * 0.1 = 100 points, got %', v_event1;
  end if;

  v_event1_repeat := app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336101', v_manager1, 'manager1');
  if v_event1_repeat.id <> v_event1.id then
    raise exception 'assertion failed: expected the IDENTICAL event on retry, got a different id %', v_event1_repeat.id;
  end if;

  select count(*) into v_count from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE row for this idempotency key, got %', v_count;
  end if;
end $$;

\echo '>> (b) INELIGIBLE INVOICES: unpaid, held, and below-eligibility-minimum are each rejected with a distinct, real error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
begin
  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336102', v_manager1, 'manager1');
    raise exception 'assertion failed: expected ar_open_item_not_paid for an open (unpaid) item';
  exception when others then if sqlerrm not like 'ar_open_item_not_paid%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336103', v_manager1, 'manager1');
    raise exception 'assertion failed: expected ar_open_item_held for a paid-but-held item';
  exception when others then if sqlerrm not like 'ar_open_item_held%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336104', v_manager1, 'manager1');
    raise exception 'assertion failed: expected ineligible_amount_below_minimum for amount=20 < min=50';
  exception when others then if sqlerrm not like 'ineligible_amount_below_minimum%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336107', v_manager1, 'manager1');
    raise exception 'assertion failed: expected loyalty_account_not_active -- Echo is never enrolled anywhere';
  exception when others then if sqlerrm not like 'loyalty_account_not_active%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336106', v_manager1, 'manager1');
    raise exception 'assertion failed: expected no_published_rule_version -- Second Program never had a rule version published';
  exception when others then if sqlerrm not like 'no_published_rule_version%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, gen_random_uuid(), v_manager1, 'manager1');
    raise exception 'assertion failed: expected ar_open_item_not_found for a genuinely nonexistent id';
  exception when others then if sqlerrm not like 'ar_open_item_not_found%' then raise; end if;
  end;
end $$;

\echo '>> (c) RULE-VERSION CHANGE DOES NOT RETROACTIVELY ALTER: publishing v2 (rate=0.2, supersedes v1) leaves event1''s own amount/rule_version_id COMPLETELY unchanged; a NEW paid invoice evaluated afterward correctly uses v2''s own rate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_published_v1_id uuid := (select id from app.loyalty_program_rule_versions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards') and status = 'published');
  v_event1_before app.loyalty_earning_events;
  v_event1_after app.loyalty_earning_events;
  v_draft2 app.loyalty_program_rule_versions;
  v_published_v2 app.loyalty_program_rule_versions;
  v_reloaded_v1 app.loyalty_program_rule_versions;
  v_published_count integer;
  v_event2 app.loyalty_earning_events;
begin
  select * into v_event1_before from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101';

  v_draft2 := app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 0.2, '{}'::jsonb, v_manager1, 'manager1');
  v_published_v2 := app.publish_loyalty_program_rule_version(v_tenant1, v_draft2.id, v_draft2.record_version, '2026-08-15T00:00:00Z', v_manager1, 'manager1');
  if v_published_v2.status <> 'published' or v_published_v2.rate <> 0.2 then
    raise exception 'assertion failed: expected v2 published with rate=0.2, got %', v_published_v2;
  end if;

  select * into v_reloaded_v1 from app.loyalty_program_rule_versions where id = v_published_v1_id;
  if v_reloaded_v1.status <> 'superseded' or v_reloaded_v1.effective_to is null or v_reloaded_v1.rate <> 0.1 then
    raise exception 'assertion failed: expected v1 superseded (rate STILL 0.1, effective_to set), got %', v_reloaded_v1;
  end if;

  select count(*) into v_published_count from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'published';
  if v_published_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE published version per program at a time, got %', v_published_count;
  end if;

  -- Tier C review fix regression: app.publish_loyalty_program_rule_version
  -- just touched BOTH v1 (superseded) and v2 (published) in this SAME
  -- transaction -- with the pre-fix `now()` default/assignment, both would
  -- have received a byte-identical updated_at, making app.list_loyalty_
  -- program_rule_versions' own `order by updated_at desc, id desc` tie-
  -- break on a random uuid instead of true recency. clock_timestamp()
  -- advances on every call regardless of transaction boundaries, so the two
  -- rows must have genuinely distinct timestamps, with the just-published
  -- v2 ordered strictly first.
  if v_reloaded_v1.updated_at = v_published_v2.updated_at then
    raise exception 'assertion failed: expected v1 (superseded) and v2 (published), touched in the SAME transaction, to have DISTINCT updated_at values (clock_timestamp(), not now()) -- got identical %', v_reloaded_v1.updated_at;
  end if;
  declare
    v_listed app.loyalty_program_rule_versions[];
  begin
    v_listed := array(select app.list_loyalty_program_rule_versions(v_tenant1, v_program_id, v_manager1, null, null, null, 10));
    if v_listed[1].id <> v_published_v2.id then
      raise exception 'assertion failed: expected the just-published v2 to sort strictly first (order by updated_at desc, id desc), got %', v_listed[1];
    end if;
  end;

  -- The core business-rule proof: event1's own row, re-read fresh, is
  -- byte-for-byte identical to before v2 was ever published.
  select * into v_event1_after from app.loyalty_earning_events where id = v_event1_before.id;
  if v_event1_after.amount <> v_event1_before.amount or v_event1_after.rule_version_id <> v_event1_before.rule_version_id or v_event1_after.rule_version_id <> v_published_v1_id then
    raise exception 'assertion failed: expected event1 COMPLETELY unchanged (amount=100, rule_version_id=v1), got % (was %)', v_event1_after, v_event1_before;
  end if;

  -- A NEW paid invoice, evaluated NOW, correctly uses v2's own rate (0.2),
  -- never v1's (already-superseded) rate.
  v_event2 := app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336105', v_manager1, 'manager1');
  if v_event2.amount <> 400 or v_event2.rule_version_id <> v_published_v2.id then
    raise exception 'assertion failed: expected 2000 * 0.2 = 400 points under v2, got %', v_event2;
  end if;
end $$;

\echo '>> (e) REVERSAL: app.reverse_loyalty_earning_event creates a NEW linked event, NEVER deletes/edits the original; idempotent; already-reversed and reverse-of-a-reversal are both rejected; LYL:Configure required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000336002';
  v_event1 app.loyalty_earning_events;
  v_event1_before_reversal app.loyalty_earning_events;
  v_reversal app.loyalty_earning_events;
  v_reversal_repeat app.loyalty_earning_events;
  v_event1_after app.loyalty_earning_events;
  v_count integer;
begin
  select * into v_event1 from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101';
  v_event1_before_reversal := v_event1;

  begin
    perform app.reverse_loyalty_earning_event(v_tenant1, v_event1.id, 'duplicate award', 'reversal:test1', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not satisfy LYL:Configure';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.reverse_loyalty_earning_event(v_tenant1, v_event1.id, '', 'reversal:test2', v_manager1, 'manager1');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_reversal := app.reverse_loyalty_earning_event(v_tenant1, v_event1.id, 'duplicate award detected', 'reversal:event1', v_manager1, 'manager1');
  if v_reversal.corrects_event_id <> v_event1.id or v_reversal.amount <> -v_event1.amount or v_reversal.source_type <> 'reversal' or v_reversal.source_id <> v_event1.id then
    raise exception 'assertion failed: expected a new linked reversal row (amount=-100, corrects_event_id=event1), got %', v_reversal;
  end if;

  -- The ORIGINAL row is untouched -- same id, same amount, same
  -- rule_version_id, still corrects_event_id IS NULL.
  select * into v_event1_after from app.loyalty_earning_events where id = v_event1.id;
  if v_event1_after.amount <> v_event1_before_reversal.amount or v_event1_after.corrects_event_id is not null or v_event1_after.rule_version_id <> v_event1_before_reversal.rule_version_id then
    raise exception 'assertion failed: expected the ORIGINAL event1 row completely unchanged after reversal, got %', v_event1_after;
  end if;

  select count(*) into v_count from app.loyalty_earning_events where id = v_event1.id or corrects_event_id = v_event1.id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly TWO rows now for this earning story (original + reversal, never a delete/replace), got %', v_count;
  end if;

  -- Idempotent: the SAME idempotency key returns the SAME reversal row.
  v_reversal_repeat := app.reverse_loyalty_earning_event(v_tenant1, v_event1.id, 'duplicate award detected', 'reversal:event1', v_manager1, 'manager1');
  if v_reversal_repeat.id <> v_reversal.id then
    raise exception 'assertion failed: expected the IDENTICAL reversal row on retry, got a different id %', v_reversal_repeat.id;
  end if;

  -- A DIFFERENT idempotency key against the SAME already-reversed event is rejected.
  begin
    perform app.reverse_loyalty_earning_event(v_tenant1, v_event1.id, 'attempt again', 'reversal:event1-again', v_manager1, 'manager1');
    raise exception 'assertion failed: expected already_reversed';
  exception when others then if sqlerrm not like 'already_reversed%' then raise; end if;
  end;

  -- A reversal event may not itself be reversed.
  begin
    perform app.reverse_loyalty_earning_event(v_tenant1, v_reversal.id, 'reverse the reversal', 'reversal:of-reversal', v_manager1, 'manager1');
    raise exception 'assertion failed: expected invalid_reversal -- a reversal event may not itself be reversed';
  exception when others then if sqlerrm not like 'invalid_reversal%' then raise; end if;
  end;
end $$;

\echo '>> staff reads: app.get_loyalty_program/get_loyalty_program_rule_version/get_loyalty_account/get_loyalty_earning_event all LYL:View-gated (Viewer succeeds, Plain User denied); app.list_loyalty_earning_events keyset pagination visits every row exactly once at p_limit=1; half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_viewer1 uuid := '00000000-0000-0000-0000-000000336002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000336003';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_event1_id uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101');
  v_loyalty_account_id uuid := (select loyalty_account_id from app.loyalty_earning_events where id = (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101'));
  v_program app.loyalty_programs;
  v_event app.loyalty_earning_events;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_created_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
  v_expected_total integer;
begin
  v_program := app.get_loyalty_program(v_tenant1, v_program_id, v_viewer1);
  if v_program.id <> v_program_id then
    raise exception 'assertion failed: Viewer (LYL:View) should be able to read the program';
  end if;

  begin
    perform app.get_loyalty_program(v_tenant1, v_program_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User on get_loyalty_program';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_event := app.get_loyalty_earning_event(v_tenant1, v_event1_id, v_viewer1);
  if v_event.id <> v_event1_id then
    raise exception 'assertion failed: Viewer should be able to read the earning event';
  end if;

  begin
    perform app.get_loyalty_earning_event(v_tenant1, gen_random_uuid(), v_viewer1);
    raise exception 'assertion failed: expected loyalty_earning_event_not_found for a genuinely nonexistent id';
  exception when others then if sqlerrm not like 'loyalty_earning_event_not_found%' then raise; end if;
  end;

  select count(*) into v_expected_total from app.loyalty_earning_events where loyalty_account_id = v_loyalty_account_id;
  if v_expected_total < 2 then
    raise exception 'assertion failed: fixture setup error, expected at least 2 events for this loyalty_account, got %', v_expected_total;
  end if;

  loop
    v_page_count := 0;
    for v_row in select * from app.list_loyalty_earning_events(v_tenant1, v_viewer1, p_loyalty_account_id => v_loyalty_account_id, p_cursor_created_at => v_cursor_created_at, p_cursor_id => v_cursor_id, p_limit => 1) loop
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
    perform app.list_loyalty_earning_events(v_tenant1, v_viewer1, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_created_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> (d) CROSS-TENANT ISOLATION (staff surface): tenant loy2''s own Loyalty Manager cannot read/act on tenant loy1''s program/rule-version/account/event, whether by passing loy1''s own tenant_id (denied by authority -- no role assignment there) or by guessing a loy1 id inside loy2''s own tenant_id (denied by not_found, tenant-scoped fetch)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'loy2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000337001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_event1_id uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101');
begin
  begin
    perform app.get_loyalty_program(v_tenant1, v_program_id, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority -- manager2 holds no role assignment in tenant1 at all';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_program(v_tenant2, v_program_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_program_not_found -- a loy1 program id does not exist inside tenant2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_program_not_found%' then raise; end if;
  end;

  begin
    perform app.get_loyalty_earning_event(v_tenant2, v_event1_id, v_manager2);
    raise exception 'assertion failed: expected loyalty_earning_event_not_found -- a loy1 event id does not exist inside tenant2''s own scope';
  exception when others then if sqlerrm not like 'loyalty_earning_event_not_found%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant2, '00000000-0000-0000-0000-000000336101', v_manager2, 'manager2');
    raise exception 'assertion failed: expected ar_open_item_not_found -- a loy1 AR open item does not exist inside tenant2''s own scope';
  exception when others then if sqlerrm not like 'ar_open_item_not_found%' then raise; end if;
  end;

  begin
    perform app.reverse_loyalty_earning_event(v_tenant2, v_event1_id, 'cross tenant attempt', 'reversal:cross-tenant', v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_earning_event_not_found for a cross-tenant reversal attempt';
  exception when others then if sqlerrm not like 'loyalty_earning_event_not_found%' then raise; end if;
  end;
end $$;

\echo '>> Gamma (tenant loy2) enrolls in her own tenant''s own program and earns, entirely independent of tenant loy1'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'loy2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000337001';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy2') and legal_name = 'Loy Account Gamma');
  v_program app.loyalty_programs;
  v_draft app.loyalty_program_rule_versions;
  v_published app.loyalty_program_rule_versions;
  v_event app.loyalty_earning_events;
begin
  v_program := app.create_loyalty_program(v_tenant2, 'Gamma Rewards', null, v_manager2, 'manager2');
  perform app.update_loyalty_program_status(v_tenant2, v_program.id, 1, 'active', v_manager2, 'manager2');
  v_draft := app.create_loyalty_program_rule_version(v_tenant2, v_program.id, 'per_paid_invoice_amount', 'cashback', 0.05, '{}'::jsonb, v_manager2, 'manager2');
  v_published := app.publish_loyalty_program_rule_version(v_tenant2, v_draft.id, v_draft.record_version, null, v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_gamma, v_program.id, v_manager2, 'manager2');

  v_event := app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant2, '00000000-0000-0000-0000-000000337101', v_manager2, 'manager2');
  if v_event.reward_type <> 'cashback' or v_event.amount <> 40.00 then
    raise exception 'assertion failed: expected 800 * 0.05 = 40.00 cashback, got %', v_event;
  end if;
end $$;

\echo '>> customer-facing reads: app.list_customer_portal_loyalty_accounts / app.list_customer_portal_loyalty_earning_events -- Alpha sees her own Freight Rewards enrollment and earning history (event1, its reversal, event2) with correct program_name/earning_basis/rate; NEVER Beta''s own rows; deny-by-default for cross-tenant/no-scope; customer-safe projection never carries internal linkage fields'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000336010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000336020';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Beta');
  v_row record;
  v_row_json jsonb;
  v_count integer;
  v_internal_only_fields text[] := array['loyalty_account_id', 'program_id', 'rule_version_id', 'source_id', 'customer_account_id', 'tenant_id'];
begin
  select count(*) into v_count from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_alpha);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 loyalty enrollment (Freight Rewards) for Alpha, got %', v_count;
  end if;

  select * into v_row from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_alpha);
  if v_row.program_name <> 'Freight Rewards' or v_row.customer_account_id <> v_account_alpha or v_row.status <> 'active' then
    raise exception 'assertion failed: expected Alpha''s own active Freight Rewards enrollment, got %', v_row;
  end if;

  select count(*) into v_count from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_limit => 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 earning events for Alpha (event1, its reversal, event2), got %', v_count;
  end if;

  select * into v_row from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_limit => 200) where corrects_event_id is null and amount = 100;
  if v_row.program_name <> 'Freight Rewards' or v_row.earning_basis <> 'per_paid_invoice_amount' or v_row.rate <> 0.1 then
    raise exception 'assertion failed: expected event1''s own customer-safe row to cite earning_basis=per_paid_invoice_amount, rate=0.1 (v1''s own, never v2''s), got %', v_row;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ?| v_internal_only_fields then
    raise exception 'assertion failed: app.list_customer_portal_loyalty_earning_events leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;

  select * into v_row from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_limit => 200) where corrects_event_id is not null;
  if v_row.amount <> -100 or v_row.reason is null then
    raise exception 'assertion failed: expected the reversal row visible to Alpha with amount=-100 and a real reason, got %', v_row;
  end if;

  -- Cross-account: Beta sees ONLY her own (her Second Program enrollment,
  -- from the earlier enrollment test section -- never Alpha's Freight
  -- Rewards row, and zero earning events since Beta was never evaluated).
  select count(*) into v_count from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_beta);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 loyalty account visible to Beta (her own Second Program enrollment, never Alpha''s), got %', v_count;
  end if;
  select * into v_row from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_beta);
  if v_row.program_name <> 'Second Program' or v_row.customer_account_id <> v_account_beta then
    raise exception 'assertion failed: expected Beta''s own Second Program row, got %', v_row;
  end if;
  select count(*) into v_count from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_beta, p_limit => 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero earning events visible to Beta (never Alpha''s), got %', v_count;
  end if;

  -- Filtering explicitly by an out-of-scope customer_account_id (Beta's own
  -- id, requested by Alpha's own session) is deny-by-default empty, never a
  -- leak and never an error.
  select count(*) into v_count from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_alpha, p_customer_account_id => v_account_beta);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows -- Alpha''s own session may not read Beta''s account by explicit filter, got %', v_count;
  end if;
end $$;

\echo '>> customer-facing reads: cross-tenant isolation and keyset pagination'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'loy2');
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000337010';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000336010';
  v_count integer;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_created_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  -- Gamma probing tenant1 with her own real, active identity resolves to an
  -- EMPTY scope (she holds no relationship to tenant1 at all) -- never an
  -- error, never tenant1 data.
  select count(*) into v_count from app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_gamma);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant identity probing tenant1, got %', v_count;
  end if;

  -- Gamma, in her OWN tenant, sees her own real enrollment.
  select count(*) into v_count from app.list_customer_portal_loyalty_accounts(v_tenant2, v_customer_gamma);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 loyalty enrollment for Gamma in her own tenant, got %', v_count;
  end if;

  -- Keyset pagination over Alpha's own 3 earning events at p_limit=1.
  loop
    v_page_count := 0;
    for v_row in select * from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_cursor_created_at => v_cursor_created_at, p_cursor_id => v_cursor_id, p_limit => 1) loop
      v_page_count := v_page_count + 1;
      if v_row.id = any (v_seen_ids) then
        raise exception 'assertion failed: cursor pagination returned a duplicate row %', v_row.id;
      end if;
      v_seen_ids := v_seen_ids || v_row.id;
      v_cursor_created_at := v_row.created_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_page_count = 0;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 10 then
      raise exception 'assertion failed: cursor pagination did not terminate within 10 pages';
    end if;
  end loop;
  if v_total_pages <> 3 or array_length(v_seen_ids, 1) <> 3 then
    raise exception 'assertion failed: expected exactly 3 pages of 1 row each, got % pages / % rows', v_total_pages, array_length(v_seen_ids, 1);
  end if;

  begin
    perform app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_created_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS/grant defense-in-depth: app.loyalty_programs/app.loyalty_program_rule_versions/app.loyalty_accounts/app.loyalty_earning_events all deny a raw authenticated SELECT outright with a real permission-denied error -- authenticated holds ZERO direct grant on any of the 4 new tables (not merely RLS-filtered to zero rows)'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000336010", "role": "authenticated"}';

  begin
    select count(*) into v_count from app.loyalty_programs;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_programs to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_program_rule_versions;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_program_rule_versions to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_accounts;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_accounts to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_earning_events;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_earning_events to be denied with permission_denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;

  reset role;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on any of the 19 new public functions; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.create_loyalty_program(uuid, text, text, uuid, text)',
    'app.update_loyalty_program_status(uuid, uuid, integer, text, uuid, text)',
    'app.get_loyalty_program(uuid, uuid, uuid)',
    'app.list_loyalty_programs(uuid, uuid, text, timestamptz, uuid, integer)',
    'app.create_loyalty_program_rule_version(uuid, uuid, text, text, numeric, jsonb, uuid, text)',
    'app.update_loyalty_program_rule_version_draft(uuid, uuid, integer, text, text, numeric, jsonb, uuid, text)',
    'app.publish_loyalty_program_rule_version(uuid, uuid, integer, timestamptz, uuid, text)',
    'app.get_loyalty_program_rule_version(uuid, uuid, uuid)',
    'app.list_loyalty_program_rule_versions(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.enroll_customer_loyalty_account(uuid, uuid, uuid, uuid, text)',
    'app.set_loyalty_account_status(uuid, uuid, integer, text, text, uuid, text)',
    'app.get_loyalty_account(uuid, uuid, uuid)',
    'app.list_loyalty_accounts(uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.evaluate_customer_loyalty_earning_for_paid_invoice(uuid, uuid, uuid, text)',
    'app.reverse_loyalty_earning_event(uuid, uuid, text, text, uuid, text)',
    'app.get_loyalty_earning_event(uuid, uuid, uuid)',
    'app.list_loyalty_earning_events(uuid, uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_accounts(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_earning_events(uuid, uuid, uuid, timestamptz, uuid, integer)'
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

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every one of the 19 new RPCs (ATW-031/032 discipline, applied from the first draft)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000336010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000336050';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards');
  v_rule_version_id uuid := (select id from app.loyalty_program_rule_versions where program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards') and status = 'published');
  v_loyalty_account_id uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and program_id = (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'loy1') and name = 'Freight Rewards') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Alpha'));
  v_event_id uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000336101');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'loy1') and legal_name = 'Loy Account Alpha');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000336050", "role": "authenticated"}';

  begin
    perform app.create_loyalty_program(v_tenant1, 'Impersonated Program', null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.create_loyalty_program';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.update_loyalty_program_status(v_tenant1, v_program_id, 4, 'inactive', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.update_loyalty_program_status';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_program(v_tenant1, v_program_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_program';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_programs(v_tenant1, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_programs';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 0.1, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.create_loyalty_program_rule_version';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.update_loyalty_program_rule_version_draft(v_tenant1, v_rule_version_id, 1, 'per_paid_invoice_amount', 'points', 0.1, '{}'::jsonb, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.update_loyalty_program_rule_version_draft';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.publish_loyalty_program_rule_version(v_tenant1, v_rule_version_id, 1, null, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.publish_loyalty_program_rule_version';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_program_rule_version(v_tenant1, v_rule_version_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_program_rule_version';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_program_rule_versions(v_tenant1, v_program_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_program_rule_versions';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.enroll_customer_loyalty_account';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.set_loyalty_account_status(v_tenant1, v_loyalty_account_id, 1, 'suspended', 'x', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.set_loyalty_account_status';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_account(v_tenant1, v_loyalty_account_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_account';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_accounts(v_tenant1, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_accounts';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000336101', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.evaluate_customer_loyalty_earning_for_paid_invoice';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.reverse_loyalty_earning_event(v_tenant1, v_event_id, 'x', 'reversal:imp', v_manager1, 'manager1');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.reverse_loyalty_earning_event';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_earning_event(v_tenant1, v_event_id, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_earning_event';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_earning_events(v_tenant1, v_manager1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_earning_events';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_accounts(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_accounts';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_earning_events';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (impersonator holds the
  -- Loyalty Manager role too) is NOT rejected by the identity check -- it
  -- succeeds on its own authority, proving the identity check and the
  -- authority check are two independent gates.
  perform app.get_loyalty_program(v_tenant1, v_program_id, v_impersonator);

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: Alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000336010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_limit => 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000336010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_loyalty_earning_events(v_tenant1, v_customer_alpha, p_limit => 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

\echo '>> ISS-2026-126: the earning-evaluation SWEEP -- finds every paid, unheld, not-yet-evaluated invoice and evaluates it; one ineligible record is a counted skip, never an aborted run; idempotent per run label'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'loy2');
  v_manager1 uuid := '00000000-0000-0000-0000-000000336001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000336002';
  v_manager2 uuid := '00000000-0000-0000-0000-000000337001';
  v_candidates integer;
  v_row record;
  v_repeat record;
  v_remaining integer;
  v_t2_events_before integer;
  v_t2_events_after integer;
begin
  -- What the sweep should find: every paid, unheld invoice with no earning event yet. Counted
  -- from the same predicate the sweep uses, BEFORE running it, so the assertion below is
  -- against a number derived independently of the sweep's own report.
  select count(*) into v_candidates
  from app.finance_ar_open_items ar
  where ar.tenant_id = v_tenant1 and ar.status = 'paid' and not ar.is_held
    and not exists (select 1 from app.loyalty_earning_events e where e.tenant_id = v_tenant1 and e.idempotency_key = 'ar-open-item:' || ar.id::text);
  if v_candidates = 0 then
    raise exception 'assertion failed: this fixture must leave at least one unevaluated paid invoice for the sweep to find';
  end if;

  select count(*) into v_t2_events_before from app.loyalty_earning_events where tenant_id = v_tenant2;

  select * into v_row from app.run_loyalty_earning_evaluation_sweep(v_tenant1, now(), v_manager1, 'manager1', 'iss126-run-a');

  -- Every candidate is accounted for: processed or skipped, never silently dropped, and the
  -- run completed rather than aborting on the first ineligible record.
  if v_row.processed_count + v_row.skipped_count <> v_candidates then
    raise exception 'assertion failed: sweep must account for every candidate -- % processed + % skipped <> % candidates', v_row.processed_count, v_row.skipped_count, v_candidates;
  end if;
  if v_row.status <> 'completed' then
    raise exception 'assertion failed: expected a completed sweep job, got %', v_row.status;
  end if;
  if v_row.processed_count = 0 then
    raise exception 'assertion failed: at least one genuinely eligible invoice must have been evaluated by the sweep';
  end if;

  -- Nothing eligible is left behind: a second look finds only records the sweep already
  -- attempted, so the candidate set is genuinely drained of everything that could succeed.
  select count(*) into v_remaining
  from app.finance_ar_open_items ar
  where ar.tenant_id = v_tenant1 and ar.status = 'paid' and not ar.is_held
    and not exists (select 1 from app.loyalty_earning_events e where e.tenant_id = v_tenant1 and e.idempotency_key = 'ar-open-item:' || ar.id::text);
  if v_remaining <> v_row.skipped_count then
    raise exception 'assertion failed: what remains unevaluated (%) must be exactly what the sweep skipped (%)', v_remaining, v_row.skipped_count;
  end if;

  -- Tenant isolation: a tenant1 sweep never touches tenant2's own loyalty data.
  select count(*) into v_t2_events_after from app.loyalty_earning_events where tenant_id = v_tenant2;
  if v_t2_events_after <> v_t2_events_before then
    raise exception 'assertion failed: a tenant1 sweep created % tenant2 earning events', v_t2_events_after - v_t2_events_before;
  end if;

  -- Idempotent per (tenant, run_label): the same label is the same run, reporting the
  -- ORIGINAL run's own counts rather than re-doing the work.
  select * into v_repeat from app.run_loyalty_earning_evaluation_sweep(v_tenant1, now(), v_manager1, 'manager1', 'iss126-run-a');
  if v_repeat.job_id <> v_row.job_id or v_repeat.processed_count <> v_row.processed_count then
    raise exception 'assertion failed: re-running the same run label must be the same job with the same counts (job % vs %, processed % vs %)', v_repeat.job_id, v_row.job_id, v_repeat.processed_count, v_row.processed_count;
  end if;

  -- The outer gate: LYL:Edit is required to start a run at all, independently of the
  -- per-record gate inside the RPC the sweep calls.
  begin
    perform app.run_loyalty_earning_evaluation_sweep(v_tenant1, now(), v_viewer1, 'viewer1', 'iss126-denied');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not start an earning sweep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Cross-tenant: tenant2's own manager holds LYL:Edit in tenant2, never in tenant1.
  begin
    perform app.run_loyalty_earning_evaluation_sweep(v_tenant1, now(), v_manager2, 'manager2', 'iss126-crosstenant');
    raise exception 'assertion failed: expected insufficient_authority -- a tenant2 manager must not sweep tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'PASS: earning sweep evaluated %, skipped % of % candidates, drained everything eligible, stayed inside its tenant, and is idempotent per run label', v_row.processed_count, v_row.skipped_count, v_candidates;
end $$;

\echo '>> ISS-2026-126: the sweep records WHY it skipped, without leaking a tenant id into the reason -- an operator reading a zero-processed run must be able to tell "nothing was due" from "everything failed"'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'loy1');
  v_payload jsonb;
  v_skips jsonb;
  v_reason text;
begin
  select payload into v_payload from app.jobs
  where tenant_id = v_tenant1 and job_type = 'loyalty_earning_evaluation_sweep' and idempotency_key like '%iss126-run-a'
  order by created_at desc limit 1;

  if v_payload is null then
    raise exception 'assertion failed: the sweep job row must exist and carry its own result payload';
  end if;
  if not (v_payload ? 'processed_count' and v_payload ? 'skipped_count' and v_payload ? 'skips') then
    raise exception 'assertion failed: the job payload must record processed/skipped counts and the skip reasons, got %', v_payload;
  end if;

  v_skips := v_payload -> 'skips';
  if jsonb_array_length(v_skips) > 20 then
    raise exception 'assertion failed: the skip list must be capped at 20 entries, got %', jsonb_array_length(v_skips);
  end if;

  -- ISS-2026-146 class: only the error CODE is recorded, never the full message, which for
  -- several of these RPCs interpolates a tenant id.
  for v_reason in select value ->> 'reason' from jsonb_array_elements(v_skips) loop
    if v_reason like '%' || v_tenant1::text || '%' then
      raise exception 'assertion failed: a skip reason leaked the tenant id: %', v_reason;
    end if;
    if position(':' in v_reason) > 0 then
      raise exception 'assertion failed: a skip reason must be the bare error code, not the interpolated message: %', v_reason;
    end if;
  end loop;

  raise notice 'PASS: the sweep job row carries real counts and % capped, tenant-id-free skip reasons', jsonb_array_length(v_skips);
end $$;

\echo '>> ALL PASSED: CPL-316 Loyalty Program and Earning'
