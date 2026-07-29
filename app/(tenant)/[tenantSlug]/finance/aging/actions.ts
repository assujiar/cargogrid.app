"use server";

/**
 * AR and AP Aging Server Actions (FIN-210, CG-S9-FIN-021). Uses the
 * RLS-scoped `authenticated` client -- the mutation is granted directly to
 * `authenticated` and performs its own FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts
 * uses. The report/summary themselves are read-only RPCs invoked directly
 * from the page component -- no server action needed for a read.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { setFinanceAgingBucketConfig, AgingMutationError } from "../../../../../server/mutations/aging.ts";
import type { FinanceAgingEntityType } from "../../../../../server/contracts/aging/aging.ts";

export interface FinanceAgingFormState {
  readonly error: string | null;
}

export async function setFinanceAgingBucketConfigAction(
  tenantSlug: string,
  _prevState: FinanceAgingFormState,
  formData: FormData,
): Promise<FinanceAgingFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const entityType = String(formData.get("entityType") ?? "").trim();
  const bucketsRaw = String(formData.get("bucketsJson") ?? "").trim();

  if (entityType !== "ar" && entityType !== "ap") {
    return { error: "Entity type must be ar or ap." };
  }
  if (!bucketsRaw) {
    return { error: "A buckets JSON array is required." };
  }

  let buckets: unknown;
  try {
    buckets = JSON.parse(bucketsRaw);
  } catch {
    return { error: "Buckets must be valid JSON, e.g. a comma-separated array of {\"label\":\"Current\",\"minDays\":-999999,\"maxDays\":0} objects." };
  }
  if (!Array.isArray(buckets)) {
    return { error: "Buckets must be a JSON array." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await setFinanceAgingBucketConfig(supabase, {
      tenantId: access.tenant.id,
      entityType: entityType as FinanceAgingEntityType,
      buckets: buckets as { label: string; minDays: number; maxDays: number | null }[],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof AgingMutationError) {
      return { error: `Could not set bucket configuration: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/aging`);
  return { error: null };
}
