-- Real, executable test evidence for FIN-202 (Subledger, CG-S9-FIN-013) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: posting-map-driven account resolution (missing map / missing key /
-- unresolved code / inactive / not-postable, each a distinct named
-- exception); a direct accountId reference line resolves and validates the
-- same way; a balanced batch posts idempotently on (tenant, source_type,
-- source_id) and an unbalanced one is rejected before any row is written;
-- period-aware posting; preview never persists; control-account
-- reconciliation is a real, direct comparison against live AR/AP open-item
-- totals, not an asserted-true claim; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail. The four retrofitted
-- callers (app.issue_finance_invoice, app.allocate_finance_receipt,
-- app.post_finance_vendor_bill, app.post_finance_settlement) are proven by
-- their own respective db-test files, each extended this checkpoint with a
-- published finance_posting_map fixture -- not re-proven here.

\set ON_ERROR_STOP on

-- ISS-2026-319 fixture helpers (docs/runtime/KNOWN_ISSUES.md). The new
-- app.validate_finance_open_item_source guard (20260901060000) now rejects a
-- fabricated source_document_id on app.finance_ar_open_items/
-- app.finance_ap_open_items, so this file's own direct
-- app.post_finance_ar_open_item/app.post_finance_ap_open_item calls below can no
-- longer pass gen_random_uuid() and expect it to be accepted. These pg_temp
-- functions mint a genuinely real, minimal row in the actual target table each
-- source_document_type resolves against (app.finance_invoices/
-- app.finance_vendor_bills/app.import_staging_rows) via direct INSERT rather than
-- the full Commercial->Operations RPC pipeline -- the same "direct fixture
-- insert, out of scope for this capability's own test" convention this file
-- already uses for its own minimal app.accounts row below, extended one layer
-- deeper because the new guard now checks one layer deeper. pg_temp is
-- session-scoped, matching scripts/db-tests/run.sh's one-psql-connection-per-file
-- execution model, so these are defined once and reused by every DO block below.

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
-- app.post_finance_ar_open_item(..., 'invoice', <this id>, ...) call below
-- resolves against a genuinely existing invoice instead of a fabricated one.
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

-- Mints one real, minimal (draft, never posted -- so it never posts its own AP
-- open item) app.finance_vendor_bills row and returns its id, so a direct
-- app.post_finance_ap_open_item(..., 'vendor_bill', <this id>, ...) call below
-- resolves against a genuinely existing vendor bill instead of a fabricated one.
create function pg_temp.iss319_mint_vendor_bill(p_tenant_id uuid, p_account_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
returns uuid
language plpgsql
as $fn$
declare
  v_job_order_id uuid;
  v_shipment_id uuid;
  v_cost_id uuid;
  v_bill_id uuid;
begin
  v_job_order_id := pg_temp.iss319_build_job_order(p_tenant_id, p_account_id, p_actor_auth_user_id, p_actor_label, p_seed);

  insert into app.shipment_orders (tenant_id, job_order_id, shipment_number, idempotency_key, shipper_account_id, consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination, created_by)
  values (p_tenant_id, v_job_order_id, p_seed || '-SHIP', p_seed || '-ship-idem', p_account_id, '{}'::jsonb, '{}'::jsonb, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya', p_actor_label)
  returning id into v_shipment_id;

  insert into app.shipment_actual_costs (tenant_id, shipment_order_id, currency, status, created_by)
  values (p_tenant_id, v_shipment_id, 'USD', 'approved', p_actor_label)
  returning id into v_cost_id;

  insert into app.shipment_actual_cost_components (tenant_id, actual_cost_id, category, source_type, vendor_id, description, quantity, rate, amount, currency, created_by)
  values (p_tenant_id, v_cost_id, 'freight', 'vendor', p_vendor_master_id, 'ISS-2026-319 fixture freight component', 1, 100, 100, 'USD', p_actor_label);

  insert into app.finance_vendor_bills (tenant_id, vendor_master_id, shipment_order_id, actual_cost_id, currency, bill_date, due_date, created_by)
  values (p_tenant_id, p_vendor_master_id, v_shipment_id, v_cost_id, 'USD', current_date, current_date + 30, p_actor_label)
  returning id into v_bill_id;

  return v_bill_id;
end;
$fn$;

-- Mints one real app.import_staging_rows row and returns its id -- the correct
-- target for source_document_type = 'opening_balance' on both open-item tables
-- (app.commit_finance_opening_balance_import_job passes the staged row's own id,
-- not the open item's, per 20260901060000's own header).
create function pg_temp.iss319_mint_staging_row(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns uuid
language plpgsql
as $fn$
declare
  v_job_id uuid;
  v_row_id uuid;
begin
  insert into app.jobs (tenant_id, job_type, requested_by_auth_user_id, created_by)
  values (p_tenant_id, 'import', p_actor_auth_user_id, p_actor_label)
  returning job_id into v_job_id;

  insert into app.import_staging_rows (tenant_id, job_id, row_number, raw_payload)
  values (p_tenant_id, v_job_id, 1, '{}'::jsonb)
  returning id into v_row_id;

  return v_row_id;
end;
$fn$;

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager with no posting map ever published; tenant A gets one open fiscal period (2026-03), a small real chart of accounts, and a published finance_posting_map covering every key this checkpoint uses except a deliberately-held-back key, plus one draft (not-yet-active) account and one activated control (non-postable) account for negative-path coverage'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000029701', 'admina@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029702', 'financemanagera@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029703', 'financeeditora@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029704', 'plainusera@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029705', 'financemanagerb@acmesubl.test');

  perform app.provision_tenant('acmesubla', 'Acme Subledger A', 'idem-acmesubla', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMESUBLA-CO', 'Acme Subledger A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMESUBLA-CO');

  perform app.provision_tenant('acmesublb', 'Acme Subledger B', 'idem-acmesublb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmesublb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMESUBLB-CO', 'Acme Subledger B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMESUBLB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029701', 'admina@acmesubl.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmesubl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029701', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029702', 'financemanagera@acmesubl.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmesubl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029702', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029703', 'financeeditora@acmesubl.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmesubl.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Subledger authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029702', '00000000-0000-0000-0000-000000029701', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000029703', '00000000-0000-0000-0000-000000029701', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029704', 'plainusera@acmesubl.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmesubl.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000029705', 'financemanagerb@acmesubl.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmesubl.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Subledger authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000029705', '00000000-0000-0000-0000-000000029705', 'tester');

  -- Six open fiscal periods (Jan-Jun 2026) for tenant A (FIN-193). Tenant B
  -- gets its own open period too (app.post_finance_subledger_batch checks
  -- period eligibility before resolving the posting map, so a missing-map
  -- test against tenant B needs an open period to reach that check) but
  -- deliberately never gets a published finance_posting_map.
  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.generate_finance_fiscal_calendar(v_tenant_b, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029705', 'financemanagerb');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AP-CTRL', 'Accounts Payable Control', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'EXP-DEFAULT', 'Default Expense', 'expense', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-DEFAULT', 'Default Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- A control (non-postable) account, activated -- for the not-postable negative path.
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'GL-CONTROL-NP', 'Non-Postable Control', 'asset', 'debit', null, true, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- A draft (never activated) account -- for the inactive-account negative path.
  perform app.create_finance_account_draft(v_tenant_a, null, 'DRAFT-ONLY', 'Never Activated', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- Published posting map: every key this checkpoint's own retrofits use,
  -- except fee_expense_default and tax_payable_default/input_tax_default --
  -- deliberately held back so app.resolve_finance_posting_map_account's own
  -- finance_subledger_missing_mapping path is exercised against a real
  -- published-but-incomplete map, not merely a wholly absent one.
  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'ap_control', 'value', jsonb_build_object('accountCodeRef', 'AP-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'expense_default', 'value', jsonb_build_object('accountCodeRef', 'EXP-DEFAULT')),
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-DEFAULT'))
  ), '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000029702', null, 'financemanagera');

  -- ISS-2026-206 fixture: a vendor and a pool of REAL app.finance_settlements rows.
  --
  -- This file used to drive app.post_finance_subledger_batch with gen_random_uuid() source
  -- ids on purpose, to exercise the posting primitive's own mechanics in isolation from real
  -- document creation -- a legitimate test design, and the exact reason ISS-2026-206's guard
  -- was deferred rather than forced when it was first drafted. That entry recorded the right
  -- remedy: update the fixture to pass real ids, rather than work around the guard.
  --
  -- Settlements rather than invoices because a real app.finance_invoices row needs the whole
  -- quotation -> handoff -> job order -> billing-readiness chain behind it, while a settlement
  -- needs a tenant and a vendor. Settlement is a first-class source type for a subledger
  -- batch, and none of this file's assertions read the batch's source_type -- they are about
  -- posting-map resolution, balance, period eligibility, idempotency and concurrency. So the
  -- fixture gets strictly more real: it now posts accounting for documents that exist.
  insert into app.master_records (master_type_code, tenant_id, code, name)
  values ('vendor', v_tenant_a, 'ISS206-SUBL-VEND', 'ISS-2026-206 fixture vendor');
  insert into app.finance_settlements (id, tenant_id, vendor_master_id, currency, settlement_date, idempotency_key)
  select coalesce(k.fixed_id, gen_random_uuid()), v_tenant_a,
         (select id from app.master_records where tenant_id = v_tenant_a and code = 'ISS206-SUBL-VEND'),
         'USD', '2026-03-10'::date, k.key
  from (values
    ('iss206-subl-1', null::uuid),
    ('iss206-subl-2', null::uuid),
    ('iss206-subl-3', null::uuid),
    ('iss206-subl-4', null::uuid),
    ('iss206-subl-5', null::uuid),
    -- The two-process concurrency proof further down races a hardcoded source id through psql
    -- \set interpolation, so that one settlement is created with that exact id rather than a
    -- generated one -- the race must hit the SAME (tenant, source_type, source_id) from both
    -- processes, which is the whole point of it.
    ('iss206-subl-race', '00000000-0000-0000-0000-000000029799'::uuid)
  ) as k(key, fixed_id);
end;
$$;

\echo '>> app.post_finance_subledger_batch validation: Plain User A is denied; an unsupported source_type, an empty line set, an invalid direction, a non-positive amount, an unbalanced batch, a period-uncovered date, and a missing posting-map key are each rejected with a distinct named exception; a real balanced batch posts once and a retried call for the same (tenant, source_type, source_id) returns it unchanged'
do $$
declare
  v_tenant_a uuid;
  -- Deliberately still synthetic, and the boundary is exact rather than assumed: reading
  -- app.post_finance_subledger_batch's live definition, the batch row is inserted only AFTER
  -- the source_type, membership, FIN:Edit, empty-batch, period, direction, line-amount and
  -- balance checks, and BEFORE account resolution. Every call using this id is one of the
  -- former, so it never reaches ISS-2026-206's lineage guard -- which is what proves those
  -- checks still fire first rather than being masked by the new one. The account-resolution
  -- negative paths, which DO reach the insert, use a real settlement instead.
  v_source_id uuid := gen_random_uuid();
  v_real_source_id uuid;
  v_batch app.finance_subledger_batches;
  v_retry app.finance_subledger_batches;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  v_real_source_id := (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-1');

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100)),
      '00000000-0000-0000-0000-000000029704', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'not_a_real_source', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_unsupported_source_type';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_unsupported_source_type' then
        raise exception 'assertion failed: expected finance_subledger_unsupported_source_type, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD', '[]'::jsonb, '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_empty_batch';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_empty_batch' then
        raise exception 'assertion failed: expected finance_subledger_empty_batch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'sideways', 'amount', 100)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_invalid_direction';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_invalid_direction' then
        raise exception 'assertion failed: expected finance_subledger_invalid_direction, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 0)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_invalid_line_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_invalid_line_amount' then
        raise exception 'assertion failed: expected finance_subledger_invalid_line_amount, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 90)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_unbalanced_batch';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_unbalanced_batch' then
        raise exception 'assertion failed: expected finance_subledger_unbalanced_batch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2099-01-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 100)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_period_not_found for a date outside every generated period';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_period_not_found' then
        raise exception 'assertion failed: expected finance_subledger_period_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    -- Real source id, unlike the negative paths above: posting-map resolution happens AFTER
    -- the batch row is inserted, so this call reaches ISS-2026-206's lineage guard first if
    -- its source is fabricated. The row it inserts is discarded with the exception.
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'settlement', v_real_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'credit', 'amount', 100)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_missing_mapping for a key never configured in the published map';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_missing_mapping' then
        raise exception 'assertion failed: expected finance_subledger_missing_mapping, got %', sqlerrm;
      end if;
  end;

  -- Uses cash_default rather than ar_control for this real, persisted post
  -- (and the direct-accountId success case below does the same) so neither
  -- pollutes the ar_control/ap_control balances the dedicated reconciliation
  -- scenario group later checks against a clean, exactly-tied state.
  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'settlement', v_real_source_id, '2026-03-10'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'debit', 'amount', 1000),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 1000)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');
  if v_batch.total_amount <> 1000 or v_batch.status <> 'posted' then
    raise exception 'assertion failed: expected a posted batch of total_amount 1000, got total=% status=%', v_batch.total_amount, v_batch.status;
  end if;

  select * into v_retry from app.post_finance_subledger_batch(v_tenant_a, null, 'settlement', v_real_source_id, '2026-03-10'::date, 'USD',
    jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 9999)),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');
  if v_retry.id <> v_batch.id or v_retry.total_amount <> 1000 then
    raise exception 'assertion failed: expected a retried post for the same (tenant, source_type, source_id) to return the original batch unchanged (idempotent), got id=% total=%', v_retry.id, v_retry.total_amount;
  end if;
end;
$$;

\echo '>> direct accountId line resolution: a not-postable control account and a never-activated (draft) account are each rejected; a real active/postable direct account reference posts with a null posting_map_key line'
do $$
declare
  v_tenant_a uuid;
  v_np_account_id uuid;
  v_draft_account_id uuid;
  v_cash_account_id uuid;
  v_batch app.finance_subledger_batches;
  v_lines app.finance_subledger_lines[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  v_np_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'GL-CONTROL-NP');
  v_draft_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'DRAFT-ONLY');
  -- cash_default, not ar_control/ap_control -- keeps this real, persisted
  -- post out of the dedicated reconciliation scenario group's own
  -- exactly-tied AR/AP control-account comparison.
  v_cash_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-DEFAULT');

  begin
    -- Real source id: account resolution runs after the insert, so a fabricated source would
    -- trip ISS-2026-206's guard before this block's own assertion could be reached.
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'settlement',
      (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-5'), '2026-03-11'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_np_account_id, 'direction', 'debit', 'amount', 50),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 50)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_not_postable_mapped_account for a control account referenced directly';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_not_postable_mapped_account' then
        raise exception 'assertion failed: expected finance_subledger_not_postable_mapped_account, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'settlement',
      (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-5'), '2026-03-11'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_draft_account_id, 'direction', 'debit', 'amount', 50),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 50)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_inactive_mapped_account for a never-activated account referenced directly';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_inactive_mapped_account' then
        raise exception 'assertion failed: expected finance_subledger_inactive_mapped_account, got %', sqlerrm;
      end if;
  end;

  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'settlement',
    (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-2'), '2026-03-11'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_account_id, 'direction', 'debit', 'amount', 75),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 75)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select array_agg(r order by r.line_number) into v_lines from app.finance_subledger_lines r where batch_id = v_batch.id;
  if v_lines[1].account_id <> v_cash_account_id or v_lines[1].posting_map_key is not null then
    raise exception 'assertion failed: expected line 1 to resolve directly to CASH-DEFAULT with a null posting_map_key, got account_id=% key=%', v_lines[1].account_id, v_lines[1].posting_map_key;
  end if;
end;
$$;

\echo '>> preview never persists: a balanced preview reports balanced=true; an unbalanced preview reports balanced=false; batch count is unchanged by either call'
do $$
declare
  v_tenant_a uuid;
  v_before integer;
  v_after integer;
  v_result jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select count(*) into v_before from app.finance_subledger_batches where tenant_id = v_tenant_a;

  select app.preview_finance_subledger_posting(v_tenant_a,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 200),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 200)
    ),
    '00000000-0000-0000-0000-000000029702') into v_result;
  if (v_result ->> 'balanced')::boolean is not true then
    raise exception 'assertion failed: expected a balanced preview, got %', v_result;
  end if;

  select app.preview_finance_subledger_posting(v_tenant_a,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 200),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 150)
    ),
    '00000000-0000-0000-0000-000000029702') into v_result;
  if (v_result ->> 'balanced')::boolean is not false then
    raise exception 'assertion failed: expected an unbalanced preview, got %', v_result;
  end if;

  select count(*) into v_after from app.finance_subledger_batches where tenant_id = v_tenant_a;
  if v_after <> v_before then
    raise exception 'assertion failed: expected preview to persist zero rows, batch count moved from % to %', v_before, v_after;
  end if;
end;
$$;

\echo '>> control-account reconciliation: a real match between subledger control balances and live AR/AP open-item totals reports reconciled=true; an unmatched extra invoice-sourced open item (posted with no matching subledger batch) makes it false -- a real comparison against this same tenant''s own already-accumulated activity from earlier scenario groups in this file, not a hardcoded/reset-state claim'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_ar_item app.finance_ar_open_items;
  v_ap_item app.finance_ap_open_items;
  v_vendor app.master_records;
  v_summary_before jsonb;
  v_summary jsonb;
  v_extra_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary_before;

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Subledger Customer', 'acmesubl-customer-fixture-fingerprint', '{}'::jsonb, (select id from app.org_units where tenant_id = v_tenant_a limit 1), 'tester');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  v_ar_item := app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', pg_temp.iss319_mint_invoice(v_tenant_a, v_customer_id, '00000000-0000-0000-0000-000000029702', 'financemanagera', 'iss319-subledger-ar'), 'USD', 500, '2026-03-12'::date, '2026-04-11'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  -- ISS-2026-206/ISS-2026-319: v_ar_item.source_document_id used to be a bare
  -- gen_random_uuid() -- app.finance_ar_open_items.source_document_id carried the
  -- same unresolved-polymorphic-id shape ISS-2026-206 closed one hop further in,
  -- and is now guarded by 20260901060000's own app.validate_finance_open_item_source
  -- (ISS-2026-319), so it now points at a real, minted app.finance_invoices row.
  -- A real settlement is still used for the subledger batch's own source_id below;
  -- the AR/AP totals this block actually asserts on come from the open items'
  -- source_document_TYPE and open_amount, never from the batch's source_type.
  perform app.post_finance_subledger_batch(v_tenant_a, null, 'settlement',
    (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-3'), '2026-03-12'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 500),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 500)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select * into v_vendor from app.create_master_record('vendor', v_tenant_a, 'VEND-SUBL-1', 'Subledger Vendor', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  v_ap_item := app.post_finance_ap_open_item(v_tenant_a, null, v_vendor.id, 'vendor_bill', pg_temp.iss319_mint_vendor_bill(v_tenant_a, v_customer_id, v_vendor.id, '00000000-0000-0000-0000-000000029702', 'financemanagera', 'iss319-subledger-ap'), 'USD', 300, '2026-03-12'::date, '2026-04-11'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.post_finance_subledger_batch(v_tenant_a, null, 'settlement',
    (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-4'), '2026-03-12'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', 300),
      jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', 300)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary;
  if (v_summary ->> 'arReconciled')::boolean is not true or (v_summary ->> 'apReconciled')::boolean is not true then
    raise exception 'assertion failed: expected both AR and AP reconciled after every open item had a matching subledger batch, got %', v_summary;
  end if;
  if (v_summary ->> 'arControlSubledgerBalance')::numeric - (v_summary_before ->> 'arControlSubledgerBalance')::numeric <> 500
     or (v_summary ->> 'arOpenItemTotal')::numeric - (v_summary_before ->> 'arOpenItemTotal')::numeric <> 500 then
    raise exception 'assertion failed: expected AR control balance and open total to each move by exactly 500 from this scenario''s own real invoice, got before=% after=%', v_summary_before, v_summary;
  end if;
  if (v_summary ->> 'apControlSubledgerBalance')::numeric - (v_summary_before ->> 'apControlSubledgerBalance')::numeric <> 300
     or (v_summary ->> 'apOpenItemTotal')::numeric - (v_summary_before ->> 'apOpenItemTotal')::numeric <> 300 then
    raise exception 'assertion failed: expected AP control balance and open total to each move by exactly 300 from this scenario''s own real vendor bill, got before=% after=%', v_summary_before, v_summary;
  end if;

  -- An AR open item posted with no matching subledger batch does NOT break
  -- reconciliation, and must not silently disappear from the report either.
  --
  -- ISS-2026-236-era note, updated at ISS-2026-273: this used to hold because the
  -- comparison filtered open items to source_document_type = 'invoice', excluding
  -- opening balances outright. That filter is gone -- opening balances now emit real
  -- subledger batches, and one that HAS a batch is counted in arOpenItemTotal (see the
  -- dedicated import block later in this file). This item is excluded from the total
  -- because it has NO batch, and it is now reported explicitly as
  -- arOpeningBalanceNotPostedToGl rather than vanishing into a filter. That distinction
  -- is the whole point: Prompt 385 §24's "exact reconciliation" means being able to see a
  -- difference, not excluding it from the comparison.
  v_extra_item := app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'opening_balance', pg_temp.iss319_mint_staging_row(v_tenant_a, '00000000-0000-0000-0000-000000029702', 'financemanagera'), 'USD', 999, '2026-03-01'::date, '2026-03-31'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary;
  if (v_summary ->> 'arReconciled')::boolean is not true or (v_summary ->> 'arOpenItemTotal')::numeric <> 500 + (v_summary_before ->> 'arOpenItemTotal')::numeric then
    raise exception 'assertion failed: expected arReconciled to remain true and arOpenItemTotal unmoved by the un-posted opening_balance item, got before=% after=%', v_summary_before, v_summary;
  end if;
  if (v_summary ->> 'arOpeningBalanceNotPostedToGl')::numeric <> 999 then
    raise exception 'assertion failed: expected the un-posted opening balance to be REPORTED as arOpeningBalanceNotPostedToGl = 999, not silently filtered out, got %', v_summary ->> 'arOpeningBalanceNotPostedToGl';
  end if;
  if (v_summary ->> 'openingBalancesFullyPostedToGl')::boolean is not false then
    raise exception 'assertion failed: expected openingBalancesFullyPostedToGl to be false while an opening balance has no GL batch, got %', v_summary ->> 'openingBalancesFullyPostedToGl';
  end if;
end;
$$;

\echo '>> list/lines and cross-tenant isolation: filtering by source_type returns only matching batches; get_finance_subledger_lines is ordered by line_number; Finance Manager B (tenant B, no posting map ever published) sees zero of tenant A''s own batches'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_settlement_batches app.finance_subledger_batches[];
  v_invoice_batches app.finance_subledger_batches[];
  v_unfiltered app.finance_subledger_batches[];
  v_cross_rows app.finance_subledger_batches[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  v_tenant_b := (select id from app.tenants where slug = 'acmesublb');

  -- ISS-2026-206 changed which source types this fixture can produce: a batch's source_id is
  -- now resolved against the table its source_type names, and settlement is the one source
  -- document this file makes real. So the filter is exercised in BOTH directions instead of
  -- twice in one -- a type that has rows, and a type that has none.
  select array_agg(r) into v_settlement_batches from app.list_finance_subledger_batches(v_tenant_a, null, 'settlement', '00000000-0000-0000-0000-000000029702') r;
  if v_settlement_batches is null or exists (select 1 from unnest(v_settlement_batches) r where r.source_type <> 'settlement') then
    raise exception 'assertion failed: expected list_finance_subledger_batches filtered by source_type=settlement to return a non-empty set of only settlement batches, got %', v_settlement_batches;
  end if;

  -- The exclusion half, which the previous two-inclusive-filters shape never actually tested:
  -- this tenant posts no invoice-sourced batch, so the filter must return nothing rather than
  -- falling back to everything.
  select array_agg(r) into v_invoice_batches from app.list_finance_subledger_batches(v_tenant_a, null, 'invoice', '00000000-0000-0000-0000-000000029702') r;
  if v_invoice_batches is not null then
    raise exception 'assertion failed: expected list_finance_subledger_batches filtered by source_type=invoice to return zero rows for a tenant with no invoice-sourced batch, got %', v_invoice_batches;
  end if;

  -- ...and the filter must genuinely be narrowing, not returning nothing for every value.
  select array_agg(r) into v_unfiltered from app.list_finance_subledger_batches(v_tenant_a, null, null, '00000000-0000-0000-0000-000000029702') r;
  if v_unfiltered is null or array_length(v_unfiltered, 1) < array_length(v_settlement_batches, 1) then
    raise exception 'assertion failed: expected the unfiltered list to be at least as large as the settlement-filtered one';
  end if;

  select array_agg(r) into v_cross_rows from app.list_finance_subledger_batches(v_tenant_b, null, null, '00000000-0000-0000-0000-000000029705') r;
  if v_cross_rows is not null and exists (select 1 from unnest(v_cross_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_subledger_batches to never return a tenant A row';
  end if;

  -- Tenant B needs a real source document too: the posting-map lookup this asserts on happens
  -- after the batch row is inserted, so a fabricated id would trip ISS-2026-206's lineage
  -- guard before the missing-map check could be reached.
  insert into app.master_records (master_type_code, tenant_id, code, name)
  values ('vendor', v_tenant_b, 'ISS206-SUBLB-VEND', 'ISS-2026-206 fixture vendor (tenant B)');
  insert into app.finance_settlements (tenant_id, vendor_master_id, currency, settlement_date, idempotency_key)
  values (v_tenant_b, (select id from app.master_records where tenant_id = v_tenant_b and code = 'ISS206-SUBLB-VEND'),
          'USD', '2026-03-12'::date, 'iss206-sublb-1');

  begin
    perform app.post_finance_subledger_batch(v_tenant_b, null, 'settlement',
      (select id from app.finance_settlements where tenant_id = v_tenant_b and idempotency_key = 'iss206-sublb-1'), '2026-03-12'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 10),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 10)
      ),
      '00000000-0000-0000-0000-000000029705', 'financemanagerb');
    raise exception 'assertion failed: expected finance_subledger_missing_posting_map for tenant B, which never published one';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_missing_posting_map' then
        raise exception 'assertion failed: expected finance_subledger_missing_posting_map, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-206: app.finance_subledger_batches.source_id is resolved against the table its own source_type names -- a fabricated id is refused for every one of the five types, INCLUDING through a direct service_role insert that bypasses the RPC entirely, which is how the gap was originally live-forced'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmesubla');
  v_period_id uuid;
  v_source_type text;
  -- subl-5 rather than subl-1: subl-5 backs only the two account-resolution negative paths
  -- above, both of which roll back, so no batch exists for it and the positive insert below
  -- does not collide with the (tenant, source_type, source_id) uniqueness rule.
  v_real_settlement uuid := (select id from app.finance_settlements where tenant_id = v_tenant_a and idempotency_key = 'iss206-subl-5');
begin
  v_period_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a limit 1);

  -- The original live-forcing shape: a raw insert as the owner, not a call through the RPC.
  -- A guard that only lives inside app.post_finance_subledger_batch would pass this and still
  -- leave the table able to hold a lineage-less row.
  foreach v_source_type in array array['invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance'] loop
    begin
      insert into app.finance_subledger_batches (tenant_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
      values (v_tenant_a, v_source_type, gen_random_uuid(), 'USD', 1, v_period_id, 'iss206-prober');
      raise exception 'assertion failed: a direct insert with a fabricated source_id for source_type % was accepted -- ISS-2026-206 has regressed', v_source_type;
    exception
      when foreign_key_violation then
        if sqlerrm not like 'finance_subledger_orphan_source%' then raise; end if;
    end;
  end loop;

  -- The guard must not have become a blanket refusal: a REAL settlement still inserts.
  insert into app.finance_subledger_batches (tenant_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
  values (v_tenant_a, 'settlement', v_real_settlement, 'USD', 1, v_period_id, 'iss206-prober-positive');
  delete from app.finance_subledger_batches where posted_by = 'iss206-prober-positive';

  -- receipt_allocation resolves against the allocation BATCH, not app.finance_receipt_
  -- allocations. Getting this backwards would have rejected every legitimate receipt
  -- allocation in production, so it is pinned rather than left to a reader's assumption.
  if position('finance_receipt_allocation_batches' in pg_get_functiondef('app.validate_finance_subledger_batch_source()'::regprocedure)) = 0 then
    raise exception 'assertion failed: the receipt_allocation branch must resolve against app.finance_receipt_allocation_batches -- app.allocate_finance_receipt passes the allocation batch id, not an allocation row id';
  end if;

  -- An UPDATE is guarded too, not just an INSERT: moving an existing batch onto a fabricated
  -- source is the same lie arriving by a different route.
  begin
    update app.finance_subledger_batches set source_id = gen_random_uuid()
    where tenant_id = v_tenant_a and source_type = 'settlement';
    raise exception 'assertion failed: an UPDATE onto a fabricated source_id was accepted -- the guard must cover UPDATE as well as INSERT';
  exception
    when foreign_key_violation then
      if sqlerrm not like 'finance_subledger_orphan_source%' then raise; end if;
  end;

  raise notice 'ISS-2026-206 proof: all five source types resolve their source_id against the table their real caller reads; a fabricated id is refused on INSERT and on UPDATE, including through a direct owner insert; a real one still posts';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-202 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'check_finance_subledger_authority', 'resolve_finance_posting_map_account', 'post_finance_subledger_batch',
    'preview_finance_subledger_posting', 'list_finance_subledger_batches', 'get_finance_subledger_lines',
    'get_finance_subledger_reconciliation_summary'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;
end;
$$;

\echo '>> audit trail: at least one post_finance_subledger_batch event was captured for tenant A''s own subledger activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action = 'post_finance_subledger_batch';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 post_finance_subledger_batch audit event, found %', v_count;
  end if;
end;
$$;

\echo '>> HDN-374 (Financial Integrity Audit) finding 3 regression: a REAL two-process concurrent race -- both processes call app.post_finance_subledger_batch for the SAME (tenant, source_type, source_id) at the same instant. post_finance_subledger_batch is the core GL-posting primitive called transitively by AR receipt allocation, AP settlement posting and invoice/vendor-bill subledger posting -- before the fix, the losing process surfaced a raw duplicate-key error; after the fix, it must gracefully return the SAME winning batch row, and the source''s own journal must be posted exactly once (never double-posted GL lines)'
-- A fixed, self-chosen source_id (not gen_random_uuid()) -- unlike the pick_task race
-- above, this proof's own post-race assertion needs to re-identify the exact target row
-- from a plain do $$ ... $$ block, and psql's own :variable interpolation is not
-- performed inside dollar-quoted bodies, so a literal constant known to both the raced
-- SQL and the assertion block is used instead of a \gset''d random value.
select id as race_tenant_id from app.tenants where slug = 'acmesubla' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.post_finance_subledger_batch(''' :race_tenant_id ''', null, ''settlement'', ''00000000-0000-0000-0000-000000029799'', ''2026-03-10'', ''USD'', ''[{"postingMapKey": "cash_default", "direction": "debit", "amount": 750}, {"postingMapKey": "revenue_default", "direction": "credit", "amount": 750}]''::jsonb, ''00000000-0000-0000-0000-000000029702'', ''financemanagera'');'
\set race_sql_b 'select app.post_finance_subledger_batch(''' :race_tenant_id ''', null, ''settlement'', ''00000000-0000-0000-0000-000000029799'', ''2026-03-10'', ''USD'', ''[{"postingMapKey": "cash_default", "direction": "debit", "amount": 750}, {"postingMapKey": "revenue_default", "direction": "credit", "amount": 750}]''::jsonb, ''00000000-0000-0000-0000-000000029702'', ''financemanagera'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-fin-subledger-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-fin-subledger-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_tenant_a uuid;
  v_source_id uuid := '00000000-0000-0000-0000-000000029799';
  v_batch_count integer;
  v_journal_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');

  select count(*) into v_batch_count from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'settlement' and source_id = v_source_id;
  if v_batch_count <> 1 then
    raise exception 'assertion failed: HDN-374 finding 3 regressed -- expected exactly ONE subledger batch row to survive the concurrent race (never two, never zero -- a raw unique_violation reaching a caller means this fix is not applied), got % -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_batch_count;
  end if;

  select count(*) into v_journal_count from app.finance_journals where tenant_id = v_tenant_a and source_type = 'subledger'
    and source_id = (select id from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'settlement' and source_id = v_source_id);
  if v_journal_count <> 1 then
    raise exception 'assertion failed: expected the race-surviving subledger batch to have posted exactly ONE backing system journal (never a double GL posting), got %', v_journal_count;
  end if;

  raise notice 'concurrent subledger-batch-post race proof: exactly 1 batch row / 1 backing journal survived two genuinely concurrent psql processes racing the SAME (tenant, source_type, source_id) -- the loser was handed the winner''s row gracefully, never a raw unique_violation';
end;
$$;

-- ===========================================================================
-- ISS-2026-273 -- bulk opening-balance import, and the GL posting opening
-- balances never had.
-- ===========================================================================

\echo '>> ISS-2026-273 setup: an opening-balance equity account, the opening_balance_equity posting-map key, a FIN:Import role for the finance manager, and the tenant''s published finance_opening_balance_import column definition'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmesubla');
  v_fm uuid := '00000000-0000-0000-0000-000000029702';
  -- This file seeds no Supreme Admin of its own (029701 is tenant_admin), and
  -- app.register_document_type is Supreme-only by design. One is created here rather
  -- than the check being worked around.
  v_supreme uuid := '00000000-0000-0000-0000-000000029799';
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_import_role uuid;
  v_import_draft app.role_versions;
  v_doctype_draft app.config_versions;
  v_schema_draft app.config_versions;
begin
  insert into auth.users (id, email) values (v_supreme, 'supreme@acmesubl.test')
  on conflict (id) do nothing;
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'OB-EQUITY', 'Opening Balance Equity', 'equity', 'credit', null, false, null, v_fm, 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, v_fm, 'financemanagera');

  -- A new published posting-map version. Every previously-published key is restated:
  -- set_finance_config_items replaces the item set, so omitting one would silently
  -- unconfigure it -- and fee_expense_default/tax_payable_default/input_tax_default stay
  -- deliberately held back, exactly as the original fixture left them, so the
  -- finance_subledger_missing_mapping negative path this file already exercises keeps
  -- working.
  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, v_fm, 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'ap_control', 'value', jsonb_build_object('accountCodeRef', 'AP-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'expense_default', 'value', jsonb_build_object('accountCodeRef', 'EXP-DEFAULT')),
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-DEFAULT')),
    jsonb_build_object('key', 'opening_balance_equity', 'value', jsonb_build_object('accountCodeRef', 'OB-EQUITY'))
  ), v_fm, 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, v_fm, null, 'financemanagera');

  -- FIN:Import is a distinct permission from FIN:Approve, and holding tenant_admin does
  -- not confer it -- the finance manager needs a granting role like anyone else.
  v_import_role := (app.create_role(v_tenant_a, 'Finance Importer', 'FIN:Import', 'tester')).id;
  v_import_draft := app.create_role_version(v_import_role, 'tester');
  perform app.set_role_version_permissions(v_import_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action = 'Import'), 'tester');
  perform app.publish_role_version(v_import_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_import_role and status = 'published'), v_fm, v_fm, 'tester');

  perform app.register_document_type('finance_opening_balance_source', 'Finance Opening Balance Source File', 'FIN', v_supreme, 'supreme');
  v_doctype_draft := app.create_config_draft('document:finance_opening_balance_source', v_tenant_a, 'tenant', null, v_fm, 'financemanagera');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_fm, 'financemanagera');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_fm, now(), 'financemanagera');

  v_schema_draft := app.create_config_draft('import_export:finance_opening_balance_import', v_tenant_a, 'tenant', null, v_fm, 'financemanagera');
  perform app.set_config_items(
    v_schema_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'open_item_type', 'label', 'AR or AP', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'party_tax_id', 'label', 'Customer tax id', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'party_legal_name', 'label', 'Customer legal name', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'party_vendor_code', 'label', 'Vendor code', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'currency', 'label', 'Currency', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'original_amount', 'label', 'Amount', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'document_date', 'label', 'Document date', 'required', true, 'data_type', 'date'),
      jsonb_build_object('key', 'due_date', 'label', 'Due date', 'required', true, 'data_type', 'date')
    ), 'canonical_ref', null)),
    v_fm, 'financemanagera'
  );
  perform app.publish_import_export_schema(v_schema_draft.id, v_fm, now(), 'financemanagera');
end $$;

\echo '>> ISS-2026-273: the opening-balance import validates ar/ap, currency, amount sign and scale, dates, an OPEN fiscal period and counterparty resolution (ambiguity refused); a real batch posts BOTH the open item and its balanced GL entry in one transaction; the equity counter-account carries the offset; reconciliation now counts them and reports openingBalancesFullyPostedToGl'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmesubla');
  v_fm uuid := '00000000-0000-0000-0000-000000029702';
  v_editor uuid := '00000000-0000-0000-0000-000000029703';
  v_customer_id uuid;
  v_customer_tax text := '09.876.543.2-109.000';
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
  v_ar app.finance_ar_open_items;
  v_ap app.finance_ap_open_items;
  v_batch app.finance_subledger_batches;
  v_equity app.finance_accounts;
  v_equity_balance numeric(14, 2);
  v_summary jsonb;
  v_summary_before jsonb;
begin
  -- A customer with a resolvable tax id, and a second one whose legal name collides, so
  -- the ambiguity path is exercised against a real collision rather than a contrived one.
  select id into v_customer_id from app.accounts where tenant_id = v_tenant_a and legal_name = 'Acme Subledger Customer';
  update app.accounts
  set tax_id = v_customer_tax, normalized_tax_id = app.normalize_prospect_identifier(v_customer_tax),
      normalized_legal_name = app.normalize_prospect_identifier('Acme Subledger Customer')
  where id = v_customer_id;

  insert into app.accounts (tenant_id, legal_name, normalized_legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant_a, 'Acme Subledger Customer', app.normalize_prospect_identifier('Acme Subledger Customer'),
          'acmesubl-ambiguous-twin-fingerprint', '{}'::jsonb, 'tester');

  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, v_fm) into v_summary_before;

  v_source_file := app.initiate_file_upload(
    v_tenant_a, 'finance_opening_balance_source', 'import_source', gen_random_uuid(),
    'opening-balances.csv', 'text/csv', 4096, 'internal', false, null, null, null,
    'idem-fin-ob-source', v_fm, 'financemanagera'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_fm, 'financemanagera');
  v_job := app.create_import_export_job(v_tenant_a, 'import', 'finance_opening_balance_import', v_source_file.id, '{}'::jsonb, 'idem-fin-ob-job', v_fm, 'financemanagera');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- 1: valid AR, customer resolved by tax id.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '1250.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 2: valid AP, vendor resolved by code (VEND-SUBL-1 exists from the earlier block).
      jsonb_build_object('open_item_type', 'ap', 'party_vendor_code', 'VEND-SUBL-1', 'currency', 'USD',
                         'original_amount', '400.00', 'document_date', '2026-03-06', 'due_date', '2026-03-26'),
      -- 3: neither ar nor ap.
      jsonb_build_object('open_item_type', 'gl', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '10.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 4: a negative amount -- a sign error in a cutover extract must not abort the batch
      --    at row 700; it is caught at validation.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '-50.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 5: more precision than numeric(14,2) can store. Rounding a customer's opening debt
      --    is exactly the quiet difference §24 forbids, so it is refused, not rounded.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '10.005', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 6: a date outside any open fiscal period.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '10.00', 'document_date', '2019-01-01', 'due_date', '2019-02-01'),
      -- 7: due before document date.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
                         'original_amount', '10.00', 'document_date', '2026-03-20', 'due_date', '2026-03-10'),
      -- 8: an AMBIGUOUS customer name -- two active accounts normalize identically.
      jsonb_build_object('open_item_type', 'ar', 'party_legal_name', 'Acme Subledger Customer', 'currency', 'USD',
                         'original_amount', '10.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 9: an AP row naming no vendor at all.
      jsonb_build_object('open_item_type', 'ap', 'currency', 'USD',
                         'original_amount', '10.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'),
      -- 10: an unregistered currency.
      jsonb_build_object('open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'ZZZ',
                         'original_amount', '10.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25')
    ),
    v_fm, 'financemanagera'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;
  for v_idx in 1..10 loop
    perform app.validate_finance_opening_balance_import_row(v_ids[v_idx], v_fm, 'financemanagera');
  end loop;

  if (select validation_status from app.import_staging_rows where id = v_ids[1]) <> 'valid'
     or (select validation_status from app.import_staging_rows where id = v_ids[2]) <> 'valid' then
    raise exception 'assertion failed: expected rows 1 (AR) and 2 (AP) to validate cleanly';
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[3];
  if v_status <> 'invalid' or v_error not like '%must be ar or ap%' then
    raise exception 'assertion failed: row 3, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[4];
  if v_status <> 'invalid' or v_error not like '%must be positive%' then
    raise exception 'assertion failed: row 4, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[5];
  if v_status <> 'invalid' or v_error not like '%would be silently rounded on storage%' then
    raise exception 'assertion failed: row 5, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[6];
  if v_status <> 'invalid' or v_error not like '%no fiscal period covers%' then
    raise exception 'assertion failed: row 6, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[7];
  if v_status <> 'invalid' or v_error not like '%is before document_date%' then
    raise exception 'assertion failed: row 7, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[8];
  if v_status <> 'invalid' or v_error not like '%ambiguous%' then
    raise exception 'assertion failed: row 8 -- posting one customer''s opening debt against another''s account is a misstatement, so ambiguity must be refused, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[9];
  if v_status <> 'invalid' or v_error not like '%requires party_vendor_code%' then
    raise exception 'assertion failed: row 9, got status=% error=%', v_status, v_error;
  end if;
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[10];
  if v_status <> 'invalid' or v_error not like '%not a registered, active currency%' then
    raise exception 'assertion failed: row 10, got status=% error=%', v_status, v_error;
  end if;

  -- The Finance Editor holds FIN:Edit/View but neither tenant_admin nor FIN:Import.
  begin
    perform app.commit_finance_opening_balance_import_job(v_job.job_id, true, v_editor, 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for an actor without FIN:Import';
  exception when insufficient_privilege then
    null;
  end;

  v_updated := app.commit_finance_opening_balance_import_job(v_job.job_id, true, v_fm, 'financemanagera');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected the opening-balance job to complete, got %', v_updated.status;
  end if;

  -- The open item exists, keyed by the staging row id -- no second provenance column.
  select * into v_ar from app.finance_ar_open_items
  where tenant_id = v_tenant_a and source_document_type = 'opening_balance' and source_document_id = v_ids[1];
  if not found or v_ar.original_amount <> 1250.00 or v_ar.customer_account_id <> v_customer_id then
    raise exception 'assertion failed: expected row 1 to have produced a 1250.00 AR opening balance against the resolved customer, got %', v_ar;
  end if;
  select * into v_ap from app.finance_ap_open_items
  where tenant_id = v_tenant_a and source_document_type = 'opening_balance' and source_document_id = v_ids[2];
  if not found or v_ap.original_amount <> 400.00 then
    raise exception 'assertion failed: expected row 2 to have produced a 400.00 AP opening balance, got %', v_ap;
  end if;

  -- ...and so does its GL batch. This is the half that never existed before ISS-2026-273.
  select * into v_batch from app.finance_subledger_batches
  where tenant_id = v_tenant_a and source_type = 'opening_balance' and source_id = v_ar.id;
  if not found or v_batch.total_amount <> 1250.00 then
    raise exception 'assertion failed: expected a balanced opening_balance subledger batch of 1250.00 for the AR item, got %', v_batch;
  end if;
  if (select count(*) from app.finance_subledger_lines where batch_id = v_batch.id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines (control + equity) on the opening-balance batch';
  end if;

  -- The equity counter-account carries the offset, in the right direction on both sides:
  -- credited 1250 by the AR item and debited 400 by the AP item, net 850 credit.
  v_equity := app.resolve_finance_posting_map_account(v_tenant_a, 'opening_balance_equity');
  select coalesce(sum(case when l.direction = 'credit' then l.amount else -l.amount end), 0) into v_equity_balance
    from app.finance_subledger_lines l join app.finance_subledger_batches b on b.id = l.batch_id
    where b.tenant_id = v_tenant_a and l.account_id = v_equity.id;
  if v_equity_balance <> 850.00 then
    raise exception 'assertion failed: expected opening_balance_equity net credit of 850.00 (1250 AR credit less 400 AP debit), got %', v_equity_balance;
  end if;

  -- Reconciliation counts the newly-posted opening balances on BOTH sides and stays exact.
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, v_fm) into v_summary;
  if (v_summary ->> 'arReconciled')::boolean is not true or (v_summary ->> 'apReconciled')::boolean is not true then
    raise exception 'assertion failed: expected reconciliation to remain exact once opening balances post to the GL -- this is the case that would have read UNRECONCILED under the old invoice-only filter, got %', v_summary;
  end if;
  if (v_summary ->> 'arOpenItemTotal')::numeric - (v_summary_before ->> 'arOpenItemTotal')::numeric <> 1250.00 then
    raise exception 'assertion failed: expected arOpenItemTotal to move by exactly the imported 1250.00, before=% after=%', v_summary_before, v_summary;
  end if;
  if (v_summary ->> 'apOpenItemTotal')::numeric - (v_summary_before ->> 'apOpenItemTotal')::numeric <> 400.00 then
    raise exception 'assertion failed: expected apOpenItemTotal to move by exactly the imported 400.00, before=% after=%', v_summary_before, v_summary;
  end if;
  -- The earlier un-posted 999 opening balance is still outstanding and still reported.
  if (v_summary ->> 'arOpeningBalanceNotPostedToGl')::numeric <> 999
     or (v_summary ->> 'openingBalancesFullyPostedToGl')::boolean is not false then
    raise exception 'assertion failed: expected the earlier un-posted 999 opening balance to remain visible and keep openingBalancesFullyPostedToGl false, got %', v_summary;
  end if;

  -- Posting THAT one closes the loop: the report flips to fully posted.
  perform app.post_finance_opening_balance_batch('ar', (select id from app.finance_ar_open_items where tenant_id = v_tenant_a and source_document_type = 'opening_balance' and original_amount = 999), v_fm, 'financemanagera');
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, v_fm) into v_summary;
  if (v_summary ->> 'arOpeningBalanceNotPostedToGl')::numeric <> 0
     or (v_summary ->> 'openingBalancesFullyPostedToGl')::boolean is not true
     or (v_summary ->> 'arReconciled')::boolean is not true then
    raise exception 'assertion failed: expected posting the last outstanding opening balance to flip openingBalancesFullyPostedToGl true with reconciliation still exact, got %', v_summary;
  end if;

  -- Replay is refused, and creates nothing.
  begin
    perform app.commit_finance_opening_balance_import_job(v_job.job_id, true, v_fm, 'financemanagera');
    raise exception 'assertion failed: expected import_export_job_not_committable on a replayed commit';
  exception when sqlstate '23514' then
    if sqlerrm not like 'import_export_job_not_committable%' then raise; end if;
  end;

  -- The GL posting is itself idempotent per open item.
  v_batch := app.post_finance_opening_balance_batch('ar', v_ar.id, v_fm, 'financemanagera');
  if (select count(*) from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'opening_balance' and source_id = v_ar.id) <> 1 then
    raise exception 'assertion failed: expected a repeated opening-balance GL post to return the existing batch, not create a second';
  end if;

  -- It refuses a non-opening-balance open item outright, so it can never be used to
  -- double-post an invoice that already has its own batch.
  begin
    perform app.post_finance_opening_balance_batch('ar', (select id from app.finance_ar_open_items where tenant_id = v_tenant_a and source_document_type = 'invoice' limit 1), v_fm, 'financemanagera');
    raise exception 'assertion failed: expected finance_opening_balance_wrong_source_type for an invoice-sourced open item';
  exception when check_violation then
    null;
  end;
end $$;

\echo '>> ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed) regression: app.commit_finance_opening_balance_import_job composes app.assert_current_step_up_authorization(tenant, actor, ''FIN'', ''Import'') immediately after its own existing FIN:Import check -- a strict no-op for a tenant with no MFA policy configured, and a real block-then-unblock once the tenant opts (FIN, Import) into its own additional_high_risk_actions and completes a genuine step-up challenge'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmesubla');
  v_fm uuid := '00000000-0000-0000-0000-000000029702';
  v_supreme uuid := '00000000-0000-0000-0000-000000029999';
  v_customer_tax text := '09.876.543.2-109.000';
  v_source_file1 app.files;
  v_source_file2 app.files;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_committed app.jobs;
  v_challenge app.mfa_step_up_challenges;
  v_raised boolean;
begin
  insert into auth.users (id, email) values (v_supreme, 'supreme@acmesubla.test')
    on conflict (id) do nothing;
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  -- (a) no app.mfa_tenant_policies row at all yet for this tenant -- a strict no-op, the
  -- commit succeeds exactly as it did before this checkpoint.
  v_source_file1 := app.initiate_file_upload(
    v_tenant_a, 'finance_opening_balance_source', 'import_source', gen_random_uuid(),
    'opening-balances-mfacheck-a.csv', 'text/csv', 4096, 'internal', false, null, null, null,
    'idem-fin-ob-mfacheck-source-a', v_fm, 'financemanagera'
  );
  perform app.record_file_scan_result(v_source_file1.id, 'clean', 'test-scanner', v_fm, 'financemanagera');
  v_job1 := app.create_import_export_job(v_tenant_a, 'import', 'finance_opening_balance_import', v_source_file1.id, '{}'::jsonb, 'idem-fin-ob-mfacheck-job-a', v_fm, 'financemanagera');
  perform app.stage_import_rows(v_job1.job_id, jsonb_build_array(jsonb_build_object(
    'open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
    'original_amount', '10.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'
  )), v_fm, 'financemanagera');
  perform app.validate_finance_opening_balance_import_row((select id from app.import_staging_rows where job_id = v_job1.job_id and row_number = 1), v_fm, 'financemanagera');
  v_committed := app.commit_finance_opening_balance_import_job(v_job1.job_id, false, v_fm, 'financemanagera');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit for a tenant with no MFA policy configured (strict no-op), got %', v_committed;
  end if;

  -- (b) this tenant now additively opts (FIN, Import) into its own additional_high_risk_
  -- actions -- tenant_wide_required deliberately left false, since app.assert_current_
  -- step_up_authorization gates on is_high_risk_action alone, never on tenant_wide_required.
  -- Never FIN:Approve, which is a platform-default high-risk tuple already.
  perform app.set_mfa_tenant_policy(v_tenant_a, false, '["supreme_admin", "tenant_admin"]'::jsonb, 15, '[{"moduleCode": "FIN", "action": "Import"}]'::jsonb, v_supreme, 'supreme');

  v_source_file2 := app.initiate_file_upload(
    v_tenant_a, 'finance_opening_balance_source', 'import_source', gen_random_uuid(),
    'opening-balances-mfacheck-b.csv', 'text/csv', 4096, 'internal', false, null, null, null,
    'idem-fin-ob-mfacheck-source-b', v_fm, 'financemanagera'
  );
  perform app.record_file_scan_result(v_source_file2.id, 'clean', 'test-scanner', v_fm, 'financemanagera');
  v_job2 := app.create_import_export_job(v_tenant_a, 'import', 'finance_opening_balance_import', v_source_file2.id, '{}'::jsonb, 'idem-fin-ob-mfacheck-job-b', v_fm, 'financemanagera');
  perform app.stage_import_rows(v_job2.job_id, jsonb_build_array(jsonb_build_object(
    'open_item_type', 'ar', 'party_tax_id', v_customer_tax, 'currency', 'USD',
    'original_amount', '20.00', 'document_date', '2026-03-05', 'due_date', '2026-03-25'
  )), v_fm, 'financemanagera');
  perform app.validate_finance_opening_balance_import_row((select id from app.import_staging_rows where job_id = v_job2.job_id and row_number = 1), v_fm, 'financemanagera');

  v_raised := false;
  begin
    perform app.commit_finance_opening_balance_import_job(v_job2.job_id, false, v_fm, 'financemanagera');
    raise exception 'assertion failed: expected mfa_step_up_required with no verified challenge on record, the call unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'mfa_step_up_required' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected mfa_step_up_required, got none';
  end if;
  if (select status from app.jobs where job_id = v_job2.job_id) <> 'in_progress' then
    raise exception 'assertion failed: expected the job to remain in_progress while blocked on step-up';
  end if;

  -- (c) a genuine step-up challenge (request + verify) for the SAME actor/tenant/module/
  -- action then unblocks the identical commit call.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant_a, 'FIN', 'Import', v_fm, 'financemanagera');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_fm, 'financemanagera');

  v_committed := app.commit_finance_opening_balance_import_job(v_job2.job_id, false, v_fm, 'financemanagera');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit once a current verified step-up challenge exists, got %', v_committed;
  end if;

  raise notice 'PASS: app.commit_finance_opening_balance_import_job (ISS-2026-278, resumed) is a strict no-op for a tenant with no MFA policy configured, blocks with mfa_step_up_required once the tenant opts (FIN, Import) into its own additional_high_risk_actions, and succeeds again once a genuine step-up challenge is requested and verified';
end;
$$;

\echo '>> ISS-2026-273: neither anon nor authenticated holds EXECUTE on the new opening-balance functions or their public wrappers'
do $$
declare
  v_has boolean;
  v_fn text;
begin
  foreach v_fn in array array[
    'app.post_finance_opening_balance_batch(text, uuid, uuid, text, text)',
    'app.validate_finance_opening_balance_import_row(uuid, uuid, text)',
    'app.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text)',
    'public.post_finance_opening_balance_batch(text, uuid, uuid, text, text)',
    'public.validate_finance_opening_balance_import_row(uuid, uuid, text)',
    'public.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has;
    if v_has then raise exception 'assertion failed: anon must hold no EXECUTE on %', v_fn; end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has;
    if v_has then raise exception 'assertion failed: authenticated must hold no EXECUTE on %', v_fn; end if;
  end loop;
end $$;
