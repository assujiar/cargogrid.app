import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listOrgUnitsFull, toOrgHierarchyRpcClient, OrgHierarchyQueryError } from "../../../../../server/queries/org-hierarchy.ts";
import type { OrgUnit } from "../../../../../server/contracts/org-hierarchy/org-hierarchy.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { OrgHierarchyPanel } from "./org-hierarchy-panel.tsx";
import { createOrgUnitAction, renameOrgUnitAction, moveOrgUnitAction, setOrgUnitStatusAction } from "./actions.ts";

/**
 * Org-unit master-data entry (audit remediation A2;
 * `docs/blueprint/01_CargoGrid_Project_Product_Charter.md` §41 MVP scope:
 * tenant provisioning, user invitation, role/permission configuration, and
 * master-data entry). `createOrgUnit`/`moveOrgUnit`/`renameOrgUnit`/
 * `setOrgUnitStatus` (PLT-109) already existed as real, tested backend
 * capability with zero callers -- this page closes that gap. Reuses
 * `listOrgUnitsFull` (a full-row projection of the already-`authenticated`-
 * callable `list_org_units` RPC, O1 remediation cluster 7), so this page's
 * own read uses the RLS-scoped client -- only the mutations (`actions.ts`)
 * need the service-role client.
 */
export default async function TenantAdminOrganizationPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let orgUnits: OrgUnit[] = [];
  let loadFailed = false;
  try {
    orgUnits = await listOrgUnitsFull(toOrgHierarchyRpcClient(supabase), access.tenant.id);
  } catch (error) {
    if (!(error instanceof OrgHierarchyQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-neutral-900">Organization structure</h1>
        <ErrorState description="Something went wrong loading your organization's structure. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Organization structure</h1>
      <OrgHierarchyPanel
        orgUnits={orgUnits}
        createAction={createOrgUnitAction.bind(null, tenantSlug)}
        renameActionFor={(orgUnitId, expectedVersion) => renameOrgUnitAction.bind(null, tenantSlug, orgUnitId, expectedVersion)}
        moveActionFor={(orgUnitId, expectedVersion) => moveOrgUnitAction.bind(null, tenantSlug, orgUnitId, expectedVersion)}
        setStatusActionFor={(orgUnitId, expectedVersion, nextStatus) => setOrgUnitStatusAction.bind(null, tenantSlug, orgUnitId, expectedVersion, nextStatus)}
      />
    </div>
  );
}
