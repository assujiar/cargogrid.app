import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerBookingRequest, CustomerBookingRequestQueryError } from "../../../../../server/queries/customer-booking-request.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerBookingDetailPanel } from "./customer-booking-detail-panel.tsx";
import { updateCustomerBookingRequestDraftAction, submitCustomerBookingRequestAction, requestCustomerBookingRescheduleAction, requestCustomerBookingCancellationAction } from "../actions.ts";

/**
 * Customer booking request detail/status-timeline view (CPL-303, CG-S13-CPL-
 * 005). Uses ONLY the customer-safe get RPC (app.get_customer_booking_
 * request) -- an out-of-scope booking id and a genuinely nonexistent id are
 * indistinguishable here (both raise the identical anti-enumerating
 * record_not_found), which is why this page renders a plain 404 rather than
 * a "forbidden" state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-quotes/[requestId]/page.tsx exactly).
 */
export default async function CustomerBookingDetailPage({ params }: { params: Promise<{ tenantSlug: string; bookingRequestId: string }> }) {
  const { tenantSlug, bookingRequestId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let detail: Awaited<ReturnType<typeof getCustomerBookingRequest>> | null = null;

  try {
    detail = await getCustomerBookingRequest(supabase, access.tenant.id, bookingRequestId, access.authUserId);
  } catch (error) {
    if (!(error instanceof CustomerBookingRequestQueryError)) throw error;
    if (error.code === "record_not_found") {
      notFoundResult = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this booking. Please try again." />;
  }

  const recordVersion = detail.recordVersion;

  return (
    <CustomerBookingDetailPanel
      detail={detail}
      updateAction={updateCustomerBookingRequestDraftAction.bind(null, tenantSlug, bookingRequestId, recordVersion)}
      submitAction={submitCustomerBookingRequestAction.bind(null, tenantSlug, bookingRequestId, recordVersion)}
      rescheduleAction={requestCustomerBookingRescheduleAction.bind(null, tenantSlug, bookingRequestId, recordVersion)}
      cancelAction={requestCustomerBookingCancellationAction.bind(null, tenantSlug, bookingRequestId, recordVersion)}
    />
  );
}
