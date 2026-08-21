/**
 * n8n Integration contract (IAE-013, Prompt 341). Mirrors
 * supabase/migrations/20260804050000_create_intelligence_n8n_integration.sql's
 * app.n8n_action_allowlist / app.n8n_connectors and the
 * app.create_n8n_connector / app.revoke_n8n_connector /
 * app.list_n8n_connectors_for_tenant / app.list_n8n_action_allowlist RPCs.
 * n8n calls the SAME REST /v1 surface and the SAME webhook delivery
 * mechanism every other API/webhook consumer already uses -- this contract
 * covers only the governance/linking layer this checkpoint adds.
 */

import { z } from "zod";

export const N8nAllowlistedActionSchema = z.object({
  scope: z.string(),
  description: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type N8nAllowlistedAction = z.infer<typeof N8nAllowlistedActionSchema>;

export function parseN8nAllowlistedAction(row: Record<string, unknown>): N8nAllowlistedAction {
  return N8nAllowlistedActionSchema.parse({
    scope: row.scope,
    description: row.description,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

export const N8nConnectorSchema = z.object({
  connectorId: z.string().uuid(),
  apiKeyId: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  keyPrefix: z.string(),
  scopes: z.array(z.string()),
  status: z.enum(["active", "revoked", "expired"]),
  rateLimitPerMinute: z.number().int().positive().nullable(),
  lastUsedAt: z.string().nullable().optional(),
  webhookEndpointId: z.string().uuid().nullable(),
  webhookEndpointUrl: z.string().nullable().optional(),
  webhookEndpointStatus: z.enum(["active", "disabled"]).nullable().optional(),
  createdAt: z.string(),
  updatedAt: z.string().optional(),
});
export type N8nConnector = z.infer<typeof N8nConnectorSchema>;

export function parseN8nConnector(row: Record<string, unknown>): N8nConnector {
  return N8nConnectorSchema.parse({
    connectorId: row.connector_id,
    apiKeyId: row.api_key_id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    lastUsedAt: row.last_used_at,
    webhookEndpointId: row.webhook_endpoint_id,
    webhookEndpointUrl: row.webhook_endpoint_url,
    webhookEndpointStatus: row.webhook_endpoint_status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreatedN8nConnectorSchema = N8nConnectorSchema.omit({ lastUsedAt: true, webhookEndpointUrl: true, webhookEndpointStatus: true, updatedAt: true }).extend({ rawKey: z.string() });
export type CreatedN8nConnector = z.infer<typeof CreatedN8nConnectorSchema>;

export function parseCreatedN8nConnector(row: Record<string, unknown>): CreatedN8nConnector {
  return CreatedN8nConnectorSchema.parse({
    connectorId: row.connector_id,
    apiKeyId: row.api_key_id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    webhookEndpointId: row.webhook_endpoint_id,
    createdAt: row.created_at,
    rawKey: row.raw_key,
  });
}

export const CreateN8nConnectorInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  scopes: z.array(z.string().min(1)).min(1),
  webhookEndpointId: z.string().uuid().nullable().default(null),
  rateLimitPerMinute: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateN8nConnectorInput = z.input<typeof CreateN8nConnectorInputSchema>;

export const RevokeN8nConnectorInputSchema = z.object({
  connectorId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeN8nConnectorInput = z.input<typeof RevokeN8nConnectorInputSchema>;

/**
 * Tier C Batch 3 fix: unlike revoke (which updates the SAME app.api_keys row
 * in place, so the connector's own fixed api_key_id FK never goes stale),
 * rotate mints a brand-new app.api_keys row -- app.rotate_n8n_connector
 * composes app.rotate_api_key AND re-points app.n8n_connectors.api_key_id at
 * the new row, so the console's own generic RotateApiKeyForm must never be
 * reused here (it would silently orphan the connector's own governance
 * linkage).
 */
export const RotateN8nConnectorInputSchema = z.object({
  connectorId: z.string().uuid(),
  overlapMinutes: z.number().int().min(0).max(10080),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RotateN8nConnectorInput = z.input<typeof RotateN8nConnectorInputSchema>;

export const ListN8nConnectorsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListN8nConnectorsForTenantInput = z.input<typeof ListN8nConnectorsForTenantInputSchema>;
