"use server";

/**
 * Vendor Rate Server Actions (COM-149, CG-S7-COM-008). Uses the RLS-scoped
 * `authenticated` client -- app.create_rate_version is granted directly to
 * `authenticated` and performs its own app.is_support_grant_authority entitlement check
 * in-body, the same convention every prior Commercial capability's actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createRateVersion, RateMutationError } from "../../../../../server/mutations/rate.ts";

export interface RateFormState {
  readonly error: string | null;
}

export async function createRateVersionAction(tenantSlug: string, _prevState: RateFormState, formData: FormData): Promise<RateFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const vendorCode = String(formData.get("vendorCode") ?? "").trim();
  const vendorName = String(formData.get("vendorName") ?? "").trim();
  const serviceType = String(formData.get("serviceType") ?? "").trim();
  const originLane = String(formData.get("originLane") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const baseAmount = Number(formData.get("baseAmount") ?? "");

  if (!vendorCode || !vendorName || !serviceType || !originLane || !destinationLane) {
    return { error: "Vendor code, vendor name, service type, and both lane fields are required." };
  }
  if (!Number.isFinite(baseAmount) || baseAmount < 0) {
    return { error: "A non-negative base amount is required." };
  }

  const supabase = await createSupabaseServerClient();
  let rateVersionId: string;
  try {
    const version = await createRateVersion(supabase, {
      tenantId: access.tenant.id,
      vendorCode,
      vendorName,
      serviceType,
      originLane,
      destinationLane,
      currency,
      baseAmount,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    rateVersionId = version.id;
  } catch (error) {
    if (error instanceof RateMutationError) {
      return { error: `Could not create rate version: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/rates`);
  redirect(`/${tenantSlug}/commercial/rates/${rateVersionId}`);
}
