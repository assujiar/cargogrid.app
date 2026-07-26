/**
 * Customer Contract and Pricing mutation primitives (COM-156, CG-S7-COM-015). Thin,
 * typed wrappers around the five RPCs
 * supabase/migrations/20260724300000_create_commercial_customer_contract_pricing.sql
 * defines.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateCustomerContractDraftInputSchema,
  AddCustomerContractPriceComponentInputSchema,
  RemoveCustomerContractPriceComponentInputSchema,
  PublishCustomerContractInputSchema,
  RetireCustomerContractInputSchema,
  parseCustomerContract,
  parseCustomerContractPriceComponent,
  type CreateCustomerContractDraftInput,
  type AddCustomerContractPriceComponentInput,
  type RemoveCustomerContractPriceComponentInput,
  type PublishCustomerContractInput,
  type RetireCustomerContractInput,
  type CustomerContract,
  type CustomerContractPriceComponent,
} from "../contracts/contract/contract.ts";

export type ContractMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CONTRACT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_not_found",
  "quotation_not_accepted",
  "quotation_not_converted",
  "quotation_already_contracted",
  "contract_not_found",
  "invalid_source",
  "invalid_validity",
  "reason_required",
  "price_component_not_found",
  "invalid_transition",
  "stale_version",
  "no_price_components",
  "overlapping_active_version",
  "invalid_currency",
  "invalid_service_type",
] as const;
type KnownContractMutationErrorCode = (typeof CONTRACT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ContractMutationErrorCode = KnownContractMutationErrorCode | "mutation_failed" | "invalid_response";

export class ContractMutationError extends Error {
  readonly code: ContractMutationErrorCode;

  constructor(code: ContractMutationErrorCode, message: string) {
    super(message);
    this.name = "ContractMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ContractMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CONTRACT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownContractMutationErrorCode) : "mutation_failed";
}

/** Main flow (sourceQuotationId set) requires an accepted, already-converted (COM-155) quotation -- one contract root per source quotation, ever. Alternative flow (sourceContractId set) is a renewal/amendment: copies the source version's own price components into the new draft. */
export async function createCustomerContractDraft(client: ContractMutationRpcClient, input: CreateCustomerContractDraftInput): Promise<CustomerContract> {
  const parsedInput = CreateCustomerContractDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_customer_contract_draft", {
    p_source_quotation_id: parsedInput.sourceQuotationId,
    p_source_contract_id: parsedInput.sourceContractId,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_amendment_reason: parsedInput.amendmentReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ContractMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ContractMutationError("invalid_response", "create_customer_contract_draft returned no row");
  }
  return parseCustomerContract(data as Record<string, unknown>);
}

/** Only while the owning contract is status=draft. The identity unique index surfaces a real unique_violation on a duplicate service/lane/mode/equipment combination. */
export async function addCustomerContractPriceComponent(client: ContractMutationRpcClient, input: AddCustomerContractPriceComponentInput): Promise<CustomerContractPriceComponent> {
  const parsedInput = AddCustomerContractPriceComponentInputSchema.parse(input);
  const { data, error } = await client.rpc("add_customer_contract_price_component", {
    p_contract_id: parsedInput.contractId,
    p_service_type: parsedInput.serviceType,
    p_mode: parsedInput.mode,
    p_origin_lane: parsedInput.originLane,
    p_destination_lane: parsedInput.destinationLane,
    p_equipment_type: parsedInput.equipmentType,
    p_currency: parsedInput.currency,
    p_base_amount: parsedInput.baseAmount,
    p_minimum_amount: parsedInput.minimumAmount,
    p_discount_pct: parsedInput.discountPct,
    p_surcharge_components: parsedInput.surchargeComponents,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ContractMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ContractMutationError("invalid_response", "add_customer_contract_price_component returned no row");
  }
  return parseCustomerContractPriceComponent({ ...(data as Record<string, unknown>), price_masked: false });
}

export async function removeCustomerContractPriceComponent(client: ContractMutationRpcClient, input: RemoveCustomerContractPriceComponentInput): Promise<void> {
  const parsedInput = RemoveCustomerContractPriceComponentInputSchema.parse(input);
  const { error } = await client.rpc("remove_customer_contract_price_component", {
    p_component_id: parsedInput.componentId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ContractMutationError(classifyError(error.message), error.message);
  }
}

/** COM:Approve-gated (governance-weighted, hard-to-reverse). Requires >=1 price component and no date-overlapping already-published sibling under the same root_contract_id. */
export async function publishCustomerContract(client: ContractMutationRpcClient, input: PublishCustomerContractInput): Promise<CustomerContract> {
  const parsedInput = PublishCustomerContractInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_customer_contract", {
    p_contract_id: parsedInput.contractId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ContractMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ContractMutationError("invalid_response", "publish_customer_contract returned no row");
  }
  return parseCustomerContract(data as Record<string, unknown>);
}

/** COM:Approve-gated, mandatory reason. Only a published contract may be retired. */
export async function retireCustomerContract(client: ContractMutationRpcClient, input: RetireCustomerContractInput): Promise<CustomerContract> {
  const parsedInput = RetireCustomerContractInputSchema.parse(input);
  const { data, error } = await client.rpc("retire_customer_contract", {
    p_contract_id: parsedInput.contractId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ContractMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ContractMutationError("invalid_response", "retire_customer_contract returned no row");
  }
  return parseCustomerContract(data as Record<string, unknown>);
}
