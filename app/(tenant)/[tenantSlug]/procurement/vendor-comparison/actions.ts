"use server";

/**
 * Vendor Comparison Server Actions (PRC-258, CG-S11-PRC-009). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/rfq/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known
 * mutation error into a plain-language message, revalidate) plus its own
 * bound-per-row-action convention (expectedVersion captured via `.bind()` at
 * render time, not a hidden form field) for the detail page's own
 * offer-level actions.
 *
 * Idempotency-key disclosure: identical to every other PRC-25x creation form
 * in this repository -- a fresh `crypto.randomUUID()` is generated here,
 * server-side, on every submit, not client-persisted. The RPC-level
 * idempotency guarantee itself is real and tested
 * (scripts/db-tests/procurement-vendor-comparison.sql).
 *
 * Criteria input disclosure: the create/revise forms accept criteria as a
 * raw JSON-array textarea (key/label/weight objects) rather than a
 * structured weight-editor widget -- no PRC-25x capability in this
 * repository has built a generic weighted-criteria editor yet, so a one-off
 * here would duplicate, not reuse, whatever that shared widget eventually
 * is (the same disclosed bound RFQ's own file-attachment id field already
 * established). The RPC's own validation (app._normalize_vendor_comparison_
 * criteria -- exactly one "price" entry, weights sum to 100) still runs
 * regardless of how the JSON reaches it.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorComparison,
  reviseVendorComparison,
  linkVendorComparisonOfferRate,
  setVendorComparisonOfferInclusion,
  scoreVendorComparisonOfferCriterion,
  recommendVendorComparisonOffer,
  submitVendorComparisonForApproval,
  cancelVendorComparison,
  VendorComparisonMutationError,
} from "../../../../../server/mutations/vendor-comparison.ts";
import type { ComparisonCriterion } from "../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";

export interface VendorComparisonActionState {
  readonly error: string | null;
}

const OK: VendorComparisonActionState = { error: null };
const NO_ACCESS: VendorComparisonActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, comparisonId: string): string {
  return `/${tenantSlug}/procurement/vendor-comparison/${comparisonId}`;
}

function parseCriteria(raw: FormDataEntryValue | null): ComparisonCriterion[] | null | { error: string } {
  const value = String(raw ?? "").trim();
  if (value.length === 0) return null;
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) return { error: "Criteria must be a JSON array." };
    return parsed as ComparisonCriterion[];
  } catch {
    return { error: "Criteria must be valid JSON, e.g. [{\"key\":\"price\",\"label\":\"Price\",\"weight\":70},{\"key\":\"service\",\"label\":\"Service\",\"weight\":30}]." };
  }
}

// --- Creation (redirect to the new detail page on success) ----------------

export async function createVendorComparisonAction(tenantSlug: string, _prevState: VendorComparisonActionState, formData: FormData): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const rfqId = String(formData.get("rfqId") ?? "").trim();
  const comparisonCurrency = String(formData.get("comparisonCurrency") ?? "").trim();
  if (!rfqId || !comparisonCurrency) {
    return { error: "A closed RFQ id and a comparison currency are required." };
  }
  const basisWeightRaw = String(formData.get("basisWeight") ?? "").trim();
  const basisVolumeRaw = String(formData.get("basisVolume") ?? "").trim();
  const basisQuantityRaw = String(formData.get("basisQuantity") ?? "").trim();
  const criteria = parseCriteria(formData.get("criteria"));
  if (criteria && "error" in criteria) {
    return { error: criteria.error };
  }

  const supabase = await createSupabaseServerClient();
  let comparisonId: string;
  try {
    const comparison = await createVendorComparison(supabase, {
      tenantId: access.tenant.id,
      rfqId,
      comparisonCurrency,
      basisWeight: basisWeightRaw.length > 0 ? Number(basisWeightRaw) : null,
      basisVolume: basisVolumeRaw.length > 0 ? Number(basisVolumeRaw) : null,
      basisQuantity: basisQuantityRaw.length > 0 ? Number(basisQuantityRaw) : null,
      criteria,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    comparisonId = comparison.id;
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not create the comparison: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendor-comparison`);
  redirect(detailPath(tenantSlug, comparisonId));
}

// --- Detail-page comparison-root actions (stay on the detail page) --------

export async function reviseVendorComparisonAction(
  tenantSlug: string,
  comparisonId: string,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to revise a comparison." };
  }
  const comparisonCurrency = String(formData.get("comparisonCurrency") ?? "").trim() || null;
  const basisWeightRaw = String(formData.get("basisWeight") ?? "").trim();
  const basisVolumeRaw = String(formData.get("basisVolume") ?? "").trim();
  const basisQuantityRaw = String(formData.get("basisQuantity") ?? "").trim();
  const criteria = parseCriteria(formData.get("criteria"));
  if (criteria && "error" in criteria) {
    return { error: criteria.error };
  }

  const supabase = await createSupabaseServerClient();
  let newComparisonId: string;
  try {
    const comparison = await reviseVendorComparison(supabase, {
      comparisonId,
      comparisonCurrency,
      basisWeight: basisWeightRaw.length > 0 ? Number(basisWeightRaw) : null,
      basisVolume: basisVolumeRaw.length > 0 ? Number(basisVolumeRaw) : null,
      basisQuantity: basisQuantityRaw.length > 0 ? Number(basisQuantityRaw) : null,
      criteria,
      reason,
      idempotencyKey: crypto.randomUUID(),
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newComparisonId = comparison.id;
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not revise the comparison: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendor-comparison`);
  redirect(detailPath(tenantSlug, newComparisonId));
}

export async function recommendVendorComparisonOfferAction(
  tenantSlug: string,
  comparisonId: string,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const comparisonOfferId = String(formData.get("comparisonOfferId") ?? "").trim();
  if (!comparisonOfferId) {
    return { error: "Select an offer to recommend." };
  }
  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await recommendVendorComparisonOffer(supabase, { comparisonId, comparisonOfferId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not record the recommendation: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}

export async function submitVendorComparisonForApprovalAction(
  tenantSlug: string,
  comparisonId: string,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const selectedOfferId = String(formData.get("selectedOfferId") ?? "").trim();
  if (!selectedOfferId) {
    return { error: "Select an offer to submit for approval." };
  }
  const selectionReason = String(formData.get("selectionReason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitVendorComparisonForApproval(supabase, { comparisonId, selectedOfferId, selectionReason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not submit for approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}

export async function cancelVendorComparisonAction(
  tenantSlug: string,
  comparisonId: string,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel a comparison." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelVendorComparison(supabase, { comparisonId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}

// --- Detail-page offer-level actions ---------------------------------------

export async function linkVendorComparisonOfferRateAction(
  tenantSlug: string,
  comparisonId: string,
  comparisonOfferId: string,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const rateVersionId = String(formData.get("rateVersionId") ?? "").trim();
  if (!rateVersionId) {
    return { error: "An approved rate version id is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await linkVendorComparisonOfferRate(supabase, { comparisonOfferId, rateVersionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not link the rate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}

export async function setVendorComparisonOfferInclusionAction(
  tenantSlug: string,
  comparisonId: string,
  comparisonOfferId: string,
  included: boolean,
  expectedVersion: number,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;
  if (!included && !reason) {
    return { error: "A non-empty reason is required to exclude an offer." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await setVendorComparisonOfferInclusion(supabase, { comparisonOfferId, included, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not update inclusion: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}

export async function scoreVendorComparisonOfferCriterionAction(
  tenantSlug: string,
  comparisonId: string,
  comparisonOfferId: string,
  _prevState: VendorComparisonActionState,
  formData: FormData,
): Promise<VendorComparisonActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const criterionKey = String(formData.get("criterionKey") ?? "").trim();
  const scoreRaw = String(formData.get("score") ?? "").trim();
  if (!criterionKey || scoreRaw.length === 0) {
    return { error: "A criterion key and a score (0-100) are required." };
  }
  const score = Number(scoreRaw);
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    return { error: "Score must be a number between 0 and 100." };
  }
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await scoreVendorComparisonOfferCriterion(supabase, { comparisonOfferId, criterionKey, score, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComparisonMutationError) return { error: `Could not record the score: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, comparisonId));
  return OK;
}
