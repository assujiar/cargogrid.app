import { TruncationNotice } from "../../../../../components/ui/truncation-notice.tsx";
import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationsForTenant, QuotationQueryError } from "../../../../../server/queries/quotation.ts";
import type { Quotation } from "../../../../../server/contracts/quotation/quotation.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { QUOTATION_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

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

  let quotations: readonly Quotation[];
  let truncated = false;
  let loadFailed = false;
  try {
    const page = await listQuotationsForTenant(supabase, access.tenant.id);
    quotations = page.rows;
    truncated = page.truncated;
  } catch (error) {
    if (!(error instanceof QuotationQueryError)) {
      throw error;
    }
    loadFailed = true;
    quotations = [];
  }

  const columns: readonly DataTableColumn<Quotation>[] = [
    {
      key: "quoteNumber",
      header: "Quote number",
      render: (quotation) => (
        <a href={`/${tenantSlug}/commercial/quotations/${quotation.id}`} className="font-medium text-primary underline">
          {quotation.quoteNumber}
        </a>
      ),
    },
    { key: "customer", header: "Customer", render: (quotation) => quotation.customerSnapshot.legalName ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (quotation) => {
        const { tone, label } = QUOTATION_STATUS_TONE_MAP[quotation.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "total",
      header: "Total",
      render: (quotation) => (quotation.sellMasked ? "Restricted" : quotation.totalAmount !== null ? `${quotation.totalAmount} ${quotation.currency}` : "—"),
    },
    { key: "validity", header: "Validity", render: (quotation) => new Date(quotation.validityTo).toLocaleDateString() },
  ];

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Quotations</h1>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading quotations. Please try again." />
      ) : (
        <>
          {truncated ? <TruncationNotice shown={quotations.length} noun="quotations" hint="narrow by status or search for a quotation reference" /> : null}
          <DataTable
            caption="Quotations"
            columns={columns}
            rows={quotations}
            rowKey={(quotation) => quotation.id}
            emptyMessage={<>No quotations yet. Create one from an opportunity&apos;s detail page.</>}
          />
        </>
      )}
    </div>
  );
}
