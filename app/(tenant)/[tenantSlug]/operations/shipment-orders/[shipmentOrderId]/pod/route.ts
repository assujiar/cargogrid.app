import { NextResponse } from "next/server";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../../../lib/supabase/service-role.ts";
import { generatePodPdf, PodGenerationError } from "../../../../../../../server/documents/generate-pod.server.ts";

/**
 * Proof of Delivery (POD) PDF download (audit remediation A7). A Route
 * Handler, not a Server Action, because a Server Action cannot return a raw
 * binary HTTP response with a `Content-Type`/`Content-Disposition` header --
 * the same access-gate-then-query shape every sibling `page.tsx` already
 * uses (`resolveOperationsAccessForRequest`), just returning a PDF instead
 * of HTML, mirroring the surat-jalan route exactly.
 *
 * A service-role client is also created (audit remediation NEW-2, follow-on
 * to A6's own closure): `app.access_epod_evidence_for_download` -- the RPC
 * `generatePodPdf` now calls to mint each evidence image's signed URL -- is
 * service_role-only, mirroring `downloadEpodEvidenceAction`'s own identical
 * reasoning in this same route's sibling `actions.ts`. Every other read
 * still goes through the RLS-scoped `supabase` client.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();
  const serviceRole = createSupabaseServiceRoleClient();

  let result: Awaited<ReturnType<typeof generatePodPdf>>;
  try {
    result = await generatePodPdf(supabase, serviceRole, access.tenant.slug, shipmentOrderId, access.authUserId);
  } catch (error) {
    if (error instanceof PodGenerationError) {
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
      "Content-Disposition": `inline; filename="pod-${result.shipmentOrder.shipmentNumber}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
