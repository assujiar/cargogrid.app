"use server";

/**
 * Job, Customer and Service Profitability Server Actions (FIN-212,
 * CG-S9-FIN-023). Uses the RLS-scoped `authenticated` client -- the
 * mutation is granted directly to `authenticated` and performs its own
 * FIN:Edit + FIN:View margin authority check in-body, the same convention
 * every prior capability's own actions.ts uses. The summary/detail reads
 * themselves are read-only RPCs invoked directly from the page component --
 * no server action needed for a read.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { calculateFinanceJobProfitability, ProfitabilityMutationError } from "../../../../../server/mutations/profitability.ts";
import type { FinanceJobProfitabilityFact } from "../../../../../server/contracts/profitability/profitability.ts";

export interface FinanceProfitabilityFormState {
  readonly error: string | null;
  readonly fact: FinanceJobProfitabilityFact | null;
}

export async function calculateFinanceJobProfitabilityAction(
  tenantSlug: string,
  _prevState: FinanceProfitabilityFormState,
  formData: FormData,
): Promise<FinanceProfitabilityFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", fact: null };
  }

  const jobOrderId = String(formData.get("jobOrderId") ?? "").trim();
  const recalculationReason = String(formData.get("recalculationReason") ?? "").trim();

  if (!jobOrderId) {
    return { error: "A Job Order id is required.", fact: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const fact = await calculateFinanceJobProfitability(supabase, {
      jobOrderId,
      recalculationReason: recalculationReason.length > 0 ? recalculationReason : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    revalidatePath(`/${tenantSlug}/finance/profitability`);
    return { error: null, fact };
  } catch (error) {
    if (error instanceof ProfitabilityMutationError) {
      return { error: `Could not calculate profitability: ${error.message}`, fact: null };
    }
    throw error;
  }
}
