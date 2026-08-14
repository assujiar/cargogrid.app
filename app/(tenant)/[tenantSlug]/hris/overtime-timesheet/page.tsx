import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listOvertimeRequests,
  listTimesheetEntries,
  listTimesheetPeriods,
  listTimesheetPeriodSummaries,
  OvertimeTimesheetQueryError,
} from "../../../../../server/queries/overtime-timesheet.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { OvertimeTimesheetAdminPanel } from "./overtime-timesheet-admin-panel.tsx";
import {
  decideOvertimeRequestAction,
  decideTimesheetEntryAction,
  createTimesheetPeriodAction,
  lockTimesheetPeriodAction,
  reopenTimesheetPeriodAction,
  approveTimesheetPeriodSummaryAction,
  rejectTimesheetPeriodSummaryAction,
  reopenTimesheetPeriodSummaryAction,
  generatePayrollTimeInputsForPeriodAction,
} from "./actions.ts";

/**
 * HR/manager overtime and timesheet review workspace (HRT-281,
 * CG-S12-HRT-009). HRS:View holders see the full tenant-scoped list; a
 * manager with no HRS:View instead transparently sees self + direct
 * reports only (app.list_overtime_requests/app.list_timesheet_entries' own
 * design, reusing the roster's own manager-scope resolution).
 */
export default async function OvertimeTimesheetAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let overtimeRequests: Awaited<ReturnType<typeof listOvertimeRequests>> = [];
  let timesheetEntries: Awaited<ReturnType<typeof listTimesheetEntries>> = [];
  let periods: Awaited<ReturnType<typeof listTimesheetPeriods>> = [];
  let summaries: Awaited<ReturnType<typeof listTimesheetPeriodSummaries>> = [];
  try {
    [overtimeRequests, timesheetEntries, periods, summaries] = await Promise.all([
      listOvertimeRequests(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listTimesheetEntries(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listTimesheetPeriods(supabase, access.tenant.id, access.authUserId),
      listTimesheetPeriodSummaries(supabase, access.tenant.id, access.authUserId, { status: "submitted" }),
    ]);
  } catch (error) {
    if (!(error instanceof OvertimeTimesheetQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the overtime and timesheet workspace. Please try again." />;
  }

  return (
    <OvertimeTimesheetAdminPanel
      overtimeRequests={overtimeRequests}
      timesheetEntries={timesheetEntries}
      periods={periods}
      summaries={summaries}
      decideOvertimeRequestAction={(requestId: string, expectedVersion: number, decision: "approve" | "reject") =>
        decideOvertimeRequestAction.bind(null, tenantSlug, requestId, expectedVersion, decision)
      }
      decideTimesheetEntryAction={(entryId: string, expectedVersion: number, decision: "approve" | "reject") =>
        decideTimesheetEntryAction.bind(null, tenantSlug, entryId, expectedVersion, decision)
      }
      createTimesheetPeriodAction={createTimesheetPeriodAction.bind(null, tenantSlug)}
      lockTimesheetPeriodAction={(periodId: string, expectedVersion: number) => lockTimesheetPeriodAction.bind(null, tenantSlug, periodId, expectedVersion)}
      reopenTimesheetPeriodAction={(periodId: string, expectedVersion: number) => reopenTimesheetPeriodAction.bind(null, tenantSlug, periodId, expectedVersion)}
      approveTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => approveTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
      rejectTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => rejectTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
      reopenTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => reopenTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
      generatePayrollTimeInputsForPeriodAction={(periodId: string) => generatePayrollTimeInputsForPeriodAction.bind(null, tenantSlug, periodId)}
    />
  );
}
