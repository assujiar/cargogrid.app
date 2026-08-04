/**
 * Customer Inventory Access mutation primitives (ATW-023, CG-S10-ATW-023). Thin,
 * typed wrapper around app.export_customer_inventory_snapshot
 * (supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql)
 * -- the one RPC in this capability that has a real, audited side effect (every call
 * captures an app.audit_logs row, migration design note 9), placed in mutations
 * rather than queries for that reason even though it never writes inventory state.
 *
 * app.grant_warehouse_customer_eligibility/app.revoke_warehouse_customer_eligibility
 * (ATW-229) are NOT wrapped here -- server/mutations/warehouse-zone.ts already exposes
 * both (grantWarehouseCustomerEligibility/revokeWarehouseCustomerEligibility), so no
 * duplicate wrapper is added by this migration's own service layer.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ExportCustomerInventorySnapshotInputSchema,
  parseCustomerInventoryBalance,
  type ExportCustomerInventorySnapshotInput,
  type CustomerInventoryBalance,
} from "../contracts/customer-inventory-access/customer-inventory-access.ts";

export type CustomerInventoryAccessMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_INVENTORY_ACCESS_KNOWN_MUTATION_ERROR_CODES = [] as const;
type KnownCustomerInventoryAccessMutationErrorCode = (typeof CUSTOMER_INVENTORY_ACCESS_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerInventoryAccessMutationErrorCode = KnownCustomerInventoryAccessMutationErrorCode | "mutation_failed" | "invalid_response";

export class CustomerInventoryAccessMutationError extends Error {
  readonly code: CustomerInventoryAccessMutationErrorCode;

  constructor(code: CustomerInventoryAccessMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerInventoryAccessMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerInventoryAccessMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CUSTOMER_INVENTORY_ACCESS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCustomerInventoryAccessMutationErrorCode)
    : "mutation_failed";
}

/**
 * Bounded, single-shot snapshot export (p_limit default 500, hard-capped 1000
 * server-side -- never OFFSET, no cursor, an export not a list). Always audits
 * (actor, requested scope, result count, never the row payload) regardless of how
 * many rows matched. Same owner+warehouse-eligibility scope and column projection as
 * app.list_customer_inventory_balances. A genuinely async/streaming large-volume
 * export pipeline remains Step 13 Portal scope (migration design note above the
 * function).
 */
export async function exportCustomerInventorySnapshot(
  client: CustomerInventoryAccessMutationRpcClient,
  input: ExportCustomerInventorySnapshotInput,
): Promise<CustomerInventoryBalance[]> {
  const parsedInput = ExportCustomerInventorySnapshotInputSchema.parse(input);
  const { data, error } = await client.rpc("export_customer_inventory_snapshot", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_warehouse_id: parsedInput.warehouseId ?? null,
    p_item_master_id: parsedInput.itemMasterId ?? null,
    p_limit: parsedInput.limit ?? 500,
    p_actor_label: parsedInput.actorLabel ?? null,
  });
  if (error) {
    throw new CustomerInventoryAccessMutationError(classifyError(error.message), error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerInventoryBalance);
}
