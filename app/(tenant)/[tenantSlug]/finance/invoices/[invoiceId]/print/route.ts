import { NextResponse } from "next/server";
import { resolveFinanceAccessForRequest } from "../../../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { generateInvoicePdf, InvoiceGenerationError } from "../../../../../../../server/documents/generate-invoice.server.ts";

/**
 * Invoice PDF download (audit remediation A7). A Route Handler, not a Server
 * Action, because a Server Action cannot return a raw binary HTTP response
 * with a `Content-Type`/`Content-Disposition` header -- the same
 * access-gate-then-query shape `page.tsx` already uses
 * (`resolveFinanceAccessForRequest`), mirroring the surat-jalan/POD/
 * purchase-order routes exactly. `getFinanceInvoice` throws
 * `finance_invoice_not_found` rather than returning null, so that specific
 * error is mapped to a 404 here instead of a generic 500.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ tenantSlug: string; invoiceId: string }> }) {
  const { tenantSlug, invoiceId } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();

  let result: Awaited<ReturnType<typeof generateInvoicePdf>>;
  try {
    result = await generateInvoicePdf(supabase, access.tenant.slug, invoiceId, access.authUserId);
  } catch (error) {
    if (error instanceof InvoiceGenerationError) {
      if (error.message.includes("finance_invoice_not_found")) {
        return NextResponse.json({ error: "not_found" }, { status: 404 });
      }
      return NextResponse.json({ error: "generation_failed", message: error.message }, { status: 500 });
    }
    throw error;
  }

  return new NextResponse(new Uint8Array(result.pdfBuffer), {
    status: 200,
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `inline; filename="invoice-${result.invoice.invoiceNumber ?? result.invoice.id}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
