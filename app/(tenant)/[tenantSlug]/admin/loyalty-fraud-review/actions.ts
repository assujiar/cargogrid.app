"use server";

/**
 * Fraud review-case workbench Server Actions (CPL-322, CG-S13-CPL-024).
 * Uses the RLS-scoped `authenticated` client -- every RPC below is granted
 * directly to `authenticated` and performs its own LYL:Configure/Edit
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses. Gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check) -- the real, per-action LYL:* authority
 * is enforced by each RPC itself, not by this guard.
 */

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  openLoyaltyFraudReviewCase,
  claimLoyaltyFraudReviewCase,
  decideLoyaltyFraudReviewCase,
  suppressLoyaltyFraudReview,
  revokeLoyaltyFraudReviewSuppression,
  LoyaltyExpiryFraudMutationError,
} from "../../../../../server/mutations/customer-portal-loyalty-expiry-fraud.ts";
import type { LoyaltyFraudRiskSignalType } from "../../../../../server/contracts/customer-portal-loyalty-expiry-fraud/customer-portal-loyalty-expiry-fraud.ts";

export interface LoyaltyFraudReviewAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyFraudReviewAdminFormState = { error: null };

function readText(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}

export async function openLoyaltyFraudReviewCaseAction(tenantSlug: string, _prevState: LoyaltyFraudReviewAdminFormState, formData: FormData): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const loyaltyAccountId = readText(formData, "loyaltyAccountId");
  const riskSignalType = readText(formData, "riskSignalType") as LoyaltyFraudRiskSignalType;
  const riskSignalDetail = readText(formData, "riskSignalDetail");
  if (!loyaltyAccountId) return { error: "A loyalty account id is required." };
  if (!riskSignalDetail) return { error: "A non-empty internal risk signal detail is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await openLoyaltyFraudReviewCase(supabase, {
      tenantId: access.tenant.id,
      loyaltyAccountId,
      riskSignalType,
      riskSignalDetail,
      idempotencyKey: randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not open a fraud review case: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}

export async function claimLoyaltyFraudReviewCaseAction(tenantSlug: string, caseId: string, expectedVersion: number, _prevState: LoyaltyFraudReviewAdminFormState, _formData: FormData): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await claimLoyaltyFraudReviewCase(supabase, { tenantId: access.tenant.id, caseId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not claim this case: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}

export async function confirmLoyaltyFraudReviewCaseAction(tenantSlug: string, caseId: string, expectedVersion: number, _prevState: LoyaltyFraudReviewAdminFormState, formData: FormData): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reviewReason = readText(formData, "reviewReason");
  if (!reviewReason) return { error: "A review reason is required to confirm this case." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLoyaltyFraudReviewCase(supabase, { tenantId: access.tenant.id, caseId, expectedVersion, decision: "confirm", reviewReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not confirm this case: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}

export async function clearLoyaltyFraudReviewCaseAction(tenantSlug: string, caseId: string, expectedVersion: number, _prevState: LoyaltyFraudReviewAdminFormState, formData: FormData): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reviewReason = readText(formData, "reviewReason");
  if (!reviewReason) return { error: "A review reason is required to clear this case." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLoyaltyFraudReviewCase(supabase, { tenantId: access.tenant.id, caseId, expectedVersion, decision: "clear", reviewReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not clear this case: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}

export async function suppressLoyaltyFraudReviewAction(tenantSlug: string, _prevState: LoyaltyFraudReviewAdminFormState, formData: FormData): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const loyaltyAccountId = readText(formData, "loyaltyAccountId");
  const reason = readText(formData, "reason");
  const days = Number(readText(formData, "days") || "7");
  if (!loyaltyAccountId) return { error: "A loyalty account id is required." };
  if (!reason) return { error: "A reason is required to suppress fraud review for this account." };
  if (!Number.isFinite(days) || days <= 0) return { error: "Days must be a positive number." };

  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();

  const supabase = await createSupabaseServerClient();
  try {
    await suppressLoyaltyFraudReview(supabase, { tenantId: access.tenant.id, loyaltyAccountId, reason, expiresAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not suppress fraud review for this account: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}

export async function revokeLoyaltyFraudReviewSuppressionAction(
  tenantSlug: string,
  suppressionId: string,
  expectedVersion: number,
  _prevState: LoyaltyFraudReviewAdminFormState,
  formData: FormData,
): Promise<LoyaltyFraudReviewAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = readText(formData, "reason") || null;

  const supabase = await createSupabaseServerClient();
  try {
    await revokeLoyaltyFraudReviewSuppression(supabase, { tenantId: access.tenant.id, suppressionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not revoke this suppression: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-fraud-review`);
  return INITIAL_STATE;
}
