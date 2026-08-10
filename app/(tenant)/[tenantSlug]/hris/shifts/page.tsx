import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listShiftTemplates, ShiftRosterQueryError } from "../../../../../server/queries/shift-roster.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ShiftTemplatePanel } from "./shift-template-panel.tsx";
import { createShiftTemplateAction, createAndPublishShiftTemplateVersionAction } from "./actions.ts";

/**
 * Shift template authoring (HRT-279, decision 1). A real, reachable UI caller
 * for app.create_shift_template/create_shift_template_version/publish_shift_
 * template_version -- without this, no schedule assignment or roster cycle
 * could ever reference a published shift (taxonomy C-20).
 */
export default async function ShiftTemplatesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let templates: Awaited<ReturnType<typeof listShiftTemplates>> = [];
  try {
    templates = await listShiftTemplates(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof ShiftRosterQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading shift templates. Please try again." />;
  }

  return (
    <ShiftTemplatePanel
      templates={templates}
      createShiftTemplateAction={createShiftTemplateAction.bind(null, tenantSlug)}
      createAndPublishVersionAction={(shiftTemplateId: string) => createAndPublishShiftTemplateVersionAction.bind(null, tenantSlug, shiftTemplateId)}
    />
  );
}
