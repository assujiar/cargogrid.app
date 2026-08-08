import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getVendorContract, listVendorContractVersions, getVendorContractLifecycleHistory, VendorContractQueryError } from "../../../../../../server/queries/vendor-contract.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorContractDetailPanel } from "./vendor-contract-detail-panel.tsx";
import {
  updateVendorContractDraftAction,
  submitVendorContractForApprovalAction,
  recordVendorContractSignatureAction,
  activateVendorContractAction,
  amendVendorContractAction,
  renewVendorContractAction,
  suspendVendorContractAction,
  reactivateVendorContractAction,
  terminateVendorContractAction,
  cancelVendorContractDraftAction,
} from "../actions.ts";

/**
 * Vendor Contract detail (PRC-261, CG-S11-PRC-012): terms matrix, version diff/lineage
 * (every version of the same contract_number), approval/signature status, and lifecycle
 * timeline. Every mutating action below binds the CURRENT record_version at render time
 * (mirrors app/(tenant)/[tenantSlug]/procurement/purchase-orders/[purchaseOrderId]/
 * page.tsx's own `.bind()`-per-row convention) -- a concurrent edit between render and
 * submit surfaces as a real stale_version error from the RPC itself, not a silently
 * accepted overwrite.
 */
export default async function VendorContractDetailPage({ params }: { params: Promise<{ tenantSlug: string; contractId: string }> }) {
  const { tenantSlug, contractId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let contract: Awaited<ReturnType<typeof getVendorContract>> | null = null;
  let versions: Awaited<ReturnType<typeof listVendorContractVersions>> = [];
  let history: Awaited<ReturnType<typeof getVendorContractLifecycleHistory>> = [];
  try {
    contract = await getVendorContract(supabase, contractId, access.authUserId);
    [versions, history] = await Promise.all([
      listVendorContractVersions(supabase, contract.contractNumber, contract.tenantId, access.authUserId),
      getVendorContractLifecycleHistory(supabase, contractId, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof VendorContractQueryError)) throw error;
    if (error.message.includes("vendor_contract_not_found")) {
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
  if (loadFailed || !contract || !contract.id) {
    return <ErrorState description="Something went wrong loading this vendor contract. Please try again." />;
  }

  return (
    <VendorContractDetailPanel
      contract={contract}
      versions={versions}
      history={history}
      updateAction={updateVendorContractDraftAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      submitAction={submitVendorContractForApprovalAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      signAction={recordVendorContractSignatureAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      activateAction={activateVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      amendAction={amendVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      renewAction={renewVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      suspendAction={suspendVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      reactivateAction={reactivateVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      terminateAction={terminateVendorContractAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
      cancelAction={cancelVendorContractDraftAction.bind(null, tenantSlug, contractId, contract.recordVersion)}
    />
  );
}
