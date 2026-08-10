import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listAttendancePolicies, AttendanceQueryError } from "../../../../../../server/queries/attendance.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PolicyListPanel } from "./policy-list-panel.tsx";
import { createPolicyAction, createAndPublishPolicyVersionAction } from "./actions.ts";

/**
 * Attendance policy authoring (HRT-278, decision 3). A real, reachable UI
 * caller for app.create_attendance_policy/create_attendance_policy_version/
 * publish_attendance_policy_version -- without this, only a database-admin-
 * level actor could ever configure the policy every clock-in/out depends on
 * (taxonomy C-20).
 */
export default async function AttendancePoliciesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let policies: Awaited<ReturnType<typeof listAttendancePolicies>> = [];
  try {
    policies = await listAttendancePolicies(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof AttendanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading attendance policies. Please try again." />;
  }

  return (
    <PolicyListPanel
      policies={policies}
      createPolicyAction={createPolicyAction.bind(null, tenantSlug)}
      createAndPublishVersionAction={(policyId: string) => createAndPublishPolicyVersionAction.bind(null, tenantSlug, policyId)}
    />
  );
}
