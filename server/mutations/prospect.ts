/**
 * Prospect Lifecycle mutation primitives (COM-144, CG-S7-COM-003). Thin, typed wrappers
 * around app.convert_lead_to_prospect / app.link_lead_to_existing_prospect /
 * app.disqualify_prospect / app.archive_prospect / app.merge_prospects
 * (supabase/migrations/20260723120000_create_commercial_prospect_lifecycle.sql). Each RPC
 * performs its own entitlement/record-scope check in-body -- callable by an
 * `authenticated` client, the same convention server/mutations/lead.ts established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ConvertLeadToProspectInputSchema,
  LinkLeadToExistingProspectInputSchema,
  DisqualifyProspectInputSchema,
  ArchiveProspectInputSchema,
  MergeProspectsInputSchema,
  parseProspect,
  type ConvertLeadToProspectInput,
  type LinkLeadToExistingProspectInput,
  type DisqualifyProspectInput,
  type ArchiveProspectInput,
  type MergeProspectsInput,
  type Prospect,
} from "../contracts/prospect/prospect.ts";

export type ProspectMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PROSPECT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "lead_not_found",
  "prospect_not_found",
  "invalid_transition",
  "invalid_link",
  "stale_version",
  "reason_required",
  "invalid_merge",
  "cross_tenant_merge_denied",
  "cross_tenant_link_denied",
] as const;
type KnownProspectMutationErrorCode = (typeof PROSPECT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ProspectMutationErrorCode = KnownProspectMutationErrorCode | "mutation_failed" | "invalid_response";

export class ProspectMutationError extends Error {
  readonly code: ProspectMutationErrorCode;

  constructor(code: ProspectMutationErrorCode, message: string) {
    super(message);
    this.name = "ProspectMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ProspectMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PROSPECT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownProspectMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseProspect(
  client: ProspectMutationRpcClient,
  fn: "convert_lead_to_prospect" | "link_lead_to_existing_prospect" | "disqualify_prospect" | "archive_prospect" | "merge_prospects",
  args: Record<string, unknown>,
): Promise<Prospect> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ProspectMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ProspectMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseProspect(data as Record<string, unknown>);
}

/** Idempotent on leadId -- a retried call returns the original prospect. Requires the source lead to be status=qualified. */
export async function convertLeadToProspect(client: ProspectMutationRpcClient, input: ConvertLeadToProspectInput): Promise<Prospect> {
  const parsedInput = ConvertLeadToProspectInputSchema.parse(input);
  return callAndParseProspect(client, "convert_lead_to_prospect", {
    p_lead_id: parsedInput.leadId,
    p_legal_name: parsedInput.legalName,
    p_trade_name: parsedInput.tradeName,
    p_tax_id: parsedInput.taxId,
    p_billing_address: parsedInput.billingAddress,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Alternative flow -- links a qualified lead to an existing, accessible prospect instead of creating a new one. */
export async function linkLeadToExistingProspect(client: ProspectMutationRpcClient, input: LinkLeadToExistingProspectInput): Promise<Prospect> {
  const parsedInput = LinkLeadToExistingProspectInputSchema.parse(input);
  return callAndParseProspect(client, "link_lead_to_existing_prospect", {
    p_lead_id: parsedInput.leadId,
    p_prospect_id: parsedInput.prospectId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** active -> disqualified. A non-empty reason is required. */
export async function disqualifyProspect(client: ProspectMutationRpcClient, input: DisqualifyProspectInput): Promise<Prospect> {
  const parsedInput = DisqualifyProspectInputSchema.parse(input);
  return callAndParseProspect(client, "disqualify_prospect", {
    p_prospect_id: parsedInput.prospectId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** active -> archived. No reason required -- distinct from disqualify (a commercial-fit judgment). */
export async function archiveProspect(client: ProspectMutationRpcClient, input: ArchiveProspectInput): Promise<Prospect> {
  const parsedInput = ArchiveProspectInputSchema.parse(input);
  return callAndParseProspect(client, "archive_prospect", {
    p_prospect_id: parsedInput.prospectId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Marks duplicateProspectId merged into survivorProspectId (never deleted); returns the survivor. Cross-tenant merges are denied server-side. */
export async function mergeProspects(client: ProspectMutationRpcClient, input: MergeProspectsInput): Promise<Prospect> {
  const parsedInput = MergeProspectsInputSchema.parse(input);
  return callAndParseProspect(client, "merge_prospects", {
    p_survivor_prospect_id: parsedInput.survivorProspectId,
    p_duplicate_prospect_id: parsedInput.duplicateProspectId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
