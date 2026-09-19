import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  listTenantRoles,
  listRoleVersions,
  listRoleVersionPermissions,
  listRoleAssignmentsForRole,
  listActiveTenantUsersForRoleAssignment,
  listPermissionsForModule,
  toRolePermissionLookupClient,
  RolePermissionLookupError,
} from "../../../../../../server/queries/role-permission.ts";
import type { Role, RoleVersion, RoleAssignment, Permission } from "../../../../../../server/contracts/role-permission/role-permission.ts";
import type { RoleAssignmentCandidate } from "../../../../../../server/queries/role-permission.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { RoleDetailPanel } from "./role-detail-panel.tsx";
import { createRoleVersionAction, setRoleVersionPermissionsAction, publishRoleVersionAction, assignRoleAction, revokeRoleAssignmentAction } from "../actions.ts";

const RESOURCE_MODULE_CODES = ["COM", "OPS", "FIN", "PRC", "HRS", "TKT", "CPT", "LYL", "REP"] as const;

/**
 * Role detail: versions, permissions, and assignments (audit remediation A2).
 * See `actions.ts`'s own header for the service-role/mutation rationale, and
 * `20260914010000_add_role_permission_management_read_rpcs.sql`'s own header
 * for why `listRoleVersions`/`listRoleVersionPermissions`/
 * `listRoleAssignmentsForRole`/`listActiveTenantUsersForRoleAssignment` exist
 * at all -- without them this page could create data it could never show
 * again after a reload.
 */
export default async function RoleDetailPage({ params }: { params: Promise<{ tenantSlug: string; roleId: string }> }) {
  const { tenantSlug, roleId } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const lookupClient = toRolePermissionLookupClient(supabase);

  let role: Role | null = null;
  let versions: RoleVersion[] = [];
  let assignments: RoleAssignment[] = [];
  let candidates: RoleAssignmentCandidate[] = [];
  let allPermissions: Permission[] = [];
  let loadFailed = false;

  try {
    const roles = await listTenantRoles(lookupClient, access.tenant.id, access.authUserId);
    role = roles.find((candidateRole) => candidateRole.id === roleId) ?? null;
    if (role) {
      versions = await listRoleVersions(lookupClient, roleId);
      assignments = await listRoleAssignmentsForRole(lookupClient, roleId);
      candidates = await listActiveTenantUsersForRoleAssignment(lookupClient, access.tenant.id, access.authUserId);
      const perModule = await Promise.all(RESOURCE_MODULE_CODES.map((moduleCode) => listPermissionsForModule(lookupClient, moduleCode, access.authUserId)));
      allPermissions = perModule.flat();
    }
  } catch (error) {
    if (!(error instanceof RolePermissionLookupError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading this role. Please try again." />;
  }
  if (!role) {
    notFound();
  }

  const draftVersion = versions.find((version) => version.status === "draft") ?? null;

  let draftPermissionIds: string[] = [];
  if (draftVersion) {
    try {
      const boundPermissions = await listRoleVersionPermissions(lookupClient, draftVersion.id, access.authUserId);
      draftPermissionIds = boundPermissions.map((permission) => permission.id);
    } catch (error) {
      if (!(error instanceof RolePermissionLookupError)) {
        throw error;
      }
    }
  }

  const candidateNamesByAuthUserId = new Map(candidates.map((candidate) => [candidate.authUserId, candidate.displayName]));

  return (
    <RoleDetailPanel
      role={role}
      versions={versions}
      draftVersion={draftVersion}
      draftPermissionIds={draftPermissionIds}
      allPermissions={allPermissions}
      assignments={assignments}
      candidateNamesByAuthUserId={candidateNamesByAuthUserId}
      candidates={candidates}
      createVersionAction={createRoleVersionAction.bind(null, tenantSlug, roleId)}
      setPermissionsAction={draftVersion ? setRoleVersionPermissionsAction.bind(null, tenantSlug, roleId, draftVersion.id) : null}
      publishAction={draftVersion ? publishRoleVersionAction.bind(null, tenantSlug, roleId, draftVersion.id) : null}
      assignAction={assignRoleAction.bind(null, tenantSlug, roleId)}
      revokeActionFor={(assignmentId: string) => revokeRoleAssignmentAction.bind(null, tenantSlug, roleId, assignmentId)}
    />
  );
}
