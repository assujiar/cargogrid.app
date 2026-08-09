import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listPositionGrades, listPositions, PositionQueryError } from "../../../../../server/queries/position.ts";
import type { PositionGradeStatus, PositionStatus } from "../../../../../server/contracts/position/position.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { PositionCataloguePanel } from "./position-catalogue-panel.tsx";
import { createPositionGradeAction, setPositionGradeStatusAction, createPositionAction, setPositionStatusAction } from "./actions.ts";

/**
 * Position/grade catalogue (HRT-275, CG-S12-HRT-003) -- HR-governed, tenant-scoped
 * structural data referencing the canonical company/branch/department/business_unit/
 * team org tree (never a second hierarchy). Server-filtered, cursor-paginated
 * (section 17: no client-loaded full dataset).
 */
export default async function PositionCataloguePage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ status?: string; q?: string; after?: string }> }) {
  const { tenantSlug } = await params;
  const { status, q, after } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as PositionStatus) : null) ?? null;

  let denied = false;
  let loadFailed = false;
  let positions: Awaited<ReturnType<typeof listPositions>> = [];
  let grades: Awaited<ReturnType<typeof listPositionGrades>> = [];
  let orgUnits: { id: string; name: string; unitType: string }[] = [];

  try {
    [positions, grades] = await Promise.all([
      listPositions(supabase, access.tenant.id, access.authUserId, { statusFilter, search: q ?? null, limit: 50, afterCode: after ?? null }),
      listPositionGrades(supabase, access.tenant.id, access.authUserId),
    ]);
    const { data: orgUnitRows, error: orgUnitError } = await supabase.from("org_units").select("id, name, unit_type").eq("tenant_id", access.tenant.id).eq("status", "active");
    if (orgUnitError) throw new PositionQueryError(orgUnitError.message);
    orgUnits = (orgUnitRows ?? []).map((row) => ({ id: String(row.id), name: String(row.name), unitType: String(row.unit_type) }));
  } catch (error) {
    if (!(error instanceof PositionQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view the position/grade catalogue." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the position/grade catalogue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Positions &amp; grades</h1>
          <p className="text-xs text-neutral-500">HR-governed structural catalogue, referencing the canonical company/branch/department/business_unit/team organization tree. Organization write itself stays Platform-governed and unchanged.</p>
        </div>
        <a href={`/${tenantSlug}/hris/organization`} className="text-sm text-primary underline">
          View organization tree
        </a>
      </div>

      <PositionCataloguePanel
        tenantSlug={tenantSlug}
        positions={positions}
        grades={grades}
        orgUnits={orgUnits}
        statusFilter={statusFilter}
        search={q ?? ""}
        createGradeAction={createPositionGradeAction.bind(null, tenantSlug)}
        setGradeStatusAction={(id: string, expectedVersion: number, newStatus: PositionGradeStatus) => setPositionGradeStatusAction.bind(null, tenantSlug, id, expectedVersion, newStatus)}
        createPositionAction={createPositionAction.bind(null, tenantSlug)}
        setPositionStatusAction={(id: string, expectedVersion: number, newStatus: PositionStatus) => setPositionStatusAction.bind(null, tenantSlug, id, expectedVersion, newStatus)}
      />
    </div>
  );
}
