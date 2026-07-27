"use server";

/**
 * Shipment Order detail Server Actions (OPS-169, CG-S8-OPS-003). Uses the RLS-scoped
 * `authenticated` client, mirroring the Job Order detail actions (OPS-168).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { confirmShipmentOrder, ShipmentOrderMutationError } from "../../../../../../server/mutations/shipment-order.ts";
import { transitionShipmentOrder, ShipmentLifecycleMutationError } from "../../../../../../server/mutations/shipment-lifecycle.ts";
import { setShipmentModeProfile, changeShipmentMode, ShipmentModeBaselineMutationError } from "../../../../../../server/mutations/shipment-mode-baseline.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";
import type { SetShipmentModeProfileInput, ShipmentModeProfileMode } from "../../../../../../server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts";

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

/**
 * OPS-170: the one canonical, idempotent transition entry point for every status
 * change beyond draft -> confirmed. idempotencyKey is generated fresh per form
 * render (see the detail page), not regenerated per submit, so a genuine retry
 * reuses the same key.
 */
export async function transitionShipmentOrderAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  idempotencyKey: string,
  toStatus: TransitionableStatus,
  reason: string,
  evidenceRef: string,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await transitionShipmentOrder(supabase, {
      shipmentOrderId,
      toStatus,
      expectedVersion,
      reason: reason.trim().length === 0 ? null : reason,
      evidenceRef: evidenceRef.trim().length === 0 ? null : evidenceRef,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ShipmentLifecycleMutationError) {
      return { error: `Could not transition this Shipment Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/**
 * OPS-171: the one idempotent create-or-update path for a Shipment Order's own mode
 * profile. `mode` is the shipment's own current mode (read server-side by the page,
 * bound into this action) -- never a value the form itself chooses, since a profile's
 * shape must always match its shipment's real mode.
 */
export async function setShipmentModeProfileAction(
  tenantSlug: string,
  shipmentOrderId: string,
  mode: ShipmentModeProfileMode,
  fields: Record<string, string>,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const orNull = (value: string | undefined): string | null => (!value || value.trim().length === 0 ? null : value);

  const input: SetShipmentModeProfileInput =
    mode === "land"
      ? { shipmentOrderId, mode: "land", vehicleRef: fields.vehicleRef ?? "", vendorRef: fields.vendorRef ?? "", pickupAddress: fields.pickupAddress ?? "", deliveryAddress: fields.deliveryAddress ?? "", actorAuthUserId: access.authUserId, actorLabel: access.authUserId }
      : mode === "air"
        ? { shipmentOrderId, mode: "air", awbNumber: fields.awbNumber ?? "", flightNumber: fields.flightNumber ?? "", originAirport: fields.originAirport ?? "", destinationAirport: fields.destinationAirport ?? "", actorAuthUserId: access.authUserId, actorLabel: access.authUserId }
        : {
            shipmentOrderId,
            mode: "sea",
            blNumber: fields.blNumber ?? "",
            bookingNumber: fields.bookingNumber ?? "",
            vesselName: fields.vesselName ?? "",
            originPort: fields.originPort ?? "",
            destinationPort: fields.destinationPort ?? "",
            containerNumber: orNull(fields.containerNumber),
            containerType: orNull(fields.containerType),
            actorAuthUserId: access.authUserId,
            actorLabel: access.authUserId,
          };

  const supabase = await createSupabaseServerClient();
  try {
    await setShipmentModeProfile(supabase, input);
  } catch (error) {
    if (error instanceof ShipmentModeBaselineMutationError) {
      return { error: `Could not set the mode profile: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-171: the one path that may alter a Shipment Order's own mode -- draft-only, reconciles the prior profile. */
export async function changeShipmentModeAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  newMode: ShipmentModeProfileMode,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await changeShipmentMode(supabase, { shipmentOrderId, newMode, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShipmentModeBaselineMutationError) {
      return { error: `Could not change this Shipment Order's mode: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
