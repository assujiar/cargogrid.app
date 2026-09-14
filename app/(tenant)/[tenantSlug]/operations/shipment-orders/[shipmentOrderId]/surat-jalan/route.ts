import { NextResponse } from "next/server";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { generateSuratJalanPdf, SuratJalanGenerationError } from "../../../../../../../server/documents/generate-surat-jalan.server.ts";

/**
 * Surat Jalan (delivery note) PDF download (audit remediation A7). A Route
 * Handler, not a Server Action, because a Server Action cannot return a raw
 * binary HTTP response with a `Content-Type`/`Content-Disposition` header --
 * this is the same access-gate-then-query shape every sibling `page.tsx`
 * already uses (`resolveOperationsAccessForRequest`, the route group itself
 * is a UX boundary only), just returning a PDF instead of HTML.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();

  let result: Awaited<ReturnType<typeof generateSuratJalanPdf>>;
  try {
    result = await generateSuratJalanPdf(supabase, access.tenant.slug, shipmentOrderId, access.authUserId);
  } catch (error) {
    if (error instanceof SuratJalanGenerationError) {
      return NextResponse.json({ error: "generation_failed", message: error.message }, { status: 500 });
    }
    throw error;
  }

  if (!result) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  return new NextResponse(new Uint8Array(result.pdfBuffer), {
    status: 200,
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `inline; filename="surat-jalan-${result.shipmentOrder.shipmentNumber}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
