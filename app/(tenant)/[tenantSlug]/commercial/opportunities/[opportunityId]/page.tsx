import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getOpportunityById, listOpportunityStageHistory, getOpportunityCostingReadiness, OpportunityQueryError } from "../../../../../../server/queries/opportunity.ts";
import { listActivitiesForRecord } from "../../../../../../server/queries/contact.ts";
import { OpportunityActionsPanel } from "./opportunity-actions-panel.tsx";
import { ActivityTimeline } from "../../_shared/activity-timeline.tsx";

/**
 * Opportunity Detail (COM-147, CG-S7-COM-006). `getOpportunityById` returns `null` for
 * both "does not exist" and "exists but RLS denies it" -- deliberately not distinguished,
 * the same posture every prior Commercial detail page uses. Value/probability display
 * respects `opportunity.valueMasked` (set by app.opportunities_directory) -- the value
 * edit form is hidden entirely, not just its current value, when the caller lacks
 * COM:View selling price (attempting to "blind-set" a value they cannot see would still
 * be denied server-side, but hiding the control is the clearer UX).
 */
export default async function OpportunityDetailPage({ params }: { params: Promise<{ tenantSlug: string; opportunityId: string }> }) {
  const { tenantSlug, opportunityId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let opportunity;
  try {
    opportunity = await getOpportunityById(supabase, opportunityId);
  } catch (error) {
    if (!(error instanceof OpportunityQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this opportunity. Please try again.</p>
      </div>
    );
  }

  if (!opportunity || opportunity.tenantId !== access.tenant.id) {
    notFound();
  }

  const [stageHistory, readiness, activities] = await Promise.all([
    listOpportunityStageHistory(supabase, opportunity.id),
    getOpportunityCostingReadiness(supabase, opportunity.id, access.authUserId),
    listActivitiesForRecord(supabase, "opportunity", opportunity.id),
  ]);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{opportunity.name}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Stage</dt>
        <dd className="text-neutral-900">{opportunity.stage.replace(/_/g, " ")}</dd>
        <dt className="font-medium text-neutral-600">Probability</dt>
        <dd className="text-neutral-900">{opportunity.valueMasked ? "Restricted" : (opportunity.probability ?? "—")}</dd>
        <dt className="font-medium text-neutral-600">Value</dt>
        <dd className="text-neutral-900">
          {opportunity.valueMasked ? "Restricted" : opportunity.valueAmount ? `${opportunity.valueAmount} ${opportunity.valueCurrency ?? ""}` : "—"}
        </dd>
        <dt className="font-medium text-neutral-600">Next action</dt>
        <dd className="text-neutral-900">{opportunity.nextAction ?? "—"}</dd>
        {opportunity.stage === "won" || opportunity.stage === "lost" ? (
          <>
            <dt className="font-medium text-neutral-600">Close reason</dt>
            <dd className="text-neutral-900">{opportunity.closeReason}</dd>
          </>
        ) : null}
        <dt className="font-medium text-neutral-600">Source prospect</dt>
        <dd className="text-neutral-900">
          <a href={`/${tenantSlug}/commercial/prospects/${opportunity.prospectId}`} className="font-medium text-primary underline">
            View prospect
          </a>
        </dd>
        {opportunity.clonedFromId ? (
          <>
            <dt className="font-medium text-neutral-600">Cloned from</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/opportunities/${opportunity.clonedFromId}`} className="font-medium text-primary underline">
                View source opportunity
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Costing readiness</h2>
        {readiness.ready ? (
          <p className="mt-2 text-sm text-neutral-600">Ready — all mandatory requirement fields are present.</p>
        ) : (
          <p className="mt-2 text-sm text-neutral-600">Not ready — missing: {readiness.missing.join(", ")}.</p>
        )}
      </div>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Stage history</h2>
        {stageHistory.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No stage history yet.</p>
        ) : (
          <ul className="mt-2 flex flex-col gap-1 text-sm">
            {stageHistory.map((entry) => (
              <li key={entry.id} className="text-neutral-600">
                {entry.fromStage ? `${entry.fromStage.replace(/_/g, " ")} → ` : ""}
                {entry.toStage.replace(/_/g, " ")} (probability {entry.probability})
                {entry.reason ? ` — ${entry.reason}` : ""}
              </li>
            ))}
          </ul>
        )}
      </div>

      <OpportunityActionsPanel
        tenantSlug={tenantSlug}
        opportunityId={opportunity.id}
        recordVersion={opportunity.recordVersion}
        stage={opportunity.stage}
        requirements={opportunity.requirements}
        showValueForm={!opportunity.valueMasked}
      />

      <ActivityTimeline tenantSlug={tenantSlug} relatedType="opportunity" relatedId={opportunity.id} activities={activities} />
    </div>
  );
}
