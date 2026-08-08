import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorContracts, listVendorContractsExpiring, VendorContractQueryError } from "../../../../../server/queries/vendor-contract.ts";
import { listVendorProfiles, VendorProfileQueryError } from "../../../../../server/queries/vendor-profile.ts";
import { VENDOR_CONTRACT_STATUSES, type VendorContractStatus } from "../../../../../server/contracts/vendor-contract/vendor-contract.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorContractQueuePanel } from "./vendor-contract-queue-panel.tsx";
import { createVendorContractDraftAction } from "./actions.ts";

/**
 * Vendor Contract queue (PRC-261, CG-S11-PRC-012) -- versioned vendor contracts
 * governing services, rates, capacity, SLA, compliance, terms, amendment and renewal.
 * Filterable by status; mirrors app/(tenant)/[tenantSlug]/procurement/purchase-orders/
 * page.tsx's own exact shape.
 */
export default async function VendorContractQueuePage({
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

  const statusFilter: VendorContractStatus | null = status && (VENDOR_CONTRACT_STATUSES as readonly string[]).includes(status) ? (status as VendorContractStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let contracts: Awaited<ReturnType<typeof listVendorContracts>> = [];
  let activeVendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  let expiringSoon: Awaited<ReturnType<typeof listVendorContractsExpiring>> = [];
  try {
    [contracts, activeVendors, expiringSoon] = await Promise.all([
      listVendorContracts(supabase, access.tenant.id, access.authUserId, null, statusFilter, 100),
      listVendorProfiles(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 100 }),
      listVendorContractsExpiring(supabase, access.tenant.id, 30, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof VendorContractQueryError) && !(error instanceof VendorProfileQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor contract queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Contracts</h1>
        <p className="text-xs text-neutral-500">
          Versioned standing agreements governing services, rates, capacity, SLA, compliance, and terms. Contract activation never creates a purchase order, AP, or journal entry --
          downstream capabilities snapshot exact applicable terms from whichever version is currently active.
        </p>
      </div>

      <VendorContractQueuePanel
        tenantSlug={tenantSlug}
        contracts={contracts}
        activeVendors={activeVendors}
        expiringSoon={expiringSoon}
        statusFilter={statusFilter}
        createAction={createVendorContractDraftAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
