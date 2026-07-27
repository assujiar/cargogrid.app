import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listPortalUsers, PortalUsersQueryError, type ListPortalUsersResult, type PortalUser } from "../../../../../server/queries/portal-users.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { resolvePortalUserStatusTone } from "../../../../../components/domain/status-tone-map.ts";

const PAGE_SIZE = 20;

/**
 * Users list (PLT-135, CG-S6-PLT-032) -- the one bounded "core management" child slice
 * this checkpoint ships (Prompt 135 §11/§12: "exact bounded workflow adapters," never
 * an "all-admin-pages mega task"). Read-only: invite/suspend/role-assignment mutations
 * already exist as real backend capability (PLT-110/111) but their own UI is deferred
 * to a later, separately-scoped slice -- this page proves the full route -> guard ->
 * RLS-scoped query -> render pattern end to end without expanding scope beyond it.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4): Empty and Error are both real, distinct
 * renders below, not a bare table that silently shows nothing. A dedicated `loading.tsx`
 * sibling covers the Loading state (Suspense boundary) for this route segment. Data is
 * fetched into a plain result/error value first, with JSX construction kept entirely
 * outside the `try`/`catch` (`react-hooks/error-boundaries`) -- JSX itself never throws
 * synchronously, only the `await` above it can.
 */
export default async function TenantAdminUsersPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListPortalUsersResult | null = null;
  let loadFailed = false;
  try {
    result = await listPortalUsers(supabase, { tenantId: access.tenant.id, page, pageSize: PAGE_SIZE });
  } catch (error) {
    if (!(error instanceof PortalUsersQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !result) {
    return (
      <div className="flex flex-col gap-2" role="alert">
        <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
        <p className="text-sm text-danger">Something went wrong loading users. Please try again.</p>
      </div>
    );
  }

  const columns: readonly DataTableColumn<PortalUser>[] = [
    { key: "name", header: "Name", render: (user) => user.displayName },
    {
      key: "email",
      header: "Email",
      render: (user) => (
        <>
          {user.email ?? "—"}
          {user.emailMasked ? <span className="ml-1 text-xs text-neutral-400">(masked)</span> : null}
        </>
      ),
    },
    {
      key: "status",
      header: "Status",
      render: (user) => {
        const { tone, label } = resolvePortalUserStatusTone(user.status);
        return <StatusBadge tone={tone} label={label} />;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
      <DataTable
        caption="Users"
        columns={columns}
        rows={result.users}
        rowKey={(user) => user.id}
        emptyMessage="No users found for this organization yet."
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-neutral-500">
          Page {result.page} — {result.totalCount} total user{result.totalCount === 1 ? "" : "s"}
        </p>
        <Pagination
          page={result.page}
          pageSize={result.pageSize}
          totalCount={result.totalCount}
          buildHref={(targetPage) => `/${tenantSlug}/admin/users?page=${targetPage}`}
        />
      </div>
    </div>
  );
}
