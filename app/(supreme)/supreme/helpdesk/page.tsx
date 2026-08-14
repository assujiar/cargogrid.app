import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listPlatformHelpdeskTickets, listSupportQueues, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { CreateSupportQueueForm } from "./create-support-queue-form.tsx";
import type { PlatformHelpdeskTicketListRow, TicketStatus } from "../../../../server/contracts/ticketing/ticketing.ts";

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function PlatformHelpdeskRow({ ticket }: { ticket: PlatformHelpdeskTicketListRow }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/supreme/helpdesk/${ticket.id}`} className="text-primary underline">
          {ticket.ticketNumber}
        </Link>
      </td>
      <td className="p-2 text-xs text-neutral-500">{ticket.tenantName}</td>
      <td className="p-2 text-sm">{ticket.subject}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[ticket.status]} label={ticket.status.replace(/_/g, " ")} />
      </td>
      <td className="p-2 text-xs text-neutral-500">{ticket.severity ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.supportQueueCode ?? "unassigned"}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.assigneeEmail ?? "unassigned"}</td>
    </tr>
  );
}

/**
 * CargoGrid support (Supreme Admin) cross-tenant helpdesk queue (HRT-288,
 * CG-S12-HRT-016) -- the ONE deliberate cross-tenant read surface this
 * capability introduces (`app.list_platform_helpdesk_tickets`), scoped
 * strictly to `channel = 'helpdesk'`. Per this checkpoint's own bounded
 * Platform-support-staff decision, this workspace is Supreme-Admin-only --
 * there is no separate, narrower "support agent" role in this repository
 * yet (disclosed limitation, see the build log).
 */
export default async function SupremeHelpdeskPage() {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let tickets: Awaited<ReturnType<typeof listPlatformHelpdeskTickets>> = [];
  let queues: Awaited<ReturnType<typeof listSupportQueues>> = [];

  try {
    [tickets, queues] = await Promise.all([listPlatformHelpdeskTickets(supabase, access.authUserId, { limit: 100 }), listSupportQueues(supabase, access.authUserId)]);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the CargoGrid support queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">CargoGrid support queue</h1>
        <p className="text-xs text-neutral-500">Every tenant&apos;s own governed helpdesk case, across the whole platform. A case here never grants access to a tenant&apos;s business data by itself.</p>
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {tickets.length === 0 ? (
          <EmptyState title="No support cases yet" description="Cases tenants open with CargoGrid support will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Case</th>
                  <th className="p-2">Tenant</th>
                  <th className="p-2">Subject</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Severity</th>
                  <th className="p-2">Queue</th>
                  <th className="p-2">Assignee</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map((t) => (
                  <PlatformHelpdeskRow key={t.id} ticket={t} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Support queues</h2>
        <p className="text-xs text-neutral-500">Platform-internal routing/triage teams — never visible to any tenant.</p>
        <ul className="flex flex-wrap gap-2 text-xs text-neutral-700">
          {queues.map((q) => (
            <li key={q.id} className="rounded-full border border-neutral-200 px-2 py-1">
              {q.code} — {q.name}
            </li>
          ))}
        </ul>
        <CreateSupportQueueForm />
      </section>
    </div>
  );
}
