"use server";

/**
 * Period Lock and Governed Reopen Server Actions (FIN-207, CG-S9-FIN-018).
 * Uses the RLS-scoped `authenticated` client -- every mutation is granted
 * directly to `authenticated` and performs its own FIN:Edit/FIN:Approve
 * authority check in-body, the same convention every prior capability's
 * own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  lockFinancePeriod,
  requestFinancePeriodReopen,
  approveFinancePeriodReopen,
  relockFinancePeriod,
  PeriodLockMutationError,
} from "../../../../../server/mutations/period-lock.ts";
import type { FinancePeriodLockScope } from "../../../../../server/contracts/period-lock/period-lock.ts";

export interface FinancePeriodLockFormState {
  readonly error: string | null;
}

const VALID_SCOPES: readonly FinancePeriodLockScope[] = ["all", "gl", "ar", "ap", "tax"];

export async function lockFinancePeriodAction(
  tenantSlug: string,
  _prevState: FinancePeriodLockFormState,
  formData: FormData,
): Promise<FinancePeriodLockFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const periodId = String(formData.get("periodId") ?? "").trim();
  const lockScope = String(formData.get("lockScope") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const evidenceRef = String(formData.get("evidenceRef") ?? "").trim();

  if (!periodId) {
    return { error: "A fiscal period ID is required." };
  }
  if (!VALID_SCOPES.includes(lockScope as FinancePeriodLockScope)) {
    return { error: `Lock scope must be one of: ${VALID_SCOPES.join(", ")}.` };
  }
  if (!reason) {
    return { error: "A reason is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await lockFinancePeriod(supabase, {
      tenantId: access.tenant.id,
      periodId,
      lockScope: lockScope as FinancePeriodLockScope,
      reason,
      evidenceRef: evidenceRef.length > 0 ? evidenceRef : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PeriodLockMutationError) {
      return { error: `Could not lock period: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/period-locks`);
  return { error: null };
}

export async function requestFinancePeriodReopenAction(
  tenantSlug: string,
  lockId: string,
  expectedVersion: number,
  _prevState: FinancePeriodLockFormState,
  formData: FormData,
): Promise<FinancePeriodLockFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A reason is required to request a reopen." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestFinancePeriodReopen(supabase, { lockId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PeriodLockMutationError) {
      return { error: `Could not request reopen: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/period-locks`);
  return { error: null };
}

export async function approveFinancePeriodReopenAction(
  tenantSlug: string,
  lockId: string,
  expectedVersion: number,
  _prevState: FinancePeriodLockFormState,
  formData: FormData,
): Promise<FinancePeriodLockFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const windowHours = Number(formData.get("windowHours") ?? "");
  if (!Number.isFinite(windowHours) || windowHours <= 0) {
    return { error: "A positive reopen window (hours) is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinancePeriodReopen(supabase, { lockId, expectedVersion, windowHours, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PeriodLockMutationError) {
      return { error: `Could not approve reopen: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/period-locks`);
  return { error: null };
}

export async function relockFinancePeriodAction(
  tenantSlug: string,
  lockId: string,
  expectedVersion: number,
  _prevState: FinancePeriodLockFormState,
  _formData: FormData,
): Promise<FinancePeriodLockFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await relockFinancePeriod(supabase, { lockId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PeriodLockMutationError) {
      return { error: `Could not re-lock period: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/period-locks`);
  return { error: null };
}
