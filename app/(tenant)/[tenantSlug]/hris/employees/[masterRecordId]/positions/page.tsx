import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getEmployeeProfile, EmployeeQueryError } from "../../../../../../../server/queries/employee.ts";
import { getEmployeePositionAssignmentHistory, listPositions, listPositionGrades, PositionQueryError } from "../../../../../../../server/queries/position.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../../components/ui/permission-state.tsx";
import { EmployeePositionPanel } from "./employee-position-panel.tsx";
import { previewAssignmentImpactAction, proposeAssignmentAction, decideAssignmentAction, cancelAssignmentAction } from "./actions.ts";

/**
 * Employee assignment timeline + transfer/promotion/reorg wizard with impact
 * preview (HRT-275, CG-S12-HRT-003, section 15/21/24). The full effective-dated
 * history from app.employee_position_assignments (never inferred from
 * app.employees' own convenience-cache columns).
 */
export default async function EmployeePositionsPage({ params }: { params: Promise<{ tenantSlug: string; masterRecordId: string }> }) {
  const { tenantSlug, masterRecordId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let notFoundError = false;
  let loadFailed = false;
  let profile: Awaited<ReturnType<typeof getEmployeeProfile>> | null = null;
  let history: Awaited<ReturnType<typeof getEmployeePositionAssignmentHistory>> = [];
  let positions: Awaited<ReturnType<typeof listPositions>> = [];
  let grades: Awaited<ReturnType<typeof listPositionGrades>> = [];

  try {
    profile = await getEmployeeProfile(supabase, masterRecordId, access.authUserId);
    [history, positions, grades] = await Promise.all([
      getEmployeePositionAssignmentHistory(supabase, masterRecordId, access.authUserId),
      listPositions(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 200 }),
      listPositionGrades(supabase, access.tenant.id, access.authUserId, { statusFilter: "active" }),
    ]);
  } catch (error) {
    if (error instanceof EmployeeQueryError) {
      if (error.message.startsWith("insufficient_authority")) denied = true;
      else if (error.message.startsWith("employee_not_found")) notFoundError = true;
      else loadFailed = true;
    } else if (error instanceof PositionQueryError) {
      if (error.message.startsWith("insufficient_authority")) denied = true;
      else loadFailed = true;
    } else {
      throw error;
    }
  }

  if (notFoundError) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this employee's position assignments." />;
  }
  if (loadFailed || !profile) {
    return <ErrorState description="Something went wrong loading this employee's assignment timeline. Please try again." />;
  }

  return (
    <EmployeePositionPanel
      tenantSlug={tenantSlug}
      profile={profile}
      history={history}
      positions={positions}
      grades={grades}
      previewAction={previewAssignmentImpactAction.bind(null, tenantSlug, masterRecordId)}
      proposeAction={proposeAssignmentAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      decideAction={(assignmentId: string, expectedVersion: number, decision: "approve" | "reject") => decideAssignmentAction.bind(null, tenantSlug, masterRecordId, assignmentId, expectedVersion, decision)}
      cancelAction={(assignmentId: string, expectedVersion: number) => cancelAssignmentAction.bind(null, tenantSlug, masterRecordId, assignmentId, expectedVersion)}
    />
  );
}
