import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getVendorComplianceRequirement, listVendorComplianceRequirements, VendorComplianceQueryError } from "../../../../../../../server/queries/vendor-compliance.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { RequirementDetailPanel } from "./requirement-detail-panel.tsx";
import { updateVendorComplianceRequirementDraftAction, publishVendorComplianceRequirementAction, archiveVendorComplianceRequirementAction } from "../../actions.ts";

/**
 * Vendor compliance requirement detail page (PRC-253, CG-S11-PRC-004): draft-only
 * field editing, publish (offering to supersede an existing published requirement at
 * the identical scope tuple when one exists), and archive.
 */
export default async function VendorComplianceRequirementDetailPage({ params }: { params: Promise<{ tenantSlug: string; requirementVersionId: string }> }) {
  const { tenantSlug, requirementVersionId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    requirement: Awaited<ReturnType<typeof getVendorComplianceRequirement>>;
    currentPublished: Awaited<ReturnType<typeof listVendorComplianceRequirements>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const requirement = await getVendorComplianceRequirement(supabase, requirementVersionId, access.authUserId);
    const currentPublished =
      requirement.status === "draft"
        ? await listVendorComplianceRequirements(supabase, access.tenant.id, access.authUserId, {
            statusFilter: "published",
            vendorCategory: requirement.vendorCategory,
            serviceType: requirement.serviceType,
            limit: 5,
          })
        : [];
    loaded = { requirement, currentPublished };
  } catch (error) {
    if (!(error instanceof VendorComplianceQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorComplianceQueryError && error.message.startsWith("vendor_compliance_requirement_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this requirement. Please try again." />;
  }

  const { requirement, currentPublished } = loaded;

  return (
    <RequirementDetailPanel
      requirement={requirement}
      currentPublished={currentPublished.find((r) => r.id !== requirement.id && r.documentTypeCode === requirement.documentTypeCode) ?? null}
      updateDraftAction={updateVendorComplianceRequirementDraftAction.bind(null, tenantSlug, requirementVersionId, requirement.recordVersion)}
      publishAction={publishVendorComplianceRequirementAction.bind(null, tenantSlug, requirementVersionId, requirement.recordVersion)}
      archiveAction={archiveVendorComplianceRequirementAction.bind(null, tenantSlug, requirementVersionId, requirement.recordVersion)}
    />
  );
}
