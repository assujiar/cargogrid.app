import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  getTicket,
  listTicketMessages,
  listTicketWatchers,
  listTicketEvents,
  listTicketQueues,
  listTicketCategories,
  listTicketQueueMembers,
  getTicketSlaClock,
  getTicketSlaStatusForRequester,
  listTicketAssignmentCandidates,
  listTicketAssignmentEvents,
  getTicketEscalation,
  getTicketEscalationStatusForRequester,
  listTicketEscalationEvents,
  listTicketLinkEvents,
  listTicketEscalationSuppressions,
  listTicketLinks,
  TicketQueryError,
} from "../../../../../server/queries/ticketing.ts";
import { listTicketKnowledgeArticleLinks, listTicketKnowledgeArticleLinksForRequester, KbQueryError } from "../../../../../server/queries/knowledge-base.ts";
import { linkTicketKnowledgeArticleAction, unlinkTicketKnowledgeArticleAction } from "../../knowledge-base/actions.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { TicketDetailPanel } from "./ticket-detail-panel.tsx";
import {
  replyToTicketAction,
  redactTicketMessageAction,
  addTicketWatcherAction,
  removeTicketWatcherAction,
  assignTicketAction,
  transferTicketQueueAction,
  updateTicketClassificationAction,
  transitionTicketStatusAction,
  startTicketSlaClockAction,
  pauseTicketSlaClockAction,
  resumeTicketSlaClockAction,
  claimTicketAction,
  acceptTicketAssignmentAction,
  declineTicketAssignmentAction,
  autoRouteTicketAction,
  escalateTicketAction,
  acknowledgeTicketEscalationAction,
  resolveTicketEscalationAction,
  suppressTicketEscalationAction,
  revokeTicketEscalationSuppressionAction,
  searchTicketLinkCandidatesAction,
  linkTicketRecordAction,
  unlinkTicketRecordAction,
  recordTicketLinkSummaryAccessAction,
} from "../actions.ts";

/**
 * Internal ticket thread/detail view (HRT-286, CG-S12-HRT-014). One
 * canonical conversation with an explicit, server-enforced public-reply vs.
 * internal-note distinction (decision 3) -- the requester never sees an
 * internal-visibility message anywhere on this page, because
 * app.list_ticket_messages itself never returns one to a non-staff caller
 * (the query, not this component, is what makes that structurally true).
 * Lifecycle/assignment/transfer/reclassification controls render only for a
 * staff viewer (`detail.isStaffViewer`, server-computed) -- a requester still
 * sees their own reply/cancel/reopen affordances, gated the same way at the
 * RPC layer (app._ticket_transition_authority).
 */
export default async function TicketDetailPage({ params }: { params: Promise<{ tenantSlug: string; ticketId: string }> }) {
  const { tenantSlug, ticketId } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let notFoundError = false;
  let loadFailed = false;
  let detail: Awaited<ReturnType<typeof getTicket>> = null;
  let messages: Awaited<ReturnType<typeof listTicketMessages>> = [];
  let watchers: Awaited<ReturnType<typeof listTicketWatchers>> = [];
  let events: Awaited<ReturnType<typeof listTicketEvents>> = [];
  let queues: Awaited<ReturnType<typeof listTicketQueues>> = [];
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];
  let queueMembers: Awaited<ReturnType<typeof listTicketQueueMembers>> = [];
  let slaClock: Awaited<ReturnType<typeof getTicketSlaClock>> = null;
  let slaStatusForRequester: Awaited<ReturnType<typeof getTicketSlaStatusForRequester>> = null;
  let kbLinks: Awaited<ReturnType<typeof listTicketKnowledgeArticleLinks>> = [];
  let kbLinksForRequester: Awaited<ReturnType<typeof listTicketKnowledgeArticleLinksForRequester>> = [];
  let assignmentCandidates: Awaited<ReturnType<typeof listTicketAssignmentCandidates>> = [];
  let assignmentEvents: Awaited<ReturnType<typeof listTicketAssignmentEvents>> = [];
  let escalation: Awaited<ReturnType<typeof getTicketEscalation>> = null;
  let escalationStatusForRequester: Awaited<ReturnType<typeof getTicketEscalationStatusForRequester>> = null;
  let escalationEvents: Awaited<ReturnType<typeof listTicketEscalationEvents>> = [];
  let suppressions: Awaited<ReturnType<typeof listTicketEscalationSuppressions>> = [];
  let ticketLinks: Awaited<ReturnType<typeof listTicketLinks>> = [];
  // ISS-2026-100: staff-only, and left empty for everyone else rather than fetched and hidden.
  // app.list_ticket_link_events re-authorizes its caller, so a requester fetch would simply be
  // refused -- but not asking at all is the honest shape: the link ledger records who looked at
  // which linked record, which is a staff access trail, not something a requester should read
  // about the people handling their ticket.
  let ticketLinkEvents: Awaited<ReturnType<typeof listTicketLinkEvents>> = [];

  try {
    detail = await getTicket(supabase, ticketId, access.authUserId);
    if (!detail) {
      notFoundError = true;
    } else {
      [messages, watchers, events, queues, categories, ticketLinks] = await Promise.all([
        listTicketMessages(supabase, ticketId, access.authUserId, { limit: 200 }),
        listTicketWatchers(supabase, ticketId, access.authUserId),
        listTicketEvents(supabase, ticketId, access.authUserId),
        listTicketQueues(supabase, access.tenant.id, access.authUserId),
        listTicketCategories(supabase, access.tenant.id, access.authUserId),
        // HRT-292: fetched for EVERY viewer who reaches this panel (staff,
        // requester, or watcher) -- unlike escalation/assignment, linking is
        // not staff-only (business rule: staff OR requester-side party may
        // link); app.list_ticket_links itself independently re-authorizes
        // every row for the calling principal, so there is nothing here for
        // a lesser-privileged viewer to over-see.
        listTicketLinks(supabase, ticketId, access.authUserId),
      ]);
      if (detail.isStaffViewer) {
        queueMembers = await listTicketQueueMembers(supabase, detail.queueId, access.authUserId);
        // HRT-289 decision 10: the STAFF-facing full SLA projection (calendar/
        // policy identity included) -- never derived from the requester-safe
        // projection below, and never shown to a requester.
        slaClock = await getTicketSlaClock(supabase, ticketId, access.authUserId);
        kbLinks = await listTicketKnowledgeArticleLinks(supabase, ticketId, access.authUserId);
        // HRT-290 (CG-S12-HRT-018): bounded to internal/customer -- both new
        // RPCs reject a helpdesk-channel ticket (channel_not_supported /
        // ticket_not_found), so this is skipped entirely for one, matching
        // the migration's own decision 2 rather than rendering a control
        // that would only ever error.
        if (detail.channel !== "helpdesk") {
          ticketLinkEvents = await listTicketLinkEvents(supabase, ticketId, access.authUserId);
          [assignmentCandidates, assignmentEvents] = await Promise.all([
            listTicketAssignmentCandidates(supabase, ticketId, access.authUserId),
            listTicketAssignmentEvents(supabase, ticketId, access.authUserId),
          ]);
          // HRT-291 (CG-S12-HRT-019): bounded to internal/customer, matching
          // HRT-290's own established guard -- both new staff-facing RPCs
          // reject a helpdesk-channel ticket.
          [escalation, escalationEvents, suppressions] = await Promise.all([
            getTicketEscalation(supabase, ticketId, access.authUserId),
            listTicketEscalationEvents(supabase, ticketId, access.authUserId),
            listTicketEscalationSuppressions(supabase, ticketId, access.authUserId),
          ]);
        }
      } else {
        // HRT-289 decision 10, security impact section 16: the requester sees
        // ONLY target/status via app.get_ticket_sla_status_for_requester --
        // never the staff projection, structurally (a different RPC, not a
        // client-side field filter).
        slaStatusForRequester = await getTicketSlaStatusForRequester(supabase, ticketId, access.authUserId);
        kbLinksForRequester = await listTicketKnowledgeArticleLinksForRequester(supabase, ticketId, access.authUserId);
        // HRT-291 (decision 12): the customer-safe is_escalated-only
        // projection -- never the staff-side escalation row.
        if (detail.channel !== "helpdesk") {
          escalationStatusForRequester = await getTicketEscalationStatusForRequester(supabase, ticketId, access.authUserId);
        }
      }
    }
  } catch (error) {
    if (!(error instanceof TicketQueryError) && !(error instanceof KbQueryError)) throw error;
    loadFailed = true;
  }

  if (notFoundError) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this ticket. Please try again." />;
  }

  const recordVersion = detail.recordVersion;

  return (
    <TicketDetailPanel
      tenantSlug={tenantSlug}
      detail={detail}
      messages={messages}
      watchers={watchers}
      events={events}
      queues={queues}
      categories={categories}
      queueMembers={queueMembers}
      slaClock={slaClock}
      slaStatusForRequester={slaStatusForRequester}
      kbLinks={kbLinks}
      kbLinksForRequester={kbLinksForRequester}
      assignmentCandidates={assignmentCandidates}
      assignmentEvents={assignmentEvents}
      escalation={escalation}
      escalationStatusForRequester={escalationStatusForRequester}
      ticketLinkEvents={ticketLinkEvents}
      escalationEvents={escalationEvents}
      suppressions={suppressions}
      replyAction={replyToTicketAction.bind(null, tenantSlug, ticketId)}
      redactAction={(messageId: string, expectedVersion: number) => redactTicketMessageAction.bind(null, tenantSlug, ticketId, messageId, expectedVersion)}
      addWatcherAction={addTicketWatcherAction.bind(null, tenantSlug, ticketId)}
      removeWatcherAction={(watcherId: string, expectedVersion: number) => removeTicketWatcherAction.bind(null, tenantSlug, ticketId, watcherId, expectedVersion)}
      assignAction={assignTicketAction.bind(null, tenantSlug, ticketId, recordVersion)}
      transferAction={transferTicketQueueAction.bind(null, tenantSlug, ticketId, recordVersion)}
      classifyAction={updateTicketClassificationAction.bind(null, tenantSlug, ticketId, recordVersion)}
      transitionAction={(toStatus) => transitionTicketStatusAction.bind(null, tenantSlug, ticketId, recordVersion, toStatus)}
      startSlaClockAction={startTicketSlaClockAction.bind(null, tenantSlug, ticketId)}
      pauseSlaClockAction={(expectedVersion: number) => pauseTicketSlaClockAction.bind(null, tenantSlug, ticketId, expectedVersion)}
      resumeSlaClockAction={(expectedVersion: number) => resumeTicketSlaClockAction.bind(null, tenantSlug, ticketId, expectedVersion)}
      claimAction={claimTicketAction.bind(null, tenantSlug, ticketId, recordVersion)}
      acceptAssignmentAction={acceptTicketAssignmentAction.bind(null, tenantSlug, ticketId, recordVersion)}
      declineAssignmentAction={declineTicketAssignmentAction.bind(null, tenantSlug, ticketId, recordVersion)}
      autoRouteAction={autoRouteTicketAction.bind(null, tenantSlug, ticketId, recordVersion)}
      escalateAction={escalateTicketAction.bind(null, tenantSlug, ticketId, recordVersion)}
      acknowledgeEscalationAction={(expectedVersion: number) => acknowledgeTicketEscalationAction.bind(null, tenantSlug, ticketId, expectedVersion)}
      resolveEscalationAction={(expectedVersion: number) => resolveTicketEscalationAction.bind(null, tenantSlug, ticketId, expectedVersion)}
      suppressEscalationAction={suppressTicketEscalationAction.bind(null, tenantSlug, ticketId)}
      revokeEscalationSuppressionAction={(suppressionId: string, expectedVersion: number) => revokeTicketEscalationSuppressionAction.bind(null, tenantSlug, ticketId, suppressionId, expectedVersion)}
      linkArticleAction={linkTicketKnowledgeArticleAction.bind(null, tenantSlug, ticketId)}
      unlinkArticleAction={(linkId: string, expectedVersion: number) => unlinkTicketKnowledgeArticleAction.bind(null, tenantSlug, ticketId, linkId, expectedVersion)}
      ticketLinks={ticketLinks}
      searchTicketLinksAction={searchTicketLinkCandidatesAction.bind(null, tenantSlug, ticketId)}
      linkTicketRecordAction={(entityType, entityId, relationship) => linkTicketRecordAction.bind(null, tenantSlug, ticketId, entityType, entityId, relationship)}
      unlinkTicketRecordAction={(linkId: string, expectedVersion: number) => unlinkTicketRecordAction.bind(null, tenantSlug, ticketId, linkId, expectedVersion)}
      markTicketLinkViewedAction={(linkId: string) => recordTicketLinkSummaryAccessAction.bind(null, tenantSlug, linkId, "summary_viewed")}
    />
  );
}
