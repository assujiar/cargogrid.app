/**
 * Warehouse Billing Events read queries (ATW-022, CG-S10-ATW-022). Thin, typed
 * wrappers around app.get_warehouse_billing_event/app.list_warehouse_billing_events/
 * app.get_warehouse_billing_handoff/app.list_warehouse_billing_handoffs/
 * app.list_warehouse_billing_rate_components
 * (supabase/migrations/20260730300000_create_advanced_tms_warehouse_billing_events.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWarehouseBillingEvent,
  parseWarehouseBillingHandoff,
  parseWarehouseBillingRateComponent,
  type WarehouseBillingEvent,
  type WarehouseBillingHandoff,
  type WarehouseBillingRateComponent,
  type WarehouseBillingActivityType,
  type WarehouseBillingEventStatus,
} from "../contracts/warehouse-billing/warehouse-billing.ts";

export type WarehouseBillingQueryClient = Pick<SupabaseClient, "rpc">;

export class WarehouseBillingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WarehouseBillingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-gated (OPS:View) + record/owner-scoped. */
export async function getWarehouseBillingEvent(client: WarehouseBillingQueryClient, eventId: string, actorAuthUserId: string): Promise<WarehouseBillingEvent> {
  const { data, error } = await client.rpc("get_warehouse_billing_event", { p_event_id: eventId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WarehouseBillingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseBillingQueryError("get_warehouse_billing_event returned no row");
  }
  return parseWarehouseBillingEvent(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record/owner-scoped. */
export async function listWarehouseBillingEvents(
  client: WarehouseBillingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: {
    warehouseId?: string | null;
    ownerAccountId?: string | null;
    activityType?: WarehouseBillingActivityType | null;
    statusFilter?: WarehouseBillingEventStatus | null;
    limit?: number;
  },
): Promise<WarehouseBillingEvent[]> {
  const { data, error } = await client.rpc("list_warehouse_billing_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_activity_type: options?.activityType ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WarehouseBillingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseBillingEvent);
}

/** Single-row read by id, RBAC-gated (OPS:View) + record/owner-scoped (via the parent event). */
export async function getWarehouseBillingHandoff(client: WarehouseBillingQueryClient, handoffId: string, actorAuthUserId: string): Promise<WarehouseBillingHandoff> {
  const { data, error } = await client.rpc("get_warehouse_billing_handoff", { p_handoff_id: handoffId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WarehouseBillingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseBillingQueryError("get_warehouse_billing_handoff returned no row");
  }
  return parseWarehouseBillingHandoff(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record/owner-scoped via the parent event. */
export async function listWarehouseBillingHandoffs(
  client: WarehouseBillingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { billingEventId?: string | null; limit?: number },
): Promise<WarehouseBillingHandoff[]> {
  const { data, error } = await client.rpc("list_warehouse_billing_handoffs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_billing_event_id: options?.billingEventId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WarehouseBillingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseBillingHandoff);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide, COM:View-gated (mirrors app.customer_contract_price_components' own tenant-wide read posture). */
export async function listWarehouseBillingRateComponents(
  client: WarehouseBillingQueryClient,
  contractId: string,
  actorAuthUserId: string,
  options?: { activityType?: WarehouseBillingActivityType | null; limit?: number },
): Promise<WarehouseBillingRateComponent[]> {
  const { data, error } = await client.rpc("list_warehouse_billing_rate_components", {
    p_contract_id: contractId,
    p_actor_auth_user_id: actorAuthUserId,
    p_activity_type: options?.activityType ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WarehouseBillingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseBillingRateComponent);
}
