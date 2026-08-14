import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listTicketRoutingRules, listTicketRoutingRuleVersions, listTicketCategories, listTicketQueues, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { RoutingAdminPanel } from "./routing-admin-panel.tsx";
import { createTicketRoutingRuleAction, createTicketRoutingRuleVersionAction, publishTicketRoutingRuleVersionAction, previewTicketRoutingAction } from "../actions.ts";

/**
 * Ticket routing rule administration (HRT-290, CG-S12-HRT-018). A
 * tenant-scoped configuration surface, deliberately kept under `tickets/`
 * (never a separate top-level route) -- mirrors `tickets/sla/page.tsx`'s own
 * exact reasoning and shape. Every write here is TKT:Edit-gated at the RPC
 * layer; this page renders the forms for any tenant member and lets the
 * server enforce the bar, exactly like the queue/category catalog forms and
 * the SLA admin page already do.
 *
 * Channel is restricted to internal/customer -- helpdesk has no eligibility
 * model to route within (decision 2 of the migration: staffing there is
 * Supreme-Admin-only via the existing, unmodified
 * app.assign_helpdesk_ticket/app.transfer_helpdesk_support_queue, never
 * fought or duplicated here).
 */
export default async function TicketRoutingPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let rules: Awaited<ReturnType<typeof listTicketRoutingRules>> = [];
  let ruleVersionsByRule: Record<string, Awaited<ReturnType<typeof listTicketRoutingRuleVersions>>> = {};
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];
  let queues: Awaited<ReturnType<typeof listTicketQueues>> = [];

  try {
    [rules, categories, queues] = await Promise.all([
      listTicketRoutingRules(supabase, access.tenant.id, access.authUserId),
      listTicketCategories(supabase, access.tenant.id, access.authUserId),
      listTicketQueues(supabase, access.tenant.id, access.authUserId),
    ]);
    const ruleEntries = await Promise.all(rules.map(async (r) => [r.id, await listTicketRoutingRuleVersions(supabase, r.id, access.authUserId)] as const));
    ruleVersionsByRule = Object.fromEntries(ruleEntries);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading routing configuration. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Ticket routing rules</h1>
        <p className="text-xs text-neutral-500">
          A ticket auto-routed via the assignment drawer applies the ONE published rule version that matches its channel/category/priority -- explainable, versioned, never a hidden heuristic.
        </p>
      </div>

      <RoutingAdminPanel
        rules={rules}
        ruleVersionsByRule={ruleVersionsByRule}
        categories={categories}
        queues={queues}
        createRuleAction={createTicketRoutingRuleAction.bind(null, tenantSlug)}
        createRuleVersionAction={(ruleId: string) => createTicketRoutingRuleVersionAction.bind(null, tenantSlug, ruleId)}
        publishRuleVersionAction={(versionId: string, expectedVersion: number) => publishTicketRoutingRuleVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
        previewAction={previewTicketRoutingAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
