import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getOrgPositionTree, PositionQueryError } from "../../../../../server/queries/position.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { OrganizationTreePanel } from "./organization-tree-panel.tsx";

/**
 * Organization-linked position tree (HRT-275, CG-S12-HRT-003, section 15). One
 * joined query (app.get_org_position_tree, section 17: no recursive N+1) over the
 * Platform-governed app.org_units tree (company/branch/department/business_unit/
 * team, ADR-0023 Part A) and this domain's own app.positions catalogue.
 * Organization write itself is Platform-governed and unchanged -- this page is
 * read-only.
 */
export default async function OrganizationTreePage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ root?: string }> }) {
  const { tenantSlug } = await params;
  const { root } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let loadFailed = false;
  let rows: Awaited<ReturnType<typeof getOrgPositionTree>> = [];

  try {
    rows = await getOrgPositionTree(supabase, access.tenant.id, access.authUserId, root ?? null);
  } catch (error) {
    if (!(error instanceof PositionQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view the organization tree." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the organization tree. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Organization tree</h1>
          <p className="text-xs text-neutral-500">
            The canonical company/branch/department/business_unit/team hierarchy, with each org unit&apos;s own governed positions and current headcount. Organization write is Platform-governed and unchanged here -- read-only.
          </p>
        </div>
        <a href={`/${tenantSlug}/hris/positions`} className="text-sm text-primary underline">
          Manage positions &amp; grades
        </a>
      </div>

      <OrganizationTreePanel tenantSlug={tenantSlug} rows={rows} />
    </div>
  );
}
