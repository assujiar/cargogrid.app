-- CG-AUDIT-2026-09-02 B7 (first half only -- "Invoicing is driven by a
-- hand-copied UUID... Finance has no billable-jobs worklist"; the second half,
-- app.check_customer_credit/credit control, is a separate, larger, deliberately
-- excluded piece of work, untouched here).
--
-- app.billing_readiness_handoffs (20260728140000_create_operations_billing_
-- readiness.sql:122-133) is append-only with no status column at all, and the
-- only existing read, app.list_billing_readiness_handoffs
-- (20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql:712),
-- is scoped to ONE job order (p_job_order_id) -- exactly the id Finance does
-- not have without first knowing which job order to look up, so it cannot
-- serve as a tenant-wide worklist. This is a genuinely new, additive read: no
-- existing RPC lists every still-billable handoff across a tenant.
--
-- "Still billable" is the exact predicate app.prepare_finance_invoice_from_
-- readiness already re-derives on every call (20260907130000_fix_withholding_
-- tax_deducted_not_added_iss_b5.sql:152: "select ... from app.finance_invoices
-- where tenant_id = p_tenant_id and billing_readiness_handoff_id =
-- p_billing_readiness_handoff_id and status <> 'void'" -- a live invoice
-- already prepared from this handoff), reused here as a NOT EXISTS filter
-- rather than re-invented. The amount/currency shown is the same revenue-
-- snapshot arithmetic that same function uses to build the invoice
-- (subtotalAmount - discountAmount, in the snapshot's own currency) -- a
-- worklist that showed a different number than what preparing the invoice
-- will actually charge would be worse than showing none.
--
-- Revenue is masked behind app.has_view_selling_price, mirroring app.
-- list_job_orders' own precedent exactly (20260911000000_close_o1_query_
-- layer_cluster3_batch1_dispatch_job_order_views.sql:1408) -- a Finance
-- viewer with FIN:View but not COM's "View selling price" sees every handoff
-- but not its amount, the same "Masked" convention purchase orders' own
-- PRC:View-cost split established, rather than a new disclosure path around
-- an existing gate.
--
-- Gated on app.check_finance_invoice_authority('View', ...), the exact gate
-- app.list_finance_invoices/app.get_finance_invoice already use for a
-- finance-domain read -- no app.assert_actor_is_session_identity call, since
-- that RULE A pattern is specific to the OPS-domain app.can_access_record
-- functions (confirmed by re-reading app.list_finance_invoices/app.
-- get_finance_invoice's own bodies, neither of which calls it either).
create function app.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  job_order_id uuid,
  job_number text,
  account_id uuid,
  customer_legal_name text,
  currency text,
  amount numeric(14, 2),
  amount_masked boolean,
  handed_off_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    h.id,
    h.job_order_id,
    jo.job_number,
    jo.account_id,
    a.legal_name,
    jo.revenue_snapshot ->> 'currency',
    case when app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id)
      then (jo.revenue_snapshot ->> 'subtotalAmount')::numeric(14, 2) - coalesce((jo.revenue_snapshot ->> 'discountAmount')::numeric(14, 2), 0)
      else null
    end,
    not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id),
    h.handed_off_at
  from app.billing_readiness_handoffs h
  join app.job_orders jo on jo.id = h.job_order_id and jo.tenant_id = p_tenant_id
  join app.accounts a on a.id = jo.account_id
  where h.tenant_id = p_tenant_id
    and not exists (
      select 1 from app.finance_invoices i
      where i.tenant_id = p_tenant_id and i.billing_readiness_handoff_id = h.id and i.status <> 'void'
    )
  order by h.handed_off_at desc;
end;
$$;

comment on function app.list_billable_readiness_handoffs is
  'CG-AUDIT-2026-09-02 B7 (worklist half): every app.billing_readiness_handoffs row for the tenant that has no live (non-void) app.finance_invoices row yet -- the tenant-wide "still needs an invoice" worklist app.list_billing_readiness_handoffs (job-order-scoped) cannot serve. amount/currency mirror app.prepare_finance_invoice_from_readiness''s own arithmetic exactly (subtotalAmount - discountAmount from the job order''s revenue_snapshot) so the worklist never shows a number preparing the invoice would not actually charge. amount is masked behind app.has_view_selling_price, mirroring app.list_job_orders'' own precedent. FIN:View-gated, same as app.list_finance_invoices/app.get_finance_invoice.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.list_billable_readiness_handoffs(uuid, uuid) to authenticated, service_role;

-- Option-2 PostgREST wrapper (mode parity with app.list_billable_readiness_handoffs).
-- CG-AUDIT-2026-09-02 A4's own HUNDRED-AND-FORTY-FIFTH-PASS lesson applied here:
-- the revoke below explicitly names anon, authenticated, AND service_role (never
-- just "from public", which is the PUBLIC pseudo-role, not the anon/authenticated
-- roles -- Supabase's own ALTER DEFAULT PRIVILEGES rule grants every newly created
-- public.* function EXECUTE to anon/authenticated/service_role directly at CREATE
-- time, the ISS-2026-309 defect class).
create function public.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  job_order_id uuid,
  job_number text,
  account_id uuid,
  customer_legal_name text,
  currency text,
  amount numeric(14, 2),
  amount_masked boolean,
  handed_off_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_billable_readiness_handoffs(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_billable_readiness_handoffs with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;
grant execute on function public.list_billable_readiness_handoffs(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated;
