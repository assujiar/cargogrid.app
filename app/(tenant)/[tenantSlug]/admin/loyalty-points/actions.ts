"use server";

/**
 * Points Ledger admin Server Actions (CPL-318, CG-S13-CPL-020). Uses the
 * RLS-scoped `authenticated` client -- every RPC below is granted directly
 * to `authenticated` and performs its own LYL:Edit/Configure authority check
 * in-body, the same convention every prior capability's own actions.ts uses
 * (e.g. app/(tenant)/[tenantSlug]/admin/loyalty/actions.ts). Gated by
 * resolveTenantAdminAccessForRequest (a coarse tenant_admin portal-entry
 * check) -- the real, per-action LYL:* authority is enforced by each RPC
 * itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  postLoyaltyPointsEarned,
  reverseLoyaltyPointsEarned,
  expireLoyaltyPointLots,
  requestLoyaltyPointAdjustment,
  decideLoyaltyPointAdjustment,
  LoyaltyPointsMutationError,
} from "../../../../../server/mutations/customer-portal-loyalty-points.ts";

export interface LoyaltyPointsAdminFormState {
  readonly error: string | null;
  readonly notice: string | null;
}

const INITIAL_STATE: LoyaltyPointsAdminFormState = { error: null, notice: null };

function pathFor(tenantSlug: string): string {
  return `/${tenantSlug}/admin/loyalty-points`;
}

export async function postLoyaltyPointsEarnedAction(tenantSlug: string, _prevState: LoyaltyPointsAdminFormState, formData: FormData): Promise<LoyaltyPointsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace.", notice: null };

  const earningEventId = String(formData.get("earningEventId") ?? "").trim();
  const expiryDaysRaw = String(formData.get("expiryDays") ?? "365").trim();
  const expiryDays = Number(expiryDaysRaw);
  if (earningEventId.length === 0) return { error: "An earning event ID is required.", notice: null };
  if (!Number.isFinite(expiryDays) || expiryDays < 1 || expiryDays > 3650) return { error: "Expiry window must be between 1 and 3650 days.", notice: null };

  const supabase = await createSupabaseServerClient();
  try {
    const entry = await postLoyaltyPointsEarned(supabase, { tenantId: access.tenant.id, earningEventId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, expiryDays });
    revalidatePath(pathFor(tenantSlug));
    return { error: null, notice: `Posted a ${entry.amount.toFixed(0)}-point earn entry.` };
  } catch (error) {
    if (error instanceof LoyaltyPointsMutationError) return { error: `Could not convert this earning event: ${error.message}`, notice: null };
    throw error;
  }
}

export async function reverseLoyaltyPointsEarnedAction(tenantSlug: string, _prevState: LoyaltyPointsAdminFormState, formData: FormData): Promise<LoyaltyPointsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace.", notice: null };

  const reversalEarningEventId = String(formData.get("reversalEarningEventId") ?? "").trim();
  if (reversalEarningEventId.length === 0) return { error: "A reversal earning event ID is required.", notice: null };

  const supabase = await createSupabaseServerClient();
  try {
    const entry = await reverseLoyaltyPointsEarned(supabase, { tenantId: access.tenant.id, reversalEarningEventId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    revalidatePath(pathFor(tenantSlug));
    return { error: null, notice: `Posted a ${entry.amount.toFixed(0)}-point reversal entry.` };
  } catch (error) {
    if (error instanceof LoyaltyPointsMutationError) return { error: `Could not reverse points for this event: ${error.message}`, notice: null };
    throw error;
  }
}

export async function expireLoyaltyPointLotsAction(tenantSlug: string, _prevState: LoyaltyPointsAdminFormState, _formData: FormData): Promise<LoyaltyPointsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace.", notice: null };

  const supabase = await createSupabaseServerClient();
  try {
    const entries = await expireLoyaltyPointLots(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    revalidatePath(pathFor(tenantSlug));
    return { error: null, notice: entries.length === 0 ? "No lots were due to expire." : `Expired ${entries.length} lot(s).` };
  } catch (error) {
    if (error instanceof LoyaltyPointsMutationError) return { error: `Could not run the expiry scan: ${error.message}`, notice: null };
    throw error;
  }
}

export async function requestLoyaltyPointAdjustmentAction(tenantSlug: string, _prevState: LoyaltyPointsAdminFormState, formData: FormData): Promise<LoyaltyPointsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace.", notice: null };

  const loyaltyAccountId = String(formData.get("loyaltyAccountId") ?? "").trim();
  const adjustmentAmount = Number(formData.get("adjustmentAmount"));
  const reason = String(formData.get("reason") ?? "").trim();
  if (loyaltyAccountId.length === 0) return { error: "A loyalty account is required.", notice: null };
  if (!Number.isFinite(adjustmentAmount) || adjustmentAmount === 0) return { error: "Adjustment amount must be a non-zero number.", notice: null };
  if (reason.length === 0) return { error: "A reason is required to request a point adjustment.", notice: null };

  const supabase = await createSupabaseServerClient();
  try {
    await requestLoyaltyPointAdjustment(supabase, { tenantId: access.tenant.id, loyaltyAccountId, adjustmentAmount, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyPointsMutationError) return { error: `Could not request this adjustment: ${error.message}`, notice: null };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug));
  return { error: null, notice: "Adjustment request submitted -- a different Loyalty Manager must decide it." };
}

export async function decideLoyaltyPointAdjustmentAction(tenantSlug: string, adjustmentId: string, expectedVersion: number, decision: "approved" | "rejected", _prevState: LoyaltyPointsAdminFormState, formData: FormData): Promise<LoyaltyPointsAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace.", notice: null };

  const decisionNotes = String(formData.get("decisionNotes") ?? "").trim();
  if (decisionNotes.length === 0) return { error: "Decision notes are required.", notice: null };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLoyaltyPointAdjustment(supabase, { tenantId: access.tenant.id, adjustmentId, expectedVersion, decision, decisionNotes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyPointsMutationError) return { error: `Could not decide this adjustment: ${error.message}`, notice: null };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug));
  return { error: null, notice: decision === "approved" ? "Adjustment approved and posted to the ledger." : "Adjustment rejected." };
}
