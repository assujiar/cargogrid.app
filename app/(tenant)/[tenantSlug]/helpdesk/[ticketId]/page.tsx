import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getTenantHelpdeskTicket, listTenantHelpdeskTicketMessages, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { HelpdeskDetailPanel } from "./helpdesk-detail-panel.tsx";
import { replyToHelpdeskTicketAction, transitionHelpdeskTicketStatusAction } from "../actions.ts";

/**
 * Tenant-to-CargoGrid helpdesk thread/detail view (HRT-288, CG-S12-HRT-016).
 * Uses ONLY the tenant-safe projection RPCs (app.get_tenant_helpdesk_ticket/
 * app.list_tenant_helpdesk_ticket_messages) -- an internal/customer-channel
 * ticket id, another tenant's helpdesk case id, or a genuinely nonexistent
 * id are all indistinguishable here (getTenantHelpdeskTicket returns null
 * for all three), so this page renders a plain 404 rather than a
 * "forbidden" state that would disclose which case occurred. Neither the
 * assigned CargoGrid support queue/team nor the assigned staffer's identity
 * is ever fetched or rendered here -- that is Platform-internal routing
 * metadata, deliberately never exposed to a tenant.
 */
export default async function HelpdeskDetailPage({ params }: { params: Promise<{ tenantSlug: string; ticketId: string }> }) {
  const { tenantSlug, ticketId } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let detail: Awaited<ReturnType<typeof getTenantHelpdeskTicket>> = null;
  let messages: Awaited<ReturnType<typeof listTenantHelpdeskTicketMessages>> = [];

  try {
    detail = await getTenantHelpdeskTicket(supabase, ticketId, access.authUserId);
    if (detail) {
      messages = await listTenantHelpdeskTicketMessages(supabase, ticketId, access.authUserId, { limit: 200 });
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
    <HelpdeskDetailPanel
      detail={detail}
      messages={messages}
      replyAction={replyToHelpdeskTicketAction.bind(null, tenantSlug, ticketId)}
      transitionAction={(toStatus) => transitionHelpdeskTicketStatusAction.bind(null, tenantSlug, ticketId, recordVersion, toStatus)}
    />
  );
}
