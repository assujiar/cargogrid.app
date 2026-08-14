import NextLink from "next/link";
import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listTicketBreachQueue, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";

const STATUS_TONE: Record<string, StatusTone> = { new: "info", open: "info", pending: "warning", on_hold: "warning", resolved: "success", closed: "neutral", cancelled: "neutral" };
const ESCALATION_STATUS_TONE: Record<string, StatusTone> = { active: "danger", acknowledged: "warning", resolved: "neutral" };

/**
 * Breach/stuck ticket queue browser (HRT-291, CG-S12-HRT-019, section 15's
 * own "breach/stuck queue" UI-impact requirement). A dedicated, minimal
 * view -- deliberately NOT a tab bolted onto `tickets/page.tsx`'s existing
 * "My Tickets"/"Queue" toggle, because both of those read from app.
 * list_tickets/app.list_my_tickets (already-applied, already-VERIFIED
 * migrations this task may never edit in place), and widening either
 * RETURNS TABLE shape for one new column would be a real, unwarranted
 * signature change rippling through every existing caller/test -- disclosed
 * (taxonomy C-23), not an oversight. app.list_ticket_breach_queue is its
 * own staff-scoped (per-row app.is_ticket_staff), cursor-paginated read.
 */
export default async function TicketBreachQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ minLevel?: string }>;
}) {
  const { tenantSlug } = await params;
  const { minLevel } = await searchParams;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const minLevelFilter = minLevel && /^\d+$/.test(minLevel) ? Number(minLevel) : null;

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let rows: Awaited<ReturnType<typeof listTicketBreachQueue>> = [];

  try {
    rows = await listTicketBreachQueue(supabase, access.tenant.id, access.authUserId, { minLevel: minLevelFilter, limit: 100 });
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the breach queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Breach / stuck tickets</h1>
          <p className="text-xs text-neutral-500">Every ticket with an active or acknowledged escalation, most-recently-triggered first -- staff-scoped, never a raw cross-queue directory.</p>
        </div>
        <NextLink href={`/${tenantSlug}/tickets/escalation`} className="text-xs text-info hover:underline">
          Escalation policies
        </NextLink>
      </div>

      {rows.length === 0 ? (
        <EmptyState title="Nothing escalated" description="No ticket you can see currently has an open escalation." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-xs font-medium text-neutral-500">
                <th className="p-2">Ticket</th>
                <th className="p-2">Subject</th>
                <th className="p-2">Status</th>
                <th className="p-2">Priority</th>
                <th className="p-2">Queue</th>
                <th className="p-2">Level</th>
                <th className="p-2">Escalation</th>
                <th className="p-2">Last triggered</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.ticketId} className="border-t border-neutral-100">
                  <td className="p-2 text-sm">
                    <NextLink href={`/${tenantSlug}/tickets/${r.ticketId}`} className="text-primary underline">
                      {r.ticketNumber}
                    </NextLink>
                  </td>
                  <td className="p-2 text-sm">{r.subject}</td>
                  <td className="p-2 text-sm">
                    <StatusBadge tone={STATUS_TONE[r.status] ?? "neutral"} label={r.status.replace(/_/g, " ")} />
                  </td>
                  <td className="p-2 text-sm">{r.priority}</td>
                  <td className="p-2 text-xs text-neutral-500">{r.queueCode}</td>
                  <td className="p-2 text-xs text-neutral-500">
                    Level {r.currentLevel} ({r.lastTriggerType.replace(/_/g, " ")})
                  </td>
                  <td className="p-2 text-xs">
                    <StatusBadge tone={ESCALATION_STATUS_TONE[r.escalationStatus] ?? "neutral"} label={r.escalationStatus} />
                    {r.acknowledgedAt ? <span className="ml-1 text-neutral-500">acked</span> : null}
                  </td>
                  <td className="p-2 text-xs text-neutral-500">{new Date(r.lastTriggeredAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
