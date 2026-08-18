import { randomUUID } from "node:crypto";
import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerShipmentOrder, listCustomerShipmentOrderChangeRequests, CustomerShipmentOrderQueryError } from "../../../../../server/queries/customer-shipment-order.ts";
import { getCustomerShipmentTracking, CustomerShipmentTrackingQueryError } from "../../../../../server/queries/customer-shipment-tracking.ts";
import type { CustomerShipmentTracking } from "../../../../../server/contracts/customer-shipment-tracking/customer-shipment-tracking.ts";
import { listCustomerShipmentAlertSubscriptions, CustomerShipmentAlertQueryError } from "../../../../../server/queries/customer-shipment-alert.ts";
import type { CustomerShipmentAlertSubscription, CustomerShipmentAlertType } from "../../../../../server/contracts/customer-shipment-alert/customer-shipment-alert.ts";
import { getCustomerEpod, CustomerEpodMutationError } from "../../../../../server/mutations/customer-epod.ts";
import type { CustomerEpod } from "../../../../../server/contracts/customer-epod/customer-epod.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerShipmentDetailPanel } from "./customer-shipment-detail-panel.tsx";
import { CustomerShipmentTrackingPanel } from "./customer-shipment-tracking-panel.tsx";
import { CustomerShipmentAlertSubscriptionsPanel } from "./customer-shipment-alert-subscriptions-panel.tsx";
import { CustomerEpodPanel } from "./customer-epod-panel.tsx";
import { requestCustomerShipmentOrderChangeAction, subscribeCustomerShipmentAlertAction, unsubscribeCustomerShipmentAlertAction, accessCustomerEpodAction, type CustomerShipmentOrderActionState } from "../actions.ts";

const ALERT_TYPES: readonly CustomerShipmentAlertType[] = ["milestone_delay", "exception", "no_fresh_position", "tracking_restored", "delivery", "document_available"];

type AlertAction = (prevState: CustomerShipmentOrderActionState, formData: FormData) => Promise<CustomerShipmentOrderActionState>;

/**
 * Customer shipment order detail view (CPL-304, CG-S13-CPL-006). Uses ONLY
 * the customer-safe get RPC (app.get_customer_shipment_order) -- an
 * out-of-scope shipment order id and a genuinely nonexistent id are
 * indistinguishable here (both raise the identical anti-enumerating
 * record_not_found), which is why this page renders a plain 404 rather than
 * a "forbidden" state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-bookings/[bookingRequestId]/page.tsx
 * exactly).
 *
 * Renders app.shipment_orders' own real status plainly (draft/confirmed/
 * cancelled) -- no new "locked" concept exists; the source prompt's own
 * alternative flow ("if Operations has locked the shipment... create a
 * ticket or change request instead") is fully satisfied by this immutable
 * detail plus the "request a change" form plus a plain link to the existing
 * customer-tickets route (design decision 4 of the migration -- ticket
 * CREATION integration is Prompt 313's own job, not built here).
 *
 * Extended at CPL-305 (CG-S13-CPL-007, Prompt 305) with a tracking/timeline
 * section (customer-shipment-tracking-panel.tsx) fetched from the new,
 * independent app.get_customer_shipment_tracking RPC -- per that
 * capability's own design decision 7, this SAME detail page/route, not a
 * new sibling route. Fetched non-fatally: a tracking-composition failure
 * degrades to omitting that section, never to hiding the shipment detail
 * above it that already loaded successfully.
 *
 * Extended again at CPL-306 (CG-S13-CPL-008, Prompt 306) with a "notify me"
 * alert-subscription sub-section (customer-shipment-alert-subscriptions-
 * panel.tsx), per that capability's own design decision 7 (same route,
 * never a new sibling). Subscriptions are fetched non-fatally, identically
 * to tracking above. One Server Action is bound per alert type (12 total:
 * subscribe/unsubscribe x 6 types) via .bind() -- a plain closure factory
 * cannot cross the server/client boundary as a prop, only an already-bound
 * Server Action reference can.
 *
 * Extended again at CPL-307 (CG-S13-CPL-009, Prompt 307) with an ePOD
 * ("delivery evidence") sub-section (customer-epod-panel.tsx), per that
 * capability's own design decision 12 (same route, never a new sibling).
 * `getCustomerEpod` is fetched non-fatally, identically to tracking/alerts
 * above -- but unlike those two, every call is itself a real, audited access
 * attempt (app.get_customer_epod writes an app.file_access_logs/app.
 * capture_audit_event row on every invocation, migration design decision 3),
 * so this page's own eager fetch is deliberately also a genuine, disclosed
 * access event, not merely a status preview.
 */
export default async function CustomerShipmentDetailPage({ params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let detail: Awaited<ReturnType<typeof getCustomerShipmentOrder>> | null = null;
  let changeRequests: Awaited<ReturnType<typeof listCustomerShipmentOrderChangeRequests>> = [];

  try {
    detail = await getCustomerShipmentOrder(supabase, access.tenant.id, access.authUserId, shipmentOrderId);
    changeRequests = await listCustomerShipmentOrderChangeRequests(supabase, access.tenant.id, access.authUserId, { shipmentOrderId, limit: 50 });
  } catch (error) {
    if (!(error instanceof CustomerShipmentOrderQueryError)) throw error;
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
    return <ErrorState description="Something went wrong loading this shipment. Please try again." />;
  }

  // Tracking (CPL-305) is fetched independently, non-fatally -- the detail
  // load above already proved this identity's scope on this exact shipment
  // order (the identical anti-enumerating check), so a tracking failure here
  // is a genuine degraded state, never re-thrown into the whole page's own
  // ErrorState (source prompt §22's own "show last trusted update... do not
  // fabricate live status" alternative flow, applied to the composition
  // itself: a tracking outage never hides the shipment detail the customer
  // already successfully loaded).
  let tracking: CustomerShipmentTracking | null = null;
  try {
    tracking = await getCustomerShipmentTracking(supabase, access.tenant.id, access.authUserId, shipmentOrderId);
  } catch (error) {
    if (!(error instanceof CustomerShipmentTrackingQueryError)) throw error;
    tracking = null;
  }

  // CPL-306: alert subscriptions, fetched non-fatally, identically to
  // tracking above -- a subscription-load failure degrades to an empty list
  // (every row renders as "off"), never to hiding the shipment detail.
  let alertSubscriptions: readonly CustomerShipmentAlertSubscription[] = [];
  try {
    alertSubscriptions = await listCustomerShipmentAlertSubscriptions(supabase, access.tenant.id, access.authUserId, { shipmentOrderId, limit: 10 });
  } catch (error) {
    if (!(error instanceof CustomerShipmentAlertQueryError)) throw error;
    alertSubscriptions = [];
  }

  // CPL-307: ePOD, fetched non-fatally, identically to tracking/alerts above
  // -- an ePOD-load failure degrades to omitting that section, never to
  // hiding the shipment detail already loaded successfully. record_not_found
  // should be structurally unreachable here (the detail load above already
  // proved this identity's scope on this exact shipment order), but is still
  // handled defensively rather than assumed impossible.
  let epod: CustomerEpod | null = null;
  try {
    epod = await getCustomerEpod(supabase, access.tenant.id, access.authUserId, shipmentOrderId);
  } catch (error) {
    if (!(error instanceof CustomerEpodMutationError)) throw error;
    epod = null;
  }

  // Fresh per render, not regenerated per submit -- Tier C fix
  // (spec-compliance), mirrors customer-quotes/[requestId]/page.tsx's own
  // identical fix. Neither the change-request action nor the alert
  // subscribe/unsubscribe actions below take a client-supplied idempotency
  // key at all -- the alert RPCs are natural-key upserts (migration header
  // decision 3), so no key needs to be minted for them here.
  const requestChangeIdempotencyKey = randomUUID();

  const subscribeActions = Object.fromEntries(ALERT_TYPES.map((t) => [t, subscribeCustomerShipmentAlertAction.bind(null, tenantSlug, shipmentOrderId, t)])) as Record<CustomerShipmentAlertType, AlertAction>;
  const unsubscribeActions = Object.fromEntries(ALERT_TYPES.map((t) => [t, unsubscribeCustomerShipmentAlertAction.bind(null, tenantSlug, shipmentOrderId, t)])) as Record<CustomerShipmentAlertType, AlertAction>;

  return (
    <div className="flex flex-col gap-4">
      <CustomerShipmentDetailPanel
        tenantSlug={tenantSlug}
        detail={detail}
        changeRequests={changeRequests}
        requestChangeAction={requestCustomerShipmentOrderChangeAction.bind(null, tenantSlug, shipmentOrderId, requestChangeIdempotencyKey)}
      />
      {tracking ? <CustomerShipmentTrackingPanel tracking={tracking} /> : null}
      <CustomerShipmentAlertSubscriptionsPanel subscriptions={alertSubscriptions} subscribeActions={subscribeActions} unsubscribeActions={unsubscribeActions} />
      {epod ? <CustomerEpodPanel tenantSlug={tenantSlug} epod={epod} accessAction={accessCustomerEpodAction.bind(null, tenantSlug, shipmentOrderId)} /> : null}
    </div>
  );
}
