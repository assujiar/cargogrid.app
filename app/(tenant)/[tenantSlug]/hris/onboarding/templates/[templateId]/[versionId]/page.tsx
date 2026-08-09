import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../../lib/supabase/server.ts";
import { getOnboardingChecklistTemplateVersion, OnboardingQueryError } from "../../../../../../../../server/queries/onboarding.ts";
import { ErrorState } from "../../../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../../../components/ui/permission-state.tsx";
import { TemplateVersionPanel } from "./template-version-panel.tsx";
import { addTemplateTaskAction, addTemplateTaskDependencyAction, publishTemplateVersionAction } from "../../actions.ts";

/**
 * Checklist template DRAFT version authoring (HRT-277, section 20) -- add tasks
 * and dependency edges, then publish. A published version is immutable
 * (app.onboarding_checklist_template_versions.status='published') -- this page
 * only ever operates on a draft.
 */
export default async function TemplateVersionPage({ params }: { params: Promise<{ tenantSlug: string; templateId: string; versionId: string }> }) {
  const { tenantSlug, templateId, versionId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let denied = false;
  let loadFailed = false;
  let notFoundFlag = false;
  let tasks: Awaited<ReturnType<typeof getOnboardingChecklistTemplateVersion>> = [];
  try {
    tasks = await getOnboardingChecklistTemplateVersion(supabase, versionId, access.authUserId);
  } catch (error) {
    if (!(error instanceof OnboardingQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("template_version_not_found")) notFoundFlag = true;
    else loadFailed = true;
  }

  if (notFoundFlag) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to manage this template version." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading this template version. Please try again." />;
  }

  return (
    <TemplateVersionPanel
      tenantSlug={tenantSlug}
      templateId={templateId}
      versionId={versionId}
      tasks={tasks}
      addTaskAction={addTemplateTaskAction.bind(null, tenantSlug, versionId)}
      addDependencyAction={addTemplateTaskDependencyAction.bind(null, tenantSlug, versionId)}
      publishAction={(expectedVersion: number) => publishTemplateVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
    />
  );
}
