"use server";

/**
 * RFQ Server Actions (PRC-257, CG-S11-PRC-008). Mirrors app/(tenant)/
 * [tenantSlug]/procurement/sourcing/actions.ts's own exact shape (resolve
 * portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) plus its own bound-per-
 * row-action convention (expectedVersion captured via `.bind()` at render
 * time, not a hidden form field) for the detail page's own invitation/
 * clarification/response actions.
 *
 * Idempotency-key disclosure: identical to every other PRC-25x creation
 * form in this repository -- a fresh `crypto.randomUUID()` is generated
 * here, server-side, on every submit, not client-persisted. The RPC-level
 * idempotency guarantee itself is real and tested
 * (scripts/db-tests/procurement-rfq.sql); this is the same disclosed UI-
 * wiring gap every other PRC-25x create form already carries.
 *
 * File attachment disclosure: app.submit_rfq_response accepts an array of
 * already-uploaded, already-scanned file ids (app.initiate_file_upload /
 * app.record_file_scan_result, record_type='rfq_invitation'). This
 * checkpoint's own detail-panel form collects file ids as a manual
 * comma-separated text field rather than a full drag-and-drop upload
 * widget -- no PRC-25x capability in this repository has built a generic
 * file-upload UI component yet, so building a one-off here would duplicate,
 * not reuse, whatever that shared widget ends up being. Disclosed, not
 * silently a dead action -- the RPC's own file re-validation (tenant/
 * record-scope/scan-status) still runs for whatever ids are submitted.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  draftRfqFromSourcing,
  reviseRfq,
  issueRfq,
  inviteAdditionalRfqVendor,
  extendRfqDeadline,
  closeRfqForComparison,
  cancelRfq,
  declineRfqInvitation,
  recordRfqClarification,
  answerRfqClarification,
  submitRfqResponse,
  withdrawRfqResponse,
  RfqMutationError,
} from "../../../../../server/mutations/rfq.ts";

export interface RfqActionState {
  readonly error: string | null;
}

const OK: RfqActionState = { error: null };
const NO_ACCESS: RfqActionState = { error: "You don't have access to this organization's Procurement workspace." };

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

function parseFileIds(raw: FormDataEntryValue | null): string[] | null {
  const value = String(raw ?? "").trim();
  if (value.length === 0) return null;
  return value
    .split(",")
    .map((id) => id.trim())
    .filter((id) => id.length > 0);
}

function detailPath(tenantSlug: string, rfqId: string): string {
  return `/${tenantSlug}/procurement/rfq/${rfqId}`;
}

// --- Creation (redirect to the new detail page on success) ----------------

export async function draftRfqFromSourcingAction(tenantSlug: string, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const sourcingRequestId = String(formData.get("sourcingRequestId") ?? "").trim();
  if (!sourcingRequestId) {
    return { error: "A shortlisted sourcing request id is required." };
  }

  const supabase = await createSupabaseServerClient();
  let rfqId: string;
  try {
    const rfq = await draftRfqFromSourcing(supabase, {
      tenantId: access.tenant.id,
      sourcingRequestId,
      ownerUserId: access.authUserId,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    rfqId = rfq.id;
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not draft RFQ: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/rfq`);
  redirect(detailPath(tenantSlug, rfqId));
}

// --- Detail-page RFQ-root lifecycle actions (stay on the detail page) -----

export async function reviseRfqAction(tenantSlug: string, rfqId: string, expectedVersion: number, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to revise an RFQ." };
  }
  const cargoWeightMaxRaw = String(formData.get("cargoWeightMax") ?? "").trim();
  const cargoVolumeMaxRaw = String(formData.get("cargoVolumeMax") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim() || null;
  const currency = String(formData.get("currency") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let newRfqId: string;
  try {
    const rfq = await reviseRfq(supabase, {
      rfqId,
      cargoWeightMax: cargoWeightMaxRaw.length > 0 ? Number(cargoWeightMaxRaw) : null,
      cargoVolumeMax: cargoVolumeMaxRaw.length > 0 ? Number(cargoVolumeMaxRaw) : null,
      destinationLane,
      currency,
      reason,
      idempotencyKey: crypto.randomUUID(),
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newRfqId = rfq.id;
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not revise RFQ: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/rfq`);
  redirect(detailPath(tenantSlug, newRfqId));
}

export async function issueRfqAction(tenantSlug: string, rfqId: string, expectedVersion: number, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const responseDeadlineAt = toIsoOrNull(formData.get("responseDeadlineAt"));
  if (!responseDeadlineAt) {
    return { error: "A future response deadline is required to issue this RFQ." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await issueRfq(supabase, { rfqId, responseDeadlineAt, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not issue RFQ: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function inviteAdditionalRfqVendorAction(tenantSlug: string, rfqId: string, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const sourcingCandidateId = String(formData.get("sourcingCandidateId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!sourcingCandidateId || !reason) {
    return { error: "A sourcing candidate id and a non-empty reason are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await inviteAdditionalRfqVendor(supabase, { rfqId, sourcingCandidateId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not invite the additional vendor: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function extendRfqDeadlineAction(tenantSlug: string, rfqId: string, expectedVersion: number, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newDeadlineAt = toIsoOrNull(formData.get("newDeadlineAt"));
  if (!newDeadlineAt) {
    return { error: "A new deadline is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await extendRfqDeadline(supabase, { rfqId, newDeadlineAt, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not extend the deadline: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function closeRfqForComparisonAction(tenantSlug: string, rfqId: string, expectedVersion: number, _prevState: RfqActionState): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await closeRfqForComparison(supabase, { rfqId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not close for comparison: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function cancelRfqAction(tenantSlug: string, rfqId: string, expectedVersion: number, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel an RFQ." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelRfq(supabase, { rfqId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

// --- Detail-page invitation/clarification/response actions ----------------

export async function declineRfqInvitationAction(
  tenantSlug: string,
  rfqId: string,
  rfqInvitationId: string,
  expectedVersion: number,
  _prevState: RfqActionState,
  formData: FormData,
): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to record a decline." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await declineRfqInvitation(supabase, { rfqInvitationId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not record the decline: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function recordRfqClarificationAction(tenantSlug: string, rfqId: string, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const question = String(formData.get("question") ?? "").trim();
  if (!question) {
    return { error: "A non-empty question is required." };
  }
  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await recordRfqClarification(supabase, { rfqId, vendorMasterId, question, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not record the clarification: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function answerRfqClarificationAction(
  tenantSlug: string,
  rfqId: string,
  clarificationId: string,
  expectedVersion: number,
  _prevState: RfqActionState,
  formData: FormData,
): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const answer = String(formData.get("answer") ?? "").trim();
  if (!answer) {
    return { error: "A non-empty answer is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await answerRfqClarification(supabase, { clarificationId, answer, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not record the answer: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function submitRfqResponseAction(tenantSlug: string, rfqId: string, rfqInvitationId: string, _prevState: RfqActionState, formData: FormData): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const currency = String(formData.get("currency") ?? "").trim();
  const totalAmountRaw = String(formData.get("totalAmount") ?? "").trim();
  const receivedAt = toIsoOrNull(formData.get("receivedAt"));
  if (!currency || totalAmountRaw.length === 0 || !receivedAt) {
    return { error: "Currency, total amount, and received date/time are required." };
  }
  const totalAmount = Number(totalAmountRaw);
  if (!Number.isFinite(totalAmount) || totalAmount < 0) {
    return { error: "Total amount must be a non-negative number." };
  }
  const leadTimeDaysRaw = String(formData.get("leadTimeDays") ?? "").trim();
  const leadTimeDays = leadTimeDaysRaw.length > 0 ? Number(leadTimeDaysRaw) : null;
  const validityUntil = toIsoOrNull(formData.get("validityUntil"));
  const captureModeRaw = String(formData.get("captureMode") ?? "offline").trim();
  const captureMode = captureModeRaw === "email" ? "email" : "offline";
  const sourceMessageRef = String(formData.get("sourceMessageRef") ?? "").trim() || null;
  const vendorConfirmed = formData.get("vendorConfirmed") === "on";
  const lateReason = String(formData.get("lateReason") ?? "").trim() || null;
  const fileIds = parseFileIds(formData.get("fileIds"));

  const supabase = await createSupabaseServerClient();
  try {
    await submitRfqResponse(supabase, {
      rfqInvitationId,
      currency,
      totalAmount,
      validityUntil,
      leadTimeDays,
      captureMode,
      sourceMessageRef,
      receivedAt,
      vendorConfirmed,
      fileIds,
      lateReason,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not capture the response: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}

export async function withdrawRfqResponseAction(
  tenantSlug: string,
  rfqId: string,
  rfqResponseId: string,
  expectedVersion: number,
  _prevState: RfqActionState,
  formData: FormData,
): Promise<RfqActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to withdraw a response." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawRfqResponse(supabase, { rfqResponseId, reason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RfqMutationError) return { error: `Could not withdraw the response: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, rfqId));
  return OK;
}
