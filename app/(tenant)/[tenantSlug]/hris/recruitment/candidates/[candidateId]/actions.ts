"use server";

/**
 * Candidate profile Server Actions (ISS-2026-067 items 1 and 4). Mirrors the sibling
 * actions.ts files' shape exactly: resolve portal access, call the typed mutation
 * wrapper, translate a known mutation error into a plain-language message, revalidate.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  updateCandidateProfile,
  setCandidateStatus,
  flagCandidateDuplicate,
  decideCandidateDuplicate,
  RecruitmentMutationError,
} from "../../../../../../../server/mutations/recruitment.ts";
import { searchCandidateDuplicates, RecruitmentQueryError } from "../../../../../../../server/queries/recruitment.ts";
import type { CandidateStatus, CandidateDuplicateMatch, CandidateDuplicateCandidate } from "../../../../../../../server/contracts/recruitment/recruitment.ts";

export interface CandidateActionState {
  readonly error: string | null;
}

const OK: CandidateActionState = { error: null };
const NO_ACCESS: CandidateActionState = { error: "You don't have access to this organization's HRIS workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, candidateId: string): string {
  return `/${tenantSlug}/hris/recruitment/candidates/${candidateId}`;
}

/** ISS-2026-067 item 5: the candidate profile-edit surface the directory needed -- `app.update_candidate_profile` already existed and was already wired nowhere. */
export async function updateCandidateProfileAction(tenantSlug: string, candidateId: string, expectedVersion: number, _prevState: CandidateActionState, formData: FormData): Promise<CandidateActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const fullName = String(formData.get("fullName") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const nationalIdNumber = String(formData.get("nationalIdNumber") ?? "").trim() || null;
  const dateOfBirth = String(formData.get("dateOfBirth") ?? "").trim() || null;
  const address = String(formData.get("address") ?? "").trim() || null;
  const resumeFileId = String(formData.get("resumeFileId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await updateCandidateProfile(supabase, {
      id: candidateId,
      expectedVersion,
      fullName,
      phone,
      nationalIdNumber,
      dateOfBirth,
      address,
      resumeFileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not save this candidate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, candidateId));
  return OK;
}

/** ISS-2026-067 item 4: `app.set_candidate_status` (block/archive) had no UI caller. */
export async function setCandidateStatusAction(
  tenantSlug: string,
  candidateId: string,
  expectedVersion: number,
  newStatus: CandidateStatus,
  _prevState: CandidateActionState,
  formData: FormData,
): Promise<CandidateActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await setCandidateStatus(supabase, { id: candidateId, expectedVersion, newStatus, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not update this candidate's status: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, candidateId));
  return OK;
}

export interface DuplicateSearchState {
  readonly error: string | null;
  readonly matches: CandidateDuplicateMatch[];
  readonly searched: boolean;
}

const SEARCH_OK: DuplicateSearchState = { error: null, matches: [], searched: false };

/** ISS-2026-067 item 1: `app.search_candidate_duplicates` had no UI caller. Exact email/phone match plus pg_trgm fuzzy name similarity, human-reviewed-only (never auto-merges) -- see `scripts/db-tests/hris-recruitment-ats.sql`'s own "candidate" block. */
export async function searchCandidateDuplicatesAction(tenantSlug: string, _prevState: DuplicateSearchState, formData: FormData): Promise<DuplicateSearchState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...SEARCH_OK, error: "You don't have access to this organization's HRIS workspace." };

  const fullName = String(formData.get("fullName") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  if (!fullName && !email && !phone) return { ...SEARCH_OK, error: "Provide at least a name, email, or phone to search for possible duplicates." };

  const supabase = await createSupabaseServerClient();
  try {
    const matches = await searchCandidateDuplicates(supabase, access.tenant.id, access.authUserId, { fullName, email, phone, limit: 10 });
    return { error: null, matches, searched: true };
  } catch (error) {
    if (error instanceof RecruitmentQueryError) return { ...SEARCH_OK, error: `Could not search for duplicates: ${error.message}` };
    throw error;
  }
}

export interface DuplicateFlagState {
  readonly error: string | null;
  readonly flagged: CandidateDuplicateCandidate | null;
}

const FLAG_OK: DuplicateFlagState = { error: null, flagged: null };

/**
 * Flags a candidate as a possible duplicate of the one this page belongs to
 * (ISS-2026-067 item 1: `app.flag_candidate_duplicate` had no UI caller). Returns the
 * created record so the caller can immediately decide it -- this repository has no
 * dedicated duplicate-review inbox UI, the same disclosed posture
 * `ApprovalStepForm` in `../../applications/[applicationId]/application-detail-
 * panel.tsx` already established for job-offer approvals ("ships with zero
 * authoring/inbox UI").
 */
export async function flagCandidateDuplicateAction(
  tenantSlug: string,
  sourceCandidateId: string,
  matchCandidateId: string,
  similarityBasis: string,
  similarityScore: number | null,
  _prevState: DuplicateFlagState,
  _formData: FormData,
): Promise<DuplicateFlagState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...FLAG_OK, error: "You don't have access to this organization's HRIS workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    const flagged = await flagCandidateDuplicate(supabase, {
      sourceCandidateId,
      candidateId: matchCandidateId,
      similarityBasis,
      similarityScore,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    return { error: null, flagged };
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { ...FLAG_OK, error: `Could not flag this pair as duplicates: ${error.message}` };
    throw error;
  }
}

/** ISS-2026-067 item 1: `app.decide_candidate_duplicate` had no UI caller. */
export async function decideCandidateDuplicateAction(
  tenantSlug: string,
  duplicateId: string,
  expectedVersion: number,
  decision: "linked" | "dismissed",
  _prevState: CandidateActionState,
  formData: FormData,
): Promise<CandidateActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to decide a duplicate pair." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideCandidateDuplicate(supabase, { id: duplicateId, expectedVersion, decision, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not record this decision: ${error.message}` };
    throw error;
  }

  return OK;
}
