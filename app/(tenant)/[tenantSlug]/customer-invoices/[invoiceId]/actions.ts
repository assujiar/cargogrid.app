"use server";

/**
 * Customer invoice Server Actions (CPL-311, CG-S13-CPL-013). 'Download'
 * (migration design decision 12) is a real, structured JSON export of the
 * invoice + its lines + its payment status, composed from the SAME three
 * read RPCs the detail page itself already calls -- no new RPC, no
 * fabricated PDF/document-generation/signed-URL pipeline (confirmed by
 * direct repository-wide search before this migration was written: zero
 * Storage-bucket integration, zero PDF-generation dependency, and zero
 * existing signed-URL pattern for any Finance document anywhere in this
 * repository). Every call re-derives access from the authenticated session
 * itself (resolveCustomerPortalAccessForRequest) -- it never trusts a
 * client-supplied tenant/actor id.
 */

import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { getCustomerPortalInvoice, getCustomerPortalInvoiceLines, getCustomerPortalInvoicePaymentStatus, CustomerPortalInvoiceQueryError } from "../../../../../server/queries/customer-portal-invoice.ts";
import { CustomerPortalInvoiceExportSchema, type CustomerPortalInvoiceExport } from "../../../../../server/contracts/customer-portal-invoice/customer-portal-invoice.ts";

export interface ExportCustomerPortalInvoiceResult {
  readonly ok: boolean;
  readonly error: string | null;
  readonly json: string | null;
  readonly filename: string | null;
}

export async function exportCustomerPortalInvoiceAction(tenantSlug: string, invoiceId: string): Promise<ExportCustomerPortalInvoiceResult> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { ok: false, error: "You don't have access to this organization's billing.", json: null, filename: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const [invoice, lines, payment] = await Promise.all([
      getCustomerPortalInvoice(supabase, access.tenant.id, access.authUserId, invoiceId),
      getCustomerPortalInvoiceLines(supabase, access.tenant.id, access.authUserId, invoiceId),
      getCustomerPortalInvoicePaymentStatus(supabase, access.tenant.id, access.authUserId, invoiceId),
    ]);

    const payload: CustomerPortalInvoiceExport = CustomerPortalInvoiceExportSchema.parse({
      exportedAt: new Date().toISOString(),
      invoice,
      lines,
      payment,
    });

    return {
      ok: true,
      error: null,
      json: JSON.stringify(payload, null, 2),
      filename: `invoice-${invoice.invoiceNumber ?? invoice.id}.json`,
    };
  } catch (error) {
    if (error instanceof CustomerPortalInvoiceQueryError && error.code === "record_not_found") {
      return { ok: false, error: "This invoice is no longer available.", json: null, filename: null };
    }
    return { ok: false, error: "Something went wrong preparing this export. Please try again.", json: null, filename: null };
  }
}
