import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listAttendanceSessions, listAttendanceExceptions, listAttendanceCorrectionRequests, AttendanceQueryError } from "../../../../../server/queries/attendance.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { AttendanceAdminPanel } from "./attendance-admin-panel.tsx";
import { recordManualEntryAction, decideCorrectionAction, acknowledgeExceptionAction, waiveExceptionAction, approvePayrollInputAction, recalculateExceptionsAction } from "./actions.ts";

/**
 * HR/manager attendance review workspace (HRT-278, section 15's "exception
 * banner, correction request and HR review queue"). HRS:View holders see the
 * full tenant-scoped list; a manager with no HRS:View instead transparently
 * sees self + direct reports only (app.list_attendance_sessions' own design,
 * section 26).
 */
export default async function AttendanceAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let sessions: Awaited<ReturnType<typeof listAttendanceSessions>> = [];
  let exceptions: Awaited<ReturnType<typeof listAttendanceExceptions>> = [];
  let corrections: Awaited<ReturnType<typeof listAttendanceCorrectionRequests>> = [];
  try {
    [sessions, exceptions, corrections] = await Promise.all([
      listAttendanceSessions(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listAttendanceExceptions(supabase, access.tenant.id, access.authUserId, { status: "open", limit: 50 }),
      listAttendanceCorrectionRequests(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof AttendanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the attendance workspace. Please try again." />;
  }

  return (
    <AttendanceAdminPanel
      sessions={sessions}
      exceptions={exceptions}
      corrections={corrections}
      recordManualEntryAction={recordManualEntryAction.bind(null, tenantSlug)}
      decideCorrectionAction={(requestId: string, expectedVersion: number, decision: "approve" | "reject") => decideCorrectionAction.bind(null, tenantSlug, requestId, expectedVersion, decision)}
      acknowledgeExceptionAction={(exceptionId: string, expectedVersion: number) => acknowledgeExceptionAction.bind(null, tenantSlug, exceptionId, expectedVersion)}
      waiveExceptionAction={(exceptionId: string, expectedVersion: number) => waiveExceptionAction.bind(null, tenantSlug, exceptionId, expectedVersion)}
      approvePayrollInputAction={approvePayrollInputAction.bind(null, tenantSlug)}
      recalculateExceptionsAction={recalculateExceptionsAction.bind(null, tenantSlug)}
    />
  );
}
