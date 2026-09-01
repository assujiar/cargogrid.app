import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listCandidates, RecruitmentQueryError } from "../../../../../../server/queries/recruitment.ts";
import type { CandidateStatus } from "../../../../../../server/contracts/recruitment/recruitment.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { CandidatesPanel } from "./candidates-panel.tsx";
import { exportCandidatesAction } from "./actions.ts";

/**
 * Candidate directory entry point (ISS-2026-067 item 5). Previously a candidate was
 * reachable only via an application's own detail page
 * (`/hris/recruitment/applications/[applicationId]`), never independently by candidate
 * id -- this route closes that gap. Server-filtered, cursor-paginated (mirrors
 * `../page.tsx`'s own vacancy list: section 17, never a client-loaded full dataset).
 */
export default async function CandidatesPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ status?: string; q?: string; after?: string }> }) {
  const { tenantSlug } = await params;
  const { status, q, after } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as CandidateStatus) : null) ?? null;

  let denied = false;
  let loadFailed = false;
  let candidates: Awaited<ReturnType<typeof listCandidates>> = [];

  try {
    candidates = await listCandidates(supabase, access.tenant.id, access.authUserId, { statusFilter, search: q ?? null, limit: 50, afterId: after ?? null });
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view the candidate directory." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the candidate directory. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Candidates</h1>
          <p className="text-xs text-neutral-500">Every candidate in this tenant, independent of any one vacancy or application.</p>
        </div>
        <Link href={`/${tenantSlug}/hris/recruitment`} className="text-sm text-primary underline">
          Back to recruitment
        </Link>
      </div>

      <CandidatesPanel tenantSlug={tenantSlug} candidates={candidates} statusFilter={statusFilter} search={q ?? ""} exportAction={exportCandidatesAction.bind(null, tenantSlug, statusFilter)} />
    </div>
  );
}
