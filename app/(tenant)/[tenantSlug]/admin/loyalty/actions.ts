"use server";

/**
 * Loyalty Program and Earning admin Server Actions (CPL-316, CG-S13-CPL-018).
 * Uses the RLS-scoped `authenticated` client -- every RPC below is granted
 * directly to `authenticated` and performs its own LYL:Create/Edit/Configure
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses (e.g. app/(tenant)/[tenantSlug]/finance/config/actions.ts).
 * Gated by resolveTenantAdminAccessForRequest (a coarse tenant_admin
 * portal-entry check) -- the real, per-action LYL:* authority is enforced by
 * each RPC itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  createLoyaltyProgram,
  updateLoyaltyProgramStatus,
  createLoyaltyProgramRuleVersion,
  updateLoyaltyProgramRuleVersionDraft,
  publishLoyaltyProgramRuleVersion,
  enrollCustomerLoyaltyAccount,
  setLoyaltyAccountStatus,
  evaluateCustomerLoyaltyEarningForPaidInvoice,
  reverseLoyaltyEarningEvent,
  LoyaltyProgramMutationError,
} from "../../../../../server/mutations/customer-portal-loyalty-program.ts";
import type { LoyaltyProgramStatus, LoyaltyRewardType, LoyaltyAccountStatus } from "../../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";

export interface LoyaltyAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyAdminFormState = { error: null };

function pathFor(tenantSlug: string, programId?: string): string {
  return programId ? `/${tenantSlug}/admin/loyalty?programId=${programId}` : `/${tenantSlug}/admin/loyalty`;
}

export async function createLoyaltyProgramAction(tenantSlug: string, _prevState: LoyaltyAdminFormState, formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  if (name.length === 0) return { error: "A program name is required." };

  const supabase = await createSupabaseServerClient();
  let programId: string;
  try {
    const program = await createLoyaltyProgram(supabase, { tenantId: access.tenant.id, name, description: description.length > 0 ? description : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    programId = program.id;
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not create program: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug));
  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function updateLoyaltyProgramStatusAction(
  tenantSlug: string,
  programId: string,
  expectedVersion: number,
  newStatus: LoyaltyProgramStatus,
  _prevState: LoyaltyAdminFormState,
  _formData: FormData,
): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await updateLoyaltyProgramStatus(supabase, { tenantId: access.tenant.id, programId, expectedVersion, newStatus, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not update program status: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function createLoyaltyProgramRuleVersionAction(tenantSlug: string, programId: string, _prevState: LoyaltyAdminFormState, formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const earningBasis = String(formData.get("earningBasis") ?? "").trim();
  const rewardType = String(formData.get("rewardType") ?? "") as LoyaltyRewardType;
  const rate = Number(formData.get("rate"));
  const minInvoiceAmountRaw = String(formData.get("minInvoiceAmount") ?? "").trim();
  if (!Number.isFinite(rate) || rate <= 0) return { error: "Rate must be a positive number." };
  const eligibilityConfig: Record<string, unknown> = {};
  if (minInvoiceAmountRaw.length > 0) {
    const minInvoiceAmount = Number(minInvoiceAmountRaw);
    if (!Number.isFinite(minInvoiceAmount) || minInvoiceAmount < 0) return { error: "Minimum invoice amount must be a non-negative number." };
    eligibilityConfig.min_invoice_amount = minInvoiceAmount;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createLoyaltyProgramRuleVersion(supabase, { tenantId: access.tenant.id, programId, earningBasis, rewardType, rate, eligibilityConfig, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not create a draft rule version: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function updateLoyaltyProgramRuleVersionDraftAction(
  tenantSlug: string,
  programId: string,
  ruleVersionId: string,
  expectedVersion: number,
  _prevState: LoyaltyAdminFormState,
  formData: FormData,
): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const earningBasis = String(formData.get("earningBasis") ?? "").trim();
  const rewardType = String(formData.get("rewardType") ?? "") as LoyaltyRewardType;
  const rate = Number(formData.get("rate"));
  const minInvoiceAmountRaw = String(formData.get("minInvoiceAmount") ?? "").trim();
  if (!Number.isFinite(rate) || rate <= 0) return { error: "Rate must be a positive number." };
  const eligibilityConfig: Record<string, unknown> = {};
  if (minInvoiceAmountRaw.length > 0) {
    const minInvoiceAmount = Number(minInvoiceAmountRaw);
    if (!Number.isFinite(minInvoiceAmount) || minInvoiceAmount < 0) return { error: "Minimum invoice amount must be a non-negative number." };
    eligibilityConfig.min_invoice_amount = minInvoiceAmount;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateLoyaltyProgramRuleVersionDraft(supabase, {
      tenantId: access.tenant.id,
      ruleVersionId,
      expectedVersion,
      earningBasis,
      rewardType,
      rate,
      eligibilityConfig,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not save the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function publishLoyaltyProgramRuleVersionAction(tenantSlug: string, programId: string, ruleVersionId: string, expectedVersion: number, _prevState: LoyaltyAdminFormState, _formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await publishLoyaltyProgramRuleVersion(supabase, { tenantId: access.tenant.id, ruleVersionId, expectedVersion, effectiveFrom: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not publish: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function enrollCustomerLoyaltyAccountAction(tenantSlug: string, programId: string, _prevState: LoyaltyAdminFormState, formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const customerAccountId = String(formData.get("customerAccountId") ?? "").trim();
  if (customerAccountId.length === 0) return { error: "A customer account ID is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await enrollCustomerLoyaltyAccount(supabase, { tenantId: access.tenant.id, customerAccountId, programId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not enroll this account: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function setLoyaltyAccountStatusAction(
  tenantSlug: string,
  programId: string,
  accountId: string,
  expectedVersion: number,
  newStatus: LoyaltyAccountStatus,
  _prevState: LoyaltyAdminFormState,
  formData: FormData,
): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  if (newStatus !== "active" && reason.length === 0) return { error: "A reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await setLoyaltyAccountStatus(supabase, { tenantId: access.tenant.id, accountId, expectedVersion, newStatus, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not update this account: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function evaluateCustomerLoyaltyEarningForPaidInvoiceAction(tenantSlug: string, programId: string, _prevState: LoyaltyAdminFormState, formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const arOpenItemId = String(formData.get("arOpenItemId") ?? "").trim();
  if (arOpenItemId.length === 0) return { error: "An AR open item ID is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await evaluateCustomerLoyaltyEarningForPaidInvoice(supabase, { tenantId: access.tenant.id, arOpenItemId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not evaluate earning: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

/** Idempotency key is derived deterministically server-side (never client-Date.now()-based), mirroring the RPC's own evaluate-side discipline. */
export async function reverseLoyaltyEarningEventAction(tenantSlug: string, programId: string, eventId: string, _prevState: LoyaltyAdminFormState, formData: FormData): Promise<LoyaltyAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) return { error: "A reason is required to reverse an earning event." };

  const supabase = await createSupabaseServerClient();
  try {
    await reverseLoyaltyEarningEvent(supabase, { tenantId: access.tenant.id, eventId, reason, idempotencyKey: `reversal:${eventId}`, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyProgramMutationError) return { error: `Could not reverse this event: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}
