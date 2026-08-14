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
  TicketQueryError,
} from "../../../../../server/queries/ticketing.ts";
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

  try {
    detail = await getTicket(supabase, ticketId, access.authUserId);
    if (!detail) {
      notFoundError = true;
    } else {
      [messages, watchers, events, queues, categories] = await Promise.all([
        listTicketMessages(supabase, ticketId, access.authUserId, { limit: 200 }),
        listTicketWatchers(supabase, ticketId, access.authUserId),
        listTicketEvents(supabase, ticketId, access.authUserId),
        listTicketQueues(supabase, access.tenant.id, access.authUserId),
        listTicketCategories(supabase, access.tenant.id, access.authUserId),
      ]);
      if (detail.isStaffViewer) {
        queueMembers = await listTicketQueueMembers(supabase, detail.queueId, access.authUserId);
      }
    }
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
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
      replyAction={replyToTicketAction.bind(null, tenantSlug, ticketId)}
      redactAction={(messageId: string, expectedVersion: number) => redactTicketMessageAction.bind(null, tenantSlug, ticketId, messageId, expectedVersion)}
      addWatcherAction={addTicketWatcherAction.bind(null, tenantSlug, ticketId)}
      removeWatcherAction={(watcherId: string, expectedVersion: number) => removeTicketWatcherAction.bind(null, tenantSlug, ticketId, watcherId, expectedVersion)}
      assignAction={assignTicketAction.bind(null, tenantSlug, ticketId, recordVersion)}
      transferAction={transferTicketQueueAction.bind(null, tenantSlug, ticketId, recordVersion)}
      classifyAction={updateTicketClassificationAction.bind(null, tenantSlug, ticketId, recordVersion)}
      transitionAction={(toStatus) => transitionTicketStatusAction.bind(null, tenantSlug, ticketId, recordVersion, toStatus)}
    />
  );
}
