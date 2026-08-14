import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getMssTeamWorkspace, SelfServiceQueryError, TEAM_QUEUE_BOUND } from "../../../../../server/queries/self-service.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { TeamWorkspacePanel } from "./team-workspace-panel.tsx";
import { decideLeaveQueueItemAction, decideOvertimeQueueItemAction, decideTimesheetQueueItemAction, decideTrainingQueueItemAction } from "./actions.ts";

/**
 * MSS team workspace (HRT-285, CG-S12-HRT-013). Own/effective-team scope is
 * derived entirely server-side by `getMssTeamWorkspace`
 * (`server/queries/self-service.ts`) from `app.list_my_team_employees` --
 * the SAME effective-manager-scope resolution HRT-274 already established
 * (section 24/26: "reuse the established manager-scope resolution, never a
 * new one"). Manager status alone never grants payroll, candidate, medical,
 * talent or unrestricted personal data here -- this page never reads any
 * `app.payroll_*` table and never reads talent-review/pool/succession data
 * (both `HRS:Override`-only, decision documented in
 * `server/queries/self-service.ts`'s own header comment).
 */
export default async function MssTeamWorkspacePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let workspace: Awaited<ReturnType<typeof getMssTeamWorkspace>> | null = null;
  try {
    workspace = await getMssTeamWorkspace(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof SelfServiceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed || !workspace) {
    return <ErrorState description="Something went wrong loading your team workspace. Please try again." />;
  }

  if (!workspace.isManager) {
    return (
      <EmptyState
        title="No direct reports"
        description="This workspace shows approvals and team status for your own effective team. You currently have no employees reporting to you."
      />
    );
  }

  return (
    <TeamWorkspacePanel
      workspace={workspace}
      teamQueueBound={TEAM_QUEUE_BOUND}
      decideLeaveAction={(requestStepId: string) => decideLeaveQueueItemAction.bind(null, tenantSlug, requestStepId)}
      decideOvertimeAction={(requestId: string, expectedVersion: number) => decideOvertimeQueueItemAction.bind(null, tenantSlug, requestId, expectedVersion)}
      decideTimesheetAction={(entryId: string, expectedVersion: number) => decideTimesheetQueueItemAction.bind(null, tenantSlug, entryId, expectedVersion)}
      decideTrainingAction={(enrollmentId: string, expectedVersion: number) => decideTrainingQueueItemAction.bind(null, tenantSlug, enrollmentId, expectedVersion)}
    />
  );
}
