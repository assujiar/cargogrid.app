import NextLink from "next/link";
import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listTicketQueues, listTicketCategories, listTickets, listMyTickets, getTicketQueueWorkload, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { listOrgUnits, toOrgHierarchyRpcClient, OrgHierarchyQueryError } from "../../../../server/queries/org-hierarchy.ts";
import type { TicketStatus, TicketQueueWorkloadRow } from "../../../../server/contracts/ticketing/ticketing.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { TicketsListPanel } from "./tickets-list-panel.tsx";
import { createTicketAction, createTicketQueueAction, createTicketCategoryAction, addTicketQueueMemberAction, setTicketCategoryCustomerVisibilityAction } from "./actions.ts";

/**
 * Internal ticket queue/list view (HRT-286, CG-S12-HRT-014) -- the first
 * capability of the Ticket Channels and Conversation workstream, a sibling
 * of HRIS rather than a sub-feature of it (hence the dedicated top-level
 * `tickets/` route family, section 15). Two tabs sharing one page: "My
 * Tickets" (app.list_my_tickets, self-scoped) and "Queue" (app.list_tickets,
 * scoped server-side by app.can_access_ticket -- a bare requester sees the
 * SAME rows either tab shows; only staff/service-admins see additional rows
 * in the Queue tab). The queue/category catalog and a create-ticket form are
 * always shown -- any Layer 3 tenant user may file an internal ticket with
 * no special permission (section 21's own main flow), matching
 * app.create_ticket's own self-service, identity-resolved-only design.
 */
export default async function TicketsListPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; view?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, view } = await searchParams;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const statusFilter = (status && status.length > 0 ? (status as TicketStatus) : null) ?? null;
  const showQueueView = view === "queue";

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let queues: Awaited<ReturnType<typeof listTicketQueues>> = [];
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];
  let tickets: Awaited<ReturnType<typeof listTickets>> = [];
  let myTickets: Awaited<ReturnType<typeof listMyTickets>> = [];
  let orgUnits: { id: string; name: string; unitType: string }[] = [];
  let workloadByQueue: Record<string, readonly TicketQueueWorkloadRow[]> = {};

  try {
    [queues, categories] = await Promise.all([listTicketQueues(supabase, access.tenant.id, access.authUserId), listTicketCategories(supabase, access.tenant.id, access.authUserId)]);
    if (showQueueView) {
      tickets = await listTickets(supabase, access.tenant.id, access.authUserId, { status: statusFilter, limit: 50 });
    } else {
      myTickets = await listMyTickets(supabase, access.tenant.id, access.authUserId, { status: statusFilter, limit: 50 });
    }

    // HRT-290 (CG-S12-HRT-018, section 17 "workload indicators"): a live,
    // read-only aggregation per queue -- app.get_ticket_queue_workload
    // itself refuses a caller who is neither an active member of that
    // specific queue nor TKT:Edit/TKT:Assign, so this silently omits
    // whichever queues the caller cannot view rather than surfacing a
    // partial-failure error for an ordinary, expected authorization
    // boundary.
    const workloadEntries = await Promise.all(
      queues.map(async (q) => {
        try {
          return [q.id, await getTicketQueueWorkload(supabase, q.id, access.authUserId)] as const;
        } catch {
          return [q.id, null] as const;
        }
      }),
    );
    workloadByQueue = Object.fromEntries(workloadEntries.filter((entry): entry is [string, TicketQueueWorkloadRow[]] => entry[1] !== null));

    // CG-AUDIT-2026-09-02 Ø1-query-layer (missed by the cluster-7 sweep): this
    // used to be a direct `.from("org_units")` read -- `app` is not exposed to
    // PostgREST (supabase/config.toml), so it has never worked in production,
    // always throwing and taking down this entire page. `listOrgUnits` is the
    // same domain-agnostic ("any active tenant member") picker cluster-7 built
    // for exactly this shape, already used by 5 HRIS call sites.
    orgUnits = await listOrgUnits(toOrgHierarchyRpcClient(supabase), access.tenant.id, { statusFilter: "active" });
  } catch (error) {
    if (!(error instanceof TicketQueryError) && !(error instanceof OrgHierarchyQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the ticketing workspace. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Tickets</h1>
          <p className="text-xs text-neutral-500">Internal and interdepartmental service requests -- one canonical ticket model, shared across every future channel.</p>
        </div>
        <div className="flex items-center gap-3 text-xs">
          <NextLink href={`/${tenantSlug}/tickets/routing`} className="text-info hover:underline">
            Routing rules
          </NextLink>
          <NextLink href={`/${tenantSlug}/tickets/sla`} className="text-info hover:underline">
            SLA policies &amp; calendars
          </NextLink>
          <NextLink href={`/${tenantSlug}/tickets/escalation`} className="text-info hover:underline">
            Escalation policies
          </NextLink>
          <NextLink href={`/${tenantSlug}/tickets/breach-queue`} className="text-info hover:underline">
            Breach queue
          </NextLink>
          <NextLink href={`/${tenantSlug}/knowledge-base`} className="text-info hover:underline">
            Knowledge base
          </NextLink>
        </div>
      </div>

      <TicketsListPanel
        tenantSlug={tenantSlug}
        queues={queues}
        categories={categories}
        tickets={tickets}
        myTickets={myTickets}
        orgUnits={orgUnits}
        workloadByQueue={workloadByQueue}
        showQueueView={showQueueView}
        statusFilter={statusFilter}
        createTicketAction={createTicketAction.bind(null, tenantSlug)}
        createQueueAction={createTicketQueueAction.bind(null, tenantSlug)}
        createCategoryAction={createTicketCategoryAction.bind(null, tenantSlug)}
        addQueueMemberAction={addTicketQueueMemberAction.bind(null, tenantSlug)}
        setCategoryCustomerVisibilityAction={(categoryId, customerVisible) => setTicketCategoryCustomerVisibilityAction.bind(null, tenantSlug, categoryId, customerVisible)}
      />
    </div>
  );
}
