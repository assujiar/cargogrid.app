"use server";

/**
 * Customer API key self-service Server Actions (IAE-010, Prompt 338). Mirrors
 * customer-portal-users/actions.ts's own shape exactly. Every write is scope/
 * authority-gated at the RPC layer itself (app.actor_is_active_customer_portal_
 * account_admin, composed via app.create_customer_api_key/app.check_api_key_
 * manage_authority) -- this file never re-derives or trusts a client-supplied
 * authority decision, it only forwards. Uses the RLS-scoped `authenticated`
 * client throughout -- every RPC below (including PLT-129's own revoke/rotate,
 * widened by this migration to grant authenticated) is directly callable by a
 * real customer_user session.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createCustomerApiKey, CustomerApiMutationError, type CustomerApiMutationRpcClient } from "../../../../server/mutations/customer-api.ts";
import { revokeApiKey, rotateApiKey, ApiKeyWebhookMutationError, type ApiKeyWebhookMutationRpcClient } from "../../../../server/mutations/api-key-webhook.ts";
import type { CreatedCustomerApiKey } from "../../../../server/contracts/customer-api/customer-api.ts";
import type { CreatedApiKey } from "../../../../server/contracts/api-key-webhook/api-key-webhook.ts";

export interface CustomerApiKeyActionState {
  readonly error: string | null;
  readonly createdKey: CreatedCustomerApiKey | CreatedApiKey | null;
}

const OK: CustomerApiKeyActionState = { error: null, createdKey: null };
const NO_ACCESS: CustomerApiKeyActionState = { error: "You don't have access to this organization's customer portal.", createdKey: null };

/** `SupabaseClient.rpc()` returns a `PostgrestFilterBuilder` (thenable, not structurally a `Promise`) -- the same cast `app/(tenant)/[tenantSlug]/admin/api-keys/page.tsx`'s own `toQueryClient()` already established for this exact mismatch. */
function toRpcClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): CustomerApiMutationRpcClient & ApiKeyWebhookMutationRpcClient {
  return client as unknown as CustomerApiMutationRpcClient & ApiKeyWebhookMutationRpcClient;
}

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function apiKeysPath(tenantSlug: string, accountId: string): string {
  return `/${tenantSlug}/customer-portal-api-keys?accountId=${accountId}`;
}

export async function createCustomerApiKeyAction(tenantSlug: string, accountId: string, _prevState: CustomerApiKeyActionState, formData: FormData): Promise<CustomerApiKeyActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  if (name.length === 0) return { error: "A key name is required.", createdKey: null };

  const rateLimitRaw = String(formData.get("rateLimitPerMinute") ?? "").trim();
  const rateLimitPerMinute = rateLimitRaw.length > 0 ? Number(rateLimitRaw) : null;
  if (rateLimitPerMinute !== null && (!Number.isFinite(rateLimitPerMinute) || rateLimitPerMinute <= 0)) {
    return { error: "Rate limit per minute must be a positive number, or left blank for unlimited.", createdKey: null };
  }

  const supabase = await createSupabaseServerClient();
  let createdKey: CreatedCustomerApiKey;
  try {
    createdKey = await createCustomerApiKey(toRpcClient(supabase), {
      tenantId: access.tenant.id,
      accountId,
      customerActorAuthUserId: access.authUserId,
      name,
      expiresAt: null,
      rateLimitPerMinute,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CustomerApiMutationError) return { error: `Could not create this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(apiKeysPath(tenantSlug, accountId));
  return { error: null, createdKey };
}

export async function rotateCustomerApiKeyAction(tenantSlug: string, accountId: string, keyId: string, _prevState: CustomerApiKeyActionState, formData: FormData): Promise<CustomerApiKeyActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const overlapRaw = String(formData.get("overlapMinutes") ?? "0").trim();
  const overlapMinutes = Number(overlapRaw);
  if (!Number.isFinite(overlapMinutes) || overlapMinutes < 0 || overlapMinutes > 10080) {
    return { error: "Overlap window must be between 0 (immediate revoke) and 10080 minutes (7 days).", createdKey: null };
  }

  const supabase = await createSupabaseServerClient();
  let rotatedKey: CreatedApiKey;
  try {
    rotatedKey = await rotateApiKey(toRpcClient(supabase), { keyId, overlapMinutes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not rotate this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(apiKeysPath(tenantSlug, accountId));
  return { error: null, createdKey: rotatedKey };
}

export async function revokeCustomerApiKeyAction(tenantSlug: string, accountId: string, keyId: string, _prevState: CustomerApiKeyActionState, formData: FormData): Promise<CustomerApiKeyActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await revokeApiKey(toRpcClient(supabase), { keyId, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not revoke this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(apiKeysPath(tenantSlug, accountId));
  return OK;
}
