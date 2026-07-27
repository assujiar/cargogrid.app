"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createShipmentOrderFromJob, ShipmentOrderMutationError } from "../../../../../../server/mutations/shipment-order.ts";
import type { ShipmentMode } from "../../../../../../server/contracts/shipment-order/shipment-order.ts";

export interface CreateShipmentOrderState {
  readonly error: string | null;
}

/**
 * OPS-169: idempotent on (tenant, job order, idempotencyKey) -- a retry with the same
 * key returns the same row, never a duplicate. idempotencyKey is generated once when
 * the create page itself renders (a hidden field, not regenerated per submit) so a
 * genuine resubmission (e.g. a network retry) reuses the same key; a fresh page load
 * for a deliberate new split gets a fresh key.
 */
export async function createShipmentOrderFromJobAction(
  tenantSlug: string,
  jobOrderId: string,
  idempotencyKey: string,
  serviceType: string,
  mode: ShipmentMode,
  origin: string,
  destination: string,
  plannedPickupAt: string,
  plannedDeliveryAt: string,
  allocatedQuantity: string,
  allocatedWeightKg: string,
  allocatedVolumeCbm: string,
  basisQuantity: string,
  basisWeightKg: string,
  basisVolumeCbm: string,
  splitReason: string,
  _prevState: CreateShipmentOrderState,
  _formData: FormData,
): Promise<CreateShipmentOrderState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const toNumberOrNull = (value: string): number | null => (value.trim().length === 0 ? null : Number(value));
  const toStringOrNull = (value: string): string | null => (value.trim().length === 0 ? null : value);

  const supabase = await createSupabaseServerClient();
  let shipmentId: string;
  try {
    const shipment = await createShipmentOrderFromJob(supabase, {
      jobOrderId,
      idempotencyKey,
      serviceType,
      mode,
      origin,
      destination,
      plannedPickupAt: toStringOrNull(plannedPickupAt),
      plannedDeliveryAt: toStringOrNull(plannedDeliveryAt),
      allocatedQuantity: toNumberOrNull(allocatedQuantity),
      allocatedWeightKg: toNumberOrNull(allocatedWeightKg),
      allocatedVolumeCbm: toNumberOrNull(allocatedVolumeCbm),
      basisQuantity: toNumberOrNull(basisQuantity),
      basisWeightKg: toNumberOrNull(basisWeightKg),
      basisVolumeCbm: toNumberOrNull(basisVolumeCbm),
      splitReason: toStringOrNull(splitReason),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    shipmentId = shipment.id;
  } catch (error) {
    if (error instanceof ShipmentOrderMutationError) {
      return { error: `Could not create this Shipment Order: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/operations/shipment-orders/${shipmentId}`);
}
