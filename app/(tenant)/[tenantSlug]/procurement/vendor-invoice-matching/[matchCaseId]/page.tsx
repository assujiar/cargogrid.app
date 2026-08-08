import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getVendorBillMatchCase,
  listVendorBillMatchLines,
  listVendorBillMatchCaseEvents,
  listVendorBillMatchDisputes,
  listVendorBillMatchExceptionApprovals,
  listVendorBillMatchCaseVersions,
  VendorInvoiceMatchingQueryError,
} from "../../../../../../server/queries/vendor-invoice-matching.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorBillMatchDetailPanel } from "./vendor-bill-match-detail-panel.tsx";
import {
  reEvaluateVendorBillMatchCaseAction,
  mapVendorBillMatchLineAction,
  acceptVendorBillMatchWithinToleranceAction,
  cancelVendorBillMatchCaseAction,
  raiseVendorBillMatchDisputeAction,
  recordVendorBillMatchDisputeResponseAction,
  resolveVendorBillMatchDisputeAction,
  requestVendorBillMatchExceptionApprovalAction,
  decideVendorBillMatchExceptionApprovalAction,
} from "./actions.ts";

/**
 * Vendor Invoice Matching case detail (PRC-265, CG-S11-PRC-016) -- line-level variance
 * explanation, tolerance, duplicate, dispute/response, exception-approval, and the
 * read-only Finance readiness handoff.
 */
export default async function VendorBillMatchDetailPage({ params }: { params: Promise<{ tenantSlug: string; matchCaseId: string }> }) {
  const { tenantSlug, matchCaseId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundResult = false;
  let matchCase: Awaited<ReturnType<typeof getVendorBillMatchCase>> | null = null;
  let lines: Awaited<ReturnType<typeof listVendorBillMatchLines>> = [];
  let events: Awaited<ReturnType<typeof listVendorBillMatchCaseEvents>> = [];
  let disputes: Awaited<ReturnType<typeof listVendorBillMatchDisputes>> = [];
  let exceptionApprovals: Awaited<ReturnType<typeof listVendorBillMatchExceptionApprovals>> = [];
  let versions: Awaited<ReturnType<typeof listVendorBillMatchCaseVersions>> = [];
  try {
    matchCase = await getVendorBillMatchCase(supabase, { matchCaseId }, access.authUserId);
    [lines, events, disputes, exceptionApprovals, versions] = await Promise.all([
      listVendorBillMatchLines(supabase, matchCaseId, access.authUserId),
      listVendorBillMatchCaseEvents(supabase, matchCaseId, access.authUserId),
      listVendorBillMatchDisputes(supabase, matchCaseId, access.authUserId),
      listVendorBillMatchExceptionApprovals(supabase, matchCaseId, access.authUserId),
      listVendorBillMatchCaseVersions(supabase, matchCase.billId, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof VendorInvoiceMatchingQueryError)) throw error;
    if (error.message.startsWith("vendor_bill_match_case_not_found")) {
      notFoundResult = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !matchCase) {
    return <ErrorState description="Something went wrong loading this match case. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Match case -- bill {matchCase.billId}</h1>
        <p className="text-xs text-neutral-500">Version {matchCase.versionNo}. No match result posts a journal or executes payment -- Finance alone owns approval, posting, and payment.</p>
      </div>

      <VendorBillMatchDetailPanel
        tenantSlug={tenantSlug}
        matchCase={matchCase}
        lines={lines}
        events={events}
        disputes={disputes}
        exceptionApprovals={exceptionApprovals}
        versions={versions}
        reEvaluateAction={reEvaluateVendorBillMatchCaseAction.bind(null, tenantSlug, matchCase.id, matchCase.recordVersion, lines.map((l) => l.billLineId))}
        mapLineAction={mapVendorBillMatchLineAction.bind(null, tenantSlug, matchCase.id)}
        acceptAction={acceptVendorBillMatchWithinToleranceAction.bind(null, tenantSlug, matchCase.id, matchCase.recordVersion)}
        cancelAction={cancelVendorBillMatchCaseAction.bind(null, tenantSlug, matchCase.id, matchCase.recordVersion)}
        raiseDisputeAction={raiseVendorBillMatchDisputeAction.bind(null, tenantSlug, matchCase.id)}
        respondDisputeAction={recordVendorBillMatchDisputeResponseAction.bind(null, tenantSlug, matchCase.id)}
        resolveDisputeAction={resolveVendorBillMatchDisputeAction.bind(null, tenantSlug, matchCase.id)}
        requestExceptionAction={requestVendorBillMatchExceptionApprovalAction.bind(null, tenantSlug, matchCase.id, matchCase.recordVersion)}
        decideExceptionAction={decideVendorBillMatchExceptionApprovalAction.bind(null, tenantSlug, matchCase.id)}
      />
    </div>
  );
}
