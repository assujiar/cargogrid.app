"use server";

/**
 * Vendor Assignment Server Actions (PRC-263, CG-S11-PRC-014). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-capacity/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) plus its own bound-per-row-action
 * convention (expectedVersion captured via `.bind()` at render time, not a hidden form
 * field).
 *
 * Idempotency-key disclosure: identical to every other PRC-25x/26x creation form in
 * this repository -- a fresh crypto.randomUUID() is generated here, server-side, on
 * every submit, not client-persisted.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  proposeVendorAssignmentInvitation,
  acceptVendorAssignmentInvitation,
  declineVendorAssignmentInvitation,
  cancelVendorAssignmentInvitation,
  confirmVendorAssignment,
  reassignVendorAssignment,
  overrideVendorAssignment,
  VendorAssignmentMutationError,
} from "../../../../../server/mutations/vendor-assignment.ts";

export interface VendorAssignmentActionState {
  readonly error: string | null;
}

const OK: VendorAssignmentActionState = { error: null };
const NO_ACCESS: VendorAssignmentActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function queuePath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/vendor-assignments`;
}

function detailPath(tenantSlug: string, invitationId: string): string {
  return `/${tenantSlug}/procurement/vendor-assignments/${invitationId}`;
}

function optionalUuid(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length > 0 ? raw : null;
}

// --- Propose / override ---------------------------------------------------------

export async function proposeVendorAssignmentInvitationAction(tenantSlug: string, _prevState: VendorAssignmentActionState, formData: FormData): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const shipmentOrderId = String(formData.get("shipmentOrderId") ?? "").trim();
  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  if (!shipmentOrderId || !vendorMasterId) {
    return { error: "Shipment order ID and vendor are both required." };
  }
  const responseDeadlineRaw = String(formData.get("responseDeadline") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  let invitationId: string;
  try {
    const invitation = await proposeVendorAssignmentInvitation(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      vendorMasterId,
      contractId: optionalUuid(formData, "contractId"),
      poId: optionalUuid(formData, "poId"),
      rateVersionId: optionalUuid(formData, "rateVersionId"),
      capacityReservationId: optionalUuid(formData, "capacityReservationId"),
      responseDeadline: responseDeadlineRaw.length > 0 ? responseDeadlineRaw : null,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    invitationId = invitation.id;
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not propose the invitation: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, invitationId));
}

export async function overrideVendorAssignmentAction(tenantSlug: string, _prevState: VendorAssignmentActionState, formData: FormData): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const shipmentOrderId = String(formData.get("shipmentOrderId") ?? "").trim();
  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!shipmentOrderId || !vendorMasterId || !reason) {
    return { error: "Shipment order ID, vendor, and a non-empty reason are all required for an emergency override." };
  }

  const supabase = await createSupabaseServerClient();
  let invitationId: string;
  try {
    const invitation = await overrideVendorAssignment(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      vendorMasterId,
      reason,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    invitationId = invitation.id;
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not override: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, invitationId));
}

// --- Invitation lifecycle --------------------------------------------------------

export async function acceptVendorAssignmentInvitationAction(
  tenantSlug: string,
  invitationId: string,
  expectedVersion: number,
  _prevState: VendorAssignmentActionState,
  _formData: FormData,
): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acceptVendorAssignmentInvitation(supabase, { invitationId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not accept: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, invitationId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function declineVendorAssignmentInvitationAction(
  tenantSlug: string,
  invitationId: string,
  expectedVersion: number,
  _prevState: VendorAssignmentActionState,
  formData: FormData,
): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to decline an invitation." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await declineVendorAssignmentInvitation(supabase, { invitationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not decline: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, invitationId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function cancelVendorAssignmentInvitationAction(
  tenantSlug: string,
  invitationId: string,
  expectedVersion: number,
  _prevState: VendorAssignmentActionState,
  formData: FormData,
): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel an invitation." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelVendorAssignmentInvitation(supabase, { invitationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, invitationId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function confirmVendorAssignmentAction(
  tenantSlug: string,
  invitationId: string,
  expectedVersion: number,
  _prevState: VendorAssignmentActionState,
  _formData: FormData,
): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await confirmVendorAssignment(supabase, { invitationId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not confirm: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, invitationId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function reassignVendorAssignmentAction(
  tenantSlug: string,
  invitationId: string,
  expectedVersion: number,
  _prevState: VendorAssignmentActionState,
  formData: FormData,
): Promise<VendorAssignmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newVendorMasterId = String(formData.get("newVendorMasterId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!newVendorMasterId || !reason) {
    return { error: "A replacement vendor and a non-empty reason are both required to reassign." };
  }

  const supabase = await createSupabaseServerClient();
  let newInvitationId: string;
  try {
    const newInvitation = await reassignVendorAssignment(supabase, {
      invitationId,
      expectedVersion,
      newVendorMasterId,
      newContractId: optionalUuid(formData, "newContractId"),
      newPoId: optionalUuid(formData, "newPoId"),
      newRateVersionId: optionalUuid(formData, "newRateVersionId"),
      newCapacityReservationId: optionalUuid(formData, "newCapacityReservationId"),
      reason,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newInvitationId = newInvitation.id;
  } catch (error) {
    if (error instanceof VendorAssignmentMutationError) return { error: `Could not reassign: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, invitationId));
  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, newInvitationId));
}
