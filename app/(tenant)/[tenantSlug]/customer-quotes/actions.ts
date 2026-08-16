"use server";

/**
 * Customer Quote Request Server Actions (CPL-302, CG-S13-CPL-004). Mirrors
 * app/(tenant)/[tenantSlug]/customer-tickets/actions.ts's own shape --
 * resolve the portal guard first, forward to the typed mutation wrapper,
 * classify the error into a form-safe message, revalidate the affected
 * route. Every write is scope-gated at the RPC layer itself (app.resolve_
 * customer_account_scope) -- this file never re-derives or trusts a
 * client-supplied account id, it only forwards.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer
 * 4 portal entry guard), not the Phase-7-specific customer-ticket-guard.ts.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import {
  createCustomerQuoteRequestDraft,
  updateCustomerQuoteRequestDraft,
  submitCustomerQuoteRequest,
  cancelCustomerQuoteRequest,
  CustomerQuoteRequestMutationError,
} from "../../../../server/mutations/customer-quote-request.ts";
import { uploadCustomerQuoteRequestAttachment, CustomerQuoteRequestAttachmentMutationError } from "../../../../server/mutations/customer-quote-request-attachment.ts";
import { getCustomerQuoteRequest, CustomerQuoteRequestQueryError } from "../../../../server/queries/customer-quote-request.ts";

export interface CustomerQuoteRequestActionState {
  readonly error: string | null;
}

const OK: CustomerQuoteRequestActionState = { error: null };
const NO_ACCESS: CustomerQuoteRequestActionState = { error: "You don't have access to this organization's customer portal." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/customer-quotes`;
}

function detailPath(tenantSlug: string, requestId: string): string {
  return `/${tenantSlug}/customer-quotes/${requestId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerQuoteRequestActionState {
  if (error instanceof CustomerQuoteRequestMutationError || error instanceof CustomerQuoteRequestAttachmentMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

function orNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

function readLocation(formData: FormData, prefix: "origin" | "destination"): Record<string, string> | null {
  const label = orNull(formData.get(`${prefix}Label`));
  const addressLine = orNull(formData.get(`${prefix}AddressLine`));
  const city = orNull(formData.get(`${prefix}City`));
  const country = orNull(formData.get(`${prefix}Country`));
  const value: Record<string, string> = {};
  if (label) value.label = label;
  if (addressLine) value.addressLine = addressLine;
  if (city) value.city = city;
  if (country) value.country = country;
  return Object.keys(value).length === 0 ? null : value;
}

export async function createCustomerQuoteRequestDraftAction(
  tenantSlug: string,
  idempotencyKey: string,
  _prevState: CustomerQuoteRequestActionState,
  formData: FormData,
): Promise<CustomerQuoteRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const accountId = orNull(formData.get("accountId"));
  if (!accountId) return { error: "Select an account to request a quotation for." };

  const supabase = await createSupabaseServerClient();
  try {
    await createCustomerQuoteRequestDraft(supabase, {
      tenantId: access.tenant.id,
      accountId,
      cargoDescription: orNull(formData.get("cargoDescription")),
      origin: readLocation(formData, "origin"),
      destination: readLocation(formData, "destination"),
      serviceType: orNull(formData.get("serviceType")),
      requestedPickupDate: orNull(formData.get("requestedPickupDate")),
      requestedDeliveryDate: orNull(formData.get("requestedDeliveryDate")),
      notes: orNull(formData.get("notes")),
      // Tier C fix (spec-compliance): idempotencyKey is now generated ONCE
      // per Server Component render (see page.tsx's own randomUUID() call)
      // and bound into this action's closure -- not regenerated here on
      // every invocation. A `Date.now()`-derived key computed inside the
      // action body produces a DIFFERENT key on every physical
      // re-invocation (double-click, network retry), defeating the
      // double-submit protection this parameter exists for; a stable
      // per-render key means a genuine retry of the SAME rendered form
      // reuses the SAME key, mirroring the submit/cancel actions' own
      // established pattern (customer-quotes/[requestId]/page.tsx).
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not start this quote request", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function updateCustomerQuoteRequestDraftAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  _prevState: CustomerQuoteRequestActionState,
  formData: FormData,
): Promise<CustomerQuoteRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await updateCustomerQuoteRequestDraft(supabase, {
      requestId,
      expectedVersion,
      cargoDescription: orNull(formData.get("cargoDescription")),
      origin: readLocation(formData, "origin"),
      destination: readLocation(formData, "destination"),
      serviceType: orNull(formData.get("serviceType")),
      requestedPickupDate: orNull(formData.get("requestedPickupDate")),
      requestedDeliveryDate: orNull(formData.get("requestedDeliveryDate")),
      notes: orNull(formData.get("notes")),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not save these changes", error);
  }
  revalidatePath(detailPath(tenantSlug, requestId));
  return OK;
}

export async function submitCustomerQuoteRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  idempotencyKey: string,
  _prevState: CustomerQuoteRequestActionState,
  _formData: FormData,
): Promise<CustomerQuoteRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitCustomerQuoteRequest(supabase, { requestId, expectedVersion, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not submit this quote request", error);
  }
  revalidatePath(detailPath(tenantSlug, requestId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function cancelCustomerQuoteRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  _prevState: CustomerQuoteRequestActionState,
  formData: FormData,
): Promise<CustomerQuoteRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = orNull(formData.get("reason"));
  if (!reason) return { error: "A reason is required to cancel a quote request." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelCustomerQuoteRequest(supabase, { requestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not cancel this quote request", error);
  }
  revalidatePath(detailPath(tenantSlug, requestId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

/**
 * Uploads one attachment's metadata against an existing draft. Re-checks the
 * request through the anti-enumerating getCustomerQuoteRequest (RLS-scoped
 * client) FIRST -- this is the real per-record authorization decision (does
 * this identity's own account scope include this exact request, and is it
 * still a draft) -- before ever reaching the service-role-mediated upload
 * (design decision 4(b) of the migration: app.check_file_action_authority's
 * own widening only proves "a standing customer_user of this tenant," never
 * "owns this specific request").
 */
export async function uploadCustomerQuoteRequestAttachmentAction(
  tenantSlug: string,
  requestId: string,
  idempotencyKey: string,
  _prevState: CustomerQuoteRequestActionState,
  formData: FormData,
): Promise<CustomerQuoteRequestActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const originalFilename = orNull(formData.get("originalFilename"));
  const mimeType = orNull(formData.get("mimeType"));
  const sizeBytes = Number(formData.get("sizeBytes") ?? 0);
  if (!originalFilename || !mimeType || !(sizeBytes > 0)) {
    return { error: "Choose a file to attach." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const request = await getCustomerQuoteRequest(supabase, access.tenant.id, requestId, access.authUserId);
    if (request.status !== "draft") {
      return { error: "Attachments can only be added while a quote request is still a draft." };
    }

    const serviceRole = createSupabaseServiceRoleClient();
    await uploadCustomerQuoteRequestAttachment(serviceRole, {
      tenantId: access.tenant.id,
      requestId,
      originalFilename,
      mimeType,
      sizeBytes,
      // Tier C fix (spec-compliance): stable, per-render key bound from
      // page.tsx (see createCustomerQuoteRequestDraftAction's own identical
      // fix and rationale) -- a `revalidatePath` after a successful upload
      // re-renders the detail page and mints a fresh key for the NEXT
      // attachment, while a retry of the SAME upload attempt (before that
      // re-render) reuses the same key.
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CustomerQuoteRequestQueryError) {
      return { error: "This quote request is no longer available." };
    }
    return errorMessage("Could not attach this file", error);
  }
  revalidatePath(detailPath(tenantSlug, requestId));
  return OK;
}
