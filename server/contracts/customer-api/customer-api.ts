/**
 * Customer API contract (IAE-010, Prompt 338). Mirrors
 * supabase/migrations/20260804020000_create_intelligence_customer_api.sql's
 * additive app.api_keys.customer_account_id/customer_actor_auth_user_id columns
 * and the app.create_customer_api_key / app.list_customer_api_keys_for_account
 * RPCs. Revoke/rotate reuse ../api-key-webhook/api-key-webhook.ts's own
 * RevokeApiKeyInputSchema/RotateApiKeyInputSchema/revokeApiKey/rotateApiKey
 * directly (PLT-129, extended in-place by this migration to compose the new
 * customer-account_admin authority path) -- not re-declared here.
 */

import { z } from "zod";

export const CustomerApiKeySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  keyPrefix: z.string(),
  scopes: z.array(z.string()),
  status: z.enum(["active", "revoked", "expired"]),
  rateLimitPerMinute: z.number().int().positive().nullable(),
  expiresAt: z.string().nullable(),
  lastUsedAt: z.string().nullable().optional(),
  createdAt: z.string(),
  updatedAt: z.string().optional(),
  customerAccountId: z.string().uuid(),
  customerActorAuthUserId: z.string().uuid(),
});
export type CustomerApiKey = z.infer<typeof CustomerApiKeySchema>;

export const CreatedCustomerApiKeySchema = CustomerApiKeySchema.extend({ rawKey: z.string() });
export type CreatedCustomerApiKey = z.infer<typeof CreatedCustomerApiKeySchema>;

export const CreateCustomerApiKeyInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  customerActorAuthUserId: z.string().uuid(),
  name: z.string().min(1),
  expiresAt: z.string().nullable().default(null),
  rateLimitPerMinute: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateCustomerApiKeyInput = z.input<typeof CreateCustomerApiKeyInputSchema>;

export const ListCustomerApiKeysForAccountInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListCustomerApiKeysForAccountInput = z.input<typeof ListCustomerApiKeysForAccountInputSchema>;

export function parseCustomerApiKey(row: Record<string, unknown>): CustomerApiKey {
  return CustomerApiKeySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    expiresAt: row.expires_at,
    lastUsedAt: row.last_used_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    customerAccountId: row.customer_account_id,
    customerActorAuthUserId: row.customer_actor_auth_user_id,
  });
}

/** Maps app.create_customer_api_key()'s one-time return row, including raw_key. */
export function parseCreatedCustomerApiKey(row: Record<string, unknown>): CreatedCustomerApiKey {
  return CreatedCustomerApiKeySchema.parse({ ...parseCustomerApiKey(row), rawKey: row.raw_key });
}
