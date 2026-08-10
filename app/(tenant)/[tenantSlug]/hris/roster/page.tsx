import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listScheduleAssignments,
  listShiftTemplates,
  listScheduleSwapRequests,
  listRosterHolidays,
  getScheduleCoveragePreview,
  ShiftRosterQueryError,
} from "../../../../../server/queries/shift-roster.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { RosterAdminPanel } from "./roster-admin-panel.tsx";
import { assignEmployeeScheduleAction, publishScheduleAssignmentsAction, decideSwapAction, setRosterHolidayAction, setCoverageRequirementAction } from "./actions.ts";

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * HR/scheduler roster workspace (HRT-279, section 15's "roster calendar/
 * table, coverage/conflict preview, bulk assignment... views"). HRS:View
 * holders see the full tenant-scoped list; anyone else transparently sees
 * self + direct reports only (app.list_schedule_assignments' own design,
 * section 26) -- table-shaped here, matching HRT-278's own disclosed
 * table-not-calendar-grid precedent.
 */
export default async function RosterAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const today = new Date();
  const in14Days = new Date(today.getTime() + 13 * 24 * 60 * 60 * 1000);

  let loadFailed = false;
  let assignments: Awaited<ReturnType<typeof listScheduleAssignments>> = [];
  let shiftTemplates: Awaited<ReturnType<typeof listShiftTemplates>> = [];
  let pendingSwaps: Awaited<ReturnType<typeof listScheduleSwapRequests>> = [];
  let holidays: Awaited<ReturnType<typeof listRosterHolidays>> = [];
  let coveragePreview: Awaited<ReturnType<typeof getScheduleCoveragePreview>> = [];
  try {
    [assignments, shiftTemplates, pendingSwaps, holidays, coveragePreview] = await Promise.all([
      listScheduleAssignments(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listShiftTemplates(supabase, access.tenant.id, access.authUserId),
      listScheduleSwapRequests(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listRosterHolidays(supabase, access.tenant.id, access.authUserId),
      getScheduleCoveragePreview(supabase, access.tenant.id, access.authUserId, null, isoDate(today), isoDate(in14Days)),
    ]);
  } catch (error) {
    if (!(error instanceof ShiftRosterQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the roster workspace. Please try again." />;
  }

  return (
    <RosterAdminPanel
      assignments={assignments}
      shiftTemplates={shiftTemplates}
      pendingSwaps={pendingSwaps}
      holidays={holidays}
      coveragePreview={coveragePreview}
      assignEmployeeScheduleAction={assignEmployeeScheduleAction.bind(null, tenantSlug)}
      publishScheduleAssignmentsAction={publishScheduleAssignmentsAction.bind(null, tenantSlug)}
      decideSwapAction={(requestId: string, expectedVersion: number, decision: "approve" | "reject") => decideSwapAction.bind(null, tenantSlug, requestId, expectedVersion, decision)}
      setRosterHolidayAction={setRosterHolidayAction.bind(null, tenantSlug)}
      setCoverageRequirementAction={setCoverageRequirementAction.bind(null, tenantSlug)}
    />
  );
}
