"use server";

/**
 * Finance Reports server actions (FIN-213, CG-S9-FIN-024). Uses the RLS-scoped
 * `authenticated` client -- app.enqueue_finance_report_export is granted directly to
 * `authenticated` and performs its own FIN:Export entitlement check in-body, the same
 * convention `operations/reports/actions.ts` (OPS-183) already established.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { enqueueFinanceReportExport } from "../../../../../server/mutations/finance-report.ts";
import { ReportMutationError } from "../../../../../server/mutations/report.ts";

export interface ReportExportFormState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function requestFinanceReportExportAction(
  tenantSlug: string,
  reportTypeCode: string,
  _prevState: ReportExportFormState,
  _formData: FormData,
): Promise<ReportExportFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", success: false };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await enqueueFinanceReportExport(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError && error.code === "insufficient_authority") {
      return { error: "You don't hold the Export permission for Finance reports.", success: false };
    }
    if (error instanceof ReportMutationError) {
      return { error: error.message, success: false };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/reports`);
  revalidatePath(`/${tenantSlug}/finance/reports/${reportTypeCode}`);
  return { error: null, success: true };
}
