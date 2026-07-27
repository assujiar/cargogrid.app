import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listOpportunities, OpportunityQueryError, type ListOpportunitiesResult } from "../../../../../server/queries/opportunity.ts";
import type { Opportunity } from "../../../../../server/contracts/opportunity/opportunity.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { OPPORTUNITY_STAGE_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { createOpportunityAction } from "./actions.ts";
import { CreateOpportunityForm } from "./create-opportunity-form.tsx";

/**
 * Opportunity list (COM-147, CG-S7-COM-006). A server-paginated table, not a drag/drop
 * Kanban board -- a full board UI is deferred (disclosed, COM-147 build log) in favor of
 * the server-paginated table/create-form pattern every prior Commercial list page already
 * uses; stage moves are still fully real, tested mutations, exercised from the Opportunity
 * Detail page. Reads through app.opportunities_directory, so value/probability are
 * field-masked exactly as they would be anywhere else this data is shown.
 */
export default async function CommercialOpportunitiesPage({
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

  let result: ListOpportunitiesResult | null = null;
  let loadFailed = false;
  try {
    result = await listOpportunities(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof OpportunityQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const boundCreateAction = createOpportunityAction.bind(null, tenantSlug);

  const columns: readonly DataTableColumn<Opportunity>[] = [
    {
      key: "name",
      header: "Name",
      render: (opportunity) => (
        <a href={`/${tenantSlug}/commercial/opportunities/${opportunity.id}`} className="font-medium text-primary underline">
          {opportunity.name}
        </a>
      ),
    },
    {
      key: "stage",
      header: "Stage",
      render: (opportunity) => {
        const { tone, label } = OPPORTUNITY_STAGE_TONE_MAP[opportunity.stage];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "probability", header: "Probability", render: (opportunity) => opportunity.probability ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Opportunities</h1>

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading opportunities. Please try again.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Opportunities"
            columns={columns}
            rows={result.opportunities}
            rowKey={(opportunity) => opportunity.id}
            emptyMessage="No opportunities yet. Create one below from a prospect."
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total opportunit{result.totalCount === 1 ? "y" : "ies"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/commercial/opportunities?page=${targetPage}`}
            />
          </div>
        </div>
      )}

      <CreateOpportunityForm action={boundCreateAction} />
    </div>
  );
}
