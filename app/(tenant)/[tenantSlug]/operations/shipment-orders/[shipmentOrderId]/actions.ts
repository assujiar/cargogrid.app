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
import { dispatchShipmentOrder, BasicDispatchMutationError } from "../../../../../../server/mutations/basic-dispatch.ts";
import {
  pinShipmentDocumentChecklist,
  linkDocumentToChecklistItem,
  reviewDocumentChecklistItem,
  uploadShipmentDocumentFile,
  DocumentRequirementMutationError,
} from "../../../../../../server/mutations/document-requirement.ts";
import {
  startEpodCapture,
  setEpodEvidence,
  submitEpodCapture,
  reviewEpodCapture,
  reviseEpodCapture,
  completeEpodCapture,
  EpodCaptureReviewMutationError,
} from "../../../../../../server/mutations/epod-capture-review.ts";
import type { GeoJsonPoint } from "../../../../../../server/contracts/epod-capture-review/epod-capture-review.ts";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
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

/** OPS-175: the one validated dispatch command -- assigned -> dispatched, gated on a real commit-time readiness recheck. Idempotent on (shipmentOrderId, idempotencyKey). */
export async function dispatchShipmentOrderAction(
  tenantSlug: string,
  shipmentOrderId: string,
  expectedVersion: number,
  idempotencyKey: string,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
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

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  revalidatePath(`/${tenantSlug}/operations/dispatch`);
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

/** OPS-176: additive-only checklist sync -- pins any currently-published requirement matching the shipment's mode/service_type not yet pinned. */
export async function pinDocumentChecklistAction(tenantSlug: string, shipmentOrderId: string, _prevState: ShipmentOrderFormState, _formData: FormData): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await pinShipmentDocumentChecklist(supabase, { shipmentOrderId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof DocumentRequirementMutationError) {
      return { error: `Could not sync the document checklist: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/**
 * OPS-176: uploads file metadata through the Platform Document/File Engine
 * (app.initiate_file_upload, PLT-128, service_role-only -- lib/supabase/service-role.ts's
 * createSupabaseServiceRoleClient is the same "explicit actor, service-role execution"
 * pattern lib/portal/tenant-admin-guard-deps.server.ts already established), then links
 * the resulting file to this checklist item through the RLS-scoped authenticated client.
 * No live storage backend exists in this sandbox -- only filename/MIME/size metadata is
 * ever captured, the same disclosed constraint PLT-128's own migration recorded.
 */
export async function uploadAndLinkDocumentAction(
  tenantSlug: string,
  shipmentOrderId: string,
  checklistItemId: string,
  documentTypeCode: string,
  idempotencyKey: string,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const originalFilename = String(formData.get("originalFilename") ?? "");
  const mimeType = String(formData.get("mimeType") ?? "");
  const sizeBytes = Number(formData.get("sizeBytes") ?? 0);

  try {
    const serviceRole = createSupabaseServiceRoleClient();
    const file = await uploadShipmentDocumentFile(serviceRole, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      documentTypeCode,
      originalFilename,
      mimeType,
      sizeBytes,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });

    const supabase = await createSupabaseServerClient();
    await linkDocumentToChecklistItem(supabase, { checklistItemId, fileId: file.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof DocumentRequirementMutationError) {
      return { error: `Could not upload/link this document: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-176: approve/reject the linked evidence for one checklist item. Approving an unscanned or unsafe file is rejected server-side (document_checklist_unsafe_file) regardless of what the UI disables. */
export async function reviewDocumentChecklistItemAction(
  tenantSlug: string,
  shipmentOrderId: string,
  checklistItemId: string,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const decision = String(formData.get("decision") ?? "") as "approved" | "rejected";
  const notes = String(formData.get("notes") ?? "").trim();
  const expiresAtLocal = String(formData.get("expiresAt") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await reviewDocumentChecklistItem(supabase, {
      checklistItemId,
      decision,
      notes: notes.length === 0 ? null : notes,
      expiresAt: expiresAtLocal.length === 0 ? null : new Date(expiresAtLocal).toISOString(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof DocumentRequirementMutationError) {
      return { error: `Could not record this review decision: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-177: begins ePOD capture -- requires the shipment to already be delivered. */
export async function startEpodCaptureAction(tenantSlug: string, shipmentOrderId: string, idempotencyKey: string, _prevState: ShipmentOrderFormState, _formData: FormData): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await startEpodCapture(supabase, { tenantId: access.tenant.id, shipmentOrderId, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not start ePOD capture: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/**
 * OPS-177: uploads any provided signature/photo file metadata (through the same
 * service-role `app.initiate_file_upload` path OPS-176 already established) and saves
 * receiver/geolocation/captured-at evidence on the current draft/revision_requested
 * ePOD capture version. No live storage backend exists in this sandbox -- MIME type
 * and size are fixed placeholders, matching PLT-128's own disclosed constraint.
 */
export async function setEpodEvidenceAction(
  tenantSlug: string,
  shipmentOrderId: string,
  captureId: string,
  idempotencyKeyPrefix: string,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const receiverName = String(formData.get("receiverName") ?? "");
  const receiverPosition = String(formData.get("receiverPosition") ?? "").trim();
  const signatureFilename = String(formData.get("signatureFilename") ?? "").trim();
  const photoFilename = String(formData.get("photoFilename") ?? "").trim();
  const latitude = String(formData.get("latitude") ?? "").trim();
  const longitude = String(formData.get("longitude") ?? "").trim();
  const capturedAtLocal = String(formData.get("capturedAt") ?? "").trim();

  try {
    const serviceRole = createSupabaseServiceRoleClient();
    let signatureFileId: string | null = null;
    if (signatureFilename.length > 0) {
      const file = await uploadShipmentDocumentFile(serviceRole, {
        tenantId: access.tenant.id,
        shipmentOrderId,
        documentTypeCode: "epod",
        originalFilename: signatureFilename,
        mimeType: "image/png",
        sizeBytes: 20480,
        idempotencyKey: `${idempotencyKeyPrefix}-sig`,
        actorAuthUserId: access.authUserId,
        actorLabel: access.authUserId,
      });
      signatureFileId = file.id;
    }
    let photoFileIds: string[] = [];
    if (photoFilename.length > 0) {
      const file = await uploadShipmentDocumentFile(serviceRole, {
        tenantId: access.tenant.id,
        shipmentOrderId,
        documentTypeCode: "epod",
        originalFilename: photoFilename,
        mimeType: "image/jpeg",
        sizeBytes: 102400,
        idempotencyKey: `${idempotencyKeyPrefix}-photo`,
        actorAuthUserId: access.authUserId,
        actorLabel: access.authUserId,
      });
      photoFileIds = [file.id];
    }

    const deliveryGeojson: GeoJsonPoint | null =
      latitude.length > 0 && longitude.length > 0 ? { type: "Point", coordinates: [Number(longitude), Number(latitude)] } : null;

    const supabase = await createSupabaseServerClient();
    await setEpodEvidence(supabase, {
      captureId,
      receiverName: receiverName.trim().length === 0 ? null : receiverName,
      receiverPosition: receiverPosition.length === 0 ? null : receiverPosition,
      signatureFileId,
      photoFileIds,
      deliveryGeojson,
      capturedAt: capturedAtLocal.length === 0 ? null : new Date(capturedAtLocal).toISOString(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not save this ePOD evidence: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-177: draft/revision_requested -> submitted. Requires a receiver name, at least one evidence file, and every referenced file to have already scanned clean. */
export async function submitEpodCaptureAction(
  tenantSlug: string,
  shipmentOrderId: string,
  captureId: string,
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
    await submitEpodCapture(supabase, { captureId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not submit this ePOD capture: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-177: submitted -> approved | revision_requested. */
export async function reviewEpodCaptureAction(
  tenantSlug: string,
  shipmentOrderId: string,
  captureId: string,
  expectedVersion: number,
  _prevState: ShipmentOrderFormState,
  formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const decision = String(formData.get("decision") ?? "") as "approved" | "revision_requested";
  const notes = String(formData.get("notes") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await reviewEpodCapture(supabase, { captureId, decision, notes: notes.length === 0 ? null : notes, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not record this ePOD review decision: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-177: revision_requested -> a brand-new draft version; the prior rejected version is preserved unmutated. */
export async function reviseEpodCaptureAction(
  tenantSlug: string,
  shipmentOrderId: string,
  previousCaptureId: string,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await reviseEpodCapture(supabase, { previousCaptureId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not start a revision: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}

/** OPS-177: approved -> completed; also transitions the shipment delivered -> epod through OPS-170's own existing transition command. */
export async function completeEpodCaptureAction(
  tenantSlug: string,
  shipmentOrderId: string,
  captureId: string,
  expectedCaptureVersion: number,
  shipmentExpectedVersion: number,
  idempotencyKey: string,
  _prevState: ShipmentOrderFormState,
  _formData: FormData,
): Promise<ShipmentOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await completeEpodCapture(supabase, {
      captureId,
      expectedCaptureVersion,
      shipmentExpectedVersion,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof EpodCaptureReviewMutationError) {
      return { error: `Could not complete this ePOD capture: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`);
  return { error: null };
}
