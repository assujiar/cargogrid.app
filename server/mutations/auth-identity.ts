/**
 * Auth identity linkage service (PLT-107, CG-S6-PLT-004). Thin, typed wrapper around
 * app.link_auth_identity / app.revoke_auth_identity
 * (supabase/migrations/20260716095343_link_auth_identities.sql).
 */

import {
  LinkAuthIdentityInputSchema,
  RevokeAuthIdentityInputSchema,
  parseTenantUserIdentity,
  type LinkAuthIdentityInput,
  type RevokeAuthIdentityInput,
  type TenantUserIdentity,
} from "../contracts/auth/identity.ts";

export interface IdentityRpcClient {
  rpc(
    fn: "link_auth_identity" | "revoke_auth_identity",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export type IdentityMutationErrorCode = "link_failed" | "revoke_failed" | "invalid_response";

export class IdentityMutationError extends Error {
  readonly code: IdentityMutationErrorCode;

  constructor(code: IdentityMutationErrorCode, message: string) {
    super(message);
    this.name = "IdentityMutationError";
    this.code = code;
  }
}

export async function linkAuthIdentity(client: IdentityRpcClient, input: LinkAuthIdentityInput): Promise<TenantUserIdentity> {
  const parsedInput = LinkAuthIdentityInputSchema.parse(input);

  const { data, error } = await client.rpc("link_auth_identity", {
    p_auth_user_id: parsedInput.authUserId,
    p_tenant_id: parsedInput.tenantId,
    p_invited_by: parsedInput.invitedBy,
    p_status: parsedInput.status,
  });

  if (error) {
    throw new IdentityMutationError("link_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IdentityMutationError("invalid_response", "link_auth_identity returned no row");
  }
  return parseTenantUserIdentity(data as Record<string, unknown>);
}

export async function revokeAuthIdentity(client: IdentityRpcClient, input: RevokeAuthIdentityInput): Promise<TenantUserIdentity> {
  const parsedInput = RevokeAuthIdentityInputSchema.parse(input);

  const { data, error } = await client.rpc("revoke_auth_identity", {
    p_auth_user_id: parsedInput.authUserId,
    p_tenant_id: parsedInput.tenantId,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });

  if (error) {
    throw new IdentityMutationError("revoke_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IdentityMutationError("invalid_response", "revoke_auth_identity returned no row");
  }
  return parseTenantUserIdentity(data as Record<string, unknown>);
}
