import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationsForTenant, QuotationQueryError } from "../../../../../server/queries/quotation.ts";
import type { Quotation } from "../../../../../server/contracts/quotation/quotation.ts";

/**
 * Quotation list (COM-151, CG-S7-COM-010). Tenant-wide, field-masked via
 * app.quotations_directory (COM:View selling price gates every monetary total) -- a
 * quotation is created from its source opportunity (`opportunities/[opportunityId]`'s own
 * "Create quotation" form), not from this list page, mirroring how costing requests are
 * created from the opportunity they belong to rather than a standalone creation form here.
 */
export default async function QuotationsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let quotations: Quotation[];
  let loadFailed = false;
  try {
    quotations = await listQuotationsForTenant(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof QuotationQueryError)) {
      throw error;
    }
    loadFailed = true;
    quotations = [];
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Quotations</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading quotations. Please try again.</p>
        </div>
      ) : quotations.length === 0 ? (
        <p className="text-sm text-neutral-600">No quotations yet. Create one from an opportunity&apos;s detail page.</p>
      ) : (
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-neutral-600">
              <th scope="col" className="py-2 pr-4 font-medium">
                Quote number
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Customer
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Status
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Total
              </th>
              <th scope="col" className="py-2 font-medium">
                Validity
              </th>
            </tr>
          </thead>
          <tbody>
            {quotations.map((quotation) => (
              <tr key={quotation.id} className="border-b border-neutral-100">
                <td className="py-2 pr-4 text-neutral-900">
                  <a href={`/${tenantSlug}/commercial/quotations/${quotation.id}`} className="font-medium text-primary underline">
                    {quotation.quoteNumber}
                  </a>
                </td>
                <td className="py-2 pr-4 text-neutral-600">{quotation.customerSnapshot.legalName ?? "—"}</td>
                <td className="py-2 pr-4 text-neutral-600">{quotation.status}</td>
                <td className="py-2 pr-4 text-neutral-600">
                  {quotation.sellMasked ? "Restricted" : quotation.totalAmount !== null ? `${quotation.totalAmount} ${quotation.currency}` : "—"}
                </td>
                <td className="py-2 text-neutral-600">{new Date(quotation.validityTo).toLocaleDateString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
