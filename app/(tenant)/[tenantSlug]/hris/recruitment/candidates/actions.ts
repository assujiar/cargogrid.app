"use server";

/**
 * Candidate directory Server Actions (ISS-2026-067 item 5). Mirrors the sibling
 * actions.ts files' shape exactly: resolve portal access, call the typed
 * query/mutation wrapper, translate errors, revalidate.
 */

import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { exportCandidates } from "../../../../../../server/queries/recruitment.ts";
import type { RecruitmentExportActionState } from "../../../../../../components/domain/recruitment-export-form.tsx";
import { buildRecruitmentExport } from "../../../../../../lib/recruitment/recruitment-export-action.ts";
import type { CandidateStatus } from "../../../../../../server/contracts/recruitment/recruitment.ts";

/**
 * Bulk CSV export of the candidate directory (ISS-2026-067 item 2:
 * `app.export_candidates` had no UI caller). Respects the same status filter the
 * directory page itself is showing.
 */
export async function exportCandidatesAction(
  tenantSlug: string,
  statusFilter: CandidateStatus | null,
  _prevState: RecruitmentExportActionState,
  _formData: FormData,
): Promise<RecruitmentExportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's HRIS workspace.", csv: null, filename: null, rowCount: 0, token: null };

  const supabase = await createSupabaseServerClient();
  return buildRecruitmentExport({
    filenameStem: "candidates",
    header: ["Full name", "Source", "Status"],
    fetchRows: () => exportCandidates(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 500 }),
    toCells: (row) => [row.fullName, row.source, row.status],
  });
}
