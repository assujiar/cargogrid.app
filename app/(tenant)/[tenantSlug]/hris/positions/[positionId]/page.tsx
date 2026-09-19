import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getPosition, listPositionGrades, listPositionIncumbents, PositionQueryError } from "../../../../../../server/queries/position.ts";
import { listOrgUnits, toOrgHierarchyRpcClient, OrgHierarchyQueryError } from "../../../../../../server/queries/org-hierarchy.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { PositionDetailPanel } from "./position-detail-panel.tsx";
import { updatePositionAction, setPositionStatusAction } from "../actions.ts";

/**
 * Position detail (HRT-275, CG-S12-HRT-003) -- capacity/headcount, edit, status
 * lifecycle, and the real list of employees currently holding this position (a
 * direct, RLS-scoped table read against app.employee_position_assignments, mirroring
 * the employee detail page's own established files/change-requests direct-read
 * precedent -- no dedicated "list assignments by position" RPC exists yet, and RLS
 * scopes the ROWS correctly).
 *
 * HRT-293 (Sensitive Personal and Payroll Data Controls) fix: the assignment
 * read below now selects an explicit column list, never `select("*")`.
 * `reason_note`/`decided_reason` are free-text HR narrative (the same class
 * Finding A named for app.employees) this page never actually renders
 * (confirmed -- position-detail-panel.tsx has zero reference to either) and
 * app.employee_position_assignments' own grant to `authenticated` no longer
 * includes either column (supabase/migrations/
 * 20260731200000_harden_hris_raw_table_reason_column_grant_sweep_batch_293.sql)
 * -- a bare `select("*")` against a column-restricted table is rejected
 * outright by Postgres, so this explicit list is required for this read to
 * keep working at all, not merely a defense-in-depth style choice.
 */
export default async function PositionDetailPage({ params }: { params: Promise<{ tenantSlug: string; positionId: string }> }) {
  const { tenantSlug, positionId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let notFoundError = false;
  let loadFailed = false;
  let position: Awaited<ReturnType<typeof getPosition>> | null = null;
  let grades: Awaited<ReturnType<typeof listPositionGrades>> = [];
  let orgUnits: { id: string; name: string; unitType: string }[] = [];
  let incumbents: Awaited<ReturnType<typeof listPositionIncumbents>> = [];

  try {
    position = await getPosition(supabase, positionId, access.authUserId);
    grades = await listPositionGrades(supabase, access.tenant.id, access.authUserId);
    orgUnits = await listOrgUnits(toOrgHierarchyRpcClient(supabase), access.tenant.id, { statusFilter: "active" });
    incumbents = await listPositionIncumbents(supabase, positionId, access.authUserId);
  } catch (error) {
    if (error instanceof OrgHierarchyQueryError) {
      loadFailed = true;
    } else if (!(error instanceof PositionQueryError)) {
      throw error;
    } else if (error.message.startsWith("insufficient_authority")) {
      denied = true;
    } else if (error.message.startsWith("position_not_found")) {
      notFoundError = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundError) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this position." />;
  }
  if (loadFailed || !position) {
    return <ErrorState description="Something went wrong loading this position. Please try again." />;
  }

  return (
    <PositionDetailPanel
      tenantSlug={tenantSlug}
      position={position}
      grades={grades}
      orgUnits={orgUnits}
      incumbents={incumbents}
      updateAction={updatePositionAction.bind(null, tenantSlug, positionId, position.recordVersion)}
      setStatusAction={(newStatus) => setPositionStatusAction.bind(null, tenantSlug, positionId, position!.recordVersion, newStatus)}
    />
  );
}
