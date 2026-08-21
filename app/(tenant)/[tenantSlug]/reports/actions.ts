"use server";

/**
 * Report Library server actions (IAE-002, Reporting Engine, Prompt 330). Uses
 * the RLS-scoped `authenticated` client -- app.cancel_report_run is granted
 * directly to `authenticated` and performs its own requester/COM:Export/Supreme
 * entitlement check in-body, the same convention every prior report action uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { cancelReportRun, ReportMutationError } from "../../../../server/mutations/report.ts";

export interface CancelReportRunFormState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function cancelReportRunAction(
  tenantSlug: string,
  runId: string,
  _prevState: CancelReportRunFormState,
  _formData: FormData,
): Promise<CancelReportRunFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's workspace.", success: false };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelReportRun(supabase, {
      runId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError && error.code === "insufficient_authority") {
      return {
        error: "You may only cancel a report you requested yourself, unless you hold report export authority.",
        success: false,
      };
    }
    if (error instanceof ReportMutationError && error.code === "report_run_not_cancellable") {
      return { error: "This run is no longer queued and can't be cancelled.", success: false };
    }
    if (error instanceof ReportMutationError) {
      return { error: error.message, success: false };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/reports`);
  return { error: null, success: true };
}
