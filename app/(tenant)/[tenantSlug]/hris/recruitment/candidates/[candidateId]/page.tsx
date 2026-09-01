import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getCandidateProfile, RecruitmentQueryError } from "../../../../../../../server/queries/recruitment.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../../components/ui/permission-state.tsx";
import { CandidateDetailPanel } from "./candidate-detail-panel.tsx";
import { updateCandidateProfileAction, setCandidateStatusAction, searchCandidateDuplicatesAction, flagCandidateDuplicateAction, decideCandidateDuplicateAction } from "./actions.ts";

/**
 * Candidate profile (ISS-2026-067 items 1, 4 and 5) -- a candidate's own detail view,
 * reachable directly by candidate id (not only through one application). Profile
 * editing (`app.update_candidate_profile`), status changes
 * (`app.set_candidate_status`, block/archive), and duplicate search/flag/decide
 * (`app.search_candidate_duplicates`/`app.flag_candidate_duplicate`/
 * `app.decide_candidate_duplicate`) all live here -- every one of these RPCs already
 * existed, tested, with zero UI caller before this page.
 */
export default async function CandidateDetailPage({ params }: { params: Promise<{ tenantSlug: string; candidateId: string }> }) {
  const { tenantSlug, candidateId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let loadFailed = false;
  let notFoundFlag = false;
  let candidate: Awaited<ReturnType<typeof getCandidateProfile>> | null = null;

  try {
    candidate = await getCandidateProfile(supabase, candidateId, access.authUserId);
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("candidate_not_found")) notFoundFlag = true;
    else loadFailed = true;
  }

  if (notFoundFlag) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this candidate." />;
  }
  if (loadFailed || !candidate) {
    return <ErrorState description="Something went wrong loading this candidate. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <Link href={`/${tenantSlug}/hris/recruitment/candidates`} className="w-fit text-sm text-primary underline">
        Back to candidates
      </Link>
      <CandidateDetailPanel
        candidate={candidate}
        updateProfileAction={updateCandidateProfileAction.bind(null, tenantSlug, candidateId, candidate.recordVersion)}
        setStatusAction={(newStatus) => setCandidateStatusAction.bind(null, tenantSlug, candidateId, candidate!.recordVersion, newStatus)}
        searchDuplicatesAction={searchCandidateDuplicatesAction.bind(null, tenantSlug)}
        flagDuplicateAction={(matchCandidateId, similarityBasis, similarityScore) => flagCandidateDuplicateAction.bind(null, tenantSlug, candidateId, matchCandidateId, similarityBasis, similarityScore)}
        decideDuplicateAction={(duplicateId, expectedVersion, decision) => decideCandidateDuplicateAction.bind(null, tenantSlug, duplicateId, expectedVersion, decision)}
      />
    </div>
  );
}
