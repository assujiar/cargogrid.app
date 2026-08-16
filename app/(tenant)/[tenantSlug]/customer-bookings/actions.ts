"use server";

/**
 * Customer Booking Request Server Actions (CPL-303, CG-S13-CPL-005). Mirrors
 * app/(tenant)/[tenantSlug]/customer-quotes/actions.ts's own shape --
 * resolve the portal guard first, forward to the typed mutation wrapper,
 * classify the error into a form-safe message, revalidate the affected
 * route. Every write is scope-gated at the RPC layer itself (app.resolve_
 * customer_account_scope) -- this file never re-derives or trusts a
 * client-supplied account id, it only forwards.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer
 * 4 portal entry guard).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import {
  createCustomerBookingRequestDraft,
  updateCustomerBookingRequestDraft,
  submitCustomerBookingRequest,
  requestCustomerBookingReschedule,
  requestCustomerBookingCancellation,
  CustomerBookingRequestMutationError,
} from "../../../../server/mutations/customer-booking-request.ts";

export interface CustomerBookingRequestActionState {
  readonly error: string | null;
}

const OK: CustomerBookingRequestActionState = { error: null };
const NO_ACCESS: CustomerBookingRequestActionState = { error: "You don't have access to this organization's customer portal." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/customer-bookings`;
}

function detailPath(tenantSlug: string, bookingRequestId: string): string {
  return `/${tenantSlug}/customer-bookings/${bookingRequestId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerBookingRequestActionState {
  if (error instanceof CustomerBookingRequestMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

function orNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

function isoOrNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  if (text.length === 0) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function readLocation(formData: FormData, prefix: "pickup" | "delivery"): Record<string, string> | null {
  const label = orNull(formData.get(`${prefix}Label`));
  const contactName = orNull(formData.get(`${prefix}ContactName`));
  const contactPhone = orNull(formData.get(`${prefix}ContactPhone`));
  const value: Record<string, string> = {};
  if (label) value.label = label;
  if (contactName) value.contactName = contactName;
  if (contactPhone) value.contactPhone = contactPhone;
  return Object.keys(value).length === 0 ? null : value;
}

export async function createCustomerBookingRequestDraftAction(
  tenantSlug: string,
  idempotencyKey: string,
  _prevState: CustomerBookingRequestActionState,
  formData: FormData,
): Promise<CustomerBookingRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const accountId = orNull(formData.get("accountId"));
  if (!accountId) return { error: "Select an account to book a shipment for." };

  const supabase = await createSupabaseServerClient();
  try {
    await createCustomerBookingRequestDraft(supabase, {
      tenantId: access.tenant.id,
      accountId,
      linkedQuoteRequestId: orNull(formData.get("linkedQuoteRequestId")),
      cargoDescription: orNull(formData.get("cargoDescription")),
      pickup: readLocation(formData, "pickup"),
      delivery: readLocation(formData, "delivery"),
      requestedPickupAt: isoOrNull(formData.get("requestedPickupAt")),
      requestedDeliveryAt: isoOrNull(formData.get("requestedDeliveryAt")),
      specialInstructions: orNull(formData.get("specialInstructions")),
      // Tier C fix (spec-compliance): idempotencyKey is now generated ONCE
      // per Server Component render (see page.tsx's own randomUUID() call)
      // and bound into this action's closure -- not regenerated here on
      // every invocation. A `Date.now()`-derived key computed inside the
      // action body produced a DIFFERENT key on every physical
      // re-invocation, defeating the double-submit protection this
      // parameter exists for. Mirrors CPL-302's identical fix.
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not start this booking", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function updateCustomerBookingRequestDraftAction(
  tenantSlug: string,
  bookingRequestId: string,
  expectedVersion: number,
  _prevState: CustomerBookingRequestActionState,
  formData: FormData,
): Promise<CustomerBookingRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await updateCustomerBookingRequestDraft(supabase, {
      bookingRequestId,
      expectedVersion,
      cargoDescription: orNull(formData.get("cargoDescription")),
      pickup: readLocation(formData, "pickup"),
      delivery: readLocation(formData, "delivery"),
      requestedPickupAt: isoOrNull(formData.get("requestedPickupAt")),
      requestedDeliveryAt: isoOrNull(formData.get("requestedDeliveryAt")),
      specialInstructions: orNull(formData.get("specialInstructions")),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not save these changes", error);
  }
  revalidatePath(detailPath(tenantSlug, bookingRequestId));
  return OK;
}

export async function submitCustomerBookingRequestAction(
  tenantSlug: string,
  bookingRequestId: string,
  expectedVersion: number,
  _prevState: CustomerBookingRequestActionState,
  _formData: FormData,
): Promise<CustomerBookingRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitCustomerBookingRequest(supabase, { bookingRequestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not submit this booking", error);
  }
  revalidatePath(detailPath(tenantSlug, bookingRequestId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function requestCustomerBookingRescheduleAction(
  tenantSlug: string,
  bookingRequestId: string,
  expectedVersion: number,
  _prevState: CustomerBookingRequestActionState,
  formData: FormData,
): Promise<CustomerBookingRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = orNull(formData.get("reason"));
  if (!reason) return { error: "A reason is required to request a reschedule." };

  const requestedPickupAt = isoOrNull(formData.get("requestedPickupAt"));
  const requestedDeliveryAt = isoOrNull(formData.get("requestedDeliveryAt"));
  if (!requestedPickupAt && !requestedDeliveryAt) {
    return { error: "Enter at least one new requested pickup or delivery date/time." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestCustomerBookingReschedule(supabase, {
      bookingRequestId,
      expectedVersion,
      requestedPickupAt,
      requestedDeliveryAt,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not request a reschedule", error);
  }
  revalidatePath(detailPath(tenantSlug, bookingRequestId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function requestCustomerBookingCancellationAction(
  tenantSlug: string,
  bookingRequestId: string,
  expectedVersion: number,
  _prevState: CustomerBookingRequestActionState,
  formData: FormData,
): Promise<CustomerBookingRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = orNull(formData.get("reason"));
  if (!reason) return { error: "A reason is required to cancel a booking." };

  const supabase = await createSupabaseServerClient();
  try {
    await requestCustomerBookingCancellation(supabase, { bookingRequestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not cancel this booking", error);
  }
  revalidatePath(detailPath(tenantSlug, bookingRequestId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}
