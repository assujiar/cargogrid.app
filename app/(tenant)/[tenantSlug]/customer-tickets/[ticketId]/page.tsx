import { notFound } from "next/navigation";
import { resolveCustomerTicketAccessForRequest } from "../../../../../lib/portal/resolve-customer-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerTicket, listCustomerTicketMessages, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerTicketDetailPanel } from "./customer-ticket-detail-panel.tsx";
import { replyToCustomerTicketAction, transitionCustomerTicketStatusAction } from "../actions.ts";

/**
 * Customer ticket thread/detail view (HRT-287, CG-S12-HRT-015). Uses ONLY
 * the customer-safe projection RPCs (app.get_customer_ticket/app.
 * list_customer_ticket_messages) -- an internal-channel ticket id, another
 * account's ticket id, or a genuinely nonexistent id are all indistinguishable
 * here (getCustomerTicket returns null for all three), which is why this
 * page renders a plain 404 rather than a "forbidden" state that would
 * disclose which case occurred.
 */
export default async function CustomerTicketDetailPage({ params }: { params: Promise<{ tenantSlug: string; ticketId: string }> }) {
  const { tenantSlug, ticketId } = await params;
  const access = await resolveCustomerTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let detail: Awaited<ReturnType<typeof getCustomerTicket>> = null;
  let messages: Awaited<ReturnType<typeof listCustomerTicketMessages>> = [];

  try {
    detail = await getCustomerTicket(supabase, ticketId, access.authUserId);
    if (detail) {
      messages = await listCustomerTicketMessages(supabase, ticketId, access.authUserId, { limit: 200 });
    }
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (!detail && !loadFailed) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this ticket. Please try again." />;
  }

  const recordVersion = detail.recordVersion;

  return (
    <CustomerTicketDetailPanel
      detail={detail}
      messages={messages}
      replyAction={replyToCustomerTicketAction.bind(null, tenantSlug, ticketId)}
      transitionAction={(toStatus) => transitionCustomerTicketStatusAction.bind(null, tenantSlug, ticketId, recordVersion, toStatus)}
    />
  );
}
