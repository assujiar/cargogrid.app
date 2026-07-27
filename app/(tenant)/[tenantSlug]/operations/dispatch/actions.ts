"use server";

/**
 * Basic Dispatch queue Server Actions (OPS-175, CG-S8-OPS-009). Dispatches directly
 * from the ready-queue list, mirroring the shipment detail page's own dispatch panel
 * action -- both call the exact same `dispatchShipmentOrder` mutation.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { dispatchShipmentOrder, BasicDispatchMutationError } from "../../../../../server/mutations/basic-dispatch.ts";

export interface DispatchQueueFormState {
  readonly error: string | null;
}

/** assigned -> dispatched, gated on a real commit-time readiness recheck. Idempotent on (shipmentOrderId, idempotencyKey). */
export async function dispatchShipmentOrderFromQueueAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  idempotencyKey: string,
  _prevState: DispatchQueueFormState,
  _formData: FormData,
): Promise<DispatchQueueFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await dispatchShipmentOrder(supabase, { shipmentOrderId, expectedVersion, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof BasicDispatchMutationError) {
      return { error: `Could not dispatch this Shipment Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/dispatch`);
  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
