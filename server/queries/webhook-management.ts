/**
 * Webhook Management query entry points (IAE-012, Prompt 340). Thin, typed
 * wrappers around app.list_webhook_deliveries_for_tenant /
 * app.get_webhook_delivery_dispatch_info
 * (supabase/migrations/20260804040000_create_intelligence_webhook_management.sql).
 */

import { ListWebhookDeliveriesForTenantInputSchema, parseWebhookDelivery, parseWebhookDeliveryDispatchInfo, type ListWebhookDeliveriesForTenantInput, type WebhookDelivery, type WebhookDeliveryDispatchInfo } from "../contracts/webhook-management/webhook-management.ts";

export interface WebhookManagementQueryRpcClient {
  rpc(fn: "list_webhook_deliveries_for_tenant" | "get_webhook_delivery_dispatch_info", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class WebhookManagementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WebhookManagementQueryError";
  }
}

/** Authority: Supreme or the tenant's own active tenant_admin (app.check_api_webhook_admin_authority). */
export async function listWebhookDeliveriesForTenant(client: WebhookManagementQueryRpcClient, input: ListWebhookDeliveriesForTenantInput): Promise<WebhookDelivery[]> {
  const parsedInput = ListWebhookDeliveriesForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_webhook_deliveries_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_status: parsedInput.status,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new WebhookManagementQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWebhookDelivery);
}

/** The real delivery worker's own minimal read -- never selects the raw signing secret; the worker calls app.compute_webhook_signature() instead. No actor-authority check (service_role-only, worker-context caller, never a live authenticated session). */
export async function getWebhookDeliveryDispatchInfo(client: WebhookManagementQueryRpcClient, deliveryId: string): Promise<WebhookDeliveryDispatchInfo | null> {
  const { data, error } = await client.rpc("get_webhook_delivery_dispatch_info", { p_delivery_id: deliveryId });
  if (error) {
    throw new WebhookManagementQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseWebhookDeliveryDispatchInfo(row as Record<string, unknown>);
}
