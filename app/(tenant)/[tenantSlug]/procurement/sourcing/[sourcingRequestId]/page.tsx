import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getSourcingRequest, listSourcingCandidates, getSourcingRequestHistory, SourcingQueryError } from "../../../../../../server/queries/sourcing.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { SourcingDetailPanel } from "./sourcing-detail-panel.tsx";
import {
  submitSourcingRequestAction,
  overrideSourcingRequestConstraintsAction,
  evaluateSourcingCandidateEligibilityAction,
  shortlistSourcingCandidateAction,
  submitSourcingShortlistAction,
  closeSourcingRequestNoSourceAction,
  cancelSourcingRequestAction,
  reopenSourcingRequestAction,
} from "../actions.ts";

/**
 * Sourcing request detail (PRC-256, CG-S11-PRC-007): the inherited demand
 * snapshot/constraints (read-only except through the dedicated override RPC --
 * never a re-typeable form), the candidate longlist with exclusion-reason
 * chips and shortlist controls, lifecycle actions, and the lifecycle history.
 * Every mutating action below binds the CURRENT record_version at render time
 * (mirrors app/(tenant)/[tenantSlug]/procurement/compliance/vendors/
 * [vendorMasterRecordId]/page.tsx's own `.bind()`-per-row convention) -- a
 * concurrent edit between render and submit surfaces as a real stale_version
 * error from the RPC itself, not a silently-accepted overwrite.
 */
export default async function SourcingRequestDetailPage({ params }: { params: Promise<{ tenantSlug: string; sourcingRequestId: string }> }) {
  const { tenantSlug, sourcingRequestId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let request: Awaited<ReturnType<typeof getSourcingRequest>> | null = null;
  let candidates: Awaited<ReturnType<typeof listSourcingCandidates>> = [];
  let history: Awaited<ReturnType<typeof getSourcingRequestHistory>> = [];
  try {
    request = await getSourcingRequest(supabase, sourcingRequestId, access.authUserId);
    candidates = await listSourcingCandidates(supabase, sourcingRequestId, access.authUserId);
    history = await getSourcingRequestHistory(supabase, sourcingRequestId, access.authUserId);
  } catch (error) {
    if (!(error instanceof SourcingQueryError)) throw error;
    if (error.message.includes("sourcing_request_not_found")) {
      notFoundOrDenied = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !request || !request.id) {
    return <ErrorState description="Something went wrong loading this sourcing request. Please try again." />;
  }

  return (
    <SourcingDetailPanel
      request={request}
      candidates={candidates}
      history={history}
      submitAction={submitSourcingRequestAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
      overrideAction={overrideSourcingRequestConstraintsAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
      evaluateEligibilityAction={evaluateSourcingCandidateEligibilityAction.bind(null, tenantSlug, sourcingRequestId)}
      shortlistActionFor={(candidateId, expectedVersion, shortlisted) => shortlistSourcingCandidateAction.bind(null, tenantSlug, sourcingRequestId, candidateId, expectedVersion, shortlisted)}
      submitShortlistAction={submitSourcingShortlistAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
      closeNoSourceAction={closeSourcingRequestNoSourceAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
      cancelAction={cancelSourcingRequestAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
      reopenAction={reopenSourcingRequestAction.bind(null, tenantSlug, sourcingRequestId, request.recordVersion)}
    />
  );
}
