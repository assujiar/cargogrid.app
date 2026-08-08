import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getVendorAssignmentInvitation, getVendorAssignmentEligibilityPreview, VendorAssignmentQueryError } from "../../../../../../server/queries/vendor-assignment.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorAssignmentInvitationDetailPanel } from "./vendor-assignment-invitation-detail-panel.tsx";
import {
  acceptVendorAssignmentInvitationAction,
  declineVendorAssignmentInvitationAction,
  cancelVendorAssignmentInvitationAction,
  confirmVendorAssignmentAction,
  reassignVendorAssignmentAction,
} from "../actions.ts";

/**
 * Vendor Assignment invitation detail (PRC-263, CG-S11-PRC-014): eligibility snapshot,
 * linked evidence (contract/PO/rate/capacity reservation), and the full
 * invited -> accepted/declined -> assigned -> superseded lifecycle. Every mutating
 * action below binds the CURRENT record_version at render time (mirrors the vendor-
 * capacity offer detail page's own `.bind()`-per-row convention).
 */
export default async function VendorAssignmentInvitationDetailPage({ params }: { params: Promise<{ tenantSlug: string; invitationId: string }> }) {
  const { tenantSlug, invitationId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let invitation: Awaited<ReturnType<typeof getVendorAssignmentInvitation>> | null = null;
  try {
    invitation = await getVendorAssignmentInvitation(supabase, invitationId, access.authUserId);
  } catch (error) {
    if (!(error instanceof VendorAssignmentQueryError)) throw error;
    if (error.message.includes("vendor_assignment_invitation_not_found")) {
      notFoundOrDenied = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !invitation || !invitation.id) {
    return <ErrorState description="Something went wrong loading this vendor assignment invitation. Please try again." />;
  }

  // C-20 discipline (mirrors PRC-262's own already-fixed precedent): app.get_vendor_
  // assignment_eligibility_preview needs a real UI caller, not just an advisory RPC
  // nobody reads. Only meaningful before confirmation -- the terminal states already
  // carry their own final eligibility_snapshot, and confirm_vendor_assignment itself
  // always re-verifies fresh regardless of this preview (migration design note 3).
  let livePreview: Awaited<ReturnType<typeof getVendorAssignmentEligibilityPreview>> | null = null;
  if (invitation.status === "invited" || invitation.status === "accepted") {
    try {
      livePreview = await getVendorAssignmentEligibilityPreview(
        supabase,
        invitation.tenantId,
        invitation.vendorMasterId,
        invitation.contractId,
        invitation.poId,
        invitation.capacityReservationId,
        access.authUserId,
      );
    } catch {
      livePreview = null;
    }
  }

  return (
    <VendorAssignmentInvitationDetailPanel
      invitation={invitation}
      livePreview={livePreview}
      acceptAction={acceptVendorAssignmentInvitationAction.bind(null, tenantSlug, invitationId, invitation.recordVersion)}
      declineAction={declineVendorAssignmentInvitationAction.bind(null, tenantSlug, invitationId, invitation.recordVersion)}
      cancelAction={cancelVendorAssignmentInvitationAction.bind(null, tenantSlug, invitationId, invitation.recordVersion)}
      confirmAction={confirmVendorAssignmentAction.bind(null, tenantSlug, invitationId, invitation.recordVersion)}
      reassignAction={reassignVendorAssignmentAction.bind(null, tenantSlug, invitationId, invitation.recordVersion)}
    />
  );
}
