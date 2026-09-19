-- CG-AUDIT-2026-09-02 A7: fourth printable document (invoice), following the
-- exact precedent surat jalan/POD/purchase order already established this
-- session. Confirmed via research before writing this migration: only two
-- reads exist for `app.finance_invoices` today --
-- `app.list_finance_invoices` (tenant-scoped list) and
-- `app.get_finance_invoice_lines` (lines for one invoice id) -- no
-- single-invoice-by-id HEADER read exists anywhere, confirmed by repo-wide
-- grep and by `server/queries/invoice.ts`, which wraps exactly those two
-- RPCs and nothing else.
--
-- `app.get_finance_invoice` mirrors `app.get_finance_invoice_lines`'s own
-- CURRENT (hardened) shape byte-for-byte -- SECURITY DEFINER,
-- `app.check_finance_invoice_authority('View', ...)` for the real FIN:View
-- authority gate, and the ISS-2026-146 tenant-id-disclosure fix already
-- applied to that sibling (`20260902100000_harden_tenant_id_disclosure_
-- finance.sql`): folds `app.has_active_tenant_membership` into the initial
-- not-found branch, so a zero-relationship cross-tenant probe learns
-- nothing a genuinely nonexistent invoice id wouldn't also produce, rather
-- than a tenant_id-interpolating insufficient_authority. `finance_invoices`
-- carries NO cost-masking concept analogous to purchase orders' own
-- PRC:View-cost split (`app.check_finance_invoice_authority` gates the
-- WHOLE read behind a single FIN:View predicate, confirmed by re-reading
-- that function's own body) -- so, unlike `app.get_purchase_order`, this
-- function returns every column unmasked to any FIN:View holder.
--
-- A basic, single-currency invoice PDF deliberately does not touch B3 (no
-- credit notes, one invoice per job order) or B4 (multi-currency summed as
-- raw numbers, DEFERRED_LARGE): `app.finance_invoices.currency` is
-- constrained to exactly one 3-letter code per row
-- (`finance_invoices_currency_check`) and `total_amount` is a generated
-- column in that one currency -- the schema structurally cannot represent
-- multi-currency on a single invoice, so there is nothing here to decide.
-- Printing renders an already-issued row exactly as it stands; B3/B4 remain
-- fully deferred.

create function app.get_finance_invoice(p_invoice_id uuid, p_actor_auth_user_id uuid)
returns app.finance_invoices
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('View', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return v_invoice;
end;
$$;

comment on function app.get_finance_invoice is
  'CG-AUDIT-2026-09-02 A7: single-invoice-by-id read, mirroring app.get_finance_invoice_lines'' own CURRENT hardened shape (SECURITY DEFINER, FIN:View gate, ISS-2026-146-style not-found-folds-membership fix) byte-for-byte. No cost-masking concept exists for invoices (unlike purchase orders'' PRC:View-cost split) -- app.check_finance_invoice_authority gates the whole read behind one FIN:View predicate, so every column returns unmasked to any FIN:View holder.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on function app.get_finance_invoice(uuid, uuid) from public;
grant execute on function app.get_finance_invoice(uuid, uuid) to authenticated, service_role;

-- app is not exposed to PostgREST (supabase/config.toml: schemas = ["public",
-- "graphql_public"]) -- every RPC callable from application code needs a matching
-- public.* thin pass-through wrapper (RGL-394 Option 2). Matches
-- app.get_finance_invoice's own SECURITY DEFINER mode exactly, mirroring
-- public.get_finance_invoice_lines' identical shape (scripts/db-tests/
-- public-api-wrapper-regression.sql asserts exhaustively that a wrapper's
-- security mode never differs from its app.* counterpart).
create function public.get_finance_invoice(p_invoice_id uuid, p_actor_auth_user_id uuid)
returns app.finance_invoices
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_finance_invoice(p_invoice_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_finance_invoice(p_invoice_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_finance_invoice with an identical grant set, never a reimplementation.';

revoke execute on function public.get_finance_invoice(p_invoice_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_invoice(p_invoice_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
