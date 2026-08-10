import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listLeaveTypes, LeaveQueryError } from "../../../../../../server/queries/leave.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { LeaveTypePanel } from "./leave-type-panel.tsx";
import { createLeaveTypeAction, publishLeaveTypeAction, createAndPublishPolicyVersionAction } from "./actions.ts";

/** Leave type / policy version authoring (HRT-280, section 20 "policy/version"). */
export default async function LeaveTypesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let leaveTypes: Awaited<ReturnType<typeof listLeaveTypes>> = [];
  try {
    leaveTypes = await listLeaveTypes(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof LeaveQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading leave types. Please try again." />;
  }

  return (
    <LeaveTypePanel
      leaveTypes={leaveTypes}
      createLeaveTypeAction={createLeaveTypeAction.bind(null, tenantSlug)}
      publishLeaveTypeAction={(id: string, v: number) => publishLeaveTypeAction.bind(null, tenantSlug, id, v)}
      createAndPublishPolicyVersionAction={(id: string) => createAndPublishPolicyVersionAction.bind(null, tenantSlug, id)}
    />
  );
}
