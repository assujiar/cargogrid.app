import { notFound } from "next/navigation";
import { resolveSupremeAdminAccessForRequest } from "../../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getPlatformHelpdeskTicket, listTicketMessages, listTicketCategories, listSupportQueues, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { HelpdeskTriagePanel } from "./helpdesk-triage-panel.tsx";
import {
  replyToHelpdeskTicketAsStaffAction,
  transitionHelpdeskTicketStatusAsStaffAction,
  assignHelpdeskTicketAction,
  transferHelpdeskSupportQueueAction,
  updateHelpdeskTicketClassificationAction,
  linkHelpdeskSupportGrantAction,
} from "../actions.ts";

/**
 * CargoGrid support (Supreme Admin) helpdesk triage/thread view (HRT-288,
 * CG-S12-HRT-016). Uses the Platform-side projection
 * (`app.get_platform_helpdesk_ticket`) plus the generic staff-facing
 * message thread (`app.list_ticket_messages`, already correctly gated to
 * Supreme-Admin-only for a helpdesk ticket) -- shows tenant-visible AND
 * Platform-internal messages, explicitly labeled. The support-access
 * correlation form below is DISPLAY/AUDIT ONLY and never itself grants,
 * extends, or bypasses privileged tenant-data access.
 */
export default async function SupremeHelpdeskDetailPage({ params }: { params: Promise<{ ticketId: string }> }) {
  const { ticketId } = await params;
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let detail: Awaited<ReturnType<typeof getPlatformHelpdeskTicket>> = null;
  let messages: Awaited<ReturnType<typeof listTicketMessages>> = [];
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];
  let queues: Awaited<ReturnType<typeof listSupportQueues>> = [];

  try {
    detail = await getPlatformHelpdeskTicket(supabase, ticketId, access.authUserId);
    if (detail) {
      [messages, categories, queues] = await Promise.all([
        listTicketMessages(supabase, ticketId, access.authUserId, { limit: 500 }),
        listTicketCategories(supabase, detail.tenantId, access.authUserId),
        listSupportQueues(supabase, access.authUserId),
      ]);
    }
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (!detail && !loadFailed) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this support case. Please try again." />;
  }

  const recordVersion = detail.recordVersion;

  return (
    <HelpdeskTriagePanel
      detail={detail}
      messages={messages}
      categories={categories}
      queues={queues}
      replyAction={replyToHelpdeskTicketAsStaffAction.bind(null, ticketId)}
      transitionAction={(toStatus) => transitionHelpdeskTicketStatusAsStaffAction.bind(null, ticketId, recordVersion, toStatus)}
      assignAction={assignHelpdeskTicketAction.bind(null, ticketId, recordVersion)}
      transferAction={transferHelpdeskSupportQueueAction.bind(null, ticketId, recordVersion)}
      classifyAction={updateHelpdeskTicketClassificationAction.bind(null, ticketId, recordVersion)}
      linkGrantAction={linkHelpdeskSupportGrantAction.bind(null, ticketId, recordVersion)}
    />
  );
}
