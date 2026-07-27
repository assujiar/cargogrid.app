import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listProspects, ProspectQueryError, type ListProspectsResult } from "../../../../../server/queries/prospect.ts";
import type { Prospect } from "../../../../../server/contracts/prospect/prospect.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { PROSPECT_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";

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

  const columns: readonly DataTableColumn<Prospect>[] = [
    {
      key: "legalName",
      header: "Legal name",
      render: (prospect) => (
        <a href={`/${tenantSlug}/commercial/prospects/${prospect.id}`} className="font-medium text-primary underline">
          {prospect.legalName}
        </a>
      ),
    },
    { key: "contact", header: "Contact", render: (prospect) => prospect.contactName },
    {
      key: "status",
      header: "Status",
      render: (prospect) => {
        const { tone, label } = PROSPECT_STATUS_TONE_MAP[prospect.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Prospects</h1>

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading prospects. Please try again.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Prospects"
            columns={columns}
            rows={result.prospects}
            rowKey={(prospect) => prospect.id}
            emptyMessage={
              <>
                No prospects yet. Convert a qualified <a href={`/${tenantSlug}/commercial/leads`} className="font-medium text-primary underline">lead</a> to get started.
              </>
            }
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total prospect{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/commercial/prospects?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
