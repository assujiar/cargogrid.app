"use server";

/**
 * Commercial Reports server actions (COM-159, CG-S7-COM-018). Uses the RLS-scoped
 * `authenticated` client -- app.enqueue_report_export is granted directly to
 * `authenticated` and performs its own COM:Export entitlement check in-body, the same
 * convention every prior Commercial capability's actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { enqueueReportExport, ReportMutationError } from "../../../../../server/mutations/report.ts";

export interface ReportExportFormState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function requestReportExportAction(
  tenantSlug: string,
  reportTypeCode: string,
  _prevState: ReportExportFormState,
  _formData: FormData,
): Promise<ReportExportFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace.", success: false };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await enqueueReportExport(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError && error.code === "insufficient_authority") {
      return { error: "You don't hold the Export permission for Commercial reports.", success: false };
    }
    if (error instanceof ReportMutationError) {
      return { error: error.message, success: false };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/reports`);
  revalidatePath(`/${tenantSlug}/commercial/reports/${reportTypeCode}`);
  return { error: null, success: true };
}
