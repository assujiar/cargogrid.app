import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getLeadById, LeadQueryError } from "../../../../../../server/queries/lead.ts";
import { LeadActionsPanel } from "./lead-actions-panel.tsx";

/**
 * Lead Detail (COM-143, CG-S7-COM-002). `getLeadById` returns `null` for both "does not
 * exist" and "exists but RLS denies it" -- deliberately not distinguished (the same
 * no-tenant/no-record-enumeration posture `resolve-tenant-admin-access.server.ts`
 * already established at the portal-entry layer, extended here to the record layer),
 * rendered as a plain `notFound()` either way.
 */
export default async function LeadDetailPage({ params }: { params: Promise<{ tenantSlug: string; leadId: string }> }) {
  const { tenantSlug, leadId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let lead;
  try {
    lead = await getLeadById(supabase, leadId);
  } catch (error) {
    if (!(error instanceof LeadQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this lead. Please try again.</p>
      </div>
    );
  }

  if (!lead || lead.tenantId !== access.tenant.id) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{lead.contactName}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Company</dt>
        <dd className="text-neutral-900">{lead.companyName ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Email</dt>
        <dd className="text-neutral-900">{lead.email ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Phone</dt>
        <dd className="text-neutral-900">{lead.phone ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Source</dt>
        <dd className="text-neutral-900">{lead.source}</dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{lead.status}</dd>
        <dt className="font-medium text-neutral-600">Score</dt>
        <dd className="text-neutral-900">{lead.score}</dd>
        {lead.status === "disqualified" ? (
          <>
            <dt className="font-medium text-neutral-600">Disqualify reason</dt>
            <dd className="text-neutral-900">{lead.disqualifyReason}</dd>
          </>
        ) : null}
      </dl>

      <LeadActionsPanel tenantSlug={tenantSlug} leadId={lead.id} recordVersion={lead.recordVersion} status={lead.status} />
    </div>
  );
}
