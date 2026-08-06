import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../../../lib/supabase/server.ts";
import { listVendorComplianceDocumentVersions, getVendorComplianceRequirement, VendorComplianceQueryError } from "../../../../../../../../../server/queries/vendor-compliance.ts";
import { getVendorProfile, VendorProfileQueryError } from "../../../../../../../../../server/queries/vendor-profile.ts";
import { ErrorState } from "../../../../../../../../../components/ui/error-state.tsx";
import { DocumentVersionPanel } from "./document-version-panel.tsx";
import { accessVendorComplianceDocumentEvidenceAction } from "../../../actions.ts";

/**
 * Compliance document/version viewer (PRC-253 fix-pass addition, HIGH-severity
 * finding, adversarial review -- Sec.15/16/18/21). Full renewal lineage for one
 * compliance evidence slot (`version_group_id`), oldest to newest, each version's own
 * evidence gated through app.access_vendor_compliance_document_evidence (PRC:Download
 * + PLT-128's own app.authorize_file_access -- malware-scan + record/sensitivity
 * gate, audited both by this capability's own audit trail and PLT-128's own
 * app.file_access_logs). Proves renewal never deletes prior evidence (design note 4)
 * by construction -- every version, not just the latest, is listed and independently
 * viewable/deniable.
 */
export default async function VendorComplianceDocumentVersionsPage({
  params,
}: {
  params: Promise<{ tenantSlug: string; vendorMasterRecordId: string; versionGroupId: string }>;
}) {
  const { tenantSlug, vendorMasterRecordId, versionGroupId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    vendor: Awaited<ReturnType<typeof getVendorProfile>>;
    versions: Awaited<ReturnType<typeof listVendorComplianceDocumentVersions>>;
    requirementName: string | null;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const vendor = await getVendorProfile(supabase, vendorMasterRecordId, access.authUserId);
    const versions = await listVendorComplianceDocumentVersions(supabase, versionGroupId, access.authUserId);
    const firstVersion = versions[0];
    if (!firstVersion || firstVersion.vendorMasterRecordId !== vendorMasterRecordId) {
      // Either no such version lineage, or it belongs to a different vendor than the
      // URL claims -- both are treated as "not found" rather than silently rendering
      // a mismatched vendor's own evidence lineage.
      notFound();
    }
    const requirement = await getVendorComplianceRequirement(supabase, firstVersion.requirementVersionId, access.authUserId).catch(() => null);
    loaded = { vendor, versions, requirementName: requirement?.name ?? null };
  } catch (error) {
    if (!(error instanceof VendorComplianceQueryError) && !(error instanceof VendorProfileQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorProfileQueryError && error.message.startsWith("vendor_profile_not_found")) {
      notFound();
    }
    if (error instanceof VendorComplianceQueryError && error.message.startsWith("vendor_compliance_document_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this document's version history. Please try again." />;
  }

  const { vendor, versions, requirementName } = loaded;

  return (
    <DocumentVersionPanel
      tenantSlug={tenantSlug}
      vendorMasterRecordId={vendorMasterRecordId}
      vendorLegalName={vendor.legalName}
      requirementName={requirementName}
      versions={versions}
      accessActionFor={(documentId) => accessVendorComplianceDocumentEvidenceAction.bind(null, tenantSlug, documentId, "metadata_view")}
    />
  );
}
