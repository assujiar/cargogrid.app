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
import {
  assignResource,
  reassignResource,
  holdResourceAssignment,
  resumeResourceAssignment,
  unassignResource,
  ResourceAssignmentMutationError,
} from "../../../../../../server/mutations/resource-assignment.ts";
import { ingestMilestoneEvent, MilestoneManagementMutationError } from "../../../../../../server/mutations/milestone-management.ts";
import {
  reportException,
  assignExceptionOwner,
  acknowledgeException,
  escalateException,
  resolveException,
  closeException,
  reopenException,
  ExceptionEscalationMutationError,
} from "../../../../../../server/mutations/exception-escalation.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";
import type { SetShipmentModeProfileInput, ShipmentModeProfileMode } from "../../../../../../server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts";
import type { ResourceAssignmentRole } from "../../../../../../server/contracts/resource-assignment/resource-assignment.ts";
import type { ExceptionType, ExceptionSeverity } from "../../../../../../server/contracts/exception-escalation/exception-escalation.ts";

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

/** OPS-172: creates the first assignment for a (shipmentOrderId, role) slot. */
export async function assignResourceAction(
  tenantSlug: string,
  shipmentOrderId: string,
  role: ResourceAssignmentRole,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const resourceId = String(formData.get("resourceId") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await assignResource(supabase, { shipmentOrderId, role, resourceId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ResourceAssignmentMutationError) {
      return { error: `Could not assign this ${role}: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-172: reason-mandatory replacement of the current (shipmentOrderId, role) assignment -- the prior row is preserved, never overwritten. */
export async function reassignResourceAction(
  tenantSlug: string,
  shipmentOrderId: string,
  role: ResourceAssignmentRole,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const newResourceId = String(formData.get("resourceId") ?? "");
  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await reassignResource(supabase, { shipmentOrderId, role, newResourceId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ResourceAssignmentMutationError) {
      return { error: `Could not reassign this ${role}: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-172: in-place status flip active -> held on the current (shipmentOrderId, role) assignment -- reason mandatory. */
export async function holdResourceAssignmentAction(
  tenantSlug: string,
  shipmentOrderId: string,
  role: ResourceAssignmentRole,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await holdResourceAssignment(supabase, { shipmentOrderId, role, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ResourceAssignmentMutationError) {
      return { error: `Could not hold this ${role} assignment: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-172: in-place status flip held -> active on the current (shipmentOrderId, role) assignment. */
export async function resumeResourceAssignmentAction(
  tenantSlug: string,
  shipmentOrderId: string,
  role: ResourceAssignmentRole,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await resumeResourceAssignment(supabase, { shipmentOrderId, role, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ResourceAssignmentMutationError) {
      return { error: `Could not resume this ${role} assignment: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-172: releases the (shipmentOrderId, role) slot entirely -- reason mandatory. A subsequent assign may then create a fresh current row for the same role. */
export async function unassignResourceAction(
  tenantSlug: string,
  shipmentOrderId: string,
  role: ResourceAssignmentRole,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await unassignResource(supabase, { shipmentOrderId, role, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ResourceAssignmentMutationError) {
      return { error: `Could not unassign this ${role}: ${error.message}` };
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

/** OPS-173: ingests one milestone event -- idempotent on the fresh-per-render idempotencyKey (see the detail page). A correction (correctsEventId set) requires a non-empty reason. */
export async function ingestMilestoneEventAction(
  tenantSlug: string,
  shipmentOrderId: string,
  idempotencyKey: string,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const milestoneCode = String(formData.get("milestoneCode") ?? "");
  const eventTime = String(formData.get("eventTime") ?? "");
  const locationLabel = String(formData.get("locationLabel") ?? "").trim();
  const correctsEventId = String(formData.get("correctsEventId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await ingestMilestoneEvent(supabase, {
      shipmentOrderId,
      milestoneCode,
      eventTime: new Date(eventTime).toISOString(),
      source: "manual",
      location: locationLabel.length === 0 ? null : { lat: 0, lng: 0, label: locationLabel },
      reason: reason.length === 0 ? null : reason,
      correctsEventId: correctsEventId.length === 0 ? null : correctsEventId,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof MilestoneManagementMutationError) {
      return { error: `Could not record this milestone event: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-174: reports a new operational exception -- always source="manual" for this internal UI. */
export async function reportExceptionAction(
  tenantSlug: string,
  shipmentOrderId: string,
  idempotencyKey: string,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const type = String(formData.get("type") ?? "") as ExceptionType;
  const severity = String(formData.get("severity") ?? "") as ExceptionSeverity;
  const description = String(formData.get("description") ?? "");

  const supabase = await createSupabaseServerClient();
  try {
    await reportException(supabase, {
      shipmentOrderId,
      type,
      severity,
      description,
      source: "manual",
      correlationKey: idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ExceptionEscalationMutationError) {
      return { error: `Could not report this exception: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/**
 * OPS-174: one unified dispatcher for every per-exception lifecycle action
 * (acknowledge/escalate/resolve/close/reopen/assign owner) -- the form's own hidden
 * "action" field selects which real mutation runs, keeping the UI to one compact
 * per-exception control instead of six separate forms.
 */
export async function manageExceptionAction(
  tenantSlug: string,
  shipmentOrderId: string,
  exceptionId: string,
  expectedVersion: number,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const action = String(formData.get("action") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const supabase = await createSupabaseServerClient();

  try {
    if (action === "acknowledge") {
      await acknowledgeException(supabase, { exceptionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else if (action === "escalate") {
      await escalateException(supabase, { exceptionId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else if (action === "resolve") {
      await resolveException(supabase, { exceptionId, expectedVersion, resolutionEvidence: reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else if (action === "close") {
      await closeException(supabase, { exceptionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else if (action === "reopen") {
      await reopenException(supabase, { exceptionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else if (action === "assign_owner") {
      const ownerUserId = String(formData.get("ownerUserId") ?? "");
      await assignExceptionOwner(supabase, { exceptionId, ownerUserId, reason: reason.length === 0 ? null : reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    } else {
      return { error: `Unknown exception action: ${action}` };
    }
  } catch (error) {
    if (error instanceof ExceptionEscalationMutationError) {
      return { error: `Could not perform this action: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
