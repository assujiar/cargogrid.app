"use server";

/**
 * Sourcing Server Actions (PRC-256, CG-S11-PRC-007). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/rates/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known
 * mutation error into a plain-language message, revalidate) plus
 * app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts's own
 * bound-per-row-action convention (expectedVersion captured via `.bind()` at
 * render time, not a hidden form field) for the detail page's own candidate
 * actions.
 *
 * Idempotency-key disclosure: none of the three creation forms below render a
 * client-persisted idempotency-key field (no PRC-25x creation form in this
 * repository does either -- confirmed by direct inspection of
 * app/(tenant)/[tenantSlug]/procurement/vendors/vendor-directory-panel.tsx
 * before writing this file). A fresh `crypto.randomUUID()` is generated here,
 * server-side, on every submit -- a genuine network-level double-submit (e.g.
 * a double-click before the redirect below completes) could in principle
 * create two sourcing requests rather than deduplicating one, the same
 * disclosed, pre-existing UI-layer limitation every other PRC-25x create form
 * already carries. The RPC-level idempotency guarantee itself (verified in
 * scripts/db-tests/procurement-sourcing.sql) is unaffected -- this is a UI
 * wiring gap, not a data-integrity one.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createSourcingRequestFromCosting,
  createSourcingRequestFromOperationalDemand,
  createProactiveSourcingRequest,
  submitSourcingRequest,
  overrideSourcingRequestConstraints,
  evaluateSourcingCandidateEligibility,
  shortlistSourcingCandidate,
  submitSourcingShortlist,
  closeSourcingRequestNoSource,
  cancelSourcingRequest,
  reopenSourcingRequest,
  SourcingMutationError,
} from "../../../../../server/mutations/sourcing.ts";

export interface SourcingActionState {
  readonly error: string | null;
}

const OK: SourcingActionState = { error: null };
const NO_ACCESS: SourcingActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function toIsoOrNull(raw: FormDataEntryValue | null): string | null {
  const value = String(raw ?? "").trim();
  if (value.length === 0) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function detailPath(tenantSlug: string, sourcingRequestId: string): string {
  return `/${tenantSlug}/procurement/sourcing/${sourcingRequestId}`;
}

// --- Creation (redirect to the new detail page on success) ----------------

export async function createSourcingRequestFromCostingAction(tenantSlug: string, _prevState: SourcingActionState, formData: FormData): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const costingRequestId = String(formData.get("costingRequestId") ?? "").trim();
  if (!costingRequestId) {
    return { error: "A costing request id is required." };
  }

  const supabase = await createSupabaseServerClient();
  let sourcingRequestId: string;
  try {
    const request = await createSourcingRequestFromCosting(supabase, {
      tenantId: access.tenant.id,
      costingRequestId,
      ownerUserId: access.authUserId,
      slaDueAt: toIsoOrNull(formData.get("slaDueAt")),
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    sourcingRequestId = request.id;
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not create sourcing request: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/sourcing`);
  redirect(detailPath(tenantSlug, sourcingRequestId));
}

export async function createSourcingRequestFromOperationalDemandAction(tenantSlug: string, _prevState: SourcingActionState, formData: FormData): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const shipmentOrderId = String(formData.get("shipmentOrderId") ?? "").trim();
  if (!shipmentOrderId) {
    return { error: "A shipment order id is required." };
  }

  const supabase = await createSupabaseServerClient();
  let sourcingRequestId: string;
  try {
    const request = await createSourcingRequestFromOperationalDemand(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      ownerUserId: access.authUserId,
      slaDueAt: toIsoOrNull(formData.get("slaDueAt")),
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    sourcingRequestId = request.id;
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not create sourcing request: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/sourcing`);
  redirect(detailPath(tenantSlug, sourcingRequestId));
}

export async function createProactiveSourcingRequestAction(tenantSlug: string, _prevState: SourcingActionState, formData: FormData): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const serviceType = String(formData.get("serviceType") ?? "").trim();
  const originLane = String(formData.get("originLane") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim();
  if (!serviceType || !originLane || !destinationLane) {
    return { error: "Service type, origin, and destination are required." };
  }
  const mode = String(formData.get("mode") ?? "").trim() || null;
  const currency = String(formData.get("currency") ?? "").trim() || null;
  const budgetAmountRaw = String(formData.get("budgetAmount") ?? "").trim();
  const budgetAmount = budgetAmountRaw.length > 0 ? Number(budgetAmountRaw) : null;
  if (budgetAmount !== null && (!Number.isFinite(budgetAmount) || budgetAmount < 0)) {
    return { error: "Budget amount must be a non-negative number." };
  }

  const supabase = await createSupabaseServerClient();
  let sourcingRequestId: string;
  try {
    const request = await createProactiveSourcingRequest(supabase, {
      tenantId: access.tenant.id,
      serviceType,
      mode,
      originLane,
      destinationLane,
      currency,
      budgetAmount,
      ownerUserId: access.authUserId,
      slaDueAt: toIsoOrNull(formData.get("slaDueAt")),
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    sourcingRequestId = request.id;
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not create sourcing request: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/sourcing`);
  redirect(detailPath(tenantSlug, sourcingRequestId));
}

// --- Detail-page lifecycle/candidate actions (stay on the detail page) ----

export async function submitSourcingRequestAction(tenantSlug: string, sourcingRequestId: string, expectedVersion: number, _prevState: SourcingActionState): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitSourcingRequest(supabase, { sourcingRequestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not submit: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function overrideSourcingRequestConstraintsAction(
  tenantSlug: string,
  sourcingRequestId: string,
  expectedVersion: number,
  _prevState: SourcingActionState,
  formData: FormData,
): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to override constraints." };
  }
  const cargoWeightMaxRaw = String(formData.get("cargoWeightMax") ?? "").trim();
  const cargoVolumeMaxRaw = String(formData.get("cargoVolumeMax") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await overrideSourcingRequestConstraints(supabase, {
      sourcingRequestId,
      cargoWeightMax: cargoWeightMaxRaw.length > 0 ? Number(cargoWeightMaxRaw) : null,
      cargoVolumeMax: cargoVolumeMaxRaw.length > 0 ? Number(cargoVolumeMaxRaw) : null,
      destinationLane,
      reason,
      overrideExpiresAt: toIsoOrNull(formData.get("overrideExpiresAt")),
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not override constraints: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function evaluateSourcingCandidateEligibilityAction(tenantSlug: string, sourcingRequestId: string, _prevState: SourcingActionState): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await evaluateSourcingCandidateEligibility(supabase, { sourcingRequestId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not evaluate candidate eligibility: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function shortlistSourcingCandidateAction(
  tenantSlug: string,
  sourcingRequestId: string,
  candidateId: string,
  expectedVersion: number,
  shortlisted: boolean,
  _prevState: SourcingActionState,
  formData: FormData,
): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await shortlistSourcingCandidate(supabase, { candidateId, shortlisted, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not update shortlist: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function submitSourcingShortlistAction(tenantSlug: string, sourcingRequestId: string, expectedVersion: number, _prevState: SourcingActionState): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitSourcingShortlist(supabase, { sourcingRequestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not submit shortlist: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function closeSourcingRequestNoSourceAction(
  tenantSlug: string,
  sourcingRequestId: string,
  expectedVersion: number,
  _prevState: SourcingActionState,
  formData: FormData,
): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to close a sourcing request with no source." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await closeSourcingRequestNoSource(supabase, { sourcingRequestId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not close: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function cancelSourcingRequestAction(
  tenantSlug: string,
  sourcingRequestId: string,
  expectedVersion: number,
  _prevState: SourcingActionState,
  formData: FormData,
): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel a sourcing request." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelSourcingRequest(supabase, { sourcingRequestId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}

export async function reopenSourcingRequestAction(
  tenantSlug: string,
  sourcingRequestId: string,
  expectedVersion: number,
  _prevState: SourcingActionState,
  formData: FormData,
): Promise<SourcingActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to reopen a sourcing request." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await reopenSourcingRequest(supabase, { sourcingRequestId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SourcingMutationError) return { error: `Could not reopen: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, sourcingRequestId));
  return OK;
}
