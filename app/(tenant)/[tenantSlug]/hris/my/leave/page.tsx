import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listEmployeeLeaveBalances, listLeaveRequests, listLeaveTypes, LeaveQueryError } from "../../../../../../server/queries/leave.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyLeavePanel } from "./my-leave-panel.tsx";
import { requestLeaveAction, resubmitLeaveRequestAction, cancelMyLeaveRequestAction } from "./actions.ts";

/**
 * Self-service leave/permit/business-trip (HRT-280, HRS-LVE-001). Own
 * balances (section 16 "employees see own balances") and own requests, with
 * a single request/submit form and self-cancel on a draft/pending/future
 * approved request.
 */
export default async function MyLeavePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let balances: Awaited<ReturnType<typeof listEmployeeLeaveBalances>> = [];
  let requests: Awaited<ReturnType<typeof listLeaveRequests>> = [];
  let leaveTypes: Awaited<ReturnType<typeof listLeaveTypes>> = [];
  try {
    [balances, requests, leaveTypes] = await Promise.all([
      listEmployeeLeaveBalances(supabase, access.tenant.id, access.authUserId),
      listLeaveRequests(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listLeaveTypes(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof LeaveQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your leave workspace. Please try again." />;
  }

  return (
    <MyLeavePanel
      balances={balances}
      requests={requests}
      leaveTypes={leaveTypes.filter((t) => t.status === "published")}
      requestLeaveAction={requestLeaveAction.bind(null, tenantSlug)}
      resubmitLeaveRequestAction={(requestId: string, expectedVersion: number) => resubmitLeaveRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
      cancelMyLeaveRequestAction={(requestId: string, expectedVersion: number) => cancelMyLeaveRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
    />
  );
}
