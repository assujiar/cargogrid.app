import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getSalesPlanById,
  listSalesTargetsForPlan,
  listForecastSnapshotsForTarget,
  getSalesTargetActual,
  PipelineQueryError,
} from "../../../../../../server/queries/pipeline.ts";
import { PlanActionsPanel } from "./plan-actions-panel.tsx";
import { CaptureSnapshotForm } from "./capture-snapshot-form.tsx";

/**
 * Sales Plan Detail (COM-146, CG-S7-COM-005). `getSalesPlanById` returns `null` for both
 * "does not exist" and "exists but RLS denies it" -- deliberately not distinguished, the
 * same no-record-enumeration posture COM-143/144/145's own detail pages already use.
 */
export default async function SalesPlanDetailPage({ params }: { params: Promise<{ tenantSlug: string; planId: string }> }) {
  const { tenantSlug, planId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let plan;
  try {
    plan = await getSalesPlanById(supabase, planId);
  } catch (error) {
    if (!(error instanceof PipelineQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this sales plan. Please try again.</p>
      </div>
    );
  }

  if (!plan || plan.tenantId !== access.tenant.id) {
    notFound();
  }

  const targets = await listSalesTargetsForPlan(supabase, plan.id);
  const targetDetails = await Promise.all(
    targets.map(async (target) => {
      const [actual, snapshots] = await Promise.all([
        getSalesTargetActual(supabase, target.id, access.authUserId),
        listForecastSnapshotsForTarget(supabase, target.id),
      ]);
      return { target, actual, latestSnapshot: snapshots[0] ?? null };
    }),
  );

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{plan.name}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Period</dt>
        <dd className="text-neutral-900">
          {plan.periodStart} — {plan.periodEnd}
        </dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{plan.status}</dd>
        <dt className="font-medium text-neutral-600">Organization unit</dt>
        <dd className="text-neutral-900">{plan.orgUnitId ?? "Tenant-wide"}</dd>
        {plan.supersedesPlanId ? (
          <>
            <dt className="font-medium text-neutral-600">Supersedes</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/pipeline/${plan.supersedesPlanId}`} className="font-medium text-primary underline">
                View prior plan
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Targets</h2>
        {targetDetails.length === 0 ? (
          <p className="text-sm text-neutral-600">No targets yet. Add one below.</p>
        ) : (
          <div className="flex flex-col gap-4">
            {targetDetails.map(({ target, actual, latestSnapshot }) => (
              <div key={target.id} className="rounded-md border border-neutral-200 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-sm font-medium text-neutral-900">{target.metricType.replace(/_/g, " ")}</p>
                  <p className="text-sm text-neutral-600">
                    Target: {target.targetValue} — Live actual: {actual}
                    {latestSnapshot ? (
                      <>
                        {" "}
                        — Last snapshot: {latestSnapshot.overrideValue ?? latestSnapshot.computedValue}
                        {latestSnapshot.overrideValue !== null ? " (overridden)" : ""}
                      </>
                    ) : null}
                  </p>
                </div>
                <div className="mt-2">
                  <CaptureSnapshotForm tenantSlug={tenantSlug} planId={plan.id} targetId={target.id} />
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <PlanActionsPanel tenantSlug={tenantSlug} planId={plan.id} recordVersion={plan.recordVersion} status={plan.status} />
    </div>
  );
}
