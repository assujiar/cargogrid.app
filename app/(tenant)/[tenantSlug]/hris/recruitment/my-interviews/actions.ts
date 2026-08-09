"use server";

/** My-interviews Server Action (HRT-276, CG-S12-HRT-004). Identity-gated -- design note 5. */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { submitInterviewFeedback, RecruitmentMutationError } from "../../../../../../server/mutations/recruitment.ts";
import type { InterviewRecommendation } from "../../../../../../server/contracts/recruitment/recruitment.ts";

export interface MyInterviewsActionState {
  readonly error: string | null;
}

const OK: MyInterviewsActionState = { error: null };
const NO_ACCESS: MyInterviewsActionState = { error: "You don't have access to this organization's HRIS workspace." };

export async function submitMyInterviewFeedbackAction(tenantSlug: string, interviewId: string, _prevState: MyInterviewsActionState, formData: FormData): Promise<MyInterviewsActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const rating = Number(String(formData.get("rating") ?? "3"));
  const recommendation = String(formData.get("recommendation") ?? "yes") as InterviewRecommendation;
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitInterviewFeedback(supabase, { interviewId, rating, recommendation, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not submit feedback: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/recruitment/my-interviews`);
  return OK;
}
