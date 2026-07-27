"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { prepareJobOrder, JobOrderMutationError } from "../../../../../../server/mutations/job-order.ts";

export interface PrepareJobOrderState {
  readonly error: string | null;
}

/** OPS-168: idempotent -- calling this again after a Job Order already exists for this handoff simply re-fetches the same row, it never re-derives or duplicates it. */
export async function prepareJobOrderAction(
  tenantSlug: string,
  sourceHandoffId: string,
  _prevState: PrepareJobOrderState,
  _formData: FormData,
): Promise<PrepareJobOrderState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let jobOrderId: string;
  try {
    const jobOrder = await prepareJobOrder(supabase, { sourceHandoffId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    jobOrderId = jobOrder.id;
  } catch (error) {
    if (error instanceof JobOrderMutationError) {
      return { error: `Could not convert this handoff into a Job Order: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
}
