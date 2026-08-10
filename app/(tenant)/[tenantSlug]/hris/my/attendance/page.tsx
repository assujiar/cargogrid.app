import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getMyAttendanceStatus, listMyAttendanceCorrectionRequests, AttendanceQueryError } from "../../../../../../server/queries/attendance.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyAttendancePanel } from "./my-attendance-panel.tsx";
import { clockAction, requestMyCorrectionAction } from "./actions.ts";

/**
 * Self-service attendance (HRT-278, section 15 "mobile-first responsive
 * attendance action/status"; HRS-ATT-US-001). Online-first (RPD-004) -- no
 * offline-sync promise, no fake location success (section 15's own "no fake
 * location success or hidden failure").
 */
export default async function MyAttendancePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let statusRows: Awaited<ReturnType<typeof getMyAttendanceStatus>> = [];
  let corrections: Awaited<ReturnType<typeof listMyAttendanceCorrectionRequests>> = [];
  try {
    [statusRows, corrections] = await Promise.all([
      getMyAttendanceStatus(supabase, access.tenant.id, access.authUserId),
      listMyAttendanceCorrectionRequests(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof AttendanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your attendance status. Please try again." />;
  }

  return (
    <MyAttendancePanel
      statusRows={statusRows}
      corrections={corrections}
      clockAction={clockAction.bind(null, tenantSlug)}
      requestCorrectionAction={requestMyCorrectionAction.bind(null, tenantSlug)}
    />
  );
}
