import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorBillMatchCases, listVendorBillMatchTolerancePolicies, getVendorBillMatchReconciliationStatus, VendorInvoiceMatchingQueryError } from "../../../../../server/queries/vendor-invoice-matching.ts";
import { VENDOR_BILL_MATCH_CASE_STATUSES, type VendorBillMatchCaseStatus } from "../../../../../server/contracts/vendor-invoice-matching/vendor-invoice-matching.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorBillMatchQueuePanel } from "./vendor-bill-match-queue-panel.tsx";
import {
  startVendorBillMatchAction,
  createVendorBillMatchTolerancePolicyDraftAction,
  updateVendorBillMatchTolerancePolicyDraftAction,
  activateVendorBillMatchTolerancePolicyAction,
} from "./actions.ts";

/**
 * Vendor Invoice Matching queue (PRC-265, CG-S11-PRC-016) -- match cases against the
 * canonical Finance vendor bill (FIN-200), configurable tolerance policy, and a
 * reconciliation summary. Extends, never duplicates, Finance's own AP truth.
 */
export default async function VendorBillMatchQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ overallStatus?: string }>;
}) {
  const { tenantSlug } = await params;
  const { overallStatus } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const statusFilter: VendorBillMatchCaseStatus | null = overallStatus && (VENDOR_BILL_MATCH_CASE_STATUSES as readonly string[]).includes(overallStatus) ? (overallStatus as VendorBillMatchCaseStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let cases: Awaited<ReturnType<typeof listVendorBillMatchCases>> = [];
  let policies: Awaited<ReturnType<typeof listVendorBillMatchTolerancePolicies>> = [];
  let reconciliation: Awaited<ReturnType<typeof getVendorBillMatchReconciliationStatus>> = [];
  try {
    [cases, policies, reconciliation] = await Promise.all([
      listVendorBillMatchCases(supabase, access.tenant.id, access.authUserId, { overallStatus: statusFilter, limit: 100 }),
      listVendorBillMatchTolerancePolicies(supabase, access.tenant.id, access.authUserId),
      getVendorBillMatchReconciliationStatus(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof VendorInvoiceMatchingQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor invoice matching queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Invoice Matching</h1>
        <p className="text-xs text-neutral-500">
          Match each vendor bill against PO/contract, actual-cost, rate, and tax evidence. No match result posts a journal or executes payment -- Finance alone owns approval,
          posting, and payment for its own canonical vendor bill.
        </p>
      </div>

      <VendorBillMatchQueuePanel
        tenantSlug={tenantSlug}
        cases={cases}
        policies={policies}
        reconciliation={reconciliation}
        statusFilter={statusFilter}
        startMatchAction={startVendorBillMatchAction.bind(null, tenantSlug)}
        createPolicyAction={createVendorBillMatchTolerancePolicyDraftAction.bind(null, tenantSlug)}
        updatePolicyAction={updateVendorBillMatchTolerancePolicyDraftAction.bind(null, tenantSlug)}
        activatePolicyAction={activateVendorBillMatchTolerancePolicyAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
