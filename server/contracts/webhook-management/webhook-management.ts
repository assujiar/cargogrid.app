/**
 * Webhook Management contract (IAE-012, Prompt 340). Mirrors
 * supabase/migrations/20260804040000_create_intelligence_webhook_management.sql's
 * app.list_webhook_deliveries_for_tenant / app.send_test_webhook_delivery /
 * app.replay_webhook_delivery / app.get_webhook_delivery_dispatch_info RPCs.
 * Endpoint CRUD (register/rotate/disable/reenable/list) reuses
 * ../api-key-webhook/api-key-webhook.ts's own WebhookEndpoint/CreatedWebhookEndpoint
 * and mutation wrappers directly -- not re-declared here.
 */

import { z } from "zod";

export const WEBHOOK_DELIVERY_STATUSES = ["pending", "delivered", "dead_letter"] as const;
export const WebhookDeliveryStatusSchema = z.enum(WEBHOOK_DELIVERY_STATUSES);
export type WebhookDeliveryStatus = z.infer<typeof WebhookDeliveryStatusSchema>;

export const WebhookDeliverySchema = z.object({
  id: z.string().uuid(),
  webhookEndpointId: z.string().uuid(),
  endpointUrl: z.string(),
  eventTypeCode: z.string(),
  status: WebhookDeliveryStatusSchema,
  attempts: z.number().int().nonnegative(),
  maxAttempts: z.number().int().positive(),
  nextAttemptAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WebhookDelivery = z.infer<typeof WebhookDeliverySchema>;

export function parseWebhookDelivery(row: Record<string, unknown>): WebhookDelivery {
  return WebhookDeliverySchema.parse({
    id: row.id,
    webhookEndpointId: row.webhook_endpoint_id,
    endpointUrl: row.endpoint_url,
    eventTypeCode: row.event_type_code,
    status: row.status,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    nextAttemptAt: row.next_attempt_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** The raw app.webhook_deliveries row shape -- no endpoint_url (that's a join-time addition list_webhook_deliveries_for_tenant makes for display; app.send_test_webhook_delivery/app.replay_webhook_delivery return the bare table row). */
export const WebhookDeliveryRowSchema = z.object({
  id: z.string().uuid(),
  webhookEndpointId: z.string().uuid(),
  eventTypeCode: z.string(),
  status: WebhookDeliveryStatusSchema,
  attempts: z.number().int().nonnegative(),
  maxAttempts: z.number().int().positive(),
  nextAttemptAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WebhookDeliveryRow = z.infer<typeof WebhookDeliveryRowSchema>;

export function parseWebhookDeliveryRow(row: Record<string, unknown>): WebhookDeliveryRow {
  return WebhookDeliveryRowSchema.parse({
    id: row.id,
    webhookEndpointId: row.webhook_endpoint_id,
    eventTypeCode: row.event_type_code,
    status: row.status,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    nextAttemptAt: row.next_attempt_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ListWebhookDeliveriesForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  status: WebhookDeliveryStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListWebhookDeliveriesForTenantInput = z.input<typeof ListWebhookDeliveriesForTenantInputSchema>;

export const SendTestWebhookDeliveryInputSchema = z.object({
  endpointId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SendTestWebhookDeliveryInput = z.input<typeof SendTestWebhookDeliveryInputSchema>;

export const ReplayWebhookDeliveryInputSchema = z.object({
  deliveryId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReplayWebhookDeliveryInput = z.input<typeof ReplayWebhookDeliveryInputSchema>;

/** Maps app.get_webhook_delivery_dispatch_info()'s own return row -- the real delivery worker's own minimal read, never the raw signing secret. */
export const WebhookDeliveryDispatchInfoSchema = z.object({
  deliveryId: z.string().uuid(),
  tenantId: z.string().uuid(),
  status: WebhookDeliveryStatusSchema,
  eventTypeCode: z.string(),
  payload: z.record(z.string(), z.unknown()),
  webhookEndpointId: z.string().uuid(),
  endpointUrl: z.string(),
  endpointStatus: z.enum(["active", "disabled"]),
});
export type WebhookDeliveryDispatchInfo = z.infer<typeof WebhookDeliveryDispatchInfoSchema>;

export function parseWebhookDeliveryDispatchInfo(row: Record<string, unknown>): WebhookDeliveryDispatchInfo {
  return WebhookDeliveryDispatchInfoSchema.parse({
    deliveryId: row.delivery_id,
    tenantId: row.tenant_id,
    status: row.status,
    eventTypeCode: row.event_type_code,
    payload: row.payload,
    webhookEndpointId: row.webhook_endpoint_id,
    endpointUrl: row.endpoint_url,
    endpointStatus: row.endpoint_status,
  });
}
