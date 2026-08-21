/**
 * Customer API read queries (IAE-010, Prompt 338). Thin, typed wrapper around
 * app.list_customer_api_keys_for_account
 * (supabase/migrations/20260804020000_create_intelligence_customer_api.sql).
 * SECURITY DEFINER, granted to authenticated (account_admin self-service) and
 * service_role.
 */

import { ListCustomerApiKeysForAccountInputSchema, parseCustomerApiKey, type ListCustomerApiKeysForAccountInput, type CustomerApiKey } from "../contracts/customer-api/customer-api.ts";

export interface CustomerApiQueryRpcClient {
  rpc(fn: "list_customer_api_keys_for_account", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class CustomerApiQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerApiQueryError";
  }
}

/** Scoped to EXACTLY one account's own customer keys -- never a tenant-wide listing. */
export async function listCustomerApiKeysForAccount(client: CustomerApiQueryRpcClient, input: ListCustomerApiKeysForAccountInput): Promise<CustomerApiKey[]> {
  const parsedInput = ListCustomerApiKeysForAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("list_customer_api_keys_for_account", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new CustomerApiQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new CustomerApiQueryError("list_customer_api_keys_for_account returned a non-array result");
  }
  return data.map((row) => parseCustomerApiKey(row as Record<string, unknown>));
}
