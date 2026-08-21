"use server";

/**
 * Public API Platform developer console Server Actions (IAE-009, Prompt 337).
 * Reads use the RLS-scoped `authenticated` client (app.list_api_keys_for_tenant /
 * app.list_api_logs_for_tenant / app.list_api_versions are all `authenticated`-callable,
 * SECURITY DEFINER, authority-gated in-body). Key/webhook-endpoint lifecycle mutations
 * (app.create_api_key/app.rotate_api_key/app.revoke_api_key -- PLT-129) are
 * `service_role`-only, so those use the service-role client instead, the same
 * "explicit actor, service-role execution" pattern
 * app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts already
 * established -- never a new SECURITY DEFINER proxy for an already-server-mediated
 * capability.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createApiKey, rotateApiKey, revokeApiKey, ApiKeyWebhookMutationError, type ApiKeyWebhookMutationRpcClient } from "../../../../../server/mutations/api-key-webhook.ts";
import type { CreatedApiKey } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";

export interface ApiKeyFormState {
  readonly error: string | null;
  readonly createdKey: CreatedApiKey | null;
}

const OK: ApiKeyFormState = { error: null, createdKey: null };
const NO_ACCESS: ApiKeyFormState = { error: "You don't have access to this organization's admin workspace.", createdKey: null };

function toApiKeyWebhookClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): ApiKeyWebhookMutationRpcClient {
  return client as unknown as ApiKeyWebhookMutationRpcClient;
}

function parseScopes(raw: FormDataEntryValue | null): string[] {
  return String(raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export async function createApiKeyAction(tenantSlug: string, _prevState: ApiKeyFormState, formData: FormData): Promise<ApiKeyFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  if (name.length === 0) return { error: "A key name is required.", createdKey: null };

  const scopes = parseScopes(formData.get("scopes"));
  if (scopes.length === 0) return { error: "At least one scope is required (e.g. INTHUB:View).", createdKey: null };

  const rateLimitRaw = String(formData.get("rateLimitPerMinute") ?? "").trim();
  const rateLimitPerMinute = rateLimitRaw.length > 0 ? Number(rateLimitRaw) : null;
  if (rateLimitPerMinute !== null && (!Number.isFinite(rateLimitPerMinute) || rateLimitPerMinute <= 0)) {
    return { error: "Rate limit per minute must be a positive number, or left blank for unlimited.", createdKey: null };
  }

  const expiresRaw = String(formData.get("expiresAt") ?? "").trim();
  const expiresAt = expiresRaw.length > 0 ? new Date(expiresRaw).toISOString() : null;

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  let createdKey: CreatedApiKey;
  try {
    createdKey = await createApiKey(client, {
      tenantId: access.tenant.id,
      name,
      scopes,
      expiresAt,
      rateLimitPerMinute,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not create this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdKey };
}

export async function rotateApiKeyAction(tenantSlug: string, keyId: string, _prevState: ApiKeyFormState, formData: FormData): Promise<ApiKeyFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const overlapRaw = String(formData.get("overlapMinutes") ?? "0").trim();
  const overlapMinutes = Number(overlapRaw);
  if (!Number.isFinite(overlapMinutes) || overlapMinutes < 0 || overlapMinutes > 10080) {
    return { error: "Overlap window must be between 0 (immediate revoke) and 10080 minutes (7 days).", createdKey: null };
  }

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  let rotatedKey: CreatedApiKey;
  try {
    rotatedKey = await rotateApiKey(client, { keyId, overlapMinutes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not rotate this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdKey: rotatedKey };
}

export async function revokeApiKeyAction(tenantSlug: string, keyId: string, _prevState: ApiKeyFormState, formData: FormData): Promise<ApiKeyFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  try {
    await revokeApiKey(client, { keyId, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not revoke this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return OK;
}
