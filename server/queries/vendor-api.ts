/**
 * Vendor API query entry points (IAE-011, Prompt 339). Thin, typed wrappers
 * around app.list_vendor_api_keys_for_tenant / app.get_rfq_for_vendor_api
 * (supabase/migrations/20260804030000_create_intelligence_vendor_api.sql).
 */

import { ListVendorApiKeysForTenantInputSchema, parseVendorApiKey, parseRfqForVendorApi, type ListVendorApiKeysForTenantInput, type VendorApiKey, type RfqForVendorApi } from "../contracts/vendor-api/vendor-api.ts";

export interface VendorApiQueryRpcClient {
  rpc(fn: "list_vendor_api_keys_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class VendorApiQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorApiQueryError";
  }
}

/** Authority: Supreme or the tenant's own active tenant_admin (app.check_api_webhook_admin_authority). */
export async function listVendorApiKeysForTenant(client: VendorApiQueryRpcClient, input: ListVendorApiKeysForTenantInput): Promise<VendorApiKey[]> {
  const parsedInput = ListVendorApiKeysForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_vendor_api_keys_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new VendorApiQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorApiKey);
}

export interface VendorApiRpcClient {
  rpc(fn: "get_rfq_for_vendor_api", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class VendorApiError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorApiError";
  }
}

/** Authority: vendor-scope containment -- the invitation's own vendor_master_id must equal the presented key's own vendor_master_record_id. Anti-enumeration: a mismatched or nonexistent invitation gets the same rfq_invitation_not_found either way. */
export async function getRfqForVendorApi(client: VendorApiRpcClient, tenantId: string, vendorMasterRecordId: string, rfqInvitationId: string): Promise<RfqForVendorApi> {
  const { data, error } = await client.rpc("get_rfq_for_vendor_api", {
    p_tenant_id: tenantId,
    p_vendor_master_record_id: vendorMasterRecordId,
    p_rfq_invitation_id: rfqInvitationId,
  });
  if (error) {
    throw new VendorApiError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorApiError("get_rfq_for_vendor_api returned no row");
  }
  return parseRfqForVendorApi(row as Record<string, unknown>);
}
