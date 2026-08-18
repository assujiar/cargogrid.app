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
 * decideCustomerProfileChangeRequest (the staff COM:Approve decision) is
 * deliberately NOT wired to any action here -- this route is customer-facing
 * only. Staff decide from the internal Commercial workspace, out of this
 * checkpoint's own bounded scope (no such internal review UI exists yet in
 * this repository for any Phase 8 request/intent table; disclosed as a
 * residual gap identical in kind to CPL-302's own quote-request conversion
 * boundary, which also has no dedicated internal UI).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { submitCustomerProfileChangeRequest, withdrawCustomerProfileChangeRequest, CustomerPortalProfileMutationError } from "../../../../server/mutations/customer-portal-profile.ts";
import type { CustomerProfileWritableField } from "../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";

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
