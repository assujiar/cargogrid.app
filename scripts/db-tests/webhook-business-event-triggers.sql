-- Real, executable test evidence for CG-AUDIT-2026-09-02 E6 (webhook half),
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves the one narrow gap the original finding actually identified --
-- "app.queue_webhook_delivery is referenced by 0 other database functions"
-- -- is now closed for the three event types IAE-012's own seed data already
-- anticipated: a real ticket creation, invoice issuance, and shipment status
-- transition each genuinely enqueue a real app.webhook_deliveries row (never
-- merely a hypothetical wiring). Also proves: a tenant with zero subscribed
-- endpoints incurs no error (safe no-op); a customer-channel ticket (filed by
-- a customer_user-layer identity) fires the same event without being blocked
-- by a second, unrelated "may trigger webhooks" authority check (this
-- migration's own central design claim -- app._enqueue_webhook_delivery has
-- no authority check of its own, precisely so a customer-originated event
-- is never treated as less trustworthy than a staff-originated one); a
-- shipment order that transitions twice fires two DISTINCT deliveries, never
-- deduped against each other; cross-tenant isolation (tenant B's own
-- endpoint never receives tenant A's events); and that app.queue_webhook_
-- delivery's own public authority gate (its existing callers: the manual
-- send-test/replay console actions) is entirely unaffected by the E6
-- refactor -- still denies a non-member caller.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors scripts/db-tests/webhook-management.sql's own setup).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

create function pg_temp.e6_mint_job_order(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
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
  values (p_tenant_id, 'manual', p_seed, p_seed || '@e6-webhook-fixture.test', p_actor_label)
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
  values (p_tenant_id, v_quotation_id, p_account_id, '{}'::jsonb, 'e6-fixture-hash-' || p_seed, p_actor_auth_user_id, p_actor_label)
  returning id into v_joh_id;

  insert into app.job_orders (tenant_id, job_number, source_handoff_id, quotation_id, account_id, customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot, created_by)
  values (p_tenant_id, p_seed || '-JOB', v_joh_id, v_quotation_id, p_account_id, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, p_actor_label)
  returning id into v_job_order_id;

  return v_job_order_id;
end;
$fn$;

\echo '>> setup: tenant A (one actor holding tenant_admin + TKT/OPS/FIN authority, a customer account + customer_user identity, a helpdesk-and-customer-visible ticket category, an active fiscal calendar, a published AR/revenue posting map, and a webhook endpoint subscribed to all three business event types), tenant B (its own webhook endpoint, same subscriptions, for cross-tenant isolation), and tenant C (zero webhook endpoints, for the safe-no-op proof)'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_tenant_c uuid;
  v_role uuid;
  v_role_draft app.role_versions;
  v_account_a uuid;
  v_company uuid;
  v_queue_id uuid;
  v_category_id uuid;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_endpoint_a record;
  v_endpoint_b record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000032101', 'actora@e6webhook.test'),
    ('00000000-0000-0000-0000-000000032102', 'customera@e6webhook.test'),
    ('00000000-0000-0000-0000-000000032103', 'actorb@e6webhook.test');

  perform app.provision_tenant('e6webhooka', 'E6 Webhook A', 'idem-e6webhooka', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');

  perform app.provision_tenant('e6webhookb', 'E6 Webhook B', 'idem-e6webhookb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'e6webhookb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');

  perform app.provision_tenant('e6webhookc', 'E6 Webhook C (no endpoints)', 'idem-e6webhookc', 'tester');
  v_tenant_c := (select id from app.tenants where slug = 'e6webhookc');
  perform app.transition_tenant_status(v_tenant_c, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032101', 'actora@e6webhook.test', 'Actor A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'actora@e6webhook.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032101', 'tenant_admin', v_tenant_a, null, 'tester');

  v_role := (app.create_role(v_tenant_a, 'E6 Actor', 'TKT/OPS/FIN full grants', 'tester')).id;
  v_role_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_role_draft.id,
    array(select id from app.permissions where
      (resource_module_code = 'TKT' and action = 'Edit')
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))
    ),
    'tester'
  );
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_role and status = 'published'), '00000000-0000-0000-0000-000000032101', '00000000-0000-0000-0000-000000032101', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000032103', 'actorb@e6webhook.test', 'Actor B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'actorb@e6webhook.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032103', 'tenant_admin', v_tenant_b, null, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant_a, 'E6 Customer Account', 'fp-e6webhook-a', '{}'::jsonb, 'tester')
  returning id into v_account_a;

  -- grant_principal_membership's own FK requires an app.tenant_user_identities
  -- row, so this customer identity is invited as a plain (non-employee)
  -- tenant user first, mirroring ATW-023's own established fixture pattern
  -- (scripts/db-tests/ticketing-customer.sql).
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032102', 'customera@e6webhook.test', 'Customer A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customera@e6webhook.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032102', 'customer_user', v_tenant_a, v_account_a::text, 'tester');

  v_company := (app.create_org_unit(v_tenant_a, 'company', null, 'E6WH-CO', 'E6 Webhook Co', 'tester')).id;
  v_queue_id := (app.create_ticket_queue(v_tenant_a, v_company, 'E6-Q', 'E6 Support Queue', null, '00000000-0000-0000-0000-000000032101', 'actora')).id;
  v_category_id := (app.create_ticket_category(v_tenant_a, 'E6-CAT', 'E6 Category', v_queue_id, '00000000-0000-0000-0000-000000032101', 'actora')).id;
  perform app.set_ticket_category_customer_visibility(v_category_id, true, '00000000-0000-0000-0000-000000032101', 'actora');
  perform app.set_ticket_category_helpdesk_visibility(v_category_id, true, '00000000-0000-0000-0000-000000032101', 'actora');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026E6', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000032101', 'actora');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-E6', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000032101', 'actora');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000032101', 'actora');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-E6', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000032101', 'actora');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000032101', 'actora');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000032101', 'actora');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-E6')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-E6'))
  ), '00000000-0000-0000-0000-000000032101', 'actora');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000032101', null, 'actora');

  select * into v_endpoint_a from app.register_webhook_endpoint(v_tenant_a, 'https://a.e6webhook.test/hook', '["ticket.created", "invoice.issued", "shipment.status_changed"]'::jsonb, '00000000-0000-0000-0000-000000032101', 'actora');
  select * into v_endpoint_b from app.register_webhook_endpoint(v_tenant_b, 'https://b.e6webhook.test/hook', '["ticket.created", "invoice.issued", "shipment.status_changed"]'::jsonb, '00000000-0000-0000-0000-000000032103', 'actorb');
end;
$$;

\echo '>> ticket.created (helpdesk channel): creating a real ticket enqueues exactly one real app.webhook_deliveries row for tenant A''s endpoint, in pending status, payload matching app.ticket_audit_projection; tenant B''s own endpoint (subscribed to the same event type) receives zero -- fan-out is genuinely tenant-scoped, not global'
do $$
declare
  v_tenant_a uuid;
  v_category_id uuid;
  v_ticket app.tickets;
  v_delivery record;
  v_count_b integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  v_category_id := (select id from app.ticket_categories where tenant_id = v_tenant_a and code = 'E6-CAT');

  v_ticket := app.create_helpdesk_ticket(v_tenant_a, v_category_id, 'normal', null, null, null, null, 'First support request', 'Please help.', 'e6-helpdesk-1', '00000000-0000-0000-0000-000000032101', 'actora');

  select d.* into v_delivery from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'ticket.created';
  if not found then
    raise exception 'assertion failed: expected a real webhook_deliveries row for ticket.created';
  end if;
  if v_delivery.status <> 'pending' or (v_delivery.payload ->> 'id') <> v_ticket.id::text or (v_delivery.payload ->> 'channel') <> 'helpdesk' then
    raise exception 'assertion failed: expected a pending delivery whose payload matches the real ticket (id=%, channel=helpdesk), got status=% payload=%', v_ticket.id, v_delivery.status, v_delivery.payload;
  end if;

  select count(*) into v_count_b from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    join app.tenants t on t.id = e.tenant_id
    where t.slug = 'e6webhookb';
  if v_count_b <> 0 then
    raise exception 'assertion failed: expected zero deliveries on tenant B''s own endpoint from tenant A''s ticket creation, got %', v_count_b;
  end if;
end;
$$;

\echo '>> ticket.created (customer channel): a customer_user-layer identity filing a ticket also fires the event -- proving app._enqueue_webhook_delivery imposes no second, transitive authority requirement beyond app._create_ticket''s own real customer-channel authority model'
do $$
declare
  v_tenant_a uuid;
  v_account_a uuid;
  v_category_id uuid;
  v_ticket app.tickets;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  v_account_a := (select id from app.accounts where tenant_id = v_tenant_a and legal_name = 'E6 Customer Account');
  v_category_id := (select id from app.ticket_categories where tenant_id = v_tenant_a and code = 'E6-CAT');

  v_ticket := app.create_customer_ticket(v_tenant_a, v_account_a, v_category_id, 'normal', 'Invoice question', 'What is my balance?', 'e6-customer-1', '00000000-0000-0000-0000-000000032102', 'Customer A');
  if v_ticket.channel <> 'customer' then
    raise exception 'assertion failed: expected a real customer-channel ticket, got channel=%', v_ticket.channel;
  end if;

  select count(*) into v_count from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'ticket.created';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 ticket.created deliveries now (helpdesk + customer), got %', v_count;
  end if;
  if not exists (
    select 1 from app.webhook_deliveries d join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'ticket.created' and (d.payload ->> 'id') = v_ticket.id::text and (d.payload ->> 'channel') = 'customer'
  ) then
    raise exception 'assertion failed: expected a delivery whose payload matches the real customer-channel ticket';
  end if;
end;
$$;

\echo '>> shipment.status_changed: a real shipment order transition (draft -> confirmed) enqueues one delivery; a SECOND, later transition (confirmed -> cancelled) enqueues a SECOND, distinct delivery -- never deduped against the first, since the idempotency key is scoped per transition (this migration''s own disclosed design), not per shipment order'
do $$
declare
  v_tenant_a uuid;
  v_account_a uuid;
  v_job_order_id uuid;
  v_shipment app.shipment_orders;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  v_account_a := (select id from app.accounts where tenant_id = v_tenant_a and legal_name = 'E6 Customer Account');
  v_job_order_id := pg_temp.e6_mint_job_order(v_tenant_a, v_account_a, '00000000-0000-0000-0000-000000032101', 'actora', 'e6ship1');

  insert into app.shipment_orders (
    tenant_id, job_order_id, shipment_number, idempotency_key, shipper_account_id, consignee_snapshot,
    cargo_service_snapshot, service_type, mode, origin, destination, owner_user_id, created_by
  ) values (
    v_tenant_a, v_job_order_id, 'E6-SHIP-1', 'e6-ship-1-idem', v_account_a, '{}'::jsonb,
    '{}'::jsonb, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya', '00000000-0000-0000-0000-000000032101', 'actora'
  ) returning * into v_shipment;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'confirmed', v_shipment.record_version, null, null, 'e6-transition-1', '00000000-0000-0000-0000-000000032101', 'actora');

  select count(*) into v_count from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'shipment.status_changed';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 shipment.status_changed delivery after the first transition, got %', v_count;
  end if;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'cancelled', v_shipment.record_version, 'no longer needed', null, 'e6-transition-2', '00000000-0000-0000-0000-000000032101', 'actora');

  select count(*) into v_count from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'shipment.status_changed';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 distinct shipment.status_changed deliveries after a second, different transition on the same shipment order, got %', v_count;
  end if;

  if not exists (
    select 1 from app.webhook_deliveries d join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'shipment.status_changed'
      and (d.payload ->> 'from_status') = 'confirmed' and (d.payload ->> 'to_status') = 'cancelled'
      and (d.payload ->> 'reason') = 'no longer needed'
  ) then
    raise exception 'assertion failed: expected the second delivery''s own payload to reflect the confirmed -> cancelled transition with its own real reason';
  end if;
end;
$$;

\echo '>> invoice.issued: a real invoice, submitted/approved/issued through the genuine lifecycle, enqueues one delivery whose payload carries the real invoice_number/total_amount/status'
do $$
declare
  v_tenant_a uuid;
  v_account_a uuid;
  v_job_order_id uuid;
  v_eval_id uuid;
  v_handoff_id uuid;
  v_invoice app.finance_invoices;
  v_delivery record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  v_account_a := (select id from app.accounts where tenant_id = v_tenant_a and legal_name = 'E6 Customer Account');
  v_job_order_id := pg_temp.e6_mint_job_order(v_tenant_a, v_account_a, '00000000-0000-0000-0000-000000032101', 'actora', 'e6inv1');

  insert into app.billing_readiness_evaluations (tenant_id, job_order_id, evaluated_status, is_overridden, override_reason, overridden_by_auth_user_id, overridden_by, evaluated_by_auth_user_id, evaluated_by, created_by)
  values (v_tenant_a, v_job_order_id, 'not_ready', true, 'E6 fixture: minted so issue_finance_invoice has a real invoice to issue', '00000000-0000-0000-0000-000000032101', 'actora', '00000000-0000-0000-0000-000000032101', 'actora', 'actora')
  returning id into v_eval_id;

  insert into app.billing_readiness_handoffs (tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (v_tenant_a, v_job_order_id, v_eval_id, 'e6inv1-handoff', '00000000-0000-0000-0000-000000032101', 'actora')
  returning id into v_handoff_id;

  insert into app.finance_invoices (tenant_id, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, created_by)
  values (v_tenant_a, v_account_a, v_job_order_id, v_handoff_id, 'USD', 'actora')
  returning * into v_invoice;

  update app.finance_invoices set subtotal_amount = 5000 where id = v_invoice.id returning * into v_invoice;

  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000032101', 'actora');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000032101', 'actora');
  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-15'::date, '00000000-0000-0000-0000-000000032101', 'actora');
  if v_invoice.status <> 'issued' then
    raise exception 'assertion failed: expected the fixture invoice to reach issued, got %', v_invoice.status;
  end if;

  select d.* into v_delivery from app.webhook_deliveries d
    join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
    where e.tenant_id = v_tenant_a and d.event_type_code = 'invoice.issued';
  if not found then
    raise exception 'assertion failed: expected a real webhook_deliveries row for invoice.issued';
  end if;
  if (v_delivery.payload ->> 'invoice_number') <> v_invoice.invoice_number
     or (v_delivery.payload ->> 'total_amount')::numeric <> v_invoice.total_amount
     or (v_delivery.payload ->> 'status') <> 'issued' then
    raise exception 'assertion failed: expected the delivery payload to carry the real issued invoice''s own invoice_number/total_amount/status, got %', v_delivery.payload;
  end if;
end;
$$;

\echo '>> safe no-op: tenant C has zero registered webhook endpoints -- creating a real ticket there still succeeds (app._enqueue_webhook_delivery''s own fan-out loop simply iterates zero times) and produces zero delivery rows anywhere'
do $$
declare
  v_tenant_c uuid;
  v_company_c uuid;
  v_category_id uuid;
  v_queue_id uuid;
  v_role_c uuid;
  v_role_c_draft app.role_versions;
  v_ticket app.tickets;
  v_count integer;
begin
  v_tenant_c := (select id from app.tenants where slug = 'e6webhookc');
  perform app.invite_user(v_tenant_c, '00000000-0000-0000-0000-000000032101', 'actora@e6webhookc.test', 'Actor A (Tenant C)', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where tenant_id = v_tenant_c and auth_user_id = '00000000-0000-0000-0000-000000032101'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032101', 'tenant_admin', v_tenant_c, null, 'tester');

  v_role_c := (app.create_role(v_tenant_c, 'E6C Actor', 'TKT:Edit', 'tester')).id;
  v_role_c_draft := app.create_role_version(v_role_c, 'tester');
  perform app.set_role_version_permissions(v_role_c_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action = 'Edit'), 'tester');
  perform app.publish_role_version(v_role_c_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_c, (select id from app.role_versions where role_id = v_role_c and status = 'published'), '00000000-0000-0000-0000-000000032101', '00000000-0000-0000-0000-000000032101', 'tester');

  v_company_c := (app.create_org_unit(v_tenant_c, 'company', null, 'E6WHC-CO', 'E6C Webhook Co', 'tester')).id;
  v_queue_id := (app.create_ticket_queue(v_tenant_c, v_company_c, 'E6C-Q', 'E6C Queue', null, '00000000-0000-0000-0000-000000032101', 'actora')).id;
  v_category_id := (app.create_ticket_category(v_tenant_c, 'E6C-CAT', 'E6C Category', v_queue_id, '00000000-0000-0000-0000-000000032101', 'actora')).id;
  perform app.set_ticket_category_helpdesk_visibility(v_category_id, true, '00000000-0000-0000-0000-000000032101', 'actora');

  v_ticket := app.create_helpdesk_ticket(v_tenant_c, v_category_id, 'normal', null, null, null, null, 'No endpoints registered', 'Should still work.', 'e6c-helpdesk-1', '00000000-0000-0000-0000-000000032101', 'actora');
  if v_ticket.id is null then
    raise exception 'assertion failed: expected ticket creation to succeed even with zero registered webhook endpoints';
  end if;

  select count(*) into v_count from app.webhook_deliveries d join app.webhook_endpoints e on e.id = d.webhook_endpoint_id where e.tenant_id = v_tenant_c;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero deliveries for a tenant with zero registered endpoints, got %', v_count;
  end if;
end;
$$;

\echo '>> regression: app.queue_webhook_delivery''s own public authority gate (its existing callers -- the manual send-test/replay console actions) is unaffected by the E6 refactor -- still denies a non-member actor'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'e6webhooka');
  begin
    perform app.queue_webhook_delivery(v_tenant_a, 'webhook.test', '{}'::jsonb, 'e6-manual-1', gen_random_uuid(), 'nobody');
    raise exception 'assertion failed: expected webhook_actor_unauthorized for a non-member actor calling the public app.queue_webhook_delivery directly';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> ALL PASSED: webhook-business-event-triggers.sql'
