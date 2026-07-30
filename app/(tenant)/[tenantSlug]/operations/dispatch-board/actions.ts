"use server";

/**
 * Advanced Dispatch Board Server Actions (ATW-222, CG-S10-ATW-003). The board's own
 * dispatch action is the identical `dispatch_shipment_order` mutation OPS-175's own
 * queue and the Shipment Order detail panel already call -- no new mutation exists
 * for this capability, only an extended read model.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { dispatchShipmentOrder, BasicDispatchMutationError } from "../../../../../server/mutations/basic-dispatch.ts";

export interface DispatchBoardFormState {
  readonly error: string | null;
}

/** assigned -> dispatched, gated on a real commit-time readiness recheck. Idempotent on (shipmentOrderId, idempotencyKey). */
export async function dispatchShipmentOrderFromBoardAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  idempotencyKey: string,
  _prevState: DispatchBoardFormState,
  _formData: FormData,
): Promise<DispatchBoardFormState> {
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

  revalidatePath(`/${tenantSlug}/operations/dispatch-board`);
  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
