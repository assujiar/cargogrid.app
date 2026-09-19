import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLeaveRequests, listLeaveApprovalInboxForActor, LeaveQueryError } from "../../../../../server/queries/leave.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { LeaveAdminPanel } from "./leave-admin-panel.tsx";
import { decideLeaveRequestAction, adjustLeaveBalanceAction, syncLeaveLifecycleAction, cancelConflictingScheduleAction, exportLeaveRequestsAction } from "./actions.ts";
import { HrisExportForm } from "../../../../../components/domain/hris-export-form.tsx";

/**
 * HR/manager leave/permit/business-trip review workspace (HRT-280,
 * HRS-LVE-001). HRS:View holders see the full tenant-scoped list; a manager
 * with no HRS:View instead transparently sees self + direct reports only
 * (app.list_leave_requests' own design, section 26).
 */
export default async function LeaveAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let requests: Awaited<ReturnType<typeof listLeaveRequests>> = [];
  let inbox: Awaited<ReturnType<typeof listLeaveApprovalInboxForActor>> = [];
  try {
    [requests, inbox] = await Promise.all([
      listLeaveRequests(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listLeaveApprovalInboxForActor(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof LeaveQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the leave workspace. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <h1 className="text-xl font-semibold text-neutral-900">Leave</h1>
        <Link href={`/${tenantSlug}/hris/imports/leave-opening-balance`} className="text-sm text-primary underline">
          Load opening balances from CSV
        </Link>
      </div>
      <LeaveAdminPanel
        requests={requests}
        inbox={inbox}
        decideLeaveRequestAction={(requestStepId: string, decision: "approved" | "rejected") => decideLeaveRequestAction.bind(null, tenantSlug, requestStepId, decision)}
        adjustLeaveBalanceAction={adjustLeaveBalanceAction.bind(null, tenantSlug)}
        syncLeaveLifecycleAction={syncLeaveLifecycleAction.bind(null, tenantSlug)}
        cancelConflictingScheduleAction={cancelConflictingScheduleAction.bind(null, tenantSlug)}
      />
      <HrisExportForm
        label="Export leave requests"
        description="Leave, permit and business-trip requests overlapping a date range, as a CSV. Reason, destination and evidence are deliberately never included, whatever your own permissions. Requires the HR export permission."
        action={exportLeaveRequestsAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
