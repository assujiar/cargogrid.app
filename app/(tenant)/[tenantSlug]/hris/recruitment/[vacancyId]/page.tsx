import { notFound } from "next/navigation";
import { getJobVacancy, listApplicationsForVacancy, RecruitmentQueryError } from "../../../../../../server/queries/recruitment.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { VacancyDetailPanel } from "./vacancy-detail-panel.tsx";
import {
  updateJobVacancyDraftAction,
  publishJobVacancyAction,
  holdJobVacancyAction,
  reopenJobVacancyAction,
  closeJobVacancyAction,
  cancelJobVacancyDraftAction,
  createCandidateAndApplyAction,
  exportApplicationsForVacancyAction,
} from "../actions.ts";

/**
 * Vacancy detail (HRT-276, CG-S12-HRT-004) -- the real recruitment pipeline table
 * (section 15 "recruitment pipeline/table"): every application against this vacancy,
 * by stage, linking through to each candidate's own application detail page.
 */
export default async function VacancyDetailPage({ params }: { params: Promise<{ tenantSlug: string; vacancyId: string }> }) {
  const { tenantSlug, vacancyId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let loadFailed = false;
  let notFoundFlag = false;
  let detail: Awaited<ReturnType<typeof getJobVacancy>> | null = null;
  let applications: Awaited<ReturnType<typeof listApplicationsForVacancy>> = [];

  try {
    [detail, applications] = await Promise.all([getJobVacancy(supabase, vacancyId, access.authUserId), listApplicationsForVacancy(supabase, vacancyId, access.authUserId)]);
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("vacancy_not_found")) notFoundFlag = true;
    else loadFailed = true;
  }

  if (notFoundFlag) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this vacancy." />;
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this vacancy. Please try again." />;
  }

  return (
    <VacancyDetailPanel
      tenantSlug={tenantSlug}
      detail={detail}
      applications={applications}
      updateAction={updateJobVacancyDraftAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      publishAction={publishJobVacancyAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      holdAction={holdJobVacancyAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      reopenAction={reopenJobVacancyAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      closeAction={closeJobVacancyAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      cancelAction={cancelJobVacancyDraftAction.bind(null, tenantSlug, vacancyId, detail.vacancy.recordVersion)}
      addCandidateAction={createCandidateAndApplyAction.bind(null, tenantSlug, vacancyId)}
      exportApplicationsAction={exportApplicationsForVacancyAction.bind(null, tenantSlug, vacancyId)}
    />
  );
}
