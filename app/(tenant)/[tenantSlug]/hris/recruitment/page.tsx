import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listJobVacancies, RecruitmentQueryError } from "../../../../../server/queries/recruitment.ts";
import { listPositions } from "../../../../../server/queries/position.ts";
import type { VacancyStatus } from "../../../../../server/contracts/recruitment/recruitment.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { RecruitmentPanel } from "./recruitment-panel.tsx";
import { createJobVacancyDraftAction, exportJobVacanciesAction } from "./actions.ts";

/**
 * Recruitment pipeline entry point (HRT-276, CG-S12-HRT-004) -- the vacancy list and
 * builder. Server-filtered, cursor-paginated (section 17: no client-loaded full
 * dataset). Vacancy detail (the real pipeline table of applications) lives one level
 * deeper at ./[vacancyId].
 */
export default async function RecruitmentPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ status?: string; q?: string; after?: string }> }) {
  const { tenantSlug } = await params;
  const { status, q, after } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as VacancyStatus) : null) ?? null;

  let denied = false;
  let loadFailed = false;
  let vacancies: Awaited<ReturnType<typeof listJobVacancies>> = [];
  let positions: Awaited<ReturnType<typeof listPositions>> = [];

  try {
    [vacancies, positions] = await Promise.all([
      listJobVacancies(supabase, access.tenant.id, access.authUserId, { statusFilter, search: q ?? null, limit: 50, afterId: after ?? null }),
      listPositions(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 200 }),
    ]);
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view the recruitment pipeline." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the recruitment pipeline. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Recruitment</h1>
          <p className="text-xs text-neutral-500">Vacancies, candidates and offers. Publishing a vacancy opens a public, token-based application link.</p>
        </div>
        <div className="flex flex-col items-end gap-1 text-sm">
          <Link href={`/${tenantSlug}/hris/recruitment/my-interviews`} className="text-primary underline">
            My assigned interviews
          </Link>
          <Link href={`/${tenantSlug}/hris/recruitment/candidates`} className="text-primary underline">
            Candidate directory
          </Link>
        </div>
      </div>

      <RecruitmentPanel
        tenantSlug={tenantSlug}
        vacancies={vacancies}
        positions={positions}
        statusFilter={statusFilter}
        search={q ?? ""}
        createVacancyAction={(positionId: string) => createJobVacancyDraftAction.bind(null, tenantSlug, positionId)}
        exportAction={exportJobVacanciesAction.bind(null, tenantSlug, statusFilter)}
      />
    </div>
  );
}
