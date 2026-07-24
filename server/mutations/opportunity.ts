/**
 * Opportunity Management mutation primitives (COM-147, CG-S7-COM-006). Thin, typed
 * wrappers around app.create_opportunity / app.update_opportunity /
 * app.transition_opportunity_stage / app.clone_opportunity
 * (supabase/migrations/20260723210000_create_commercial_opportunity_management.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateOpportunityInputSchema,
  UpdateOpportunityInputSchema,
  TransitionOpportunityStageInputSchema,
  CloneOpportunityInputSchema,
  toRequirementsJson,
  parseOpportunity,
  type CreateOpportunityInput,
  type UpdateOpportunityInput,
  type TransitionOpportunityStageInput,
  type CloneOpportunityInput,
  type Opportunity,
} from "../contracts/opportunity/opportunity.ts";

export type OpportunityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const OPPORTUNITY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "prospect_not_found",
  "opportunity_not_found",
  "cross_tenant_prospect_denied",
  "stale_version",
  "invalid_transition",
  "invalid_stage",
  "invalid_probability",
  "reason_required",
] as const;
type KnownOpportunityMutationErrorCode = (typeof OPPORTUNITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type OpportunityMutationErrorCode = KnownOpportunityMutationErrorCode | "mutation_failed" | "invalid_response";

export class OpportunityMutationError extends Error {
  readonly code: OpportunityMutationErrorCode;

  constructor(code: OpportunityMutationErrorCode, message: string) {
    super(message);
    this.name = "OpportunityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OpportunityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (OPPORTUNITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownOpportunityMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseOpportunity(client: OpportunityMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Opportunity> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new OpportunityMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new OpportunityMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseOpportunity(data as Record<string, unknown>);
}

/** Always creates a new opportunity -- no external idempotency key exists (it originates from an internal prospect). Starts at stage=qualifying, probability=10. */
export async function createOpportunity(client: OpportunityMutationRpcClient, input: CreateOpportunityInput): Promise<Opportunity> {
  const parsedInput = CreateOpportunityInputSchema.parse(input);
  return callAndParseOpportunity(client, "create_opportunity", {
    p_tenant_id: parsedInput.tenantId,
    p_prospect_id: parsedInput.prospectId,
    p_name: parsedInput.name,
    p_requirements: toRequirementsJson(parsedInput.requirements),
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Blocked once stage is won/lost. Setting a new/changed valueAmount or valueCurrency additionally requires COM:View selling price. */
export async function updateOpportunity(client: OpportunityMutationRpcClient, input: UpdateOpportunityInput): Promise<Opportunity> {
  const parsedInput = UpdateOpportunityInputSchema.parse(input);
  return callAndParseOpportunity(client, "update_opportunity", {
    p_opportunity_id: parsedInput.opportunityId,
    p_expected_version: parsedInput.expectedVersion,
    p_name: parsedInput.name,
    p_requirements: toRequirementsJson(parsedInput.requirements),
    p_next_action: parsedInput.nextAction,
    p_next_action_due_at: parsedInput.nextActionDueAt,
    p_value_amount: parsedInput.valueAmount,
    p_value_currency: parsedInput.valueCurrency,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Closing to won/lost requires COM:Approve and a non-empty closeReason; any other move requires COM:Edit. probability defaults deterministically per stage unless overridden. */
export async function transitionOpportunityStage(client: OpportunityMutationRpcClient, input: TransitionOpportunityStageInput): Promise<Opportunity> {
  const parsedInput = TransitionOpportunityStageInputSchema.parse(input);
  return callAndParseOpportunity(client, "transition_opportunity_stage", {
    p_opportunity_id: parsedInput.opportunityId,
    p_expected_version: parsedInput.expectedVersion,
    p_new_stage: parsedInput.newStage,
    p_probability: parsedInput.probability,
    p_close_reason: parsedInput.closeReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Always creates a new row (never idempotent -- cloning the same source twice is a legitimate distinct action). Resets stage/probability to the create defaults. */
export async function cloneOpportunity(client: OpportunityMutationRpcClient, input: CloneOpportunityInput): Promise<Opportunity> {
  const parsedInput = CloneOpportunityInputSchema.parse(input);
  return callAndParseOpportunity(client, "clone_opportunity", {
    p_opportunity_id: parsedInput.opportunityId,
    p_name: parsedInput.name,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}
