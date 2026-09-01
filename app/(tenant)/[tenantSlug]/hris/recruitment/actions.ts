"use server";

/**
 * Recruitment/ATS Server Actions (HRT-276, CG-S12-HRT-004). Mirrors
 * app/(tenant)/[tenantSlug]/hris/positions/actions.ts's own shape exactly: resolve
 * portal access, call the typed mutation wrapper, translate a known mutation error
 * into a plain-language message, revalidate the affected path(s).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createJobVacancyDraft,
  updateJobVacancyDraft,
  publishJobVacancy,
  holdJobVacancy,
  reopenJobVacancy,
  closeJobVacancy,
  cancelJobVacancyDraft,
  createCandidate,
  applyToVacancy,
  RecruitmentMutationError,
} from "../../../../../server/mutations/recruitment.ts";
import { exportJobVacancies, exportApplications } from "../../../../../server/queries/recruitment.ts";
import type { RecruitmentExportActionState } from "../../../../../components/domain/recruitment-export-form.tsx";
import { buildRecruitmentExport } from "../../../../../lib/recruitment/recruitment-export-action.ts";
import type { VacancyStatus } from "../../../../../server/contracts/recruitment/recruitment.ts";

export interface RecruitmentActionState {
  readonly error: string | null;
}

const OK: RecruitmentActionState = { error: null };
const NO_ACCESS: RecruitmentActionState = { error: "You don't have access to this organization's HRIS workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/hris/recruitment`;
}
function detailPath(tenantSlug: string, vacancyId: string): string {
  return `/${tenantSlug}/hris/recruitment/${vacancyId}`;
}

export async function createJobVacancyDraftAction(tenantSlug: string, positionId: string, _prevState: RecruitmentActionState, formData: FormData): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const employmentType = String(formData.get("employmentType") ?? "full_time") as "full_time" | "part_time" | "contract" | "internship" | "temporary";
  const headcountRaw = String(formData.get("headcount") ?? "1").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const requirements = String(formData.get("requirements") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createJobVacancyDraft(supabase, {
      tenantId: access.tenant.id,
      positionId,
      title,
      employmentType,
      headcount: Number(headcountRaw) || 1,
      description,
      requirements,
      hiringManagerEmployeeId: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not create this vacancy: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function updateJobVacancyDraftAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, formData: FormData): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const employmentType = String(formData.get("employmentType") ?? "full_time") as "full_time" | "part_time" | "contract" | "internship" | "temporary";
  const headcountRaw = String(formData.get("headcount") ?? "1").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const requirements = String(formData.get("requirements") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await updateJobVacancyDraft(supabase, {
      id,
      expectedVersion,
      title,
      employmentType,
      headcount: Number(headcountRaw) || 1,
      description,
      requirements,
      hiringManagerEmployeeId: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not save this vacancy: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  revalidatePath(detailPath(tenantSlug, id));
  return OK;
}

export async function publishJobVacancyAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, formData: FormData): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const validityDaysRaw = String(formData.get("validityDays") ?? "30").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await publishJobVacancy(supabase, { id, expectedVersion, validityDays: Number(validityDaysRaw) || 30, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not publish this vacancy: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  revalidatePath(detailPath(tenantSlug, id));
  return OK;
}

async function vacancyStatusAction(
  tenantSlug: string,
  id: string,
  expectedVersion: number,
  rpc: typeof holdJobVacancy,
  errorPrefix: string,
  formData: FormData,
): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await rpc(supabase, { id, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `${errorPrefix}: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  revalidatePath(detailPath(tenantSlug, id));
  return OK;
}

export async function holdJobVacancyAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, formData: FormData) {
  return vacancyStatusAction(tenantSlug, id, expectedVersion, holdJobVacancy, "Could not place this vacancy on hold", formData);
}
export async function closeJobVacancyAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, formData: FormData) {
  return vacancyStatusAction(tenantSlug, id, expectedVersion, closeJobVacancy, "Could not close this vacancy", formData);
}
export async function cancelJobVacancyDraftAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, formData: FormData) {
  return vacancyStatusAction(tenantSlug, id, expectedVersion, cancelJobVacancyDraft, "Could not cancel this vacancy", formData);
}

export async function reopenJobVacancyAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: RecruitmentActionState, _formData: FormData): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await reopenJobVacancy(supabase, { id, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not reopen this vacancy: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  revalidatePath(detailPath(tenantSlug, id));
  return OK;
}

/** Creates a candidate (staff-entered) and immediately applies them to this vacancy, in two calls -- the vacancy detail page's own "add candidate" form. */
export async function createCandidateAndApplyAction(tenantSlug: string, vacancyId: string, _prevState: RecruitmentActionState, formData: FormData): Promise<RecruitmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const fullName = String(formData.get("fullName") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const source = String(formData.get("source") ?? "staff_created") as "staff_created" | "referral" | "agency" | "talent_pool" | "import";

  const supabase = await createSupabaseServerClient();
  try {
    const candidate = await createCandidate(supabase, {
      tenantId: access.tenant.id,
      fullName,
      email,
      phone,
      source,
      referralEmployeeId: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await applyToVacancy(supabase, {
      vacancyId,
      candidateId: candidate.id,
      source,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not add this candidate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vacancyId));
  return OK;
}

/**
 * Bulk CSV export of the vacancy list (ISS-2026-067 item 2: `app.export_job_vacancies`
 * had no UI caller). Respects the same status filter the list page itself is showing,
 * so "export what I'm looking at" holds -- never a second, silently different dataset.
 */
export async function exportJobVacanciesAction(
  tenantSlug: string,
  statusFilter: VacancyStatus | null,
  _prevState: RecruitmentExportActionState,
  _formData: FormData,
): Promise<RecruitmentExportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's HRIS workspace.", csv: null, filename: null, rowCount: 0, token: null };

  const supabase = await createSupabaseServerClient();
  return buildRecruitmentExport({
    filenameStem: "job-vacancies",
    header: ["Title", "Employment type", "Headcount", "Status"],
    fetchRows: () => exportJobVacancies(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 500 }),
    toCells: (row) => [row.title, row.employmentType, row.headcount, row.status],
  });
}

/**
 * Bulk CSV export of one vacancy's applications (ISS-2026-067 item 2:
 * `app.export_applications` had no UI caller). Scoped to this vacancy -- the vacancy
 * detail page is where the applications pipeline table this exports already lives.
 */
export async function exportApplicationsForVacancyAction(
  tenantSlug: string,
  vacancyId: string,
  _prevState: RecruitmentExportActionState,
  _formData: FormData,
): Promise<RecruitmentExportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's HRIS workspace.", csv: null, filename: null, rowCount: 0, token: null };

  const supabase = await createSupabaseServerClient();
  return buildRecruitmentExport({
    filenameStem: "applications",
    header: ["Vacancy", "Candidate", "Stage", "Source", "Applied at"],
    fetchRows: () => exportApplications(supabase, access.tenant.id, access.authUserId, { vacancyId, limit: 500 }),
    toCells: (row) => [row.vacancyTitle, row.candidateFullName, row.stage, row.source, row.appliedAt],
  });
}
