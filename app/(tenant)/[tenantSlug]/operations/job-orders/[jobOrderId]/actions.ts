"use server";

/**
 * Job Order detail Server Actions (OPS-168, CG-S8-OPS-002). Uses the RLS-scoped
 * `authenticated` client -- every app.* RPC below is granted directly to `authenticated`
 * and performs its own OPS:Edit/OPS:Override/record-access check in-body, the same
 * convention every prior Commercial capability's actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { confirmJobOrder, overrideJobOrderField, JobOrderMutationError } from "../../../../../../server/mutations/job-order.ts";
import type { OverridableSnapshotColumn } from "../../../../../../server/contracts/job-order/job-order.ts";

export interface JobOrderFormState {
  readonly error: string | null;
}

/** draft -> confirmed. Optimistic-concurrency-checked (expectedVersion). */
export async function confirmJobOrderAction(
  tenantSlug: string,
  jobOrderId: string,
  expectedVersion: number,
  _prevState: JobOrderFormState,
  _formData: FormData,
): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await confirmJobOrder(supabase, { jobOrderId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JobOrderMutationError) {
      return { error: `Could not confirm this Job Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** The one bounded, reasoned, audited post-conversion correction path -- restricted to customerSnapshot/cargoServiceSnapshot. */
export async function overrideJobOrderFieldAction(
  tenantSlug: string,
  jobOrderId: string,
  expectedVersion: number,
  snapshotColumn: OverridableSnapshotColumn,
  fieldPath: string,
  newValue: string,
  reason: string,
  _prevState: JobOrderFormState,
  _formData: FormData,
): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await overrideJobOrderField(supabase, {
      jobOrderId,
      expectedVersion,
      snapshotColumn,
      fieldPath,
      newValue,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JobOrderMutationError) {
      return { error: `Could not override this field: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}
