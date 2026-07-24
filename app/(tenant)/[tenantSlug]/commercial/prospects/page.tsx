import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listProspects, ProspectQueryError, type ListProspectsResult } from "../../../../../server/queries/prospect.ts";

/**
 * Prospect queue (COM-144, CG-S7-COM-003). Read-only -- prospects are created only via
 * the Lead Detail page's "Convert to prospect" action (COM-143's own actions.ts), the
 * same "one bounded mutating entry point, not an all-actions mega task" scoping the Lead
 * List's capture form already used.
 */
export default async function CommercialProspectsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListProspectsResult | null = null;
  let loadFailed = false;
  try {
    result = await listProspects(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof ProspectQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Prospects</h1>

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading prospects. Please try again.</p>
        </div>
      ) : result.prospects.length === 0 ? (
        <p className="text-sm text-neutral-600">
          No prospects yet. Convert a qualified <a href={`/${tenantSlug}/commercial/leads`} className="font-medium text-primary underline">lead</a> to get started.
        </p>
      ) : (
        <div className="flex flex-col gap-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Legal name
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Contact
                </th>
                <th scope="col" className="py-2 font-medium">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {result.prospects.map((prospect) => (
                <tr key={prospect.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">
                    <a href={`/${tenantSlug}/commercial/prospects/${prospect.id}`} className="font-medium text-primary underline">
                      {prospect.legalName}
                    </a>
                  </td>
                  <td className="py-2 pr-4 text-neutral-600">{prospect.contactName}</td>
                  <td className="py-2 text-neutral-600">{prospect.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="text-xs text-neutral-500">
            Page {result.page} — {result.totalCount} total prospect{result.totalCount === 1 ? "" : "s"}
          </p>
        </div>
      )}
    </div>
  );
}
