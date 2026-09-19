import { NextResponse } from "next/server";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { generatePackingListPdf, PackingListGenerationError } from "../../../../../../../server/documents/generate-packing-list.server.ts";

/**
 * Packing List PDF download (audit remediation A7). A Route Handler, not a
 * Server Action, because a Server Action cannot return a raw binary HTTP
 * response with a `Content-Type`/`Content-Disposition` header -- the same
 * access-gate-then-query shape the sibling `page.tsx` already uses
 * (`resolveOperationsAccessForRequest`), mirroring the purchase-order/
 * surat-jalan/POD routes exactly. `getWmsPackingTask` itself throws
 * `packing_task_not_found` rather than returning null, so that specific
 * error is mapped to a 404 here instead of a generic 500.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ tenantSlug: string; packingTaskId: string }> }) {
  const { tenantSlug, packingTaskId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();

  let result: Awaited<ReturnType<typeof generatePackingListPdf>>;
  try {
    result = await generatePackingListPdf(supabase, access.tenant.slug, access.tenant.id, packingTaskId, access.authUserId);
  } catch (error) {
    if (error instanceof PackingListGenerationError) {
      if (error.message.includes("packing_task_not_found")) {
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
      "Content-Disposition": `inline; filename="packing-list-${result.packingTask.packingTaskNumber}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
