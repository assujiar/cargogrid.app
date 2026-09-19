import { NextResponse } from "next/server";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { generatePurchaseOrderPdf, PurchaseOrderGenerationError } from "../../../../../../../server/documents/generate-purchase-order.server.ts";

/**
 * Purchase Order PDF download (audit remediation A7). A Route Handler, not a
 * Server Action, because a Server Action cannot return a raw binary HTTP
 * response with a `Content-Type`/`Content-Disposition` header -- the same
 * access-gate-then-query shape the sibling `page.tsx` already uses
 * (`resolveProcurementAccessForRequest`), mirroring the surat-jalan/POD
 * routes exactly. `getPurchaseOrder` itself throws `purchase_order_not_found`
 * rather than returning null (unlike `getShipmentOrder`), so that specific
 * error is mapped to a 404 here instead of a generic 500.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ tenantSlug: string; purchaseOrderId: string }> }) {
  const { tenantSlug, purchaseOrderId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();

  let result: Awaited<ReturnType<typeof generatePurchaseOrderPdf>>;
  try {
    result = await generatePurchaseOrderPdf(supabase, access.tenant.slug, purchaseOrderId, access.authUserId);
  } catch (error) {
    if (error instanceof PurchaseOrderGenerationError) {
      if (error.message.includes("purchase_order_not_found")) {
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
      "Content-Disposition": `inline; filename="purchase-order-${result.purchaseOrder.poNumber}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
