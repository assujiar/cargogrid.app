/**
 * Public API Platform mutation entry points (IAE-009, Prompt 337). Thin, typed
 * wrappers around app.register_api_version / app.set_api_version_status /
 * app.authenticate_and_authorize_api_request
 * (supabase/migrations/20260804010000_create_intelligence_public_api_platform.sql).
 * Every one of these is service_role-only -- register/set_api_version_status mirror
 * PLT-129's own "definition-admin-grade authority, server-mediated only" design;
 * authenticate_and_authorize_api_request is this capability's own gateway entrypoint,
 * called exclusively from a REST route handler's service-role client, never a live
 * authenticated session.
 */

import {
  RegisterApiVersionInputSchema,
  SetApiVersionStatusInputSchema,
  AuthenticateAndAuthorizeApiRequestInputSchema,
  parseApiVersion,
  parseAuthenticateAndAuthorizeApiRequestResult,
  type RegisterApiVersionInput,
  type SetApiVersionStatusInput,
  type AuthenticateAndAuthorizeApiRequestInput,
  type ApiVersion,
  type AuthenticateAndAuthorizeApiRequestResult,
} from "../contracts/public-api-platform/public-api-platform.ts";

export interface PublicApiPlatformMutationRpcClient {
  rpc(
    fn: "register_api_version" | "set_api_version_status" | "authenticate_and_authorize_api_request",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const PUBLIC_API_PLATFORM_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "api_version_invalid_status",
  "api_version_missing_sunset_at",
  "api_version_not_found",
] as const;
type KnownPublicApiPlatformMutationErrorCode = (typeof PUBLIC_API_PLATFORM_KNOWN_MUTATION_ERROR_CODES)[number];
export type PublicApiPlatformMutationErrorCode = KnownPublicApiPlatformMutationErrorCode | "mutation_failed" | "invalid_response";

export class PublicApiPlatformMutationError extends Error {
  readonly code: PublicApiPlatformMutationErrorCode;

  constructor(code: PublicApiPlatformMutationErrorCode, message: string) {
    super(message);
    this.name = "PublicApiPlatformMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PublicApiPlatformMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PUBLIC_API_PLATFORM_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownPublicApiPlatformMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent by code -- a repeated register for an already-registered code returns it unchanged, never overwritten. Supreme-Admin-only. */
export async function registerApiVersion(client: PublicApiPlatformMutationRpcClient, input: RegisterApiVersionInput): Promise<ApiVersion> {
  const parsedInput = RegisterApiVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("register_api_version", {
    p_code: parsedInput.code,
    p_status: parsedInput.status,
    p_sunset_at: parsedInput.sunsetAt,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new PublicApiPlatformMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PublicApiPlatformMutationError("invalid_response", "register_api_version returned no row");
  }
  return parseApiVersion(data as Record<string, unknown>);
}

/** The real, audited active -> deprecated -> sunset transition (Prompt 337's own "breaking changes require version/deprecation plan" business rule). Supreme-Admin-only. */
export async function setApiVersionStatus(client: PublicApiPlatformMutationRpcClient, input: SetApiVersionStatusInput): Promise<ApiVersion> {
  const parsedInput = SetApiVersionStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_api_version_status", {
    p_code: parsedInput.code,
    p_status: parsedInput.status,
    p_sunset_at: parsedInput.sunsetAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new PublicApiPlatformMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PublicApiPlatformMutationError("invalid_response", "set_api_version_status returned no row");
  }
  return parseApiVersion(data as Record<string, unknown>);
}

/** The one real REST /v1 gateway entrypoint -- never throws for a routine unauthenticated/forbidden_scope/rate_limited outcome (see the result's own `outcome` field); a thrown error here means the call to this function itself was malformed. */
export async function authenticateAndAuthorizeApiRequest(
  client: PublicApiPlatformMutationRpcClient,
  input: AuthenticateAndAuthorizeApiRequestInput,
): Promise<AuthenticateAndAuthorizeApiRequestResult> {
  const parsedInput = AuthenticateAndAuthorizeApiRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("authenticate_and_authorize_api_request", {
    p_raw_key: parsedInput.rawKey,
    p_required_scope: parsedInput.requiredScope,
  });
  if (error) {
    throw new PublicApiPlatformMutationError("mutation_failed", error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new PublicApiPlatformMutationError("invalid_response", "authenticate_and_authorize_api_request returned no row");
  }
  return parseAuthenticateAndAuthorizeApiRequestResult(row as Record<string, unknown>);
}
