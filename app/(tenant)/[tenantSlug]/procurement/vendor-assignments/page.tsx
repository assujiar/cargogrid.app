import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorAssignmentInvitations, VendorAssignmentQueryError } from "../../../../../server/queries/vendor-assignment.ts";
import { listVendorProfiles, VendorProfileQueryError } from "../../../../../server/queries/vendor-profile.ts";
import { VENDOR_ASSIGNMENT_INVITATION_STATUSES, type VendorAssignmentInvitationStatus } from "../../../../../server/contracts/vendor-assignment/vendor-assignment.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorAssignmentQueuePanel } from "./vendor-assignment-queue-panel.tsx";
import { proposeVendorAssignmentInvitationAction, overrideVendorAssignmentAction } from "./actions.ts";

/**
 * Vendor Assignment queue (PRC-263, CG-S11-PRC-014) -- the Procurement-side
 * invitation/eligibility workflow for a shipment order's role=vendor slot. Extends,
 * never duplicates, the canonical Operations resource assignment (OPS-172, already
 * `VERIFIED`): the real app.resource_assignments commitment lives on the Operations
 * shipment order page, this queue tracks the vendor-selection evidence (eligibility
 * snapshot, contract/PO/rate/capacity linkage) leading up to it. Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-capacity/page.tsx's own exact shape.
 */
export default async function VendorAssignmentQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const statusFilter: VendorAssignmentInvitationStatus | null =
    status && (VENDOR_ASSIGNMENT_INVITATION_STATUSES as readonly string[]).includes(status) ? (status as VendorAssignmentInvitationStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let invitations: Awaited<ReturnType<typeof listVendorAssignmentInvitations>> = [];
  let activeVendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  try {
    [invitations, activeVendors] = await Promise.all([
      listVendorAssignmentInvitations(supabase, access.tenant.id, access.authUserId, null, null, statusFilter, 100),
      listVendorProfiles(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 100 }),
    ]);
  } catch (error) {
    if (!(error instanceof VendorAssignmentQueryError) && !(error instanceof VendorProfileQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor assignment queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Assignment</h1>
        <p className="text-xs text-neutral-500">
          Invite a vendor onto a shipment order&apos;s vendor slot, or, for a genuine emergency, direct-assign under the dual OPS:Assign + PRC:Override authority. The canonical commitment always
          extends the Operations resource assignment shown on the shipment order itself.
        </p>
      </div>

      <VendorAssignmentQueuePanel
        tenantSlug={tenantSlug}
        invitations={invitations}
        activeVendors={activeVendors}
        statusFilter={statusFilter}
        proposeAction={proposeVendorAssignmentInvitationAction.bind(null, tenantSlug)}
        overrideAction={overrideVendorAssignmentAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
