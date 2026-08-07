import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listRfqs, RfqQueryError } from "../../../../../server/queries/rfq.ts";
import { RFQ_STATUSES, type RfqStatus } from "../../../../../server/contracts/rfq/rfq.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { RfqQueuePanel } from "./rfq-queue-panel.tsx";
import { draftRfqFromSourcingAction } from "./actions.ts";

/**
 * RFQ queue (PRC-257, CG-S11-PRC-008) -- source-linked Procurement RFQs
 * drafted from a shortlisted app.sourcing_requests (PRC-256), filterable by
 * status. With no status filter, superseded (historical, non-current)
 * versions are excluded by default. Mirrors app/(tenant)/[tenantSlug]/
 * procurement/sourcing/page.tsx's own exact shape.
 */
export default async function RfqQueuePage({
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

  const statusFilter: RfqStatus | null = status && (RFQ_STATUSES as readonly string[]).includes(status) ? (status as RfqStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let rfqs: Awaited<ReturnType<typeof listRfqs>> = [];
  try {
    rfqs = await listRfqs(supabase, access.tenant.id, access.authUserId, statusFilter, 100);
  } catch (error) {
    if (!(error instanceof RfqQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the RFQ queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Procurement RFQ</h1>
        <p className="text-xs text-neutral-500">
          RFQs inherit requirements from a shortlisted Sourcing request -- never re-typed -- and invite only eligible, scoped vendors. Responses are confidential, versioned and comparable; a
          changed requirement is a governed revision, never a silent edit.
        </p>
      </div>

      <RfqQueuePanel tenantSlug={tenantSlug} rfqs={rfqs} statusFilter={statusFilter} draftAction={draftRfqFromSourcingAction.bind(null, tenantSlug)} />
    </div>
  );
}
