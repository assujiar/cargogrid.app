import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getEssHomeSummary, SelfServiceQueryError } from "../../../../../server/queries/self-service.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { EssHomePanel } from "./ess-home-panel.tsx";

/**
 * ESS home (HRT-285, CG-S12-HRT-013). A single composed, bounded landing
 * view over every canonical HR capability's own self-service reads
 * (HRT-274/278/279/280/281/282/283/284) -- section 15's "responsive ESS
 * home". Every widget here is a count or short link, never the full detail
 * a widget summarizes; the detail lives on that capability's OWN
 * already-`VERIFIED`/`COMPLETED` page (`hris/my/profile`, `/attendance`,
 * `/schedule`, `/leave`, `/overtime-timesheet`, `/payroll`,
 * `/kpi-performance`, `/training-talent`), reused by link, never
 * re-implemented here (section 13/24: "never a second... datastore").
 */
export default async function EssHomePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let summary: Awaited<ReturnType<typeof getEssHomeSummary>> | null = null;
  try {
    summary = await getEssHomeSummary(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof SelfServiceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed || !summary) {
    return <ErrorState description="Something went wrong loading your workspace. Please try again." />;
  }

  if (!summary.hasEmployeeProfile) {
    return (
      <EmptyState
        title="No employee profile linked to your account yet"
        description="Ask HR to link your Platform user to your employee record before your self-service workspace becomes available."
      />
    );
  }

  return <EssHomePanel summary={summary} tenantSlug={tenantSlug} />;
}
