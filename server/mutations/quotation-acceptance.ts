/**
 * Customer Acceptance mutation primitives (COM-154, CG-S7-COM-013). Thin, typed wrappers
 * around app.send_quotation_for_acceptance / app.revoke_quotation_acceptance_token /
 * app.record_quotation_customer_decision
 * (supabase/migrations/20260724280000_create_commercial_quotation_customer_acceptance.sql).
 * `sendQuotationForAcceptance`/`revokeQuotationAcceptanceToken` are called with the
 * RLS-scoped `authenticated` client (internal, seller-side); `recordQuotationCustomerDecision`
 * is called with a service-role client from the public `/quote-decision/[token]` route (the
 * customer has no `auth.users` session).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SendQuotationForAcceptanceInputSchema,
  RevokeQuotationAcceptanceTokenInputSchema,
  RecordQuotationCustomerDecisionInputSchema,
  parseSendQuotationForAcceptanceResult,
  parseQuotationAcceptanceToken,
  type SendQuotationForAcceptanceInput,
  type RevokeQuotationAcceptanceTokenInput,
  type RecordQuotationCustomerDecisionInput,
  type SendQuotationForAcceptanceResult,
  type QuotationAcceptanceToken,
} from "../contracts/quotation/quotation-acceptance.ts";
import { parseQuotation, type Quotation } from "../contracts/quotation/quotation.ts";

export type QuotationAcceptanceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const QUOTATION_ACCEPTANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_not_found",
  "not_current_version",
  "quotation_not_acceptance_eligible",
  "decision_already_recorded",
  "quotation_validity_expired",
  "recipient_not_found",
  "invalid_channel",
  "token_not_found",
  "token_not_active",
  "reason_required",
  "invalid_decision",
  "decided_by_name_required",
  "token_expired",
  "token_revoked",
  "token_already_consumed",
] as const;
type KnownQuotationAcceptanceMutationErrorCode = (typeof QUOTATION_ACCEPTANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type QuotationAcceptanceMutationErrorCode = KnownQuotationAcceptanceMutationErrorCode | "mutation_failed" | "invalid_response";

export class QuotationAcceptanceMutationError extends Error {
  readonly code: QuotationAcceptanceMutationErrorCode;

  constructor(code: QuotationAcceptanceMutationErrorCode, message: string) {
    super(message);
    this.name = "QuotationAcceptanceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): QuotationAcceptanceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (QUOTATION_ACCEPTANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownQuotationAcceptanceMutationErrorCode)
    : "mutation_failed";
}

/** Mints (or re-mints, revoking any prior active token) a hashed single-use acceptance token. rawToken is returned exactly once -- never storable, never replayable. */
export async function sendQuotationForAcceptance(client: QuotationAcceptanceMutationRpcClient, input: SendQuotationForAcceptanceInput): Promise<SendQuotationForAcceptanceResult> {
  const parsedInput = SendQuotationForAcceptanceInputSchema.parse(input);
  const { data, error } = await client.rpc("send_quotation_for_acceptance", {
    p_quotation_id: parsedInput.quotationId,
    p_recipient_contact_id: parsedInput.recipientContactId,
    p_channel: parsedInput.channel,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new QuotationAcceptanceMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new QuotationAcceptanceMutationError("invalid_response", "send_quotation_for_acceptance returned no row");
  }
  return parseSendQuotationForAcceptanceResult(row as Record<string, unknown>);
}

/** Explicit seller-initiated revoke -- requires a reason. A token superseded by a resend is revoked automatically by sendQuotationForAcceptance itself, not through this function. */
export async function revokeQuotationAcceptanceToken(client: QuotationAcceptanceMutationRpcClient, input: RevokeQuotationAcceptanceTokenInput): Promise<QuotationAcceptanceToken> {
  const parsedInput = RevokeQuotationAcceptanceTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_quotation_acceptance_token", {
    p_token_id: parsedInput.tokenId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new QuotationAcceptanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new QuotationAcceptanceMutationError("invalid_response", "revoke_quotation_acceptance_token returned no row");
  }
  return parseQuotationAcceptanceToken(data as Record<string, unknown>);
}

/** The one customer-facing decision write. Atomic single-use token consumption is the real replay guard -- a concurrent second attempt with the same token fails closed (token_not_active/token_already_consumed). */
export async function recordQuotationCustomerDecision(client: QuotationAcceptanceMutationRpcClient, input: RecordQuotationCustomerDecisionInput): Promise<Quotation> {
  const parsedInput = RecordQuotationCustomerDecisionInputSchema.parse(input);
  const { data, error } = await client.rpc("record_quotation_customer_decision", {
    p_raw_token: parsedInput.rawToken,
    p_decision: parsedInput.decision,
    p_decided_by_name: parsedInput.decidedByName,
    p_decided_by_title: parsedInput.decidedByTitle,
    p_decided_by_email: parsedInput.decidedByEmail,
    p_reason: parsedInput.reason,
    p_ip_address: parsedInput.ipAddress,
    p_user_agent: parsedInput.userAgent,
  });
  if (error) {
    throw new QuotationAcceptanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new QuotationAcceptanceMutationError("invalid_response", "record_quotation_customer_decision returned no row");
  }
  return parseQuotation(data as Record<string, unknown>);
}
