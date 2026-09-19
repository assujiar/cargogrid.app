import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listTenantRoles, toRolePermissionLookupClient, RolePermissionLookupError } from "../../../../../server/queries/role-permission.ts";
import type { Role } from "../../../../../server/contracts/role-permission/role-permission.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { Link } from "../../../../../components/ui/link.tsx";
import { CreateRolePanel } from "./create-role-panel.tsx";
import { createRoleAction } from "./actions.ts";

/**
 * Role list plus role creation (audit remediation A2;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A2:
 * "createRole/assignRole/revokeRoleAssignment have no caller"). `createRole`
 * (PLT-111) already existed as real, tested backend capability with zero
 * callers -- this page and `[roleId]/page.tsx` close that gap. Reuses
 * `listTenantRoles` (O1 remediation cluster 2), already `authenticated`-
 * callable, so this page's own read uses the RLS-scoped client -- only the
 * mutations (`actions.ts`) need the service-role client.
 */
export default async function TenantAdminRolesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let roles: Role[] = [];
  let loadFailed = false;
  try {
    roles = await listTenantRoles(toRolePermissionLookupClient(supabase), access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof RolePermissionLookupError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-neutral-900">Roles</h1>
        <ErrorState description="Something went wrong loading roles. Please try again." />
        <CreateRolePanel createAction={createRoleAction.bind(null, tenantSlug)} />
      </div>
    );
  }

  const columns: readonly DataTableColumn<Role>[] = [
    {
      key: "name",
      header: "Name",
      render: (role) => <Link href={`/${tenantSlug}/admin/roles/${role.id}`}>{role.name}</Link>,
    },
    { key: "description", header: "Description", render: (role) => role.description ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (role) => <StatusBadge tone={role.status === "active" ? "success" : "neutral"} label={role.status} />,
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Roles</h1>
      <DataTable caption="Roles" columns={columns} rows={roles} rowKey={(role) => role.id} emptyMessage="No roles have been created for this organization yet." />
      <CreateRolePanel createAction={createRoleAction.bind(null, tenantSlug)} />
    </div>
  );
}
