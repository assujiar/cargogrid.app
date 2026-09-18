-- CG-AUDIT-2026-09-02 E6 (webhook half): wires the already-built, already-
-- tested webhook delivery pipeline into three real domain mutations.
--
-- The original finding ("Outbound webhooks have no publisher.
-- app.queue_webhook_delivery is referenced by 0 other database functions and
-- nothing outside its own module") was carried in the remediation backlog as
-- one undivided DEFERRED_LARGE item alongside "no GraphQL surface and no
-- OpenAPI document exist". A dedicated research pass (the same "verify
-- before trusting a deferred label" discipline that found B7's and B2a's own
-- real bounded cores) found the webhook half of that finding stale: schema
-- (app.webhook_endpoints/subscriptions/deliveries/delivery_attempts,
-- 20260719150000), HMAC-SHA256 signing, SSRF guarding at both registration
-- and dispatch time, the real outbound HTTP worker
-- (lib/webhooks/process-webhook-delivery-job.server.ts), its job-type
-- registration, its wiring into the production supervisor loop
-- (scripts/jobs/supervisor.ts's own "webhook-delivery" lane), and a reachable
-- tenant admin UI (admin/api-keys) all already exist and are already tested.
-- The literal finding was accurate on exactly one narrow point: nothing in
-- this codebase ever called app.queue_webhook_delivery from a real business
-- event -- it was dead-gated, reachable only from its own test file and from
-- the manual "send test" console action. This migration closes that one
-- gap for the three event types IAE-012's own seed data already anticipated
-- (shipment.status_changed, ticket.created, invoice.issued) by adding one
-- additional call to each of their three natural, already-existing,
-- already-tested trigger points -- no new subsystem, no schema change.
--
-- Design decision -- an internal, authority-check-free enqueue core, mirroring
-- CG-AUDIT-2026-09-02 B7's own app._evaluate_customer_credit precedent:
-- app.queue_webhook_delivery's own app.check_webhook_trigger_authority gate
-- requires the calling identity to hold active tenant membership (or Supreme
-- Admin). That gate is correct for its own existing callers (the manual
-- "send test"/"replay" console actions, where the acting identity IS the
-- literal caller triggering a webhook test). It is the WRONG gate to
-- transitively impose on a business-event trigger fired from inside
-- app._create_ticket/app.issue_finance_invoice/app.transition_shipment_order:
-- each of those functions already enforces its OWN correct authority model
-- for who may create a ticket/issue an invoice/transition a shipment order
-- (including a customer-channel ticket, filed by a customer_user-layer
-- identity whose own membership shape this migration does not need to -- and
-- must not have to -- reason about to fire a webhook side effect of an
-- already-authorized action). Re-checking a second, unrelated "may trigger
-- webhooks" permission at the trigger point would either wrongly block a
-- legitimate customer-filed ticket's webhook (if customer_user identities do
-- not satisfy app.has_active_tenant_membership) or silently do nothing
-- useful (if they do) -- pure risk, no benefit, exactly the shape of defect
-- B7's own regression caught. app._enqueue_webhook_delivery carries every
-- line of app.queue_webhook_delivery's own real logic (structural payload
-- validation, idempotency-key requirement, per-subscribed-endpoint fan-out,
-- the atomic ON CONFLICT DO NOTHING insert, the real app.jobs bridge, the
-- audit event) with only the authority check removed; app.queue_webhook_
-- delivery becomes a thin wrapper (check authority, then delegate) so its
-- own existing callers and grants are entirely unaffected.
--
-- Each of the three trigger call sites is `perform`-ed (return value
-- discarded) after its own function's real state change and audit event are
-- already committed, using an idempotency key scoped to the specific event
-- occurrence (the entity's own id for ticket/invoice, since each fires
-- exactly once per entity lifetime; the caller's own already-unique-per-
-- transition p_idempotency_key for shipment status changes, since one
-- shipment order fires this many times over its life and app.
-- queue_webhook_delivery's own idempotency is scoped forever per (tenant,
-- endpoint, idempotency_key), never per call). A tenant with zero webhook
-- endpoints subscribed to a given event type incurs a no-op loop iteration
-- count of zero -- calling this unconditionally on every ticket/invoice/
-- shipment-transition is safe and cheap for a tenant that has never
-- registered a single webhook endpoint, which is every tenant today.
--
-- Per `ERR-2026-004`: no blanket schema-wide revoke needed here (none of the
-- three replaced functions' own external signatures or grants change).

-- ===========================================================================
-- 1. app._enqueue_webhook_delivery -- extracted decision/fan-out core, no
--    authority check of its own. Byte-for-byte the same logic app.queue_
--    webhook_delivery (20260804060000 Tier C Batch 3 fix, the current live
--    version) already carries past its own authority check.
-- ===========================================================================

create function app._enqueue_webhook_delivery(
  p_tenant_id uuid,
  p_event_type_code text,
  p_payload jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_triggered_by text
)
returns setof app.webhook_deliveries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_endpoint record;
  v_delivery app.webhook_deliveries;
begin
  if not app.validate_config_value(p_payload) then
    raise exception 'webhook_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'webhook_missing_idempotency_key: idempotency_key is required'
      using errcode = 'check_violation';
  end if;

  for v_endpoint in
    select we.id from app.webhook_endpoints we
    join app.webhook_subscriptions ws on ws.webhook_endpoint_id = we.id
    where we.tenant_id = p_tenant_id and we.status = 'active' and ws.event_type_code = p_event_type_code
  loop
    insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, next_attempt_at)
    values (p_tenant_id, v_endpoint.id, p_event_type_code, p_payload, p_idempotency_key, now())
    on conflict (tenant_id, webhook_endpoint_id, idempotency_key) do nothing
    returning * into v_delivery;

    if found then
      perform app.enqueue_job(
        p_tenant_id, 'webhook_retry',
        jsonb_build_object('delivery_id', v_delivery.id),
        0, 'webhook-delivery:' || v_delivery.id::text, v_delivery.max_attempts,
        p_actor_auth_user_id, p_triggered_by
      );

      perform app.capture_audit_event(
        p_tenant_id, p_actor_auth_user_id, p_triggered_by, 'queue_webhook_delivery',
        'app.webhook_deliveries', v_delivery.id, 'success', null, null,
        jsonb_build_object('id', v_delivery.id, 'webhook_endpoint_id', v_delivery.webhook_endpoint_id, 'event_type_code', v_delivery.event_type_code)
      );
    else
      select * into v_delivery
      from app.webhook_deliveries
      where tenant_id = p_tenant_id and webhook_endpoint_id = v_endpoint.id and idempotency_key = p_idempotency_key;
    end if;

    return next v_delivery;
  end loop;

  return;
end;
$$;

comment on function app._enqueue_webhook_delivery is
  'CG-AUDIT-2026-09-02 E6: internal decision/fan-out core for app.queue_webhook_delivery, no authority check of its own -- callable by any already-gated business-event trigger (app._create_ticket, app.issue_finance_invoice, app.transition_shipment_order) without imposing a second, transitive "may trigger webhooks" requirement on top of that trigger''s own real authority model. Mirrors app._evaluate_customer_credit''s (B7) identical reasoning. Never call this directly from a context that has not already established its own authority to perform the underlying action.';

revoke execute on function app._enqueue_webhook_delivery(uuid, text, jsonb, text, uuid, text) from public;
grant execute on function app._enqueue_webhook_delivery(uuid, text, jsonb, text, uuid, text) to service_role;

-- ===========================================================================
-- 2. app.queue_webhook_delivery -- now a thin wrapper: check authority, then
--    delegate. External signature, grants, and behavior for every existing
--    caller (manual "send test"/"replay" console actions, this function's
--    own db-test file) are unchanged.
-- ===========================================================================

create or replace function app.queue_webhook_delivery(
  p_tenant_id uuid,
  p_event_type_code text,
  p_payload jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_triggered_by text
)
returns setof app.webhook_deliveries
language plpgsql
as $$
begin
  if not app.check_webhook_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app._enqueue_webhook_delivery(p_tenant_id, p_event_type_code, p_payload, p_idempotency_key, p_actor_auth_user_id, p_triggered_by);
end;
$$;

comment on function app.queue_webhook_delivery is
  'PLT-129, extended by IAE-012, Tier C Batch 3 fix, CG-AUDIT-2026-09-02 E6: thin wrapper over app._enqueue_webhook_delivery (E6''s own internal decision core, no authority check of its own) -- adds the app.check_webhook_trigger_authority gate this function''s own existing callers (manual send-test/replay console actions) still correctly require. A real business-event trigger calls app._enqueue_webhook_delivery directly instead, per this migration''s own header.';

-- ===========================================================================
-- 3. app._create_ticket -- adds one app._enqueue_webhook_delivery call for
--    'ticket.created', after the existing audit event, before returning.
--    Every other line is byte-for-byte unchanged from the current live
--    version (20260731100000_extend_ticketing_helpdesk_channel.sql).
-- ===========================================================================

create or replace function app._create_ticket(
  p_tenant_id uuid,
  p_channel text,
  p_requester_employee_id uuid,
  p_requester_customer_account_id uuid,
  p_category_id uuid,
  p_queue_id uuid,
  p_priority text,
  p_subject text,
  p_body text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_severity text default null,
  p_product_area text default null,
  p_environment text default null,
  p_external_reference text default null
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_resolved_queue_id uuid;
  v_priority text := coalesce(p_priority, 'normal');
  v_existing app.tickets;
  v_existing_body text;
  v_ticket app.tickets;
  v_number text;
begin
  if p_channel is null or not (p_channel = any (array['internal', 'customer', 'helpdesk'])) then
    raise exception 'invalid_channel: % is not one of internal/customer/helpdesk', p_channel using errcode = 'check_violation';
  end if;
  if p_channel = 'internal' then
    if p_requester_employee_id is null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: internal channel requires exactly a requester_employee_id' using errcode = 'check_violation';
    end if;
  elsif p_channel = 'customer' then
    if p_requester_customer_account_id is null or p_requester_employee_id is not null then
      raise exception 'invalid_requester_identity: customer channel requires exactly a requester_customer_account_id' using errcode = 'check_violation';
    end if;
  else
    if p_requester_employee_id is not null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: helpdesk channel requires neither a requester_employee_id nor a requester_customer_account_id (the tenant itself is the requester)' using errcode = 'check_violation';
    end if;
  end if;

  if p_subject is null or length(trim(p_subject)) = 0 then
    raise exception 'subject_required: a non-empty subject is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty ticket description is required' using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;

  select * into v_category from app.ticket_categories where id = p_category_id and tenant_id = p_tenant_id and status = 'active';
  if not found then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  if p_channel in ('internal', 'customer') then
    v_resolved_queue_id := coalesce(p_queue_id, v_category.default_queue_id);
    if v_resolved_queue_id is null then
      raise exception 'queue_required: no queue was supplied and category % has no default queue', p_category_id using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.ticket_queues where id = v_resolved_queue_id and tenant_id = p_tenant_id and status = 'active') then
      raise exception 'queue_not_available: % is not an active queue for this tenant', v_resolved_queue_id using errcode = 'no_data_found';
    end if;
  else
    -- HRT-288 (decision 2): a helpdesk ticket's queue is ALWAYS null at
    -- creation -- Platform-internal routing (app.support_queues) is a
    -- staff-side triage action performed later (app.
    -- transfer_helpdesk_support_queue), never chosen or forged by the
    -- filing tenant.
    v_resolved_queue_id := null;
  end if;

  if p_idempotency_key is not null then
    if p_channel = 'internal' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
    elsif p_channel = 'customer' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
        and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
    else
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'helpdesk' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    end if;
    if found then
      select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_existing.id order by m.created_at asc limit 1;
      if v_existing.category_id = p_category_id and coalesce(v_existing.queue_id::text, '') = coalesce(v_resolved_queue_id::text, '') and v_existing.priority = v_priority
         and v_existing.subject = p_subject and coalesce(v_existing_body, '') = p_body then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different ticket', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  v_number := app.next_ticket_number(p_tenant_id);

  begin
    insert into app.tickets (
      tenant_id, ticket_number, channel, category_id, queue_id, priority, subject, status,
      requester_employee_id, requester_customer_account_id, requested_by_auth_user_id, requested_by,
      idempotency_key, created_by, severity, product_area, environment, external_reference
    ) values (
      p_tenant_id, v_number, p_channel, p_category_id, v_resolved_queue_id, v_priority, p_subject, 'new',
      p_requester_employee_id, p_requester_customer_account_id, p_actor_auth_user_id, p_actor_label,
      p_idempotency_key, p_actor_label, p_severity, p_product_area, p_environment, p_external_reference
    )
    returning * into v_ticket;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        if p_channel = 'internal' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
        elsif p_channel = 'customer' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
            and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
        else
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'helpdesk' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
        end if;
        if found then
          select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_ticket.id order by m.created_at asc limit 1;
          if v_ticket.category_id = p_category_id and coalesce(v_ticket.queue_id::text, '') = coalesce(v_resolved_queue_id::text, '') and v_ticket.priority = v_priority
             and v_ticket.subject = p_subject and coalesce(v_existing_body, '') = p_body then
            return v_ticket;
          end if;
        end if;
      end if;
      raise;
  end;

  insert into app.ticket_messages (tenant_id, ticket_id, visibility, body, author_auth_user_id, author_label, author_role)
  values (p_tenant_id, v_ticket.id, 'public', p_body, p_actor_auth_user_id, p_actor_label, 'requester');

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_ticket.id, 'create', null, 'new', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket',
    'app.tickets', v_ticket.id, 'success', null, null, app.ticket_audit_projection(v_ticket)
  );

  -- CG-AUDIT-2026-09-02 E6: real business-event trigger, added -- see this
  -- migration's own header for why this is app._enqueue_webhook_delivery
  -- (no authority check) rather than the public app.queue_webhook_delivery.
  perform app._enqueue_webhook_delivery(
    p_tenant_id, 'ticket.created', app.ticket_audit_projection(v_ticket),
    'ticket-created:' || v_ticket.id::text, p_actor_auth_user_id, p_actor_label
  );

  return v_ticket;
end;
$$;

comment on function app._create_ticket is
  'HRT-286/287/288 (decision 4/ISS-2026-085 fully resolved), CG-AUDIT-2026-09-02 E6: the shared ticket-creation engine, now taking p_channel in (''internal'',''customer'',''helpdesk''), validated to have EXACTLY the requester identity shape matching that channel (belt-and-suspenders alongside the table CHECK tickets_requester_identity_shape). Queue resolution/requirement is SKIPPED entirely for helpdesk (queue_id always null at creation, decision 2). Called by app.create_ticket/app.create_ticket_for_employee (channel:=''internal''), app.create_customer_ticket (channel:=''customer''), and app.create_helpdesk_ticket (channel:=''helpdesk''). Idempotency replay is keyed per channel: requester_employee_id (internal); requested_by_auth_user_id + requester_customer_account_id (customer); requested_by_auth_user_id alone (helpdesk -- there is no per-ticket customer-account-style scope to additionally key on, since the requester IS the tenant). E6: fires ticket.created via app._enqueue_webhook_delivery once a ticket is genuinely newly created (never on an idempotent replay, which returns early above).';

grant execute on function app._create_ticket(uuid, text, uuid, uuid, uuid, uuid, text, text, text, text, uuid, text, text, text, text, text) to service_role;

-- ===========================================================================
-- 4. app.issue_finance_invoice -- adds one app._enqueue_webhook_delivery
--    call for 'invoice.issued', after the existing audit event, before
--    returning. Every other line is byte-for-byte unchanged from the
--    current live version
--    (20260907130000_fix_withholding_tax_deducted_not_added_iss_b5.sql).
-- ===========================================================================

create or replace function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_invoices
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
  v_tax_code app.finance_tax_codes;
  v_net_collectible numeric(14, 2);
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 (Financial Integrity Audit) finding 2: a job order may reach `issued` for at
  -- most one invoice at a time -- backed by finance_invoices_job_order_issued_unique
  -- (Tier C fix), not merely this application-level pre-check. Draft/submitted/approved
  -- invoices from a legitimate re-handoff (OPS-181) remain freely creatable and discardable
  -- (see the migration header); this is the actual AR/GL posting boundary, so it is the one
  -- place a second full-amount bill for the same job's revenue must be refused.
  if exists (
    select 1 from app.finance_invoices
    where tenant_id = v_invoice.tenant_id and job_order_id = v_invoice.job_order_id
      and id <> v_invoice.id and status = 'issued'
  ) then
    raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  -- CG-AUDIT-2026-09-02 B5: the amount actually collectible in cash is total_amount
  -- LESS any withholding_tax_amount -- the customer withholds that portion at source and
  -- remits it directly to the tax authority, so it is never a real AR balance CargoGrid
  -- can collect or age. See this fix's own migration header.
  v_net_collectible := v_invoice.total_amount - v_invoice.withholding_tax_amount;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_net_collectible, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the net amount actually collectible (CG-AUDIT-2026-09-02
  -- B5: total_amount minus withholding_tax_amount); credit revenue for the subtotal;
  -- credit each ADDED (non-withholding) tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured); DEBIT each WITHHELD tax
  -- line's own governed recoverable account (or the withholding_tax_receivable_default
  -- posting-map key) -- a creditable asset to CargoGrid, never a payable, mirroring app.
  -- post_finance_vendor_bill's own established recoverable_account_id-debit pattern for
  -- input tax credits on the AP side. The journal still balances: net-collectible AR debit
  -- plus the withholding-receivable debit sums to total_amount, exactly matching revenue
  -- credit plus any added-tax credit.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_net_collectible, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    v_tax_code := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id;
    end if;
    if v_tax_line.tax_code_id is not null then
      select * into v_tax_code from app.finance_tax_codes where id = v_tax_line.tax_code_id;
    end if;
    -- CG-AUDIT-2026-09-02 B5 (found while writing this fix's own regression test, not
    -- previously exercised by any test before it -- every prior fixture left both
    -- output_account_id and recoverable_account_id unconfigured): a plpgsql row variable's
    -- own `IS NOT NULL` is true only when EVERY field of the row is non-null (SQL composite-
    -- type semantics), never merely "was a row found". app.finance_tax_rule_versions and
    -- app.finance_tax_codes both carry other nullable columns (e.g. currency) that are null
    -- on an ordinary fetched row, so `v_tax_rule is not null` / `v_tax_code is not null`
    -- would silently read as false even when the SELECT above found a real row -- checking
    -- each row's own guaranteed-NOT-NULL primary key column instead is the correct,
    -- established idiom (mirrors every `if not found then` check elsewhere in this
    -- codebase, just phrased for a value read after the block that set it rather than
    -- immediately after the SELECT itself).
    if v_tax_code.id is not null and v_tax_code.tax_type = 'withholding' then
      if v_tax_rule.id is not null and v_tax_rule.recoverable_account_id is not null then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
      else
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'withholding_tax_receivable_default', 'direction', 'debit', 'amount', v_tax_line.amount));
      end if;
    elsif v_tax_rule.id is not null and v_tax_rule.output_account_id is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- HDN-374 Tier C finding 2: a genuine race between the exists() pre-check above and this
  -- update (two concurrent issue_finance_invoice calls for two DIFFERENT invoices on the
  -- SAME job order, each already past its own exists() check before either commits) is
  -- caught here by finance_invoices_job_order_issued_unique -- the loser's own update
  -- raises unique_violation instead of silently succeeding; re-raised as the same named
  -- exception the non-concurrent pre-check above already gives, never a raw unique_violation.
  begin
    update app.finance_invoices
      set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
          posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
      where id = p_invoice_id
      returning * into v_invoice;
  exception
    when unique_violation then
      raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  -- CG-AUDIT-2026-09-02 E6: real business-event trigger, added -- see this
  -- migration's own header for why this is app._enqueue_webhook_delivery
  -- (no authority check) rather than the public app.queue_webhook_delivery.
  -- A curated field set, never the raw row, is sent to a tenant-registered
  -- external endpoint.
  perform app._enqueue_webhook_delivery(
    v_invoice.tenant_id, 'invoice.issued',
    jsonb_build_object(
      'id', v_invoice.id,
      'invoice_number', v_invoice.invoice_number,
      'customer_account_id', v_invoice.customer_account_id,
      'job_order_id', v_invoice.job_order_id,
      'currency', v_invoice.currency,
      'total_amount', v_invoice.total_amount,
      'issue_date', v_invoice.issue_date,
      'due_date', v_invoice.due_date,
      'status', v_invoice.status
    ),
    'invoice-issued:' || v_invoice.id::text, p_actor_auth_user_id, p_actor_label
  );

  return v_invoice;
end;
$function$;

-- ===========================================================================
-- 5. app.transition_shipment_order -- adds one app._enqueue_webhook_delivery
--    call for 'shipment.status_changed', after the existing audit event,
--    before returning. Every other line is byte-for-byte unchanged from the
--    current live version (20260902201000_harden_tenant_id_disclosure_
--    operations.sql -- the ISS-2026-146 tenant-membership fold-in and the
--    ATW-032/ISS-2026-034 swallowed-lost-update fix, both carried forward
--    here; an earlier draft of this migration was caught, before commit,
--    sourcing the pre-ISS-2026-146/pre-ATW-032 body from an older migration
--    -- fixed by re-deriving from the true latest definition).
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.transition_shipment_order(p_shipment_order_id uuid, p_to_status text, p_expected_version integer, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_transition app.shipment_status_transitions;
  v_from_status text;
  v_next_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_transition from app.shipment_status_transitions
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing_transition.to_status is distinct from p_to_status then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different status transition (transition to %, not to %)', p_idempotency_key, v_existing_transition.to_status, p_to_status
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_shipment.status;

  -- The canonical matrix. 'held'/'cancelled' branch off most active states; 'held'
  -- resumes only into its own recorded held_from_status; 'closed' may only reopen
  -- into 'delivered'/'epod' (Supreme-only, checked below), never further back.
  if v_from_status = 'held' then
    if p_to_status <> v_shipment.held_from_status and p_to_status <> 'cancelled' then
      raise exception 'invalid_transition: a held shipment order % may only resume into % or cancel', p_shipment_order_id, v_shipment.held_from_status
        using errcode = 'check_violation';
    end if;
  elsif v_from_status = 'closed' then
    if p_to_status not in ('delivered', 'epod') then
      raise exception 'invalid_transition: shipment order % is closed and may only reopen into delivered or epod', p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)'
        using errcode = 'insufficient_privilege';
    end if;
  elsif v_from_status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled, a terminal state', p_shipment_order_id using errcode = 'check_violation';
  elsif v_from_status = 'draft' and p_to_status in ('confirmed', 'cancelled') then
    null;
  elsif v_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit') and p_to_status in ('held', 'cancelled') then
    null;
  elsif v_from_status = 'confirmed' and p_to_status = 'planned' then
    null;
  elsif v_from_status = 'planned' and p_to_status = 'assigned' then
    null;
  elsif v_from_status = 'assigned' and p_to_status = 'dispatched' then
    null;
  elsif v_from_status = 'dispatched' and p_to_status = 'in_transit' then
    null;
  elsif v_from_status = 'in_transit' and p_to_status = 'delivered' then
    null;
  elsif v_from_status = 'delivered' and p_to_status in ('epod', 'cancelled') then
    null;
  elsif v_from_status = 'epod' and p_to_status = 'closed' then
    null;
  else
    raise exception 'invalid_transition: % -> % is not a legal Shipment Order transition', v_from_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if p_to_status in ('held', 'cancelled') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('delivered', 'epod', 'closed') and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: a non-empty evidence reference is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_next_status := p_to_status;

  begin
    insert into app.shipment_status_transitions (
      tenant_id, shipment_order_id, from_status, to_status, reason, evidence_ref, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, v_from_status, v_next_status, p_reason, p_evidence_ref, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
      return v_shipment;
  end;

  update app.shipment_orders
  set status = v_next_status,
      held_from_status = case when v_next_status = 'held' then v_from_status else null end
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null,
    jsonb_build_object('status', v_from_status),
    jsonb_build_object('status', v_next_status, 'reason', p_reason, 'evidence_ref', p_evidence_ref)
  );

  -- CG-AUDIT-2026-09-02 E6: real business-event trigger, added -- see this
  -- migration's own header for why this is app._enqueue_webhook_delivery
  -- (no authority check) rather than the public app.queue_webhook_delivery,
  -- and why the idempotency key is scoped to this specific transition
  -- (p_idempotency_key, already unique per (tenant, shipment_order_id) via
  -- app.shipment_status_transitions' own unique constraint) rather than to
  -- the shipment order alone -- one shipment order fires this event many
  -- times over its life.
  perform app._enqueue_webhook_delivery(
    v_shipment.tenant_id, 'shipment.status_changed',
    jsonb_build_object(
      'shipment_order_id', v_shipment.id,
      'from_status', v_from_status,
      'to_status', v_next_status,
      'reason', p_reason,
      'evidence_ref', p_evidence_ref,
      'changed_at', now()
    ),
    'shipment-status-changed:' || p_shipment_order_id::text || ':' || p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  );

  return v_shipment;
end;
$function$;
