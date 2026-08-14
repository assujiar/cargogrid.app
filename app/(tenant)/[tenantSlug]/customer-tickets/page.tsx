import { notFound } from "next/navigation";
import { resolveCustomerTicketAccessForRequest } from "../../../../lib/portal/resolve-customer-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerAccountsForActor, listCustomerTicketCategories, listCustomerTickets, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerTicketsPanel } from "./customer-tickets-panel.tsx";
import { createCustomerTicketAction } from "./actions.ts";

/**
 * Customer ticket list/create view (HRT-287, CG-S12-HRT-015) -- the bounded
 * Layer 4 verification surface named in section 15: "minimal bounded
 * customer ticket create/list/detail/thread surfaces sufficient for
 * isolation and contract verification... full portal shell/dashboard/
 * account management remains Step 13." A genuinely separate top-level route
 * family from `tickets/` (the internal/staff workspace), gated by
 * `resolveCustomerTicketAccessForRequest` (customer_user layer only, never
 * org_user/tenant_admin). Every account/category/ticket shown here is
 * already scoped server-side by the owning RPC
 * (app.resolve_customer_owner_account_scope) -- this page never applies its
 * own additional filtering, since the RPC layer is the actual enforcing
 * boundary.
 */
export default async function CustomerTicketsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof listCustomerAccountsForActor>> = [];
  let categories: Awaited<ReturnType<typeof listCustomerTicketCategories>> = [];
  let tickets: Awaited<ReturnType<typeof listCustomerTickets>> = [];

  try {
    [accounts, categories, tickets] = await Promise.all([
      listCustomerAccountsForActor(supabase, access.tenant.id, access.authUserId),
      listCustomerTicketCategories(supabase, access.tenant.id, access.authUserId),
      listCustomerTickets(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your support tickets. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Support tickets</h1>
        <p className="text-xs text-neutral-500">Raise and track service issues for your account. Internal notes and other customers&apos; tickets are never shown here.</p>
      </div>

      <CustomerTicketsPanel tenantSlug={tenantSlug} accounts={accounts} categories={categories} tickets={tickets} createTicketAction={createCustomerTicketAction.bind(null, tenantSlug)} />
    </div>
  );
}
