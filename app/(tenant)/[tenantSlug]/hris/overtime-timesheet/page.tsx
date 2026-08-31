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
import { listEmployees, EmployeeQueryError } from "../../../../../server/queries/employee.ts";
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
  createOvertimeRequestForEmployeeAction,
  createTimesheetEntryForEmployeeAction,
  updateTimesheetEntryDraftAction,
  reconcileOvertimeRequestActualAction,
  generatePayrollTimeInputAction,
  exportTimesheetEntriesAction,
} from "./actions.ts";
import { HrisExportForm } from "../../../../../components/domain/hris-export-form.tsx";

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
  // ISS-2026-076: the three extra reads the HR-on-behalf / correction / reconcile surfaces need.
  // Each is server-filtered and capped rather than filtered in the browser -- the same discipline
  // the two lists above already follow.
  let draftEntries: Awaited<ReturnType<typeof listTimesheetEntries>> = [];
  let approvedRequests: Awaited<ReturnType<typeof listOvertimeRequests>> = [];
  let employees: Awaited<ReturnType<typeof listEmployees>> = [];
  try {
    [overtimeRequests, timesheetEntries, draftEntries, approvedRequests, periods, summaries, employees] = await Promise.all([
      listOvertimeRequests(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listTimesheetEntries(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listTimesheetEntries(supabase, access.tenant.id, access.authUserId, { status: "draft", limit: 50 }),
      listOvertimeRequests(supabase, access.tenant.id, access.authUserId, { status: "approved", limit: 50 }),
      listTimesheetPeriods(supabase, access.tenant.id, access.authUserId),
      listTimesheetPeriodSummaries(supabase, access.tenant.id, access.authUserId, { status: "submitted" }),
      listEmployees(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 200 }),
    ]);
  } catch (error) {
    if (!(error instanceof OvertimeTimesheetQueryError) && !(error instanceof EmployeeQueryError)) throw error;
    loadFailed = true;
  }

  // Reconciliation is only meaningful once a request is approved AND has not been matched yet --
  // offering the button on an already-matched row would invite a no-op nobody could interpret.
  // There is no status filter for this on the RPC, so it is narrowed here, from a capped read.
  const reconcilableRequests = approvedRequests.filter((r) => r.reconciliationStatus === "not_reconciled");

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the overtime and timesheet workspace. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <OvertimeTimesheetAdminPanel
        overtimeRequests={overtimeRequests}
        timesheetEntries={timesheetEntries}
        draftEntries={draftEntries}
        reconcilableRequests={reconcilableRequests}
        employees={employees}
        periods={periods}
        summaries={summaries}
        decideOvertimeRequestAction={(requestId: string, expectedVersion: number, decision: "approve" | "reject") =>
          decideOvertimeRequestAction.bind(null, tenantSlug, requestId, expectedVersion, decision)
        }
        decideTimesheetEntryAction={(entryId: string, expectedVersion: number, decision: "approve" | "reject") =>
          decideTimesheetEntryAction.bind(null, tenantSlug, entryId, expectedVersion, decision)
        }
        createOvertimeRequestForEmployeeAction={createOvertimeRequestForEmployeeAction.bind(null, tenantSlug)}
        createTimesheetEntryForEmployeeAction={createTimesheetEntryForEmployeeAction.bind(null, tenantSlug)}
        updateTimesheetEntryDraftAction={(entryId: string, expectedVersion: number) => updateTimesheetEntryDraftAction.bind(null, tenantSlug, entryId, expectedVersion)}
        reconcileOvertimeRequestActualAction={(requestId: string) => reconcileOvertimeRequestActualAction.bind(null, tenantSlug, requestId)}
        generatePayrollTimeInputAction={(periodId: string) => generatePayrollTimeInputAction.bind(null, tenantSlug, periodId)}
        createTimesheetPeriodAction={createTimesheetPeriodAction.bind(null, tenantSlug)}
        lockTimesheetPeriodAction={(periodId: string, expectedVersion: number) => lockTimesheetPeriodAction.bind(null, tenantSlug, periodId, expectedVersion)}
        reopenTimesheetPeriodAction={(periodId: string, expectedVersion: number) => reopenTimesheetPeriodAction.bind(null, tenantSlug, periodId, expectedVersion)}
        approveTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => approveTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
        rejectTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => rejectTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
        reopenTimesheetPeriodSummaryAction={(summaryId: string, expectedVersion: number) => reopenTimesheetPeriodSummaryAction.bind(null, tenantSlug, summaryId, expectedVersion)}
        generatePayrollTimeInputsForPeriodAction={(periodId: string) => generatePayrollTimeInputsForPeriodAction.bind(null, tenantSlug, periodId)}
      />
      <HrisExportForm
        label="Export timesheet entries"
        description="Timesheet entries in a date range, as a CSV: employee, work date, job and shipment, entry/eligible/approved minutes and status. Requires the HR export permission."
        action={exportTimesheetEntriesAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
