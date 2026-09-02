import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listOnboardingCases, listOnboardingChecklistTemplates, OnboardingQueryError } from "../../../../../server/queries/onboarding.ts";
import type { CaseStatus, CaseType } from "../../../../../server/contracts/onboarding/onboarding.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { OnboardingCaseListPanel } from "./onboarding-case-list-panel.tsx";
import { startOnboardingCaseAction, previewOnboardingCaseStartAction, exportOnboardingCasesAction } from "./actions.ts";

/**
 * Onboarding/offboarding case workspace (HRT-277, CG-S12-HRT-005) -- role-based
 * case list (section 15), server-filtered/searched (section 17). Starting a case
 * is the ADR-0023 Part B conversion itself (app.start_onboarding_case).
 */
export default async function OnboardingCasesPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ caseType?: string; status?: string; q?: string; after?: string }>;
}) {
  const { tenantSlug } = await params;
  const { caseType, status, q, after } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const caseTypeFilter = (caseType && caseType.length > 0 ? (caseType as CaseType) : null) ?? null;
  const statusFilter = (status && status.length > 0 ? (status as CaseStatus) : null) ?? null;

  let denied = false;
  let loadFailed = false;
  let cases: Awaited<ReturnType<typeof listOnboardingCases>> = [];
  let templates: Awaited<ReturnType<typeof listOnboardingChecklistTemplates>> = [];

  try {
    [cases, templates] = await Promise.all([
      listOnboardingCases(supabase, access.tenant.id, access.authUserId, { caseTypeFilter, statusFilter, search: q ?? null, limit: 50, afterId: after ?? null }),
      listOnboardingChecklistTemplates(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof OnboardingQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view onboarding/offboarding cases." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading onboarding/offboarding cases. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Onboarding &amp; offboarding</h1>
          <p className="text-xs text-neutral-500">Governed workforce entry/exit cases -- checklist, access provisioning/revocation, and finalize approval, per case.</p>
        </div>
        <div className="flex gap-3 text-sm">
          <Link href={`/${tenantSlug}/hris/onboarding/my-tasks`} className="text-primary underline">
            My assigned tasks
          </Link>
          <Link href={`/${tenantSlug}/hris/onboarding/templates`} className="text-primary underline">
            Checklist templates
          </Link>
        </div>
      </div>

      <OnboardingCaseListPanel
        tenantSlug={tenantSlug}
        cases={cases}
        templates={templates}
        caseTypeFilter={caseTypeFilter}
        statusFilter={statusFilter}
        search={q ?? ""}
        startCaseAction={startOnboardingCaseAction.bind(null, tenantSlug)}
        previewCaseAction={previewOnboardingCaseStartAction.bind(null, tenantSlug)}
        exportCasesAction={exportOnboardingCasesAction.bind(null, tenantSlug, statusFilter)}
      />
    </div>
  );
}
