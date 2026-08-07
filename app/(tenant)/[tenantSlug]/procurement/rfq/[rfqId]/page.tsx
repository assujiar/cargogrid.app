import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getRfq,
  listRfqRequirementLines,
  listRfqInvitations,
  listRfqClarifications,
  listRfqResponses,
  listRfqResponseAttachments,
  getRfqHistory,
  RfqQueryError,
} from "../../../../../../server/queries/rfq.ts";
import type { RfqResponseAttachment } from "../../../../../../server/contracts/rfq/rfq.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { RfqDetailPanel } from "./rfq-detail-panel.tsx";
import {
  reviseRfqAction,
  issueRfqAction,
  inviteAdditionalRfqVendorAction,
  extendRfqDeadlineAction,
  closeRfqForComparisonAction,
  cancelRfqAction,
  declineRfqInvitationAction,
  recordRfqClarificationAction,
  answerRfqClarificationAction,
  submitRfqResponseAction,
  withdrawRfqResponseAction,
} from "../actions.ts";

/**
 * RFQ detail (PRC-257, CG-S11-PRC-008): the inherited requirements (read-only
 * except through the governed revise flow), invited-vendor panel, decline
 * capture, clarification timeline, versioned response capture/comparison
 * preview, and lifecycle history. Every mutating action below binds the
 * CURRENT record_version at render time (mirrors app/(tenant)/[tenantSlug]/
 * procurement/sourcing/[sourcingRequestId]/page.tsx's own `.bind()`-per-row
 * convention) -- a concurrent edit between render and submit surfaces as a
 * real stale_version error from the RPC itself, not a silently-accepted
 * overwrite.
 */
export default async function RfqDetailPage({ params }: { params: Promise<{ tenantSlug: string; rfqId: string }> }) {
  const { tenantSlug, rfqId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let rfq: Awaited<ReturnType<typeof getRfq>> | null = null;
  let requirementLines: Awaited<ReturnType<typeof listRfqRequirementLines>> = [];
  let invitations: Awaited<ReturnType<typeof listRfqInvitations>> = [];
  let clarifications: Awaited<ReturnType<typeof listRfqClarifications>> = [];
  let responses: Awaited<ReturnType<typeof listRfqResponses>> = [];
  let history: Awaited<ReturnType<typeof getRfqHistory>> = [];
  const attachmentsByResponseId = new Map<string, RfqResponseAttachment[]>();
  try {
    rfq = await getRfq(supabase, rfqId, access.authUserId);
    requirementLines = await listRfqRequirementLines(supabase, rfqId, access.authUserId);
    invitations = await listRfqInvitations(supabase, rfqId, access.authUserId);
    clarifications = await listRfqClarifications(supabase, rfqId, access.authUserId);
    responses = await listRfqResponses(supabase, rfqId, access.authUserId);
    history = await getRfqHistory(supabase, rfqId, access.authUserId);
    // Every response's own attachment set (app.list_rfq_response_attachments,
    // design note 9's C-10 re-validation happens at capture time, not here --
    // this is a plain, already-authorized read of what was captured).
    for (const response of responses) {
      attachmentsByResponseId.set(response.id, await listRfqResponseAttachments(supabase, response.id, access.authUserId));
    }
  } catch (error) {
    if (!(error instanceof RfqQueryError)) throw error;
    if (error.message.includes("rfq_not_found")) {
      notFoundOrDenied = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !rfq || !rfq.id) {
    return <ErrorState description="Something went wrong loading this RFQ. Please try again." />;
  }

  return (
    <RfqDetailPanel
      rfq={rfq}
      requirementLines={requirementLines}
      invitations={invitations}
      clarifications={clarifications}
      responses={responses}
      attachmentsByResponseId={attachmentsByResponseId}
      history={history}
      reviseAction={reviseRfqAction.bind(null, tenantSlug, rfqId, rfq.recordVersion)}
      issueAction={issueRfqAction.bind(null, tenantSlug, rfqId, rfq.recordVersion)}
      inviteAdditionalAction={inviteAdditionalRfqVendorAction.bind(null, tenantSlug, rfqId)}
      extendDeadlineAction={extendRfqDeadlineAction.bind(null, tenantSlug, rfqId, rfq.recordVersion)}
      closeAction={closeRfqForComparisonAction.bind(null, tenantSlug, rfqId, rfq.recordVersion)}
      cancelAction={cancelRfqAction.bind(null, tenantSlug, rfqId, rfq.recordVersion)}
      declineInvitationActionFor={(invitationId, expectedVersion) => declineRfqInvitationAction.bind(null, tenantSlug, rfqId, invitationId, expectedVersion)}
      recordClarificationAction={recordRfqClarificationAction.bind(null, tenantSlug, rfqId)}
      answerClarificationActionFor={(clarificationId, expectedVersion) => answerRfqClarificationAction.bind(null, tenantSlug, rfqId, clarificationId, expectedVersion)}
      submitResponseActionFor={(invitationId) => submitRfqResponseAction.bind(null, tenantSlug, rfqId, invitationId)}
      withdrawResponseActionFor={(responseId, expectedVersion) => withdrawRfqResponseAction.bind(null, tenantSlug, rfqId, responseId, expectedVersion)}
    />
  );
}
