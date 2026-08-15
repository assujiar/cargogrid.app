import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listTicketEscalationPolicies,
  listTicketEscalationPolicyVersions,
  listTicketEscalationLevels,
  listTicketCategories,
  listTicketQueues,
  TicketQueryError,
} from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EscalationAdminPanel } from "./escalation-admin-panel.tsx";
import {
  createTicketEscalationPolicyAction,
  createTicketEscalationPolicyVersionAction,
  addTicketEscalationLevelAction,
  publishTicketEscalationPolicyVersionAction,
  previewTicketEscalationAction,
} from "../actions.ts";

/**
 * Ticket escalation policy administration (HRT-291, CG-S12-HRT-019). A
 * tenant-scoped configuration surface, deliberately kept under `tickets/`
 * (never a separate top-level route) -- mirrors `tickets/routing/page.tsx`
 * and `tickets/sla/page.tsx`'s own exact shape and reasoning. Every write
 * here is TKT:Edit-gated at the RPC layer; this page renders the forms for
 * any tenant member and lets the server enforce the bar.
 *
 * Channel is restricted to internal/customer -- helpdesk has no
 * non-Supreme-Admin escalation model, matching HRT-288/290's own
 * precedent-setting decision, reused here rather than fought or duplicated.
 */
export default async function TicketEscalationPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let policies: Awaited<ReturnType<typeof listTicketEscalationPolicies>> = [];
  let versionsByPolicy: Record<string, Awaited<ReturnType<typeof listTicketEscalationPolicyVersions>>> = {};
  let levelsByVersion: Record<string, Awaited<ReturnType<typeof listTicketEscalationLevels>>> = {};
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];
  let queues: Awaited<ReturnType<typeof listTicketQueues>> = [];

  try {
    [policies, categories, queues] = await Promise.all([
      listTicketEscalationPolicies(supabase, access.tenant.id, access.authUserId),
      listTicketCategories(supabase, access.tenant.id, access.authUserId),
      listTicketQueues(supabase, access.tenant.id, access.authUserId),
    ]);
    const policyEntries = await Promise.all(policies.map(async (p) => [p.id, await listTicketEscalationPolicyVersions(supabase, p.id, access.authUserId)] as const));
    versionsByPolicy = Object.fromEntries(policyEntries);
    const allVersions = Object.values(versionsByPolicy).flat();
    const versionEntries = await Promise.all(allVersions.map(async (v) => [v.id, await listTicketEscalationLevels(supabase, v.id, access.authUserId)] as const));
    levelsByVersion = Object.fromEntries(versionEntries);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading escalation configuration. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Ticket escalation policies</h1>
        <p className="text-xs text-neutral-500">
          Versioned functional, hierarchical and SLA-driven escalation -- a ticket auto-escalates through the ONE published policy version that matches its channel/category/priority/queue, one level at a time, explainable and never a hidden heuristic.
        </p>
      </div>

      <EscalationAdminPanel
        policies={policies}
        versionsByPolicy={versionsByPolicy}
        levelsByVersion={levelsByVersion}
        categories={categories}
        queues={queues}
        createPolicyAction={createTicketEscalationPolicyAction.bind(null, tenantSlug)}
        createPolicyVersionAction={(policyId: string) => createTicketEscalationPolicyVersionAction.bind(null, tenantSlug, policyId)}
        addLevelAction={(versionId: string) => addTicketEscalationLevelAction.bind(null, tenantSlug, versionId)}
        publishPolicyVersionAction={(versionId: string, expectedVersion: number) => publishTicketEscalationPolicyVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
        previewAction={previewTicketEscalationAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
