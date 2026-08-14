import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listHelpdeskTicketCategories, listTenantHelpdeskTickets, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { HelpdeskPanel } from "./helpdesk-panel.tsx";
import { createHelpdeskTicketAction } from "./actions.ts";

/**
 * Tenant-to-CargoGrid helpdesk list/create view (HRT-288, CG-S12-HRT-016).
 * Sibling route family of `tickets/`/`customer-tickets/`, reusing the SAME
 * portal-entry guard `tickets/` already uses (`org_user`/`tenant_admin`
 * layer) -- the actual "who may open/see a case" authority is
 * `app._is_tenant_helpdesk_authorized` (tenant_admin OR a real TKT:Edit
 * role), enforced server-side by every RPC this page calls, never by this
 * route group alone. A support case here grants ZERO business-data access
 * on its own -- any CargoGrid support diagnostic access is a separate,
 * reasoned, time-bound, MFA-protected grant your organization approves
 * (unchanged PLT-115 flow), never something this ticket surface can create
 * or shortcut.
 */
export default async function HelpdeskPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let categories: Awaited<ReturnType<typeof listHelpdeskTicketCategories>> = [];
  let tickets: Awaited<ReturnType<typeof listTenantHelpdeskTickets>> = [];

  try {
    [categories, tickets] = await Promise.all([
      listHelpdeskTicketCategories(supabase, access.tenant.id, access.authUserId),
      listTenantHelpdeskTickets(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your CargoGrid support cases. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">CargoGrid support</h1>
        <p className="text-xs text-neutral-500">
          Open and track cases with CargoGrid Platform support. Available to tenant admins and TKT-configuration-authorized staff — an ordinary support case never grants CargoGrid access to your business data on its own.
        </p>
      </div>

      <HelpdeskPanel tenantSlug={tenantSlug} categories={categories} tickets={tickets} createTicketAction={createHelpdeskTicketAction.bind(null, tenantSlug)} />
    </div>
  );
}
