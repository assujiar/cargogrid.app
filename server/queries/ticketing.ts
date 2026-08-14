/**
 * Ticketing read queries (HRT-286, CG-S12-HRT-014). Thin, typed wrappers
 * around every read RPC in
 * supabase/migrations/20260731060000_create_ticketing_internal.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTicketQueueRow,
  parseTicketCategoryRow,
  parseTicketQueueMemberRow,
  parseTicketDetail,
  parseTicketListRow,
  parseMyTicketListRow,
  parseTicketMessageRow,
  parseTicketWatcherRow,
  parseTicketEventRow,
  parseTicketExportRow,
  type TicketQueueRow,
  type TicketCategoryRow,
  type TicketQueueMemberRow,
  type TicketDetail,
  type TicketListRow,
  type MyTicketListRow,
  type TicketMessageRow,
  type TicketWatcherRow,
  type TicketEventRow,
  type TicketExportRow,
  type TicketStatus,
  type TicketPriority,
} from "../contracts/ticketing/ticketing.ts";

export type TicketQueryClient = Pick<SupabaseClient, "rpc">;

export class TicketQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TicketQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listTicketQueues(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<TicketQueueRow[]> {
  const { data, error } = await client.rpc("list_ticket_queues", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketQueueRow);
}

export async function listTicketCategories(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<TicketCategoryRow[]> {
  const { data, error } = await client.rpc("list_ticket_categories", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketCategoryRow);
}

export async function listTicketQueueMembers(client: TicketQueryClient, queueId: string, actorAuthUserId: string): Promise<TicketQueueMemberRow[]> {
  const { data, error } = await client.rpc("list_ticket_queue_members", { p_queue_id: queueId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketQueueMemberRow);
}

export async function getTicket(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketDetail | null> {
  const { data, error } = await client.rpc("get_ticket", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketDetail(row) : null;
}

export interface ListTicketsOptions {
  readonly status?: TicketStatus | null;
  readonly queueId?: string | null;
  readonly categoryId?: string | null;
  readonly priority?: TicketPriority | null;
  readonly assigneeEmployeeId?: string | null;
  readonly limit?: number;
  readonly afterId?: string | null;
}

export async function listTickets(client: TicketQueryClient, tenantId: string, actorAuthUserId: string, options?: ListTicketsOptions): Promise<TicketListRow[]> {
  const { data, error } = await client.rpc("list_tickets", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_queue_id: options?.queueId ?? null,
    p_category_id: options?.categoryId ?? null,
    p_priority: options?.priority ?? null,
    p_assignee_employee_id: options?.assigneeEmployeeId ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketListRow);
}

export async function listMyTickets(
  client: TicketQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { status?: TicketStatus | null; limit?: number; afterId?: string | null },
): Promise<MyTicketListRow[]> {
  const { data, error } = await client.rpc("list_my_tickets", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseMyTicketListRow);
}

export async function listTicketMessages(
  client: TicketQueryClient,
  ticketId: string,
  actorAuthUserId: string,
  options?: { limit?: number; afterId?: string | null },
): Promise<TicketMessageRow[]> {
  const { data, error } = await client.rpc("list_ticket_messages", {
    p_ticket_id: ticketId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketMessageRow);
}

export async function listTicketWatchers(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketWatcherRow[]> {
  const { data, error } = await client.rpc("list_ticket_watchers", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketWatcherRow);
}

export async function listTicketEvents(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketEventRow[]> {
  const { data, error } = await client.rpc("list_ticket_events", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEventRow);
}

export async function exportTickets(client: TicketQueryClient, tenantId: string, actorAuthUserId: string, fromDate: string, toDate: string): Promise<TicketExportRow[]> {
  const { data, error } = await client.rpc("export_tickets", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_from_date: fromDate, p_to_date: toDate });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketExportRow);
}
