"use server";

/**
 * Vendor Capacity and Availability Server Actions (PRC-262, CG-S11-PRC-013). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-contracts/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) plus its own bound-per-row-action
 * convention (expectedVersion captured via `.bind()` at render time, not a hidden form
 * field).
 *
 * Idempotency-key disclosure: identical to every other PRC-25x/26x creation form in
 * this repository -- a fresh crypto.randomUUID() is generated here, server-side, on
 * every submit, not client-persisted. The RPC-level idempotency guarantee itself is
 * real and tested, including a live two-process concurrent race
 * (scripts/db-tests/procurement-vendor-capacity.sql).
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorCapacityOfferDraft,
  updateVendorCapacityOfferDraft,
  publishVendorCapacityOffer,
  archiveVendorCapacityOffer,
  addVendorCapacityBlackout,
  removeVendorCapacityBlackout,
  reserveVendorCapacity,
  acceptVendorCapacityReservation,
  declineVendorCapacityReservation,
  releaseVendorCapacityReservation,
  consumeVendorCapacityReservation,
  VendorCapacityMutationError,
} from "../../../../../server/mutations/vendor-capacity.ts";

export interface VendorCapacityActionState {
  readonly error: string | null;
}

const OK: VendorCapacityActionState = { error: null };
const NO_ACCESS: VendorCapacityActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function queuePath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/vendor-capacity`;
}

function detailPath(tenantSlug: string, offerId: string): string {
  return `/${tenantSlug}/procurement/vendor-capacity/${offerId}`;
}

// --- Creation ----------------------------------------------------------------

export async function createVendorCapacityOfferDraftAction(tenantSlug: string, _prevState: VendorCapacityActionState, formData: FormData): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  const serviceType = String(formData.get("serviceType") ?? "").trim();
  const quantityRaw = String(formData.get("quantity") ?? "").trim();
  const uom = String(formData.get("uom") ?? "").trim();
  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  if (!vendorMasterId || !serviceType || !quantityRaw || !uom || !windowStart || !windowEnd) {
    return { error: "Vendor, service type, quantity, UOM, and window start/end are all required." };
  }

  const supabase = await createSupabaseServerClient();
  let offerId: string;
  try {
    const offer = await createVendorCapacityOfferDraft(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      contractId: null,
      serviceType,
      mode: null,
      originLane: null,
      destinationLane: null,
      resourceType: "general",
      resourceMasterId: null,
      quantity: Number(quantityRaw),
      uom,
      windowStart,
      windowEnd,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    offerId = offer.id;
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not create the draft offer: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, offerId));
}

// --- Offer lifecycle -----------------------------------------------------------

export async function updateVendorCapacityOfferDraftAction(
  tenantSlug: string,
  offerId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const quantityRaw = String(formData.get("quantity") ?? "").trim();
  const uom = String(formData.get("uom") ?? "").trim();
  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  if (!quantityRaw || !uom || !windowStart || !windowEnd) {
    return { error: "Quantity, UOM, and window start/end are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateVendorCapacityOfferDraft(supabase, {
      offerId,
      expectedVersion,
      contractId: null,
      mode: null,
      originLane: null,
      destinationLane: null,
      resourceMasterId: null,
      quantity: Number(quantityRaw),
      uom,
      windowStart,
      windowEnd,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not update the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function publishVendorCapacityOfferAction(
  tenantSlug: string,
  offerId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  _formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishVendorCapacityOffer(supabase, { offerId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not publish: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function archiveVendorCapacityOfferAction(
  tenantSlug: string,
  offerId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  _formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await archiveVendorCapacityOffer(supabase, { offerId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not archive: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

// --- Blackout ------------------------------------------------------------------

export async function addVendorCapacityBlackoutAction(tenantSlug: string, offerId: string, _prevState: VendorCapacityActionState, formData: FormData): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!windowStart || !windowEnd || !reason) {
    return { error: "Window start/end and a non-empty reason are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addVendorCapacityBlackout(supabase, { offerId, windowStart, windowEnd, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not add the blackout: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function removeVendorCapacityBlackoutAction(
  tenantSlug: string,
  offerId: string,
  blackoutId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  _formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await removeVendorCapacityBlackout(supabase, { blackoutId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not remove the blackout: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

// --- Reservation lifecycle -------------------------------------------------------

export async function reserveVendorCapacityAction(tenantSlug: string, offerId: string, _prevState: VendorCapacityActionState, formData: FormData): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requestedQuantityRaw = String(formData.get("requestedQuantity") ?? "").trim();
  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  if (!requestedQuantityRaw || !windowStart || !windowEnd) {
    return { error: "Requested quantity and window start/end are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await reserveVendorCapacity(supabase, {
      offerId,
      requestedQuantity: Number(requestedQuantityRaw),
      windowStart,
      windowEnd,
      sourceReferenceType: "manual",
      sourceReferenceId: null,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not reserve capacity: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function acceptVendorCapacityReservationAction(
  tenantSlug: string,
  offerId: string,
  reservationId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  _formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acceptVendorCapacityReservation(supabase, { reservationId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not accept: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function declineVendorCapacityReservationAction(
  tenantSlug: string,
  offerId: string,
  reservationId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to decline a reservation." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await declineVendorCapacityReservation(supabase, { reservationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not decline: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function releaseVendorCapacityReservationAction(
  tenantSlug: string,
  offerId: string,
  reservationId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to release a reservation." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await releaseVendorCapacityReservation(supabase, { reservationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not release: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}

export async function consumeVendorCapacityReservationAction(
  tenantSlug: string,
  offerId: string,
  reservationId: string,
  expectedVersion: number,
  _prevState: VendorCapacityActionState,
  _formData: FormData,
): Promise<VendorCapacityActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await consumeVendorCapacityReservation(supabase, { reservationId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorCapacityMutationError) return { error: `Could not consume: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, offerId));
  return OK;
}
