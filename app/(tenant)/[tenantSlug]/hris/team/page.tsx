import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getMssTeamWorkspace, SelfServiceQueryError, TEAM_QUEUE_BOUND, TEAM_QUEUE_SIZES, TEAM_PAGE_SIZE } from "../../../../../server/queries/self-service.ts";
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
export default async function MssTeamWorkspacePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ teamCursors?: string; queue?: string }>;
}) {
  const { tenantSlug } = await params;
  const { teamCursors: rawCursors, queue: rawQueue } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  // ISS-2026-084. The roster's page history lives in the URL as a comma-joined stack of
  // the employee numbers each page started after -- so Back is a real Back (drop the
  // last entry) rather than a browser-history guess, the view is shareable, and no
  // client-side pagination state has to be kept in sync with a Server Action. The RPC's
  // cursor is forward-only, which is exactly what a stack compensates for.
  const teamCursors = (rawCursors ?? "")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c.length > 0 && c.length <= 64)
    .slice(0, 50);
  const teamAfterEmployeeNumber = teamCursors[teamCursors.length - 1] ?? null;

  // An unparseable or out-of-range value falls back to the default rather than erroring:
  // the query layer clamps it again server-side, so a hand-edited URL can only ever ask
  // for a page size the composition is willing to pay for.
  const requestedQueue = Number(rawQueue);
  const queueLimit = TEAM_QUEUE_SIZES.includes(requestedQueue as (typeof TEAM_QUEUE_SIZES)[number]) ? requestedQueue : TEAM_QUEUE_BOUND;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let workspace: Awaited<ReturnType<typeof getMssTeamWorkspace>> | null = null;
  try {
    workspace = await getMssTeamWorkspace(supabase, access.tenant.id, access.authUserId, { teamAfterEmployeeNumber, queueLimit });
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
      teamPageSize={TEAM_PAGE_SIZE}
      queueSizes={TEAM_QUEUE_SIZES}
      basePath={`/${tenantSlug}/hris/team`}
      teamCursors={teamCursors}
      decideLeaveAction={(requestStepId: string) => decideLeaveQueueItemAction.bind(null, tenantSlug, requestStepId)}
      decideOvertimeAction={(requestId: string, expectedVersion: number) => decideOvertimeQueueItemAction.bind(null, tenantSlug, requestId, expectedVersion)}
      decideTimesheetAction={(entryId: string, expectedVersion: number) => decideTimesheetQueueItemAction.bind(null, tenantSlug, entryId, expectedVersion)}
      decideTrainingAction={(enrollmentId: string, expectedVersion: number) => decideTrainingQueueItemAction.bind(null, tenantSlug, enrollmentId, expectedVersion)}
    />
  );
}
