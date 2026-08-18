import { notFound } from "next/navigation";
import { resolveCustomerTicketAccessForRequest } from "../../../../lib/portal/resolve-customer-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerAccountsForActor, listCustomerTicketCategories, listCustomerTickets, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerTicketsPanel } from "./customer-tickets-panel.tsx";
import { createCustomerTicketAction, searchCustomerTicketPortalLinkCandidatesPrecreateAction } from "./actions.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
 *
 * CPL-311 (CG-S13-CPL-013, Prompt 311, Invoice and Billing Visibility) adds
 * optional `disputeInvoiceId`/`disputeInvoiceNumber` query params -- a real,
 * working "open a dispute" deep link from the customer invoice detail page
 * (app/(tenant)/[tenantSlug]/customer-invoices/[invoiceId]/), pre-filling the
 * create-ticket form below rather than building a parallel dispute
 * mechanism. `disputeInvoiceId` is never trusted as an authorization
 * grant here -- `createCustomerTicketAction` (./actions.ts) re-validates it
 * through the ALREADY-VERIFIED HRT-292 `app.link_ticket_record`'s own
 * independent domain check before ever linking it to the created ticket.
 *
 * CPL-313 (CG-S13-CPL-015, Prompt 313, Complaint and Ticket) adds two
 * things: (1) `CustomerPortalNav` -- the first checkpoint to wire this
 * standalone route family into the shared portal nav, per this task's own
 * explicit instruction; (2) a generic linked-record picker on the create
 * form (shipment/warehouse order/invoice/document), independent of the
 * CPL-311 dispute-deep-link mechanism above -- see `customer-tickets-panel
 * .tsx`'s own `LinkRecordPicker` component and `./actions.ts`'s own
 * `searchCustomerTicketPortalLinkCandidatesPrecreateAction`/generic
 * `linkEntityType`/`linkEntityId`/`linkRelationship` form fields.
 */
export default async function CustomerTicketsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ disputeInvoiceId?: string; disputeInvoiceNumber?: string }>;
}) {
  const { tenantSlug } = await params;
  const { disputeInvoiceId: rawDisputeInvoiceId, disputeInvoiceNumber } = await searchParams;
  const access = await resolveCustomerTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  // A malformed disputeInvoiceId is silently ignored (never surfaced as an
  // error) -- the downstream link RPC is deny-by-default and would reject
  // it anyway; this check only avoids pre-filling the form from an obviously
  // non-uuid value.
  const disputeInvoiceId = rawDisputeInvoiceId && UUID_RE.test(rawDisputeInvoiceId) ? rawDisputeInvoiceId : null;
  const initialDispute = disputeInvoiceId ? { invoiceId: disputeInvoiceId, invoiceNumber: disputeInvoiceNumber?.trim() || disputeInvoiceId } : null;

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
      <CustomerPortalNav tenantSlug={tenantSlug} current="tickets" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Support tickets</h1>
        <p className="text-xs text-neutral-500">Raise and track service issues for your account. Internal notes and other customers&apos; tickets are never shown here.</p>
      </div>

      <CustomerTicketsPanel
        tenantSlug={tenantSlug}
        accounts={accounts}
        categories={categories}
        tickets={tickets}
        createTicketAction={createCustomerTicketAction.bind(null, tenantSlug)}
        searchLinkCandidatesAction={searchCustomerTicketPortalLinkCandidatesPrecreateAction.bind(null, tenantSlug)}
        initialDispute={initialDispute}
      />
    </div>
  );
}
