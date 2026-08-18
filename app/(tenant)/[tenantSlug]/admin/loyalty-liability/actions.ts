"use server";

/**
 * Liability Reconciliation Analytics admin Server Actions (CPL-323,
 * CG-S13-CPL-025). Uses the RLS-scoped `authenticated` client -- every RPC
 * here is granted directly to `authenticated` and performs its own LYL:*
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses. Gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check) -- the real authority is enforced by the
 * RPC itself.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { executeLoyaltyLiabilityReconciliationRun, resolveLoyaltyLiabilityReconciliationException, certifyLoyaltyLiabilityReconciliationRun, LoyaltyLiabilityMutationError } from "../../../../../server/mutations/customer-portal-loyalty-liability.ts";

export interface LoyaltyLiabilityAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyLiabilityAdminFormState = { error: null };

function readNullableText(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length === 0 ? null : raw;
}

export async function executeLoyaltyLiabilityReconciliationRunAction(tenantSlug: string, _prevState: LoyaltyLiabilityAdminFormState, formData: FormData): Promise<LoyaltyLiabilityAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) return { error: "Currency must be a 3-letter ISO code, e.g. USD." };

  const supabase = await createSupabaseServerClient();
  try {
    await executeLoyaltyLiabilityReconciliationRun(supabase, {
      tenantId: access.tenant.id,
      currency,
      asOf: readNullableText(formData, "asOf"),
      idempotencyKey: readNullableText(formData, "idempotencyKey"),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyLiabilityMutationError) return { error: `Could not run the reconciliation: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-liability`);
  return INITIAL_STATE;
}

export async function resolveLoyaltyLiabilityReconciliationExceptionAction(
  tenantSlug: string,
  exceptionId: string,
  expectedVersion: number,
  _prevState: LoyaltyLiabilityAdminFormState,
  formData: FormData,
): Promise<LoyaltyLiabilityAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const resolutionReason = String(formData.get("resolutionReason") ?? "").trim();
  if (resolutionReason.length === 0) return { error: "A resolution reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await resolveLoyaltyLiabilityReconciliationException(supabase, {
      tenantId: access.tenant.id,
      exceptionId,
      expectedVersion,
      resolutionReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyLiabilityMutationError) return { error: `Could not resolve the exception: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-liability`);
  return INITIAL_STATE;
}

export async function certifyLoyaltyLiabilityReconciliationRunAction(
  tenantSlug: string,
  runId: string,
  expectedVersion: number,
  _prevState: LoyaltyLiabilityAdminFormState,
  _formData: FormData,
): Promise<LoyaltyLiabilityAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await certifyLoyaltyLiabilityReconciliationRun(supabase, {
      tenantId: access.tenant.id,
      runId,
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyLiabilityMutationError) return { error: `Could not certify the run: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-liability`);
  return INITIAL_STATE;
}
