/**
 * Customer Contract and Pricing read queries (COM-156, CG-S7-COM-015). Base-table reads
 * of app.customer_contracts are unmasked (no money columns live there); price component
 * reads go through app.customer_contract_price_components_directory, the one masked path
 * (COM:View selling price), the same posture app.vendor_rate_versions_directory (COM-149)
 * already established on the vendor-cost side.
 */

import { BOUNDED_LIST_LIMIT, toBoundedListByCapReached, type BoundedList } from "./bounded-list.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GetEffectiveCustomerPriceInputSchema,
  parseCustomerContract,
  parseCustomerContractPriceComponent,
  parseEffectiveCustomerPrice,
  type GetEffectiveCustomerPriceInput,
  type CustomerContract,
  type CustomerContractPriceComponent,
  type EffectiveCustomerPrice,
} from "../contracts/contract/contract.ts";

export type ContractQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class ContractQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ContractQueryError";
  }
}

/** Every version of every contract for one tenant, most recently created first -- app.list_customer_contracts (SECURITY DEFINER) is the real scope gate (tenant membership, excluding the customer_user layer). */
export async function listCustomerContracts(client: ContractQueryClient, tenantId: string, actorAuthUserId: string): Promise<BoundedList<CustomerContract>> {
  const { data, error } = await client.rpc("list_customer_contracts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: BOUNDED_LIST_LIMIT,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  return toBoundedListByCapReached(((data as unknown[] | null) ?? []).map((row) => parseCustomerContract(row as Record<string, unknown>)));
}

/** Every version sharing one root_contract_id, oldest first -- the full version history of one contract. */
export async function listCustomerContractVersions(client: ContractQueryClient, rootContractId: string, actorAuthUserId: string): Promise<CustomerContract[]> {
  const { data, error } = await client.rpc("list_customer_contract_versions", {
    p_root_contract_id: rootContractId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCustomerContract(row));
}

/** Returns null when not found or denied (matching every prior Commercial detail-page query's posture). */
export async function getCustomerContractById(client: ContractQueryClient, contractId: string, actorAuthUserId: string): Promise<CustomerContract | null> {
  const { data, error } = await client.rpc("get_customer_contract_by_id", {
    p_contract_id: contractId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseCustomerContract(row as Record<string, unknown>);
}

/** Returns null when the quotation has never sourced a contract. */
export async function getCustomerContractForQuotation(client: ContractQueryClient, quotationId: string, actorAuthUserId: string): Promise<CustomerContract | null> {
  const { data, error } = await client.rpc("get_customer_contract_for_quotation", {
    p_source_quotation_id: quotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseCustomerContract(row as Record<string, unknown>);
}

/** Masked (COM:View selling price) price components for one contract version, via app.list_customer_contract_price_components (SECURITY DEFINER restatement of app.customer_contract_price_components_directory). */
export async function listCustomerContractPriceComponents(client: ContractQueryClient, contractId: string, actorAuthUserId: string): Promise<CustomerContractPriceComponent[]> {
  const { data, error } = await client.rpc("list_customer_contract_price_components", {
    p_contract_id: contractId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCustomerContractPriceComponent(row));
}

/** The deterministic effective-price lookup (Prompt 156's own objective). asOf defaults to "now" resolved here in JS -- the underlying RPC's own `default now()` only applies when an argument is omitted entirely, never when explicitly passed as null. */
export async function getEffectiveCustomerPrice(client: ContractQueryClient, input: GetEffectiveCustomerPriceInput): Promise<EffectiveCustomerPrice> {
  const parsedInput = GetEffectiveCustomerPriceInputSchema.parse(input);
  const { data, error } = await client.rpc("get_effective_customer_price", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_service_type: parsedInput.serviceType,
    p_mode: parsedInput.mode,
    p_origin_lane: parsedInput.originLane,
    p_destination_lane: parsedInput.destinationLane,
    p_equipment_type: parsedInput.equipmentType,
    p_as_of: parsedInput.asOf ?? new Date().toISOString(),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ContractQueryError("get_effective_customer_price returned no row");
  }
  return parseEffectiveCustomerPrice(row as Record<string, unknown>);
}
