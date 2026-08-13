import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  listMyOvertimeRequests,
  listMyTimesheetEntries,
  listTimesheetPeriods,
  listTimesheetPeriodSummaries,
  OvertimeTimesheetQueryError,
} from "../../../../../../server/queries/overtime-timesheet.ts";
import { getMyEmployeeProfile } from "../../../../../../server/queries/employee.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyOvertimeTimesheetPanel } from "./my-overtime-timesheet-panel.tsx";
import {
  createOvertimeRequestAction,
  submitOvertimeRequestAction,
  cancelOvertimeRequestAction,
  createTimesheetEntryAction,
  submitTimesheetEntryAction,
  cancelTimesheetEntryAction,
  submitTimesheetPeriodSummaryAction,
} from "./actions.ts";

/**
 * Self-service overtime and timesheet workspace (HRT-281, CG-S12-HRT-009).
 * Every write here is self-only, structurally -- no employee-id parameter
 * exists on any of the create/submit/cancel RPCs this page calls (decision
 * 5/14, mirrors app.record_attendance_clock_event's own established anti-
 * spoofing shape). The employee's own master_record_id (needed only for
 * app.submit_timesheet_period_summary's explicit p_employee_id parameter --
 * the SAME entrypoint HR-on-behalf also uses) is resolved server-side via
 * the already-established, already-VERIFIED app.get_my_employee_profile
 * (HRT-274) -- never a second self-identity resolution mechanism.
 */
export default async function MyOvertimeTimesheetPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let overtimeRequests: Awaited<ReturnType<typeof listMyOvertimeRequests>> = [];
  let timesheetEntries: Awaited<ReturnType<typeof listMyTimesheetEntries>> = [];
  let periods: Awaited<ReturnType<typeof listTimesheetPeriods>> = [];
  let summaries: Awaited<ReturnType<typeof listTimesheetPeriodSummaries>> = [];
  let myEmployeeId: string | null = null;
  try {
    const [overtimeRes, entriesRes, periodsRes, summariesRes, profileRes] = await Promise.all([
      listMyOvertimeRequests(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listMyTimesheetEntries(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listTimesheetPeriods(supabase, access.tenant.id, access.authUserId),
      listTimesheetPeriodSummaries(supabase, access.tenant.id, access.authUserId, {}),
      getMyEmployeeProfile(supabase, access.tenant.id, access.authUserId),
    ]);
    overtimeRequests = overtimeRes;
    timesheetEntries = entriesRes;
    periods = periodsRes;
    summaries = summariesRes;
    myEmployeeId = profileRes?.masterRecordId ?? null;
  } catch (error) {
    if (!(error instanceof OvertimeTimesheetQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your overtime and timesheet workspace. Please try again." />;
  }

  return (
    <MyOvertimeTimesheetPanel
      overtimeRequests={overtimeRequests}
      timesheetEntries={timesheetEntries}
      periods={periods}
      summaries={summaries}
      myEmployeeId={myEmployeeId}
      createOvertimeRequestAction={createOvertimeRequestAction.bind(null, tenantSlug)}
      submitOvertimeRequestAction={(requestId: string, expectedVersion: number) => submitOvertimeRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
      cancelOvertimeRequestAction={(requestId: string, expectedVersion: number) => cancelOvertimeRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
      createTimesheetEntryAction={createTimesheetEntryAction.bind(null, tenantSlug)}
      submitTimesheetEntryAction={(entryId: string, expectedVersion: number) => submitTimesheetEntryAction.bind(null, tenantSlug, entryId, expectedVersion)}
      cancelTimesheetEntryAction={(entryId: string, expectedVersion: number) => cancelTimesheetEntryAction.bind(null, tenantSlug, entryId, expectedVersion)}
      submitTimesheetPeriodSummaryAction={submitTimesheetPeriodSummaryAction.bind(null, tenantSlug)}
    />
  );
}
