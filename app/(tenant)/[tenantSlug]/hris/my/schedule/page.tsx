import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getMySchedule, listMyScheduleSwapRequests, ShiftRosterQueryError } from "../../../../../../server/queries/shift-roster.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MySchedulePanel } from "./my-schedule-panel.tsx";
import { requestMySwapAction, cancelMySwapAction } from "./actions.ts";

/**
 * Self-service schedule (HRT-279, section 26 "employee reads own schedule
 * and request swaps"). Mobile-friendly, online-first (RPD-004), mirrors
 * HRT-278's own my/attendance route shape exactly.
 */
export default async function MySchedulePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let mySchedule: Awaited<ReturnType<typeof getMySchedule>> = [];
  let mySwapRequests: Awaited<ReturnType<typeof listMyScheduleSwapRequests>> = [];
  try {
    [mySchedule, mySwapRequests] = await Promise.all([
      getMySchedule(supabase, access.tenant.id, access.authUserId),
      listMyScheduleSwapRequests(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof ShiftRosterQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your schedule. Please try again." />;
  }

  return (
    <MySchedulePanel
      mySchedule={mySchedule}
      mySwapRequests={mySwapRequests}
      requestMySwapAction={requestMySwapAction.bind(null, tenantSlug)}
      cancelMySwapAction={(requestId: string, expectedVersion: number) => cancelMySwapAction.bind(null, tenantSlug, requestId, expectedVersion)}
    />
  );
}
