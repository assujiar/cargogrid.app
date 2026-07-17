/**
 * User lifecycle service (PLT-110, CG-S6-PLT-007). Thin, typed wrappers around
 * app.invite_user / app.resend_invitation / app.transition_user_status /
 * app.reassign_user_org_unit (supabase/migrations/20260716102620_create_users.sql).
 */

import {
  InviteUserInputSchema,
  ReassignUserOrgUnitInputSchema,
  ResendInvitationInputSchema,
  TransitionUserStatusInputSchema,
  parseUser,
  type InviteUserInput,
  type ReassignUserOrgUnitInput,
  type ResendInvitationInput,
  type TransitionUserStatusInput,
  type User,
} from "../contracts/user-lifecycle/user-lifecycle.ts";

export interface UserLifecycleRpcClient {
  rpc(
    fn: "invite_user" | "resend_invitation" | "transition_user_status" | "reassign_user_org_unit",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const USER_LIFECYCLE_KNOWN_ERROR_CODES = [
  "user_not_found",
  "user_version_conflict",
  "invalid_resend",
  "last_critical_admin",
  "cross_tenant_org_unit",
] as const;
type KnownUserLifecycleErrorCode = (typeof USER_LIFECYCLE_KNOWN_ERROR_CODES)[number];
export type UserLifecycleMutationErrorCode = KnownUserLifecycleErrorCode | "mutation_failed" | "invalid_response";

export class UserLifecycleMutationError extends Error {
  readonly code: UserLifecycleMutationErrorCode;

  constructor(code: UserLifecycleMutationErrorCode, message: string) {
    super(message);
    this.name = "UserLifecycleMutationError";
    this.code = code;
  }
}

function classifyError(message: string): UserLifecycleMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (USER_LIFECYCLE_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownUserLifecycleErrorCode)
    : "mutation_failed";
}

async function callAndParse(
  client: UserLifecycleRpcClient,
  fn: "invite_user" | "resend_invitation" | "transition_user_status" | "reassign_user_org_unit",
  args: Record<string, unknown>,
): Promise<User> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new UserLifecycleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new UserLifecycleMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseUser(data as Record<string, unknown>);
}

export async function inviteUser(client: UserLifecycleRpcClient, input: InviteUserInput): Promise<User> {
  const parsedInput = InviteUserInputSchema.parse(input);
  return callAndParse(client, "invite_user", {
    p_tenant_id: parsedInput.tenantId,
    p_auth_user_id: parsedInput.authUserId,
    p_email: parsedInput.email,
    p_display_name: parsedInput.displayName,
    p_org_unit_id: parsedInput.orgUnitId,
    p_invited_by: parsedInput.invitedBy,
    p_invite_expires_at: parsedInput.inviteExpiresAt,
  });
}

export async function resendInvitation(client: UserLifecycleRpcClient, input: ResendInvitationInput): Promise<User> {
  const parsedInput = ResendInvitationInputSchema.parse(input);
  return callAndParse(client, "resend_invitation", {
    p_id: parsedInput.id,
    p_new_expires_at: parsedInput.newExpiresAt,
    p_requested_by: parsedInput.requestedBy,
  });
}

export async function transitionUserStatus(client: UserLifecycleRpcClient, input: TransitionUserStatusInput): Promise<User> {
  const parsedInput = TransitionUserStatusInputSchema.parse(input);
  return callAndParse(client, "transition_user_status", {
    p_id: parsedInput.id,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });
}

export async function reassignUserOrgUnit(client: UserLifecycleRpcClient, input: ReassignUserOrgUnitInput): Promise<User> {
  const parsedInput = ReassignUserOrgUnitInputSchema.parse(input);
  return callAndParse(client, "reassign_user_org_unit", {
    p_id: parsedInput.id,
    p_new_org_unit_id: parsedInput.newOrgUnitId,
    p_expected_version: parsedInput.expectedVersion,
    p_requested_by: parsedInput.requestedBy,
  });
}
