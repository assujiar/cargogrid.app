import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorCapacityOffers, VendorCapacityQueryError } from "../../../../../server/queries/vendor-capacity.ts";
import { listVendorProfiles, VendorProfileQueryError } from "../../../../../server/queries/vendor-profile.ts";
import { VENDOR_CAPACITY_OFFER_STATUSES, type VendorCapacityOfferStatus } from "../../../../../server/contracts/vendor-capacity/vendor-capacity.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorCapacityQueuePanel } from "./vendor-capacity-queue-panel.tsx";
import { createVendorCapacityOfferDraftAction } from "./actions.ts";

/**
 * Vendor Capacity and Availability queue (PRC-262, CG-S11-PRC-013) -- vendor-declared
 * capacity offers by service/mode/lane/region/resource type over a time window,
 * reservable by sourcing/assignment without silent overbooking (concurrency-safe,
 * live-proven in scripts/db-tests/procurement-vendor-capacity.sql). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-contracts/page.tsx's own exact shape.
 */
export default async function VendorCapacityQueuePage({
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

  const statusFilter: VendorCapacityOfferStatus | null = status && (VENDOR_CAPACITY_OFFER_STATUSES as readonly string[]).includes(status) ? (status as VendorCapacityOfferStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let offers: Awaited<ReturnType<typeof listVendorCapacityOffers>> = [];
  let activeVendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  try {
    [offers, activeVendors] = await Promise.all([
      listVendorCapacityOffers(supabase, access.tenant.id, access.authUserId, null, statusFilter, null, 100),
      listVendorProfiles(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 100 }),
    ]);
  } catch (error) {
    if (!(error instanceof VendorCapacityQueryError) && !(error instanceof VendorProfileQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor capacity queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Capacity</h1>
        <p className="text-xs text-neutral-500">
          Vendor-declared capacity offers over a time window. Reservations against a published offer are concurrency-safe -- two concurrent requests that together would exceed the offer&apos;s own
          quantity can never both succeed.
        </p>
      </div>

      <VendorCapacityQueuePanel tenantSlug={tenantSlug} offers={offers} activeVendors={activeVendors} statusFilter={statusFilter} createAction={createVendorCapacityOfferDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
