import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationApprovalInboxForActor, QuotationApprovalQueryError } from "../../../../../server/queries/quotation-approval.ts";
import { getQuotationById } from "../../../../../server/queries/quotation.ts";

/**
 * Quotation approval inbox (COM-153, CG-S7-COM-012, Prompt 153 §66/§15: "accessible
 * approval inbox"). Lists every currently-active step across the tenant this actor is
 * eligible to decide right now (direct role/user match or an active delegation) --
 * app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic, so
 * listQuotationApprovalInboxForActor (server/queries/quotation-approval.ts) resolves each
 * step to its bound quotation. Deciding happens on the quotation's own detail page (the
 * approval panel there already carries the full record -- cost/margin fields projected by
 * permission, version history, comparison diff -- rather than duplicating that context
 * here); this page is a routing list, not a second decision surface.
 */
export default async function ApprovalsInboxPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let items: Awaited<ReturnType<typeof listQuotationApprovalInboxForActor>>;
  let loadFailed = false;
  try {
    items = await listQuotationApprovalInboxForActor(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof QuotationApprovalQueryError)) {
      throw error;
    }
    loadFailed = true;
    items = [];
  }

  const quotations = await Promise.all(items.map((item) => getQuotationById(supabase, item.quotationId)));

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Approvals</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading your approval inbox. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Waiting on your decision</h2>
          {items.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-600">Nothing is waiting on you right now.</p>
          ) : (
            <table className="mt-2 w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-600">
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Quotation
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Step
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    Action
                  </th>
                </tr>
              </thead>
              <tbody>
                {items.map((item, index) => {
                  const quotation = quotations[index];
                  return (
                    <tr key={item.stepId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">{quotation?.quoteNumber ?? item.quotationId}</td>
                      <td className="py-2 pr-4 text-neutral-600">Step {item.stepOrder}</td>
                      <td className="py-2 text-neutral-600">
                        <a href={`/${tenantSlug}/commercial/quotations/${item.quotationId}`} className="text-sm font-medium text-primary underline">
                          Review
                        </a>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
