import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listEmployees, EmployeeQueryError } from "../../../../../../server/queries/employee.ts";
import { listPositions, listPositionGrades, PositionQueryError } from "../../../../../../server/queries/position.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { BulkReassignPanel } from "./bulk-reassign-panel.tsx";
import { proposeBulkReassignmentAction } from "./actions.ts";

/**
 * Bulk/multi-employee reorganization wizard (ISS-2026-066 item 1). Every existing
 * assignment RPC (propose/decide/cancel_employee_position_assignment) operates one
 * employee at a time -- this page is the "move an entire department's employees to a
 * new org unit/position in one transaction" tool the entry names, calling the new
 * app.propose_bulk_employee_position_assignment RPC
 * (supabase/migrations/20260902210000_create_bulk_employee_position_reassignment.sql).
 * Every row it creates lands as a status=pending_approval proposal in the SAME queue a
 * single-employee proposal would -- reviewed through the existing
 * /hris/employees/[masterRecordId]/positions wizard, never auto-approved here.
 */
export default async function BulkReassignPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ department?: string }>;
}) {
  const { tenantSlug } = await params;
  const { department } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const departmentOrgUnitId = department && department.length > 0 ? department : null;

  let denied = false;
  let loadFailed = false;
  let departments: { id: string; name: string }[] = [];
  let positions: Awaited<ReturnType<typeof listPositions>> = [];
  let grades: Awaited<ReturnType<typeof listPositionGrades>> = [];
  let employees: Awaited<ReturnType<typeof listEmployees>> = [];

  try {
    [positions, grades] = await Promise.all([
      listPositions(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 200 }),
      listPositionGrades(supabase, access.tenant.id, access.authUserId, { statusFilter: "active" }),
    ]);
    const { data: orgUnitRows, error: orgUnitError } = await supabase.from("org_units").select("id, name").eq("tenant_id", access.tenant.id).eq("unit_type", "department").eq("status", "active").order("name");
    if (orgUnitError) throw new PositionQueryError(orgUnitError.message);
    departments = (orgUnitRows ?? []).map((row) => ({ id: String(row.id), name: String(row.name) }));

    if (departmentOrgUnitId) {
      employees = await listEmployees(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", departmentOrgUnitId, limit: 200 });
    }
  } catch (error) {
    if (error instanceof EmployeeQueryError || error instanceof PositionQueryError) {
      if (error.message.startsWith("insufficient_authority")) denied = true;
      else loadFailed = true;
    } else {
      throw error;
    }
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to bulk-reassign employee positions." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the bulk reassignment wizard. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Bulk reorganization</h1>
          <p className="text-xs text-neutral-500">Move every selected employee in a department to a new position in one submission. Each row becomes a real, separately reviewable pending-approval proposal -- nothing here is immediately effective.</p>
        </div>
        <a href={`/${tenantSlug}/hris/positions`} className="text-sm text-primary underline">
          Back to position catalogue
        </a>
      </div>

      <BulkReassignPanel
        tenantSlug={tenantSlug}
        departments={departments}
        selectedDepartmentId={departmentOrgUnitId}
        employees={employees}
        positions={positions}
        grades={grades}
        submitAction={proposeBulkReassignmentAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
