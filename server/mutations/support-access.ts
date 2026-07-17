/**
 * Support access and impersonation lifecycle mutations (PLT-115, CG-S6-PLT-012). Thin,
 * typed wrappers around app.request_support_access / app.approve_support_access /
 * app.deny_support_access / app.revoke_support_access / app.start_support_session /
 * app.end_support_session / app.complete_support_access_post_review
 * (supabase/migrations/20260716111315_create_support_access.sql).
 */

import {
  ApproveSupportAccessInputSchema,
  CompleteSupportAccessPostReviewInputSchema,
  DenySupportAccessInputSchema,
  EndSupportSessionInputSchema,
  RequestSupportAccessInputSchema,
  RevokeSupportAccessInputSchema,
  StartSupportSessionInputSchema,
  parseSupportAccessGrant,
  parseSupportAccessSession,
  type ApproveSupportAccessInput,
  type CompleteSupportAccessPostReviewInput,
  type DenySupportAccessInput,
  type EndSupportSessionInput,
  type RequestSupportAccessInput,
  type RevokeSupportAccessInput,
  type StartSupportSessionInput,
  type SupportAccessGrant,
  type SupportAccessSession,
} from "../contracts/support-access/support-access.ts";

type GrantRpcFn =
  | "request_support_access"
  | "approve_support_access"
  | "deny_support_access"
  | "revoke_support_access"
  | "complete_support_access_post_review";

type SessionRpcFn = "start_support_session" | "end_support_session";

export interface SupportAccessMutationRpcClient {
  rpc(
    fn: GrantRpcFn | SessionRpcFn,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const SUPPORT_ACCESS_KNOWN_ERROR_CODES = [
  "grant_not_found",
  "session_not_found",
  "invalid_grant_status",
  "invalid_grant_transition",
  "self_approval_forbidden",
  "insufficient_authority",
  "invalid_expiry",
  "grant_not_approved",
  "grant_revoked",
  "grant_expired",
  "reauth_required",
  "not_emergency_grant",
] as const;
type KnownSupportAccessErrorCode = (typeof SUPPORT_ACCESS_KNOWN_ERROR_CODES)[number];
export type SupportAccessMutationErrorCode = KnownSupportAccessErrorCode | "mutation_failed" | "invalid_response";

export class SupportAccessMutationError extends Error {
  readonly code: SupportAccessMutationErrorCode;

  constructor(code: SupportAccessMutationErrorCode, message: string) {
    super(message);
    this.name = "SupportAccessMutationError";
    this.code = code;
  }
}

function classifyError(message: string): SupportAccessMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SUPPORT_ACCESS_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownSupportAccessErrorCode)
    : "mutation_failed";
}

async function callAndParseGrant(
  client: SupportAccessMutationRpcClient,
  fn: GrantRpcFn,
  args: Record<string, unknown>,
): Promise<SupportAccessGrant> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new SupportAccessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SupportAccessMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseSupportAccessGrant(data as Record<string, unknown>);
}

async function callAndParseSession(
  client: SupportAccessMutationRpcClient,
  fn: SessionRpcFn,
  args: Record<string, unknown>,
): Promise<SupportAccessSession> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new SupportAccessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SupportAccessMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseSupportAccessSession(data as Record<string, unknown>);
}

export async function requestSupportAccess(
  client: SupportAccessMutationRpcClient,
  input: RequestSupportAccessInput,
): Promise<SupportAccessGrant> {
  const parsedInput = RequestSupportAccessInputSchema.parse(input);
  return callAndParseGrant(client, "request_support_access", {
    p_tenant_id: parsedInput.tenantId,
    p_grantee_auth_user_id: parsedInput.granteeAuthUserId,
    p_reason: parsedInput.reason,
    p_case_id: parsedInput.caseId,
    p_expiry_minutes: parsedInput.expiryMinutes,
    p_requested_by: parsedInput.requestedBy,
    p_scope: parsedInput.scope,
    p_emergency: parsedInput.emergency,
    p_authorized_by_auth_user_id: parsedInput.authorizedByAuthUserId,
  });
}

export async function approveSupportAccess(
  client: SupportAccessMutationRpcClient,
  input: ApproveSupportAccessInput,
): Promise<SupportAccessGrant> {
  const parsedInput = ApproveSupportAccessInputSchema.parse(input);
  return callAndParseGrant(client, "approve_support_access", {
    p_grant_id: parsedInput.grantId,
    p_approver_auth_user_id: parsedInput.approverAuthUserId,
    p_approved_by: parsedInput.approvedBy,
    p_expires_at: parsedInput.expiresAt,
  });
}

export async function denySupportAccess(
  client: SupportAccessMutationRpcClient,
  input: DenySupportAccessInput,
): Promise<SupportAccessGrant> {
  const parsedInput = DenySupportAccessInputSchema.parse(input);
  return callAndParseGrant(client, "deny_support_access", {
    p_grant_id: parsedInput.grantId,
    p_denier_auth_user_id: parsedInput.denierAuthUserId,
    p_denied_by: parsedInput.deniedBy,
    p_reason: parsedInput.reason,
  });
}

/** The kill switch (Prompt 115 §16/§20 task 3). */
export async function revokeSupportAccess(
  client: SupportAccessMutationRpcClient,
  input: RevokeSupportAccessInput,
): Promise<SupportAccessGrant> {
  const parsedInput = RevokeSupportAccessInputSchema.parse(input);
  return callAndParseGrant(client, "revoke_support_access", {
    p_grant_id: parsedInput.grantId,
    p_revoker_auth_user_id: parsedInput.revokerAuthUserId,
    p_revoked_by: parsedInput.revokedBy,
    p_reason: parsedInput.reason,
  });
}

export async function completeSupportAccessPostReview(
  client: SupportAccessMutationRpcClient,
  input: CompleteSupportAccessPostReviewInput,
): Promise<SupportAccessGrant> {
  const parsedInput = CompleteSupportAccessPostReviewInputSchema.parse(input);
  return callAndParseGrant(client, "complete_support_access_post_review", {
    p_grant_id: parsedInput.grantId,
    p_reviewer_auth_user_id: parsedInput.reviewerAuthUserId,
    p_note: parsedInput.note,
  });
}

/** Activation (Prompt 115 §4: "re-authentication"). reauthConfirmedAt must be a fresh (<=5 minute old) timestamp obtained by having the grantee actually re-authenticate immediately beforehand. */
export async function startSupportSession(
  client: SupportAccessMutationRpcClient,
  input: StartSupportSessionInput,
): Promise<SupportAccessSession> {
  const parsedInput = StartSupportSessionInputSchema.parse(input);
  return callAndParseSession(client, "start_support_session", {
    p_grant_id: parsedInput.grantId,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_started_by: parsedInput.startedBy,
  });
}

export async function endSupportSession(
  client: SupportAccessMutationRpcClient,
  input: EndSupportSessionInput,
): Promise<SupportAccessSession> {
  const parsedInput = EndSupportSessionInputSchema.parse(input);
  return callAndParseSession(client, "end_support_session", {
    p_session_id: parsedInput.sessionId,
    p_ended_by: parsedInput.endedBy,
    p_ended_reason: parsedInput.endedReason,
  });
}
