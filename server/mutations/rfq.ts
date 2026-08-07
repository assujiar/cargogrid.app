/**
 * RFQ mutation primitives (PRC-257, CG-S11-PRC-008). Thin, typed wrappers
 * around the write RPCs supabase/migrations/20260730640000_create_
 * procurement_rfq.sql adds -- the same KNOWN_MUTATION_ERROR_CODES /
 * classifyError / callRpc shape server/mutations/sourcing.ts already
 * establishes for this checkpoint's own template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  DraftRfqFromSourcingInputSchema,
  ReviseRfqInputSchema,
  IssueRfqInputSchema,
  InviteAdditionalRfqVendorInputSchema,
  ExtendRfqDeadlineInputSchema,
  CloseRfqForComparisonInputSchema,
  CancelRfqInputSchema,
  DeclineRfqInvitationInputSchema,
  RecordRfqClarificationInputSchema,
  AnswerRfqClarificationInputSchema,
  SubmitRfqResponseInputSchema,
  WithdrawRfqResponseInputSchema,
  parseRfq,
  parseRfqInvitation,
  parseRfqClarification,
  parseRfqResponse,
  type DraftRfqFromSourcingInput,
  type ReviseRfqInput,
  type IssueRfqInput,
  type InviteAdditionalRfqVendorInput,
  type ExtendRfqDeadlineInput,
  type CloseRfqForComparisonInput,
  type CancelRfqInput,
  type DeclineRfqInvitationInput,
  type RecordRfqClarificationInput,
  type AnswerRfqClarificationInput,
  type SubmitRfqResponseInput,
  type WithdrawRfqResponseInput,
  type Rfq,
  type RfqInvitation,
  type RfqClarification,
  type RfqResponse,
} from "../contracts/rfq/rfq.ts";

export type RfqMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RFQ_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "rfq_not_found",
  "rfq_invitation_not_found",
  "rfq_clarification_not_found",
  "rfq_response_not_found",
  "sourcing_request_not_found",
  "sourcing_candidate_not_found",
  "tenant_mismatch",
  "invalid_source_status",
  "candidate_source_mismatch",
  "ineligible_vendor",
  "vendor_already_invited",
  "vendor_not_invited",
  "idempotency_key_required",
  "idempotency_key_conflict",
  "reason_required",
  "question_required",
  "answer_required",
  "clarification_already_answered",
  "invalid_deadline",
  "deadline_narrowing_not_allowed",
  "no_shortlisted_vendors",
  "invalid_currency",
  "invalid_total_amount",
  "invalid_capture_mode",
  "received_at_required",
  "late_reason_required",
  "not_latest_response_version",
  "rfq_response_file_not_found",
  "rfq_response_file_mismatch",
  "rfq_response_unsafe_file",
  "stale_version",
  "invalid_transition",
  "invalid_status_filter",
] as const;
type KnownRfqMutationErrorCode = (typeof RFQ_KNOWN_MUTATION_ERROR_CODES)[number];
export type RfqMutationErrorCode = KnownRfqMutationErrorCode | "mutation_failed" | "invalid_response";

export class RfqMutationError extends Error {
  readonly code: RfqMutationErrorCode;

  constructor(code: RfqMutationErrorCode, message: string) {
    super(message);
    this.name = "RfqMutationError";
    this.code = code;
  }
}

function classifyError(message: string): RfqMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RFQ_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownRfqMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: RfqMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new RfqMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireRfqRow(data: unknown, fn: string): Rfq {
  if (!data || typeof data !== "object") {
    throw new RfqMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseRfq(data as Record<string, unknown>);
}

function requireRfqInvitationRow(data: unknown, fn: string): RfqInvitation {
  if (!data || typeof data !== "object") {
    throw new RfqMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseRfqInvitation(data as Record<string, unknown>);
}

function requireRfqClarificationRow(data: unknown, fn: string): RfqClarification {
  if (!data || typeof data !== "object") {
    throw new RfqMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseRfqClarification(data as Record<string, unknown>);
}

function requireRfqResponseRow(data: unknown, fn: string): RfqResponse {
  if (!data || typeof data !== "object") {
    throw new RfqMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseRfqResponse(data as Record<string, unknown>);
}

/** Drafts (or, on idempotency-key replay, returns the existing) an RFQ from a shortlisted sourcing request. status=draft -- needs issueRfq to invite vendors. */
export async function draftRfqFromSourcing(client: RfqMutationRpcClient, input: DraftRfqFromSourcingInput): Promise<Rfq> {
  const parsed = DraftRfqFromSourcingInputSchema.parse(input);
  const data = await callRpc(client, "draft_rfq_from_sourcing", {
    p_tenant_id: parsed.tenantId,
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_owner_user_id: parsed.ownerUserId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "draft_rfq_from_sourcing");
}

/** Only from status=issued. Marks the current version superseded and creates a new draft version (version+1, same rfq_number). Idempotent on (tenant_id, idempotency_key). */
export async function reviseRfq(client: RfqMutationRpcClient, input: ReviseRfqInput): Promise<Rfq> {
  const parsed = ReviseRfqInputSchema.parse(input);
  const data = await callRpc(client, "revise_rfq", {
    p_rfq_id: parsed.rfqId,
    p_cargo_weight_max: parsed.cargoWeightMax,
    p_cargo_volume_max: parsed.cargoVolumeMax,
    p_destination_lane: parsed.destinationLane,
    p_currency: parsed.currency,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "revise_rfq");
}

/** draft -> issued. Bulk-invites every shortlisted sourcing candidate for this RFQ's own sourcing request (bounded to 500). Requires a future p_response_deadline_at and at least one shortlisted candidate. */
export async function issueRfq(client: RfqMutationRpcClient, input: IssueRfqInput): Promise<Rfq> {
  const parsed = IssueRfqInputSchema.parse(input);
  const data = await callRpc(client, "issue_rfq", {
    p_rfq_id: parsed.rfqId,
    p_response_deadline_at: parsed.responseDeadlineAt,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "issue_rfq");
}

/** PRC:Override, mandatory reason -- a governed exception. Only an eligible (never ineligible) sourcing candidate belonging to the same sourcing request may be added, only while the RFQ is issued. */
export async function inviteAdditionalRfqVendor(client: RfqMutationRpcClient, input: InviteAdditionalRfqVendorInput): Promise<RfqInvitation> {
  const parsed = InviteAdditionalRfqVendorInputSchema.parse(input);
  const data = await callRpc(client, "invite_additional_rfq_vendor", {
    p_rfq_id: parsed.rfqId,
    p_sourcing_candidate_id: parsed.sourcingCandidateId,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqInvitationRow(data, "invite_additional_rfq_vendor");
}

/** Widen-only deadline extension while issued. */
export async function extendRfqDeadline(client: RfqMutationRpcClient, input: ExtendRfqDeadlineInput): Promise<Rfq> {
  const parsed = ExtendRfqDeadlineInputSchema.parse(input);
  const data = await callRpc(client, "extend_rfq_deadline", {
    p_rfq_id: parsed.rfqId,
    p_new_deadline_at: parsed.newDeadlineAt,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "extend_rfq_deadline");
}

/** issued -> closed. Every still-invited (never responded) invitation is marked no_response. */
export async function closeRfqForComparison(client: RfqMutationRpcClient, input: CloseRfqForComparisonInput): Promise<Rfq> {
  const parsed = CloseRfqForComparisonInputSchema.parse(input);
  const data = await callRpc(client, "close_rfq_for_comparison", {
    p_rfq_id: parsed.rfqId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "close_rfq_for_comparison");
}

/** draft or issued -> cancelled. Mandatory reason. */
export async function cancelRfq(client: RfqMutationRpcClient, input: CancelRfqInput): Promise<Rfq> {
  const parsed = CancelRfqInputSchema.parse(input);
  const data = await callRpc(client, "cancel_rfq", {
    p_rfq_id: parsed.rfqId,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqRow(data, "cancel_rfq");
}

/** Internal staff-captured record of a vendor decline (offline/email). Only while invited and the parent RFQ is issued. Mandatory reason. */
export async function declineRfqInvitation(client: RfqMutationRpcClient, input: DeclineRfqInvitationInput): Promise<RfqInvitation> {
  const parsed = DeclineRfqInvitationInputSchema.parse(input);
  const data = await callRpc(client, "decline_rfq_invitation", {
    p_rfq_invitation_id: parsed.rfqInvitationId,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqInvitationRow(data, "decline_rfq_invitation");
}

/** Records an offline-captured clarification question. vendorMasterId=null broadcasts to every invited vendor. */
export async function recordRfqClarification(client: RfqMutationRpcClient, input: RecordRfqClarificationInput): Promise<RfqClarification> {
  const parsed = RecordRfqClarificationInputSchema.parse(input);
  const data = await callRpc(client, "record_rfq_clarification", {
    p_rfq_id: parsed.rfqId,
    p_vendor_master_id: parsed.vendorMasterId,
    p_question: parsed.question,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqClarificationRow(data, "record_rfq_clarification");
}

/** Fills in the answer for an existing, not-yet-answered clarification. */
export async function answerRfqClarification(client: RfqMutationRpcClient, input: AnswerRfqClarificationInput): Promise<RfqClarification> {
  const parsed = AnswerRfqClarificationInputSchema.parse(input);
  const data = await callRpc(client, "answer_rfq_clarification", {
    p_clarification_id: parsed.clarificationId,
    p_answer: parsed.answer,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqClarificationRow(data, "answer_rfq_clarification");
}

/** Internal offline/email capture of a vendor's commercial response. On-time requires PRC:Edit; a response received after the deadline additionally requires PRC:Override + a mandatory lateReason, and is never comparisonEligible. Files must already be uploaded (app.initiate_file_upload, record_type='rfq_invitation') and scanned clean. Idempotent on (tenant_id, idempotencyKey). */
export async function submitRfqResponse(client: RfqMutationRpcClient, input: SubmitRfqResponseInput): Promise<RfqResponse> {
  const parsed = SubmitRfqResponseInputSchema.parse(input);
  const data = await callRpc(client, "submit_rfq_response", {
    p_rfq_invitation_id: parsed.rfqInvitationId,
    p_currency: parsed.currency,
    p_total_amount: parsed.totalAmount,
    p_validity_until: parsed.validityUntil,
    p_lead_time_days: parsed.leadTimeDays,
    p_commercial_terms: parsed.commercialTerms,
    p_capture_mode: parsed.captureMode,
    p_source_message_ref: parsed.sourceMessageRef,
    p_received_at: parsed.receivedAt,
    p_vendor_confirmed: parsed.vendorConfirmed,
    p_file_ids: parsed.fileIds,
    p_late_reason: parsed.lateReason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqResponseRow(data, "submit_rfq_response");
}

/** Withdraws the latest response version for an invitation (mandatory reason); the invitation reverts to invited so the vendor may be re-captured. */
export async function withdrawRfqResponse(client: RfqMutationRpcClient, input: WithdrawRfqResponseInput): Promise<RfqResponse> {
  const parsed = WithdrawRfqResponseInputSchema.parse(input);
  const data = await callRpc(client, "withdraw_rfq_response", {
    p_rfq_response_id: parsed.rfqResponseId,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRfqResponseRow(data, "withdraw_rfq_response");
}
