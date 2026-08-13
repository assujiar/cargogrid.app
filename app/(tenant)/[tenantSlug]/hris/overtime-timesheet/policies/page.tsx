import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listOvertimePolicies, OvertimeTimesheetQueryError } from "../../../../../../server/queries/overtime-timesheet.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { OvertimePolicyPanel } from "./overtime-policy-panel.tsx";
import { createOvertimePolicyAction, createAndPublishOvertimePolicyVersionAction } from "./actions.ts";

/**
 * Overtime/timesheet policy authoring (HRT-281, decision 2/6). A real,
 * reachable UI caller for app.create_overtime_policy/create_overtime_
 * policy_version/publish_overtime_policy_version -- without this, only a
 * database-admin-level actor could ever configure the rounding/cap rules
 * every overtime decide/timesheet decide depends on (taxonomy C-20).
 */
export default async function OvertimePoliciesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let policies: Awaited<ReturnType<typeof listOvertimePolicies>> = [];
  try {
    policies = await listOvertimePolicies(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof OvertimeTimesheetQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading overtime policies. Please try again." />;
  }

  return (
    <OvertimePolicyPanel
      policies={policies}
      createOvertimePolicyAction={createOvertimePolicyAction.bind(null, tenantSlug)}
      createAndPublishVersionAction={(policyId: string) => createAndPublishOvertimePolicyVersionAction.bind(null, tenantSlug, policyId)}
    />
  );
}
