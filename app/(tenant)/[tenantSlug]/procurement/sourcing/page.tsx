import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listSourcingRequests, SourcingQueryError } from "../../../../../server/queries/sourcing.ts";
import { SOURCING_REQUEST_STATUSES, type SourcingRequestStatus } from "../../../../../server/contracts/sourcing/sourcing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { SourcingQueuePanel } from "./sourcing-queue-panel.tsx";
import { createSourcingRequestFromCostingAction, createSourcingRequestFromOperationalDemandAction, createProactiveSourcingRequestAction } from "./actions.ts";

/**
 * Sourcing queue (PRC-256, CG-S11-PRC-007) -- source-linked sourcing requests
 * (from a Commercial costing request or an Operations shipment order) plus
 * proactive lane/service sourcing, filterable by status. Mirrors
 * app/(tenant)/[tenantSlug]/procurement/rates/page.tsx and
 * app/(tenant)/[tenantSlug]/procurement/compliance/page.tsx's own shape
 * (searchParams-driven status filter, a create form above the table).
 */
export default async function SourcingQueuePage({
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

  const statusFilter: SourcingRequestStatus | null = status && (SOURCING_REQUEST_STATUSES as readonly string[]).includes(status) ? (status as SourcingRequestStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let requests: Awaited<ReturnType<typeof listSourcingRequests>> = [];
  try {
    requests = await listSourcingRequests(supabase, access.tenant.id, access.authUserId, statusFilter, 100);
  } catch (error) {
    if (!(error instanceof SourcingQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the sourcing queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Sourcing</h1>
        <p className="text-xs text-neutral-500">
          Sourcing requests inherit their demand from a Commercial costing request or an Operations shipment order -- never re-typed -- or start proactively with no source. Evaluate candidate
          vendor eligibility, curate a human-owned shortlist, and hand it off to RFQ.
        </p>
      </div>

      <SourcingQueuePanel
        tenantSlug={tenantSlug}
        requests={requests}
        statusFilter={statusFilter}
        createFromCostingAction={createSourcingRequestFromCostingAction.bind(null, tenantSlug)}
        createFromOperationalDemandAction={createSourcingRequestFromOperationalDemandAction.bind(null, tenantSlug)}
        createProactiveAction={createProactiveSourcingRequestAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
