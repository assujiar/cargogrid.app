import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerPortalInvoice, getCustomerPortalInvoiceLines, CustomerPortalInvoiceQueryError } from "../../../../../server/queries/customer-portal-invoice.ts";
import { getCustomerPortalPaymentStatus, CustomerPortalPaymentQueryError } from "../../../../../server/queries/customer-portal-payment.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerInvoiceDetailPanel } from "./customer-invoice-detail-panel.tsx";

/**
 * Customer invoice detail view (CPL-311, CG-S13-CPL-013, Prompt 311; the
 * payments/receipts section CPL-312, CG-S13-CPL-014, Prompt 312 adds).
 * Uses ONLY customer-safe get RPCs (app.get_customer_portal_invoice/app.
 * get_customer_portal_invoice_lines/app.get_customer_portal_payment_status)
 * -- an out-of-scope, cross-tenant, not-yet-issued, and genuinely
 * nonexistent invoice id are all indistinguishable here (the identical
 * anti-enumerating record_not_found on every one of these RPCs, CPL-312's
 * own RPC included -- it reuses CPL-311's own gate+fetch helper directly),
 * which is why this page renders a plain 404 rather than a "forbidden"
 * state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-warehouse-orders/[outboundOrderId]/
 * page.tsx exactly).
 *
 * Tier C review fix (batch close): this page deliberately calls ONLY
 * app.get_customer_portal_payment_status (CPL-312) rather than ALSO
 * app.get_customer_portal_invoice_payment_status (CPL-311's own narrower
 * sibling) -- CPL-312's own contract (server/contracts/customer-portal-
 * payment/customer-portal-payment.ts) is a strict superset of CPL-311's
 * (paymentStatus/originalAmount/openAmount/isHeld, plus allocations), so the
 * single CPL-312 result is reused for both the summary panel and the
 * allocations list, never fetched twice. Calling both was real duplicated
 * SECURITY DEFINER work (two independent gate re-derivations plus two
 * near-identical app.finance_ar_open_items lookups for the identical row)
 * on every single page render with zero UI benefit -- CPL-311's own
 * narrower RPC remains fully alive and correct for its own real caller
 * (this route's own "download" JSON export, app/(tenant)/[tenantSlug]/
 * customer-invoices/[invoiceId]/actions.ts, a user-triggered, infrequent
 * call, not a per-render one), so it is not removed, only no longer
 * redundantly called here.
 *
 * 'Dispute' is wired to the ALREADY-VERIFIED HRT-287 customer-ticket flow
 * (app/(tenant)/[tenantSlug]/customer-tickets/), pre-filled with this
 * invoice's own id/number via query parameters and auto-linked on ticket
 * creation via the ALREADY-VERIFIED HRT-292 app.ticket_links mechanism --
 * per CPL-311's own explicit instruction, not a parallel dispute table/RPC
 * (CPL-311 migration design decision 13). CPL-312's own §22 alternative
 * flow ("pending reconciliation... allow customer to submit proof through
 * document/ticket workflow") reuses this SAME existing dispute link rather
 * than building a second, near-duplicate ticket-linking entry point for
 * payment-specific questions on the identical invoice -- disclosed in
 * docs/build-log/phase-08/CPL-312.md rather than silently assumed.
 */
export default async function CustomerInvoiceDetailPage({ params }: { params: Promise<{ tenantSlug: string; invoiceId: string }> }) {
  const { tenantSlug, invoiceId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let invoice: Awaited<ReturnType<typeof getCustomerPortalInvoice>> | null = null;
  let lines: Awaited<ReturnType<typeof getCustomerPortalInvoiceLines>> = [];
  let paymentDetail: Awaited<ReturnType<typeof getCustomerPortalPaymentStatus>> | null = null;

  try {
    invoice = await getCustomerPortalInvoice(supabase, access.tenant.id, access.authUserId, invoiceId);
    [lines, paymentDetail] = await Promise.all([
      getCustomerPortalInvoiceLines(supabase, access.tenant.id, access.authUserId, invoiceId),
      getCustomerPortalPaymentStatus(supabase, access.tenant.id, access.authUserId, invoiceId),
    ]);
  } catch (error) {
    if (error instanceof CustomerPortalInvoiceQueryError || error instanceof CustomerPortalPaymentQueryError) {
      if (error.code === "record_not_found") {
        notFoundResult = true;
      } else {
        loadFailed = true;
      }
    } else {
      throw error;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !invoice || !paymentDetail) {
    return <ErrorState description="Something went wrong loading this invoice. Please try again." />;
  }

  // paymentDetail (CPL-312) is a strict superset of CPL-311's own narrower
  // payment-status shape (paymentStatus/originalAmount/openAmount/isHeld) --
  // reused for both props rather than fetched a second time (see this
  // file's own header, Tier C review fix).
  return <CustomerInvoiceDetailPanel tenantSlug={tenantSlug} invoice={invoice} lines={lines} payment={paymentDetail} paymentDetail={paymentDetail} />;
}
