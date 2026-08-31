-- Closes `ISS-2026-118`. The customer portal dashboard still tells people "This area is launching
-- soon" about capabilities that fully exist and are one click away from the same page's own nav.
--
-- The entry named two stub cards, `bookings` and `shipments`, and warned that leaving them would
-- compound: "dashboard cards for capabilities built in later batches would compound the same gap".
-- It did. `invoices` (CPL-311) and `payments` (CPL-312) landed afterwards and are stubbed for the
-- same reason. All four are wired here, because fixing only the two the entry happened to name
-- would repeat the exact mistake it was warning about.
--
-- `loyalty` and `alerts` stay stubbed, deliberately. Loyalty is not one list to compose but a
-- programme/points/tier/entitlement surface whose "one summary number" is a real product question,
-- and no customer-facing alerts source exists at all. A card that is honestly blank beats a card
-- that invents a number.
--
-- THE DESIGN DECISION THE ENTRY LEFT OPEN: WHAT "OPEN" MEANS ON EACH CARD
--
--   * bookings   -- anything not finished: excludes `cancelled` and `converted`. A
--                   `cancel_requested` booking still counts, because it is still the customer's to
--                   watch: somebody has to act on that request, and hiding it would make the card
--                   quieter than reality.
--   * shipments  -- excludes `cancelled`, matching the outbound-order card directly above it in
--                   this same function rather than inventing a second convention.
--   * invoices   -- `issued` only; `void` is not an obligation. This deliberately does NOT try to
--                   mean "unpaid": the composed RPC does not return payment status, and a count
--                   that silently meant something other than its own label would be worse than a
--                   simpler one.
--   * payments   -- receipts with money still unallocated. Stated as a COUNT, never a summed
--                   amount: receipts carry per-row currencies, and adding them would produce a
--                   meaningless total (the same trap `ISS-2026-136` recorded on the liability
--                   reconciliation totals). "3 payments awaiting allocation" is true in every
--                   currency; "4,500" is true in none.
--
-- Each new card reuses this function's own established shape exactly: one `begin ... exception
-- when others` block per source so a single failing RPC marks only its own card degraded
-- (design decision 5), the account-scope array applied as a real per-row filter (design decision
-- 3), and the 200-row cap with its own `*Capped` flag (design decision 6).

create or replace function app.get_customer_portal_dashboard_summary(p_auth_user_id uuid, p_tenant_id uuid)
returns table (
  card_key text,
  available boolean,
  source_updated_at timestamptz,
  degraded boolean,
  summary jsonb,
  detail_path text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_account_count integer := 0;
  v_primary_account_name text;
  v_accounts_degraded boolean := false;
  v_balance_count integer := 0;
  v_balance_capped boolean := false;
  v_balance_updated_at timestamptz;
  v_balance_degraded boolean := false;
  v_outbound_count integer := 0;
  v_outbound_capped boolean := false;
  v_outbound_updated_at timestamptz;
  v_outbound_degraded boolean := false;
  v_wh_updated_at timestamptz;
  v_ticket_count integer := 0;
  v_ticket_capped boolean := false;
  v_ticket_updated_at timestamptz;
  v_tickets_degraded boolean := false;
  v_booking_count integer := 0;
  v_booking_capped boolean := false;
  v_booking_updated_at timestamptz;
  v_bookings_degraded boolean := false;
  v_shipment_count integer := 0;
  v_shipment_capped boolean := false;
  v_shipment_updated_at timestamptz;
  v_shipments_degraded boolean := false;
  v_invoice_count integer := 0;
  v_invoice_capped boolean := false;
  v_invoice_updated_at timestamptz;
  v_invoices_degraded boolean := false;
  v_payment_count integer := 0;
  v_payment_capped boolean := false;
  v_payment_updated_at timestamptz;
  v_payments_degraded boolean := false;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  -- Design decision 3, unchanged: the canonical resolver, re-derived directly and used below as a
  -- genuine per-row filter. Deliberately NOT re-derived from the scope-context query below -- that
  -- would quietly make a presentation read the source of an authorization decision.
  v_scope := app.resolve_customer_account_scope(p_auth_user_id, p_tenant_id);

  begin
    select count(*), max(account_name) filter (where is_primary)
      into v_account_count, v_primary_account_name
    from app.get_customer_portal_scope_context(p_auth_user_id, p_tenant_id);
  exception when others then
    v_accounts_degraded := true;
    v_account_count := 0;
    v_primary_account_name := null;
  end;

  begin
    with page as (
      select owner_account_id, updated_at
      from app.list_customer_inventory_balances(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where owner_account_id = any (v_scope)),
      count(*) = 200,
      max(updated_at) filter (where owner_account_id = any (v_scope))
    into v_balance_count, v_balance_capped, v_balance_updated_at
    from page;
  exception when others then
    v_balance_degraded := true;
    v_balance_count := 0;
    v_balance_capped := false;
    v_balance_updated_at := null;
  end;

  begin
    with page as (
      select owner_account_id, status, updated_at
      from app.list_customer_outbound_orders(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where owner_account_id = any (v_scope) and status <> 'cancelled'),
      count(*) = 200,
      max(updated_at) filter (where owner_account_id = any (v_scope))
    into v_outbound_count, v_outbound_capped, v_outbound_updated_at
    from page;
  exception when others then
    v_outbound_degraded := true;
    v_outbound_count := 0;
    v_outbound_capped := false;
    v_outbound_updated_at := null;
  end;

  begin
    with page as (
      select account_id, status, updated_at
      from app.list_customer_tickets(p_tenant_id, p_auth_user_id, null, null, 200, null)
    )
    select
      count(*) filter (where account_id = any (v_scope) and status not in ('resolved', 'closed', 'cancelled')),
      count(*) = 200,
      max(updated_at) filter (where account_id = any (v_scope))
    into v_ticket_count, v_ticket_capped, v_ticket_updated_at
    from page;
  exception when others then
    v_tickets_degraded := true;
    v_ticket_count := 0;
    v_ticket_capped := false;
    v_ticket_updated_at := null;
  end;

  -- ISS-2026-118, card: bookings (CPL-303). `cancel_requested` deliberately still counts -- it is
  -- an open request somebody has to act on, and dropping it would make the card quieter than the
  -- customer's actual situation.
  begin
    with page as (
      select account_id, status, updated_at
      from app.list_customer_booking_requests(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where account_id = any (v_scope) and status not in ('cancelled', 'converted')),
      count(*) = 200,
      max(updated_at) filter (where account_id = any (v_scope))
    into v_booking_count, v_booking_capped, v_booking_updated_at
    from page;
  exception when others then
    v_bookings_degraded := true;
    v_booking_count := 0;
    v_booking_capped := false;
    v_booking_updated_at := null;
  end;

  -- ISS-2026-118, card: shipments (CPL-304). `cancelled` excluded, matching the outbound-order
  -- card above rather than inventing a second convention for the same idea.
  begin
    with page as (
      select shipper_account_id, status, updated_at
      from app.list_customer_shipment_orders(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where shipper_account_id = any (v_scope) and status <> 'cancelled'),
      count(*) = 200,
      max(updated_at) filter (where shipper_account_id = any (v_scope))
    into v_shipment_count, v_shipment_capped, v_shipment_updated_at
    from page;
  exception when others then
    v_shipments_degraded := true;
    v_shipment_count := 0;
    v_shipment_capped := false;
    v_shipment_updated_at := null;
  end;

  -- ISS-2026-118, card: invoices (CPL-311). `issued` only -- a void invoice is not an obligation.
  -- Not an attempt to mean "unpaid": the composed RPC carries no payment status, and a number that
  -- quietly meant something other than its label would be worse than a plainer one.
  begin
    with page as (
      select customer_account_id, status, updated_at
      from app.list_customer_portal_invoices(p_tenant_id, p_auth_user_id, null, null, null, 200)
    )
    select
      count(*) filter (where customer_account_id = any (v_scope) and status = 'issued'),
      count(*) = 200,
      max(updated_at) filter (where customer_account_id = any (v_scope))
    into v_invoice_count, v_invoice_capped, v_invoice_updated_at
    from page;
  exception when others then
    v_invoices_degraded := true;
    v_invoice_count := 0;
    v_invoice_capped := false;
    v_invoice_updated_at := null;
  end;

  -- ISS-2026-118, card: payments (CPL-312). A COUNT of receipts with money still unallocated,
  -- never a summed amount: receipts carry per-row currencies and adding them across currencies
  -- produces a number true in none of them (the trap ISS-2026-136 recorded on the liability
  -- totals). "3 payments awaiting allocation" is true whatever the currencies are.
  begin
    with page as (
      select customer_account_id, status, unapplied_amount, updated_at
      from app.list_customer_portal_receipts(p_tenant_id, p_auth_user_id, null, null, null, 200)
    )
    select
      count(*) filter (where customer_account_id = any (v_scope) and status <> 'void' and coalesce(unapplied_amount, 0) > 0),
      count(*) = 200,
      max(updated_at) filter (where customer_account_id = any (v_scope))
    into v_payment_count, v_payment_capped, v_payment_updated_at
    from page;
  exception when others then
    v_payments_degraded := true;
    v_payment_count := 0;
    v_payment_capped := false;
    v_payment_updated_at := null;
  end;

  v_wh_updated_at := greatest(v_balance_updated_at, v_outbound_updated_at);

  return query
  select * from (values
    ('accounts'::text, true, now(), v_accounts_degraded,
      jsonb_build_object('activeAccountCount', v_account_count, 'primaryAccountName', v_primary_account_name),
      'customer-portal'::text),
    ('warehouse_inventory'::text, true, v_wh_updated_at, (v_balance_degraded or v_outbound_degraded),
      jsonb_build_object(
        'activeInventoryBalanceCount', v_balance_count, 'activeInventoryBalanceCountCapped', v_balance_capped,
        'openOutboundOrderCount', v_outbound_count, 'openOutboundOrderCountCapped', v_outbound_capped
      ),
      null::text),
    ('tickets'::text, true, v_ticket_updated_at, v_tickets_degraded,
      jsonb_build_object('openTicketCount', v_ticket_count, 'openTicketCountCapped', v_ticket_capped),
      'customer-tickets'::text),
    ('bookings'::text, true, v_booking_updated_at, v_bookings_degraded,
      jsonb_build_object('openBookingRequestCount', v_booking_count, 'openBookingRequestCountCapped', v_booking_capped),
      'customer-bookings'::text),
    ('shipments'::text, true, v_shipment_updated_at, v_shipments_degraded,
      jsonb_build_object('activeShipmentCount', v_shipment_count, 'activeShipmentCountCapped', v_shipment_capped),
      'customer-shipments'::text),
    ('invoices'::text, true, v_invoice_updated_at, v_invoices_degraded,
      jsonb_build_object('issuedInvoiceCount', v_invoice_count, 'issuedInvoiceCountCapped', v_invoice_capped),
      'customer-invoices'::text),
    ('payments'::text, true, v_payment_updated_at, v_payments_degraded,
      jsonb_build_object('unallocatedPaymentCount', v_payment_count, 'unallocatedPaymentCountCapped', v_payment_capped),
      'customer-payments'::text),
    ('loyalty'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('alerts'::text, false, null::timestamptz, false, '{}'::jsonb, null::text)
  ) as t(card_key, available, source_updated_at, degraded, summary, detail_path);
end;
$$;

comment on function app.get_customer_portal_dashboard_summary is
  'CPL-301: the live-aggregating customer portal dashboard summary -- one row per card, never a persisted cache (design decision 1). Calls app.assert_actor_is_session_identity first, then applies app.resolve_customer_account_scope as a genuine per-row filter on every composed card (design decision 3). Each composed RPC call is independently wrapped so one source failing marks only its own card degraded (design decision 5); counts are bounded at 200 with a *Capped flag (design decision 6). ISS-2026-118 (20260831210000): bookings, shipments, invoices and payments are now real composed cards. They were stubbed as available=false while the capabilities behind them fully existed, so the dashboard told customers "launching soon" about features one click away in the same page''s own nav. The entry named the first two and warned the gap would compound as later batches landed -- it did, so all four are wired rather than only the two it happened to name. loyalty and alerts stay stubbed: loyalty is a programme/points/tier surface whose single summary number is a real product question, and no customer-facing alerts source exists -- a card that is honestly blank beats one that invents a number. "Open" per card: bookings excludes cancelled/converted (a cancel_requested booking still needs somebody to act on it); shipments excludes cancelled, matching the outbound-order card rather than inventing a second convention; invoices counts issued only and deliberately does not claim to mean "unpaid", since the composed RPC carries no payment status; payments COUNTS receipts with money unallocated and never sums amounts, because receipts carry per-row currencies and a cross-currency total is true in none of them (ISS-2026-136''s own trap).';
