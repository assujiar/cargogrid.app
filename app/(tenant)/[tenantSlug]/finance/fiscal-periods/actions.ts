"use server";

/**
 * Fiscal Period Server Actions (FIN-193, CG-S9-FIN-004). Uses the RLS-scoped
 * `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  generateFinanceFiscalCalendar,
  acknowledgeFinancePeriodChecklistItem,
  softCloseFinancePeriod,
  closeFinancePeriod,
  reopenFinancePeriod,
  FiscalPeriodMutationError,
} from "../../../../../server/mutations/fiscal-period.ts";

export interface FiscalPeriodFormState {
  readonly error: string | null;
}

export async function generateFinanceFiscalCalendarAction(tenantSlug: string, _prevState: FiscalPeriodFormState, formData: FormData): Promise<FiscalPeriodFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const startDate = String(formData.get("startDate") ?? "").trim();
  const periodCount = Number(formData.get("periodCount") ?? "12");

  if (!code || !name || !startDate) {
    return { error: "Code, name, and start date are required." };
  }
  if (!Number.isInteger(periodCount) || periodCount < 1 || periodCount > 24) {
    return { error: "Period count must be between 1 and 24." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await generateFinanceFiscalCalendar(supabase, { tenantId: access.tenant.id, code, name, startDate, periodCount, actorAuthUserId: access.authUserId, createdBy: access.authUserId });
  } catch (error) {
    if (error instanceof FiscalPeriodMutationError) {
      return { error: `Could not generate calendar: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/fiscal-periods`);
  return { error: null };
}

export async function acknowledgeFinancePeriodChecklistItemAction(
  tenantSlug: string,
  periodId: string,
  itemKey: string,
  _prevState: FiscalPeriodFormState,
  formData: FormData,
): Promise<FiscalPeriodFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const satisfied = formData.get("satisfied") === "true";
  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgeFinancePeriodChecklistItem(supabase, { periodId, itemKey, satisfied, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FiscalPeriodMutationError) {
      return { error: `Could not update checklist item: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/fiscal-periods/${periodId}`);
  return { error: null };
}

export async function softCloseFinancePeriodAction(
  tenantSlug: string,
  periodId: string,
  expectedVersion: number,
  _prevState: FiscalPeriodFormState,
  _formData: FormData,
): Promise<FiscalPeriodFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await softCloseFinancePeriod(supabase, { periodId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FiscalPeriodMutationError) {
      return { error: `Could not soft-close: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/fiscal-periods`);
  revalidatePath(`/${tenantSlug}/finance/fiscal-periods/${periodId}`);
  return { error: null };
}

export async function closeFinancePeriodAction(
  tenantSlug: string,
  periodId: string,
  expectedVersion: number,
  _prevState: FiscalPeriodFormState,
  _formData: FormData,
): Promise<FiscalPeriodFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await closeFinancePeriod(supabase, { periodId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FiscalPeriodMutationError) {
      return { error: `Could not close: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/fiscal-periods`);
  revalidatePath(`/${tenantSlug}/finance/fiscal-periods/${periodId}`);
  return { error: null };
}

export async function reopenFinancePeriodAction(
  tenantSlug: string,
  periodId: string,
  expectedVersion: number,
  _prevState: FiscalPeriodFormState,
  formData: FormData,
): Promise<FiscalPeriodFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) {
    return { error: "A reason is required to reopen a closed period." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await reopenFinancePeriod(supabase, { periodId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FiscalPeriodMutationError) {
      return { error: `Could not reopen: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/fiscal-periods`);
  revalidatePath(`/${tenantSlug}/finance/fiscal-periods/${periodId}`);
  return { error: null };
}
