import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getPipelineSummary, listSalesPlans, PipelineQueryError } from "../../../../../server/queries/pipeline.ts";
import type { PipelineStageSummaryEntry, SalesPlan } from "../../../../../server/contracts/pipeline/pipeline.ts";
import { createSalesPlanAction } from "./actions.ts";
import { CreateSalesPlanForm } from "./create-sales-plan-form.tsx";

/**
 * Pipeline overview (COM-146, CG-S7-COM-005): a governed, RLS-backed stage summary
 * (app.get_pipeline_summary -- SECURITY INVOKER, so this view can never show a stage
 * count for a row the viewer could not otherwise open) plus the tenant's sales plans.
 * No org-unit drill-down filter UI in this bounded slice -- the summary always reflects
 * the caller's own full accessible scope (p_org_unit_id = null); a per-org-unit
 * drill-down control is a disclosed follow-up, not an oversight (see COM-146's build log).
 */
export default async function CommercialPipelinePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let summary: PipelineStageSummaryEntry[] = [];
  let plans: SalesPlan[] = [];
  let loadFailed = false;
  try {
    [summary, plans] = await Promise.all([
      getPipelineSummary(supabase, { tenantId: access.tenant.id }),
      listSalesPlans(supabase, access.tenant.id),
    ]);
  } catch (error) {
    if (!(error instanceof PipelineQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const boundCreateAction = createSalesPlanAction.bind(null, tenantSlug);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Pipeline</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading the pipeline. Please try again.</p>
        </div>
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Stage summary</h2>
            {summary.length === 0 ? (
              <p className="text-sm text-neutral-600">No accessible leads or prospects yet.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
                {summary.map((entry) => (
                  <li key={entry.stage} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{entry.stage.replace(/_/g, " ")}</p>
                    <p className="text-lg font-semibold text-neutral-900">{entry.recordCount}</p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Sales plans</h2>
            {plans.length === 0 ? (
              <p className="text-sm text-neutral-600">No sales plans yet. Create one below.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Name
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Period
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {plans.map((plan) => (
                    <tr key={plan.id} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">
                        <a href={`/${tenantSlug}/commercial/pipeline/${plan.id}`} className="font-medium text-primary underline">
                          {plan.name}
                        </a>
                      </td>
                      <td className="py-2 pr-4 text-neutral-600">
                        {plan.periodStart} — {plan.periodEnd}
                      </td>
                      <td className="py-2 text-neutral-600">{plan.status}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>

          <CreateSalesPlanForm action={boundCreateAction} />
        </>
      )}
    </div>
  );
}
