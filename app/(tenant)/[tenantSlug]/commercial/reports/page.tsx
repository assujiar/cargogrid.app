import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listActiveReportTypes, listReportRuns, ReportQueryError } from "../../../../../server/queries/report.ts";
import type { ReportType, ReportRun } from "../../../../../server/contracts/report/report.ts";

/**
 * Commercial Reports catalogue (COM-159, CG-S7-COM-018): the code-shipped report
 * catalogue plus this tenant's own run history. Every report reuses COM-158's own
 * governed dashboard query -- see app/.../reports/run-report.ts.
 */
export default async function CommercialReportsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let reportTypes: ReportType[] = [];
  let runs: ReportRun[] = [];
  let loadFailed = false;
  try {
    [reportTypes, runs] = await Promise.all([listActiveReportTypes(supabase), listReportRuns(supabase, access.tenant.id, 20)]);
  } catch (error) {
    if (!(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Reports</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading the report catalogue. Please try again.</p>
        </div>
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Catalogue</h2>
            <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {reportTypes.map((type) => (
                <li key={type.code} className="rounded-md border border-neutral-200 p-3">
                  <a href={`/${tenantSlug}/commercial/reports/${type.code}`} className="font-medium text-primary underline">
                    {type.name}
                  </a>
                  <p className="mt-1 text-xs text-neutral-500">{type.description}</p>
                </li>
              ))}
            </ul>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Run history</h2>
            {runs.length === 0 ? (
              <p className="text-sm text-neutral-600">No report has been run yet.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Report
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Type
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Status
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Rows
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      Requested
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {runs.map((run) => (
                    <tr key={run.id} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">{run.reportTypeCode}</td>
                      <td className="py-2 pr-4 text-neutral-600">{run.runType}</td>
                      <td className="py-2 pr-4 text-neutral-600">{run.status}</td>
                      <td className="py-2 pr-4 text-neutral-600">{run.rowCount ?? "—"}</td>
                      <td className="py-2 text-neutral-600">{run.requestedAt}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>
        </>
      )}
    </div>
  );
}
