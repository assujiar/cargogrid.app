"use server";

/**
 * Cashback, Discount and Voucher admin Server Actions (CPL-319,
 * CG-S13-CPL-021). Uses the RLS-scoped `authenticated` client -- every RPC
 * below is granted directly to `authenticated` and performs its own
 * LYL:Edit/Configure authority check in-body, the same convention every
 * prior capability's own actions.ts uses (e.g. app/(tenant)/[tenantSlug]/
 * admin/loyalty-points/actions.ts). Gated by resolveTenantAdminAccessForRequest
 * (a coarse tenant_admin portal-entry check) -- the real, per-action LYL:*
 * authority is enforced by each RPC itself, not by this guard.
 *
 * `p_idempotency_key` is required (non-nullable) on issuance -- generated
 * here, server-side, via `crypto.randomUUID()` (a real, cryptographically
 * random value, never `Date.now()`-based). A genuine double-click is
 * already prevented at the UI layer (the issue button disables itself while
 * `pending`); this key protects the database layer against any other
 * accidental duplicate RPC call for the SAME logical issuance action.
 */

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  issueLoyaltyBenefitEntitlement,
  reverseLoyaltyBenefitEntitlement,
  expireLoyaltyBenefitEntitlements,
  holdLoyaltyBenefitEntitlement,
  releaseLoyaltyBenefitEntitlementHold,
  LoyaltyBenefitsMutationError,
} from "../../../../../server/mutations/customer-portal-loyalty-benefits.ts";
import type { LoyaltyBenefitType } from "../../../../../server/contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";

export interface LoyaltyBenefitsAdminFormState {
  readonly error: string | null;
  readonly rawCode?: string | null;
}

const INITIAL_STATE: LoyaltyBenefitsAdminFormState = { error: null };

function pathFor(tenantSlug: string, programId?: string): string {
  return programId ? `/${tenantSlug}/admin/loyalty-benefits?programId=${programId}` : `/${tenantSlug}/admin/loyalty-benefits`;
}

export async function issueLoyaltyBenefitEntitlementAction(
  tenantSlug: string,
  programId: string,
  loyaltyAccountId: string,
  _prevState: LoyaltyBenefitsAdminFormState,
  formData: FormData,
): Promise<LoyaltyBenefitsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const benefitType = String(formData.get("benefitType") ?? "") as LoyaltyBenefitType;
  const valueAmount = Number(formData.get("valueAmount"));
  const valueCapRaw = String(formData.get("valueCap") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const sourceType = String(formData.get("sourceType") ?? "").trim();
  const expiresAtRaw = String(formData.get("expiresAt") ?? "").trim();

  if (!["cashback", "discount", "voucher"].includes(benefitType)) return { error: "Select a benefit type." };
  if (!Number.isFinite(valueAmount) || valueAmount <= 0) return { error: "Value amount must be greater than zero." };
  const valueCap = valueCapRaw.length > 0 ? Number(valueCapRaw) : null;
  if (valueCap !== null && (!Number.isFinite(valueCap) || valueCap <= 0)) return { error: "Value cap must be greater than zero when supplied." };
  if (valueCap !== null && valueAmount > valueCap) return { error: "Value amount cannot exceed the value cap." };
  if (!/^[A-Z]{3}$/.test(currency)) return { error: "Currency must be a 3-letter ISO code, e.g. USD." };
  if (sourceType.length === 0) return { error: "A source is required (e.g. manual, promotion)." };
  const expiresAt = expiresAtRaw.length > 0 ? new Date(expiresAtRaw).toISOString() : null;

  const supabase = await createSupabaseServerClient();
  try {
    const result = await issueLoyaltyBenefitEntitlement(supabase, {
      tenantId: access.tenant.id,
      loyaltyAccountId,
      benefitType,
      valueAmount,
      valueCap,
      currency,
      sourceType,
      sourceId: null,
      expiresAt,
      idempotencyKey: randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    revalidatePath(pathFor(tenantSlug, programId));
    return { error: null, rawCode: result.rawCode };
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not issue this benefit: ${error.message}` };
    throw error;
  }
}

export async function reverseLoyaltyBenefitEntitlementAction(
  tenantSlug: string,
  programId: string,
  entitlementId: string,
  expectedVersion: number,
  _prevState: LoyaltyBenefitsAdminFormState,
  formData: FormData,
): Promise<LoyaltyBenefitsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) return { error: "A reason is required to reverse a benefit." };

  const supabase = await createSupabaseServerClient();
  try {
    await reverseLoyaltyBenefitEntitlement(supabase, { tenantId: access.tenant.id, entitlementId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not reverse this benefit: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function expireLoyaltyBenefitEntitlementsAction(tenantSlug: string, programId: string, _prevState: LoyaltyBenefitsAdminFormState, _formData: FormData): Promise<LoyaltyBenefitsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await expireLoyaltyBenefitEntitlements(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not run the expiry scan: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function holdLoyaltyBenefitEntitlementAction(tenantSlug: string, programId: string, entitlementId: string, _prevState: LoyaltyBenefitsAdminFormState, formData: FormData): Promise<LoyaltyBenefitsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) return { error: "A reason is required to hold this benefit." };

  const supabase = await createSupabaseServerClient();
  try {
    await holdLoyaltyBenefitEntitlement(supabase, { tenantId: access.tenant.id, entitlementId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not hold this benefit: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function releaseLoyaltyBenefitEntitlementHoldAction(
  tenantSlug: string,
  programId: string,
  entitlementId: string,
  _prevState: LoyaltyBenefitsAdminFormState,
  _formData: FormData,
): Promise<LoyaltyBenefitsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await releaseLoyaltyBenefitEntitlementHold(supabase, { tenantId: access.tenant.id, entitlementId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not release this benefit's hold: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}
