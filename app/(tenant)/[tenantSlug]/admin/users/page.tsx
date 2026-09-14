import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listPortalUsers, PortalUsersQueryError, type ListPortalUsersResult, type PortalUser } from "../../../../../server/queries/portal-users.ts";
import { listOrgUnits, toOrgHierarchyRpcClient, OrgHierarchyQueryError, type OrgUnitSummary } from "../../../../../server/queries/org-hierarchy.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { resolvePortalUserStatusTone } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { InviteUserPanel } from "./invite-user-panel.tsx";
import { inviteUserAction } from "./actions.ts";

const PAGE_SIZE = 20;

/**
 * Users list plus invitation (audit remediation A2;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A2:
 * "no code path anywhere calls admin.createUser, inviteUserByEmail,
 * generateLink or signUp()"). `inviteUser` (PLT-110/111) already existed as
 * real, tested backend capability with zero callers; this page's own header
 * previously stated that gap verbatim as a deliberate, separately-scoped
 * deferral -- `actions.ts`'s own header explains what closes it.
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
    result = await listPortalUsers(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, page, pageSize: PAGE_SIZE });
  } catch (error) {
    if (!(error instanceof PortalUsersQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  let orgUnits: OrgUnitSummary[] = [];
  try {
    orgUnits = await listOrgUnits(toOrgHierarchyRpcClient(supabase), access.tenant.id);
  } catch (error) {
    if (!(error instanceof OrgHierarchyQueryError)) {
      throw error;
    }
    // Org units are an optional refinement on the invite form -- failing to load them
    // never blocks inviting a user without one.
  }

  if (loadFailed || !result) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
        <ErrorState description="Something went wrong loading users. Please try again." />
        <InviteUserPanel orgUnits={orgUnits} inviteAction={inviteUserAction.bind(null, tenantSlug)} />
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
      <InviteUserPanel orgUnits={orgUnits} inviteAction={inviteUserAction.bind(null, tenantSlug)} />
    </div>
  );
}
