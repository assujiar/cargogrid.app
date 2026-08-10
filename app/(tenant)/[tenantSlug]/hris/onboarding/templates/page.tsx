import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listOnboardingChecklistTemplates, OnboardingQueryError } from "../../../../../../server/queries/onboarding.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { TemplateListPanel } from "./template-list-panel.tsx";
import { createTemplateAction, openDraftVersionAction } from "./actions.ts";

/**
 * Checklist template catalogue (HRT-277, CG-S12-HRT-005, section 20: "versioned
 * onboarding/offboarding workflow"). Every case starts from the tenant's current
 * PUBLISHED template version for its case_type (RPD-040: active cases retain
 * their applied version).
 */
export default async function OnboardingTemplatesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let denied = false;
  let loadFailed = false;
  let templates: Awaited<ReturnType<typeof listOnboardingChecklistTemplates>> = [];
  try {
    templates = await listOnboardingChecklistTemplates(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof OnboardingQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <PermissionState description="You don't have HR permission to view checklist templates." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading checklist templates. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Onboarding/offboarding checklist templates</h1>
        <p className="text-xs text-neutral-500">Versioned per case type. Publishing a new version never retroactively changes an already-started case.</p>
      </div>
      <TemplateListPanel tenantSlug={tenantSlug} templates={templates} createAction={createTemplateAction.bind(null, tenantSlug)} openDraftAction={(templateId: string) => openDraftVersionAction.bind(null, tenantSlug, templateId)} />
    </div>
  );
}
