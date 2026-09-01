"use server";

/**
 * Customer Profile Server Actions (CPL-314, CG-S13-CPL-016). Mirrors
 * app/(tenant)/[tenantSlug]/customer-quotes/actions.ts's own shape -- resolve
 * the portal guard first, forward to the typed mutation wrapper, classify the
 * error into a form-safe message, revalidate the affected route. Every write
 * is scope-gated at the RPC layer itself (app.resolve_customer_account_scope)
 * -- this file never re-derives or trusts a client-supplied account id, it
 * only forwards.
 *
 * decideCustomerProfileChangeRequest/decideCustomerLegalIdentityChangeRequest/
 * decideCustomerContactChangeRequest (all staff COM:Approve decisions) are
 * deliberately NOT wired to any action here -- this route is customer-facing
 * only. Staff decide from the internal staff review workspace instead
 * (app/(tenant)/[tenantSlug]/admin/customer-profile-review/, ISS-2026-123).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { submitCustomerProfileChangeRequest, withdrawCustomerProfileChangeRequest, CustomerPortalProfileMutationError } from "../../../../server/mutations/customer-portal-profile.ts";
import type { CustomerProfileWritableField } from "../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";
import {
  submitCustomerLegalIdentityChangeRequest,
  withdrawCustomerLegalIdentityChangeRequest,
  CustomerPortalLegalIdentityMutationError,
} from "../../../../server/mutations/customer-portal-legal-identity.ts";
import type { CustomerLegalIdentityWritableField } from "../../../../server/contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";
import {
  submitCustomerContactChangeRequest,
  withdrawCustomerContactChangeRequest,
  CustomerPortalContactChangeMutationError,
} from "../../../../server/mutations/customer-portal-contact-change.ts";
import type { CustomerContactChangeKind, CustomerContactRole } from "../../../../server/contracts/customer-portal-contact-change/customer-portal-contact-change.ts";

export interface CustomerProfileActionState {
  readonly error: string | null;
}

const OK: CustomerProfileActionState = { error: null };
const NO_ACCESS: CustomerProfileActionState = { error: "You don't have access to this organization's customer portal." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function profilePath(tenantSlug: string, accountId: string): string {
  return `/${tenantSlug}/customer-profile?accountId=${accountId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerProfileActionState {
  if (error instanceof CustomerPortalProfileMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

function orNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

function readBillingAddress(formData: FormData): Record<string, string> {
  const value: Record<string, string> = {};
  const line1 = orNull(formData.get("billingLine1"));
  const line2 = orNull(formData.get("billingLine2"));
  const city = orNull(formData.get("billingCity"));
  const state = orNull(formData.get("billingState"));
  const postalCode = orNull(formData.get("billingPostalCode"));
  const country = orNull(formData.get("billingCountry"));
  if (line1) value.line1 = line1;
  if (line2) value.line2 = line2;
  if (city) value.city = city;
  if (state) value.state = state;
  if (postalCode) value.postalCode = postalCode;
  if (country) value.country = country;
  return value;
}

export async function submitCustomerProfileChangeRequestAction(
  tenantSlug: string,
  accountId: string,
  fieldName: CustomerProfileWritableField,
  idempotencyKey: string,
  _prevState: CustomerProfileActionState,
  formData: FormData,
): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const proposedValue = fieldName === "trade_name" ? orNull(formData.get("tradeName")) : readBillingAddress(formData);
  if (fieldName === "trade_name" && !proposedValue) {
    return { error: "Enter a trade name to propose." };
  }
  if (fieldName === "billing_address" && Object.keys(proposedValue as Record<string, string>).length === 0) {
    return { error: "Enter at least one billing address field to propose." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitCustomerProfileChangeRequest(supabase, {
      tenantId: access.tenant.id,
      accountId,
      fieldName,
      // Tier C fix (spec-compliance): idempotencyKey is generated ONCE per
      // Server Component render (page.tsx's own randomUUID() calls) and
      // bound into this action's closure -- never regenerated inside the
      // action body, so a genuine retry of the SAME rendered form reuses
      // the SAME key. Mirrors createCustomerQuoteRequestDraftAction's own
      // established fix exactly.
      idempotencyKey,
      proposedValue: (proposedValue ?? "") as string | Record<string, string>,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not submit this change request", error);
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}

export async function withdrawCustomerProfileChangeRequestAction(tenantSlug: string, _prevState: CustomerProfileActionState, formData: FormData): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requestId = orNull(formData.get("requestId"));
  const accountId = orNull(formData.get("accountId"));
  const expectedVersionRaw = orNull(formData.get("expectedVersion"));
  const expectedVersion = expectedVersionRaw ? Number(expectedVersionRaw) : NaN;
  if (!requestId || !accountId || !Number.isInteger(expectedVersion)) {
    return { error: "This change request could not be identified." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawCustomerProfileChangeRequest(supabase, {
      requestId,
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not withdraw this change request", error);
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}

// ===========================================================================
// ISS-2026-123 item 1 -- legal identity (legal_name/tax_id) change requests.
// A SEPARATE, higher-authority request path from the trade_name/billing_address
// one above -- never routed through submitCustomerProfileChangeRequestAction,
// which structurally rejects these two field names at the RPC layer.
// ===========================================================================

export async function submitCustomerLegalIdentityChangeRequestAction(
  tenantSlug: string,
  accountId: string,
  fieldName: CustomerLegalIdentityWritableField,
  idempotencyKey: string,
  _prevState: CustomerProfileActionState,
  formData: FormData,
): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const proposedValue = orNull(formData.get("proposedValue"));
  if (!proposedValue) {
    return { error: fieldName === "legal_name" ? "Enter the correct legal name to request." : "Enter the correct tax ID to request." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitCustomerLegalIdentityChangeRequest(supabase, {
      tenantId: access.tenant.id,
      accountId,
      fieldName,
      proposedValue,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CustomerPortalLegalIdentityMutationError) return { error: `Could not submit this correction request: ${error.message}` };
    throw error;
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}

export async function withdrawCustomerLegalIdentityChangeRequestAction(tenantSlug: string, _prevState: CustomerProfileActionState, formData: FormData): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requestId = orNull(formData.get("requestId"));
  const accountId = orNull(formData.get("accountId"));
  const expectedVersionRaw = orNull(formData.get("expectedVersion"));
  const expectedVersion = expectedVersionRaw ? Number(expectedVersionRaw) : NaN;
  if (!requestId || !accountId || !Number.isInteger(expectedVersion)) {
    return { error: "This correction request could not be identified." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawCustomerLegalIdentityChangeRequest(supabase, { requestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CustomerPortalLegalIdentityMutationError) return { error: `Could not withdraw this correction request: ${error.message}` };
    throw error;
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}

// ===========================================================================
// ISS-2026-123 item 2 -- contact add/update/remove change requests.
// ===========================================================================

export async function submitCustomerContactChangeRequestAction(
  tenantSlug: string,
  accountId: string,
  changeKind: CustomerContactChangeKind,
  targetContactId: string | null,
  idempotencyKey: string,
  _prevState: CustomerProfileActionState,
  formData: FormData,
): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const fullName = orNull(formData.get("fullName"));
  const title = orNull(formData.get("title"));
  const email = orNull(formData.get("email"));
  const phone = orNull(formData.get("phone"));
  const roleRaw = orNull(formData.get("role"));
  const role = (roleRaw as CustomerContactRole | null) ?? null;
  const isPrimaryRaw = formData.get("isPrimary");
  const isPrimary = isPrimaryRaw == null ? null : isPrimaryRaw === "true";

  if (changeKind === "add" && !fullName) {
    return { error: "Enter a full name to add a contact." };
  }
  if (changeKind === "add" && !email && !phone) {
    return { error: "Enter an email or phone number to add a contact." };
  }
  if (changeKind === "update" && !fullName && !title && !email && !phone && !role && isPrimary === null) {
    return { error: "Change at least one field to request a contact update." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitCustomerContactChangeRequest(supabase, {
      tenantId: access.tenant.id,
      accountId,
      changeKind,
      targetContactId,
      fullName,
      title,
      email,
      phone,
      role,
      isPrimary,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CustomerPortalContactChangeMutationError) {
      const verb = changeKind === "add" ? "add this contact" : changeKind === "remove" ? "remove this contact" : "update this contact";
      return { error: `Could not request to ${verb}: ${error.message}` };
    }
    throw error;
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}

export async function withdrawCustomerContactChangeRequestAction(tenantSlug: string, _prevState: CustomerProfileActionState, formData: FormData): Promise<CustomerProfileActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requestId = orNull(formData.get("requestId"));
  const accountId = orNull(formData.get("accountId"));
  const expectedVersionRaw = orNull(formData.get("expectedVersion"));
  const expectedVersion = expectedVersionRaw ? Number(expectedVersionRaw) : NaN;
  if (!requestId || !accountId || !Number.isInteger(expectedVersion)) {
    return { error: "This contact request could not be identified." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawCustomerContactChangeRequest(supabase, { requestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CustomerPortalContactChangeMutationError) return { error: `Could not withdraw this contact request: ${error.message}` };
    throw error;
  }
  revalidatePath(profilePath(tenantSlug, accountId));
  return OK;
}
