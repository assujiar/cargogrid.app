/**
 * Webhook Management mutation entry points (IAE-012, Prompt 340). Thin, typed
 * wrappers around app.send_test_webhook_delivery / app.replay_webhook_delivery
 * (supabase/migrations/20260804040000_create_intelligence_webhook_management.sql).
 * Endpoint CRUD (register/rotate/disable/reenable) reuses
 * ../mutations/api-key-webhook.ts's own registerWebhookEndpoint/
 * rotateWebhookSecret/disableWebhookEndpoint/reenableWebhookEndpoint directly
 * -- not re-declared here.
 */

import { SendTestWebhookDeliveryInputSchema, parseWebhookDeliveryRow, ReplayWebhookDeliveryInputSchema, type SendTestWebhookDeliveryInput, type ReplayWebhookDeliveryInput, type WebhookDeliveryRow } from "../contracts/webhook-management/webhook-management.ts";

export interface WebhookManagementMutationRpcClient {
  rpc(fn: "send_test_webhook_delivery" | "replay_webhook_delivery", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const WEBHOOK_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES = [
  "webhook_endpoint_not_found",
  "insufficient_authority",
  "webhook_delivery_not_found",
  "webhook_delivery_not_replayable",
] as const;
type KnownWebhookManagementMutationErrorCode = (typeof WEBHOOK_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type WebhookManagementMutationErrorCode = KnownWebhookManagementMutationErrorCode | "mutation_failed" | "invalid_response";

export class WebhookManagementMutationError extends Error {
  readonly code: WebhookManagementMutationErrorCode;

  constructor(code: WebhookManagementMutationErrorCode, message: string) {
    super(message);
    this.name = "WebhookManagementMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WebhookManagementMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WEBHOOK_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWebhookManagementMutationErrorCode)
    : "mutation_failed";
}

function parseDeliveryRow(data: unknown, rpcName: string): WebhookDeliveryRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new WebhookManagementMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWebhookDeliveryRow(row as Record<string, unknown>);
}

/** Authority: Supreme or the tenant's own active tenant_admin. Scoped to exactly ONE named endpoint -- never the subscription-fanout app.queue_webhook_delivery itself uses. */
export async function sendTestWebhookDelivery(client: WebhookManagementMutationRpcClient, input: SendTestWebhookDeliveryInput): Promise<WebhookDeliveryRow> {
  const parsedInput = SendTestWebhookDeliveryInputSchema.parse(input);
  const { data, error } = await client.rpc("send_test_webhook_delivery", {
    p_endpoint_id: parsedInput.endpointId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WebhookManagementMutationError(classifyError(error.message), error.message);
  }
  return parseDeliveryRow(data, "send_test_webhook_delivery");
}

/** Authority: Supreme or the tenant's own active tenant_admin. Valid ONLY from status=dead_letter. */
export async function replayWebhookDelivery(client: WebhookManagementMutationRpcClient, input: ReplayWebhookDeliveryInput): Promise<WebhookDeliveryRow> {
  const parsedInput = ReplayWebhookDeliveryInputSchema.parse(input);
  const { data, error } = await client.rpc("replay_webhook_delivery", {
    p_delivery_id: parsedInput.deliveryId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WebhookManagementMutationError(classifyError(error.message), error.message);
  }
  return parseDeliveryRow(data, "replay_webhook_delivery");
}
