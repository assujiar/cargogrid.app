import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getVendorCapacityOffer, listVendorCapacityBlackouts, listVendorCapacityReservations, computeVendorCapacityAvailable, VendorCapacityQueryError } from "../../../../../../server/queries/vendor-capacity.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorCapacityOfferDetailPanel } from "./vendor-capacity-offer-detail-panel.tsx";
import {
  updateVendorCapacityOfferDraftAction,
  publishVendorCapacityOfferAction,
  archiveVendorCapacityOfferAction,
  addVendorCapacityBlackoutAction,
  removeVendorCapacityBlackoutAction,
  reserveVendorCapacityAction,
  acceptVendorCapacityReservationAction,
  declineVendorCapacityReservationAction,
  releaseVendorCapacityReservationAction,
  consumeVendorCapacityReservationAction,
} from "../actions.ts";

/**
 * Vendor Capacity offer detail (PRC-262, CG-S11-PRC-013): declaration terms, blackout
 * windows, and the full reservation queue with accept/decline/release/consume actions.
 * Every mutating action below binds the CURRENT record_version at render time (mirrors
 * the vendor-contract detail page's own `.bind()`-per-row convention).
 */
export default async function VendorCapacityOfferDetailPage({ params }: { params: Promise<{ tenantSlug: string; offerId: string }> }) {
  const { tenantSlug, offerId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let offer: Awaited<ReturnType<typeof getVendorCapacityOffer>> | null = null;
  let blackouts: Awaited<ReturnType<typeof listVendorCapacityBlackouts>> = [];
  let reservations: Awaited<ReturnType<typeof listVendorCapacityReservations>> = [];
  let availableNow: number | null = null;
  try {
    offer = await getVendorCapacityOffer(supabase, offerId, access.authUserId);
    [blackouts, reservations] = await Promise.all([
      listVendorCapacityBlackouts(supabase, offerId, access.authUserId),
      listVendorCapacityReservations(supabase, offerId, access.authUserId, null),
    ]);
    // C-20 discipline (mirrors PRC-261's own already-fixed precedent): app.compute_
    // vendor_capacity_available needs a real UI caller, not just an advisory RPC
    // nobody reads. Best-effort preview over the offer's own full declared window --
    // the real, race-safe enforcement happens inside app.reserve_vendor_capacity
    // itself regardless (migration design note 2).
    availableNow = await computeVendorCapacityAvailable(supabase, offerId, offer.windowStart, offer.windowEnd, access.authUserId);
  } catch (error) {
    if (!(error instanceof VendorCapacityQueryError)) throw error;
    if (error.message.includes("vendor_capacity_offer_not_found")) {
      notFoundOrDenied = true;
    } else if (error.message.includes("insufficient_authority")) {
      notFoundOrDenied = false;
      loadFailed = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !offer || !offer.id) {
    return <ErrorState description="Something went wrong loading this vendor capacity offer. Please try again." />;
  }

  return (
    <VendorCapacityOfferDetailPanel
      offer={offer}
      blackouts={blackouts}
      reservations={reservations}
      availableNow={availableNow}
      updateAction={updateVendorCapacityOfferDraftAction.bind(null, tenantSlug, offerId, offer.recordVersion)}
      publishAction={publishVendorCapacityOfferAction.bind(null, tenantSlug, offerId, offer.recordVersion)}
      archiveAction={archiveVendorCapacityOfferAction.bind(null, tenantSlug, offerId, offer.recordVersion)}
      addBlackoutAction={addVendorCapacityBlackoutAction.bind(null, tenantSlug, offerId)}
      removeBlackoutAction={(blackoutId, expectedVersion) => removeVendorCapacityBlackoutAction.bind(null, tenantSlug, offerId, blackoutId, expectedVersion)}
      reserveAction={reserveVendorCapacityAction.bind(null, tenantSlug, offerId)}
      acceptReservationAction={(reservationId, expectedVersion) => acceptVendorCapacityReservationAction.bind(null, tenantSlug, offerId, reservationId, expectedVersion)}
      declineReservationAction={(reservationId, expectedVersion) => declineVendorCapacityReservationAction.bind(null, tenantSlug, offerId, reservationId, expectedVersion)}
      releaseReservationAction={(reservationId, expectedVersion) => releaseVendorCapacityReservationAction.bind(null, tenantSlug, offerId, reservationId, expectedVersion)}
      consumeReservationAction={(reservationId, expectedVersion) => consumeVendorCapacityReservationAction.bind(null, tenantSlug, offerId, reservationId, expectedVersion)}
    />
  );
}
