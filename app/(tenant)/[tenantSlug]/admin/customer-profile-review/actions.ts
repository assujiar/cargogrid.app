"use server";

/**
 * Customer profile / legal identity / contact change-request review workbench Server Actions
 * (ISS-2026-123). Uses the RLS-scoped `authenticated` client -- every decide RPC below is
 * granted directly to `authenticated` and performs its own COM:Approve authority check (plus,
 * for the legal-identity and contact-change RPCs, a step-up-MFA check when the tenant has
 * configured one) in-body, the same convention every prior capability's own actions.ts uses.
 * Gated by resolveTenantAdminAccessForRequest (a coarse tenant_admin portal-entry check) -- the
 * real, per-action COM:Approve (and step-up-MFA) authority is enforced by each RPC itself, not
 * by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { decideCustomerProfileChangeRequest, CustomerPortalProfileMutationError } from "../../../../../server/mutations/customer-portal-profile.ts";
import { decideCustomerLegalIdentityChangeRequest, CustomerPortalLegalIdentityMutationError } from "../../../../../server/mutations/customer-portal-legal-identity.ts";
import { decideCustomerContactChangeRequest, CustomerPortalContactChangeMutationError } from "../../../../../server/mutations/customer-portal-contact-change.ts";
import type { CustomerProfileDecision } from "../../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";

export interface CustomerProfileReviewActionState {
  readonly error: string | null;
}

const OK: CustomerProfileReviewActionState = { error: null };

function reviewPath(tenantSlug: string): string {
  return `/${tenantSlug}/admin/customer-profile-review`;
}

function readText(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}

async function requireAccess(tenantSlug: string) {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

export async function decideProfileChangeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: CustomerProfileDecision,
  _prevState: CustomerProfileReviewActionState,
  formData: FormData,
): Promise<CustomerProfileReviewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's admin workspace." };

  const reviewReason = readText(formData, "reviewReason");
  if (!reviewReason) return { error: "A review reason is required to decide this request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideCustomerProfileChangeRequest(supabase, { requestId, expectedVersion, decision, reviewReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CustomerPortalProfileMutationError) return { error: `Could not decide this profile change request: ${error.message}` };
    throw error;
  }
  revalidatePath(reviewPath(tenantSlug));
  return OK;
}

export async function decideLegalIdentityChangeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: CustomerProfileDecision,
  _prevState: CustomerProfileReviewActionState,
  formData: FormData,
): Promise<CustomerProfileReviewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's admin workspace." };

  const reviewReason = readText(formData, "reviewReason");
  if (!reviewReason) return { error: "A review reason is required to decide this request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideCustomerLegalIdentityChangeRequest(supabase, { requestId, expectedVersion, decision, reviewReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CustomerPortalLegalIdentityMutationError) {
      const hint = error.code === "mfa_step_up_required" ? " This tenant requires a current step-up-MFA authorization for this decision -- complete a step-up challenge, then retry." : "";
      return { error: `Could not decide this legal identity change request: ${error.message}${hint}` };
    }
    throw error;
  }
  revalidatePath(reviewPath(tenantSlug));
  return OK;
}

export async function decideContactChangeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: CustomerProfileDecision,
  _prevState: CustomerProfileReviewActionState,
  formData: FormData,
): Promise<CustomerProfileReviewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's admin workspace." };

  const reviewReason = readText(formData, "reviewReason");
  if (!reviewReason) return { error: "A review reason is required to decide this request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideCustomerContactChangeRequest(supabase, { requestId, expectedVersion, decision, reviewReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CustomerPortalContactChangeMutationError) {
      const hint = error.code === "mfa_step_up_required" ? " This tenant requires a current step-up-MFA authorization for this decision -- complete a step-up challenge, then retry." : "";
      return { error: `Could not decide this contact change request: ${error.message}${hint}` };
    }
    throw error;
  }
  revalidatePath(reviewPath(tenantSlug));
  return OK;
}
