"use server";

/**
 * Operations Reports server actions (OPS-183, CG-S8-OPS-017). Uses the RLS-scoped
 * `authenticated` client -- app.enqueue_ops_report_export is granted directly to
 * `authenticated` and performs its own OPS:Export entitlement check in-body, the same
 * convention `commercial/reports/actions.ts` (COM-159) already established.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { enqueueOpsReportExport } from "../../../../../server/mutations/ops-report.ts";
import { ReportMutationError } from "../../../../../server/mutations/report.ts";

export interface ReportExportFormState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function requestOpsReportExportAction(
  tenantSlug: string,
  reportTypeCode: string,
  _prevState: ReportExportFormState,
  _formData: FormData,
): Promise<ReportExportFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace.", success: false };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await enqueueOpsReportExport(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError && error.code === "insufficient_authority") {
      return { error: "You don't hold the Export permission for Operations reports.", success: false };
    }
    if (error instanceof ReportMutationError) {
      return { error: error.message, success: false };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/reports`);
  revalidatePath(`/${tenantSlug}/operations/reports/${reportTypeCode}`);
  return { error: null, success: true };
}
