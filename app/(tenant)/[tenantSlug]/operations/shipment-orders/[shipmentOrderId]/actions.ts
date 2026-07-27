"use server";

/**
 * Shipment Order detail Server Actions (OPS-169, CG-S8-OPS-003). Uses the RLS-scoped
 * `authenticated` client, mirroring the Job Order detail actions (OPS-168).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { confirmShipmentOrder, cancelShipmentOrder, ShipmentOrderMutationError } from "../../../../../../server/mutations/shipment-order.ts";

export interface ShipmentOrderFormState {
  readonly error: string | null;
}

/** draft -> confirmed. */
export async function confirmShipmentOrderAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await confirmShipmentOrder(supabase, { shipmentOrderId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShipmentOrderMutationError) {
      return { error: `Could not confirm this Shipment Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** draft/confirmed -> cancelled, mandatory reason. */
export async function cancelShipmentOrderAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  reason: string,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelShipmentOrder(supabase, { shipmentOrderId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShipmentOrderMutationError) {
      return { error: `Could not cancel this Shipment Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
