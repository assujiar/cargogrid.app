"use server";

/**
 * Reconciliation Server Actions (FIN-209, CG-S9-FIN-020). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly
 * to `authenticated` and performs its own FIN:Edit/FIN:Approve authority
 * check in-body, the same convention every prior capability's own
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  executeFinanceReconciliationRun,
  resolveFinanceReconciliationException,
  certifyFinanceReconciliationRun,
  ReconciliationMutationError,
} from "../../../../../server/mutations/reconciliation.ts";
import type { FinanceReconciliationScope } from "../../../../../server/contracts/reconciliation/reconciliation.ts";

export interface FinanceReconciliationFormState {
  readonly error: string | null;
}

export async function executeFinanceReconciliationRunAction(
  tenantSlug: string,
  _prevState: FinanceReconciliationFormState,
  formData: FormData,
): Promise<FinanceReconciliationFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const scope = String(formData.get("scope") ?? "").trim();
  const asOfDate = String(formData.get("asOfDate") ?? "").trim();
  const toleranceAmount = Number(formData.get("toleranceAmount") ?? "0");

  if (scope !== "ar" && scope !== "ap") {
    return { error: "Scope must be ar or ap." };
  }
  if (!asOfDate) {
    return { error: "An as-of date is required." };
  }
  if (!Number.isFinite(toleranceAmount) || toleranceAmount < 0) {
    return { error: "Tolerance must be a non-negative number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await executeFinanceReconciliationRun(supabase, {
      tenantId: access.tenant.id,
      scope: scope as FinanceReconciliationScope,
      asOfDate,
      toleranceAmount,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReconciliationMutationError) {
      return { error: `Could not execute reconciliation run: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/reconciliation`);
  return { error: null };
}

export async function resolveFinanceReconciliationExceptionAction(
  tenantSlug: string,
  exceptionId: string,
  expectedVersion: number,
  _prevState: FinanceReconciliationFormState,
  formData: FormData,
): Promise<FinanceReconciliationFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const resolutionReason = String(formData.get("resolutionReason") ?? "").trim();
  if (!resolutionReason) {
    return { error: "A resolution reason is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await resolveFinanceReconciliationException(supabase, { exceptionId, expectedVersion, resolutionReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ReconciliationMutationError) {
      return { error: `Could not resolve exception: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/reconciliation`);
  return { error: null };
}

export async function certifyFinanceReconciliationRunAction(
  tenantSlug: string,
  runId: string,
  expectedVersion: number,
  _prevState: FinanceReconciliationFormState,
  formData: FormData,
): Promise<FinanceReconciliationFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A certification reason is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await certifyFinanceReconciliationRun(supabase, { runId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ReconciliationMutationError) {
      return { error: `Could not certify run: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/reconciliation`);
  return { error: null };
}
