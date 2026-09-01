import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listProfileChangeRequestsForStaffReview,
  listLegalIdentityChangeRequestsForStaffReview,
  listContactChangeRequestsForStaffReview,
  CustomerPortalChangeRequestStaffReviewQueryError,
} from "../../../../../server/queries/customer-portal-change-request-staff-review.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ProfileChangeRequestQueue, LegalIdentityChangeRequestQueue, ContactChangeRequestQueue } from "./customer-profile-review-panel.tsx";
import { decideProfileChangeRequestAction, decideLegalIdentityChangeRequestAction, decideContactChangeRequestAction } from "./actions.ts";
import type { CustomerProfileDecision } from "../../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";

/**
 * Customer profile / legal identity / contact change-request review workbench
 * (ISS-2026-123). Closes a real, previously-missing dependency: with no page
 * anywhere in this repository ever calling app.decide_customer_profile_
 * change_request (CPL-314, already-VERIFIED, confirmed live by grep before
 * writing this page) OR either of this entry's own two new decide RPCs, all
 * three change-request tables were write-only inboxes -- a customer could
 * submit a request, but no staff member had any UI path to ever decide it.
 *
 * Lists pending requests TENANT-WIDE (via the staff-facing, COM:Approve-
 * gated app.list_*_staff_review RPCs, ISS-2026-123 -- the customer-facing
 * account-scope-only list RPCs always return empty for a staff caller, which
 * holds no customer account scope) across all three request tables, with an
 * approve/reject decision form for each. Every decision is gated by each
 * RPC's own COM:Approve authority check (and, for the legal-identity/
 * contact-change RPCs, a step-up-MFA check when the tenant has configured
 * one) -- this page's own guard (resolveTenantAdminAccessForRequest) only
 * confirms a coarse tenant_admin portal-entry boundary.
 */
export default async function CustomerProfileReviewAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let profileRequests: Awaited<ReturnType<typeof listProfileChangeRequestsForStaffReview>> = [];
  let legalIdentityRequests: Awaited<ReturnType<typeof listLegalIdentityChangeRequestsForStaffReview>> = [];
  let contactRequests: Awaited<ReturnType<typeof listContactChangeRequestsForStaffReview>> = [];

  try {
    [profileRequests, legalIdentityRequests, contactRequests] = await Promise.all([
      listProfileChangeRequestsForStaffReview(supabase, access.tenant.id, access.authUserId, { status: "pending", limit: 200 }),
      listLegalIdentityChangeRequestsForStaffReview(supabase, access.tenant.id, access.authUserId, { status: "pending", limit: 200 }),
      listContactChangeRequestsForStaffReview(supabase, access.tenant.id, access.authUserId, { status: "pending", limit: 200 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalChangeRequestStaffReviewQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Customer profile review</h1>
        <ErrorState description="Something went wrong loading the review workbench. Please try again." />
      </div>
    );
  }

  const decideProfile = (requestId: string, expectedVersion: number, decision: CustomerProfileDecision) => decideProfileChangeRequestAction.bind(null, tenantSlug, requestId, expectedVersion, decision);
  const decideLegalIdentity = (requestId: string, expectedVersion: number, decision: CustomerProfileDecision) => decideLegalIdentityChangeRequestAction.bind(null, tenantSlug, requestId, expectedVersion, decision);
  const decideContact = (requestId: string, expectedVersion: number, decision: CustomerProfileDecision) => decideContactChangeRequestAction.bind(null, tenantSlug, requestId, expectedVersion, decision);

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Customer profile review</h1>
        <p className="text-sm text-text-secondary">
          Pending trade name / billing address, legal identity, and contact change requests submitted through the customer portal, across every account in this organization. Approve or reject each with a
          reason -- nothing here applies automatically.
        </p>
      </div>

      <section aria-labelledby="profile-queue-heading" className="flex flex-col gap-3">
        <h2 id="profile-queue-heading" className="text-lg font-semibold text-text-primary">
          Trade name / billing address ({profileRequests.length})
        </h2>
        <ProfileChangeRequestQueue requests={profileRequests} decideAction={decideProfile} />
      </section>

      <section aria-labelledby="legal-identity-queue-heading" className="flex flex-col gap-3">
        <h2 id="legal-identity-queue-heading" className="text-lg font-semibold text-text-primary">
          Legal identity corrections ({legalIdentityRequests.length})
        </h2>
        <LegalIdentityChangeRequestQueue requests={legalIdentityRequests} decideAction={decideLegalIdentity} />
      </section>

      <section aria-labelledby="contact-queue-heading" className="flex flex-col gap-3">
        <h2 id="contact-queue-heading" className="text-lg font-semibold text-text-primary">
          Contact requests ({contactRequests.length})
        </h2>
        <ContactChangeRequestQueue requests={contactRequests} decideAction={decideContact} />
      </section>
    </div>
  );
}
