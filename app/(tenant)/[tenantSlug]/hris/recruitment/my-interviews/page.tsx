import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getMyAssignedInterviews, RecruitmentQueryError } from "../../../../../../server/queries/recruitment.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { MyInterviewsPanel } from "./my-interviews-panel.tsx";
import { submitMyInterviewFeedbackAction } from "./actions.ts";

/**
 * Interviewer self-service view (HRT-276, CG-S12-HRT-004, design note 5) -- lets an
 * interviewer with ZERO HRS permissions see only the candidates/applications they are
 * actually assigned to interview, never the full pipeline. Identity-gated, not
 * permission-gated (section 16: "interviewers see only assigned candidate fields").
 */
export default async function MyInterviewsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let interviews: Awaited<ReturnType<typeof getMyAssignedInterviews>> = [];

  try {
    interviews = await getMyAssignedInterviews(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your assigned interviews. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">My assigned interviews</h1>
        <p className="text-xs text-neutral-500">Only interviews you are personally assigned to -- no HR permission required to see this page.</p>
      </div>

      {interviews.length === 0 ? (
        <EmptyState title="No assigned interviews" description="You have no upcoming or past interviews assigned to you, or you have no linked employee profile in this tenant." />
      ) : (
        <MyInterviewsPanel interviews={interviews} submitFeedbackAction={(interviewId) => submitMyInterviewFeedbackAction.bind(null, tenantSlug, interviewId)} />
      )}
    </div>
  );
}
