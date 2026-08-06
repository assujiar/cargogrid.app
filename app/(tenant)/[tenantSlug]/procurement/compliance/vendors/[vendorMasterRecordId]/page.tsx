import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getVendorProfile, VendorProfileQueryError } from "../../../../../../../server/queries/vendor-profile.ts";
import {
  getVendorComplianceEligibility,
  listVendorComplianceDocuments,
  listVendorComplianceWaivers,
  listVendorComplianceRequirements,
  VendorComplianceQueryError,
} from "../../../../../../../server/queries/vendor-compliance.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { VendorCompliancePanel } from "./vendor-compliance-panel.tsx";
import {
  submitVendorComplianceDocumentAction,
  renewVendorComplianceDocumentAction,
  decideVendorComplianceDocumentAction,
  requestVendorComplianceWaiverAction,
  decideVendorComplianceWaiverAction,
  revokeVendorComplianceWaiverAction,
  recalculateVendorComplianceStatusAction,
} from "../actions.ts";

/**
 * A single vendor's own compliance dashboard (PRC-253, CG-S11-PRC-004): eligibility
 * overview per requirement family, document upload/verification (wiring the real
 * Document/File Engine upload flow, record_type='vendor_compliance'), renewal, and
 * waiver request/decision/revoke. Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendors/[masterRecordId]/page.tsx's own
 * "authorization enforced server-side, not hidden client-side" precedent -- every
 * mutating control is visible to any PRC:View holder, and an unauthorized attempt
 * surfaces the RPC's own insufficient_authority message inline.
 */
export default async function VendorCompliancePage({ params }: { params: Promise<{ tenantSlug: string; vendorMasterRecordId: string }> }) {
  const { tenantSlug, vendorMasterRecordId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    vendor: Awaited<ReturnType<typeof getVendorProfile>>;
    eligibility: Awaited<ReturnType<typeof getVendorComplianceEligibility>>;
    documents: Awaited<ReturnType<typeof listVendorComplianceDocuments>>;
    waivers: Awaited<ReturnType<typeof listVendorComplianceWaivers>>;
    publishedRequirements: Awaited<ReturnType<typeof listVendorComplianceRequirements>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const vendor = await getVendorProfile(supabase, vendorMasterRecordId, access.authUserId);
    const [eligibility, documents, waivers, publishedRequirements] = await Promise.all([
      getVendorComplianceEligibility(supabase, vendorMasterRecordId, access.authUserId),
      listVendorComplianceDocuments(supabase, vendorMasterRecordId, access.authUserId, { latestOnly: true, limit: 200 }),
      listVendorComplianceWaivers(supabase, vendorMasterRecordId, access.authUserId, { limit: 100 }),
      listVendorComplianceRequirements(supabase, access.tenant.id, access.authUserId, { statusFilter: "published", limit: 200 }),
    ]);
    loaded = { vendor, eligibility, documents, waivers, publishedRequirements };
  } catch (error) {
    if (!(error instanceof VendorComplianceQueryError) && !(error instanceof VendorProfileQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorProfileQueryError && error.message.startsWith("vendor_profile_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this vendor's compliance record. Please try again." />;
  }

  const { vendor, eligibility, documents, waivers, publishedRequirements } = loaded;

  return (
    <VendorCompliancePanel
      tenantSlug={tenantSlug}
      vendor={vendor}
      eligibility={eligibility}
      documents={documents}
      waivers={waivers}
      publishedRequirements={publishedRequirements}
      submitDocumentAction={submitVendorComplianceDocumentAction.bind(null, tenantSlug, vendorMasterRecordId)}
      renewDocumentActionFor={(previousDocumentId) => renewVendorComplianceDocumentAction.bind(null, tenantSlug, vendorMasterRecordId, previousDocumentId)}
      decideDocumentActionFor={(documentId, expectedVersion) => decideVendorComplianceDocumentAction.bind(null, tenantSlug, vendorMasterRecordId, documentId, expectedVersion)}
      requestWaiverAction={requestVendorComplianceWaiverAction.bind(null, tenantSlug, vendorMasterRecordId)}
      decideWaiverActionFor={(waiverId, expectedVersion) => decideVendorComplianceWaiverAction.bind(null, tenantSlug, vendorMasterRecordId, waiverId, expectedVersion)}
      revokeWaiverActionFor={(waiverId, expectedVersion) => revokeVendorComplianceWaiverAction.bind(null, tenantSlug, vendorMasterRecordId, waiverId, expectedVersion)}
      recalculateAction={recalculateVendorComplianceStatusAction.bind(null, tenantSlug, vendorMasterRecordId)}
    />
  );
}
