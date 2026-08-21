/**
 * Integration Hub contract (IAE-008, Prompt 336). Mirrors
 * supabase/migrations/20260803020000_create_intelligence_integration_hub.sql's
 * app.integration_adapters/app.integration_connections/app.integration_health_checks
 * shape. app.integration_connection_credentials is deliberately NOT
 * represented here at all -- it has zero authenticated/anon grant and is
 * never read by any query in this service layer (design decision 3 of the
 * migration's own header).
 */

import { z } from "zod";

export const INTEGRATION_CONNECTION_ENVIRONMENTS = ["sandbox", "production"] as const;
export const IntegrationConnectionEnvironmentSchema = z.enum(INTEGRATION_CONNECTION_ENVIRONMENTS);
export type IntegrationConnectionEnvironment = z.infer<typeof IntegrationConnectionEnvironmentSchema>;

export const INTEGRATION_CONNECTION_STATUSES = ["active", "disabled", "testing"] as const;
export const IntegrationConnectionStatusSchema = z.enum(INTEGRATION_CONNECTION_STATUSES);
export type IntegrationConnectionStatus = z.infer<typeof IntegrationConnectionStatusSchema>;

export const INTEGRATION_HEALTH_STATUSES = ["healthy", "unhealthy"] as const;
export const IntegrationHealthStatusSchema = z.enum(INTEGRATION_HEALTH_STATUSES);
export type IntegrationHealthStatus = z.infer<typeof IntegrationHealthStatusSchema>;

export const IntegrationAdapterSchema = z.object({
  code: z.string(),
  name: z.string(),
  category: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type IntegrationAdapter = z.infer<typeof IntegrationAdapterSchema>;

export function parseIntegrationAdapter(row: Record<string, unknown>): IntegrationAdapter {
  return IntegrationAdapterSchema.parse({
    code: row.code,
    name: row.name,
    category: row.category,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

export const IntegrationConnectionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  adapterCode: z.string(),
  name: z.string(),
  environment: IntegrationConnectionEnvironmentSchema,
  status: IntegrationConnectionStatusSchema,
  ownerTeam: z.string().nullable(),
  ownerEmail: z.string().nullable(),
  runbookUrl: z.string().nullable(),
  config: z.record(z.string(), z.unknown()),
  consecutiveFailureCount: z.number().int().nonnegative(),
  lastHealthCheckAt: z.string().nullable(),
  lastHealthStatus: IntegrationHealthStatusSchema.nullable(),
  autoDisabledAt: z.string().nullable(),
  disabledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type IntegrationConnection = z.infer<typeof IntegrationConnectionSchema>;

export function parseIntegrationConnection(row: Record<string, unknown>): IntegrationConnection {
  return IntegrationConnectionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    name: row.name,
    environment: row.environment,
    status: row.status,
    ownerTeam: row.owner_team,
    ownerEmail: row.owner_email,
    runbookUrl: row.runbook_url,
    config: row.config ?? {},
    consecutiveFailureCount: row.consecutive_failure_count,
    lastHealthCheckAt: row.last_health_check_at,
    lastHealthStatus: row.last_health_status,
    autoDisabledAt: row.auto_disabled_at,
    disabledReason: row.disabled_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const IntegrationHealthCheckSchema = z.object({
  id: z.string().uuid(),
  connectionId: z.string().uuid(),
  status: IntegrationHealthStatusSchema,
  detail: z.string().nullable(),
  checkedBy: z.string().nullable(),
  checkedAt: z.string(),
});
export type IntegrationHealthCheck = z.infer<typeof IntegrationHealthCheckSchema>;

export function parseIntegrationHealthCheck(row: Record<string, unknown>): IntegrationHealthCheck {
  return IntegrationHealthCheckSchema.parse({
    id: row.id,
    connectionId: row.connection_id,
    status: row.status,
    detail: row.detail,
    checkedBy: row.checked_by,
    checkedAt: row.checked_at,
  });
}

export const CreateIntegrationConnectionInputSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: z.string().min(1),
  name: z.string().min(1),
  environment: IntegrationConnectionEnvironmentSchema.default("production"),
  ownerTeam: z.string().nullable().default(null),
  ownerEmail: z.string().nullable().default(null),
  runbookUrl: z.string().nullable().default(null),
  config: z.record(z.string(), z.unknown()).default({}),
  credentialValue: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateIntegrationConnectionInput = z.input<typeof CreateIntegrationConnectionInputSchema>;

export const UpdateIntegrationConnectionConfigInputSchema = z.object({
  connectionId: z.string().uuid(),
  config: z.record(z.string(), z.unknown()).default({}),
  ownerTeam: z.string().nullable().default(null),
  ownerEmail: z.string().nullable().default(null),
  runbookUrl: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateIntegrationConnectionConfigInput = z.input<typeof UpdateIntegrationConnectionConfigInputSchema>;

export const RotateIntegrationConnectionCredentialInputSchema = z.object({
  connectionId: z.string().uuid(),
  newCredentialValue: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RotateIntegrationConnectionCredentialInput = z.input<typeof RotateIntegrationConnectionCredentialInputSchema>;

export const SetIntegrationConnectionStatusInputSchema = z.object({
  connectionId: z.string().uuid(),
  status: IntegrationConnectionStatusSchema,
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetIntegrationConnectionStatusInput = z.input<typeof SetIntegrationConnectionStatusInputSchema>;

export const RecordIntegrationHealthCheckInputSchema = z.object({
  connectionId: z.string().uuid(),
  status: IntegrationHealthStatusSchema,
  detail: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordIntegrationHealthCheckInput = z.input<typeof RecordIntegrationHealthCheckInputSchema>;
