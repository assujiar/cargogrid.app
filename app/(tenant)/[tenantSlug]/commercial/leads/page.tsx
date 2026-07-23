import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLeads, LeadQueryError, type ListLeadsResult } from "../../../../../server/queries/lead.ts";
import { captureLeadAction } from "./actions.ts";
import { CaptureLeadForm } from "./capture-lead-form.tsx";

/**
 * Lead List (COM-143, CG-S7-COM-002) -- the first business-domain page in this
 * repository. Read-only table plus the one bounded mutating action Prompt 143 §21's
 * main flow requires ("a permitted seller captures a unique lead"); assign/merge remain
 * real, tested mutation-layer capabilities without a dedicated button in this bounded
 * first slice, the same "core management, not an all-actions mega task" scoping
 * PLT-135's own Users list precedent used.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4): Empty and Error are both real, distinct
 * renders below; a sibling `loading.tsx` covers Loading via the Suspense boundary. Data
 * is fetched into a plain result/error value first, JSX construction kept entirely
 * outside the `try`/`catch`, mirroring `admin/users/page.tsx`'s own discipline exactly.
 */
export default async function CommercialLeadsPage({
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

  let result: ListLeadsResult | null = null;
  let loadFailed = false;
  try {
    result = await listLeads(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof LeadQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const boundCaptureLeadAction = captureLeadAction.bind(null, tenantSlug);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Leads</h1>

      <CaptureLeadForm action={boundCaptureLeadAction} />

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading leads. Please try again.</p>
        </div>
      ) : result.leads.length === 0 ? (
        <p className="text-sm text-neutral-600">No leads found for this organization yet.</p>
      ) : (
        <div className="flex flex-col gap-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Contact
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Company
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Source
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Status
                </th>
                <th scope="col" className="py-2 font-medium">
                  Score
                </th>
              </tr>
            </thead>
            <tbody>
              {result.leads.map((lead) => (
                <tr key={lead.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">
                    <a href={`/${tenantSlug}/commercial/leads/${lead.id}`} className="font-medium text-primary underline">
                      {lead.contactName}
                    </a>
                  </td>
                  <td className="py-2 pr-4 text-neutral-600">{lead.companyName ?? "—"}</td>
                  <td className="py-2 pr-4 text-neutral-600">{lead.source}</td>
                  <td className="py-2 pr-4 text-neutral-600">{lead.status}</td>
                  <td className="py-2 text-neutral-600">{lead.score}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="text-xs text-neutral-500">
            Page {result.page} — {result.totalCount} total lead{result.totalCount === 1 ? "" : "s"}
          </p>
        </div>
      )}
    </div>
  );
}
