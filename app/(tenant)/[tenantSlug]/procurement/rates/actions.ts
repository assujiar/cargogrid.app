"use server";

/**
 * Vendor Rate and Pricelist Server Actions (PRC-255, CG-S11-PRC-006). Extends
 * app/(tenant)/[tenantSlug]/commercial/rates/actions.ts's own exact shape (resolve
 * portal access, call the typed mutation wrapper, translate a known mutation error
 * into a plain-language message, revalidate). Uses the Procurement guard
 * (`resolveProcurementAccessForRequest`), not the Commercial one -- these actions are
 * reached from the Procurement workspace and link a rate to a real Procurement
 * vendor identity (ADR-0020).
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createProcurementRateVersion, addVendorRateTier, removeVendorRateTier, calculateVendorRate, ProcurementRateMutationError } from "../../../../../server/mutations/procurement-rate.ts";

export interface ProcurementRateActionState {
  readonly error: string | null;
}

export interface CalculatePreviewState {
  readonly error: string | null;
  readonly result: {
    readonly computedAmount: number;
    readonly currency: string;
    readonly matchedTierId: string | null;
    readonly minimumAmountApplied: boolean;
  } | null;
}

const OK: ProcurementRateActionState = { error: null };

export async function createProcurementRateVersionAction(tenantSlug: string, _prevState: ProcurementRateActionState, formData: FormData): Promise<ProcurementRateActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Procurement workspace." };
  }

  const vendorCode = String(formData.get("vendorCode") ?? "").trim();
  const vendorName = String(formData.get("vendorName") ?? "").trim();
  const serviceType = String(formData.get("serviceType") ?? "").trim();
  const originLane = String(formData.get("originLane") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const baseAmount = Number(formData.get("baseAmount") ?? "");
  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  const leadTimeDaysRaw = String(formData.get("leadTimeDays") ?? "").trim();
  const capacityTerms = String(formData.get("capacityTerms") ?? "").trim();

  if (!vendorCode || !vendorName || !serviceType || !originLane || !destinationLane) {
    return { error: "Vendor code, vendor name, service type, and both lane fields are required." };
  }
  if (!Number.isFinite(baseAmount) || baseAmount < 0) {
    return { error: "A non-negative base amount is required." };
  }

  const supabase = await createSupabaseServerClient();
  let rateVersionId: string;
  try {
    const version = await createProcurementRateVersion(supabase, {
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
      vendorMasterId: vendorMasterId.length > 0 ? vendorMasterId : null,
      leadTimeDays: leadTimeDaysRaw.length > 0 ? Number(leadTimeDaysRaw) : null,
      capacityTerms: capacityTerms.length > 0 ? capacityTerms : null,
    });
    rateVersionId = version.id;
  } catch (error) {
    if (error instanceof ProcurementRateMutationError) {
      return { error: `Could not create rate version: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/rates`);
  redirect(`/${tenantSlug}/procurement/rates/${rateVersionId}`);
}

export async function addVendorRateTierAction(tenantSlug: string, rateVersionId: string, _prevState: ProcurementRateActionState, formData: FormData): Promise<ProcurementRateActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Procurement workspace." };
  }

  const tierOrder = Number(formData.get("tierOrder") ?? "");
  const weightMinRaw = String(formData.get("weightMin") ?? "").trim();
  const weightMaxRaw = String(formData.get("weightMax") ?? "").trim();
  const volumeMinRaw = String(formData.get("volumeMin") ?? "").trim();
  const volumeMaxRaw = String(formData.get("volumeMax") ?? "").trim();
  const amount = Number(formData.get("amount") ?? "");
  const minimumChargeRaw = String(formData.get("minimumCharge") ?? "").trim();

  if (!Number.isInteger(tierOrder) || tierOrder <= 0) {
    return { error: "Tier order must be a positive integer." };
  }
  if (!Number.isFinite(amount) || amount < 0) {
    return { error: "A non-negative tier amount is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addVendorRateTier(supabase, {
      rateVersionId,
      tierOrder,
      weightMin: weightMinRaw.length > 0 ? Number(weightMinRaw) : null,
      weightMax: weightMaxRaw.length > 0 ? Number(weightMaxRaw) : null,
      volumeMin: volumeMinRaw.length > 0 ? Number(volumeMinRaw) : null,
      volumeMax: volumeMaxRaw.length > 0 ? Number(volumeMaxRaw) : null,
      amount,
      minimumCharge: minimumChargeRaw.length > 0 ? Number(minimumChargeRaw) : null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ProcurementRateMutationError) {
      return { error: `Could not add tier: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/rates/${rateVersionId}`);
  return OK;
}

export async function removeVendorRateTierAction(tenantSlug: string, rateVersionId: string, _prevState: ProcurementRateActionState, formData: FormData): Promise<ProcurementRateActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Procurement workspace." };
  }

  const tierId = String(formData.get("tierId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? "");
  if (!tierId || !Number.isInteger(expectedVersion) || expectedVersion <= 0) {
    return { error: "A valid tier id and version are required to remove a tier." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await removeVendorRateTier(supabase, { tierId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProcurementRateMutationError) {
      return { error: `Could not remove tier: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/rates/${rateVersionId}`);
  return OK;
}

export async function calculateVendorRatePreviewAction(tenantSlug: string, rateVersionId: string, _prevState: CalculatePreviewState, formData: FormData): Promise<CalculatePreviewState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Procurement workspace.", result: null };
  }

  const weightRaw = String(formData.get("weight") ?? "").trim();
  const volumeRaw = String(formData.get("volume") ?? "").trim();
  const quantityRaw = String(formData.get("quantity") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    const result = await calculateVendorRate(supabase, {
      rateVersionId,
      weight: weightRaw.length > 0 ? Number(weightRaw) : null,
      volume: volumeRaw.length > 0 ? Number(volumeRaw) : null,
      quantity: quantityRaw.length > 0 ? Number(quantityRaw) : null,
      actorAuthUserId: access.authUserId,
    });
    return {
      error: null,
      result: {
        computedAmount: result.computedAmount,
        currency: result.currency,
        matchedTierId: result.matchedTierId,
        minimumAmountApplied: result.minimumAmountApplied,
      },
    };
  } catch (error) {
    if (error instanceof ProcurementRateMutationError) {
      return { error: `Could not calculate rate: ${error.message}`, result: null };
    }
    throw error;
  }
}
