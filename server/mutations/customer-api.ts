/**
 * Customer API mutation entry points (IAE-010, Prompt 338). Thin, typed
 * wrapper around app.create_customer_api_key
 * (supabase/migrations/20260804020000_create_intelligence_customer_api.sql).
 * Revoke/rotate reuse ../mutations/api-key-webhook.ts's own revokeApiKey/
 * rotateApiKey directly -- PLT-129's own app.revoke_api_key/app.rotate_api_key
 * are extended in-place by this migration to compose the new customer-
 * account_admin authority path, never forked.
 */

import {
  CreateCustomerApiKeyInputSchema,
  parseCreatedCustomerApiKey,
  type CreateCustomerApiKeyInput,
  type CreatedCustomerApiKey,
} from "../contracts/customer-api/customer-api.ts";

export interface CustomerApiMutationRpcClient {
  rpc(fn: "create_customer_api_key", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const CUSTOMER_API_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "account_not_available",
  "api_key_missing_name",
  "api_key_invalid_rate_limit",
  "api_key_invalid_expiry",
] as const;
type KnownCustomerApiMutationErrorCode = (typeof CUSTOMER_API_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerApiMutationErrorCode = KnownCustomerApiMutationErrorCode | "mutation_failed" | "invalid_response";

export class CustomerApiMutationError extends Error {
  readonly code: CustomerApiMutationErrorCode;

  constructor(code: CustomerApiMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerApiMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerApiMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CUSTOMER_API_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCustomerApiMutationErrorCode)
    : "mutation_failed";
}

/** Authority: the target account's own active account_admin (self-service), or Supreme/tenant_admin (support/bootstrap, naming a real member on the customer's behalf). Returns the raw key exactly once. */
export async function createCustomerApiKey(client: CustomerApiMutationRpcClient, input: CreateCustomerApiKeyInput): Promise<CreatedCustomerApiKey> {
  const parsedInput = CreateCustomerApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("create_customer_api_key", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_customer_actor_auth_user_id: parsedInput.customerActorAuthUserId,
    p_name: parsedInput.name,
    p_expires_at: parsedInput.expiresAt,
    p_rate_limit_per_minute: parsedInput.rateLimitPerMinute,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CustomerApiMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerApiMutationError("invalid_response", "create_customer_api_key returned no row");
  }
  return parseCreatedCustomerApiKey(row as Record<string, unknown>);
}
