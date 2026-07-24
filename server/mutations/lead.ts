/**
 * Lead Management mutation primitives (COM-143, CG-S7-COM-002). Thin, typed wrappers
 * around app.capture_lead / app.score_lead / app.assign_lead / app.qualify_lead /
 * app.disqualify_lead / app.merge_leads
 * (supabase/migrations/20260723090000_create_commercial_lead_management.sql). Each RPC
 * performs its own entitlement (app.evaluate_permission) and record-scope
 * (app.can_access_record) check in-body -- callable by an `authenticated` client, not
 * service-role-only, since scope varies per lead and per actor.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CaptureLeadInputSchema,
  ScoreLeadInputSchema,
  AssignLeadInputSchema,
  QualifyLeadInputSchema,
  DisqualifyLeadInputSchema,
  MergeLeadsInputSchema,
  parseLead,
  type CaptureLeadInput,
  type ScoreLeadInput,
  type AssignLeadInput,
  type QualifyLeadInput,
  type DisqualifyLeadInput,
  type MergeLeadsInput,
  type Lead,
} from "../contracts/lead/lead.ts";

/** `Pick<SupabaseClient, "rpc">` rather than a hand-rolled shape -- this capability's mutations are called with a real RLS-scoped client from `app/(tenant)/[tenantSlug]/commercial/leads/actions.ts` (unlike the master-data engine's mutations, which are service_role-only and not yet wired to any live route), so the parameter type must structurally match `SupabaseClient.rpc()`'s real (thenable, not a strict `Promise`) return shape. */
export type LeadMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LEAD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "lead_not_found",
  "stale_version",
  "invalid_transition",
  "reason_required",
  "invalid_merge",
  "cross_tenant_merge_denied",
] as const;
type KnownLeadMutationErrorCode = (typeof LEAD_KNOWN_MUTATION_ERROR_CODES)[number];
export type LeadMutationErrorCode = KnownLeadMutationErrorCode | "mutation_failed" | "invalid_response";

export class LeadMutationError extends Error {
  readonly code: LeadMutationErrorCode;

  constructor(code: LeadMutationErrorCode, message: string) {
    super(message);
    this.name = "LeadMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LeadMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (LEAD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownLeadMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseLead(
  client: LeadMutationRpcClient,
  fn: "capture_lead" | "score_lead" | "assign_lead" | "qualify_lead" | "disqualify_lead" | "merge_leads",
  args: Record<string, unknown>,
): Promise<Lead> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LeadMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LeadMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseLead(data as Record<string, unknown>);
}

/** Idempotent for import/api/integration sources (repeated capture with the same externalReference returns the original row). Never blocked by a duplicate candidate -- see findDuplicateLeads/mergeLeads for that flow. */
export async function captureLead(client: LeadMutationRpcClient, input: CaptureLeadInput): Promise<Lead> {
  const parsedInput = CaptureLeadInputSchema.parse(input);
  return callAndParseLead(client, "capture_lead", {
    p_tenant_id: parsedInput.tenantId,
    p_source: parsedInput.source,
    p_external_reference: parsedInput.externalReference,
    p_company_name: parsedInput.companyName,
    p_contact_name: parsedInput.contactName,
    p_email: parsedInput.email,
    p_phone: parsedInput.phone,
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Recomputes and persists the deterministic score/explanation for an already-captured lead. */
export async function scoreLead(client: LeadMutationRpcClient, input: ScoreLeadInput): Promise<Lead> {
  const parsedInput = ScoreLeadInputSchema.parse(input);
  return callAndParseLead(client, "score_lead", {
    p_lead_id: parsedInput.leadId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
}

/** Optimistic-concurrency-checked ownership transfer -- rejects a stale expectedVersion rather than silently overwriting. */
export async function assignLead(client: LeadMutationRpcClient, input: AssignLeadInput): Promise<Lead> {
  const parsedInput = AssignLeadInputSchema.parse(input);
  return callAndParseLead(client, "assign_lead", {
    p_lead_id: parsedInput.leadId,
    p_expected_version: parsedInput.expectedVersion,
    p_new_owner_user_id: parsedInput.newOwnerUserId,
    p_new_org_unit_id: parsedInput.newOrgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** new/contacted -> qualified. Rejects any other starting status. */
export async function qualifyLead(client: LeadMutationRpcClient, input: QualifyLeadInput): Promise<Lead> {
  const parsedInput = QualifyLeadInputSchema.parse(input);
  return callAndParseLead(client, "qualify_lead", {
    p_lead_id: parsedInput.leadId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** new/contacted/qualified -> disqualified. A non-empty reason is required. */
export async function disqualifyLead(client: LeadMutationRpcClient, input: DisqualifyLeadInput): Promise<Lead> {
  const parsedInput = DisqualifyLeadInputSchema.parse(input);
  return callAndParseLead(client, "disqualify_lead", {
    p_lead_id: parsedInput.leadId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Marks duplicateLeadId merged into survivorLeadId (never deleted); returns the survivor. Cross-tenant merges are denied server-side. */
export async function mergeLeads(client: LeadMutationRpcClient, input: MergeLeadsInput): Promise<Lead> {
  const parsedInput = MergeLeadsInputSchema.parse(input);
  return callAndParseLead(client, "merge_leads", {
    p_survivor_lead_id: parsedInput.survivorLeadId,
    p_duplicate_lead_id: parsedInput.duplicateLeadId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
