import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalReceipts, CustomerPortalPaymentQueryError } from "../../../../server/queries/customer-portal-payment.ts";
import { CUSTOMER_PORTAL_RECEIPT_STATUSES, CustomerPortalReceiptStatusSchema } from "../../../../server/contracts/customer-portal-payment/customer-portal-payment.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerReceiptsPanel } from "./customer-receipts-panel.tsx";

/**
 * Payment Visibility receipts list view (CPL-312, CG-S13-CPL-014,
 * Prompt 312). Read projection over Finance-owned app.finance_receipts --
 * business rule 1 ("Portal cannot post, allocate, reverse, reconcile or
 * delete payments"), so there is no create/edit/allocate/reverse action on
 * this page; a customer cannot mutate a receipt from the portal.
 *
 * No per-receipt detail sub-route, mirroring CPL-308's own Document Center
 * "list with filters, no detail sub-route" precedent -- every field this
 * list projects (status/amount/unappliedAmount/receiptDate/currency) is
 * already the receipt's own full customer-safe shape, and a receipt's own
 * allocation-to-invoice detail is more naturally surfaced from the INVOICE
 * side (the new "Payments & receipts" section on
 * app/(tenant)/[tenantSlug]/customer-invoices/[invoiceId]/, this same
 * checkpoint) -- a receipt can apply to more than one invoice, so there is
 * no single natural "go to the invoice" link target from a bare receipt row
 * either. Never bank_account_label/payer_name (migration design decisions
 * 5/6, structurally absent from the RPC's own RETURNS TABLE shape).
 *
 * Uses lib/portal/resolve-customer-portal-access.server.ts (CPL-300's
 * general-purpose Layer 4 portal entry guard), the SAME denied/redirect
 * shape every sibling customer-portal-nav route already uses, and carries
 * CustomerPortalNav (extended this checkpoint with a new "receipts" tab).
 */
export default async function CustomerReceiptsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status: rawStatus } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={
          access.status === "tenant_suspended"
            ? "This organization's customer portal is currently unavailable."
            : "You don't have access to this organization's billing. Contact your account administrator if you believe this is a mistake."
        }
      />
    );
  }

  // An unrecognized status value simply matches zero rows server-side --
  // this parse only keeps the filter form itself honest about which values
  // are real, never surfaced as an error (mirrors customer-invoices/page.tsx's
  // own identical treatment).
  const statusParse = CustomerPortalReceiptStatusSchema.safeParse(rawStatus);
  const statusFilter = statusParse.success ? statusParse.data : null;

  const supabase = await createSupabaseServerClient();
  const generatedAt = new Date().toISOString();
  let loadFailed = false;
  let receipts: Awaited<ReturnType<typeof listCustomerPortalReceipts>> = [];

  try {
    receipts = await listCustomerPortalReceipts(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 50 });
  } catch (error) {
    if (!(error instanceof CustomerPortalPaymentQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="receipts" />
        <ErrorState description="Something went wrong loading your receipts. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="receipts" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Receipts</h1>
        <p className="text-xs text-neutral-500">
          Payments Finance has recorded against your own accounts. This is a read-only projection -- Finance remains the source of truth; you cannot post, allocate, reverse, or reconcile a payment from
          here. See an invoice&apos;s own detail page for which receipts apply to it.
        </p>
      </div>

      <CustomerReceiptsPanel tenantSlug={tenantSlug} receipts={receipts} statusFilter={statusFilter ?? ""} statuses={CUSTOMER_PORTAL_RECEIPT_STATUSES} generatedAt={generatedAt} />
    </div>
  );
}
