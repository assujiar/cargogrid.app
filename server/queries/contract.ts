/**
 * Customer Contract and Pricing read queries (COM-156, CG-S7-COM-015). Base-table reads
 * of app.customer_contracts are unmasked (no money columns live there); price component
 * reads go through app.customer_contract_price_components_directory, the one masked path
 * (COM:View selling price), the same posture app.vendor_rate_versions_directory (COM-149)
 * already established on the vendor-cost side.
 */

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

/** Every version of every contract for one tenant, most recently created first -- tenant-wide reference data, RLS-scoped by tenant membership only (not record-scoped). */
export async function listCustomerContracts(client: ContractQueryClient, tenantId: string): Promise<CustomerContract[]> {
  const { data, error } = await client.from("customer_contracts").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCustomerContract(row));
}

/** Every version sharing one root_contract_id, oldest first -- the full version history of one contract. */
export async function listCustomerContractVersions(client: ContractQueryClient, rootContractId: string): Promise<CustomerContract[]> {
  const { data, error } = await client.from("customer_contracts").select("*").eq("root_contract_id", rootContractId).order("version_number", { ascending: true });
  if (error) {
    throw new ContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCustomerContract(row));
}

/** Returns null when not found or RLS denies it (matching every prior Commercial detail-page query's posture). */
export async function getCustomerContractById(client: ContractQueryClient, contractId: string): Promise<CustomerContract | null> {
  const { data, error } = await client.from("customer_contracts").select("*").eq("id", contractId).maybeSingle();
  if (error) {
    throw new ContractQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseCustomerContract(data as Record<string, unknown>);
}

/** Returns null when the quotation has never sourced a contract. */
export async function getCustomerContractForQuotation(client: ContractQueryClient, quotationId: string): Promise<CustomerContract | null> {
  const { data, error } = await client.from("customer_contracts").select("*").eq("source_quotation_id", quotationId).maybeSingle();
  if (error) {
    throw new ContractQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseCustomerContract(data as Record<string, unknown>);
}

/** Masked (COM:View selling price) price components for one contract version, via app.customer_contract_price_components_directory. */
export async function listCustomerContractPriceComponents(client: ContractQueryClient, contractId: string): Promise<CustomerContractPriceComponent[]> {
  const { data, error } = await client.from("customer_contract_price_components_directory").select("*").eq("contract_id", contractId).order("created_at", { ascending: true });
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
