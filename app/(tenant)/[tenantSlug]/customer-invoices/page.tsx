import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalInvoices, CustomerPortalInvoiceQueryError } from "../../../../server/queries/customer-portal-invoice.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { CUSTOMER_PORTAL_INVOICE_STATUSES, CustomerPortalInvoiceStatusSchema } from "../../../../server/contracts/customer-portal-invoice/customer-portal-invoice.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerInvoicesPanel } from "./customer-invoices-panel.tsx";

/**
 * Invoice and Billing Visibility list view (CPL-311, CG-S13-CPL-013,
 * Prompt 311). Read projection over Finance-owned app.finance_invoices --
 * Business rule 1 ("Finance remains owner of invoice, AR, posting, payment
 * allocation and period lock"), so there is no create/edit/approve/issue
 * action on this page; a customer cannot mutate an invoice from the portal.
 *
 * Only status IN (issued, void) is ever returned by the RPC itself
 * (migration design decision 4) -- draft/submitted/approved pre-issuance
 * invoices never reach this page, filtered server-side, not merely hidden
 * client-side.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard), the SAME denied/redirect shape every sibling
 * customer-portal-nav route already uses, and carries CustomerPortalNav
 * (extended this checkpoint with a new "invoices" tab).
 */
export default async function CustomerInvoicesPage({
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

  // An unrecognized status value simply matches zero rows server-side
  // (migration design decision 4's own status IN (issued, void) bound
  // already covers this), so this parse only keeps the filter form itself
  // honest about which values are real -- never surfaced as an error.
  const statusParse = CustomerPortalInvoiceStatusSchema.safeParse(rawStatus);
  const statusFilter = statusParse.success ? statusParse.data : null;

  const supabase = await createSupabaseServerClient();
  const generatedAt = new Date().toISOString();
  let loadFailed = false;
  let invoices: Awaited<ReturnType<typeof listCustomerPortalInvoices>> = [];
  // ISS-2026-124: the reader's own account scope, so each invoice row can name the account it
  // belongs to. Same read, and same panel-side name lookup, CPL-309/310 already use.
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];

  try {
    [invoices, accounts] = await Promise.all([
      listCustomerPortalInvoices(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 50 }),
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalInvoiceQueryError) && !(error instanceof CustomerPortalScopeQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="invoices" />
        <ErrorState description="Something went wrong loading your invoices. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="invoices" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Invoices &amp; billing</h1>
        <p className="text-xs text-neutral-500">
          Issued invoices for your own accounts. This is a read-only projection -- Finance remains the source of truth; you cannot edit, approve, or post an invoice from here. Questions about a charge can
          be raised as a dispute from the invoice detail page.
        </p>
      </div>

      <CustomerInvoicesPanel tenantSlug={tenantSlug} invoices={invoices} accounts={accounts} statusFilter={statusFilter ?? ""} statuses={CUSTOMER_PORTAL_INVOICE_STATUSES} generatedAt={generatedAt} />
    </div>
  );
}
