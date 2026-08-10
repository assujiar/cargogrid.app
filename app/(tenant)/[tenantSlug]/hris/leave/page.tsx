import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLeaveRequests, listLeaveApprovalInboxForActor, LeaveQueryError } from "../../../../../server/queries/leave.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { LeaveAdminPanel } from "./leave-admin-panel.tsx";
import { decideLeaveRequestAction, adjustLeaveBalanceAction, syncLeaveLifecycleAction, cancelConflictingScheduleAction } from "./actions.ts";

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
    <LeaveAdminPanel
      requests={requests}
      inbox={inbox}
      decideLeaveRequestAction={(requestStepId: string, decision: "approved" | "rejected") => decideLeaveRequestAction.bind(null, tenantSlug, requestStepId, decision)}
      adjustLeaveBalanceAction={adjustLeaveBalanceAction.bind(null, tenantSlug)}
      syncLeaveLifecycleAction={syncLeaveLifecycleAction.bind(null, tenantSlug)}
      cancelConflictingScheduleAction={cancelConflictingScheduleAction.bind(null, tenantSlug)}
    />
  );
}
