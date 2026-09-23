import { notFound } from "next/navigation";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listSupportAccessGrantsForAdmin, toSupportAccessRpcClient, SupportAccessQueryError, type ListSupportAccessGrantsForAdminResult } from "../../../../server/queries/support-access.ts";
import type { SupportAccessGrant } from "../../../../server/contracts/support-access/support-access.ts";
import { DataTable, type DataTableColumn } from "../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { resolveSupportAccessGrantStatusTone } from "../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { RequestSupportAccessPanel } from "./request-support-access-panel.tsx";
import { GrantActionsCell } from "./grant-actions-cell.tsx";
import { requestSupportAccessAction, approveSupportAccessAction, denySupportAccessAction, revokeSupportAccessAction, completeSupportAccessPostReviewAction } from "./actions.ts";

const PAGE_SIZE = 20;

/**
 * The support-access console (CG-AUDIT-2026-09-02 UNTRACKED-D4) -- request,
 * approve, deny, and revoke support access to a live tenant. Every mutation
 * below wraps an already-existing, already-tested PLT-115 RPC
 * (server/mutations/support-access.ts); this page is the missing caller, not
 * new business logic. See actions.ts's own header for why starting/ending a
 * session stays deliberately out of scope.
 *
 * The list itself goes through app.list_support_access_grants_for_admin
 * (SECURITY INVOKER, relies entirely on app.support_access_grants' own RLS
 * SELECT policy for visibility -- Supreme Admin sees every grant, a tenant's
 * own tenant_admin sees only that tenant's grants), the same
 * O1-query-layer-established "no raw `.from()` read in page-level code"
 * pattern app.list_supreme_tenants already set.
 */
export default async function SupportAccessPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();
  const client = toSupportAccessRpcClient(supabase);

  let result: ListSupportAccessGrantsForAdminResult | null = null;
  let loadFailed = false;
  try {
    result = await listSupportAccessGrantsForAdmin(client, { page, pageSize: PAGE_SIZE });
  } catch (error) {
    if (!(error instanceof SupportAccessQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !result) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-neutral-900">Support access</h1>
        <ErrorState description="Something went wrong loading support access grants. Please try again." />
        <RequestSupportAccessPanel requestAction={requestSupportAccessAction} />
      </div>
    );
  }

  const columns: readonly DataTableColumn<SupportAccessGrant>[] = [
    { key: "caseId", header: "Case", render: (grant) => grant.caseId },
    { key: "tenantId", header: "Tenant", render: (grant) => grant.tenantId },
    { key: "granteeAuthUserId", header: "Grantee", render: (grant) => grant.granteeAuthUserId },
    { key: "reason", header: "Reason", render: (grant) => grant.reason },
    {
      key: "status",
      header: "Status",
      render: (grant) => {
        const { tone, label } = resolveSupportAccessGrantStatusTone(grant.status);
        return (
          <div className="flex flex-col gap-1">
            <StatusBadge tone={tone} label={label} />
            {grant.emergency ? <span className="text-xs text-warning">Emergency</span> : null}
          </div>
        );
      },
    },
    { key: "expiresAt", header: "Expires", render: (grant) => new Date(grant.expiresAt).toLocaleString() },
    {
      key: "actions",
      header: "Actions",
      render: (grant) => (
        <GrantActionsCell
          grant={grant}
          approveAction={approveSupportAccessAction.bind(null, grant.id)}
          denyAction={denySupportAccessAction.bind(null, grant.id)}
          revokeAction={revokeSupportAccessAction.bind(null, grant.id)}
          completePostReviewAction={completeSupportAccessPostReviewAction.bind(null, grant.id)}
        />
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Support access</h1>
      <DataTable caption="Support access grants" columns={columns} rows={result.grants} rowKey={(grant) => grant.id} emptyMessage="No support access has ever been requested." />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-neutral-500">
          Page {result.page} — {result.totalCount} total grant{result.totalCount === 1 ? "" : "s"}
        </p>
        <Pagination page={result.page} pageSize={PAGE_SIZE} totalCount={result.totalCount} buildHref={(targetPage) => `/supreme/support-access?page=${targetPage}`} />
      </div>
      <RequestSupportAccessPanel requestAction={requestSupportAccessAction} />
    </div>
  );
}
