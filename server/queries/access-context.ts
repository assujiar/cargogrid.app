/**
 * Four-layer access context resolver (PLT-108, CG-S6-PLT-005). Thin, typed wrapper around
 * app.resolve_access_context (supabase/migrations/20260716100825_create_principal_memberships.sql).
 * Read-only (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) --
 * this is the base guard every future API route/server action/job entry point calls first:
 * it either returns exactly one resolved context or throws, so a caller cannot proceed on
 * a partial or ambiguous principal (Prompt 108 §33 acceptance criterion). Wiring this into
 * live REST/GraphQL/job/file entry points is deferred to when those surfaces themselves are
 * built (no Next.js route or job runner exists yet in this repository) -- see PLT-108.md §2.
 */

import {
  ResolveAccessContextInputSchema,
  parseAccessContext,
  type AccessContext,
  type ResolveAccessContextInput,
} from "../contracts/access-context/access-context.ts";

export interface AccessContextRpcClient {
  rpc(
    fn: "resolve_access_context",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const ACCESS_CONTEXT_RESOLUTION_ERROR_CODES = [
  "no_active_membership",
  "ambiguous_context",
  "inactive_tenant",
  "inactive_identity_link",
  "no_active_membership_for_tenant",
] as const;
type KnownResolutionErrorCode = (typeof ACCESS_CONTEXT_RESOLUTION_ERROR_CODES)[number];
export type AccessContextResolutionErrorCode = KnownResolutionErrorCode | "resolution_failed" | "invalid_response";

/**
 * Every resolution failure fails closed as this one typed error -- never a null/undefined
 * context a caller might accidentally treat as "unrestricted." `code` lets callers branch
 * (e.g. `ambiguous_context` -> show a tenant picker; anything else -> deny outright).
 */
export class AccessContextResolutionError extends Error {
  readonly code: AccessContextResolutionErrorCode;

  constructor(code: AccessContextResolutionErrorCode, message: string) {
    super(message);
    this.name = "AccessContextResolutionError";
    this.code = code;
  }
}

function classifyResolutionError(message: string): AccessContextResolutionErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACCESS_CONTEXT_RESOLUTION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownResolutionErrorCode)
    : "resolution_failed";
}

export async function resolveAccessContext(client: AccessContextRpcClient, input: ResolveAccessContextInput): Promise<AccessContext> {
  const parsedInput = ResolveAccessContextInputSchema.parse(input);

  const { data, error } = await client.rpc("resolve_access_context", {
    p_auth_user_id: parsedInput.authUserId,
    p_tenant_id: parsedInput.tenantId,
    p_customer_account_ref: parsedInput.customerAccountRef,
  });

  if (error) {
    throw new AccessContextResolutionError(classifyResolutionError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccessContextResolutionError("invalid_response", "resolve_access_context returned no context");
  }
  return parseAccessContext(data as Record<string, unknown>);
}
