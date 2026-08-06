import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorAssessments, listVendorAssessmentTemplates, VendorAssessmentQueryError } from "../../../../../server/queries/vendor-assessment.ts";
import { listVendorProfiles } from "../../../../../server/queries/vendor-profile.ts";
import type { VendorAssessmentStatus } from "../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { AssessmentQueuePanel } from "./assessment-queue-panel.tsx";
import { startVendorAssessmentAction } from "./actions.ts";

/**
 * Vendor Assessment queue (PRC-252, CG-S11-PRC-003) -- cursor-paginated, server-side
 * status filter and an "assigned to me" tab (Prompt 252 §15's own "assessment queue,
 * assigned to me / all" requirement). The "start a new assessment" form is folded
 * into this same page, matching PRC-251's own vendors/page.tsx precedent of a
 * create-draft form on the list page rather than a separate wizard route.
 */
export default async function VendorAssessmentQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; mine?: string; after?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, mine, after } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as VendorAssessmentStatus) : null) ?? null;
  const assignedToMe = mine === "1";

  let loadFailed = false;
  let assessments: Awaited<ReturnType<typeof listVendorAssessments>> = [];
  let vendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  let templates: Awaited<ReturnType<typeof listVendorAssessmentTemplates>> = [];
  try {
    [assessments, vendors, templates] = await Promise.all([
      listVendorAssessments(supabase, access.tenant.id, access.authUserId, { statusFilter, assignedToMe, limit: 50, afterId: after ?? null }),
      listVendorProfiles(supabase, access.tenant.id, access.authUserId, { limit: 200 }),
      listVendorAssessmentTemplates(supabase, access.tenant.id, access.authUserId, { statusFilter: "published", limit: 100 }),
    ]);
  } catch (error) {
    if (!(error instanceof VendorAssessmentQueryError) && !(error instanceof Error)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the assessment queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Vendor assessments</h1>
          <p className="text-xs text-neutral-500">Initial, periodic and event-driven assessments with explainable scoring, findings and approval.</p>
        </div>
        <a href={`/${tenantSlug}/procurement/assessments/templates`} className="text-sm text-primary underline">
          Manage templates
        </a>
      </div>

      <AssessmentQueuePanel
        tenantSlug={tenantSlug}
        assessments={assessments}
        vendors={vendors}
        templates={templates}
        statusFilter={statusFilter}
        assignedToMe={assignedToMe}
        startAction={startVendorAssessmentAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
