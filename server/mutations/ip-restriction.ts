/**
 * IP Restriction and Network Access mutation primitives (IAE-028, Prompt 356).
 * Thin, typed wrappers around app.set_ip_allowlist_enforcement_mode /
 * app.add_ip_allowlist_entry / app.revoke_ip_allowlist_entry /
 * app.assert_ip_allowed / app.request_ip_allowlist_bypass /
 * app.approve_ip_allowlist_bypass
 * (supabase/migrations/20260807200000_create_intelligence_ip_restriction_network_access.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetIpAllowlistEnforcementModeInputSchema,
  AddIpAllowlistEntryInputSchema,
  RevokeIpAllowlistEntryInputSchema,
  AssertIpAllowedInputSchema,
  RequestIpAllowlistBypassInputSchema,
  ApproveIpAllowlistBypassInputSchema,
  parseIpAllowlistPolicy,
  parseIpAllowlistEntry,
  parseIpAllowlistBypassGrant,
  type SetIpAllowlistEnforcementModeInput,
  type AddIpAllowlistEntryInput,
  type RevokeIpAllowlistEntryInput,
  type AssertIpAllowedInput,
  type RequestIpAllowlistBypassInput,
  type ApproveIpAllowlistBypassInput,
  type IpAllowlistPolicy,
  type IpAllowlistEntry,
  type IpAllowlistBypassGrant,
} from "../contracts/ip-restriction/ip-restriction.ts";

export type IpRestrictionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const IP_RESTRICTION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "ip_allowlist_invalid_mode",
  "ip_allowlist_no_active_entries",
  "ip_allowlist_invalid_cidr",
  "ip_allowlist_invalid_scope",
  "ip_allowlist_entry_not_active",
  "ip_not_allowed",
  "ip_bypass_reason_required",
  "ip_bypass_not_pending",
  "ip_bypass_self_approval_forbidden",
] as const;
type KnownIpRestrictionMutationErrorCode = (typeof IP_RESTRICTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type IpRestrictionMutationErrorCode = KnownIpRestrictionMutationErrorCode | "mutation_failed" | "invalid_response";

export class IpRestrictionMutationError extends Error {
  readonly code: IpRestrictionMutationErrorCode;

  constructor(code: IpRestrictionMutationErrorCode, message: string) {
    super(message);
    this.name = "IpRestrictionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): IpRestrictionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (IP_RESTRICTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownIpRestrictionMutationErrorCode)
    : "mutation_failed";
}

export async function setIpAllowlistEnforcementMode(client: IpRestrictionMutationRpcClient, input: SetIpAllowlistEnforcementModeInput): Promise<IpAllowlistPolicy> {
  const parsedInput = SetIpAllowlistEnforcementModeInputSchema.parse(input);
  const { data, error } = await client.rpc("set_ip_allowlist_enforcement_mode", {
    p_tenant_id: parsedInput.tenantId,
    p_enforcement_mode: parsedInput.enforcementMode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionMutationError("invalid_response", "set_ip_allowlist_enforcement_mode returned no row");
  }
  return parseIpAllowlistPolicy(data as Record<string, unknown>);
}

export async function addIpAllowlistEntry(client: IpRestrictionMutationRpcClient, input: AddIpAllowlistEntryInput): Promise<IpAllowlistEntry> {
  const parsedInput = AddIpAllowlistEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("add_ip_allowlist_entry", {
    p_tenant_id: parsedInput.tenantId,
    p_raw_cidr: parsedInput.rawCidr,
    p_label: parsedInput.label,
    p_scope: parsedInput.scope,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionMutationError("invalid_response", "add_ip_allowlist_entry returned no row");
  }
  return parseIpAllowlistEntry(data as Record<string, unknown>);
}

export async function revokeIpAllowlistEntry(client: IpRestrictionMutationRpcClient, input: RevokeIpAllowlistEntryInput): Promise<IpAllowlistEntry> {
  const parsedInput = RevokeIpAllowlistEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_ip_allowlist_entry", {
    p_entry_id: parsedInput.entryId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionMutationError("invalid_response", "revoke_ip_allowlist_entry returned no row");
  }
  return parseIpAllowlistEntry(data as Record<string, unknown>);
}

/** service_role-only -- takes no actor/authority parameter by design (must stay reachable from an API-key-authenticated caller with no auth_user_id at all), so call with a trusted server-side client that has already resolved tenantId through an authorized path, never with an end-user session client. The real enforcement gate: a true no-op while disabled, never denies while dry_run (but logs what it would deny), genuinely denies while enforced. Resolves on success; throws `ip_not_allowed` on a genuine denial. */
export async function assertIpAllowed(client: IpRestrictionMutationRpcClient, input: AssertIpAllowedInput): Promise<void> {
  const parsedInput = AssertIpAllowedInputSchema.parse(input);
  const { error } = await client.rpc("assert_ip_allowed", {
    p_tenant_id: parsedInput.tenantId,
    p_raw_ip_address: parsedInput.rawIpAddress,
    p_scope: parsedInput.scope,
    p_subject_label: parsedInput.subjectLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
}

export async function requestIpAllowlistBypass(client: IpRestrictionMutationRpcClient, input: RequestIpAllowlistBypassInput): Promise<IpAllowlistBypassGrant> {
  const parsedInput = RequestIpAllowlistBypassInputSchema.parse(input);
  const { data, error } = await client.rpc("request_ip_allowlist_bypass", {
    p_tenant_id: parsedInput.tenantId,
    p_target_auth_user_id: parsedInput.targetAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionMutationError("invalid_response", "request_ip_allowlist_bypass returned no row");
  }
  return parseIpAllowlistBypassGrant(data as Record<string, unknown>);
}

/** SEC:Approve-gated; never the same identity that requested it (enforced at the DB CHECK-constraint level). */
export async function approveIpAllowlistBypass(client: IpRestrictionMutationRpcClient, input: ApproveIpAllowlistBypassInput): Promise<IpAllowlistBypassGrant> {
  const parsedInput = ApproveIpAllowlistBypassInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_ip_allowlist_bypass", {
    p_grant_id: parsedInput.grantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IpRestrictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionMutationError("invalid_response", "approve_ip_allowlist_bypass returned no row");
  }
  return parseIpAllowlistBypassGrant(data as Record<string, unknown>);
}
