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
import { createApiKey, rotateApiKey, revokeApiKey, registerWebhookEndpoint, rotateWebhookSecret, disableWebhookEndpoint, reenableWebhookEndpoint, ApiKeyWebhookMutationError, type ApiKeyWebhookMutationRpcClient } from "../../../../../server/mutations/api-key-webhook.ts";
import { createVendorApiKey, VendorApiMutationError, type VendorApiMutationRpcClient } from "../../../../../server/mutations/vendor-api.ts";
import { sendTestWebhookDelivery, replayWebhookDelivery, WebhookManagementMutationError, type WebhookManagementMutationRpcClient } from "../../../../../server/mutations/webhook-management.ts";
import { createN8nConnector, rotateN8nConnector, N8nIntegrationMutationError, type N8nIntegrationMutationRpcClient } from "../../../../../server/mutations/n8n-integration.ts";
import { listApiKeysForTenant, listWebhookEndpointsForTenant, type ApiKeyWebhookQueryRpcClient } from "../../../../../server/queries/api-key-webhook.ts";
import { listWebhookDeliveriesForTenant, type WebhookManagementQueryRpcClient } from "../../../../../server/queries/webhook-management.ts";
import { listN8nConnectorsForTenant, type N8nIntegrationQueryRpcClient } from "../../../../../server/queries/n8n-integration.ts";
import type { CreatedApiKey, CreatedWebhookEndpoint } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";
import type { CreatedVendorApiKey } from "../../../../../server/contracts/vendor-api/vendor-api.ts";
import type { WebhookDeliveryRow } from "../../../../../server/contracts/webhook-management/webhook-management.ts";
import type { CreatedN8nConnector } from "../../../../../server/contracts/n8n-integration/n8n-integration.ts";

export interface ApiKeyFormState {
  readonly error: string | null;
  readonly createdKey: CreatedApiKey | null;
}

export interface N8nConnectorFormState {
  readonly error: string | null;
  readonly createdConnector: CreatedN8nConnector | null;
}

export interface VendorApiKeyFormState {
  readonly error: string | null;
  readonly createdKey: CreatedVendorApiKey | null;
}

export interface WebhookEndpointFormState {
  readonly error: string | null;
  readonly createdEndpoint: CreatedWebhookEndpoint | null;
}

export interface WebhookDeliveryFormState {
  readonly error: string | null;
  readonly delivery: WebhookDeliveryRow | null;
}

const OK: ApiKeyFormState = { error: null, createdKey: null };
const NO_ACCESS: ApiKeyFormState = { error: "You don't have access to this organization's admin workspace.", createdKey: null };
const VENDOR_NO_ACCESS: VendorApiKeyFormState = { error: "You don't have access to this organization's admin workspace.", createdKey: null };
const ENDPOINT_OK: WebhookEndpointFormState = { error: null, createdEndpoint: null };
const ENDPOINT_NO_ACCESS: WebhookEndpointFormState = { error: "You don't have access to this organization's admin workspace.", createdEndpoint: null };
const DELIVERY_NO_ACCESS: WebhookDeliveryFormState = { error: "You don't have access to this organization's admin workspace.", delivery: null };
const N8N_NO_ACCESS: N8nConnectorFormState = { error: "You don't have access to this organization's admin workspace.", createdConnector: null };

function toApiKeyWebhookClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): ApiKeyWebhookMutationRpcClient {
  return client as unknown as ApiKeyWebhookMutationRpcClient;
}

function toN8nIntegrationClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): N8nIntegrationMutationRpcClient {
  return client as unknown as N8nIntegrationMutationRpcClient;
}

function toVendorApiClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): VendorApiMutationRpcClient {
  return client as unknown as VendorApiMutationRpcClient;
}

function toWebhookManagementClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): WebhookManagementMutationRpcClient {
  return client as unknown as WebhookManagementMutationRpcClient;
}

/**
 * `SupabaseClient.rpc()` returns a `PostgrestFilterBuilder` (thenable, but not
 * structurally a `Promise`), so it never satisfies a narrow `Promise<{data,error}>`-
 * returning RPC client interface by direct structural assignment -- the same cast
 * this file's own `page.tsx` sibling's `toQueryClient()` already established. Used
 * only for the tenant-ownership pre-checks below (HDN-BLK-013): each `list_*_for_tenant`
 * RPC is `authenticated`-callable and itself scoped to `access.tenant.id`, so a
 * client-supplied id absent from its result never belongs to the caller's own tenant.
 */
function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): ApiKeyWebhookQueryRpcClient & WebhookManagementQueryRpcClient & N8nIntegrationQueryRpcClient {
  return client as unknown as ApiKeyWebhookQueryRpcClient & WebhookManagementQueryRpcClient & N8nIntegrationQueryRpcClient;
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
    const ownedKeys = await listApiKeysForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedKeys.some((key) => key.id === keyId)) {
      throw new ApiKeyWebhookMutationError("api_key_not_found", "api_key_not_found: This key does not belong to your organization.");
    }
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
    const ownedKeys = await listApiKeysForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedKeys.some((key) => key.id === keyId)) {
      throw new ApiKeyWebhookMutationError("api_key_not_found", "api_key_not_found: This key does not belong to your organization.");
    }
    await revokeApiKey(client, { keyId, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not revoke this key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return OK;
}

/** IAE-011: staff-only (Supreme or the tenant's own active tenant_admin) -- a vendor has no login/session and cannot self-service. Rotate/revoke reuse rotateApiKeyAction/revokeApiKeyAction above unchanged -- a vendor key is a plain app.api_keys row, same rotate/revoke authority path. */
export async function createVendorApiKeyAction(tenantSlug: string, _prevState: VendorApiKeyFormState, formData: FormData): Promise<VendorApiKeyFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return VENDOR_NO_ACCESS;

  const vendorMasterRecordId = String(formData.get("vendorMasterRecordId") ?? "").trim();
  if (vendorMasterRecordId.length === 0) return { error: "A vendor id is required.", createdKey: null };

  const name = String(formData.get("name") ?? "").trim();
  if (name.length === 0) return { error: "A key name is required.", createdKey: null };

  const rateLimitRaw = String(formData.get("rateLimitPerMinute") ?? "").trim();
  const rateLimitPerMinute = rateLimitRaw.length > 0 ? Number(rateLimitRaw) : null;
  if (rateLimitPerMinute !== null && (!Number.isFinite(rateLimitPerMinute) || rateLimitPerMinute <= 0)) {
    return { error: "Rate limit per minute must be a positive number, or left blank for unlimited.", createdKey: null };
  }

  const expiresRaw = String(formData.get("expiresAt") ?? "").trim();
  const expiresAt = expiresRaw.length > 0 ? new Date(expiresRaw).toISOString() : null;

  const client = toVendorApiClient(createSupabaseServiceRoleClient());
  let createdKey: CreatedVendorApiKey;
  try {
    createdKey = await createVendorApiKey(client, {
      tenantId: access.tenant.id,
      vendorMasterRecordId,
      name,
      expiresAt,
      rateLimitPerMinute,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorApiMutationError) return { error: `Could not create this vendor key: ${error.message}`, createdKey: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdKey };
}

/** IAE-012: staff-only (Supreme or the tenant's own active tenant_admin). Registers an endpoint against one or more already-seeded event types (comma-separated). Returns the raw signing secret exactly once. */
export async function registerWebhookEndpointAction(tenantSlug: string, _prevState: WebhookEndpointFormState, formData: FormData): Promise<WebhookEndpointFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return ENDPOINT_NO_ACCESS;

  const url = String(formData.get("url") ?? "").trim();
  if (url.length === 0) return { error: "A URL is required.", createdEndpoint: null };

  const eventTypeCodes = parseScopes(formData.get("eventTypeCodes"));
  if (eventTypeCodes.length === 0) return { error: "At least one event type is required (e.g. shipment.status_changed).", createdEndpoint: null };

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  let createdEndpoint: CreatedWebhookEndpoint;
  try {
    createdEndpoint = await registerWebhookEndpoint(client, { tenantId: access.tenant.id, url, eventTypeCodes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not register this endpoint: ${error.message}`, createdEndpoint: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdEndpoint };
}

export async function rotateWebhookSecretAction(tenantSlug: string, endpointId: string, _prevState: WebhookEndpointFormState): Promise<WebhookEndpointFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return ENDPOINT_NO_ACCESS;

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  let createdEndpoint: CreatedWebhookEndpoint;
  try {
    const ownedEndpoints = await listWebhookEndpointsForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedEndpoints.some((endpoint) => endpoint.id === endpointId)) {
      throw new ApiKeyWebhookMutationError("webhook_endpoint_not_found", "webhook_endpoint_not_found: This endpoint does not belong to your organization.");
    }
    createdEndpoint = await rotateWebhookSecret(client, { endpointId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not rotate this endpoint's secret: ${error.message}`, createdEndpoint: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdEndpoint };
}

export async function disableWebhookEndpointAction(tenantSlug: string, endpointId: string, _prevState: WebhookEndpointFormState, formData: FormData): Promise<WebhookEndpointFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return ENDPOINT_NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  try {
    const ownedEndpoints = await listWebhookEndpointsForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedEndpoints.some((endpoint) => endpoint.id === endpointId)) {
      throw new ApiKeyWebhookMutationError("webhook_endpoint_not_found", "webhook_endpoint_not_found: This endpoint does not belong to your organization.");
    }
    await disableWebhookEndpoint(client, { endpointId, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not disable this endpoint: ${error.message}`, createdEndpoint: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return ENDPOINT_OK;
}

export async function reenableWebhookEndpointAction(tenantSlug: string, endpointId: string, _prevState: WebhookEndpointFormState): Promise<WebhookEndpointFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return ENDPOINT_NO_ACCESS;

  const client = toApiKeyWebhookClient(createSupabaseServiceRoleClient());
  try {
    const ownedEndpoints = await listWebhookEndpointsForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedEndpoints.some((endpoint) => endpoint.id === endpointId)) {
      throw new ApiKeyWebhookMutationError("webhook_endpoint_not_found", "webhook_endpoint_not_found: This endpoint does not belong to your organization.");
    }
    await reenableWebhookEndpoint(client, { endpointId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ApiKeyWebhookMutationError) return { error: `Could not re-enable this endpoint: ${error.message}`, createdEndpoint: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return ENDPOINT_OK;
}

/** IAE-012: scoped to exactly ONE named endpoint -- enqueues a real app.jobs job so this genuinely exercises the real delivery worker end to end. */
export async function sendTestWebhookDeliveryAction(tenantSlug: string, endpointId: string, _prevState: WebhookDeliveryFormState): Promise<WebhookDeliveryFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return DELIVERY_NO_ACCESS;

  const client = toWebhookManagementClient(createSupabaseServiceRoleClient());
  let delivery: WebhookDeliveryRow;
  try {
    delivery = await sendTestWebhookDelivery(client, { endpointId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof WebhookManagementMutationError) return { error: `Could not send a test delivery: ${error.message}`, delivery: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, delivery };
}

/** IAE-012: valid ONLY for a dead_letter delivery -- enqueues a fresh app.jobs job. */
export async function replayWebhookDeliveryAction(tenantSlug: string, deliveryId: string, _prevState: WebhookDeliveryFormState): Promise<WebhookDeliveryFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return DELIVERY_NO_ACCESS;

  const client = toWebhookManagementClient(createSupabaseServiceRoleClient());
  let delivery: WebhookDeliveryRow;
  try {
    const ownedDeliveries = await listWebhookDeliveriesForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, limit: 200 });
    if (!ownedDeliveries.some((candidate) => candidate.id === deliveryId)) {
      throw new WebhookManagementMutationError("webhook_delivery_not_found", "webhook_delivery_not_found: This delivery does not belong to your organization.");
    }
    delivery = await replayWebhookDelivery(client, { deliveryId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof WebhookManagementMutationError) return { error: `Could not replay this delivery: ${error.message}`, delivery: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, delivery };
}

/** IAE-013: staff-only. Every requested scope must be on the n8n safe-action allowlist. Revoke reuses revokeApiKeyAction above unchanged -- app.revoke_n8n_connector delegates entirely to app.revoke_api_key. */
export async function createN8nConnectorAction(tenantSlug: string, _prevState: N8nConnectorFormState, formData: FormData): Promise<N8nConnectorFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return N8N_NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  if (name.length === 0) return { error: "A connector name is required.", createdConnector: null };

  const scopes = parseScopes(formData.get("scopes"));
  if (scopes.length === 0) return { error: "At least one allowlisted scope is required (e.g. OPS:View).", createdConnector: null };

  const webhookEndpointIdRaw = String(formData.get("webhookEndpointId") ?? "").trim();
  const webhookEndpointId = webhookEndpointIdRaw.length > 0 ? webhookEndpointIdRaw : null;

  const rateLimitRaw = String(formData.get("rateLimitPerMinute") ?? "").trim();
  const rateLimitPerMinute = rateLimitRaw.length > 0 ? Number(rateLimitRaw) : null;
  if (rateLimitPerMinute !== null && (!Number.isFinite(rateLimitPerMinute) || rateLimitPerMinute <= 0)) {
    return { error: "Rate limit per minute must be a positive number, or left blank for unlimited.", createdConnector: null };
  }

  const client = toN8nIntegrationClient(createSupabaseServiceRoleClient());
  let createdConnector: CreatedN8nConnector;
  try {
    createdConnector = await createN8nConnector(client, {
      tenantId: access.tenant.id,
      name,
      scopes,
      webhookEndpointId,
      rateLimitPerMinute,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof N8nIntegrationMutationError) return { error: `Could not create this n8n connector: ${error.message}`, createdConnector: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdConnector };
}

/**
 * Tier C Batch 3 fix: rotating a connector's underlying key mints a brand-new
 * app.api_keys row (unlike revoke, which updates the SAME row in place) --
 * reusing the generic rotateApiKeyAction here would silently orphan
 * app.n8n_connectors.api_key_id, leaving the console showing a stale/wrong
 * key status while an unlabeled successor key stayed live. This action calls
 * app.rotate_n8n_connector instead, which re-points the linkage.
 */
export async function rotateN8nConnectorAction(tenantSlug: string, connectorId: string, _prevState: N8nConnectorFormState, formData: FormData): Promise<N8nConnectorFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return N8N_NO_ACCESS;

  const overlapRaw = String(formData.get("overlapMinutes") ?? "0").trim();
  const overlapMinutes = Number(overlapRaw);
  if (!Number.isFinite(overlapMinutes) || overlapMinutes < 0 || overlapMinutes > 10080) {
    return { error: "Overlap window must be between 0 (immediate revoke) and 10080 minutes (7 days).", createdConnector: null };
  }

  const client = toN8nIntegrationClient(createSupabaseServiceRoleClient());
  let rotatedConnector: CreatedN8nConnector;
  try {
    const ownedConnectors = await listN8nConnectorsForTenant(toQueryClient(await createSupabaseServerClient()), { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    if (!ownedConnectors.some((connector) => connector.connectorId === connectorId)) {
      throw new N8nIntegrationMutationError("n8n_connector_not_found", "n8n_connector_not_found: This connector does not belong to your organization.");
    }
    rotatedConnector = await rotateN8nConnector(client, { connectorId, overlapMinutes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof N8nIntegrationMutationError) return { error: `Could not rotate this connector: ${error.message}`, createdConnector: null };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/api-keys`);
  return { error: null, createdConnector: rotatedConnector };
}
