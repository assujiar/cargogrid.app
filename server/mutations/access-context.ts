/**
 * Principal membership grant/revoke service (PLT-108, CG-S6-PLT-005). Thin, typed wrapper
 * around app.grant_principal_membership / app.revoke_principal_membership
 * (supabase/migrations/20260716100825_create_principal_memberships.sql).
 */

import {
  GrantPrincipalMembershipInputSchema,
  RevokePrincipalMembershipInputSchema,
  parsePrincipalMembership,
  type GrantPrincipalMembershipInput,
  type PrincipalMembership,
  type RevokePrincipalMembershipInput,
} from "../contracts/access-context/access-context.ts";

export interface PrincipalMembershipRpcClient {
  rpc(
    fn: "grant_principal_membership" | "revoke_principal_membership",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export type PrincipalMembershipMutationErrorCode = "grant_failed" | "revoke_failed" | "invalid_response";

export class PrincipalMembershipMutationError extends Error {
  readonly code: PrincipalMembershipMutationErrorCode;

  constructor(code: PrincipalMembershipMutationErrorCode, message: string) {
    super(message);
    this.name = "PrincipalMembershipMutationError";
    this.code = code;
  }
}

export async function grantPrincipalMembership(
  client: PrincipalMembershipRpcClient,
  input: GrantPrincipalMembershipInput,
): Promise<PrincipalMembership> {
  const parsedInput = GrantPrincipalMembershipInputSchema.parse(input);

  const { data, error } = await client.rpc("grant_principal_membership", {
    p_auth_user_id: parsedInput.authUserId,
    p_layer: parsedInput.layer,
    p_tenant_id: parsedInput.tenantId,
    p_customer_account_ref: parsedInput.customerAccountRef,
    p_granted_by: parsedInput.grantedBy,
  });

  if (error) {
    throw new PrincipalMembershipMutationError("grant_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PrincipalMembershipMutationError("invalid_response", "grant_principal_membership returned no row");
  }
  return parsePrincipalMembership(data as Record<string, unknown>);
}

export async function revokePrincipalMembership(
  client: PrincipalMembershipRpcClient,
  input: RevokePrincipalMembershipInput,
): Promise<PrincipalMembership> {
  const parsedInput = RevokePrincipalMembershipInputSchema.parse(input);

  const { data, error } = await client.rpc("revoke_principal_membership", {
    p_membership_id: parsedInput.membershipId,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });

  if (error) {
    throw new PrincipalMembershipMutationError("revoke_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PrincipalMembershipMutationError("invalid_response", "revoke_principal_membership returned no row");
  }
  return parsePrincipalMembership(data as Record<string, unknown>);
}
