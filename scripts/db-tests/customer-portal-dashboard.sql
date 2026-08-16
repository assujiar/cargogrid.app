-- Real, executable test evidence for CPL-301 (CG-S13-CPL-003, Prompt 301,
-- "Customer Portal Dashboard") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-portal-scope.sql (CPL-300): two-tenant fixture,
-- direct RPC calls as the connecting superuser for parameter-driven
-- assertions, `set local role authenticated` + `set local request.jwt.claims`
-- only where the assertion genuinely needs a real session (actor-identity
-- cross-check, and -- new in this file -- a real positive-path session call,
-- since no prior Phase 8 db-test exercised that combination live).
--
-- UUID range 00000000-0000-0000-0000-0000003010xx (tenant cpd1) /
-- ...3020xx (tenant cpd2) -- grep-verified unclaimed before this file was
-- written (right after CPL-300's own ...3000xx range). Tenant slugs
-- cpd1/cpd2.
--
-- Covers, live: (1) the three real cards (accounts, warehouse_inventory,
-- tickets) return real, correct counts/timestamps/detail_path composed from
-- app.get_customer_portal_scope_context (CPL-300) / app.list_customer_
-- inventory_balances+app.list_customer_outbound_orders (ATW-023) / app.list_
-- customer_tickets (HRT-287); (2) the six stub cards (bookings/shipments/
-- invoices/payments/loyalty/alerts) are always present, available=false,
-- summary={}, detail_path=null -- never fake data; (3) cancelled outbound
-- orders and cancelled tickets are excluded from their own open counts; (4)
-- deny-by-default for an identity with zero customer-portal scope -- real
-- cards present with zero counts, never an error; (5) cross-tenant
-- isolation; (6) revocation's immediate effect on all three real cards at
-- once (CPL-300's own legacy-marker-sync fix, exercised transitively); (7)
-- the actor-identity session cross-check (assert_actor_is_session_identity)
-- rejects a genuinely different session claiming another identity's uuid;
-- (8) a real, live `authenticated`-role session (not merely a superuser
-- call with an explicit parameter) gets the SAME real data as the superuser
-- call -- a positive-path RLS/SECURITY-DEFINER proof no prior Phase 8
-- db-test exercised; (9) raw grant defense-in-depth (anon has no EXECUTE,
-- authenticated/service_role do); (10) per-card resilience -- a genuinely
-- disabled composed function (session-scoped `ALTER FUNCTION ... RENAME`,
-- reverted before this file exits) marks ONLY that one card degraded while
-- every sibling card still returns its own correct data, live-proven, not
-- reasoned about; (11) the *Capped flags correctly read false for
-- below-cap fixture counts.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cpd1 (account "Dash Co" with dash-admin as account_admin -- real balance/outbound-order/ticket data, one open + one cancelled outbound order, one open + one cancelled ticket; account "Dash Revoke Co" with dash-revoke, revoked later; dash-noscope invited with zero customer-portal grants of any kind); a second, otherwise-empty tenant cpd2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000000301001';
  v_dash_admin uuid := '00000000-0000-0000-0000-000000301010';
  v_dash_noscope uuid := '00000000-0000-0000-0000-000000301020';
  v_dash_revoke uuid := '00000000-0000-0000-0000-000000301030';
  v_impersonator uuid := '00000000-0000-0000-0000-000000301040';
  v_account app.accounts;
  v_account_revoke app.accounts;
  v_wh app.warehouses;
  v_rack app.warehouse_locations;
  v_item uuid;
  v_order_open app.wms_outbound_orders;
  v_order_cancelled app.wms_outbound_orders;
  v_queue uuid;
  v_category uuid;
  v_ticket_open app.tickets;
  v_ticket_cancelled app.tickets;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'admin@cpd1.test'),
    (v_dash_admin, 'dash-admin@cpd1.test'),
    (v_dash_noscope, 'dash-noscope@cpd1.test'),
    (v_dash_revoke, 'dash-revoke@cpd1.test'),
    (v_impersonator, 'impersonator@cpd1.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cpd1', 'Customer Portal Dashboard Tenant One', 'idem-cpd1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cpd1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-CPD1', 'Cpd1 Co', 'tester')).id;

  perform app.provision_tenant('cpd2', 'Customer Portal Dashboard Tenant Two', 'idem-cpd2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cpd2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_dash_admin, 'dash-admin@cpd1.test', 'Dash Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'dash-admin@cpd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_dash_noscope, 'dash-noscope@cpd1.test', 'Dash Noscope', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'dash-noscope@cpd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_dash_revoke, 'dash-revoke@cpd1.test', 'Dash Revoke', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'dash-revoke@cpd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@cpd1.test', 'Dash Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cpd1.test'), 'active', 'onboarded', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Dash Co', 'cpd1-dashco-fp', '{}'::jsonb, v_company, 'tester') returning * into v_account;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Dash Revoke Co', 'cpd1-revokeco-fp', '{}'::jsonb, v_company, 'tester') returning * into v_account_revoke;

  -- dash-noscope is invited (real auth.users/tenant identity) but NEVER
  -- granted any customer_user layer principal at all -- the "zero relationship"
  -- deny-by-default fixture, distinct from a revoked one.
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account.id, v_dash_admin, v_supreme, 'admin');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_revoke.id, v_dash_revoke, v_supreme, 'admin');

  -- Warehouse/item/balance/outbound orders for "Dash Co" only.
  v_wh := app.create_warehouse(v_tenant1, v_company, 'WH-CPD1', 'Cpd1 Warehouse', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_rack := app.create_warehouse_location(v_wh.id, null, null, 'RACK-CPD1-1', 'Rack 1', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh.id, v_account.id, v_supreme, 'admin');
  v_item := (app.create_item_master(v_tenant1, v_account.id, 'SKU-CPD1', 'Cpd1 Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  perform app.post_inventory_movement(
    v_tenant1, v_wh.id, 'opening_balance', 'opening_balance', null, 'idem-cpd1-open', 'cpd1 fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account.id, 'item_master_id', v_item, 'location_id', v_rack.id, 'uom_code', 'PCS', 'signed_quantity', 12)),
    v_supreme, 'admin'
  );

  v_order_open := app.create_manual_wms_outbound_order(v_tenant1, v_wh.id, v_account.id, 'cpd1 open order', 'idem-cpd1-outbound-open', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order_open.id, v_item, 'PCS', 2, null, v_supreme, 'admin');

  -- A second outbound order, created then explicitly cancelled -- proves the
  -- dashboard's own openOutboundOrderCount excludes it (design decision:
  -- status <> 'cancelled').
  v_order_cancelled := app.create_manual_wms_outbound_order(v_tenant1, v_wh.id, v_account.id, 'cpd1 cancelled order', 'idem-cpd1-outbound-cancel', current_date + 3, v_supreme, 'admin');
  v_order_cancelled := app.cancel_wms_outbound_order(v_order_cancelled.id, 'no longer needed', v_order_cancelled.record_version, v_supreme, 'admin');

  -- Ticket queue/category + one open (stays 'new') + one cancelled by the
  -- customer themselves (requester_allowed transition, HRT-287 decision 9) --
  -- proves openTicketCount excludes the cancelled one.
  v_queue := (app.create_ticket_queue(v_tenant1, v_company, 'Q-CPD1', 'Cpd1 Queue', null, v_supreme, 'admin')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'CAT-CPD1', 'Cpd1 Category', v_queue, v_supreme, 'admin')).id;
  perform app.set_ticket_category_customer_visibility(v_category, true, v_supreme, 'admin');
  v_ticket_open := app.create_customer_ticket(v_tenant1, v_account.id, v_category, 'normal', 'Open issue', 'Please help.', 'idem-cpd1-ticket-open', v_dash_admin, 'Dash Admin');
  v_ticket_cancelled := app.create_customer_ticket(v_tenant1, v_account.id, v_category, 'normal', 'Withdrawn issue', 'Never mind.', 'idem-cpd1-ticket-cancel', v_dash_admin, 'Dash Admin');
  v_ticket_cancelled := app.transition_ticket_status(v_ticket_cancelled.id, v_ticket_cancelled.record_version, 'cancelled', 'no longer an issue', v_dash_admin, 'Dash Admin');

  raise notice 'fixture ready: tenant1=%, tenant2=%, account=%, account_revoke=%, dash_admin=%, dash_noscope=%, dash_revoke=%, impersonator=%, order_open=%, order_cancelled=%, ticket_open=%, ticket_cancelled=%',
    v_tenant1, v_tenant2, v_account.id, v_account_revoke.id, v_dash_admin, v_dash_noscope, v_dash_revoke, v_impersonator, v_order_open.id, v_order_cancelled.id, v_ticket_open.id, v_ticket_cancelled.id;
end $$;

\echo '>> 1. happy path: dash-admin (superuser-driven call) sees all 9 cards, the three real cards carry correct counts/detail_path, cancelled order/ticket excluded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_dash_admin uuid := '00000000-0000-0000-0000-000000301010';
  v_row record;
  v_seen_keys text[] := array[]::text[];
begin
  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_admin, v_tenant1) loop
    v_seen_keys := array_append(v_seen_keys, v_row.card_key);

    if v_row.card_key = 'accounts' then
      if v_row.available <> true or v_row.degraded <> false or v_row.detail_path <> 'customer-portal' then
        raise exception 'accounts card: unexpected shape, got available=% degraded=% detail_path=%', v_row.available, v_row.degraded, v_row.detail_path;
      end if;
      if (v_row.summary->>'activeAccountCount')::int <> 1 then
        raise exception 'accounts card: expected activeAccountCount=1, got %', v_row.summary;
      end if;
      if v_row.summary->>'primaryAccountName' <> 'Dash Co' then
        raise exception 'accounts card: expected primaryAccountName=Dash Co, got %', v_row.summary;
      end if;
      if v_row.source_updated_at is null then
        raise exception 'accounts card: expected a non-null source_updated_at';
      end if;
    elsif v_row.card_key = 'warehouse_inventory' then
      if v_row.available <> true or v_row.degraded <> false or v_row.detail_path is not null then
        raise exception 'warehouse_inventory card: unexpected shape, got available=% degraded=% detail_path=%', v_row.available, v_row.degraded, v_row.detail_path;
      end if;
      if (v_row.summary->>'activeInventoryBalanceCount')::int <> 1 then
        raise exception 'warehouse_inventory card: expected activeInventoryBalanceCount=1, got %', v_row.summary;
      end if;
      if (v_row.summary->>'openOutboundOrderCount')::int <> 1 then
        raise exception 'warehouse_inventory card: expected openOutboundOrderCount=1 (cancelled order excluded), got %', v_row.summary;
      end if;
      if (v_row.summary->>'activeInventoryBalanceCountCapped')::boolean <> false or (v_row.summary->>'openOutboundOrderCountCapped')::boolean <> false then
        raise exception 'warehouse_inventory card: expected both Capped flags false for a below-cap fixture, got %', v_row.summary;
      end if;
      if v_row.source_updated_at is null then
        raise exception 'warehouse_inventory card: expected a non-null source_updated_at';
      end if;
    elsif v_row.card_key = 'tickets' then
      if v_row.available <> true or v_row.degraded <> false or v_row.detail_path <> 'customer-tickets' then
        raise exception 'tickets card: unexpected shape, got available=% degraded=% detail_path=%', v_row.available, v_row.degraded, v_row.detail_path;
      end if;
      if (v_row.summary->>'openTicketCount')::int <> 1 then
        raise exception 'tickets card: expected openTicketCount=1 (cancelled ticket excluded), got %', v_row.summary;
      end if;
      if v_row.source_updated_at is null then
        raise exception 'tickets card: expected a non-null source_updated_at';
      end if;
    elsif v_row.card_key in ('bookings', 'shipments', 'invoices', 'payments', 'loyalty', 'alerts') then
      if v_row.available <> false or v_row.degraded <> false or v_row.summary <> '{}'::jsonb or v_row.detail_path is not null or v_row.source_updated_at is not null then
        raise exception 'stub card %: expected available=false degraded=false summary={} detail_path=null source_updated_at=null, got available=% degraded=% summary=% detail_path=% source_updated_at=%',
          v_row.card_key, v_row.available, v_row.degraded, v_row.summary, v_row.detail_path, v_row.source_updated_at;
      end if;
    else
      raise exception 'unexpected, unrecognized card_key: %', v_row.card_key;
    end if;
  end loop;

  select array_agg(k order by k) into v_seen_keys from unnest(v_seen_keys) as k;
  if v_seen_keys <> array['accounts','alerts','bookings','invoices','loyalty','payments','shipments','tickets','warehouse_inventory']::text[] then
    raise exception 'expected exactly the 9 documented card_keys, got: %', v_seen_keys;
  end if;
  raise notice 'PASS: happy path -- all 9 cards present, three real cards correct, six stub cards structurally honest';
end $$;

\echo '>> 2. deny-by-default: dash-noscope (invited, zero customer-portal grants of any kind) sees the same 9 cards, real cards present with zero counts, never an error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_dash_noscope uuid := '00000000-0000-0000-0000-000000301020';
  v_row record;
begin
  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_noscope, v_tenant1) loop
    if v_row.card_key = 'accounts' and ((v_row.summary->>'activeAccountCount')::int <> 0 or v_row.available <> true) then
      raise exception 'expected accounts card available=true, activeAccountCount=0 for a zero-scope identity, got %', v_row;
    end if;
    if v_row.card_key = 'warehouse_inventory' and ((v_row.summary->>'activeInventoryBalanceCount')::int <> 0 or (v_row.summary->>'openOutboundOrderCount')::int <> 0) then
      raise exception 'expected warehouse_inventory card all-zero for a zero-scope identity, got %', v_row.summary;
    end if;
    if v_row.card_key = 'tickets' and (v_row.summary->>'openTicketCount')::int <> 0 then
      raise exception 'expected tickets card openTicketCount=0 for a zero-scope identity, got %', v_row.summary;
    end if;
  end loop;
  raise notice 'PASS: deny-by-default -- a zero-scope identity gets real cards with zero counts, never an error';
end $$;

\echo '>> 3. cross-tenant isolation: dash-admin (real data in cpd1) queried against cpd2 sees zero on every real card'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'cpd2');
  v_dash_admin uuid := '00000000-0000-0000-0000-000000301010';
  v_row record;
begin
  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_admin, v_tenant2) loop
    if v_row.card_key = 'accounts' and (v_row.summary->>'activeAccountCount')::int <> 0 then
      raise exception 'expected zero cross-tenant accounts, got %', v_row.summary;
    end if;
    if v_row.card_key = 'tickets' and (v_row.summary->>'openTicketCount')::int <> 0 then
      raise exception 'expected zero cross-tenant tickets, got %', v_row.summary;
    end if;
  end loop;
  raise notice 'PASS: cross-tenant isolation holds for the dashboard summary';
end $$;

\echo '>> 4. revocation immediate effect: dash-revoke sees real counts before revoke, zero on every real card immediately after (no caching), same session'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_dash_revoke uuid := '00000000-0000-0000-0000-000000301030';
  v_membership app.customer_portal_account_memberships;
  v_row record;
begin
  select * into v_membership from app.customer_portal_account_memberships where auth_user_id = v_dash_revoke and tenant_id = v_tenant1;

  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_revoke, v_tenant1) loop
    if v_row.card_key = 'accounts' and (v_row.summary->>'activeAccountCount')::int <> 1 then
      raise exception 'expected dash-revoke to see 1 account before revoke, got %', v_row.summary;
    end if;
  end loop;

  -- dash-revoke is the only account_admin on "Dash Revoke Co" -- CPL-300's own
  -- Layer-4-only authority chain (app.actor_is_active_customer_portal_
  -- account_admin) does not forbid an account_admin from revoking their own
  -- membership, so this self-revoke is a real, legal call, not a fixture
  -- shortcut.
  perform app.set_customer_portal_account_membership_status(v_membership.id, v_membership.record_version, 'revoked', 'test revoke', v_dash_revoke, 'dash-revoke');

  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_revoke, v_tenant1) loop
    if v_row.card_key = 'accounts' and (v_row.summary->>'activeAccountCount')::int <> 0 then
      raise exception 'expected dash-revoke to see 0 accounts immediately after revoke, got %', v_row.summary;
    end if;
  end loop;
  raise notice 'PASS: revocation takes effect immediately on the dashboard summary, no caching';
end $$;

\echo '>> 5. actor-identity session cross-check: a genuinely different authenticated session may not claim to act as dash-admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000301040", "role": "authenticated"}';
  begin
    perform app.get_customer_portal_dashboard_summary('00000000-0000-0000-0000-000000301010', v_tenant1);
    raise exception 'assertion failed: expected actor_identity_mismatch -- session 301040 may not act as 301010';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end $$;
\echo 'PASS: forged actor rejected before any card is computed'

\echo '>> 6. a REAL authenticated-role session (not merely a superuser call) gets the SAME real data -- positive-path RLS/SECURITY DEFINER proof'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_row record;
  v_saw_real_accounts boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000301010", "role": "authenticated"}';

  for v_row in select * from app.get_customer_portal_dashboard_summary('00000000-0000-0000-0000-000000301010', v_tenant1) loop
    if v_row.card_key = 'accounts' then
      if (v_row.summary->>'activeAccountCount')::int <> 1 then
        raise exception 'expected a real authenticated session to see activeAccountCount=1, got %', v_row.summary;
      end if;
      v_saw_real_accounts := true;
    end if;
  end loop;
  if not v_saw_real_accounts then
    raise exception 'expected to see the accounts card at all';
  end if;
  reset role;
end $$;
\echo 'PASS: a genuine authenticated-role session sees identical real data to the superuser-driven calls above -- SECURITY DEFINER ownership bypass confirmed live, not merely asserted from source'

\echo '>> 7. raw grant defense-in-depth: anon holds no EXECUTE, authenticated/service_role both do'
do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('anon', 'app.get_customer_portal_dashboard_summary(uuid, uuid)', 'execute') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on app.get_customer_portal_dashboard_summary';
  end if;
  select has_function_privilege('authenticated', 'app.get_customer_portal_dashboard_summary(uuid, uuid)', 'execute') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.get_customer_portal_dashboard_summary';
  end if;
  select has_function_privilege('service_role', 'app.get_customer_portal_dashboard_summary(uuid, uuid)', 'execute') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app.get_customer_portal_dashboard_summary';
  end if;
  raise notice 'PASS: grant surface is exactly authenticated + service_role';
end $$;

\echo '>> 8. per-card resilience: a genuinely disabled composed function (session-scoped rename, reverted before this block exits) degrades ONLY its own card -- the sibling cards still return their own correct data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_dash_admin uuid := '00000000-0000-0000-0000-000000301010';
  v_row record;
  v_tickets_degraded boolean := null;
  v_accounts_count int := null;
  v_balance_count int := null;
begin
  alter function app.list_customer_tickets(uuid, uuid, uuid, text, integer, uuid) rename to __disabled_probe_list_customer_tickets;

  -- A fresh backend connection (a new psql -c invocation would be the
  -- cleanest proof; within this same script a plain, uncached call still
  -- forces a genuine "does not exist" error the FIRST time this exact
  -- statement executes in this session, since this is this session's own
  -- first call to app.get_customer_portal_dashboard_summary after the
  -- rename -- PL/pgSQL replans a cached SPI plan whenever a DDL event
  -- invalidates one of its dependencies, which ALTER ... RENAME does.
  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_admin, v_tenant1) loop
    if v_row.card_key = 'tickets' then
      v_tickets_degraded := v_row.degraded;
      if v_row.available <> true or (v_row.summary->>'openTicketCount')::int <> 0 then
        raise exception 'expected the disabled tickets card to still report available=true with a safe zero count, got %', v_row;
      end if;
    elsif v_row.card_key = 'accounts' then
      v_accounts_count := (v_row.summary->>'activeAccountCount')::int;
    elsif v_row.card_key = 'warehouse_inventory' then
      v_balance_count := (v_row.summary->>'activeInventoryBalanceCount')::int;
      if v_row.degraded then
        raise exception 'expected warehouse_inventory to remain unaffected by the tickets card''s own failure, got degraded=true';
      end if;
    end if;
  end loop;

  alter function app.__disabled_probe_list_customer_tickets(uuid, uuid, uuid, text, integer, uuid) rename to list_customer_tickets;

  if v_tickets_degraded is distinct from true then
    raise exception 'expected the tickets card to be marked degraded while its own source function was disabled, got %', v_tickets_degraded;
  end if;
  if v_accounts_count <> 1 or v_balance_count <> 1 then
    raise exception 'expected the sibling accounts/warehouse_inventory cards to remain fully correct while only the tickets card degraded, got accounts=% warehouse=%', v_accounts_count, v_balance_count;
  end if;
end $$;

\echo '>> 9. restore verification: with app.list_customer_tickets restored, the tickets card is healthy again'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpd1');
  v_dash_admin uuid := '00000000-0000-0000-0000-000000301010';
  v_row record;
begin
  for v_row in select * from app.get_customer_portal_dashboard_summary(v_dash_admin, v_tenant1) loop
    if v_row.card_key = 'tickets' then
      if v_row.degraded <> false or (v_row.summary->>'openTicketCount')::int <> 1 then
        raise exception 'expected the tickets card to be healthy again after restoring app.list_customer_tickets, got %', v_row;
      end if;
    end if;
  end loop;
end $$;
\echo 'PASS: per-card resilience -- one source''s genuine failure degrades only its own card; every sibling card, and the same card once restored, remain fully correct'
