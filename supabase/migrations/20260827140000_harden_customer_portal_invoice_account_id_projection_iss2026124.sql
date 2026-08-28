-- ===========================================================================
-- Track B Batch 4, ISS-2026-124 (docs/runtime/KNOWN_ISSUES.md).
--
-- Fixes ISS-2026-124 (docs/runtime/KNOWN_ISSUES.md): `app.get_customer_
-- portal_invoice`/`app.list_customer_portal_invoices` (CPL-311,
-- `20260801120000_create_customer_portal_invoice_billing_visibility.sql`)
-- omit `customer_account_id` from their own `RETURNS TABLE` projection, the
-- one outlier among sibling Phase 8 customer-portal read RPCs: CPL-309's
-- `app.get_customer_portal_inventory_balance`/`app.list_customer_portal_
-- inventory_balances` and CPL-310's `app.get_customer_portal_outbound_
-- order`/`app.list_customer_portal_outbound_orders` both project
-- `owner_account_id`; CPL-312's `app.list_customer_portal_receipts`
-- (`20260801130000_create_customer_portal_payment_visibility.sql:407,445`)
-- projects `customer_account_id` directly. `app.finance_invoices.customer_
-- account_id` already exists and is already used internally by both
-- functions' own gate/filter predicate (`i.customer_account_id = any
-- (v_scope)` in `list_customer_portal_invoices`) -- this migration only
-- widens the outward projection, it invents no new data and changes no
-- authorization behavior.
--
-- DROP+CREATE is required, not plain CREATE OR REPLACE FUNCTION, because
-- PostgreSQL does not allow CREATE OR REPLACE FUNCTION to change a
-- function's RETURNS TABLE column list -- this mirrors the repo's own
-- established pattern for this exact situation (e.g. `drop function
-- app.decide_vendor_activation_approval_step(...)` in
-- `20260730670000_harden_procurement_batch_257_259_review_fixes.sql`).
--
-- SCOPE NOTE (read before applying): this migration closes only the
-- database half of ISS-2026-124. The entry's own "Not fixed at this Tier C
-- review pass" section additionally requires, for a COMPLETE and verifiable
-- fix: (1) `server/contracts/customer-portal-invoice/customer-portal-
-- invoice.ts` -- add `customerAccountId` to `CustomerPortalInvoiceSchema`
-- and its `parseCustomerPortalInvoice` mapper; (2) `server/queries/
-- customer-portal-invoice.ts` -- no change needed beyond what the Zod
-- parser already does (it maps by key from the raw row, not positionally);
-- (3) `app/(tenant)/[tenantSlug]/customer-invoices/` -- surface the new
-- field for multi-account customers. None of those are touched here --
-- this draft's mandate is DB-layer migrations and db-tests only.
--
-- A further dependency the entry's own text (written 2026-08-17) could not
-- have anticipated, found only by re-verifying current repo state: a
-- PostgREST-facing pass-through wrapper,
-- `public.get_customer_portal_invoice`/`public.list_customer_portal_
-- invoices` (`20260826000000_create_public_api_data_wrappers.sql`,
-- RGL-394 Option-2), was added on 2026-08-26 -- AFTER this issue was
-- written. Each wrapper is `language sql` and does `select * from
-- app.<fn>(...)` against its OWN independently-declared `returns
-- TABLE(...)`, so it must be widened in lockstep with the `app.` function
-- it wraps or the two column lists mismatch and every call breaks at
-- execution time. Both wrapper functions are DROP+CREATEd below too, with
-- an identical grant set to what `20260826000000` originally set up
-- (anon: no EXECUTE; authenticated/service_role: EXECUTE), verified against
-- that file's own precedent immediately preceding/following these two
-- functions before drafting this.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. app.get_customer_portal_invoice -- add customer_account_id.
-- ---------------------------------------------------------------------------

drop function app.get_customer_portal_invoice(uuid, uuid, uuid);

create function app.get_customer_portal_invoice(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns table (
  id uuid,
  invoice_number text,
  currency text,
  status text,
  subtotal_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  issue_date date,
  due_date date,
  record_version integer,
  updated_at timestamptz,
  customer_account_id uuid
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_invoice := app._resolve_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);

  return query
  select
    v_invoice.id, v_invoice.invoice_number, v_invoice.currency, v_invoice.status,
    v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.total_amount,
    v_invoice.issue_date, v_invoice.due_date, v_invoice.record_version, v_invoice.updated_at,
    v_invoice.customer_account_id;
end;
$$;

comment on function app.get_customer_portal_invoice is
  'CPL-311 (ISS-2026-124 fix): only status IN (issued, void) is ever returned (decision 4). Never company_id/job_order_id/billing_readiness_handoff_id/posting_period_id/ar_open_item_id -- internal linkage, not customer-safe (decision 6). customer_account_id IS now projected (ISS-2026-124) -- the owning account, not an internal linkage field, matching every sibling Phase 8 read RPC''s own precedent (owner_account_id/customer_account_id). record_not_found (errcode no_data_found) is identical whether the id genuinely does not exist, belongs to a different tenant, is a real but not-yet-issued invoice, or is real/issued but out of this actor''s finance scope (decision 5, anti-enumeration).';

grant execute on function app.get_customer_portal_invoice(uuid, uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.list_customer_portal_invoices -- add customer_account_id.
-- ---------------------------------------------------------------------------

drop function app.list_customer_portal_invoices(uuid, uuid, text, timestamptz, uuid, integer);

create function app.list_customer_portal_invoices(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  invoice_number text,
  currency text,
  status text,
  subtotal_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  issue_date date,
  due_date date,
  record_version integer,
  updated_at timestamptz,
  customer_account_id uuid
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- A cursor is a (timestamp, id) PAIR -- a half-supplied cursor fails loud,
  -- mirroring app.list_customer_portal_outbound_orders'/app.list_customer_
  -- portal_inventory_balances' own identical validation exactly.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  -- p_status_filter is unconstrained input, but the status IN ('issued',
  -- 'void') predicate below already bounds every possible row -- a filter
  -- value outside that set (e.g. 'draft') simply matches zero rows, never an
  -- error, mirroring app.list_customer_portal_outbound_orders' own
  -- established non-validating-filter shape (design decision 4 there).
  return query
  select
    i.id, i.invoice_number, i.currency, i.status, i.subtotal_amount, i.tax_amount, i.total_amount,
    i.issue_date, i.due_date, i.record_version, i.updated_at, i.customer_account_id
  from app.finance_invoices i
  where i.tenant_id = p_tenant_id
    and i.status in ('issued', 'void')
    and i.customer_account_id = any (v_scope)
    and (p_status_filter is null or i.status = p_status_filter)
    and (p_cursor_id is null or (i.updated_at, i.id) < (p_cursor_updated_at, p_cursor_id))
  order by i.updated_at desc, i.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_invoices is
  'CPL-311 (ISS-2026-124 fix): bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. Scoped by app.resolve_customer_account_scope (CPL-300 widened resolver) AND status IN (issued, void). customer_account_id IS now projected (ISS-2026-124) so a multi-account customer_user can tell which of their own accounts each row belongs to -- the same column already drives the scope predicate above, only the outward projection changed. A caller whose resolved scope is empty gets zero rows, never an error.';

grant execute on function app.list_customer_portal_invoices(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. public.get_customer_portal_invoice / public.list_customer_portal_invoices
--    -- RGL-394 Option-2 pass-through wrappers must be widened in lockstep
--    (20260826000000_create_public_api_data_wrappers.sql), or `select *`
--    against the now-wider app. functions mismatches their own declared
--    `returns TABLE(...)` and every call fails at execution time.
-- ---------------------------------------------------------------------------

drop function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid);

create function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid)
returns TABLE(id uuid, invoice_number text, currency text, status text, subtotal_amount numeric, tax_amount numeric, total_amount numeric, issue_date date, due_date date, record_version integer, updated_at timestamp with time zone, customer_account_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);
$wrap$;

comment on function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_customer_portal_invoice with an identical grant set, never a reimplementation. Widened in lockstep with the ISS-2026-124 fix to app.get_customer_portal_invoice. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid) from public;
grant execute on function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid) to service_role;
grant execute on function public.get_customer_portal_invoice(p_tenant_id uuid, p_actor_auth_user_id uuid, p_invoice_id uuid) to authenticated;

drop function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text, p_cursor_updated_at timestamp with time zone, p_cursor_id uuid, p_limit integer);

create function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text DEFAULT NULL::text, p_cursor_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50)
returns TABLE(id uuid, invoice_number text, currency text, status text, subtotal_amount numeric, tax_amount numeric, total_amount numeric, issue_date date, due_date date, record_version integer, updated_at timestamp with time zone, customer_account_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_customer_portal_invoices(p_tenant_id, p_actor_auth_user_id, p_status_filter, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text, p_cursor_updated_at timestamp with time zone, p_cursor_id uuid, p_limit integer) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_customer_portal_invoices with an identical grant set, never a reimplementation. Widened in lockstep with the ISS-2026-124 fix to app.list_customer_portal_invoices. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text, p_cursor_updated_at timestamp with time zone, p_cursor_id uuid, p_limit integer) from public;
grant execute on function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text, p_cursor_updated_at timestamp with time zone, p_cursor_id uuid, p_limit integer) to service_role;
grant execute on function public.list_customer_portal_invoices(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text, p_cursor_updated_at timestamp with time zone, p_cursor_id uuid, p_limit integer) to authenticated;
